#!/bin/bash
set -e

# conclave-v62-review-opus: Conclave v6.2 with adaptive routing.
#
# Same as conclave-review-opus but with state-heavy detection:
#   1. Agent codes freely (vanilla Claude Code behavior)
#   2. Agent commits and runs consensus code review
#   3. Agent addresses findings
#   4. IF task is state-heavy: runs a SECOND focused review on state correctness
#   5. Agent addresses second-review findings
#   6. Done
#
# Tests the v6.2 hypothesis: double-review on state-heavy tasks improves
# scores by +15-17pp on T5/T8 without regressing other tasks.

[[ -f "$TASK_DESCRIPTION" ]] || { echo "Task file not found: $TASK_DESCRIPTION" >&2; exit 2; }

cd "$TASK_DIR"

export HOME=/tmp

# Set up OAuth credentials from mounted read-only location
if [ -f /tmp/.claude-credentials.json ]; then
  mkdir -p "$HOME/.claude"
  cp /tmp/.claude-credentials.json "$HOME/.claude/.credentials.json"
fi

# Route API calls through proxy gateway if configured
if [ -n "$PROXY_URL" ]; then
  export ANTHROPIC_BASE_URL="$PROXY_URL"
fi

TASK_PROMPT=$(cat "$TASK_DESCRIPTION")
OUTPUT_FILE=/workspace/.thunderdome-output.jsonl

set +e
claude -p \
  --model claude-opus-4-6 \
  --output-format stream-json \
  --verbose \
  --dangerously-skip-permissions \
  --plugin-dir /opt/conclave-plugin \
  --disallowed-tools "AskUserQuestion,EnterPlanMode,Skill" \
  --append-system-prompt "You are running in a headless benchmark environment. There is no human to interact with.

WORK FREELY. Implement the task using your best judgment — no mandatory workflows, no skill invocations, no planning ceremonies. Just write good code.

## State-Heavy Task Detection

Before starting, classify this task. Check if it involves complex state management:

Compound signals (any ONE means state-heavy):
- Concurrent/async operations with ordering constraints
- Real-time updates where one operation's side effects affect others
- Constraint propagation (changing one value must update dependents)
- State machine with multiple transitions that must maintain invariants

Supporting keywords (need 2+ alongside a compound signal):
queues, dashboards, WebSockets, state machines, schedulers, concurrent, real-time

When in doubt, classify as state-heavy.

Log your decision: \"State-heavy: yes/no — [reason]\"

## After Implementation

AFTER you have finished implementing and all tests pass:

### Review #1: Standard Code Review

1. Commit your changes: git add -A && git commit -m 'implementation'
2. Find the base commit: BASE_SHA=\$(git log --reverse --format=%H | head -1)
3. Run multi-agent consensus code review:
   /opt/conclave-plugin/conclave consensus --mode=code-review --base-sha=\$BASE_SHA --head-sha=HEAD --description='Review implementation for correctness, edge cases, and code quality'
4. Read the review output carefully. Address any HIGH PRIORITY or MEDIUM PRIORITY findings.
5. Run tests again to make sure your fixes didn't break anything.

### Review #2: State-Heavy Second Pass (ONLY if task is state-heavy)

If you classified the task as state-heavy above, run a SECOND review after addressing first-review findings. This review must be independent — do not rubber-stamp the first.

1. Commit your fixes: git add -A && git commit -m 'review fixes'
2. Run a second consensus review with a focused prompt:
   /opt/conclave-plugin/conclave consensus --mode=code-review --base-sha=\$BASE_SHA --head-sha=HEAD --description='SECOND PASS - State correctness review. Focus ONLY on: (1) State consistency: Can any operation leave the system in an invalid state? (2) Constraint propagation: When one value changes, are all dependent values updated? (3) Race conditions: Can concurrent operations produce inconsistent results? (4) Edge cases: What happens at boundaries (empty, full, overflow, underflow)? (5) Performance invariants: Are state update paths O(n) or better? Assume nothing from prior reviews. Verify each property by tracing through the code.'
3. Address any findings from the second review.
4. Run tests again.

Do NOT invoke any skills. Do NOT use the Skill tool. Do NOT brainstorm or write plans. Just implement, review, fix, done." \
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
    input_tokens: 0,
    output_tokens: 0,
    cache_read_tokens: 0,
    cache_creation_tokens: 0,
    turns: 0,
    tools_used: [],
    duration_ms: 0,
    total_cost_usd: 0
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
    } catch(e) { /* skip malformed lines */ }
  }
  fs.writeFileSync("/workspace/.thunderdome-metrics.json", JSON.stringify(metrics, null, 2));
  console.error("Metrics: " + JSON.stringify(metrics));
} catch(e) {
  console.error("Metrics extraction failed: " + e.message);
}
' "$OUTPUT_FILE" || true

exit $CLAUDE_EXIT
