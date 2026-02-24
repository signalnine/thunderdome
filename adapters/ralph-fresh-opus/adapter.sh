#!/bin/bash
set -e

# Ralph Loop Adapter (Fresh Context)
# Tests H3: Fresh-context Ralph loops outperform stale-context loops on marathon tasks
#
# Strategy: Run claude -p multiple times, each with fresh context.
# The workspace persists between iterations (code changes survive).
# The agent's conversation history resets each iteration.
#
# Iteration 1: Full task prompt
# Iteration 2+: Task prompt + "review existing code, run tests, fix remaining issues"
# Exit when: tests pass (after min 2 iterations) OR max iterations reached

MIN_ITERATIONS=2
MAX_ITERATIONS=4

[[ -f "$TASK_DESCRIPTION" ]] || { echo "Task file not found: $TASK_DESCRIPTION" >&2; exit 2; }

cd "$TASK_DIR"

export HOME=/tmp

# Set up OAuth credentials
if [ -f /tmp/.claude-credentials.json ]; then
  mkdir -p "$HOME/.claude"
  cp /tmp/.claude-credentials.json "$HOME/.claude/.credentials.json"
fi

ORIGINAL_PROMPT=$(cat "$TASK_DESCRIPTION")

# Aggregated metrics across all iterations
TOTAL_OUTPUT_FILES=()
ITERATION=0

for i in $(seq 1 $MAX_ITERATIONS); do
  ITERATION=$i
  echo "=== Ralph Loop: Iteration $i of $MAX_ITERATIONS ===" >&2

  # Build the prompt
  if [ $i -eq 1 ]; then
    ITER_PROMPT="$ORIGINAL_PROMPT"
  else
    # Run tests and capture output for the prompt
    cd "$TASK_DIR"
    TEST_OUTPUT=$(npm test 2>&1 || true)

    # Extract summary line
    SUMMARY=$(echo "$TEST_OUTPUT" | grep -E "Tests\s+" | tail -1)

    # Extract failure details (first 80 lines of failures)
    FAILURES=$(echo "$TEST_OUTPUT" | grep -B 1 -A 5 "FAIL\|AssertionError\|Error:" | head -80)

    ITER_PROMPT="$ORIGINAL_PROMPT

---

## Current Progress (Iteration $i of $MAX_ITERATIONS)

Previous iterations have made progress on this task. The workspace already contains code from earlier attempts.

**Test summary:** $SUMMARY

**Failure details (excerpt):**
\`\`\`
$FAILURES
\`\`\`

IMPORTANT: Start by reading the existing code in the workspace. Understand what has already been implemented. Then:
1. Run \`npm test\` to see the current state of ALL tests
2. Identify which phases/features are incomplete or broken
3. Fix issues and implement missing functionality
4. Do NOT rewrite working code — build on what exists
5. Run \`npm test\` again to verify your changes"
  fi

  # Write prompt to temp file to avoid shell escaping issues
  printf '%s' "$ITER_PROMPT" > /tmp/ralph-iter-prompt.txt

  OUTPUT_FILE="/workspace/.thunderdome-output-iter${i}.jsonl"
  TOTAL_OUTPUT_FILES+=("$OUTPUT_FILE")

  # Clear Claude Code session files between iterations so each starts fresh
  rm -rf /tmp/.claude/projects 2>/dev/null || true

  set +e
  claude -p \
    --model claude-opus-4-6 \
    --output-format stream-json \
    --verbose \
    --dangerously-skip-permissions \
    --disallowed-tools "AskUserQuestion,EnterPlanMode" \
    --append-system-prompt "You are running in a headless benchmark environment. There is no human to interact with. Focus on implementation: read the task, write code, run tests, iterate until all tests pass. This is iteration $i of $MAX_ITERATIONS in a Ralph loop — each iteration gets fresh context but the workspace persists from previous iterations." \
    -- "$(cat /tmp/ralph-iter-prompt.txt)" \
    > "$OUTPUT_FILE" 2>"/workspace/.thunderdome-stderr-iter${i}.log"
  CLAUDE_EXIT=$?
  set -e

  echo "Iteration $i: Claude exited with code $CLAUDE_EXIT" >&2

  # After minimum iterations, check if tests pass
  if [ $i -ge $MIN_ITERATIONS ]; then
    cd "$TASK_DIR"
    set +e
    npm test > /tmp/ralph-test-check.log 2>&1
    TEST_EXIT=$?
    set -e

    if [ $TEST_EXIT -eq 0 ]; then
      echo "=== All tests pass after iteration $i! ===" >&2
      break
    else
      SUMMARY=$(grep -E "Tests\s+" /tmp/ralph-test-check.log | tail -1)
      echo "Iteration $i tests: $SUMMARY — continuing" >&2
    fi
  fi
done

echo "=== Ralph Loop complete: $ITERATION iterations ===" >&2

# Aggregate metrics across all iterations
cat > /tmp/ralph-extract-metrics.js <<'METRICS_JS'
const fs = require("fs");
try {
  const metrics = {
    input_tokens: 0, output_tokens: 0,
    cache_read_tokens: 0, cache_creation_tokens: 0,
    turns: 0, tools_used: [], duration_ms: 0,
    total_cost_usd: 0, iterations: 0,
    note: "ralph-fresh-context"
  };
  const toolsSeen = new Set();

  const iterFiles = process.argv.slice(2);
  metrics.iterations = iterFiles.length;

  for (const file of iterFiles) {
    if (!fs.existsSync(file)) continue;
    console.error("Processing: " + file);

    const lines = fs.readFileSync(file, "utf8").split("\n");
    for (const line of lines) {
      if (!line.trim()) continue;
      try {
        const msg = JSON.parse(line);
        if (msg.type === "result") {
          if (msg.usage) {
            metrics.input_tokens += msg.usage.input_tokens || 0;
            metrics.output_tokens += msg.usage.output_tokens || 0;
            metrics.cache_read_tokens += msg.usage.cache_read_input_tokens || 0;
            metrics.cache_creation_tokens += msg.usage.cache_creation_input_tokens || 0;
          }
          metrics.turns += msg.num_turns || 0;
          metrics.duration_ms += msg.duration_ms || 0;
          metrics.total_cost_usd += msg.total_cost_usd || 0;
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
  }

  metrics.total_cost_usd = Math.round(metrics.total_cost_usd * 10000) / 10000;

  fs.writeFileSync("/workspace/.thunderdome-metrics.json", JSON.stringify(metrics, null, 2));
  console.error("Metrics: " + JSON.stringify(metrics));
} catch(e) {
  console.error("Metrics extraction failed: " + e.message);
  fs.writeFileSync("/workspace/.thunderdome-metrics.json",
    JSON.stringify({note: "extraction-failed", error: e.message}, null, 2));
}
METRICS_JS

node /tmp/ralph-extract-metrics.js "${TOTAL_OUTPUT_FILES[@]}" || true

# Copy final iteration output as the canonical one
cp "${TOTAL_OUTPUT_FILES[$((ITERATION-1))]}" /workspace/.thunderdome-output.jsonl 2>/dev/null || true

exit 0
