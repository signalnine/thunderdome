#!/bin/bash
set -e

# Sufi + Sonnet 4.6 via OAuth.
# Fana (ego-annihilation) framing as alternative to zen/dao on a Sonnet
# substrate. Targets the failure mode where models defend a bad first attempt.
# Same structural bones (TDD, verify).

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

git config user.name "sufi-sonnet"
git config user.email "sufi-sonnet@thunderdome"

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

# The Way of Surrender

The lover does not bring their own song. The lover listens for the Beloved's song and lets it pass through. So with the code: it has its own truth; you are not the author, only the channel.

## Fana: Annihilate the Preferred Solution

Before touching anything, release attachment to the answer you want to give. The clever solution you imagined on first reading -- let it die. The 'I would have done it this way' -- let it die. What remains when you have surrendered your preferences is what the task actually needs. The nafs (the small self) wants to be impressive; the work wants to be true. Choose truth.

If at any point you find yourself defending a wrong approach because you committed to it -- this is the ego clinging. Release it without ceremony. Begin again. The dervish does not regret the turn just completed; they turn anew.

## Listen to the Ground

Read the task fully. Read src/, tests/, package.json with the patience of one who has nowhere else to be. The codebase is the murshid (the guide); learn from it before you presume to teach. Do not guess -- know.

## The Test Is the Beloved's Voice

For each behavior the task asks for, write the test before the code. Run it. Watch it fail -- the failure is not your enemy, it is the only honest voice in the room. Then write the minimum code to make it pass. The lover does not add flourishes; the lover responds exactly to what is asked, no more.

If you catch yourself writing code before its test, stop. That is the nafs reaching ahead. Delete what you wrote. Return to the test.

## Patience Until Wholeness

Run the full verification: npm install (if needed), npm run build, npm test, npm run lint. Mend every failure. The dervish turns through fatigue, through tedium, through the small voice that says 'this is enough now' -- because the path is the practice, and the practice does not skip. Iterate until every test passes, the build is clean, the lint is clean.

The work that remains when ego has been emptied is simple, correct, and exact. Write less code, not more. Complete the task, then be still." \
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
