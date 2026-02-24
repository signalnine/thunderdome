#!/bin/bash
set -e

# Ablation: isolate the ".git directory noise" hypothesis.
# Copy workspace files to a clean directory with NO .git at all.
# If this matches the worktree's +19 points, the mechanism is confirmed:
# .git directory clutter in file discovery degrades agent performance.

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

# --- Clean workspace setup: copy everything EXCEPT .git/ ---
echo "=== Setting up clean workspace (no .git) ==="

CLEAN_DIR=/tmp/clean-workspace
mkdir -p "$CLEAN_DIR"

# Copy everything except .git directory using tar pipe (available in all containers)
cd /workspace
tar cf - --exclude='.git' . | tar xf - -C "$CLEAN_DIR"

echo "Clean workspace ready at: $CLEAN_DIR"
echo "Contents:"
ls -la "$CLEAN_DIR" | head -20

cd "$CLEAN_DIR"

# --- Run Claude (identical flags to vanilla) ---
OUTPUT_FILE="$CLEAN_DIR/.thunderdome-output.jsonl"

set +e
claude -p \
  --model claude-opus-4-6 \
  --output-format stream-json \
  --verbose \
  --dangerously-skip-permissions \
  -- "$TASK_PROMPT" \
  > "$OUTPUT_FILE" 2>"$CLEAN_DIR/.thunderdome-stderr.log"
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

# --- Copy clean workspace work back to /workspace ---
echo "=== Copying clean workspace to /workspace ==="
cd "$CLEAN_DIR"

# Copy all files back, excluding our instrumentation files
find . -not -name '.thunderdome-output.jsonl' \
       -not -name '.thunderdome-stderr.log' \
       -not -name '.' -type f | while read -r file; do
  dir=$(dirname "$file")
  mkdir -p "/workspace/$dir"
  cp "$file" "/workspace/$file"
done

echo "Copied clean workspace to /workspace"
cd /workspace
echo "=== No-git ablation adapter complete ==="
exit $CLAUDE_EXIT
