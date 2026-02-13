# Claude Code Adapter Design

## Goal

Build a working Claude Code adapter for Thunderdome so we can run the first real benchmark. Also build an Aider adapter (~10 lines of bash) to validate the adapter contract works for simple CLI tools.

## Architecture

```
thunderdome run --orchestrator claude-code --task bench-time-tracker
  │
  ├─ Clone bench-time-tracker at tag v1
  ├─ Start LiteLLM gateway on host (:4000)
  ├─ Launch Docker container (node:20-bookworm + Claude Code)
  │    │
  │    ├─ /adapter.sh starts /opt/ws-server (Go binary) on :9876
  │    ├─ /adapter.sh launches: claude --sdk-url ws://localhost:9876
  │    ├─ ws-server sends task prompt, auto-approves tools
  │    ├─ Claude Code works in /workspace, API calls → LiteLLM via ANTHROPIC_BASE_URL
  │    ├─ Claude Code sends "result" message → ws-server writes metrics → exits
  │    └─ adapter.sh exits with Claude Code's exit code
  │
  ├─ Harness captures git diff of /workspace
  ├─ Harness runs validation (tests + lint + rubric)
  └─ Harness writes results/meta.json
```

## Components

### 1. WebSocket Server (`adapters/claude-code/ws-server.go`)

A static Go binary (~150 lines) that implements the Claude Code SDK protocol as a simple state machine.

**States:**

```
WAITING ──connect──► INITIALIZING ──init done──► RUNNING ──result──► DONE
```

- **WAITING:** Listen on `localhost:PORT`. Accept one WebSocket connection.
- **INITIALIZING:** Receive `control_request` with subtype `initialize`. Respond with `control_response`. Send `user` message containing the task prompt. Transition to RUNNING.
- **RUNNING:** Loop on incoming messages:
  - `control_request` subtype `can_use_tool` → respond `{allowed: true}`
  - `assistant` messages → log to stderr, continue
  - `result` message → extract token usage, transition to DONE
- **DONE:** Write metrics to sidecar JSON. Return exit code.

**Protocol messages (NDJSON over WebSocket):**

```jsonc
// Server → Claude Code: task prompt
{"type": "user", "content": [{"type": "text", "text": "...task description..."}]}

// Claude Code → Server: initialize handshake
{"type": "control_request", "subtype": "initialize", "supportedApiVersions": [...]}

// Server → Claude Code: initialize response
{"type": "control_response", "subtype": "initialize", "apiVersion": "1", "permissionMode": "default"}

// Claude Code → Server: tool permission request
{"type": "control_request", "subtype": "can_use_tool", "toolName": "Bash", "input": {...}}

// Server → Claude Code: approve tool
{"type": "control_response", "subtype": "can_use_tool", "allowed": true}

// Claude Code → Server: task complete
{"type": "result", "result": "...", "usage": {"input_tokens": N, "output_tokens": N}}
```

**Timeouts:** 5-minute read deadline per message. If Claude Code stops sending messages for 5 minutes, the server assumes it is stuck, logs the timeout, and exits with code 1. The Docker-level timeout (set by the harness) provides the outer bound.

**Metrics sidecar:** On completion, the server writes `/workspace/.thunderdome-metrics.json`:

```json
{
  "input_tokens": 12000,
  "output_tokens": 4500,
  "cache_read_tokens": 0,
  "cache_creation_tokens": 0,
  "turns": 15,
  "tools_used": ["Bash", "Read", "Write", "Edit", "Grep"]
}
```

The harness can read this file from the workspace after the container exits.

**Build:** `CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -o ws-server ./adapters/claude-code/`

### 2. Adapter Script (`adapters/claude-code/adapter.sh`)

```bash
#!/bin/bash
set -e

# Validate inputs
[[ -f "$TASK_DESCRIPTION" ]] || { echo "Task file not found: $TASK_DESCRIPTION" >&2; exit 2; }

# Start WebSocket server in background
/opt/ws-server \
  --port 9876 \
  --task-file "$TASK_DESCRIPTION" \
  --metrics-file /workspace/.thunderdome-metrics.json \
  --debug &
SERVER_PID=$!

# Clean up server on any exit
trap 'kill $SERVER_PID 2>/dev/null; wait $SERVER_PID 2>/dev/null' EXIT INT TERM

# Wait for server to bind (poll port, max 3 seconds)
for i in $(seq 1 30); do
  if nc -z localhost 9876 2>/dev/null; then break; fi
  sleep 0.1
done

# Launch Claude Code
cd "$TASK_DIR"
export ANTHROPIC_BASE_URL="$PROXY_URL"
claude --sdk-url ws://localhost:9876

# Capture and propagate exit code
exit $?
```

**Fixes from validation review:**
- `trap` ensures server cleanup on any exit path (fixes zombie process leak)
- Port polling with `nc -z` replaces `sleep 1` (fixes race condition)
- Input validation before launch (fails fast on missing task file)
- Exit code preserved through trap (fixes exit code masking)

### 3. Aider Adapter (`adapters/aider/adapter.sh`)

```bash
#!/bin/bash
set -e

[[ -f "$TASK_DESCRIPTION" ]] || { echo "Task file not found: $TASK_DESCRIPTION" >&2; exit 2; }

cd "$TASK_DIR"

export ANTHROPIC_BASE_URL="$PROXY_URL"

aider \
  --yes-always \
  --no-auto-commits \
  --message-file "$TASK_DESCRIPTION" \
  --model anthropic/claude-sonnet-4-5

exit $?
```

Uses `--no-auto-commits` instead of `--no-git` so Aider can still read git history but won't make commits that interfere with the harness's diff capture.

Token tracking comes from LiteLLM proxy logs, not from Aider itself. Both adapters route through the same gateway, so cost tracking is uniform.

### 4. Dockerfiles

**`docker/claude-code/Dockerfile`:**

```dockerfile
FROM node:20-bookworm

# Pin Claude Code version for reproducibility
RUN npm install -g @anthropic-ai/claude-code@1.0.0

# Git config (Claude Code needs this for tool use)
RUN git config --global user.name "Thunderdome" && \
    git config --global user.email "bench@localhost"

# Install netcat for port polling in adapter script
RUN apt-get update && apt-get install -y netcat-openbsd && rm -rf /var/lib/apt/lists/*

# Copy pre-built Go WebSocket server (static binary)
COPY ws-server /opt/ws-server
RUN chmod +x /opt/ws-server

WORKDIR /workspace
CMD ["/bin/bash", "/adapter.sh"]
```

**`docker/aider/Dockerfile`:**

```dockerfile
FROM node:20-bookworm

# Aider needs Python
RUN apt-get update && \
    apt-get install -y python3-pip python3-venv && \
    rm -rf /var/lib/apt/lists/*

# Pin Aider version
RUN pip install --break-system-packages aider-chat==0.82.0

# Git config
RUN git config --global user.name "Thunderdome" && \
    git config --global user.email "bench@localhost"

WORKDIR /workspace
CMD ["/bin/bash", "/adapter.sh"]
```

### 5. Config Updates (`thunderdome.yaml`)

```yaml
orchestrators:
  - name: "null"
    adapter: ./adapters/null.sh
    image: alpine:latest

  - name: claude-code
    adapter: ./adapters/claude-code/adapter.sh
    image: thunderdome/claude-code:latest
    env:
      ANTHROPIC_API_KEY: "${ANTHROPIC_API_KEY}"

  - name: aider
    adapter: ./adapters/aider/adapter.sh
    image: thunderdome/aider:latest
    env:
      ANTHROPIC_API_KEY: "${ANTHROPIC_API_KEY}"
```

### 6. Build Pipeline (`Makefile`)

```makefile
.PHONY: build adapters docker

build:
	go build -o thunderdome .

adapters:
	CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -o adapters/claude-code/ws-server ./adapters/claude-code/

docker: adapters
	docker build -t thunderdome/claude-code:latest -f docker/claude-code/Dockerfile adapters/claude-code/
	docker build -t thunderdome/aider:latest -f docker/aider/Dockerfile adapters/aider/

test:
	go test ./...

smoke: build docker
	./thunderdome run --orchestrator null --task bench-time-tracker --trials 1
```

## API Key Handling

The harness design states: "Secrets never enter containers." But Claude Code requires `ANTHROPIC_API_KEY` for SDK authentication, even when `ANTHROPIC_BASE_URL` points at LiteLLM.

**Two viable approaches:**

1. **Virtual key:** Configure LiteLLM to accept a known virtual key (e.g., `sk-thunderdome-virtual`) and use its own configured upstream keys. Pass the virtual key to the container. The container never sees the real API key.

2. **Pass-through key:** Accept that the API key enters the container. The container is ephemeral, isolated, and destroyed after each trial. The key is already in the host's `.env.secrets`. Risk is low for a benchmarking framework.

**Recommendation:** Start with approach 2 (pass-through) for simplicity. Switch to virtual keys if the framework is ever exposed to untrusted orchestrator code.

## Harness Fixes Required

These gaps in the existing harness must be addressed before the first real benchmark:

1. **Wire `time_limit_minutes` through.** `cmd/run.go` currently infers timeout from category name via `timeoutForCategory()`. Each task already declares `time_limit_minutes` in config. Use that value directly.

2. **Verify Internal network + host.docker.internal.** The Docker runner creates Internal=true networks and adds `host.docker.internal:host-gateway` to ExtraHosts. Confirm that containers can reach the host's LiteLLM port through this configuration. If not, remove Internal=true and rely on Docker's default bridge network.

3. **Read metrics sidecar.** After container exit, check for `/workspace/.thunderdome-metrics.json` and merge token counts into `meta.json`. Fall back to LiteLLM proxy logs if the sidecar is missing.

## Testing Strategy

1. **Unit tests for ws-server:** Test state machine transitions with mock WebSocket messages. Verify: init handshake, tool approval, result extraction, timeout handling, malformed message handling.

2. **Integration test:** Start ws-server, connect a mock client that replays a captured Claude Code session, verify correct responses and metrics output.

3. **Smoke test:** Run `thunderdome run --orchestrator claude-code --task bench-time-tracker --trials 1` end-to-end. Verify: container starts, Claude Code connects, task prompt is sent, some code is written, tests run, results are captured.

4. **Contract test:** Run `thunderdome run --orchestrator aider --task bench-time-tracker --trials 1` to verify the adapter contract works for CLI-only tools.

## Security Model

Auto-approving all tool permissions is intentional. The security boundary is the Docker container, not the permission system.

**What Claude Code can do inside the container:**
- Read/write files in /workspace (task repo)
- Execute bash commands
- Install npm packages
- Make HTTP requests to LiteLLM (via ANTHROPIC_BASE_URL)

**What it cannot do:**
- Access the host filesystem (Docker mount isolation)
- Reach external APIs directly (Internal network + ExtraHosts limits connectivity to the gateway)
- Exceed the time limit (Docker-level timeout enforcement)
- Exceed the budget (LiteLLM per-trial spending cap)

## Implementation Order

1. Write the Go WebSocket server with unit tests
2. Write the adapter shell script
3. Create the Dockerfile and build the image
4. Wire `time_limit_minutes` through in the harness
5. Verify Internal network + host.docker.internal connectivity
6. Smoke test with T1 (CLI Time Tracker — simplest task)
7. Write the Aider adapter + Dockerfile
8. Smoke test Aider with T1
9. Run both adapters against T1 with 3 trials, compare results
