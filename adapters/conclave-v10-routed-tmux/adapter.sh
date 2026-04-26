#!/bin/bash
set -e

# conclave-v10-routed-tmux: A/B test of v10 conclave running in INTERACTIVE
# mode under tmux remote control vs. the canonical headless `-p` adapter.
# Question: do plugins/skills load and behave the same in -p vs interactive?
# Pattern adopted from
# https://github.com/loupgaroublond/jakes-one-stop-all-slop-trading-post-at-the-spillway/tree/main/plugins/claude-in-tmux

[[ -f "$TASK_DESCRIPTION" ]] || { echo "Task file not found: $TASK_DESCRIPTION" >&2; exit 2; }

cd "$TASK_DIR"

export HOME=/tmp
mkdir -p "$HOME/.claude"

# Interactive `claude` ignores ~/.claude/.credentials.json on first launch and
# walks through a browser-based OAuth flow that we cannot complete inside a
# headless container. The only documented way to skip it is `--bare` with
# ANTHROPIC_API_KEY. So this adapter requires the API-key path, not OAuth.
if [ -z "$ANTHROPIC_API_KEY" ]; then
  echo "ERROR: conclave-v10-routed-tmux requires ANTHROPIC_API_KEY (interactive mode can't use OAuth)" >&2
  exit 3
fi

# Pre-stage settings to skip first-run wizards. The skipDangerousMode key
# is what host users get after clicking through the bypass-permissions
# warning once; setting it directly skips that wizard entirely.
cat > "$HOME/.claude/settings.json" <<'JSON'
{
  "theme": "dark",
  "skipDangerousModePermissionPrompt": true,
  "hasCompletedOnboarding": true,
  "hasTrustDialogAccepted": true
}
JSON

if [ -n "$PROXY_URL" ]; then
  export ANTHROPIC_BASE_URL="$PROXY_URL"
fi

TASK_PROMPT=$(cat "$TASK_DESCRIPTION")
SESSION="td-$$"
PANE_LOG=/workspace/.thunderdome-pane.log
FULL_LOG=/workspace/.thunderdome-pane-full.log

# ──────────────────────────────────────────────────────────────────
# ROUTING: Haiku classifier (same as -p variant)
# ──────────────────────────────────────────────────────────────────
echo "=== Routing ===" >&2

ROUTING_PROMPT="You are a task complexity classifier. Read the task description below and classify it as HARD or EASY.

A task is HARD if it has ANY of these characteristics:
- Complex state management with multiple interacting components that must stay consistent
- Concurrent or async operations with ordering constraints
- Algorithmic reasoning requiring careful logic
- Ambiguous specifications requiring significant inference
- Multiple subsystems that must coordinate
- Complex data transformations with edge cases

A task is EASY if it is straightforward CRUD, a clear bug fix, well-specified, adding tests/docs, or simple refactoring.

Respond with ONLY HARD or EASY.

=== TASK DESCRIPTION ===
$TASK_PROMPT"

ROUTING_RESULT=$(claude -p \
  --model claude-haiku-4-5-20251001 \
  --max-turns 1 \
  --setting-sources '' \
  --strict-mcp-config \
  -- "$ROUTING_PROMPT" 2>/dev/null || echo "EASY")

if echo "$ROUTING_RESULT" | grep -qi "HARD"; then
  SELECTED_MODEL="claude-opus-4-6"
else
  SELECTED_MODEL="claude-sonnet-4-6"
fi
echo "  Routed: $SELECTED_MODEL" >&2

# ──────────────────────────────────────────────────────────────────
# IMPLEMENTATION: tmux-driven interactive claude
# ──────────────────────────────────────────────────────────────────
echo "=== Implementation (tmux-driven, interactive): $SELECTED_MODEL ===" >&2

cleanup() {
  tmux kill-session -t "$SESSION" 2>/dev/null || true
}
trap cleanup EXIT INT TERM

# Wide pane so wrapping doesn't fragment status lines
tmux new-session -d -s "$SESSION" -x 220 -y 60 -c "$TASK_DIR"

# Stream every byte rendered to the pane to a log file. pipe-pane captures
# stdout BEFORE tmux's terminal-emulation layer collapses it, so we get the
# full transcript including ANSI escapes.
tmux pipe-pane -t "$SESSION" "cat >> $PANE_LOG"

# Launch claude. acceptEdits = auto-yes file edits without manual prompts.
# --setting-sources '' / --strict-mcp-config tighten isolation per skill recipe.
tmux send-keys -t "$SESSION" \
  "claude --bare \
     --model $SELECTED_MODEL \
     --plugin-dir /opt/conclave-plugin \
     --dangerously-skip-permissions \
     --strict-mcp-config \
     --add-dir $TASK_DIR" Enter

# Walk first-run wizards. With pre-staged settings.json (theme +
# skipDangerousModePermissionPrompt + hasCompletedOnboarding + hasTrustDialogAccepted),
# most should be suppressed. The API-key prompt is per-session and not
# settings-controlled, so we still tap "1" Enter for it. Empirically the
# remaining one to two prompts after that.
sleep 8
tmux send-keys -t "$SESSION" Enter           # theme (in case still shown)
sleep 3
tmux send-keys -t "$SESSION" "1" Enter       # API key: type "1" Enter to accept
sleep 3
tmux send-keys -t "$SESSION" Enter           # security notes (if shown)
sleep 3
tmux send-keys -t "$SESSION" Enter           # trust folder (if shown)
sleep 3
tmux send-keys -t "$SESSION" "2" Enter       # bypass-perms (if shown — type 2 Enter)
sleep 8                                      # splash + plugin load

# Send the task prompt as a single paste so newlines don't get interpreted
# as separate Enter keystrokes.
echo "$TASK_PROMPT" | tmux load-buffer -t "$SESSION" -
tmux paste-buffer -t "$SESSION"
tmux send-keys -t "$SESSION" Enter

# ──────────────────────────────────────────────────────────────────
# WAIT FOR DONE: poll pane md5; declare done after 90s of no change
# Also enforce hard 45-min ceiling so a hung session can't pin a worker.
# ──────────────────────────────────────────────────────────────────
LAST_HASH=""
IDLE_TICKS=0
ELAPSED=0
MAX_WAIT=$((45 * 60))
IDLE_THRESHOLD=9   # 9 ticks * 10s = 90s of no change
while [ $ELAPSED -lt $MAX_WAIT ]; do
  CURRENT=$(tmux capture-pane -t "$SESSION" -p 2>/dev/null | md5sum | cut -d' ' -f1)
  if [ "$CURRENT" = "$LAST_HASH" ]; then
    IDLE_TICKS=$((IDLE_TICKS + 1))
    [ $IDLE_TICKS -ge $IDLE_THRESHOLD ] && break
  else
    IDLE_TICKS=0
    LAST_HASH="$CURRENT"
  fi
  sleep 10
  ELAPSED=$((ELAPSED + 10))
done

# Ask claude for cost/tokens explicitly — much more reliable than scraping
# the status bar (which varies across CC versions).
tmux send-keys -t "$SESSION" "/cost" Enter
sleep 8

# Capture final state (last screen) and full scrollback (-S -)
tmux capture-pane -t "$SESSION" -p > /workspace/.thunderdome-final.log
tmux capture-pane -t "$SESSION" -S - -p > "$FULL_LOG"

# Try a clean exit; cleanup trap will SIGKILL if it doesn't take.
tmux send-keys -t "$SESSION" "/quit" Enter
sleep 3

# ──────────────────────────────────────────────────────────────────
# METRICS: scrape /cost output from pane log
# Format (Claude Code 2.x):
#   Total cost:            $0.0345
#   Total duration (API):  1m 23s
#   Total tokens:          input: 1,234 (cache read: 567)  output: 89
# We grep the most recent occurrence in the log.
# ──────────────────────────────────────────────────────────────────
python3 <<'PYEOF'
import re, json, sys, os

paths = ['/workspace/.thunderdome-final.log',
         '/workspace/.thunderdome-pane-full.log',
         '/workspace/.thunderdome-pane.log']
content = ''
for p in paths:
    if os.path.exists(p):
        try:
            content += open(p, 'r', errors='replace').read()
        except: pass

# Strip ANSI escapes for parsing
content = re.sub(r'\x1b\[[0-9;?]*[a-zA-Z]', '', content)
content = re.sub(r'\x1b\][^\x07]*\x07', '', content)

input_tokens = output_tokens = cache_read = 0
cost = 0.0

# Total cost line. Take last occurrence in case /cost was sent twice.
m = list(re.finditer(r'Total cost:?\s*\$?([\d.]+)', content, re.IGNORECASE))
if m: cost = float(m[-1].group(1))

# CC 2.1.119 /cost format under "Usage by model:":
#   claude-opus-4-6:  7.0k input, 12.4k output, 217.2k cache read, 41.5k cache write ($0.71)
# Numbers may be plain integers (940) or k-suffixed (7.0k).
def num(s):
    s = s.replace(',', '').strip()
    if s.lower().endswith('k'):
        return int(float(s[:-1]) * 1000)
    if s.lower().endswith('m'):
        return int(float(s[:-1]) * 1_000_000)
    return int(float(s)) if '.' in s else int(s)

# Sum across all models seen (e.g. opus + haiku for routed adapters).
pattern = re.compile(
    r'([\d.,]+k?)\s*input,\s*([\d.,]+k?)\s*output,\s*([\d.,]+k?)\s*cache\s*read,\s*([\d.,]+k?)\s*cache\s*write',
    re.IGNORECASE,
)
for m in pattern.finditer(content):
    try:
        input_tokens += num(m.group(1))
        output_tokens += num(m.group(2))
        cache_read += num(m.group(3))
    except (ValueError, AttributeError):
        pass

# Tool calls: count `■ ToolName(` patterns Claude renders for each tool use
tools_used = sorted(set(re.findall(r'[\u2022\u25A0\u25CF\u2192]\s*([A-Z][A-Za-z]+)\(', content)))[:20]

metrics = {
    'input_tokens': input_tokens,
    'output_tokens': output_tokens,
    'cache_read_tokens': cache_read,
    'cache_creation_tokens': 0,
    'turns': 0,  # not extractable from interactive pane
    'tools_used': tools_used,
    'duration_ms': 0,
    'total_cost_usd': round(cost, 6),
    'mode': 'tmux-interactive',
}
with open('/workspace/.thunderdome-metrics.json', 'w') as f:
    json.dump(metrics, f, indent=2)
print(f"Metrics: in={input_tokens} cached={cache_read} out={output_tokens} cost=${cost:.4f}", file=sys.stderr)
PYEOF

exit 0
