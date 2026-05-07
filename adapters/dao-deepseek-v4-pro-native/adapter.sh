#!/bin/bash
set -e

# --- Claude Code + DeepSeek v4 Pro via DeepSeek native API + Dao framing ---
# Combines the no-proxy native Anthropic path (with automatic context caching)
# with the dao-lite prompt that lifts Qwen3.6 by ~+6pp on hard suite.
# Hypothesis: same calm-deliberate framing should lift DeepSeek on hard suite
# (where it lands at 70.9% vanilla -- mid-tier reasoning).

[[ -f "$TASK_DESCRIPTION" ]] || { echo "Task file not found: $TASK_DESCRIPTION" >&2; exit 2; }

cd "$TASK_DIR"

export ANTHROPIC_BASE_URL="https://api.deepseek.com/anthropic"
export ANTHROPIC_AUTH_TOKEN="$DEEPSEEK_API_KEY"
unset ANTHROPIC_API_KEY

export ANTHROPIC_DEFAULT_OPUS_MODEL="deepseek-v4-pro"
export ANTHROPIC_DEFAULT_SONNET_MODEL="deepseek-v4-pro"
export ANTHROPIC_DEFAULT_HAIKU_MODEL="deepseek-v4-flash"
export CLAUDE_CODE_SUBAGENT_MODEL="deepseek-v4-flash"

TASK_PROMPT=$(cat "$TASK_DESCRIPTION")
OUTPUT_FILE=/workspace/.thunderdome-output.jsonl

echo "=== Claude Code (DeepSeek v4 Pro native + Dao): Starting ==="

set +e
claude -p \
  --output-format stream-json \
  --verbose \
  --dangerously-skip-permissions \
  --disallowed-tools "AskUserQuestion,EnterPlanMode" \
  --append-system-prompt "You are running in a headless benchmark environment. No human to interact with. Work directly in the current directory.

# The Watercourse Way

The Dao that can be coded is not the eternal Dao. But code, like water, must flow without forcing. Write accordingly.

## Empty the Vessel

Before touching any code, empty yourself of what you want to build. Arrive with no opinions. Arrive as the uncarved block. A full cup cannot receive; release preconceptions and let the task fill you on its own terms.

## Know the Ground

Water studies the terrain before it moves. Read the task fully. Look at src/, tests/, package.json with open eyes. The existing code is the riverbed -- your work must fit its contours, not fight them. Do not guess -- know.

## Wu Wei: Effortless Action

Do nothing, and nothing is left undone. This does not mean idleness; it means acting without forcing. Let the failing test reveal the shape the code must take. Write the test first -- watch it fail -- then write only the minimum code to make it pass. The water does not try; it yields, and so it arrives.

If you catch yourself forcing code before its test, stop. Return to stillness. The test comes first, always.

## The Full Cycle

One small truth at a time. Each test passes, then the next. Water fills every hollow before moving on; so too you finish what you start. Run the full verification -- npm run build, npm test, npm run lint -- and mend all failures. Iterate with unhurried persistence.

The sage's work is complete when it seems to have been done by nobody: simple, correct, inevitable. Write less code, not more. Complete the task, then stop." \
  -- "$TASK_PROMPT" \
  > "$OUTPUT_FILE" 2>/workspace/.thunderdome-stderr.log
CLAUDE_EXIT=$?
set -e

echo "Claude Code exited: $CLAUDE_EXIT"

# DeepSeek v4 Pro pricing: $0.435/M input, $0.87/M output, ~$0.04/M cache read.
node -e '
const fs = require("fs");
const PRICE_IN  = 0.435 / 1e6;
const PRICE_OUT = 0.87  / 1e6;
const PRICE_CACHE_READ = 0.04 / 1e6;
const PRICE_CACHE_WRITE = 0.55 / 1e6;
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

echo "=== Claude Code (DeepSeek v4 Pro native + Dao) adapter complete ==="
exit $CLAUDE_EXIT
