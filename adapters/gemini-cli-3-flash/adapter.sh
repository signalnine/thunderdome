#!/bin/bash
set -e

# --- Gemini CLI + Gemini 3 Flash (paid API key) ---
# Uses GEMINI_API_KEY instead of Google One OAuth to avoid free-tier
# quota exhaustion during full-suite sweeps.

[[ -f "$TASK_DESCRIPTION" ]] || { echo "Task file not found: $TASK_DESCRIPTION" >&2; exit 2; }

cd "$TASK_DIR"

export HOME=/tmp

TASK_PROMPT=$(cat "$TASK_DESCRIPTION")

set +e
gemini -p "$TASK_PROMPT" \
  --model gemini-3-flash-preview \
  --yolo \
  --sandbox false \
  --output-format json \
  2>/workspace/.thunderdome-stderr.log \
  > /workspace/.gemini-output.json
EXIT_CODE=$?
set -e

if [[ $EXIT_CODE -ne 0 ]] && grep -qi 'quota' /workspace/.thunderdome-stderr.log 2>/dev/null; then
  echo "ERROR: Gemini API quota exhausted" >&2
  cat /workspace/.thunderdome-stderr.log >&2
  echo '{"input_tokens":0,"output_tokens":0,"cache_read_tokens":0,"cache_creation_tokens":0,"total_cost_usd":0,"note":"quota-exhausted"}' \
    > /workspace/.thunderdome-metrics.json
  exit 2
fi

python3 -c "
import json, sys

try:
    with open('/workspace/.gemini-output.json', 'r') as f:
        data = json.load(f)
except Exception as e:
    print(f'Failed to parse gemini output: {e}', file=sys.stderr)
    metrics = {
        'input_tokens': 0, 'output_tokens': 0,
        'cache_read_tokens': 0, 'cache_creation_tokens': 0,
        'total_cost_usd': 0,
        'note': 'gemini-output-parse-failed',
    }
    with open('/workspace/.thunderdome-metrics.json', 'w') as f:
        json.dump(metrics, f, indent=2)
    sys.exit(0)

stats = data.get('stats', {})
models = stats.get('models', {})
tools = stats.get('tools', {})

total_input = 0
total_output = 0
total_cached = 0
total_thoughts = 0

for model_name, model_data in models.items():
    tokens = model_data.get('tokens', {})
    total_input += tokens.get('input', 0)
    total_output += tokens.get('candidates', 0)
    total_cached += tokens.get('cached', 0)
    total_thoughts += tokens.get('thoughts', 0)

# Gemini 3 Flash Preview pricing per million tokens (same as 2.5 Flash family):
# \$0.30/M input, \$2.50/M output, \$0.03/M cached. Thinking tokens are billed at output rate.
cost = (total_input * 0.30 + (total_output + total_thoughts) * 2.50 + total_cached * 0.03) / 1e6

turns = tools.get('totalCalls', 0)

metrics = {
    'input_tokens': total_input,
    'output_tokens': total_output,
    'cache_read_tokens': total_cached,
    'cache_creation_tokens': 0,
    'thought_tokens': total_thoughts,
    'turns': turns,
    'total_cost_usd': round(cost, 6),
}
with open('/workspace/.thunderdome-metrics.json', 'w') as f:
    json.dump(metrics, f, indent=2)

response = data.get('response', '')
if response:
    print(response)
"

exit $EXIT_CODE
