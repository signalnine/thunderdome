#!/bin/bash
set -e

# conclave-v8-no-review-ralph-sonnet: Ralph loop ablation.
# Same no-review prompt as conclave-v8-no-review-sonnet, but with
# fresh-context retry loop (2-4 iterations, test gate between).
# Tests whether the ralph-loop retry mechanism adds value.

MIN_ITERATIONS=2
MAX_ITERATIONS=4

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

ORIGINAL_PROMPT=$(cat "$TASK_DESCRIPTION")
TOTAL_OUTPUT_FILES=()
ITERATION=0

SYSTEM_PROMPT="You are running in a headless benchmark environment. No human to interact with. Work directly in the current directory -- no worktrees or branches.

## How to Work

### 1. Understand First
Read the task fully. Read existing code, tests, and config files. Understand what exists before writing anything.

### 2. Write a Contract BEFORE Any Code
Before writing any implementation, create a CONTRACT.md file that defines:

1. **Every behavior** the finished code must exhibit -- be specific and exhaustive
2. **How to verify each behavior** -- the exact test, command, or check that proves it works
3. **What done looks like** for each criterion -- expected output, return value, or state

Example:
\`\`\`
- [ ] POST /api/users creates a new user -> test: POST returns 201 with user object
- [ ] Duplicate email returns 409 -> test: second POST with same email returns 409
- [ ] Empty name rejected -> test: POST with empty name returns 400
\`\`\`

This contract is your definition of done. You are not finished until every criterion passes.

### 3. Test-First Development (MANDATORY -- NOT OPTIONAL)
For each contract criterion, you MUST write a failing test BEFORE any implementation code.

**The process:**
1. Pick the next contract criterion
2. Write a test that verifies it
3. Run it -- watch it FAIL (this proves the test works)
4. Write the minimal code to make it pass
5. Run it -- watch it PASS
6. Repeat for the next criterion

**If you catch yourself writing implementation without a test first, STOP IMMEDIATELY.**
Delete the implementation code. Write the test first. Then re-implement.
This is not a suggestion. This is not optional. Tests are how you prove your code works.
No tests = no proof = not done.

### 4. Boil the Lake
AI-assisted coding makes completeness nearly free. Always do the complete implementation:
- Handle ALL edge cases, not just happy paths
- Write comprehensive tests -- cover boundaries, errors, empty inputs
- Implement the full feature, not 90% of it

### 5. Verify Against Contract
After implementation, go through CONTRACT.md line by line:
- Run each verification check
- Fix ALL failures before moving on
- Do not stop until every criterion in the contract passes

Done means: all contract criteria pass, tests pass, build clean, lint clean."

for i in $(seq 1 $MAX_ITERATIONS); do
  ITERATION=$i
  echo "=== Ralph Loop: Iteration $i of $MAX_ITERATIONS ===" >&2

  if [ $i -eq 1 ]; then
    ITER_PROMPT="$ORIGINAL_PROMPT"
  else
    cd "$TASK_DIR"
    TEST_OUTPUT=$(npm test 2>&1 || true)
    SUMMARY=$(echo "$TEST_OUTPUT" | grep -E "Tests\s+" | tail -1)
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
4. Do NOT rewrite working code -- build on what exists
5. Run \`npm test\` again to verify your changes"
  fi

  printf '%s' "$ITER_PROMPT" > /tmp/ralph-iter-prompt.txt

  OUTPUT_FILE="/workspace/.thunderdome-output-iter${i}.jsonl"
  TOTAL_OUTPUT_FILES+=("$OUTPUT_FILE")

  rm -rf /tmp/.claude/projects 2>/dev/null || true

  set +e
  claude -p \
    --model claude-sonnet-4-6 \
    --output-format stream-json \
    --verbose \
    --dangerously-skip-permissions \
    --disallowed-tools "AskUserQuestion,EnterPlanMode" \
    --append-system-prompt "$SYSTEM_PROMPT

This is iteration $i of $MAX_ITERATIONS in a Ralph loop -- each iteration gets fresh context but the workspace persists from previous iterations." \
    -- "$(cat /tmp/ralph-iter-prompt.txt)" \
    > "$OUTPUT_FILE" 2>"/workspace/.thunderdome-stderr-iter${i}.log"
  CLAUDE_EXIT=$?
  set -e

  echo "Iteration $i: Claude exited with code $CLAUDE_EXIT" >&2

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
      echo "Iteration $i tests: $SUMMARY -- continuing" >&2
    fi
  fi
done

echo "=== Ralph Loop complete: $ITERATION iterations ===" >&2

cat > /tmp/ralph-extract-metrics.js <<'METRICS_JS'
const fs = require("fs");
try {
  const metrics = {
    input_tokens: 0, output_tokens: 0,
    cache_read_tokens: 0, cache_creation_tokens: 0,
    turns: 0, tools_used: [], duration_ms: 0,
    total_cost_usd: 0, iterations: 0,
    note: "ralph-no-review-ablation"
  };
  const toolsSeen = new Set();
  const iterFiles = process.argv.slice(2);
  metrics.iterations = iterFiles.length;
  for (const file of iterFiles) {
    if (!fs.existsSync(file)) continue;
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

cp "${TOTAL_OUTPUT_FILES[$((ITERATION-1))]}" /workspace/.thunderdome-output.jsonl 2>/dev/null || true

exit 0
