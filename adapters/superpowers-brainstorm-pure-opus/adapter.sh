#!/bin/bash
set -e

# superpowers-brainstorm-pure-opus: Claude Code Opus + obra/superpowers brainstorming skill.
# True superpowers test — uses superpowers image (no conclave binary).
# Agent does single-agent brainstorming (no multi-agent consensus).

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

# Build a stripped-down plugin with ONLY brainstorming from obra/superpowers.
BRAINSTORM_PLUGIN=/tmp/brainstorm-only-plugin
mkdir -p "$BRAINSTORM_PLUGIN/.claude-plugin"
mkdir -p "$BRAINSTORM_PLUGIN/skills/brainstorming"
mkdir -p "$BRAINSTORM_PLUGIN/skills/using-superpowers"

cp /opt/superpowers-plugin/.claude-plugin/plugin.json "$BRAINSTORM_PLUGIN/.claude-plugin/"
cp -r /opt/superpowers-plugin/skills/brainstorming/* "$BRAINSTORM_PLUGIN/skills/brainstorming/"
cp -r /opt/superpowers-plugin/skills/using-superpowers/* "$BRAINSTORM_PLUGIN/skills/using-superpowers/"

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
  --append-system-prompt "You are running in a headless benchmark environment. There is no human to interact with. Do NOT attempt to create git worktrees or branches — work directly in the current directory.

MANDATORY WORKFLOW:

1. Read the task description to understand requirements.
2. Invoke the brainstorming skill IMMEDIATELY:
   Use the Skill tool with skill='brainstorming'
3. Follow the skill's process. Since there is no human to interact with:
   - Explore the project context yourself (check files, docs, existing code)
   - Answer the design questions yourself — propose 2-3 approaches, evaluate trade-offs, pick the best one
   - Work through: architecture, components, data flow, error handling, and testing strategy
   - Make your own design decisions autonomously
4. Write the final design to a plan file.
5. Then implement the design — build the solution based on the brainstormed design.
6. Run tests, build, and lint to verify your implementation.

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
