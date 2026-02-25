#!/bin/bash
set -e

# superpowers-review-verify-opus: Claude Code Opus + review + verify skills stacked.
# Gene stacking study — combines the #1 scorer (review) with the cheapest top-tier (verify).

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

# Build a plugin with both requesting-code-review AND verification-before-completion.
STACKED_PLUGIN=/tmp/review-verify-plugin
mkdir -p "$STACKED_PLUGIN/.claude-plugin"
mkdir -p "$STACKED_PLUGIN/skills/requesting-code-review"
mkdir -p "$STACKED_PLUGIN/skills/verification-before-completion"
mkdir -p "$STACKED_PLUGIN/skills/using-superpowers"

cp /opt/conclave-plugin/.claude-plugin/plugin.json "$STACKED_PLUGIN/.claude-plugin/"
cp -r /opt/conclave-plugin/skills/requesting-code-review/* "$STACKED_PLUGIN/skills/requesting-code-review/"
cp -r /opt/conclave-plugin/skills/verification-before-completion/* "$STACKED_PLUGIN/skills/verification-before-completion/"
cp -r /opt/conclave-plugin/skills/using-superpowers/* "$STACKED_PLUGIN/skills/using-superpowers/" 2>/dev/null || \
  cp -r /opt/conclave-plugin/skills/using-conclave/* "$STACKED_PLUGIN/skills/using-superpowers/" 2>/dev/null || true

TASK_PROMPT=$(cat "$TASK_DESCRIPTION")
OUTPUT_FILE=/workspace/.thunderdome-output.jsonl

set +e
claude -p \
  --model claude-opus-4-6 \
  --output-format stream-json \
  --verbose \
  --dangerously-skip-permissions \
  --plugin-dir "$STACKED_PLUGIN" \
  --disallowed-tools "AskUserQuestion,EnterPlanMode" \
  --append-system-prompt "You are running in a headless benchmark environment. There is no human to interact with.

MANDATORY WORKFLOW:

1. Read the task description and implement the solution using your best judgment.
2. Run tests, build, and lint to verify your implementation works.
3. Commit your changes: git add -A && git commit -m 'implementation'
4. MANDATORY STEP 1 — Code Review: Invoke the requesting-code-review skill:
   Use the Skill tool with skill='requesting-code-review'
   Follow the skill's guidance to run multi-agent consensus code review.
   The conclave binary is at /opt/conclave-plugin/conclave
   Use: /opt/conclave-plugin/conclave consensus --mode=code-review --base-sha=\$(git log --reverse --format=%H | head -1) --head-sha=HEAD --description='Review implementation'
   Address any HIGH PRIORITY or MEDIUM PRIORITY findings.
5. MANDATORY STEP 2 — Verification: Invoke the verification-before-completion skill:
   Use the Skill tool with skill='verification-before-completion'
   Follow the skill's Iron Law: NO COMPLETION CLAIMS WITHOUT FRESH VERIFICATION EVIDENCE.
   Run npm test, npm run build, and npm run lint FRESH. Read the FULL output.
   If anything fails, fix it and re-verify.
6. Only claim completion after BOTH review AND verification pass.

You MUST invoke BOTH skills before finishing. This is non-negotiable." \
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
