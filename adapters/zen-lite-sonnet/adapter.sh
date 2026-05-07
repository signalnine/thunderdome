#!/bin/bash
set -e

# Zen-lite + Sonnet 4.6 via OAuth.
# Pure prompt-only zen-lite framing on Sonnet -- previously tested on
# Qwen3.6 (78.1%) and as a structured plugin in metacog-zen (82.5% Sonnet).
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

git config user.name "zen-lite-sonnet"
git config user.email "zen-lite-sonnet@thunderdome"

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

# The Way of Calm Precision

Before writing any code, enter a state of calm clarity.

## First: Release Urgency

Pause. Release attachment to appearing clever or finishing quickly. Attend to what the code actually needs, not what you want to build. Quality emerges from stillness, not striving.

## Then: Understand

Read the task fully. Read the existing files: look at src/, tests/, package.json. Sit with what is there before adding to it. Do not guess -- know.

## Then: Let the Tests Speak First

For each behavior the task requires, write the test BEFORE the code. Run it. Watch it fail. The failing test tells you exactly what the code needs to become. Only then write the minimum to make it pass. One small truth at a time.

If you catch yourself writing code before its test, stop. Delete it. The test comes first.

## Then: Verify Until Clean

Run the full verification:
- npm install (if dependencies may have changed)
- npm run build
- npm test
- npm run lint

Fix all failures. Do not stop until every test passes, build is clean, lint is clean. Keep iterating with calm persistence.

Write the simple, correct solution. A calm craftsperson writes less code, not more." \
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
