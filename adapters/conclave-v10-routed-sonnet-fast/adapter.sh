#!/bin/bash
set -e

# conclave-v10-routed-sonnet-fast: v10 routing with Sonnet 4.6 on both
# paths + fastMode enabled. Since Opus 4.7 Fast regressed 9pp at 2.9x cost
# vs v10 Opus 4.6, this tests whether Sonnet 4.6 + fastMode can reach the
# same quality at lower cost. Routing is kept (Haiku classify) for parity
# with v10-routed but becomes a no-op since both paths are Sonnet.

[[ -f "$TASK_DESCRIPTION" ]] || { echo "Task file not found: $TASK_DESCRIPTION" >&2; exit 2; }

cd "$TASK_DIR"

export HOME=/tmp
mkdir -p "$HOME/.claude"

if [ -f /tmp/.claude-credentials.json ]; then
  cp /tmp/.claude-credentials.json "$HOME/.claude/.credentials.json"
fi

# Enable fastMode via user settings (the only way to turn it on in -p mode).
cat > "$HOME/.claude/settings.json" <<'SETTINGS_EOF'
{"fastMode": true}
SETTINGS_EOF

if [ -n "$PROXY_URL" ]; then
  export ANTHROPIC_BASE_URL="$PROXY_URL"
fi

TASK_PROMPT=$(cat "$TASK_DESCRIPTION")
OUTPUT_FILE=/workspace/.thunderdome-output.jsonl

# ──────────────────────────────────────────────────────────────────
# ROUTING: Use Haiku to classify task complexity
# ──────────────────────────────────────────────────────────────────
echo "=== Routing: classifying task complexity ===" >&2

ROUTING_PROMPT="You are a task complexity classifier. Read the task description below and classify it as HARD or EASY.

A task is HARD if it has ANY of these characteristics:
- Complex state management with multiple interacting components that must stay consistent
- Concurrent or async operations with ordering constraints
- Algorithmic reasoning requiring careful logic (scheduling, constraint solving, graph traversal)
- Ambiguous specifications requiring significant inference about intended behavior
- Multiple subsystems that must coordinate (e.g., real-time updates + persistence + API)
- Complex data transformations with edge cases (overflow, empty, boundary conditions)

A task is EASY if it is:
- A straightforward CRUD feature or API endpoint
- A bug fix with clear reproduction steps
- A well-specified feature with clear inputs/outputs
- Adding tests, documentation, or configuration
- Simple refactoring or code cleanup

Respond with ONLY the single word HARD or EASY. Nothing else.

=== TASK DESCRIPTION ===
$TASK_PROMPT"

# Call Haiku via claude CLI (fastest, cheapest)
ROUTING_RESULT=$(claude -p \
  --model claude-haiku-4-5-20251001 \
  --max-turns 1 \
  -- "$ROUTING_PROMPT" 2>/dev/null || echo "EASY")

# Extract just HARD or EASY from response (in case of extra whitespace/text)
if echo "$ROUTING_RESULT" | grep -qi "HARD"; then
  SELECTED_MODEL="claude-sonnet-4-6"
  echo "  Routing decision: HARD -> Sonnet 4.6 (fastMode)" >&2
else
  SELECTED_MODEL="claude-sonnet-4-6"
  echo "  Routing decision: EASY -> Sonnet 4.6 (fastMode)" >&2
fi

# ──────────────────────────────────────────────────────────────────
# IMPLEMENTATION: no-review v8 prompt with selected model
# ──────────────────────────────────────────────────────────────────
echo "=== Implementation: $SELECTED_MODEL ===" >&2

set +e
claude -p \
  --model "$SELECTED_MODEL" \
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

Done means: all contract criteria pass, tests pass, build clean, lint clean." \
  -- "$TASK_PROMPT" \
  > "$OUTPUT_FILE" 2>/workspace/.thunderdome-stderr.log
CLAUDE_EXIT=$?
set -e

# ──────────────────────────────────────────────────────────────────
# METRICS
# ──────────────────────────────────────────────────────────────────
node -e '
const fs = require("fs");
try {
  const lines = fs.readFileSync(process.argv[1], "utf8").split("\n");
  const metrics = {
    input_tokens: 0, output_tokens: 0, cache_read_tokens: 0,
    cache_creation_tokens: 0, turns: 0, tools_used: [],
    duration_ms: 0, total_cost_usd: 0,
    routed_model: process.argv[2]
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
' "$OUTPUT_FILE" "$SELECTED_MODEL" || true

exit $CLAUDE_EXIT
