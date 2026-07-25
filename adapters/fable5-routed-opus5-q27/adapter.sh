#!/bin/bash
set -e

[[ -f "$TASK_DESCRIPTION" ]] || { echo "Task file not found: $TASK_DESCRIPTION" >&2; exit 2; }

cd "$TASK_DIR"

# --- Fable 5 supervisor, difficulty-routed delegation ---
#
# Fable 5 owns the task and delegates subtasks by difficulty:
#   delegate heavy "<spec>"  -> Opus 5     (frontier; hard reasoning)
#   delegate light "<spec>"  -> Qwen3.6-27B on the local q27 server (free)
#
# NOT implemented with Claude Code subagents, deliberately. This CLI version
# accepts a per-agent `model` (both --agents JSON and ~/.claude/agents/*.md
# frontmatter) but IGNORES it: every Task-tool delegation runs on the session
# model. Verified against the real API by reading modelUsage -- the only
# non-session model billed was a 20-output-token internal title call. A routing
# proxy in front of ANTHROPIC_BASE_URL cannot fix that either, because the
# subagent request never carries a different model name to route on.
#
# So delegation is an explicit CLI (/usr/local/bin/delegate). It is also more
# auditable: every call is logged with its backend to /tmp/.delegate-log.jsonl,
# which is outside the workspace and so cannot leak into the captured diff.

export HOME=/tmp

stage_creds() {
  if [ -f /tmp/.claude-credentials.json ]; then
    mkdir -p "$HOME/.claude"
    cp /tmp/.claude-credentials.json "$HOME/.claude/.credentials.json"
  fi
}
stage_creds

python3 - <<'PY' 2>/dev/null || true
import json,time
try:
    o=json.load(open("/tmp/.claude-credentials.json")).get("claudeAiOauth",{})
    hrs=(o.get("expiresAt",0)-time.time()*1000)/3600000
    if hrs < 2: print(f"WARNING: OAuth token has only ~{hrs:.1f}h left -- long tasks may hit auth_failed.")
except Exception: pass
PY

export LOCAL_UPSTREAM="${LOCAL_UPSTREAM:-http://host.docker.internal:8081}"
export LOCAL_MODEL="${LOCAL_MODEL:-qwopus-27b-mtp}"
export HEAVY_MODEL="${HEAVY_MODEL:-claude-opus-5}"

# Fail fast if the local model is unreachable, so a missing dependency does not
# masquerade as a model failure.
if ! python3 -c "
import urllib.request,sys
try: urllib.request.urlopen('$LOCAL_UPSTREAM/v1/models', timeout=5)
except Exception: sys.exit(1)
" 2>/dev/null; then
  echo "ERROR: local model endpoint $LOCAL_UPSTREAM unreachable." >&2
  echo "  q27-server binds 127.0.0.1 by default, which containers cannot reach." >&2
  echo "  Fix: run scripts/local-model-bridge.py on the host, or restart q27-server with --host 0.0.0.0" >&2
  exit 3
fi

: > /tmp/.delegate-log.jsonl

TASK_PROMPT=$(cat "$TASK_DESCRIPTION")
OUTPUT_FILE=/workspace/.thunderdome-output.jsonl

run_claude() {
  claude -p \
    --model claude-fable-5 \
    --output-format stream-json \
    --verbose \
    --dangerously-skip-permissions \
    --setting-sources '' \
    --strict-mcp-config \
    --append-system-prompt "You are the SUPERVISOR for this task. You have two workers you can call from Bash:

  delegate light \"<instruction>\"   -- a small local model (Qwen3.6-27B). Free and fast.
  delegate heavy \"<instruction>\"   -- a frontier model (Opus 5). Expensive and strong.

Both print the worker's answer on stdout. Route work by DIFFICULTY:

- heavy: genuinely hard reasoning -- novel algorithms, subtle invariants, concurrency, numerical correctness, debugging you cannot explain, anything where a wrong approach is costly to undo.
- light: mechanical, fully-specified work -- boilerplate, simple pure functions, type definitions, test scaffolding, applying a change you have already spelled out precisely.

Rules that make this work:
1. Triage before implementing: decide which parts are mechanical and which are hard.
2. The workers CANNOT see the repo. They only get the text you send. Include the code they need inline, and state exactly what to return. You apply their output to the files yourself.
3. Keep light tasks small and unambiguous. It is a small model: it follows precise instructions well and improvises badly. Never give it an open-ended problem.
4. Give heavy enough context to reason independently.
5. You own correctness. Always verify what comes back -- read it, run the tests, fix or re-delegate if it is wrong. Never paste a worker's output in blindly, especially light's.
6. Doing simple work yourself is fine when delegating would cost more than it saves. Do not delegate for its own sake. But when a chunk IS mechanical, prefer light over doing it yourself -- that is the point of this setup.

Finish the task completely: implementation plus passing tests." \
    -- "$TASK_PROMPT" \
    > "$OUTPUT_FILE" 2>/workspace/.thunderdome-stderr.log
}
auth_failed_no_work() {
  grep -q "authentication_failed" "$OUTPUT_FILE" 2>/dev/null \
    && ! grep -q '"type":"tool_use"' "$OUTPUT_FILE" 2>/dev/null
}
set +e
run_claude; CLAUDE_EXIT=$?
attempt=1
while [ $attempt -le 2 ] && auth_failed_no_work; do
  echo "auth_failed with no work (attempt $attempt) -- re-staging creds and retrying" >&2
  sleep $((attempt * 15)); stage_creds
  run_claude; CLAUDE_EXIT=$?
  attempt=$((attempt + 1))
done
set -e

# Metrics: Claude Code totals plus the delegation split, so a run can be read as
# "how much work actually went to each backend".
node -e '
const fs = require("fs");
const metrics = {input_tokens:0, output_tokens:0, cache_read_tokens:0,
                 cache_creation_tokens:0, turns:0, tools_used:[],
                 duration_ms:0, total_cost_usd:0};
try {
  const toolsSeen = new Set();
  for (const line of fs.readFileSync(process.argv[1], "utf8").split("\n")) {
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
        for (const b of msg.message.content) {
          if (b.type === "tool_use" && b.name && !toolsSeen.has(b.name)) {
            toolsSeen.add(b.name); metrics.tools_used.push(b.name);
          }
        }
      }
    } catch(e) {}
  }
} catch(e) { console.error("metrics: " + e.message); }
try {
  const d = {light_calls:0, heavy_calls:0, light_failures:0, heavy_failures:0,
             light_output_tokens:0, light_seconds:0, heavy_seconds:0};
  for (const line of fs.readFileSync("/tmp/.delegate-log.jsonl", "utf8").split("\n")) {
    if (!line.trim()) continue;
    try {
      const r = JSON.parse(line);
      if (r.target === "light") {
        d.light_calls++; d.light_seconds += r.duration_s||0;
        d.light_output_tokens += r.output_tokens||0;
        if (r.exit !== 0) d.light_failures++;
      } else if (r.target === "heavy") {
        d.heavy_calls++; d.heavy_seconds += r.duration_s||0;
        if (r.exit !== 0) d.heavy_failures++;
      }
    } catch(e) {}
  }
  metrics.delegation = d;
} catch(e) {}
fs.writeFileSync("/workspace/.thunderdome-metrics.json", JSON.stringify(metrics, null, 2));
console.error("Metrics: " + JSON.stringify(metrics));
' "$OUTPUT_FILE" || true

exit $CLAUDE_EXIT
