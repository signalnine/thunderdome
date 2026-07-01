#!/bin/bash
set -e

[[ -f "$TASK_DESCRIPTION" ]] || { echo "Task file not found: $TASK_DESCRIPTION" >&2; exit 2; }

cd "$TASK_DIR"

# Use /tmp as HOME so Claude Code can write session files, debug logs, etc.
# The container runs as host UID which can't write to /home/node
export HOME=/tmp

# Set up OAuth credentials: copy from mounted read-only location
# into a writable ~/.claude dir that Claude Code can manage.
# Uses the host Max-subscription OAuth login (no API key, no per-token billing).
# The mount at /tmp/.claude-credentials.json is a LIVE bind mount, so re-copying
# it picks up a host-side token refresh (used by the auth-retry below).
stage_creds() {
  if [ -f /tmp/.claude-credentials.json ]; then
    mkdir -p "$HOME/.claude"
    cp /tmp/.claude-credentials.json "$HOME/.claude/.credentials.json"
  fi
}
stage_creds

# Preflight: warn loudly if the mounted OAuth token has little life left. Long
# tasks (e.g. factory-reset, 150-min limit) that run at the tail of a parallel
# pool will hit `authentication_failed` (401) once the token expires -- the fix
# is to /login for a fresh (~8h) token BEFORE launching the run.
python3 - <<'PY' 2>/dev/null || true
import json,time
try:
    o=json.load(open("/tmp/.claude-credentials.json")).get("claudeAiOauth",{})
    hrs=(o.get("expiresAt",0)-time.time()*1000)/3600000
    if hrs < 2: print(f"WARNING: OAuth token has only ~{hrs:.1f}h left -- long tasks may hit auth_failed. /login for a fresh token before long runs.")
except Exception: pass
PY

TASK_PROMPT=$(cat "$TASK_DESCRIPTION")
OUTPUT_FILE=/workspace/.thunderdome-output.jsonl

# Run claude, retrying on a transient OAuth 401. A long/late task can catch the
# shared token mid-expiry (or a sibling container's refresh-token rotation); the
# CLI 401s and emits a <synthetic> empty turn -> "crashed" with no work. On that
# signature we re-stage the live host creds (which may have refreshed) and retry.
run_claude() {
  claude -p \
    --model claude-sonnet-5 \
    --output-format stream-json \
    --verbose \
    --dangerously-skip-permissions \
    --setting-sources '' \
    --strict-mcp-config \
    -- "$TASK_PROMPT" \
    > "$OUTPUT_FILE" 2>/workspace/.thunderdome-stderr.log
}
auth_failed_no_work() {
  # 401 authentication_failed in the stream AND no real assistant tool_use/text
  grep -q "authentication_failed" "$OUTPUT_FILE" 2>/dev/null \
    && ! grep -q '"type":"tool_use"' "$OUTPUT_FILE" 2>/dev/null
}
set +e
run_claude; CLAUDE_EXIT=$?
attempt=1
while [ $attempt -le 2 ] && auth_failed_no_work; do
  echo "auth_failed with no work (attempt $attempt) -- re-staging live creds and retrying" >&2
  sleep $((attempt * 15)); stage_creds
  run_claude; CLAUDE_EXIT=$?
  attempt=$((attempt + 1))
done
set -e

node -e '
const fs = require("fs");
try {
  const lines = fs.readFileSync(process.argv[1], "utf8").split("\n");
  const metrics = {
    input_tokens: 0, output_tokens: 0, cache_read_tokens: 0,
    cache_creation_tokens: 0, turns: 0, tools_used: [],
    duration_ms: 0, total_cost_usd: 0
  };
  const toolsSeen = new Set();
  for (const line of lines) {
    if (!line.trim()) continue;
    try {
      const msg = JSON.parse(line);
      if (msg.type === "result") {
        if (msg.usage) {
          metrics.input_tokens = msg.usage.input_tokens || 0;
          metrics.output_tokens = msg.usage.output_tokens || 0;
          metrics.cache_read_tokens = msg.usage.cache_read_input_tokens || 0;
          metrics.cache_creation_tokens = msg.usage.cache_creation_input_tokens || 0;
        }
        metrics.turns = msg.num_turns || 0;
        metrics.duration_ms = msg.duration_ms || 0;
        metrics.total_cost_usd = msg.total_cost_usd || 0;
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
  fs.writeFileSync("/workspace/.thunderdome-metrics.json", JSON.stringify(metrics, null, 2));
  console.error("Metrics: " + JSON.stringify(metrics));
} catch(e) {
  console.error("Metrics extraction failed: " + e.message);
}
' "$OUTPUT_FILE" || true

exit $CLAUDE_EXIT
