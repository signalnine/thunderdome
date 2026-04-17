#!/bin/bash
set -e

# sonnet-plans: Sonnet 4.6 + writing-plans skill.
# Cost-optimization experiment — highest-ROI gene (plans) on cheaper model.

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

# Build a stripped-down plugin with ONLY writing-plans.
PLANS_PLUGIN=/tmp/plans-only-plugin
mkdir -p "$PLANS_PLUGIN/.claude-plugin"
mkdir -p "$PLANS_PLUGIN/skills/writing-plans"
mkdir -p "$PLANS_PLUGIN/skills/using-superpowers"

cp /opt/superpowers-plugin/.claude-plugin/plugin.json "$PLANS_PLUGIN/.claude-plugin/"
cp -r /opt/superpowers-plugin/skills/writing-plans/* "$PLANS_PLUGIN/skills/writing-plans/"
cp -r /opt/superpowers-plugin/skills/using-superpowers/* "$PLANS_PLUGIN/skills/using-superpowers/"

TASK_PROMPT=$(cat "$TASK_DESCRIPTION")
OUTPUT_FILE=/workspace/.thunderdome-output.jsonl

set +e
claude -p \
  --model claude-sonnet-4-6 \
  --output-format stream-json \
  --verbose \
  --dangerously-skip-permissions \
  --plugin-dir "$PLANS_PLUGIN" \
  --disallowed-tools "AskUserQuestion,EnterPlanMode" \
  --append-system-prompt "You are running in a headless benchmark environment. There is no human to interact with.

MANDATORY WORKFLOW:

1. Read the task description to understand requirements.
2. Invoke the writing-plans skill IMMEDIATELY:
   Use the Skill tool with skill='writing-plans'
3. Follow the skill to create a detailed implementation plan with bite-sized tasks, exact file paths, complete code examples, and test commands.
4. Save the plan (you can save it anywhere, the location doesn't matter for scoring).
5. Then implement the plan yourself — execute each task in order. You do NOT need to use subagent-driven-development or executing-plans. Just implement directly.
6. Run tests, build, and lint to verify your implementation.

You MUST invoke the writing-plans skill and create a plan before writing any implementation code. This is non-negotiable." \
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
