#!/bin/bash
set -e

# superpowers-review-opus: Claude Code Opus + forced requesting-code-review skill.
# Ablation study — isolates the "skill-guided code review" gene.
#
# Key difference from conclave-review-opus: that adapter hardcodes the review
# steps in the system prompt with Skills DISABLED. This adapter enables the
# Skill tool and lets the requesting-code-review skill guide the agent.

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

# Build a stripped-down plugin with ONLY requesting-code-review.
# Include the code-reviewer.md and multi-review.sh assets the skill references.
REVIEW_PLUGIN=/tmp/review-only-plugin
mkdir -p "$REVIEW_PLUGIN/.claude-plugin"
mkdir -p "$REVIEW_PLUGIN/skills/requesting-code-review"
mkdir -p "$REVIEW_PLUGIN/skills/using-superpowers"

cp /opt/conclave-plugin/.claude-plugin/plugin.json "$REVIEW_PLUGIN/.claude-plugin/"
cp -r /opt/conclave-plugin/skills/requesting-code-review/* "$REVIEW_PLUGIN/skills/requesting-code-review/"
# using-superpowers is the meta-skill that teaches skill invocation
cp -r /opt/conclave-plugin/skills/using-superpowers/* "$REVIEW_PLUGIN/skills/using-superpowers/" 2>/dev/null || \
  cp -r /opt/conclave-plugin/skills/using-conclave/* "$REVIEW_PLUGIN/skills/using-superpowers/" 2>/dev/null || true

TASK_PROMPT=$(cat "$TASK_DESCRIPTION")
OUTPUT_FILE=/workspace/.thunderdome-output.jsonl

set +e
claude -p \
  --model claude-opus-4-6 \
  --output-format stream-json \
  --verbose \
  --dangerously-skip-permissions \
  --plugin-dir "$REVIEW_PLUGIN" \
  --disallowed-tools "AskUserQuestion,EnterPlanMode" \
  --append-system-prompt "You are running in a headless benchmark environment. There is no human to interact with.

MANDATORY WORKFLOW:

1. Read the task description and implement the solution using your best judgment.
2. Run tests, build, and lint to verify your implementation works.
3. Commit your changes: git add -A && git commit -m 'implementation'
4. MANDATORY: Invoke the requesting-code-review skill:
   Use the Skill tool with skill='requesting-code-review'
5. Follow the skill's guidance to run multi-agent consensus code review.
   The conclave binary is at /opt/conclave-plugin/conclave
   Use: /opt/conclave-plugin/conclave consensus --mode=code-review --base-sha=\$(git log --reverse --format=%H | head -1) --head-sha=HEAD --description='Review implementation'
6. Address any HIGH PRIORITY or MEDIUM PRIORITY findings from the review.
7. Run tests again to make sure fixes didn't break anything.

You MUST invoke the requesting-code-review skill after implementation. This is non-negotiable." \
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
