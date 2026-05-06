#!/bin/bash
set -e

# --- Claude Code + DeepSeek v4 Pro via OpenRouter (native Anthropic endpoint) ---
# DeepSeek v4 Pro at $0.435/M input, $0.87/M output, 1M ctx.
# Uses OpenRouter's Anthropic-shaped endpoint at api/v1/messages so no
# translation proxy is needed -- Claude Code talks Anthropic protocol natively.
# The anth2openai_proxy translation path hangs on tool_result followups for
# non-Anthropic models, so we sidestep it entirely.

[[ -f "$TASK_DESCRIPTION" ]] || { echo "Task file not found: $TASK_DESCRIPTION" >&2; exit 2; }

cd "$TASK_DIR"

export ANTHROPIC_BASE_URL="https://openrouter.ai/api"
export ANTHROPIC_AUTH_TOKEN="$OPENROUTER_API_KEY"
unset ANTHROPIC_API_KEY  # Claude Code prefers AUTH_TOKEN when both set

# Route every model tier to deepseek-v4-pro so subagent / haiku calls also
# hit the same model rather than trying to reach an Anthropic-only model.
export ANTHROPIC_DEFAULT_OPUS_MODEL="deepseek/deepseek-v4-pro"
export ANTHROPIC_DEFAULT_SONNET_MODEL="deepseek/deepseek-v4-pro"
export ANTHROPIC_DEFAULT_HAIKU_MODEL="deepseek/deepseek-v4-pro"
export CLAUDE_CODE_SUBAGENT_MODEL="deepseek/deepseek-v4-pro"

TASK_PROMPT=$(cat "$TASK_DESCRIPTION")
OUTPUT_FILE=/workspace/.thunderdome-output.jsonl

echo "=== Claude Code (DeepSeek v4 Pro via OpenRouter): Starting ==="

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

# Extract metrics from Claude Code's stream-json result event.
# Cost is computed locally since Claude Code reports nothing for non-Anthropic.
node -e '
const fs = require("fs");
const PRICE_IN  = 0.435 / 1e6;   // DeepSeek v4 Pro input  $/token
const PRICE_OUT = 0.87  / 1e6;   // DeepSeek v4 Pro output $/token
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
  metrics.total_cost_usd = +(metrics.input_tokens * PRICE_IN + metrics.output_tokens * PRICE_OUT).toFixed(6);
  fs.writeFileSync("/workspace/.thunderdome-metrics.json", JSON.stringify(metrics, null, 2));
  console.error("Metrics: " + JSON.stringify(metrics));
} catch(e) {
  console.error("Metrics extraction failed: " + e.message);
}
' "$OUTPUT_FILE"

echo "=== Claude Code (DeepSeek v4 Pro) adapter complete ==="
exit $CLAUDE_EXIT
