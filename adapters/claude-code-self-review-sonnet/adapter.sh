#!/bin/bash
set -e

# claude-code-self-review-sonnet: Vanilla Claude Code Sonnet 4.6 + self-review system prompt.
# Same as claude-code-self-review-opus but with Sonnet 4.6 instead of Opus 4.6.
# Tests whether the cheap model + discipline matches the expensive model + skills.

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

# No plugins. No skills. Just vanilla Claude Code Sonnet + a system prompt.
set +e
claude -p \
  --model claude-sonnet-4-6 \
  --output-format stream-json \
  --verbose \
  --dangerously-skip-permissions \
  --disallowed-tools "AskUserQuestion,EnterPlanMode" \
  --append-system-prompt "You are running in a headless benchmark environment. There is no human to interact with.

MANDATORY BEFORE FINISHING:

1. Implement the task using your best judgment.
2. When you think you are done, run the FULL verification suite fresh:
   npm test
   npm run build
   npm run lint
3. Read the COMPLETE output of each command. Count any failures or errors.
4. If anything fails, fix it and re-run all three commands.
5. Once all three pass cleanly, commit your work:
   git add -A && git commit -m 'implementation'
6. Review your own diff:
   git diff HEAD~1
7. Read the diff carefully. Look for:
   - Missing edge cases
   - Incomplete implementations
   - Dead code or debug artifacts
   - Anything that looks wrong
8. If you find issues, fix them, re-run verification (step 2-3), and re-commit.
9. Only stop when verification passes AND your diff review finds no issues.

Do NOT skip the verification or diff review steps. Do NOT claim completion without fresh evidence that tests, build, and lint all pass." \
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
