#!/bin/bash
set -e

# shit-full-sonnet: SHIT (Spec-Harness Implementation Trail) plugin -- full reification chain.
#
# Tests whether spec-driven development with 6-layer verification outperforms
# simpler methodology prompts (v8-combined self-review, etc.)
#
# Flow:
# 1. Agent runs /shit:init to scaffold spec structure
# 2. Agent writes formal specs before coding (reification chain)
# 3. Agent implements with provenance markers linking code to specs
# 4. Agent runs /shit:verify for 6-layer verification
# 5. Agent fixes issues found by verification

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

# Write a minimal CLAUDE.md so /shit:verify knows how to build/test
cat > /workspace/CLAUDE.md << 'CLAUDEMD'
# Project

## Build and Test Commands

```bash
npm run build    # Build the project
npm run lint     # Run linter
npm test         # Run test suite
```

## Coverage

Coverage is collected via Vitest's built-in coverage reporter when available.
CLAUDEMD

set +e
claude -p \
  --model claude-sonnet-4-6 \
  --output-format stream-json \
  --verbose \
  --dangerously-skip-permissions \
  --disallowed-tools "AskUserQuestion,EnterPlanMode" \
  --plugin-dir /opt/shit-plugin \
  --append-system-prompt "You are running in a headless benchmark environment. No human to interact with. Work directly in the current directory -- no worktrees or branches.

## Your Methodology: Spec-Driven Development (SHIT Plugin)

You have the SHIT (Spec-Harness Implementation Trail) plugin available. Use it to drive your work through the full reification chain: spec first, then code, then verify.

### Step 1: Initialize
Run the /shit:init slash command to scaffold the specs/ directory structure.

### Step 2: Understand the Task
Read the task description fully. Read existing code, tests, and config files. Understand what exists before writing anything.

### Step 3: Write Formal Specifications
Before writing ANY implementation code, create specification files under specs/2-spec/:

Create a spec module file (e.g., specs/2-spec/001-implementation.md) that defines:
- Every requirement with a unique ID (e.g., REQ-IMPL-001)
- For each requirement: a description, properties that must hold, and testable assertions
- Use this format:

\`\`\`markdown
# Module: Implementation

## REQ-IMPL-001: [Requirement Name]
**Description:** [What must be true]
**Properties:**
- [Property 1 that must hold]
- [Property 2 that must hold]
**Testable Assertion:** [Specific assertion that can be verified]
\`\`\`

Update specs/2-spec/000-index.md to reference your module.

### Step 4: Implement with Provenance
When writing code, add provenance markers linking back to requirements:
\`\`\`
// @provenance: REQ-IMPL-001
\`\`\`

When writing tests, add the same markers to link tests to requirements.

### Step 5: Test-First When Possible
Write tests before or alongside implementation. Every requirement should have at least one test.

### Step 6: Boil the Lake
Handle ALL edge cases, not just happy paths. Write comprehensive tests. Implement the full feature, not 90% of it.

### Step 7: Run Verification
Run the /shit:verify slash command. This runs 6 verification layers:
- Build health, test health, coverage
- Spec conformance and provenance coverage
- Invariant checks against your spec properties
- Gap analysis

Fix any issues the verification finds. Re-run until clean.

Done means: all specs satisfied, all tests pass, build clean, lint clean, verification clean." \
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
