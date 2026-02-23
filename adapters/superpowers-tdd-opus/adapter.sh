#!/bin/bash
set -e

# superpowers-tdd-opus: Claude Code Opus + forced TDD skill.
# Ablation study variant — isolates the "test-driven development" gene.
# Compared against vanilla claude-code-oauth-opus on greenfield tasks.

[[ -f "$TASK_DESCRIPTION" ]] || { echo "Task file not found: $TASK_DESCRIPTION" >&2; exit 2; }

cd "$TASK_DIR"

# Use /tmp as HOME so Claude Code can write session files
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

# Build a stripped-down plugin with ONLY test-driven-development.
TDD_PLUGIN=/tmp/tdd-only-plugin
mkdir -p "$TDD_PLUGIN/.claude-plugin"
mkdir -p "$TDD_PLUGIN/skills/test-driven-development"
mkdir -p "$TDD_PLUGIN/skills/using-superpowers"

# Copy plugin manifest
cp /opt/superpowers-plugin/.claude-plugin/plugin.json "$TDD_PLUGIN/.claude-plugin/"

# Copy only the two skills we need
cp -r /opt/superpowers-plugin/skills/test-driven-development/* "$TDD_PLUGIN/skills/test-driven-development/"
cp -r /opt/superpowers-plugin/skills/using-superpowers/* "$TDD_PLUGIN/skills/using-superpowers/"

TASK_PROMPT=$(cat "$TASK_DESCRIPTION")
OUTPUT_FILE=/workspace/.thunderdome-output.jsonl

set +e
claude -p \
  --model claude-opus-4-6 \
  --output-format stream-json \
  --verbose \
  --dangerously-skip-permissions \
  --plugin-dir "$TDD_PLUGIN" \
  --disallowed-tools "AskUserQuestion,EnterPlanMode" \
  --append-system-prompt "You are running in a headless benchmark environment. There is no human to interact with. Do NOT attempt to create git worktrees or branches — work directly in the current directory.

MANDATORY WORKFLOW — you MUST follow this exactly:

1. Read the task description to understand requirements.
2. Invoke the test-driven-development skill IMMEDIATELY:
   Use the Skill tool with skill='test-driven-development'
3. Follow the TDD Red-Green-Refactor cycle for EVERY piece of functionality:
   - RED: Write a failing test first. Run it. Confirm it fails.
   - GREEN: Write the minimum code to make the test pass. Run tests. Confirm green.
   - REFACTOR: Clean up while keeping tests green.
   - Repeat for the next piece of functionality.
4. Do NOT write implementation code before its test exists and has been seen to fail.
5. Do NOT write all tests at once — one test at a time, then implement, then next test.
6. Build up the implementation incrementally through the TDD cycle.

This is non-negotiable. You must invoke the Skill tool for test-driven-development before writing any code." \
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
