#!/bin/bash
set -e

[[ -f "$TASK_DESCRIPTION" ]] || { echo "Task file not found: $TASK_DESCRIPTION" >&2; exit 2; }

cd "$TASK_DIR"

# Set up Cerebras auth
mkdir -p "$HOME/.local/share/opencode"
cat > "$HOME/.local/share/opencode/auth.json" <<EOF
{
  "cerebras": {
    "api_key": "${CEREBRAS_API_KEY}"
  }
}
EOF

TASK_PROMPT=$(cat "$TASK_DESCRIPTION")

set +e
cerebras-cli run \
  -m cerebras/gpt-oss-120b \
  --format json \
  "$TASK_PROMPT" \
  2>/workspace/.thunderdome-stderr.log \
  | tee /workspace/.cerebras-stdout.log
EXIT_CODE=${PIPESTATUS[0]}
set -e

# Parse metrics from JSON output
python3 -c "
import json, sys

total_input = 0
total_output = 0
total_cache_read = 0
total_cache_write = 0

with open('/workspace/.cerebras-stdout.log', 'r', errors='replace') as f:
    for line in f:
        line = line.strip()
        if not line:
            continue
        try:
            event = json.loads(line)
        except json.JSONDecodeError:
            continue
        if event.get('type') == 'step_finish':
            part = event.get('part', {})
            tokens = part.get('tokens', {})
            total_input += tokens.get('input', 0)
            total_output += tokens.get('output', 0)
            cache = tokens.get('cache', {})
            total_cache_read += cache.get('read', 0)
            total_cache_write += cache.get('write', 0)

metrics = {
    'input_tokens': total_input,
    'output_tokens': total_output,
    'cache_read_tokens': total_cache_read,
    'cache_creation_tokens': total_cache_write,
    'total_cost_usd': 0.0,
}
with open('/workspace/.thunderdome-metrics.json', 'w') as f:
    json.dump(metrics, f, indent=2)
print(f'Metrics: in={total_input} out={total_output} cache_r={total_cache_read} cache_w={total_cache_write}', file=sys.stderr)
" 2>&1 || true

exit $EXIT_CODE
