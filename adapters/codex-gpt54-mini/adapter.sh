#!/bin/bash
set -e

# --- OpenAI Codex CLI + GPT-5.4-mini ---
# Cheaper tier of GPT-5.4 for a fair cost comparison against Gemini 3 Flash.

[[ -f "$TASK_DESCRIPTION" ]] || { echo "Task file not found: $TASK_DESCRIPTION" >&2; exit 2; }

cd "$TASK_DIR"

export HOME=/tmp
mkdir -p "$HOME/.codex"

: "${OPENAI_API_KEY:?OPENAI_API_KEY is required for this adapter}"
printenv OPENAI_API_KEY | codex login --with-api-key | tail -3
codex_status=${PIPESTATUS[1]}
if [[ $codex_status -ne 0 ]]; then
    echo "codex login failed (exit $codex_status)" >&2
    exit 2
fi

TASK_PROMPT=$(cat "$TASK_DESCRIPTION")
OUTPUT_FILE=/workspace/.thunderdome-output.jsonl
STDERR_FILE=/workspace/.thunderdome-stderr.log

WALL_CLOCK_START=$(date +%s)

set +e
codex exec \
  -m gpt-5.4-mini \
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

# GPT-5.4-mini pricing: \$0.25/M input, \$2.00/M output, \$0.025/M cached.
non_cached_in = max(0, input_tokens - cached_tokens)
cost = (non_cached_in * 0.25 + cached_tokens * 0.025 + output_tokens * 2.00) / 1e6

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
print(f'Metrics: in={input_tokens} cached={cached_tokens} out={output_tokens} turns={turns} cost=\${cost:.4f}', file=sys.stderr)
" 2>&1 || true

exit $EXIT_CODE
