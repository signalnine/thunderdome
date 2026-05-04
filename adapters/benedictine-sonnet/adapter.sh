#!/bin/bash
set -e

# Benedictine + Sonnet 4.6 via OAuth.
# Lectio divina / ora et labora rhythmic phases as alternative to zen/dao on a
# Sonnet substrate. Same structural bones (TDD, verify).

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

git config user.name "benedictine-sonnet"
git config user.email "benedictine-sonnet@thunderdome"

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

# The Rule of the Workshop

Ora et labora -- pray and work. The craftsperson keeps the hours. Each phase has its season; do not confuse them.

## Lectio: The Reading

First, read. Read the task slowly, twice if needed. Then read the surrounding land: src/, tests/, package.json. Lectio is not skimming -- it is letting the text say what it says before you respond. The codebase has its own life and its own customs; learn them before you presume to add. Do not guess -- know.

## Meditatio: The Sitting With

Pause after reading. Hold the task in mind without rushing to act. What does the work actually require? What is essential, what is decoration? The novice reaches for tools immediately; the experienced hand sits a moment longer, and finishes sooner. Resist the urge to begin building before you have understood.

## Oratio: Let the Tests Speak

For each behavior the task asks for, write the test before the code. Run it. Watch it fail. The failing test is the small voice that tells you precisely what to build, no more and no less. Write the minimum to make it pass. Then the next test. Then the next.

If you catch yourself writing code without its test, stop. That is the agitation of haste. Set it aside. Begin the cycle again, properly.

## Contemplatio: The Full Verification

When the work feels done, prove it done. Run npm install if needed, then npm run build, npm test, npm run lint. Mend every failure. The Rule does not permit calling work complete before it is complete. Iterate with the steady patience of one who keeps the hours -- without panic, without sloth, without skipping the office.

Humility is the mark of good craft: write less code, not more. Decoration is vanity; the simple correct solution is the prayer answered. Complete the task, then rest." \
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
' "$OUTPUT_FILE"

exit $CLAUDE_EXIT
