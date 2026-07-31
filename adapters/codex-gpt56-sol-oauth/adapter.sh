#!/bin/bash
set -e

# --- OpenAI Codex CLI + GPT-5.6 Sol via ChatGPT OAuth (subscription) ---
#
# Top tier of the GPT-5.6 series. Run on the SUBSCRIPTION rather than metered
# because Sol lists at $5.00/M input / $30.00/M output -- a 21-task suite on the
# API is real money, which is exactly the case where a subscription pays off.
# The cheap tier (Luna, $0.10/$0.60) is deliberately metered instead, because
# there the whole point is measuring $/task and a subscription would report $0.
#
# Auth: the harness auto-mounts host ~/.codex/auth.json read-only to
# /tmp/.codex-auth.json (internal/runner/trial.go). Requires an OAuth'd host --
# `codex login` with a ChatGPT account. Actual spend is $0; the cost column below
# is an IMPUTED API-equivalent so this arm stays comparable to metered ones.
#
# NOTE: this adapter deliberately does NOT copy the host's config.toml, unlike
# adapters/codex-gpt55-oauth. The host config is a personal working file -- it
# currently carries model_reasoning_effort=xhigh, a personality setting, and
# per-project trust entries -- so copying it silently imports whatever the user
# happened to set that day and makes runs non-reproducible. We write a minimal
# config here and pin the model on the CLI, which overrides config either way.

[[ -f "$TASK_DESCRIPTION" ]] || { echo "Task file not found: $TASK_DESCRIPTION" >&2; exit 2; }

cd "$TASK_DIR"

export HOME=/tmp
mkdir -p "$HOME/.codex"

if [ -f /tmp/.codex-auth.json ]; then
  cp /tmp/.codex-auth.json "$HOME/.codex/auth.json"
  chmod 600 "$HOME/.codex/auth.json"
else
  echo "ERROR: /tmp/.codex-auth.json not found." >&2
  echo "  The harness mounts host ~/.codex/auth.json automatically; run 'codex login'" >&2
  echo "  on the host with a ChatGPT account first." >&2
  exit 3
fi

# Minimal, explicit config -- reasoning effort held at 'high' to match the
# metered Luna arm so the tier ladder differs only by model.
cat > "$HOME/.codex/config.toml" <<'TOML'
model = "gpt-5.6-sol"
model_reasoning_effort = "high"
TOML

TASK_PROMPT=$(cat "$TASK_DESCRIPTION")
OUTPUT_FILE=/workspace/.thunderdome-output.jsonl
STDERR_FILE=/workspace/.thunderdome-stderr.log

WALL_CLOCK_START=$(date +%s)

set +e
codex exec \
  -m gpt-5.6-sol \
  --dangerously-bypass-approvals-and-sandbox \
  --skip-git-repo-check \
  --json \
  "$TASK_PROMPT" \
  > "$OUTPUT_FILE" 2> "$STDERR_FILE"
EXIT_CODE=$?
set -e

WALL_CLOCK_END=$(date +%s)
WALL_CLOCK_DURATION=$(( (WALL_CLOCK_END - WALL_CLOCK_START) * 1000 ))

# Codex 0.141 (--json) reports CUMULATIVE usage in each 'turn.completed', so we
# take the LAST one. adapters/codex-gpt55-oauth sums instead, which double-counts
# on this codex version -- do not copy that pattern.
python3 -c "
import json, sys

input_tokens = output_tokens = cached = 0
turns = 0
try:
    with open('$OUTPUT_FILE') as f:
        for line in f:
            line = line.strip()
            if not line: continue
            try:
                ev = json.loads(line)
            except json.JSONDecodeError:
                continue
            etype = ev.get('type', ev.get('msg', {}).get('type', ''))
            if etype == 'turn.completed':
                turns += 1
                u = ev.get('usage', {}) or {}
                input_tokens = u.get('input_tokens', input_tokens) or input_tokens
                output_tokens = u.get('output_tokens', output_tokens) or output_tokens
                cached = u.get('cached_input_tokens', cached) or cached
except FileNotFoundError:
    pass

# IMPUTED cost -- actual spend is \$0 (subscription). GPT-5.6 Sol lists at
# \$5.00/M input, \$30.00/M output (checked against OpenRouter's live
# /api/v1/models on 2026-07-30). Cached input is billed at the FULL input rate,
# matching the metered Luna arm's convention, so every arm is a consistent UPPER
# BOUND; real API spend would be lower given cache discounts.
cost = input_tokens * 5.00 / 1e6 + output_tokens * 30.00 / 1e6

metrics = {
    'input_tokens': input_tokens,
    'output_tokens': output_tokens,
    'cache_read_tokens': cached,
    'cache_creation_tokens': 0,
    'turns': turns,
    'duration_ms': $WALL_CLOCK_DURATION,
    'total_cost_usd': round(cost, 6),
    'cost_basis': 'imputed-api-equivalent; actual \$0 via ChatGPT subscription',
}
with open('/workspace/.thunderdome-metrics.json', 'w') as f:
    json.dump(metrics, f, indent=2)
print(f'Metrics: in={input_tokens} cached={cached} out={output_tokens} turns={turns} imputed=\${cost:.4f}', file=sys.stderr)
" 2>&1 || true

exit $EXIT_CODE
