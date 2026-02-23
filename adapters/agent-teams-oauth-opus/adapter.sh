#!/bin/bash
set -e

[[ -f "$TASK_DESCRIPTION" ]] || { echo "Task file not found: $TASK_DESCRIPTION" >&2; exit 2; }

cd "$TASK_DIR"

export HOME=/tmp

# Set up OAuth credentials
if [ -f /tmp/.claude-credentials.json ]; then
  mkdir -p "$HOME/.claude"
  cp /tmp/.claude-credentials.json "$HOME/.claude/.credentials.json"
fi

# Route API calls through proxy gateway if configured
if [ -n "$PROXY_URL" ]; then
  export ANTHROPIC_BASE_URL="$PROXY_URL"
fi

# Enable experimental agent teams
export CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1

# Pre-configure settings to skip the theme picker and enable agent teams.
mkdir -p "$HOME/.claude"
cat > "$HOME/.claude/settings.json" <<'SETTINGS'
{
  "env": {
    "CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS": "1"
  },
  "teammateMode": "in-process",
  "theme": "dark",
  "hasCompletedOnboarding": true
}
SETTINGS
echo '{"hasCompletedOnboarding":true}' > "$HOME/.claude.json"

TASK_PROMPT=$(cat "$TASK_DESCRIPTION")

# Write task prompt to file (avoids quoting issues)
printf '%s' "$TASK_PROMPT" > /tmp/task-prompt.txt

# ============================================================================
# Strategy: run Claude in tmux, monitor with capture-pane
# ============================================================================

# Build the claude command. Use -- to pass the prompt as a positional arg.
# Single-quote the prompt in a file and use cat to avoid shell escaping issues.
cat > /tmp/run-claude.sh <<'CLAUDE_SCRIPT'
#!/bin/bash
export HOME=/tmp
export CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1
export CLAUDE_CODE_MAX_OUTPUT_TOKENS=128000
export TERM=xterm-256color

claude \
  --model claude-opus-4-6 \
  --dangerously-skip-permissions \
  --disallowed-tools "AskUserQuestion,EnterPlanMode" \
  --append-system-prompt "You are running in a headless benchmark environment. There is no human to interact with.

You have agent teams enabled (CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1). For complex tasks, create an agent team to tackle the work with parallel teammates. Break the work into independent pieces and assign each to a teammate. Use delegate mode — coordinate and assign, don't implement everything yourself.

When all work is complete and tests pass, you are DONE. Do not wait for further input." \
  -- "$(cat /tmp/task-prompt.txt)"

# Signal completion
echo "CLAUDE_SESSION_COMPLETE" > /tmp/claude-done
CLAUDE_SCRIPT
chmod +x /tmp/run-claude.sh

# Start tmux with Claude
tmux new-session -d -s bench -x 200 -y 50 /tmp/run-claude.sh

# Give Claude a moment to start
sleep 3

# ============================================================================
# Handle startup dialogs by monitoring the pane
# ============================================================================

handle_dialogs() {
  for i in $(seq 1 30); do
    SCREEN=$(tmux capture-pane -t bench -p 2>/dev/null || echo "")

    # Theme picker — send Enter to accept default
    if echo "$SCREEN" | grep -q "Choose.*text.*style"; then
      sleep 1
      tmux send-keys -t bench Enter
      sleep 2
      continue
    fi

    # Bypass permissions confirmation — need to select "Yes, I accept"
    if echo "$SCREEN" | grep -q "Yes.*I accept"; then
      # Send down arrow to move to option 2, then Enter
      tmux send-keys -t bench Down
      sleep 0.5
      tmux send-keys -t bench Enter
      sleep 2
      continue
    fi

    # If we see tool use or thinking, Claude is working — dialogs are done
    if echo "$SCREEN" | grep -qE "Read|Write|Edit|Bash|Task|Glob|thinking|tokens"; then
      echo "Claude is working — dialogs handled" >&2
      return 0
    fi

    sleep 2
  done
  echo "Dialog handling timed out, proceeding anyway" >&2
}

handle_dialogs

# ============================================================================
# Monitor for completion
# ============================================================================

# Idle detection via tmux capture-pane.
# When Claude finishes, the TUI shows an input prompt at the bottom.
# We detect this by looking for patterns that indicate Claude is waiting for input.
# Also monitor the done-signal file as a fallback.

IDLE_COUNT=0
CHECK_INTERVAL=15
MAX_IDLE=8  # 8 * 15s = 2 minutes of idle before we call it done
PREV_SCREEN_HASH=""
WALL_START=$(date +%s)
MAX_WALL=3300  # 55 minutes — leave 5min buffer for the harness timeout

echo "Starting completion monitor (check every ${CHECK_INTERVAL}s, idle threshold ${MAX_IDLE} checks)" >&2

while true; do
  sleep "$CHECK_INTERVAL"

  # Check if tmux session still exists
  if ! tmux has-session -t bench 2>/dev/null; then
    echo "tmux session ended" >&2
    break
  fi

  # Check done signal
  if [ -f /tmp/claude-done ]; then
    echo "Claude signaled completion" >&2
    break
  fi

  # Wall clock safety
  NOW=$(date +%s)
  ELAPSED=$(( NOW - WALL_START ))
  if [ "$ELAPSED" -gt "$MAX_WALL" ]; then
    echo "Wall clock limit reached (${ELAPSED}s), sending /exit" >&2
    tmux send-keys -t bench "/exit" Enter
    sleep 10
    break
  fi

  # Capture current screen
  SCREEN=$(tmux capture-pane -t bench -p 2>/dev/null || echo "")
  SCREEN_HASH=$(echo "$SCREEN" | md5sum | cut -d' ' -f1)

  # Check for signs Claude is idle (waiting for input).
  # The input prompt in Claude Code TUI typically shows:
  #   - A ">" or cursor at the bottom
  #   - "How can I help?" or similar
  #   - The screen stops changing
  IS_IDLE=false

  # Primary signal: screen hasn't changed between checks
  if [ "$SCREEN_HASH" = "$PREV_SCREEN_HASH" ]; then
    IS_IDLE=true
  fi

  PREV_SCREEN_HASH="$SCREEN_HASH"

  if $IS_IDLE; then
    IDLE_COUNT=$((IDLE_COUNT + 1))
    echo "Idle check ${IDLE_COUNT}/${MAX_IDLE} (screen unchanged)" >&2
  else
    if [ "$IDLE_COUNT" -gt 0 ]; then
      echo "Activity detected, reset idle counter" >&2
    fi
    IDLE_COUNT=0
  fi

  # If idle long enough, Claude is done
  if [ "$IDLE_COUNT" -ge "$MAX_IDLE" ]; then
    echo "Idle threshold reached, sending /exit" >&2
    tmux send-keys -t bench "/exit" Enter
    sleep 10
    break
  fi
done

# Wait for tmux session to fully exit
for i in $(seq 1 12); do
  if ! tmux has-session -t bench 2>/dev/null; then
    break
  fi
  sleep 5
done

# Kill any remaining tmux
tmux kill-session -t bench 2>/dev/null || true

# ============================================================================
# Metrics extraction
# ============================================================================

# Capture final pane content for metrics
# (tmux may be gone, so this might fail)

node -e '
const fs = require("fs");
try {
  // Read any available output files
  let combined = "";
  for (const f of ["/workspace/.thunderdome-interactive.log", "/workspace/.thunderdome-output.txt"]) {
    try { combined += fs.readFileSync(f, "utf8") + "\n"; } catch(e) {}
  }

  // Strip ANSI escape codes
  const clean = combined.replace(/\x1b\[[0-9;]*[a-zA-Z]/g, "").replace(/\x1b\][^\x07]*\x07/g, "");

  const metrics = {
    input_tokens: 0,
    output_tokens: 0,
    cache_read_tokens: 0,
    cache_creation_tokens: 0,
    turns: 0,
    tools_used: [],
    duration_ms: 0,
    total_cost_usd: 0,
    note: "interactive-mode-metrics-approximate"
  };

  // Look for dollar amounts
  const costMatches = clean.match(/\$(\d+\.\d+)/g);
  if (costMatches && costMatches.length > 0) {
    const costs = costMatches.map(m => parseFloat(m.slice(1)));
    metrics.total_cost_usd = Math.max(...costs);
  }

  // Tool detection
  const toolNames = ["Read", "Write", "Edit", "Bash", "Glob", "Grep", "Task",
                     "Skill", "TodoWrite", "WebFetch", "WebSearch", "NotebookEdit",
                     "SpawnTeammate", "MessageTeammate", "ShutdownTeammate",
                     "TaskCreate", "TaskUpdate", "TaskList"];
  for (const tool of toolNames) {
    if (clean.includes(tool)) {
      metrics.tools_used.push(tool);
    }
  }

  fs.writeFileSync("/workspace/.thunderdome-metrics.json", JSON.stringify(metrics, null, 2));
  console.error("Metrics (approximate): " + JSON.stringify(metrics));
} catch(e) {
  console.error("Metrics extraction failed: " + e.message);
  fs.writeFileSync("/workspace/.thunderdome-metrics.json", JSON.stringify({note: "extraction-failed", error: e.message}, null, 2));
}
' || true

exit 0
