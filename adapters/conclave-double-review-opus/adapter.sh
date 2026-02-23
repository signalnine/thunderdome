#!/bin/bash
set -e

# conclave-double-review-opus: Claude Code Opus + design review + code review.
#
# Stacked ablation — combines both consensus genes:
#   1. Pre-implementation: conclave consensus --mode=general-prompt on task
#   2. Agent implements freely
#   3. Post-implementation: conclave consensus --mode=code-review on diff
#   4. Agent addresses findings
#
# Uses OAuth only (no API keys). The consensus binary needs API keys to call
# Claude/Gemini/Codex, so both consensus steps will fail gracefully. The design
# review falls back to the plain prompt. The code review step is in the system
# prompt — the agent will attempt the command, see it fail, and likely do a
# structured self-review of its own diff instead.
#
# This tests whether the "structured review discipline" helps independently
# of actual multi-model consensus.

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

# ── Stage 0: Attempt multi-agent design review ─────────────────────
# Will fail without API keys — falls back to plain prompt.
echo "Attempting multi-agent design review..." >&2
DESIGN_FILE=/tmp/design-review.md

set +e
/opt/conclave-plugin/conclave consensus \
  --mode=general-prompt \
  --prompt="You are reviewing a software development task BEFORE implementation begins. Analyze the task and recommend the best architecture and approach.

Provide specific, actionable recommendations:
1. FILE STRUCTURE: What files to create, what each file's responsibility is
2. KEY ABSTRACTIONS: Core interfaces, types, and data structures to define first
3. DATA FLOW: How data moves through the system (input → processing → output)
4. EDGE CASES: Non-obvious gotchas, boundary conditions, error scenarios to handle
5. IMPLEMENTATION ORDER: What to build first, second, third (dependency order)
6. TESTING STRATEGY: What to test, critical test cases, testing approach

Be concrete. Name specific files, functions, types. Don't be generic." \
  --context="$TASK_PROMPT" \
  --stage1-timeout=120 \
  --stage2-timeout=120 \
  > "$DESIGN_FILE" 2>/workspace/.thunderdome-design-stderr.log
DESIGN_EXIT=$?
set -e

# Build the enriched prompt
if [ $DESIGN_EXIT -eq 0 ] && [ -s "$DESIGN_FILE" ]; then
  DESIGN_REVIEW=$(cat "$DESIGN_FILE")
  echo "Design review complete ($(wc -c < "$DESIGN_FILE") bytes)" >&2
  ENRICHED_PROMPT="## Architecture Recommendations (Multi-Agent Consensus)

Before you start, three independent AI models (Claude, Gemini, Codex) analyzed this task and a chairman synthesized their recommendations. Use these as guidance — they are suggestions, not requirements. Override them if you see a better approach.

${DESIGN_REVIEW}

---

## Task Description

${TASK_PROMPT}"
else
  echo "Design review unavailable (exit=$DESIGN_EXIT), proceeding without it" >&2
  ENRICHED_PROMPT="$TASK_PROMPT"
fi

# ── Stage 1: Agent implementation + post-implementation review ──────
set +e
claude -p \
  --model claude-opus-4-6 \
  --output-format stream-json \
  --verbose \
  --dangerously-skip-permissions \
  --plugin-dir /opt/conclave-plugin \
  --disallowed-tools "AskUserQuestion,EnterPlanMode,Skill" \
  --append-system-prompt "You are running in a headless benchmark environment. There is no human to interact with. Do NOT attempt to create git worktrees or branches — work directly in the current directory.

WORK FREELY. Implement the task using your best judgment — no mandatory workflows, no skill invocations, no planning ceremonies. Just write good code.

AFTER you have finished implementing and all tests pass, do ONE code review cycle:

1. Commit your changes: git add -A && git commit -m 'implementation'
2. Find the base commit: BASE_SHA=\$(git log --reverse --format=%H | head -1)
3. Run multi-agent consensus code review:
   /opt/conclave-plugin/conclave consensus --mode=code-review --base-sha=\$BASE_SHA --head-sha=HEAD --description='Review implementation for correctness, edge cases, and code quality'
4. Read the review output carefully. Address any HIGH PRIORITY or MEDIUM PRIORITY findings by making fixes.
5. If the consensus command fails, review your own diff manually: git diff \$BASE_SHA HEAD. Look for bugs, edge cases, missing error handling, and test gaps. Fix what you find.
6. Run tests again to make sure your fixes didn't break anything.

Do NOT invoke any skills. Do NOT use the Skill tool. Do NOT brainstorm or write plans. Just implement, review, fix, done." \
  -- "$ENRICHED_PROMPT" \
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
