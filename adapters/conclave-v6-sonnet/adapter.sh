#!/bin/bash
set -e

# conclave-v6-sonnet: Conclave v6 with Sonnet 4.6 — task classifier + full skill library.
#
# Tests the new Conclave v6 experience: the using-conclave meta-skill auto-routes
# to the right skill (TDD, brainstorming, verification) based on task type.
# No forced skill invocation — the plugin hooks inject the task classifier,
# and the agent uses the Skill tool to invoke skills as directed.
#
# Key changes from previous Conclave adapters:
#   - Skill tool is ENABLED (not disallowed) — skills fire via task classifier
#   - CONCLAVE_NON_INTERACTIVE=1 — brainstorming uses single-agent Autopilot
#   - Minimal system prompt — lets the plugin's own guidance drive behavior
#   - Sonnet 4.6 model (benchmark data shows Sonnet + methodology beats Opus)

[[ -f "$TASK_DESCRIPTION" ]] || { echo "Task file not found: $TASK_DESCRIPTION" >&2; exit 2; }

cd "$TASK_DIR"

export HOME=/tmp
export CONCLAVE_NON_INTERACTIVE=1

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

# Run Claude Code (Sonnet) with the full Conclave plugin.
# The plugin's SessionStart hook injects the using-conclave skill content,
# which includes the task classifier and completion gate.
# The Skill tool is enabled so the agent can invoke skills as directed.
set +e
claude -p \
  --model claude-sonnet-4-6 \
  --output-format stream-json \
  --verbose \
  --dangerously-skip-permissions \
  --plugin-dir /opt/conclave-plugin \
  --disallowed-tools "AskUserQuestion,EnterPlanMode" \
  --append-system-prompt "You are running in a headless benchmark environment. There is no human to interact with. Do NOT attempt to create git worktrees or branches — work directly in the current directory.

Follow the skill system loaded by your plugin. The using-conclave skill has already been injected — it contains a task classifier that tells you which skill to invoke based on the task type. Follow it.

Do NOT skip skill invocation. Do NOT work without invoking the appropriate skill first. The skills contain the methodology that produces high-quality work." \
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
