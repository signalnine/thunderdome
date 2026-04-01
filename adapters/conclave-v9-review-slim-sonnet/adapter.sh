#!/bin/bash
set -e

# conclave-v9-review-slim-sonnet: Two-pass implement-then-review adapter.
# Pass 1: Full implementation (identical to v8-combined-sonnet).
# Pass 2: Unconditional review+fix in a single claude -p invocation.
#          Reads existing code, reviews for correctness issues, fixes in place.
# No plugin, no skill overhead. Tests whether a hard-wired review pass
# can replicate the +15-17pp double-review effect seen with Opus consensus.

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
# PASS 1: Full implementation (identical to v8-combined-sonnet)
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
# PASS 2: Review + fix (unconditional)
# ──────────────────────────────────────────────────────────────────
echo "=== Pass 2: Review and fix ===" >&2

PASS2_OUTPUT_FILE=/workspace/.thunderdome-output-pass2.jsonl

PASS2_PROMPT="You are reviewing and improving an existing implementation in a headless benchmark environment. Code already exists in the working directory from a prior implementation pass.

## Original Task
$TASK_PROMPT

## Your Job

### Phase 1: Review (read everything first)
1. Read all source files in the working directory
2. Read all test files
3. Read CONTRACT.md if it exists
4. Run the test suite and read the COMPLETE output
5. Run build and lint if available

### Phase 2: Identify Issues
Review the implementation as a hostile code reviewer. Focus on:
1. **State consistency**: Can any operation leave the system in an invalid state?
2. **Constraint propagation**: When one value changes, are all dependent values updated?
3. **Race conditions**: Can concurrent operations produce inconsistent results?
4. **Edge cases**: What happens at boundaries (empty, full, overflow, underflow)?
5. **Missing requirements**: Compare implementation against the task spec — is anything missing?
6. **Test gaps**: Are there behaviors specified in the task that have no test coverage?
7. **Off-by-one errors**: Check loop bounds, array indices, range boundaries
8. **Error handling**: Are all error paths handled? Can errors cascade?

### Phase 3: Fix
Fix every issue you found. For each fix:
1. If a test is missing, write it first (watch it fail)
2. Apply the fix
3. Run tests to verify

### Phase 4: Verify
After all fixes:
- Run the full test suite — ALL must pass
- Run build and lint — must be clean
- Re-read your changes and verify they're correct

IMPORTANT: Code already exists. Read it first. Fix what's broken. Do not rewrite from scratch."

set +e
claude -p \
  --model claude-sonnet-4-6 \
  --output-format stream-json \
  --verbose \
  --dangerously-skip-permissions \
  --disallowed-tools "AskUserQuestion,EnterPlanMode" \
  --append-system-prompt "You are reviewing and fixing an existing implementation. Code is already in the working directory. Read everything, review as a hostile reviewer, fix issues, verify." \
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

# Use pass 2 exit code (final state of the code)
exit $PASS2_EXIT
