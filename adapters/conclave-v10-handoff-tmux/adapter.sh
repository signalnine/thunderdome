#!/bin/bash
set -e

# conclave-v10-handoff-tmux: tests the "verifier handoff" hypothesis --
# Sonnet writes the implementation, then mid-session we /model to Opus and
# /effort high and ask it to verify + fix. Single shared context (no cache
# wipe between phases), no separate trial.
#
# Hypothesis: shared-context two-pass (cheap writer + frontier verifier)
# beats either model end-to-end at meaningfully lower cost than full-Opus.
# Comparable to:
#   - conclave-v8-combined-sonnet: 88.1% / $0.82 (Sonnet end-to-end)
#   - conclave-v8-combined-opus:   88.5% / $1.49 (Opus end-to-end)
#   - conclave-v10-routed:         88.5% / $0.99 (one model picked upfront)
#
# Only possible because tmux mode lets us issue /model and /effort slash
# commands mid-session; -p mode is locked to one model at launch.

[[ -f "$TASK_DESCRIPTION" ]] || { echo "Task file not found: $TASK_DESCRIPTION" >&2; exit 2; }

cd "$TASK_DIR"

export HOME=/tmp
mkdir -p "$HOME/.claude"

# Auth: prefer OAuth (subscription-billed) via apiKeyHelper; fall back to API key.
# `claude --bare` accepts OAuth bearer tokens through apiKeyHelper, which lets us
# avoid both (a) the interactive OAuth wizard that wants a browser, and (b) the
# per-token API billing of ANTHROPIC_API_KEY. The helper just cats accessToken
# from the credentials file mounted at /tmp/.claude-credentials.json.
if [ -f /tmp/.claude-credentials.json ]; then
  cat > "$HOME/.claude/oauth-helper.sh" <<'HELPER'
#!/bin/bash
python3 -c "import json; print(json.load(open('/tmp/.claude-credentials.json'))['claudeAiOauth']['accessToken'])"
HELPER
  chmod +x "$HOME/.claude/oauth-helper.sh"
  AUTH_FRAGMENT='"apiKeyHelper": "/tmp/.claude/oauth-helper.sh",'
  unset ANTHROPIC_API_KEY  # force --bare to use the helper, not the env var
elif [ -n "$ANTHROPIC_API_KEY" ]; then
  AUTH_FRAGMENT=''  # --bare will pick up ANTHROPIC_API_KEY from env
else
  echo "ERROR: need either /tmp/.claude-credentials.json or ANTHROPIC_API_KEY" >&2
  exit 3
fi

cat > "$HOME/.claude/settings.json" <<JSON
{
  "theme": "dark",
  "skipDangerousModePermissionPrompt": true,
  "hasCompletedOnboarding": true,
  "hasTrustDialogAccepted": true,
  ${AUTH_FRAGMENT}
  "_": null
}
JSON

if [ -n "$PROXY_URL" ]; then
  export ANTHROPIC_BASE_URL="$PROXY_URL"
fi

TASK_PROMPT=$(cat "$TASK_DESCRIPTION")
SESSION="td-$$"
PANE_LOG=/workspace/.thunderdome-pane.log
FULL_LOG=/workspace/.thunderdome-pane-full.log

# Idle detection helper. Polls pane md5 every 10s; declares "done" after
# IDLE_THRESHOLD ticks of no change. ELAPSED is bounded by MAX_WAIT.
wait_for_idle() {
  local label="$1" max_secs="$2"
  local last_hash="" idle=0 elapsed=0
  local threshold=9   # 9 * 10s = 90s of no change
  echo "  waiting for idle ($label, max ${max_secs}s)..." >&2
  while [ $elapsed -lt $max_secs ]; do
    local cur
    cur=$(tmux capture-pane -t "$SESSION" -p 2>/dev/null | md5sum | cut -d' ' -f1)
    if [ "$cur" = "$last_hash" ]; then
      idle=$((idle + 1))
      [ $idle -ge $threshold ] && { echo "  $label idle confirmed after ${elapsed}s" >&2; return 0; }
    else
      idle=0
      last_hash="$cur"
    fi
    sleep 10
    elapsed=$((elapsed + 10))
  done
  echo "  $label hit max_wait (${max_secs}s) without idle" >&2
}

cleanup() {
  tmux kill-session -t "$SESSION" 2>/dev/null || true
}
trap cleanup EXIT INT TERM

# ──────────────────────────────────────────────────────────────────
# PHASE 1: Sonnet writes the implementation
# ──────────────────────────────────────────────────────────────────
echo "=== Phase 1: Sonnet writes implementation ===" >&2

tmux new-session -d -s "$SESSION" -x 220 -y 60 -c "$TASK_DIR"
tmux pipe-pane -t "$SESSION" "cat >> $PANE_LOG"

tmux send-keys -t "$SESSION" \
  "claude --bare \
     --model claude-sonnet-4-6 \
     --plugin-dir /opt/conclave-plugin \
     --dangerously-skip-permissions \
     --strict-mcp-config \
     --settings $HOME/.claude/settings.json \
     --add-dir $TASK_DIR" Enter

sleep 8
tmux send-keys -t "$SESSION" Enter           # theme
sleep 3
# API-key wizard only appears when ANTHROPIC_API_KEY is in env. With OAuth via
# apiKeyHelper we unset it above, so this prompt is skipped. Send Enter anyway
# as a no-op (won't hurt — lands at a "ready" prompt or the next wizard).
tmux send-keys -t "$SESSION" Enter           # API-key prompt (only when env-key path)
sleep 3
tmux send-keys -t "$SESSION" Enter           # security notes
sleep 3
tmux send-keys -t "$SESSION" Enter           # trust folder
sleep 3
tmux send-keys -t "$SESSION" "2" Enter       # bypass-perms (if shown)
sleep 8

echo "$TASK_PROMPT" | tmux load-buffer -t "$SESSION" -
tmux paste-buffer -t "$SESSION"
tmux send-keys -t "$SESSION" Enter

# Phase 1 budget: 30 min. Most -p trials finish in 4-8 min, so 30 is generous.
wait_for_idle "phase1-sonnet" $((30 * 60))

# ──────────────────────────────────────────────────────────────────
# PHASE 2: Hand off to Opus + high effort, ask it to verify + fix
# ──────────────────────────────────────────────────────────────────
echo "=== Phase 2: handoff to Opus + verify ===" >&2

tmux send-keys -t "$SESSION" "/model claude-opus-4-6" Enter
sleep 4
tmux send-keys -t "$SESSION" "/effort high" Enter
sleep 4

# The verifier prompt. Distinct from a fresh task -- assumes the prior
# session's context is intact (CONTRACT.md, the implementation, test files).
VERIFY_PROMPT='Review the implementation you just produced. Now you are operating with higher reasoning capacity (Opus 4.6, high effort).

1. Re-read CONTRACT.md (if present) and the original task requirements.
2. Run all tests. Fix every failing test.
3. Look for edge cases the implementation misses: empty inputs, boundaries, concurrency, error paths, off-by-one, type coercion bugs.
4. Verify the build is clean (npm run build) and lint is clean.
5. Do NOT stop until ALL tests pass AND build is clean AND lint is clean.
6. If you find nothing to fix, write a one-line summary of what you verified and stop.

Boil the lake on edge cases -- this is your only verification pass.'

echo "$VERIFY_PROMPT" | tmux load-buffer -t "$SESSION" -
tmux paste-buffer -t "$SESSION"
tmux send-keys -t "$SESSION" Enter

# Phase 2 budget: 15 min. Verifier shouldn't need a full session, but Opus
# can be slow when it's actually running tests + fixing.
wait_for_idle "phase2-opus-verify" $((15 * 60))

# ──────────────────────────────────────────────────────────────────
# Capture metrics via /cost (deterministic across CC versions)
# ──────────────────────────────────────────────────────────────────
tmux send-keys -t "$SESSION" "/cost" Enter
sleep 8

tmux capture-pane -t "$SESSION" -p > /workspace/.thunderdome-final.log
tmux capture-pane -t "$SESSION" -S - -p > "$FULL_LOG"

tmux send-keys -t "$SESSION" "/quit" Enter
sleep 3

python3 <<'PYEOF'
import re, json, sys, os

paths = ['/workspace/.thunderdome-final.log',
         '/workspace/.thunderdome-pane-full.log',
         '/workspace/.thunderdome-pane.log']
content = ''
for p in paths:
    if os.path.exists(p):
        try: content += open(p, 'r', errors='replace').read()
        except: pass

content = re.sub(r'\x1b\[[0-9;?]*[a-zA-Z]', '', content)
content = re.sub(r'\x1b\][^\x07]*\x07', '', content)

input_tokens = output_tokens = cache_read = 0
cost = 0.0

m = list(re.finditer(r'Total cost:?\s*\$?([\d.]+)', content, re.IGNORECASE))
if m: cost = float(m[-1].group(1))

def num(s):
    s = s.replace(',', '').strip()
    if s.lower().endswith('k'): return int(float(s[:-1]) * 1000)
    if s.lower().endswith('m'): return int(float(s[:-1]) * 1_000_000)
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
    except (ValueError, AttributeError): pass

# Track the per-model breakdown so we can see the Sonnet/Opus split.
per_model = {}
model_pat = re.compile(
    r'(claude-[a-z]+-\d+(?:-\d+)?)\s*:\s*([\d.,]+k?)\s*input,\s*([\d.,]+k?)\s*output,\s*([\d.,]+k?)\s*cache\s*read,\s*([\d.,]+k?)\s*cache\s*write\s*\(\$([\d.]+)\)',
    re.IGNORECASE,
)
for m in model_pat.finditer(content):
    name = m.group(1)
    per_model[name] = {
        'input': num(m.group(2)), 'output': num(m.group(3)),
        'cache_read': num(m.group(4)), 'cache_write': num(m.group(5)),
        'cost': float(m.group(6)),
    }

tools_used = sorted(set(re.findall(r'[\u2022\u25A0\u25CF\u2192]\s*([A-Z][A-Za-z]+)\(', content)))[:20]

metrics = {
    'input_tokens': input_tokens,
    'output_tokens': output_tokens,
    'cache_read_tokens': cache_read,
    'cache_creation_tokens': 0,
    'turns': 0,
    'tools_used': tools_used,
    'duration_ms': 0,
    'total_cost_usd': round(cost, 6),
    'per_model_usage': per_model,
    'mode': 'tmux-handoff',
}
with open('/workspace/.thunderdome-metrics.json', 'w') as f:
    json.dump(metrics, f, indent=2)
print(f"Metrics: in={input_tokens} cached={cache_read} out={output_tokens} cost=${cost:.4f}", file=sys.stderr)
print(f"  per-model: {list(per_model.keys())}", file=sys.stderr)
PYEOF

exit 0
