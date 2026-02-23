#!/bin/bash
set -e

# Ablation: isolate the "git worktree from bare clone" variable from Gas Station.
# This adapter is vanilla Claude Code + bare clone + worktree + file copy back.
# No Gas Town tooling, no beads, no gt prime, no env vars, no system prompt changes.

[[ -f "$TASK_DESCRIPTION" ]] || { echo "Task file not found: $TASK_DESCRIPTION" >&2; exit 2; }

cd "$TASK_DIR"

# Use /tmp as HOME so Claude Code can write session files, debug logs, etc.
export HOME=/tmp

# Set up OAuth credentials: copy from mounted read-only location
if [ -f /tmp/.claude-credentials.json ]; then
  mkdir -p "$HOME/.claude"
  cp /tmp/.claude-credentials.json "$HOME/.claude/.credentials.json"
fi

TASK_PROMPT=$(cat "$TASK_DESCRIPTION")

# --- Worktree setup (mirrors Gas Station's git plumbing, nothing else) ---
echo "=== Setting up worktree workspace ==="

# Create a real branch from detached HEAD (required for bare clone to have a branch ref)
git -C /workspace checkout -b main 2>/dev/null || true

# Bare clone the workspace
git clone --bare /workspace /tmp/workspace-bare.git 2>/dev/null

# Create a worktree from the bare clone
WORKTREE_DIR=/tmp/worktree/bench
mkdir -p /tmp/worktree
cd /tmp/workspace-bare.git
git worktree add -b work "$WORKTREE_DIR" main 2>&1

echo "Worktree ready at: $WORKTREE_DIR"
cd "$WORKTREE_DIR"

# --- Run Claude (identical flags to vanilla) ---
OUTPUT_FILE="$WORKTREE_DIR/.thunderdome-output.jsonl"

set +e
claude -p \
  --model claude-opus-4-6 \
  --output-format stream-json \
  --verbose \
  --dangerously-skip-permissions \
  -- "$TASK_PROMPT" \
  > "$OUTPUT_FILE" 2>"$WORKTREE_DIR/.thunderdome-stderr.log"
CLAUDE_EXIT=$?
set -e

echo "Claude exited: $CLAUDE_EXIT"

# --- Extract metrics ---
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

# --- Copy worktree work back to /workspace ---
echo "=== Copying worktree work to /workspace ==="
cd "$WORKTREE_DIR"

find . -not -path './.git/*' -not -path './.git' \
       -not -name '.thunderdome-output.jsonl' \
       -not -name '.thunderdome-stderr.log' \
       -not -name '.' -type f | while read -r file; do
  dir=$(dirname "$file")
  mkdir -p "/workspace/$dir"
  cp "$file" "/workspace/$file"
done

echo "Copied worktree work to /workspace"
cd /workspace
echo "=== Worktree ablation adapter complete ==="
exit $CLAUDE_EXIT
