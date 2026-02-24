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
cat > /tmp/run-claude.sh <<CLAUDE_SCRIPT
#!/bin/bash
export HOME=/tmp
export CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1
export CLAUDE_CODE_MAX_OUTPUT_TOKENS=128000
export TERM=xterm-256color
$([ -n "$PROXY_URL" ] && echo "export ANTHROPIC_BASE_URL=\"$PROXY_URL\"")
CLAUDE_SCRIPT

# Append the rest with single-quoted heredoc (no variable expansion)
cat >> /tmp/run-claude.sh <<'CLAUDE_SCRIPT'

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

# ============================================================================
# Capture /cost output before exiting
# ============================================================================
# No-op: /cost doesn't work with OAuth (just says "using subscription").
# Token data is extracted from session JSONL files instead.
capture_cost() { :; }

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
    echo "Claude signaled completion, capturing /cost" >&2
    capture_cost
    break
  fi

  # Wall clock safety
  NOW=$(date +%s)
  ELAPSED=$(( NOW - WALL_START ))
  if [ "$ELAPSED" -gt "$MAX_WALL" ]; then
    echo "Wall clock limit reached (${ELAPSED}s), capturing /cost then exiting" >&2
    capture_cost
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
    echo "Idle threshold reached, capturing /cost then exiting" >&2
    capture_cost
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

cat > /tmp/extract-metrics.js <<'METRICS_JS'
const fs = require("fs");
const path = require("path");
try {
  const metrics = {
    input_tokens: 0, output_tokens: 0,
    cache_read_tokens: 0, cache_creation_tokens: 0,
    turns: 0, tools_used: [], duration_ms: 0,
    total_cost_usd: 0, note: "interactive-mode-session-jsonl"
  };

  // Find Claude Code session JSONL files (HOME=/tmp in container)
  const projectsDir = "/tmp/.claude/projects";
  const jsonlFiles = [];
  const findJsonl = (dir) => {
    try {
      for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
        const full = path.join(dir, entry.name);
        if (entry.isDirectory()) findJsonl(full);
        else if (entry.name.endsWith(".jsonl")) jsonlFiles.push(full);
      }
    } catch(e) {}
  };
  if (fs.existsSync(projectsDir)) findJsonl(projectsDir);
  console.error("Found " + jsonlFiles.length + " session JSONL files");

  const toolsSeen = new Set();
  for (const file of jsonlFiles) {
    console.error("Processing: " + file + " (" + fs.statSync(file).size + " bytes)");
    try { fs.copyFileSync(file, "/workspace/.thunderdome-session.jsonl"); } catch(e) {}

    // Split on actual newlines (JSONL = one JSON object per line)
    const lines = fs.readFileSync(file, "utf8").split("\n");
    console.error("Lines in file: " + lines.length);

    // Deduplicate by requestId — streaming chunks repeat usage data.
    // Keep last usage per requestId.
    const usageByRequest = new Map();

    for (const line of lines) {
      if (!line.trim()) continue;
      try {
        const msg = JSON.parse(line);

        // Usage is at msg.message.usage for assistant messages
        if (msg.type === "assistant" && msg.message && msg.message.usage) {
          const reqId = msg.requestId || msg.uuid;
          usageByRequest.set(reqId, msg.message.usage);
        }

        // Detect tools from assistant message content
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

    // Sum usage across unique API requests
    for (const [, usage] of usageByRequest) {
      metrics.input_tokens += usage.input_tokens || 0;
      metrics.output_tokens += usage.output_tokens || 0;
      metrics.cache_read_tokens += usage.cache_read_input_tokens || 0;
      metrics.cache_creation_tokens += usage.cache_creation_input_tokens || 0;
    }
    metrics.turns = usageByRequest.size;
    console.error("Unique API requests: " + usageByRequest.size);
  }

  // Estimate cost: Opus $15/$75 per M input/output, cache read $1.50/M, cache write $18.75/M
  const cost = (metrics.input_tokens * 15 + metrics.output_tokens * 75 +
    metrics.cache_read_tokens * 1.50 + metrics.cache_creation_tokens * 18.75) / 1_000_000;
  metrics.total_cost_usd = Math.round(cost * 10000) / 10000;

  if (jsonlFiles.length === 0) metrics.note = "no-session-files-found";

  fs.writeFileSync("/workspace/.thunderdome-metrics.json", JSON.stringify(metrics, null, 2));
  console.error("Metrics: " + JSON.stringify(metrics));
} catch(e) {
  console.error("Metrics extraction failed: " + e.message);
  fs.writeFileSync("/workspace/.thunderdome-metrics.json",
    JSON.stringify({note: "extraction-failed", error: e.message}, null, 2));
}
METRICS_JS
node /tmp/extract-metrics.js || true

exit 0
