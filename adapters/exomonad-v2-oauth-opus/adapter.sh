#!/bin/bash
set -e

# --- ExoMonad v2 Adapter (OAuth + Opus) ---
# Same as v1 but with guided TL behavior from Thunderdome findings:
# 1. Selective delegation (don't delegate simple tasks to Gemini)
# 2. Completion gate (verify before finishing)
# 3. Self-review (commit, review diff, fix)

[[ -f "$TASK_DESCRIPTION" ]] || { echo "Task file not found: $TASK_DESCRIPTION" >&2; exit 2; }

cd "$TASK_DIR"

export HOME=/tmp

# ============================================================================
# Phase 0: Credentials & Environment
# ============================================================================

if [ -f /tmp/.claude-credentials.json ]; then
  mkdir -p "$HOME/.claude"
  cp /tmp/.claude-credentials.json "$HOME/.claude/.credentials.json"
fi

if [ -d /tmp/.gemini-host ]; then
  mkdir -p "$HOME/.gemini"
  cp -r /tmp/.gemini-host/* "$HOME/.gemini/" 2>/dev/null || true
  chmod -R u+rw "$HOME/.gemini/" 2>/dev/null || true
  echo "Gemini credentials configured"
fi

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

echo "=== ExoMonad v2: Initializing ==="

DEFAULT_BRANCH=$(git -C /workspace symbolic-ref --short HEAD 2>/dev/null || echo "")
if [ -z "$DEFAULT_BRANCH" ]; then
  DEFAULT_BRANCH="main"
  git -C /workspace checkout -b "$DEFAULT_BRANCH" 2>/dev/null || true
fi
echo "Branch: $DEFAULT_BRANCH"

git config user.name "ExoMonad"
git config user.email "exile@exomonad.dev"

mkdir -p .exo/wasm

if [ -f /opt/exomonad/wasm/wasm-guest-devswarm.wasm ]; then
  cp /opt/exomonad/wasm/wasm-guest-devswarm.wasm .exo/wasm/
  echo "Copied WASM plugin"
else
  echo "WARN: No pre-built WASM found at /opt/exomonad/wasm/" >&2
fi

cat > .exo/config.toml << 'CONFIG_EOF'
# ExoMonad project config — headless benchmark mode (v2)
CONFIG_EOF

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

# ============================================================================
# Phase 1.5: Write CLAUDE.md with guided TL behavior
# ============================================================================

cat > /workspace/CLAUDE.md << 'CLAUDE_EOF'
# ExoMonad Team Lead Guidelines

You are the Team Lead in an ExoMonad multi-agent system. You have access to ExoMonad MCP tools
that let you spawn Gemini workers (`spawn_leaf_subtree`, `spawn_workers`) for parallel work.

## When to Delegate vs Do It Yourself

**Do the work yourself** when:
- The task is a single feature, bugfix, or straightforward implementation
- The task has fewer than 3 genuinely independent components
- The task is about debugging, fixing tests, or recovery
- You can complete it in under 30 minutes of focused work

**Delegate to workers** only when:
- The task has 3+ truly independent modules that can be built in parallel
- Each subtask is self-contained (own files, own tests, no shared state)
- The coordination overhead is worth the parallelism gain

Most tasks are better done directly. The overhead of spawning workers, managing PRs,
and merging changes is only worth it for genuinely decomposable work.

## Completion Gate (mandatory)

Before finishing, you MUST:

1. Run the full verification suite: `npm test && npm run build && npm run lint`
2. Read the COMPLETE output — do not skip or summarize
3. If ANY test fails or ANY error appears: fix it and re-run
4. Only proceed when all checks pass

## Self-Review (mandatory)

After verification passes:

1. Stage and commit your changes: `git add -A && git commit -m "implement solution"`
2. Review your diff: `git diff HEAD~1`
3. Look for: missing edge cases, incomplete implementations, dead code, debug artifacts
4. If you find issues: fix them, re-verify, re-commit
5. Only stop when verification passes AND diff review is clean

Evidence before claims, always. "Should pass" is not evidence.
CLAUDE_EOF

echo "CLAUDE.md written with TL guidance"

# ============================================================================
# Phase 2: Start ExoMonad Server
# ============================================================================

echo "=== ExoMonad v2: Starting server ==="

tmux new-session -d -s exo-bench -x 200 -y 50 2>/dev/null || true
export EXOMONAD_TMUX_SESSION=exo-bench

exomonad serve > "$METRICS_DIR/server.log" 2>&1 &
SERVER_PID=$!
echo "Server PID: $SERVER_PID"

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

echo "=== ExoMonad v2: Running Claude TL ==="

OUTPUT_FILE="$METRICS_DIR/claude-tl.jsonl"

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

kill $SERVER_PID 2>/dev/null || true

# ============================================================================
# Phase 4: Metrics
# ============================================================================

echo "=== ExoMonad v2: Aggregating metrics ==="

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
echo "=== ExoMonad v2 adapter complete ==="
exit $CLAUDE_EXIT
