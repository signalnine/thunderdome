#!/bin/bash
set -e

# conclave-v8-outcomes-sonnet: Harness-enforced iteration with isolated grading.
#
# Inspired by Anthropic's Managed Agents "Outcomes" pattern:
# - Agent works in pass 1 with v8 methodology (no self-review)
# - Harness runs real validation (tests + build + lint)
# - If failures: structured feedback fed to FRESH context (new claude -p)
# - Up to MAX_ITERATIONS passes
#
# Key difference from v8-eval: each iteration is a completely new context
# window. The agent can't anchor on its previous reasoning. And the grader
# is deterministic test execution, not an LLM.

MAX_ITERATIONS=3

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

# Shared metrics aggregation
TOTAL_INPUT=0
TOTAL_OUTPUT=0
TOTAL_CACHE_READ=0
TOTAL_CACHE_CREATE=0
TOTAL_TURNS=0
TOTAL_DURATION=0
TOTAL_COST=0
ALL_TOOLS=""

# ──────────────────────────────────────────────────────────────────
# extract_and_accumulate: Parse NDJSON output and add to running totals
# ──────────────────────────────────────────────────────────────────
extract_and_accumulate() {
  local output_file="$1"
  local result
  result=$(node -e '
const fs = require("fs");
try {
  const lines = fs.readFileSync(process.argv[1], "utf8").split("\n");
  const m = { input: 0, output: 0, cache_read: 0, cache_create: 0, turns: 0, duration: 0, cost: 0, tools: [] };
  const seen = new Set();
  for (const line of lines) {
    if (!line.trim()) continue;
    try {
      const msg = JSON.parse(line);
      if (msg.type === "result") {
        if (msg.usage) {
          m.input += msg.usage.input_tokens || 0;
          m.output += msg.usage.output_tokens || 0;
          m.cache_read += msg.usage.cache_read_input_tokens || 0;
          m.cache_create += msg.usage.cache_creation_input_tokens || 0;
        }
        m.turns += msg.num_turns || 0;
        m.duration += msg.duration_ms || 0;
        m.cost += msg.total_cost_usd || 0;
      }
      if (msg.type === "assistant" && msg.message && Array.isArray(msg.message.content)) {
        for (const block of msg.message.content) {
          if (block.type === "tool_use" && block.name && !seen.has(block.name)) {
            seen.add(block.name);
            m.tools.push(block.name);
          }
        }
      }
    } catch(e) {}
  }
  console.log(JSON.stringify(m));
} catch(e) {
  console.log("{}");
}
' "$output_file" 2>/dev/null)

  local input output cache_read cache_create turns duration cost tools
  input=$(echo "$result" | node -e 'const d=JSON.parse(require("fs").readFileSync("/dev/stdin","utf8"));console.log(d.input||0)' 2>/dev/null) || input=0
  output=$(echo "$result" | node -e 'const d=JSON.parse(require("fs").readFileSync("/dev/stdin","utf8"));console.log(d.output||0)' 2>/dev/null) || output=0
  cache_read=$(echo "$result" | node -e 'const d=JSON.parse(require("fs").readFileSync("/dev/stdin","utf8"));console.log(d.cache_read||0)' 2>/dev/null) || cache_read=0
  cache_create=$(echo "$result" | node -e 'const d=JSON.parse(require("fs").readFileSync("/dev/stdin","utf8"));console.log(d.cache_create||0)' 2>/dev/null) || cache_create=0
  turns=$(echo "$result" | node -e 'const d=JSON.parse(require("fs").readFileSync("/dev/stdin","utf8"));console.log(d.turns||0)' 2>/dev/null) || turns=0
  duration=$(echo "$result" | node -e 'const d=JSON.parse(require("fs").readFileSync("/dev/stdin","utf8"));console.log(d.duration||0)' 2>/dev/null) || duration=0
  cost=$(echo "$result" | node -e 'const d=JSON.parse(require("fs").readFileSync("/dev/stdin","utf8"));console.log(d.cost||0)' 2>/dev/null) || cost=0
  tools=$(echo "$result" | node -e 'const d=JSON.parse(require("fs").readFileSync("/dev/stdin","utf8"));console.log((d.tools||[]).join(","))' 2>/dev/null) || tools=""

  TOTAL_INPUT=$((TOTAL_INPUT + input))
  TOTAL_OUTPUT=$((TOTAL_OUTPUT + output))
  TOTAL_CACHE_READ=$((TOTAL_CACHE_READ + cache_read))
  TOTAL_CACHE_CREATE=$((TOTAL_CACHE_CREATE + cache_create))
  TOTAL_TURNS=$((TOTAL_TURNS + turns))
  TOTAL_DURATION=$((TOTAL_DURATION + duration))
  # Cost is floating point, accumulate via node
  TOTAL_COST=$(node -e "console.log($TOTAL_COST + $cost)" 2>/dev/null) || TOTAL_COST="$cost"
  if [ -n "$tools" ]; then
    ALL_TOOLS="${ALL_TOOLS:+$ALL_TOOLS,}$tools"
  fi
}

# ──────────────────────────────────────────────────────────────────
# run_validation: Execute tests + build + lint, capture output
# Returns 0 if all pass, 1 if any fail. Sets VALIDATION_FEEDBACK.
# ──────────────────────────────────────────────────────────────────
run_validation() {
  VALIDATION_FEEDBACK=""
  local any_failed=0

  # Tests
  local test_output=""
  local test_exit=0
  if [ -f package.json ]; then
    test_output=$(npm test 2>&1) || test_exit=$?
  fi

  if [ "$test_exit" -ne 0 ]; then
    any_failed=1
    # Truncate to last 100 lines (most relevant failures)
    local truncated
    truncated=$(echo "$test_output" | tail -100)
    VALIDATION_FEEDBACK="${VALIDATION_FEEDBACK}## Test Failures (exit code $test_exit)
\`\`\`
$truncated
\`\`\`

"
  fi

  # Build
  local build_output=""
  local build_exit=0
  if [ -f package.json ]; then
    build_output=$(npm run build 2>&1) || build_exit=$?
  fi

  if [ "$build_exit" -ne 0 ]; then
    any_failed=1
    local truncated
    truncated=$(echo "$build_output" | tail -50)
    VALIDATION_FEEDBACK="${VALIDATION_FEEDBACK}## Build Errors (exit code $build_exit)
\`\`\`
$truncated
\`\`\`

"
  fi

  # Lint
  local lint_output=""
  local lint_exit=0
  if [ -f package.json ]; then
    lint_output=$(npm run lint 2>&1) || lint_exit=$?
  fi

  if [ "$lint_exit" -ne 0 ]; then
    any_failed=1
    local truncated
    truncated=$(echo "$lint_output" | tail -50)
    VALIDATION_FEEDBACK="${VALIDATION_FEEDBACK}## Lint Errors (exit code $lint_exit)
\`\`\`
$truncated
\`\`\`

"
  fi

  return $any_failed
}

# ──────────────────────────────────────────────────────────────────
# PASS 1: Implementation with v8 methodology (no self-review)
# ──────────────────────────────────────────────────────────────────
ITERATION=1
echo "=== Iteration $ITERATION/$MAX_ITERATIONS: Initial implementation ===" >&2

OUTPUT_FILE="/workspace/.thunderdome-output-iter${ITERATION}.jsonl"

set +e
claude -p \
  --model claude-sonnet-4-6 \
  --output-format stream-json \
  --verbose \
  --dangerously-skip-permissions \
  --disallowed-tools "AskUserQuestion,EnterPlanMode" \
  --append-system-prompt "You are running in a headless benchmark environment. No human to interact with. Work directly in the current directory -- no worktrees or branches.

## How to Work

### 1. Understand First
Read the task fully. Read existing code, tests, and config files. Understand what exists before writing anything.

### 2. Write a Contract BEFORE Any Code
Before writing any implementation, create a CONTRACT.md file that defines:

1. **Every behavior** the finished code must exhibit -- be specific and exhaustive
2. **How to verify each behavior** -- the exact test, command, or check that proves it works
3. **What done looks like** for each criterion -- expected output, return value, or state

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

Done means: all contract criteria pass, tests pass, build clean, lint clean." \
  -- "$TASK_PROMPT" \
  > "$OUTPUT_FILE" 2>/workspace/.thunderdome-stderr-iter${ITERATION}.log
LAST_EXIT=$?
set -e

echo "  Iteration $ITERATION exit: $LAST_EXIT" >&2
extract_and_accumulate "$OUTPUT_FILE"

# ──────────────────────────────────────────────────────────────────
# ITERATION LOOP: Validate and iterate with fresh context
# ──────────────────────────────────────────────────────────────────
while [ "$ITERATION" -lt "$MAX_ITERATIONS" ]; do
  echo "=== Validation check after iteration $ITERATION ===" >&2

  set +e
  run_validation
  VAL_EXIT=$?
  set -e

  if [ "$VAL_EXIT" -eq 0 ]; then
    echo "  All validation passed -- done after $ITERATION iteration(s)" >&2
    break
  fi

  ITERATION=$((ITERATION + 1))
  echo "=== Iteration $ITERATION/$MAX_ITERATIONS: Fix with harness feedback (fresh context) ===" >&2

  OUTPUT_FILE="/workspace/.thunderdome-output-iter${ITERATION}.jsonl"

  # Build the feedback prompt -- fresh context, only sees failures + task
  FIX_PROMPT="You are fixing an existing implementation in a headless benchmark environment. Code already exists in the working directory from a previous attempt. The harness ran validation and found failures.

## Original Task
$TASK_PROMPT

## Validation Results (from isolated harness -- not your assessment)
$VALIDATION_FEEDBACK
## Your Job
1. Read the existing code in the working directory -- do NOT start from scratch
2. Analyze the specific failures above -- these are real test/build/lint outputs
3. Fix the root causes. Focus on what actually failed, not everything
4. Run the tests yourself to verify your fixes work
5. Keep fixing until all tests pass, build succeeds, and lint is clean

CRITICAL: This is iteration $ITERATION of $MAX_ITERATIONS. Code already exists. Read it first. Fix what's broken. Do not rewrite from scratch."

  set +e
  claude -p \
    --model claude-sonnet-4-6 \
    --output-format stream-json \
    --verbose \
    --dangerously-skip-permissions \
    --disallowed-tools "AskUserQuestion,EnterPlanMode" \
    --append-system-prompt "You are fixing an existing implementation based on automated test feedback. Code is already in the working directory. Read it, understand the failures, fix them. Do not start over." \
    -- "$FIX_PROMPT" \
    > "$OUTPUT_FILE" 2>/workspace/.thunderdome-stderr-iter${ITERATION}.log
  LAST_EXIT=$?
  set -e

  echo "  Iteration $ITERATION exit: $LAST_EXIT" >&2
  extract_and_accumulate "$OUTPUT_FILE"
done

# ──────────────────────────────────────────────────────────────────
# METRICS: Write combined metrics from all iterations
# ──────────────────────────────────────────────────────────────────
echo "=== Writing combined metrics ($ITERATION iteration(s)) ===" >&2

# Deduplicate tools
UNIQUE_TOOLS=$(echo "$ALL_TOOLS" | tr ',' '\n' | sort -u | tr '\n' ',' | sed 's/,$//')

node -e "
const fs = require('fs');
const tools = '$UNIQUE_TOOLS'.split(',').filter(Boolean);
const metrics = {
  input_tokens: $TOTAL_INPUT,
  output_tokens: $TOTAL_OUTPUT,
  cache_read_tokens: $TOTAL_CACHE_READ,
  cache_creation_tokens: $TOTAL_CACHE_CREATE,
  turns: $TOTAL_TURNS,
  tools_used: tools,
  duration_ms: $TOTAL_DURATION,
  total_cost_usd: $TOTAL_COST,
  iterations: $ITERATION,
  max_iterations: $MAX_ITERATIONS
};
fs.writeFileSync('/workspace/.thunderdome-metrics.json', JSON.stringify(metrics, null, 2));
console.error('Metrics: ' + JSON.stringify(metrics));
" || true

exit $LAST_EXIT
