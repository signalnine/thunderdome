#!/bin/bash
set -e

# stacked-oauth-opus: Metacog + Conclave Review + Git Worktree
#
# Stacks three top-performing genes:
#   1. Git worktree (from Gas Station ablation) — clean workspace, no .git dir noise
#   2. Metacog skill — perspective-shifting before implementation
#   3. Conclave consensus code review — multi-agent review after implementation

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

# --- Worktree setup (from Gas Station / worktree ablation) ---
echo "=== Setting up worktree workspace ==="

git -C /workspace checkout -b main 2>/dev/null || true
git clone --bare /workspace /tmp/workspace-bare.git 2>/dev/null

WORKTREE_DIR=/tmp/worktree/bench
mkdir -p /tmp/worktree
cd /tmp/workspace-bare.git
git worktree add -b work "$WORKTREE_DIR" main 2>&1

echo "Worktree ready at: $WORKTREE_DIR"
cd "$WORKTREE_DIR"

# --- Run Claude with metacog + conclave review ---
OUTPUT_FILE="$WORKTREE_DIR/.thunderdome-output.jsonl"

set +e
claude -p \
  --model claude-opus-4-6 \
  --output-format stream-json \
  --verbose \
  --dangerously-skip-permissions \
  --plugin-dir /opt/metacog-plugin \
  --disallowed-tools "AskUserQuestion,EnterPlanMode" \
  --append-system-prompt "You are running in a headless benchmark environment. There is no human to interact with.

MANDATORY WORKFLOW — three phases:

PHASE 1 — REFRAME (metacog):
Before writing ANY code, invoke the metacog skill via the Skill tool. Use it to analyze the problem from a non-default angle. Pick a stratagem that fits the task. Let it guide your approach.

PHASE 2 — IMPLEMENT:
With the metacog-informed perspective, implement the solution. Write good code. Run tests as you go.

PHASE 3 — REVIEW (conclave consensus):
After implementation is complete and tests pass:
1. Commit your changes: git add -A && git commit -m 'implementation'
2. Find the base commit: BASE_SHA=\$(git log --reverse --format=%H | head -1)
3. Run multi-agent consensus code review:
   /opt/conclave-plugin/conclave consensus --mode=code-review --base-sha=\$BASE_SHA --head-sha=HEAD --description='Review implementation for correctness, edge cases, and code quality'
4. Read the review output carefully. Address any HIGH PRIORITY or MEDIUM PRIORITY findings.
5. Run tests again to confirm fixes.

RULES:
- You MUST invoke metacog before writing implementation code.
- You MUST run conclave consensus code review after implementation.
- Let the metacog stratagem guide your approach — don't just acknowledge it.
- Focus on solving the task correctly." \
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
echo "=== Stacked adapter complete ==="
exit $CLAUDE_EXIT
