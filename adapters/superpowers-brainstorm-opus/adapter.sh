#!/bin/bash
set -e

# superpowers-brainstorm-opus: Claude Code Opus + forced brainstorming skill.
# Ablation study — isolates the "brainstorm before coding" gene.
#
# The brainstorming skill has an "autopilot" mode that uses multi-agent
# consensus to answer design questions automatically — required for headless.

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

# Build a stripped-down plugin with ONLY brainstorming.
BRAINSTORM_PLUGIN=/tmp/brainstorm-only-plugin
mkdir -p "$BRAINSTORM_PLUGIN/.claude-plugin"
mkdir -p "$BRAINSTORM_PLUGIN/skills/brainstorming"
mkdir -p "$BRAINSTORM_PLUGIN/skills/using-superpowers"

cp /opt/conclave-plugin/.claude-plugin/plugin.json "$BRAINSTORM_PLUGIN/.claude-plugin/"
cp -r /opt/conclave-plugin/skills/brainstorming/* "$BRAINSTORM_PLUGIN/skills/brainstorming/"
cp -r /opt/conclave-plugin/skills/using-superpowers/* "$BRAINSTORM_PLUGIN/skills/using-superpowers/" 2>/dev/null || \
  cp -r /opt/conclave-plugin/skills/using-conclave/* "$BRAINSTORM_PLUGIN/skills/using-superpowers/" 2>/dev/null || true

TASK_PROMPT=$(cat "$TASK_DESCRIPTION")
OUTPUT_FILE=/workspace/.thunderdome-output.jsonl

set +e
claude -p \
  --model claude-opus-4-6 \
  --output-format stream-json \
  --verbose \
  --dangerously-skip-permissions \
  --plugin-dir "$BRAINSTORM_PLUGIN" \
  --disallowed-tools "AskUserQuestion,EnterPlanMode" \
  --append-system-prompt "You are running in a headless benchmark environment. There is no human to interact with.

MANDATORY WORKFLOW:

1. Read the task description to understand requirements.
2. Invoke the brainstorming skill IMMEDIATELY:
   Use the Skill tool with skill='brainstorming'
3. Follow the skill's process. Since there is no human, select AUTOPILOT MODE.
   The conclave binary is at /opt/conclave-plugin/conclave
   Use: /opt/conclave-plugin/conclave consensus --mode=general-prompt --prompt=\"\$QUESTION\" --context=\"\$CONTEXT\"
4. Let consensus answer each design question. Work through architecture, components, data flow, error handling, and testing.
5. Write the final design to a plan file.
6. Then implement the design yourself — build the solution based on the brainstormed design.
7. Run tests, build, and lint to verify your implementation.

You MUST invoke the brainstorming skill and complete the design process before writing any implementation code. This is non-negotiable." \
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
