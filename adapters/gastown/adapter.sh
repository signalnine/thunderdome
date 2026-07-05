#!/bin/bash
set -e

# Validate inputs
[[ -f "$TASK_DESCRIPTION" ]] || { echo "Task file not found: $TASK_DESCRIPTION" >&2; exit 2; }

cd "$TASK_DIR"

# Route API calls through proxy gateway if configured
if [ -n "$PROXY_URL" ]; then
  export ANTHROPIC_BASE_URL="$PROXY_URL"
fi

TASK_PROMPT=$(cat "$TASK_DESCRIPTION")

# --- Gas Town Adapter ---
# Gas Town is a multi-agent workspace orchestrator. This adapter uses Gas Town's
# workspace architecture (town → rig → polecat worktree) and context injection
# (gt prime) while running Claude in headless mode.
#
# We manually create the polecat worktree instead of using `gt sling` because
# Claude Code's interactive mode requires prompts (API key acceptance, bypass
# permissions) that can't be automated in tmux, and Gas Town's session health
# check is unreliable with headless agents.

echo "=== Setting up Gas Town workspace ==="

# 1. Initialize town
export GT_TOWN_ROOT=/tmp/town
gt install /tmp/town --no-beads --name benchmark >/dev/null 2>&1 || true

# 2. Initialize beads database
cd /tmp/town
bd init --prefix hq >/dev/null 2>&1 || true

# 3. Create a bare repo from /workspace
git clone --bare /workspace /tmp/workspace-bare.git 2>/dev/null

# 4. Detect default branch
DEFAULT_BRANCH=$(git -C /workspace symbolic-ref --short HEAD 2>/dev/null || echo "master")
echo "Detected branch: $DEFAULT_BRANCH"

# 5. Add a rig
gt rig add bench file:///tmp/workspace-bare.git --prefix bench --branch "$DEFAULT_BRANCH" >/dev/null 2>&1

# 6. Create a bead with the task description
cd /tmp/town/bench
BEAD_JSON=$(bd create --title "Benchmark Task" --body "$TASK_PROMPT" --json 2>/dev/null)
BEAD_ID=$(echo "$BEAD_JSON" | grep -oP '"id":\s*"[^"]+"' | head -1 | sed 's/.*"id":\s*"//' | sed 's/"//')

if [ -z "$BEAD_ID" ]; then
  echo "ERROR: Failed to create bead" >&2
  exit 1
fi

echo "Created bead: $BEAD_ID"

# 7. Create polecat worktree manually
# Gas Town polecats are git worktrees under the rig's polecats/ directory
POLECAT_NAME="rust"
POLECAT_BRANCH="polecat-${POLECAT_NAME}"
POLECAT_DIR="/tmp/town/bench/polecats/${POLECAT_NAME}/bench"
mkdir -p "/tmp/town/bench/polecats/${POLECAT_NAME}"

# Create worktree from the rig's shared bare repo
cd /tmp/town/bench/.repo.git
git worktree add -b "$POLECAT_BRANCH" "$POLECAT_DIR" "$DEFAULT_BRANCH" 2>&1

echo "Created polecat worktree at: $POLECAT_DIR"

# 8. Set up Gas Town environment for the polecat
export GT_RIG=bench
export GT_ROLE=polecat
export GT_POLECAT="$POLECAT_NAME"
export BD_ACTOR="bench/polecats/${POLECAT_NAME}"
export BEADS_AGENT_NAME="bench/${POLECAT_NAME}"

# Hook the bead to the polecat
cd "$POLECAT_DIR"
bd init --prefix bench >/dev/null 2>&1 || true

# 9. Get Gas Town's context injection
echo "=== Getting GT prime context ==="
GT_CONTEXT=$(gt prime 2>/dev/null || echo "")
GT_CONTEXT_LEN=${#GT_CONTEXT}
echo "GT prime context: ${GT_CONTEXT_LEN} chars"

# 10. Run Claude in headless mode with GT context + task
echo "=== Running Claude (headless) ==="

OUTPUT_FILE="$POLECAT_DIR/.thunderdome-output.jsonl"
set +e
claude -p \
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

# 11. Extract metrics
if [ -f "$OUTPUT_FILE" ]; then
  node -e "
    const fs = require('fs');
    const lines = fs.readFileSync('$OUTPUT_FILE', 'utf8').trim().split('\n');
    let totalInput = 0, totalOutput = 0, totalCacheRead = 0, totalCacheCreate = 0;
    let turns = 0, toolsUsed = new Set(), totalCost = 0, durationMs = 0;
    for (const line of lines) {
      try {
        const obj = JSON.parse(line);
        if (obj.type === 'result' && obj.result) {
          totalCost = obj.cost_usd || 0;
          durationMs = obj.duration_ms || 0;
        }
        if (obj.type === 'assistant') { turns++; }
        if (obj.message?.usage) {
          const u = obj.message.usage;
          totalInput += u.input_tokens || 0;
          totalOutput += u.output_tokens || 0;
          totalCacheRead += u.cache_read_input_tokens || 0;
          totalCacheCreate += u.cache_creation_input_tokens || 0;
        }
        if (obj.type === 'tool_use') { toolsUsed.add(obj.name || 'unknown'); }
      } catch {}
    }
    const m = {
      input_tokens: totalInput, output_tokens: totalOutput,
      cache_read_tokens: totalCacheRead, cache_creation_tokens: totalCacheCreate,
      turns, tools_used: [...toolsUsed], duration_ms: durationMs,
      total_cost_usd: totalCost
    };
    process.stderr.write('Metrics: ' + JSON.stringify(m) + '\n');
  " 2>&1 || true
fi

# 12. Copy polecat's work back to /workspace
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
echo "=== Gas Town adapter complete ==="
exit $CLAUDE_EXIT
