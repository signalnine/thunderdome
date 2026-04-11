#!/bin/bash
set -e

# conclave-v8-eval-sonnet: Two-pass adapter with evaluator feedback.
# Pass 1: Full implementation (identical to v8-combined-sonnet).
# Pass 2: If validation tests fail, run evaluator diagnosis, then a second
#          claude -p with evaluator feedback + existing code context.

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

SYSTEM_PROMPT='You are running in a headless benchmark environment. No human to interact with. Work directly in the current directory — no worktrees or branches.

## How to Work

### 1. Understand First
Read the task fully. Read existing code, tests, and config files. Understand what exists before writing anything.

### 2. Write a Contract BEFORE Any Code
Before writing any implementation, create a CONTRACT.md file that defines:

1. **Every behavior** the finished code must exhibit — be specific and exhaustive
2. **How to verify each behavior** — the exact test, command, or check that proves it works
3. **What done looks like** for each criterion — expected output, return value, or state

Example:
\`\`\`
- [ ] POST /api/users creates a new user → test: POST returns 201 with user object
- [ ] Duplicate email returns 409 → test: second POST with same email returns 409
- [ ] Empty name rejected → test: POST with empty name returns 400
\`\`\`

This contract is your definition of done. You are not finished until every criterion passes.

### 3. Test-First Development (MANDATORY — NOT OPTIONAL)
For each contract criterion, you MUST write a failing test BEFORE any implementation code.

**The process:**
1. Pick the next contract criterion
2. Write a test that verifies it
3. Run it — watch it FAIL (this proves the test works)
4. Write the minimal code to make it pass
5. Run it — watch it PASS
6. Repeat for the next criterion

**If you catch yourself writing implementation without a test first, STOP IMMEDIATELY.**
Delete the implementation code. Write the test first. Then re-implement.
This is not a suggestion. This is not optional. Tests are how you prove your code works.
No tests = no proof = not done.

### 4. Boil the Lake
AI-assisted coding makes completeness nearly free. Always do the complete implementation:
- Handle ALL edge cases, not just happy paths
- Write comprehensive tests — cover boundaries, errors, empty inputs
- Implement the full feature, not 90% of it

### 5. Verify Against Contract
After implementation, go through CONTRACT.md line by line:
- Run each verification check
- Fix ALL failures before moving on
- Do not stop until every criterion in the contract passes

### 6. Adversarial Self-Review
After all contract criteria pass, review your own diff as if you were a hostile code reviewer:
- Read every line of code you wrote
- Check for: missing edge cases, off-by-one errors, unhandled errors, race conditions
- Check for: dead code, debug artifacts, TODOs left behind
- If you find issues, fix them and re-verify against the contract

Done means: all contract criteria pass, tests pass, build clean, lint clean, self-review clean.'

# ──────────────────────────────────────────────────────────────────
# PASS 1: Full implementation (same as v8-combined-sonnet)
# ──────────────────────────────────────────────────────────────────
echo "=== Pass 1: Implementation ===" >&2

set +e
claude -p \
  --model claude-sonnet-4-6 \
  --output-format stream-json \
  --verbose \
  --dangerously-skip-permissions \
  --disallowed-tools "AskUserQuestion,EnterPlanMode" \
  --append-system-prompt "$SYSTEM_PROMPT" \
  -- "$TASK_PROMPT" \
  > "$OUTPUT_FILE" 2>/workspace/.thunderdome-stderr-pass1.log
PASS1_EXIT=$?
set -e

echo "  Pass 1 exit: $PASS1_EXIT" >&2

# ──────────────────────────────────────────────────────────────────
# TEST CHECK: Run validation tests to see if pass 2 is needed
# ──────────────────────────────────────────────────────────────────
echo "=== Test Check ===" >&2

TEST_OUTPUT=""
TEST_EXIT=0

# Auto-detect test runner
if [ -f package.json ]; then
  TEST_OUTPUT=$(npm test 2>&1) || TEST_EXIT=$?
elif [ -f Cargo.toml ]; then
  TEST_OUTPUT=$(cargo test 2>&1) || TEST_EXIT=$?
elif [ -f pyproject.toml ] || [ -f setup.py ]; then
  TEST_OUTPUT=$(python -m pytest 2>&1) || TEST_EXIT=$?
elif [ -f go.mod ]; then
  TEST_OUTPUT=$(go test ./... 2>&1) || TEST_EXIT=$?
else
  echo "  No test runner detected, skipping pass 2" >&2
  TEST_EXIT=0
fi

if [ "$TEST_EXIT" -eq 0 ]; then
  echo "  Tests passed — no pass 2 needed" >&2
  # Extract metrics and exit
  node -e '
const fs = require("fs");
try {
  const lines = fs.readFileSync(process.argv[1], "utf8").split("\n");
  const metrics = {
    input_tokens: 0, output_tokens: 0, cache_read_tokens: 0,
    cache_creation_tokens: 0, turns: 0, tools_used: [],
    duration_ms: 0, total_cost_usd: 0, pass2_ran: false
  };
  const toolsSeen = new Set();
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
  fs.writeFileSync("/workspace/.thunderdome-metrics.json", JSON.stringify(metrics, null, 2));
  console.error("Metrics: " + JSON.stringify(metrics));
} catch(e) {
  console.error("Metrics extraction failed: " + e.message);
}
' "$OUTPUT_FILE" || true
  exit $PASS1_EXIT
fi

echo "  Tests failed (exit $TEST_EXIT) — running evaluator" >&2

# ──────────────────────────────────────────────────────────────────
# EVALUATOR: Diagnose failures using conclave's eval engine
# ──────────────────────────────────────────────────────────────────
echo "=== Evaluator ===" >&2

# Truncate test output for the evaluator prompt
TRUNCATED_TEST=$(echo "$TEST_OUTPUT" | head -200)

EVAL_PROMPT="You are a diagnostic assistant. Analyze the test/build/lint failures below, identify root causes, and specify the single most impactful fix. Base your conclusions only on the provided spec, test output, and source files. If the root cause appears to be outside the provided files, say so explicitly rather than speculating.

## Task Spec
$TASK_PROMPT

## Test Output (verbatim)
\`\`\`
$TRUNCATED_TEST
\`\`\`

## Instructions
Respond using EXACTLY this template. Maximum 5 bullets per section.
Do not restate raw test output verbatim — synthesize into root causes.

## Failing Tests
- [group by root cause, not by test name]

## Unmet Requirements
- [only spec violations evidenced by actual failures]

## Priority Fix
- [exactly one highest-leverage fix, one sentence]

## Suggested Approach
- [3-5 concrete steps at the design/logic level, no code]"

set +e
EVAL_OUTPUT=$(echo "$EVAL_PROMPT" | claude -p \
  --model claude-sonnet-4-6 \
  --output-format text \
  --dangerously-skip-permissions \
  2>/workspace/.thunderdome-stderr-eval.log)
EVAL_EXIT=$?
set -e

if [ "$EVAL_EXIT" -ne 0 ] || [ -z "$EVAL_OUTPUT" ]; then
  echo "  Evaluator failed (exit $EVAL_EXIT), skipping pass 2" >&2
  # Still extract pass 1 metrics
  node -e '
const fs = require("fs");
try {
  const lines = fs.readFileSync(process.argv[1], "utf8").split("\n");
  const metrics = {
    input_tokens: 0, output_tokens: 0, cache_read_tokens: 0,
    cache_creation_tokens: 0, turns: 0, tools_used: [],
    duration_ms: 0, total_cost_usd: 0, pass2_ran: false, eval_failed: true
  };
  const toolsSeen = new Set();
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
    } catch(e) {}
  }
  fs.writeFileSync("/workspace/.thunderdome-metrics.json", JSON.stringify(metrics, null, 2));
} catch(e) {}
' "$OUTPUT_FILE" || true
  exit $PASS1_EXIT
fi

echo "  Evaluator diagnosis received" >&2

# ──────────────────────────────────────────────────────────────────
# PASS 2: Fix implementation using evaluator feedback
# ──────────────────────────────────────────────────────────────────
echo "=== Pass 2: Fix with evaluator feedback ===" >&2

PASS2_OUTPUT_FILE=/workspace/.thunderdome-output-pass2.jsonl

PASS2_PROMPT="You are continuing work on a task in a headless benchmark environment. The first implementation attempt has been made — code already exists in the working directory. Tests were run and some failed.

## Original Task
$TASK_PROMPT

## Evaluator Diagnosis
The following analysis was produced by a separate diagnostic agent after examining the test failures and your code:

$EVAL_OUTPUT

## Your Job
1. Read the existing code in the working directory — do NOT start from scratch
2. Focus on the Priority Fix and Suggested Approach above
3. Fix the specific issues identified — do not rewrite everything
4. Run the tests to verify your fixes work
5. Keep fixing until tests pass or you've addressed all issues

IMPORTANT: Code already exists. Read it first. Fix what's broken. Do not rewrite from scratch."

set +e
claude -p \
  --model claude-sonnet-4-6 \
  --output-format stream-json \
  --verbose \
  --dangerously-skip-permissions \
  --disallowed-tools "AskUserQuestion,EnterPlanMode" \
  --append-system-prompt "You are fixing an existing implementation based on evaluator feedback. Code is already in the working directory. Read it, understand the failures, fix them." \
  -- "$PASS2_PROMPT" \
  > "$PASS2_OUTPUT_FILE" 2>/workspace/.thunderdome-stderr-pass2.log
PASS2_EXIT=$?
set -e

echo "  Pass 2 exit: $PASS2_EXIT" >&2

# ──────────────────────────────────────────────────────────────────
# METRICS: Combine pass 1 + pass 2
# ──────────────────────────────────────────────────────────────────
node -e '
const fs = require("fs");
try {
  const files = [process.argv[1], process.argv[2]];
  const metrics = {
    input_tokens: 0, output_tokens: 0, cache_read_tokens: 0,
    cache_creation_tokens: 0, turns: 0, tools_used: [],
    duration_ms: 0, total_cost_usd: 0, pass2_ran: true
  };
  const toolsSeen = new Set();
  for (const file of files) {
    let lines;
    try { lines = fs.readFileSync(file, "utf8").split("\n"); } catch(e) { continue; }
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
  fs.writeFileSync("/workspace/.thunderdome-metrics.json", JSON.stringify(metrics, null, 2));
  console.error("Metrics: " + JSON.stringify(metrics));
} catch(e) {
  console.error("Metrics extraction failed: " + e.message);
}
' "$OUTPUT_FILE" "$PASS2_OUTPUT_FILE" || true

exit $PASS2_EXIT
