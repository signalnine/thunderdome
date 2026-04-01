#!/bin/bash
set -e

# conclave-v7-double-review-sonnet: Conclave v7 plugin with double-review
# for state-heavy tasks. Uses the full conclave skill pipeline with Sonnet.
#
# Key change: using-conclave now detects state-heavy tasks and triggers
# a second code review pass focused on state consistency, constraint
# propagation, race conditions, and edge cases.
#
# Validated by Thunderdome data: +15-17pp on task-queue and analytics-dashboard.

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

TASK_PROMPT=$(cat "$TASK_DESCRIPTION")
OUTPUT_FILE=/workspace/.thunderdome-output.jsonl

set +e
claude -p \
  --model claude-sonnet-4-6 \
  --output-format stream-json \
  --verbose \
  --dangerously-skip-permissions \
  --plugin-dir /opt/conclave-plugin \
  --disallowed-tools "AskUserQuestion,EnterPlanMode" \
  --append-system-prompt "You are running in a headless benchmark environment. No human. No worktrees or branches — work directly here.

## Workflow

You have the Conclave skill system available. Use it SELECTIVELY:

**For implementation tasks** (build a feature, fix a bug, implement a spec):
- Invoke TDD skill, then implement directly. DO NOT brainstorm. DO NOT write formal plans. DO NOT use subagent-driven-development. Just read the task, write tests, write code, iterate.

**For ambiguous tasks** (vague requirements, design decisions needed):
- Invoke brainstorming only if requirements are genuinely unclear.

**Always:**
1. Read the task fully. Understand what exists before writing anything.
2. Write tests first (TDD), then implement.
3. Run tests, build, lint — fix ALL failures.
4. Request a code review (use the requesting-code-review skill).
5. Address all HIGH and MEDIUM priority findings from the review.

**State-Heavy Detection — IMPORTANT:**
Check if the task involves complex state management:
- Concurrent/async operations with ordering constraints
- Real-time updates where one operation's side effects affect others
- Constraint propagation (changing one value must update dependents)
- State machine with multiple transitions that must maintain invariants

If state-heavy: after addressing the first code review, request a SECOND code review using the Second-Pass Review prompt from the requesting-code-review skill. This focuses on state consistency, constraint propagation, race conditions, and edge cases. Address all findings from the second review too.

The goal is CORRECT, COMPLETE code — not following a process." \
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
          metrics.input_tokens += msg.usage.input_tokens || 0;
          metrics.output_tokens += msg.usage.output_tokens || 0;
          metrics.cache_read_tokens += msg.usage.cache_read_input_tokens || 0;
          metrics.cache_creation_tokens += msg.usage.cache_creation_input_tokens || 0;
        }
        metrics.turns += msg.num_turns || 0;
        metrics.duration_ms += msg.duration_ms || 0;
        metrics.total_cost_usd += msg.total_cost_usd || 0;
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
