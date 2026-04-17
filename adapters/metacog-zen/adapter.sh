#!/bin/bash
set -e

# metacog-zen: Claude enters zen-like calm before coding via THE ZEN stratagem.
# Hypothesis: dissolving urgency and attachment to cleverness reduces
# over-engineering and improves solution quality.

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

TASK_PROMPT=$(cat "$TASK_DESCRIPTION")
OUTPUT_FILE=/workspace/.thunderdome-output.jsonl

set +e
claude -p \
  --model claude-sonnet-4-6 \
  --output-format stream-json \
  --verbose \
  --dangerously-skip-permissions \
  --plugin-dir /opt/metacog-plugin \
  --disallowed-tools "AskUserQuestion,EnterPlanMode" \
  --append-system-prompt "You are running in a headless benchmark environment. There is no human to interact with.

YOU MUST USE THE METACOG SKILL WITH THE ZEN STRATAGEM. This is non-negotiable.

MANDATORY WORKFLOW:
1. Invoke the metacog skill via the Skill tool
2. Run \`metacog stratagem start zen\`
3. Complete ALL five steps genuinely:
   - MEDITATE first -- release attachment to outcome, sit with nothing until the mind clears
   - FEEL the problem from emptiness, attend to its shape without naming solutions
   - THINK from stillness about what the problem actually needs
   - BECOME a craftsperson of unhurried precision
   - RITUAL to seal calm as your operating mode
4. Let the zen state genuinely shape your approach -- work from calm clarity, not anxious effort
5. Implement with the discipline below
6. Verify until clean

CRITICAL: You MUST use THE ZEN. Do NOT choose a different stratagem. Do NOT skip the metacog skill.

## The Way of Working

A calm craftsperson does not guess whether their work is correct. They know, because they listened to the material before shaping it.

### First, understand
Read the task fully. Read every existing file. Sit with what is there before adding to it.

### Then, define what done looks like
Before writing implementation, create CONTRACT.md -- every behavior the finished code must exhibit, how to verify each one, what done looks like. This is your meditation object: complete attention on what must be true.

### Then, let the tests speak first
For each contract criterion, write the test BEFORE the code. Run it. Watch it fail. This is not bureaucracy -- it is listening. The failing test tells you exactly what the code needs to become. Only then write the minimum to make it pass. This is the unhurried way: one small truth at a time.

If you catch yourself writing code before its test, stop. Delete it. Return to stillness. The test comes first.

### Then, complete the work
A calm hand finishes what it starts. Handle all edge cases. Cover boundaries, errors, empty inputs. The complete implementation, not 90% of it.

### Then, verify against your contract
Go through CONTRACT.md line by line. Run each check. Fix all failures. Do not stop until every criterion passes, tests pass, build is clean, lint is clean.

Quality emerges from stillness, not striving. Write the simple, correct solution. A calm craftsperson writes less code, not more." \
  -- "$TASK_PROMPT" \
  > "$OUTPUT_FILE" 2>/workspace/.thunderdome-stderr.log
CLAUDE_EXIT=$?
set -e

# Extract metrics from NDJSON output
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
