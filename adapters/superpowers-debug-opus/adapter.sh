#!/bin/bash
set -e

# superpowers-debug-opus: Claude Code Opus + systematic-debugging skill ONLY.
# Ablation study variant — isolates the "systematic-debugging" gene from Superpowers.
# Compared against vanilla claude-code-oauth-opus on debug tasks (T4, T6).

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

# Build a stripped-down plugin with ONLY systematic-debugging.
# This ensures the agent literally cannot see or invoke any other skills.
DEBUG_PLUGIN=/tmp/debug-only-plugin
mkdir -p "$DEBUG_PLUGIN/.claude-plugin"
mkdir -p "$DEBUG_PLUGIN/skills/systematic-debugging"
mkdir -p "$DEBUG_PLUGIN/skills/using-superpowers"

# Copy plugin manifest
cp /opt/superpowers-plugin/.claude-plugin/plugin.json "$DEBUG_PLUGIN/.claude-plugin/"

# Copy only the two skills we need
cp -r /opt/superpowers-plugin/skills/systematic-debugging/* "$DEBUG_PLUGIN/skills/systematic-debugging/"
cp -r /opt/superpowers-plugin/skills/using-superpowers/* "$DEBUG_PLUGIN/skills/using-superpowers/"

TASK_PROMPT=$(cat "$TASK_DESCRIPTION")
OUTPUT_FILE=/workspace/.thunderdome-output.jsonl

set +e
claude -p \
  --model claude-opus-4-6 \
  --output-format stream-json \
  --verbose \
  --dangerously-skip-permissions \
  --plugin-dir "$DEBUG_PLUGIN" \
  --disallowed-tools "AskUserQuestion,EnterPlanMode" \
  --append-system-prompt "You are running in a headless benchmark environment. There is no human to interact with. Do NOT attempt to create git worktrees or branches — work directly in the current directory.

MANDATORY WORKFLOW — you MUST follow this exactly:

1. Read the task description and run tests to see failures.
2. BEFORE attempting ANY fix, invoke the systematic-debugging skill:
   Use the Skill tool with skill='systematic-debugging'
3. Follow the skill's four-phase process EXACTLY for EACH bug:
   - Phase 1: Root cause investigation (read errors, reproduce, trace data flow)
   - Phase 2: Pattern analysis (find working examples, compare)
   - Phase 3: Hypothesis and testing (form hypothesis, test minimally)
   - Phase 4: Implementation (create fix, verify)
4. Do NOT skip phases. Do NOT guess at fixes. Do NOT batch multiple fixes.
5. Fix one bug at a time. Run tests after each fix. Then investigate the next failure.

This is non-negotiable. You must invoke the Skill tool for systematic-debugging before writing any fix." \
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
