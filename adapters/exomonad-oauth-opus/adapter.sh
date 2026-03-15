#!/bin/bash
set -e

# --- ExoMonad Adapter (OAuth + Opus) ---
# Multi-agent orchestration via ExoMonad: Claude (Opus) decomposes tasks,
# Gemini implements, with tmux-based process isolation and git worktrees.
# https://github.com/tidepool-heavy-industries/exomonad

[[ -f "$TASK_DESCRIPTION" ]] || { echo "Task file not found: $TASK_DESCRIPTION" >&2; exit 2; }

cd "$TASK_DIR"

export HOME=/tmp

# ============================================================================
# Phase 0: Credentials & Environment
# ============================================================================

# Set up OAuth credentials for Claude Code
if [ -f /tmp/.claude-credentials.json ]; then
  mkdir -p "$HOME/.claude"
  cp /tmp/.claude-credentials.json "$HOME/.claude/.credentials.json"
fi

# Set up Gemini CLI credentials (mounted read-only at /tmp/.gemini-host)
if [ -d /tmp/.gemini-host ]; then
  mkdir -p "$HOME/.gemini"
  cp -r /tmp/.gemini-host/* "$HOME/.gemini/" 2>/dev/null || true
  chmod -R u+rw "$HOME/.gemini/" 2>/dev/null || true
  echo "Gemini credentials configured"
fi

# Skip dangerous mode permission prompt (required for headless)
mkdir -p "$HOME/.claude"
cat > "$HOME/.claude/settings.json" << 'SETTINGS_EOF'
{"skipDangerousModePermissionPrompt":true}
SETTINGS_EOF

if [ -n "$PROXY_URL" ]; then
  export ANTHROPIC_BASE_URL="$PROXY_URL"
fi

TASK_PROMPT=$(cat "$TASK_DESCRIPTION")
WALL_CLOCK_START=$(date +%s)
METRICS_DIR="/tmp/exomonad-metrics"
mkdir -p "$METRICS_DIR"

# ============================================================================
# Phase 1: Initialize ExoMonad
# ============================================================================

echo "=== ExoMonad: Initializing ==="

# Ensure workspace has a real branch (harness leaves HEAD detached)
DEFAULT_BRANCH=$(git -C /workspace symbolic-ref --short HEAD 2>/dev/null || echo "")
if [ -z "$DEFAULT_BRANCH" ]; then
  DEFAULT_BRANCH="main"
  git -C /workspace checkout -b "$DEFAULT_BRANCH" 2>/dev/null || true
fi
echo "Branch: $DEFAULT_BRANCH"

# Git identity (required for worktree operations)
git config user.name "ExoMonad"
git config user.email "exile@exomonad.dev"

# Bootstrap .exo directory
mkdir -p .exo/wasm

# Copy pre-built WASM from the Docker image
if [ -f /opt/exomonad/wasm/wasm-guest-devswarm.wasm ]; then
  cp /opt/exomonad/wasm/wasm-guest-devswarm.wasm .exo/wasm/
  echo "Copied WASM plugin"
else
  echo "WARN: No pre-built WASM found at /opt/exomonad/wasm/" >&2
fi

# Write minimal config
cat > .exo/config.toml << 'CONFIG_EOF'
# ExoMonad project config — headless benchmark mode
CONFIG_EOF

# Write .mcp.json for Claude Code to discover ExoMonad MCP tools
cat > .mcp.json << 'MCP_EOF'
{
  "mcpServers": {
    "exomonad": {
      "type": "stdio",
      "command": "exomonad",
      "args": ["mcp-stdio", "--role", "tl", "--name", "root"]
    }
  }
}
MCP_EOF

echo "MCP config written"

# ============================================================================
# Phase 2: Start ExoMonad Server
# ============================================================================

echo "=== ExoMonad: Starting server ==="

# Start tmux (exomonad needs it for agent isolation)
tmux new-session -d -s exo-bench -x 200 -y 50 2>/dev/null || true
export EXOMONAD_TMUX_SESSION=exo-bench

# Start exomonad serve in background
exomonad serve > "$METRICS_DIR/server.log" 2>&1 &
SERVER_PID=$!
echo "Server PID: $SERVER_PID"

# Wait for server socket
SOCKET_PATH=".exo/server.sock"
ELAPSED=0
while [ ! -S "$SOCKET_PATH" ] && [ $ELAPSED -lt 30 ]; do
  sleep 1
  ELAPSED=$((ELAPSED + 1))
done

if [ -S "$SOCKET_PATH" ]; then
  echo "Server ready (${ELAPSED}s)"
else
  echo "WARN: Server socket not found after 30s" >&2
fi

# ============================================================================
# Phase 3: Run Claude (Opus) as Team Lead
# ============================================================================

echo "=== ExoMonad: Running Claude TL ==="

OUTPUT_FILE="$METRICS_DIR/claude-tl.jsonl"

# Write hook configuration (exomonad needs this for session registration)
exomonad hook session-start < /dev/null > /dev/null 2>&1 || true

set +e
claude -p \
  --model claude-opus-4-6 \
  --output-format stream-json \
  --verbose \
  --dangerously-skip-permissions \
  --disallowed-tools "AskUserQuestion,EnterPlanMode" \
  -- "$TASK_PROMPT" \
  > "$OUTPUT_FILE" 2>"$METRICS_DIR/claude-tl-stderr.log"
CLAUDE_EXIT=$?
set -e

echo "Claude TL exited: $CLAUDE_EXIT"

# Stop the server
kill $SERVER_PID 2>/dev/null || true

# ============================================================================
# Phase 4: Metrics
# ============================================================================

echo "=== ExoMonad: Aggregating metrics ==="

WALL_CLOCK_END=$(date +%s)
WALL_CLOCK_DURATION=$(( (WALL_CLOCK_END - WALL_CLOCK_START) * 1000 ))

set +e
node -e '
const fs = require("fs");

const outputFile = process.argv[1];
const wallClockMs = parseInt(process.argv[2]) || 0;

const metrics = {
  input_tokens: 0, output_tokens: 0, cache_read_tokens: 0,
  cache_creation_tokens: 0, turns: 0, tools_used: [],
  duration_ms: wallClockMs, total_cost_usd: 0
};
const toolsSeen = new Set();

try {
  const lines = fs.readFileSync(outputFile, "utf8").split("\n");
  for (const line of lines) {
    if (!line.trim()) continue;
    try {
      const msg = JSON.parse(line);
      if (msg.type === "result") {
        if (msg.usage) {
          metrics.input_tokens += (msg.usage.input_tokens || 0);
          metrics.output_tokens += (msg.usage.output_tokens || 0);
          metrics.cache_read_tokens += (msg.usage.cache_read_input_tokens || 0);
          metrics.cache_creation_tokens += (msg.usage.cache_creation_input_tokens || 0);
        }
        metrics.turns += (msg.num_turns || 0);
        metrics.duration_ms = msg.duration_ms || wallClockMs;
        metrics.total_cost_usd += (msg.total_cost_usd || 0);
      }
      if (msg.type === "assistant" && msg.message && Array.isArray(msg.message.content)) {
        for (const block of msg.message.content) {
          if (block.type === "tool_use" && block.name && !toolsSeen.has(block.name)) {
            toolsSeen.add(block.name);
            metrics.tools_used.push(block.name);
          }
        }
      }
    } catch(e) {}
  }
} catch(e) {
  console.error("WARN: Failed to read output file: " + e.message);
}

fs.writeFileSync("/workspace/.thunderdome-metrics.json", JSON.stringify(metrics, null, 2));
console.error("Metrics: " + JSON.stringify({
  tokens: metrics.input_tokens + metrics.output_tokens,
  cost: metrics.total_cost_usd,
  turns: metrics.turns,
  wall_clock_s: Math.round(wallClockMs / 1000)
}));
' "$OUTPUT_FILE" "$WALL_CLOCK_DURATION"
NODE_EXIT=$?
set -e

# Fallback if node failed
if [ $NODE_EXIT -ne 0 ] || [ ! -f /workspace/.thunderdome-metrics.json ]; then
  echo "WARN: Metrics extraction failed, writing fallback"
  cat > /workspace/.thunderdome-metrics.json << FALLBACK_EOF
{
  "input_tokens": 0, "output_tokens": 0,
  "cache_read_tokens": 0, "cache_creation_tokens": 0,
  "turns": 0, "duration_ms": $WALL_CLOCK_DURATION,
  "total_cost_usd": 0.001
}
FALLBACK_EOF
fi

cd /workspace
echo "=== ExoMonad adapter complete ==="
exit $CLAUDE_EXIT
