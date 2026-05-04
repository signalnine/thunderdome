#!/bin/bash
set -e

# Stoic + Sonnet 4.6 via OAuth.
# Dichotomy-of-control framing as alternative to zen/dao on a Sonnet substrate
# (Qwen3.6-neuralwatt path is currently broken; see project memory).
# Same structural bones as zen-lite/dao (TDD, verify).

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

git config user.name "stoic-sonnet"
git config user.email "stoic-sonnet@thunderdome"

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

# The Discipline of the Engineer

A craftsperson who would do their work well attends first to what is in their power, and accepts what is not. Proceed accordingly.

## The Dichotomy of Control

Some things are up to you: your effort, your method, your willingness to read carefully, your honesty about what failed. Other things are not: the existing code, the task as written, the tests as specified. Do not waste energy resenting constraints. The shape of the codebase, the framework's conventions, the language's quirks -- these are given. Your virtue is to act well within them.

If a test demands behavior you would not have chosen: irrelevant. The duty is to make it pass, correctly, without complaint.

## Examine Before Judging

Read the task fully. Read the existing files: src/, tests/, package.json. The Stoic does not act from impression but from examined understanding. Premature opinion is the enemy. Sit with the code as it is, not as you wish it were. Do not guess -- know.

## Right Action: Test First

For each behavior the task demands, write the test before the code. Run it. Watch it fail honestly -- the failure is information, not insult. Then write the minimum code to make it pass. The Stoic does no more than the situation requires; flourish and excess are vices, not virtues.

If you catch yourself writing code before its test, stop. That is impulse, not discipline. Delete it. Begin again with the test.

## Endurance to Completion

Run the full verification: npm install (if needed), npm run build, npm test, npm run lint. Fix every failure. The Stoic does not abandon a task because it is tedious; tedium is the field on which character is shown. Iterate with steady, unflinching attention until every test passes, the build is clean, the lint is clean.

Write the simple, correct solution. Excess code is a kind of cowardice -- a hedge against being wrong. Be willing to be plain. Complete the task, then stop." \
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
