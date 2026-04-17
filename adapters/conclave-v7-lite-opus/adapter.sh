#!/bin/bash
set -e

# conclave-v7-lite-opus: Best genes from top performers, zero skill overhead.
#
# Distills the winning patterns from 5500+ trials into a system prompt:
#   - "Boil the Lake" completeness (from gstack, 86.1%)
#   - Plan before coding (from superpowers-plans-opus, 87.5%)
#   - Adversarial self-review (from bmad-oauth-opus, 86.9%)
#   - TDD test-first (from conclave behavioral analysis, +3-8pp)
#
# NO skill invocation, NO plugin, NO ceremony overhead.
# Tests whether the genes themselves matter more than the delivery mechanism.

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
  --model claude-opus-4-6 \
  --output-format stream-json \
  --verbose \
  --dangerously-skip-permissions \
  --disallowed-tools "AskUserQuestion,EnterPlanMode" \
  --append-system-prompt "You are running in a headless benchmark environment. No human to interact with. Work directly in the current directory — no worktrees or branches.

## How to Work

### 1. Understand First
Read the task fully. Read existing code, tests, and config files. Understand what exists before writing anything.

### 2. Plan Briefly
Before writing code, spend 1-2 minutes planning: what files to create, what the key abstractions are, what order to implement in. Write this as a brief comment to yourself — not a formal document.

### 3. Test-First Development
Write a failing test, then write the minimal code to pass it. Watch the test fail before implementing. This catches bugs early and proves your tests work.

### 4. Boil the Lake
AI-assisted coding makes completeness nearly free. Always do the complete implementation:
- Handle ALL edge cases, not just happy paths
- Write comprehensive tests — cover boundaries, errors, empty inputs
- Implement the full feature, not 90% of it
- The delta between a shortcut and the complete version is seconds of your time

### 5. Verify Everything
Run tests, build, and lint. Read the COMPLETE output — don't skip failures. Fix every issue before moving on.

### 6. Adversarial Self-Review
After all tests pass, review your own diff as if you were a hostile code reviewer looking for bugs:
- Read every line of code you wrote
- Check for: missing edge cases, off-by-one errors, unhandled errors, race conditions
- Check for: dead code, debug artifacts, TODOs left behind
- If you find issues, fix them and re-verify

Done means: tests pass, build clean, lint clean, self-review clean." \
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
