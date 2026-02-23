#!/bin/bash
set -e

# conclave-review-opus: Claude Code Opus + multi-agent consensus code review.
#
# Ablation study variant — isolates the "consensus code review" gene from
# Conclave's full skill pipeline (brainstorm → plan → implement → verify).
#
# Flow:
#   1. Agent codes freely (vanilla Claude Code behavior)
#   2. Agent commits its work and runs `conclave consensus --mode=code-review`
#   3. Agent addresses high/medium priority findings from the review
#   4. Done

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

TASK_PROMPT=$(cat "$TASK_DESCRIPTION")
OUTPUT_FILE=/workspace/.thunderdome-output.jsonl

# Run Claude Code (Opus) with the Conclave plugin loaded but NO mandatory
# skill workflow. The only instruction is to use consensus code review after
# finishing implementation — no brainstorming, no planning skills, no TDD.
set +e
claude -p \
  --model claude-opus-4-6 \
  --output-format stream-json \
  --verbose \
  --dangerously-skip-permissions \
  --plugin-dir /opt/conclave-plugin \
  --disallowed-tools "AskUserQuestion,EnterPlanMode,Skill" \
  --append-system-prompt "You are running in a headless benchmark environment. There is no human to interact with.

WORK FREELY. Implement the task using your best judgment — no mandatory workflows, no skill invocations, no planning ceremonies. Just write good code.

AFTER you have finished implementing and all tests pass, do ONE code review cycle:

1. Commit your changes: git add -A && git commit -m 'implementation'
2. Find the base commit: BASE_SHA=\$(git log --reverse --format=%H | head -1)
3. Run multi-agent consensus code review:
   /opt/conclave-plugin/conclave consensus --mode=code-review --base-sha=\$BASE_SHA --head-sha=HEAD --description='Review implementation for correctness, edge cases, and code quality'
4. Read the review output carefully. Address any HIGH PRIORITY or MEDIUM PRIORITY findings by making fixes.
5. Run tests again to make sure your fixes didn't break anything.

Do NOT invoke any skills. Do NOT use the Skill tool. Do NOT brainstorm or write plans. Just implement, review, fix, done." \
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
