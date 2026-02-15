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

TASK_PROMPT=$(cat "$TASK_DESCRIPTION")

# --- Gas Station Adapter (OAuth + Opus) ---
# Single-agent variant: runs one Claude session with Gas Town context injection.
# For the full multi-agent pipeline, see gastown-oauth-opus.
echo "=== Setting up Gas Station workspace ==="

# The harness clones with --branch <tag> --depth 1 which leaves HEAD detached.
# Gas Town needs a real branch. Create one from detached HEAD if needed.
DEFAULT_BRANCH=$(git -C /workspace symbolic-ref --short HEAD 2>/dev/null || echo "")
if [ -z "$DEFAULT_BRANCH" ]; then
  DEFAULT_BRANCH="main"
  git -C /workspace checkout -b "$DEFAULT_BRANCH" 2>/dev/null || true
fi
echo "Branch: $DEFAULT_BRANCH"

# 1. Initialize town
export GT_TOWN_ROOT=/tmp/town
gt install /tmp/town --no-beads --name benchmark >/dev/null 2>&1 || true

# 2. Initialize beads database
cd /tmp/town
bd init --prefix hq >/dev/null 2>&1 || true

# 3. Create a bare repo from /workspace (now has a real branch)
git clone --bare /workspace /tmp/workspace-bare.git 2>/dev/null

# 4. Add a rig
gt rig add bench file:///tmp/workspace-bare.git --prefix bench --branch "$DEFAULT_BRANCH" >/dev/null 2>&1

# 5. Create a bead with the task description
cd /tmp/town/bench
BEAD_JSON=$(bd create --title "Benchmark Task" --body "$TASK_PROMPT" --json 2>/dev/null)
BEAD_ID=$(echo "$BEAD_JSON" | grep -oP '"id":\s*"[^"]+"' | head -1 | sed 's/.*"id":\s*"//' | sed 's/"//')

if [ -z "$BEAD_ID" ]; then
  echo "ERROR: Failed to create bead" >&2
  exit 1
fi

echo "Created bead: $BEAD_ID"

# 6. Create polecat worktree manually
POLECAT_NAME="rust"
POLECAT_BRANCH="polecat-${POLECAT_NAME}"
POLECAT_DIR="/tmp/town/bench/polecats/${POLECAT_NAME}/bench"
mkdir -p "/tmp/town/bench/polecats/${POLECAT_NAME}"

cd /tmp/town/bench/.repo.git
git worktree add -b "$POLECAT_BRANCH" "$POLECAT_DIR" "$DEFAULT_BRANCH" 2>&1

echo "Created polecat worktree at: $POLECAT_DIR"

# 7. Set up Gas Town environment for the polecat
export GT_RIG=bench
export GT_ROLE=polecat
export GT_POLECAT="$POLECAT_NAME"
export BD_ACTOR="bench/polecats/${POLECAT_NAME}"
export BEADS_AGENT_NAME="bench/${POLECAT_NAME}"

# Hook the bead to the polecat
cd "$POLECAT_DIR"
bd init --prefix bench >/dev/null 2>&1 || true

# 8. Get Gas Town's context injection
echo "=== Getting GT prime context ==="
GT_CONTEXT=$(gt prime 2>/dev/null || echo "")
echo "GT prime context: ${#GT_CONTEXT} chars"

# 9. Run Claude (Opus) in headless mode with GT context + task
echo "=== Running Claude (headless, Opus) ==="

OUTPUT_FILE="$POLECAT_DIR/.thunderdome-output.jsonl"
set +e
claude -p \
  --model claude-opus-4-6 \
  --output-format stream-json \
  --verbose \
  --dangerously-skip-permissions \
  --disallowed-tools "AskUserQuestion,EnterPlanMode" \
  --append-system-prompt "You are running in a headless benchmark environment as a Gas Town polecat worker. There is no human to interact with. Focus on implementation: read the task, write code, run tests, iterate until all tests pass. Do NOT attempt to create git worktrees or branches — work directly in the current directory." \
  -- "$TASK_PROMPT" \
  > "$OUTPUT_FILE" 2>"$POLECAT_DIR/.thunderdome-stderr.log"
CLAUDE_EXIT=$?
set -e

echo "Claude exited: $CLAUDE_EXIT"

# 10. Extract metrics
if [ -f "$OUTPUT_FILE" ]; then
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
fi

# 11. Copy polecat work back to /workspace
echo "=== Collecting polecat work ==="
cd "$POLECAT_DIR"

find . -not -path './.git/*' -not -path './.git' \
       -not -path './.beads/*' -not -path './.beads' \
       -not -name '.thunderdome-output.jsonl' \
       -not -name '.thunderdome-stderr.log' \
       -not -name '.' -type f | while read -r file; do
  dir=$(dirname "$file")
  mkdir -p "/workspace/$dir"
  cp "$file" "/workspace/$file"
done

echo "Copied polecat work to /workspace"

cd /workspace
echo "=== Gas Station adapter complete ==="
exit $CLAUDE_EXIT
