#!/bin/bash
set -e

# Dao + Sonnet 4.6 via OAuth.
# Pure prompt-only Dao framing on Sonnet -- previously only tested on Qwen3.6
# (76.4%) and as a flavor inside metacog-zen on Sonnet (82.5%, plugin-based).
# This isolates the prompt-only effect on Sonnet 4.6.

[[ -f "$TASK_DESCRIPTION" ]] || { echo "Task file not found: $TASK_DESCRIPTION" >&2; exit 2; }

cd "$TASK_DIR"

export HOME=/tmp

if [ -f /tmp/.claude-credentials.json ]; then
  mkdir -p "$HOME/.claude"
  cp /tmp/.claude-credentials.json "$HOME/.claude/.credentials.json"
fi

if [ -n "$PROXY_URL" ]; then
  export ANTHROPIC_BASE_URL="$PROXY_URL"
fi

git config user.name "dao-sonnet"
git config user.email "dao-sonnet@thunderdome"

TASK_PROMPT=$(cat "$TASK_DESCRIPTION")
OUTPUT_FILE=/workspace/.thunderdome-output.jsonl

set +e
claude -p \
  --model claude-sonnet-4-6 \
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

node -e '
const fs = require("fs");
try {
  const lines = fs.readFileSync(process.argv[1], "utf8").split("\n");
  const metrics = {
    input_tokens: 0, output_tokens: 0, cache_read_tokens: 0,
    cache_creation_tokens: 0, turns: 0, tools_used: [],
    duration_ms: 0, total_cost_usd: 0
  };
  const seen = new Set();
  for (const line of lines) {
    if (!line.trim()) continue;
    try {
      const m = JSON.parse(line);
      if (m.type === "result") {
        if (m.usage) {
          metrics.input_tokens = m.usage.input_tokens || 0;
          metrics.output_tokens = m.usage.output_tokens || 0;
          metrics.cache_read_tokens = m.usage.cache_read_input_tokens || 0;
          metrics.cache_creation_tokens = m.usage.cache_creation_input_tokens || 0;
        }
        metrics.turns = m.num_turns || 0;
        metrics.duration_ms = m.duration_ms || 0;
        metrics.total_cost_usd = m.total_cost_usd || 0;
      }
      if (m.type === "assistant" && m.message && Array.isArray(m.message.content)) {
        for (const b of m.message.content) {
          if (b.type === "tool_use" && b.name && !seen.has(b.name)) {
            seen.add(b.name);
            metrics.tools_used.push(b.name);
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
' "$OUTPUT_FILE"

exit $CLAUDE_EXIT
