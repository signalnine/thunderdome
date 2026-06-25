#!/bin/bash
set -e

# claude-code-tmux-oauth: vanilla Claude Code in INTERACTIVE mode, driven via
# tmux send-keys/capture-pane, authenticated with OAuth (Max subscription).
#
# THE FIX over the unregistered conclave-*-tmux adapters: those used `--bare`,
# which skips credential loading entirely — that's why interactive mode seemed
# to "force browser OAuth" and they fell back to ANTHROPIC_API_KEY. Verified
# 2026-06-12 on claude 2.1.170+: full interactive mode (no --bare) loads
# ~/.claude/.credentials.json fine and runs on the Max subscription.
#
# A/B partner for claude-code-oauth-opus (same model, headless -p) to isolate
# the interactive-vs-headless harness gene.

[[ -f "$TASK_DESCRIPTION" ]] || { echo "Task file not found: $TASK_DESCRIPTION" >&2; exit 2; }

cd "$TASK_DIR"

export HOME=/tmp
mkdir -p "$HOME/.claude"

# OAuth credentials: the runner mounts host ~/.claude/.credentials.json
# read-only at /tmp/.claude-credentials.json; copy into a writable home.
if [ -f /tmp/.claude-credentials.json ]; then
  cp /tmp/.claude-credentials.json "$HOME/.claude/.credentials.json"
else
  echo "ERROR: no OAuth credentials mounted (need host ~/.claude/.credentials.json)" >&2
  exit 3
fi

# Pre-stage settings to skip first-run wizards (theme/onboarding/trust/bypass).
cat > "$HOME/.claude/settings.json" <<'JSON'
{
  "theme": "dark",
  "skipDangerousModePermissionPrompt": true,
  "hasCompletedOnboarding": true,
  "hasTrustDialogAccepted": true
}
JSON

# THE missing piece (verified 2026-06-12): interactive claude decides
# logged-in-ness from the ~/.claude.json STATE file, not just
# .credentials.json. Without it, a fresh container walks the browser-OAuth
# wizard even with valid credentials. hasCompletedOnboarding alone suffices.
cat > "$HOME/.claude.json" <<'JSON'
{ "hasCompletedOnboarding": true }
JSON

MODEL="${TMUX_CLAUDE_MODEL:-claude-opus-4-6}"
# Optional session effort level. `ultracode` (Opus 4.8 only: xhigh + automatic
# dynamic-workflow orchestration) is NOT a valid --effort CLI value -- it is a
# session SETTING set only via the `/effort ultracode` slash command. So we send
# `/effort <level>` into the live TUI after it's ready (works for ultracode and
# the model levels high/xhigh/max alike). This is the whole reason the
# interactive driver is required for ultracode -- headless -p can't set it.
EFFORT="${TMUX_CLAUDE_EFFORT:-}"
TASK_PROMPT=$(cat "$TASK_DESCRIPTION")
SESSION="td-$$"
PANE_LOG=/workspace/.thunderdome-pane.log
FULL_LOG=/workspace/.thunderdome-pane-full.log

echo "=== Interactive Claude Code via tmux (OAuth, $MODEL) ===" >&2

cleanup() { tmux kill-session -t "$SESSION" 2>/dev/null || true; }
trap cleanup EXIT INT TERM

# Wide pane so wrapping doesn't fragment status lines
tmux new-session -d -s "$SESSION" -x 220 -y 60 -c "$TASK_DIR"
tmux pipe-pane -t "$SESSION" "cat >> $PANE_LOG"

# Launch FULL interactive claude — no --bare (see header). bypass-permissions
# auto-approves edits; --strict-mcp-config keeps isolation.
tmux send-keys -t "$SESSION" \
  "claude --model $MODEL \
     --dangerously-skip-permissions \
     --strict-mcp-config \
     --add-dir $TASK_DIR" Enter

# Poll-driven dialog walker: handle whichever first-run dialog appears (the
# pre-staged settings suppress most, but trust-folder is per-directory).
# Bail clearly if the login wizard shows (means OAuth state staging failed).
READY=0
for _ in $(seq 1 18); do
  sleep 5
  P=$(tmux capture-pane -t "$SESSION" -p 2>/dev/null)
  if echo "$P" | grep -q "trust this folder"; then
    tmux send-keys -t "$SESSION" "1"; sleep 1; tmux send-keys -t "$SESSION" Enter
  elif echo "$P" | grep -q "Yes, I accept"; then
    tmux send-keys -t "$SESSION" "2"; sleep 1; tmux send-keys -t "$SESSION" Enter
  elif echo "$P" | grep -qiE "select login method|not logged in"; then
    echo "ERROR: interactive claude did not accept OAuth credentials/state" >&2
    echo "$P" >&2
    exit 4
  elif echo "$P" | grep -q "bypass permissions on"; then
    READY=1; break
  fi
done
[ "$READY" = "1" ] || { echo "ERROR: claude TUI never reached ready state" >&2; tmux capture-pane -t "$SESSION" -p >&2 || true; exit 5; }

# Set session effort (e.g. /effort ultracode) before the task, if requested.
# Send as a discrete slash command and give it a beat to register.
if [ -n "$EFFORT" ]; then
  echo "=== setting session effort: /effort $EFFORT ===" >&2
  tmux send-keys -t "$SESSION" "/effort $EFFORT" Enter
  sleep 3
  tmux capture-pane -t "$SESSION" -p 2>/dev/null | grep -iE "effort|ultracode" | tail -2 >&2 || true
fi

# Send the task prompt as a single paste so embedded newlines don't fire
# premature Enters; then submit.
echo "$TASK_PROMPT" | tmux load-buffer -t "$SESSION" -
tmux paste-buffer -t "$SESSION"
sleep 1
tmux send-keys -t "$SESSION" Enter

# WAIT FOR DONE: poll pane md5; done after 90s of no change; 45-min ceiling.
LAST_HASH=""
IDLE_TICKS=0
ELAPSED=0
MAX_WAIT=$((45 * 60))
IDLE_THRESHOLD=9
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

# Cost/tokens via /cost (more stable than scraping the status bar)
tmux send-keys -t "$SESSION" "/cost" Enter
sleep 8

tmux capture-pane -t "$SESSION" -p > /workspace/.thunderdome-final.log
tmux capture-pane -t "$SESSION" -S - -p > "$FULL_LOG"

tmux send-keys -t "$SESSION" "/quit" Enter
sleep 3

# METRICS: parse /cost output from the pane logs (same parser as the
# conclave tmux adapters).
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

content = re.sub(r'\x1b\[[0-9;?]*[a-zA-Z]', '', content)
content = re.sub(r'\x1b\][^\x07]*\x07', '', content)

input_tokens = output_tokens = cache_read = 0
cost = 0.0

m = list(re.finditer(r'Total cost:?\s*\$?([\d.]+)', content, re.IGNORECASE))
if m: cost = float(m[-1].group(1))

def num(s):
    s = s.replace(',', '').strip()
    if s.lower().endswith('k'):
        return int(float(s[:-1]) * 1000)
    if s.lower().endswith('m'):
        return int(float(s[:-1]) * 1_000_000)
    return int(float(s)) if '.' in s else int(s)

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

tools_used = sorted(set(re.findall(r'[•■●→]\s*([A-Z][A-Za-z]+)\(', content)))[:20]

metrics = {
    'input_tokens': input_tokens,
    'output_tokens': output_tokens,
    'cache_read_tokens': cache_read,
    'cache_creation_tokens': 0,
    'turns': 0,
    'tools_used': tools_used,
    'duration_ms': 0,
    'total_cost_usd': round(cost, 6),
    'mode': 'tmux-interactive-oauth',
}
with open('/workspace/.thunderdome-metrics.json', 'w') as f:
    json.dump(metrics, f, indent=2)
print(f"Metrics: in={input_tokens} cached={cache_read} out={output_tokens} cost=${cost:.4f}", file=sys.stderr)
PYEOF

exit 0
