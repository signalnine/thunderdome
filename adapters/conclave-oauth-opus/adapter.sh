#!/bin/bash
set -e

# Validate inputs
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

# Non-interactive mode for Conclave skills:
#   - brainstorming: auto-uses Consensus Autopilot
#   - executing-plans: auto-proceeds between batches
#   - finishing-a-development-branch: auto-merges locally
#   - writing-plans: auto-uses subagent-driven execution
export CONCLAVE_NON_INTERACTIVE=1

TASK_PROMPT=$(cat "$TASK_DESCRIPTION")
OUTPUT_FILE=/workspace/.thunderdome-output.jsonl

# Run Claude Code (Opus) with the Conclave plugin loaded.
# OAuth auth — no API key needed.
#
# The append-system-prompt enforces the brainstorm > plan > implement workflow:
#   1. Invoke conclave:brainstorming to explore the problem space
#   2. Invoke conclave:writing-plans to produce a concrete plan
#   3. Invoke conclave:subagent-driven-development to execute the plan
set +e
claude -p \
  --model claude-opus-4-6 \
  --output-format stream-json \
  --verbose \
  --dangerously-skip-permissions \
  --plugin-dir /opt/conclave-plugin \
  --disallowed-tools "AskUserQuestion,EnterPlanMode" \
  --append-system-prompt "You are running in a headless benchmark environment. There is no human to interact with. CONCLAVE_NON_INTERACTIVE=1 is set — all interactive prompts auto-resolve.

YOU MUST USE CONCLAVE SKILLS. This is non-negotiable. Every task requires skill invocations via the Skill tool. Do NOT skip skills, even for simple tasks.

MANDATORY WORKFLOW — choose the right path based on the task:

FOR BUGFIX / DEBUGGING / RECOVERY TASKS (fixing bugs, investigating failures, broken code, test failures, disaster recovery):
1. Invoke conclave:systematic-debugging. This skill handles the ENTIRE cycle: investigation, root cause analysis, fix, and verification. Let it run to completion.
2. That is it. Do NOT invoke writing-plans or subagent-driven-development for debug tasks. The debugging skill is self-contained.

FOR GREENFIELD / FEATURE TASKS (building new code, adding features, new functionality):
1. BRAINSTORM: Invoke conclave:brainstorming FIRST to explore approaches.
2. PLAN: Invoke conclave:writing-plans to produce a step-by-step implementation plan.
3. IMPLEMENT: Invoke conclave:subagent-driven-development to execute the plan.
4. VERIFY: Invoke conclave:verification-before-completion, then run tests, build, and lint.
5. FINISH: Invoke conclave:finishing-a-development-branch to merge work back to the main branch.

RULES:
- You MUST invoke skills. No exceptions, even for simple tasks.
- For debug/bugfix/recovery tasks: ONLY use conclave:systematic-debugging. Do NOT add extra planning or worktree overhead.
- For greenfield/feature tasks: follow the full 5-step pipeline above. Do NOT write implementation code before completing steps 1-2.
- Git worktrees ARE allowed for greenfield tasks — skills like subagent-driven-development use them. Ensure all work is merged back to the main branch before finishing." \
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
