#!/bin/bash
set -e

[[ -f "$TASK_DESCRIPTION" ]] || { echo "Task file not found: $TASK_DESCRIPTION" >&2; exit 2; }

cd "$TASK_DIR"

# Copy Gemini OAuth credentials from read-only mount to writable HOME
export HOME=/tmp
if [[ -d /tmp/.gemini-host ]]; then
  cp -r /tmp/.gemini-host "$HOME/.gemini"
  chmod -R u+rw "$HOME/.gemini"
fi

TASK_PROMPT=$(cat "$TASK_DESCRIPTION")

set +e
gemini -p "$TASK_PROMPT" \
  --yolo \
  --sandbox false \
  --output-format json \
  2>/workspace/.thunderdome-stderr.log \
  > /workspace/.gemini-output.json
EXIT_CODE=$?
set -e

# Parse token usage from Gemini CLI JSON output and write metrics file.
python3 -c "
import json, sys

try:
    with open('/workspace/.gemini-output.json', 'r') as f:
        data = json.load(f)
except Exception as e:
    print(f'Failed to parse gemini output: {e}', file=sys.stderr)
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
    # 'input' = non-cached input, 'cached' = cached input, 'prompt' = total
    total_input += tokens.get('input', 0)
    total_output += tokens.get('candidates', 0)
    total_cached += tokens.get('cached', 0)
    total_thoughts += tokens.get('thoughts', 0)

# Gemini CLI with Google One OAuth — no per-token billing,
# but estimate equivalent API cost for comparison.
# Gemini 3 Flash (primary model): \$0.10/1M input, \$0.40/1M output, \$0.025/1M cached
# 'input' is already non-cached; don't subtract cached again
cost = (total_input * 0.10 + total_output * 0.40 + total_cached * 0.025) / 1e6

turns = tools.get('totalCalls', 0)

metrics = {
    'input_tokens': total_input,
    'output_tokens': total_output,
    'cache_read_tokens': total_cached,
    'cache_creation_tokens': 0,
    'thought_tokens': total_thoughts,
    'turns': turns,
    'total_cost_usd': round(cost, 6),
    'note': 'google-one-oauth-no-actual-cost',
}
with open('/workspace/.thunderdome-metrics.json', 'w') as f:
    json.dump(metrics, f, indent=2)

# Print the response to stdout so harness can capture it
print(data.get('response', ''))
" 2>&1 || true

exit $EXIT_CODE
