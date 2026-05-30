#!/bin/bash
set -e

# --- Claude Code + DeepSeek v4 Flash via DeepSeek native API ---
# Flash is DeepSeek's smaller / cheaper v4-family model. Same /anthropic
# endpoint as Pro -- no translation proxy. Auto context caching applies.
# Run as a standalone vanilla baseline for the small-model tier; the
# Pro adapter already exercises Flash as HAIKU + subagent worker.

[[ -f "$TASK_DESCRIPTION" ]] || { echo "Task file not found: $TASK_DESCRIPTION" >&2; exit 2; }

cd "$TASK_DIR"

export ANTHROPIC_BASE_URL="https://api.deepseek.com/anthropic"
export ANTHROPIC_AUTH_TOKEN="$DEEPSEEK_API_KEY"
unset ANTHROPIC_API_KEY

export ANTHROPIC_DEFAULT_OPUS_MODEL="deepseek-v4-flash"
export ANTHROPIC_DEFAULT_SONNET_MODEL="deepseek-v4-flash"
export ANTHROPIC_DEFAULT_HAIKU_MODEL="deepseek-v4-flash"
export CLAUDE_CODE_SUBAGENT_MODEL="deepseek-v4-flash"

TASK_PROMPT=$(cat "$TASK_DESCRIPTION")
OUTPUT_FILE=/workspace/.thunderdome-output.jsonl

echo "=== Claude Code (DeepSeek v4 Flash, native API): Starting ==="

# DeepSeek v4 Flash pricing per docs (2026-05): $0.07/M input, $0.27/M output,
# $0.01/M cache read, $0.09/M cache write. Approximately 6x cheaper than Pro.

set +e
claude -p \
  --output-format stream-json \
  --verbose \
  --dangerously-skip-permissions \
  --disallowed-tools "AskUserQuestion,EnterPlanMode" \
  -- "$TASK_PROMPT" \
  > "$OUTPUT_FILE" 2>/workspace/.thunderdome-stderr.log
CLAUDE_EXIT=$?
set -e

echo "Claude Code exited: $CLAUDE_EXIT"

node -e '
const fs = require("fs");
const PRICE_IN  = 0.07 / 1e6;
const PRICE_OUT = 0.27 / 1e6;
const PRICE_CACHE_READ = 0.01 / 1e6;
const PRICE_CACHE_WRITE = 0.09 / 1e6;
try {
  const lines = fs.readFileSync(process.argv[1], "utf8").split("\n");
  const metrics = {
    input_tokens: 0, output_tokens: 0, cache_read_tokens: 0,
    cache_creation_tokens: 0, turns: 0, tools_used: [],
    duration_ms: 0, total_cost_usd: 0,
  };
  const seen = new Set();
  for (const line of lines) {
    if (!line.trim()) continue;
    let m;
    try { m = JSON.parse(line); } catch { continue; }
    if (m.type === "result") {
      const u = m.usage || {};
      metrics.input_tokens          = u.input_tokens          || 0;
      metrics.output_tokens         = u.output_tokens         || 0;
      metrics.cache_read_tokens     = u.cache_read_input_tokens     || 0;
      metrics.cache_creation_tokens = u.cache_creation_input_tokens || 0;
      metrics.turns       = m.num_turns    || 0;
      metrics.duration_ms = m.duration_ms  || 0;
    }
    if (m.type === "assistant" && m.message && Array.isArray(m.message.content)) {
      for (const b of m.message.content) {
        if (b.type === "tool_use" && b.name && !seen.has(b.name)) {
          seen.add(b.name);
          metrics.tools_used.push(b.name);
        }
      }
    }
  }
  metrics.total_cost_usd = +(
      metrics.input_tokens          * PRICE_IN
    + metrics.output_tokens         * PRICE_OUT
    + metrics.cache_read_tokens     * PRICE_CACHE_READ
    + metrics.cache_creation_tokens * PRICE_CACHE_WRITE
  ).toFixed(6);
  fs.writeFileSync("/workspace/.thunderdome-metrics.json", JSON.stringify(metrics, null, 2));
  console.error("Metrics: " + JSON.stringify(metrics));
} catch(e) {
  console.error("Metrics extraction failed: " + e.message);
}
' "$OUTPUT_FILE"

echo "=== Claude Code (DeepSeek v4 Flash native) adapter complete ==="
exit $CLAUDE_EXIT
