#!/bin/bash
set -e

# --- OpenAI Codex CLI + GPT-5.5 via ChatGPT OAuth (Plus subscription) ---
# gpt-5.5 is not yet exposed on the OpenAI REST API, but IS available to
# Codex CLI >=0.124 through ChatGPT account auth. Requires a fresh
# /tmp/.codex-auth.json mounted in (export from host ~/.codex/auth.json).
# Cost is subscription-covered — token usage is tracked but priced at $0.

[[ -f "$TASK_DESCRIPTION" ]] || { echo "Task file not found: $TASK_DESCRIPTION" >&2; exit 2; }

cd "$TASK_DIR"

export HOME=/tmp
mkdir -p "$HOME/.codex"

if [ -f /tmp/.codex-auth.json ]; then
  cp /tmp/.codex-auth.json "$HOME/.codex/auth.json"
  chmod 600 "$HOME/.codex/auth.json"
else
  echo "ERROR: /tmp/.codex-auth.json not found — mount ~/.codex/auth.json from an OAuth'd host" >&2
  exit 3
fi

if [ -f /tmp/.codex-config.toml ]; then
  cp /tmp/.codex-config.toml "$HOME/.codex/config.toml"
fi

TASK_PROMPT=$(cat "$TASK_DESCRIPTION")
OUTPUT_FILE=/workspace/.thunderdome-output.jsonl
STDERR_FILE=/workspace/.thunderdome-stderr.log

WALL_CLOCK_START=$(date +%s)

set +e
codex exec \
  -m gpt-5.5 \
  --dangerously-bypass-approvals-and-sandbox \
  --skip-git-repo-check \
  --json \
  "$TASK_PROMPT" \
  > "$OUTPUT_FILE" 2> "$STDERR_FILE"
EXIT_CODE=$?
set -e

WALL_CLOCK_END=$(date +%s)
WALL_CLOCK_DURATION=$(( (WALL_CLOCK_END - WALL_CLOCK_START) * 1000 ))

python3 -c "
import json, os, sys

input_tokens = output_tokens = cached_tokens = 0
turns = 0
try:
    with open('$OUTPUT_FILE') as f:
        for line in f:
            line = line.strip()
            if not line: continue
            try:
                ev = json.loads(line)
                mtype = ev.get('type', '')
                if 'usage' in ev:
                    u = ev['usage']
                    input_tokens += u.get('input_tokens', 0) or 0
                    output_tokens += u.get('output_tokens', 0) or 0
                    cached_tokens += u.get('cached_input_tokens', 0) or 0
                if mtype == 'item.completed':
                    item = ev.get('item', {})
                    if item.get('type') == 'agent_message':
                        turns += 1
            except json.JSONDecodeError:
                pass
except FileNotFoundError:
    pass

# gpt-5.5 pricing not yet published on API — impute using gpt-5.4 rates:
# \$1.25/M non-cached input, \$0.125/M cached input, \$10/M output.
# Actual \$ is \$0 (ChatGPT Plus subscription-covered), but this lets the
# cost column be meaningfully compared against API-based adapters.
non_cached_in = max(0, input_tokens - cached_tokens)
cost = (non_cached_in * 1.25 + cached_tokens * 0.125 + output_tokens * 10.0) / 1e6

metrics = {
    'input_tokens': input_tokens,
    'output_tokens': output_tokens,
    'cache_read_tokens': cached_tokens,
    'cache_creation_tokens': 0,
    'turns': turns,
    'duration_ms': $WALL_CLOCK_DURATION,
    'total_cost_usd': round(cost, 6),
}
with open('/workspace/.thunderdome-metrics.json', 'w') as f:
    json.dump(metrics, f, indent=2)
print(f'Metrics: in={input_tokens} cached={cached_tokens} out={output_tokens} turns={turns} imputed_cost=\${cost:.4f}', file=sys.stderr)
" 2>&1 || true

exit $EXIT_CODE
