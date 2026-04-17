#!/bin/bash
set -e

# conclave-v7-boil-opus: Conclave plugin + gstack "Boil the Lake" philosophy.
#
# Tests whether adding completeness mindset to conclave's existing TDD
# methodology improves scores. gstack alone scores 86.1% vs conclave-v6 76.6%.
# The hypothesis is that completeness + TDD > either alone.

[[ -f "$TASK_DESCRIPTION" ]] || { echo "Task file not found: $TASK_DESCRIPTION" >&2; exit 2; }

cd "$TASK_DIR"

export HOME=/tmp
export CONCLAVE_NON_INTERACTIVE=1

if [ -f /tmp/.claude-credentials.json ]; then
  mkdir -p "$HOME/.claude"
  cp /tmp/.claude-credentials.json "$HOME/.claude/.credentials.json"
fi

if [ -n "$PROXY_URL" ]; then
  export ANTHROPIC_BASE_URL="$PROXY_URL"
fi

# Inject gstack completeness philosophy into workspace CLAUDE.md
if [ -f CLAUDE.md ]; then
  EXISTING=$(cat CLAUDE.md)
  cat > CLAUDE.md << 'GSTACK_EOF'
# Completeness Principle — Boil the Lake

AI-assisted coding makes the marginal cost of completeness near-zero. Always do the complete implementation:

- If Option A is the complete implementation (all edge cases, 100% coverage) and Option B is a shortcut — **always choose A**. The delta is seconds.
- Handle ALL edge cases, not just happy paths. Write comprehensive tests. Implement the full feature, not 90%.
- Don't skip the last 10% to "save time" — that 10% costs seconds with AI assistance.

GSTACK_EOF
  echo "" >> CLAUDE.md
  echo "$EXISTING" >> CLAUDE.md
else
  cat > CLAUDE.md << 'GSTACK_EOF'
# Completeness Principle — Boil the Lake

AI-assisted coding makes the marginal cost of completeness near-zero. Always do the complete implementation:

- If Option A is the complete implementation (all edge cases, 100% coverage) and Option B is a shortcut — **always choose A**. The delta is seconds.
- Handle ALL edge cases, not just happy paths. Write comprehensive tests. Implement the full feature, not 90%.
- Don't skip the last 10% to "save time" — that 10% costs seconds with AI assistance.

GSTACK_EOF
fi

TASK_PROMPT=$(cat "$TASK_DESCRIPTION")
OUTPUT_FILE=/workspace/.thunderdome-output.jsonl

set +e
claude -p \
  --model claude-opus-4-6 \
  --output-format stream-json \
  --verbose \
  --dangerously-skip-permissions \
  --plugin-dir /opt/conclave-plugin \
  --disallowed-tools "AskUserQuestion,EnterPlanMode" \
  --append-system-prompt "You are running in a headless benchmark environment. No human to interact with. No worktrees or branches — work directly in the current directory.

Follow the skill system loaded by your plugin. The using-conclave skill tells you which skill to invoke based on the task type. Follow it.

ADDITIONALLY: Read the CLAUDE.md in this workspace — it contains a completeness principle. Apply it to everything you build. Complete implementations, comprehensive tests, all edge cases handled.

Do NOT skip skill invocation. The skills + completeness principle together produce the highest quality work." \
  -- "$TASK_PROMPT" \
  > "$OUTPUT_FILE" 2>/workspace/.thunderdome-stderr.log
CLAUDE_EXIT=$?
set -e

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
