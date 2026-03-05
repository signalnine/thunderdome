#!/bin/bash
set -e

[[ -f "$TASK_DESCRIPTION" ]] || { echo "Task file not found: $TASK_DESCRIPTION" >&2; exit 2; }

cd "$TASK_DIR"

# Point aider at Cerebras API (OpenAI-compatible)
export OPENAI_API_KEY="${CEREBRAS_API_KEY}"
export OPENAI_API_BASE="https://api.cerebras.ai/v1"

# Collect all source files for aider to edit (ts, js, json configs)
SOURCE_FILES=()
while IFS= read -r -d '' f; do
  SOURCE_FILES+=("$f")
done < <(find . -maxdepth 4 \( -name '*.ts' -o -name '*.js' -o -name '*.json' \) \
  ! -path '*/node_modules/*' ! -path '*/.git/*' ! -path '*/dist/*' ! -name 'package-lock.json' \
  -print0 2>/dev/null)

set +e
aider \
  --yes-always \
  --no-auto-commits \
  --model openai/gpt-oss-120b \
  --edit-format diff \
  --map-tokens 2048 \
  --message-file "$TASK_DESCRIPTION" \
  "${SOURCE_FILES[@]}" \
  2>/workspace/.thunderdome-stderr.log \
  | tee /workspace/.aider-stdout.log
EXIT_CODE=${PIPESTATUS[0]}
set -e

# Parse cost from Aider's console output and write metrics file.
python3 -c "
import re, json, sys

last_cost = 0.0
last_sent = 0
last_received = 0

def parse_tokens(s):
    s = s.strip().lower()
    if s.endswith('k'):
        return int(float(s[:-1]) * 1000)
    elif s.endswith('m'):
        return int(float(s[:-1]) * 1000000)
    return int(s.replace(',', ''))

with open('/workspace/.aider-stdout.log', 'r', errors='replace') as f:
    for line in f:
        clean = re.sub(r'\x1b\[[0-9;]*m', '', line)
        m = re.search(r'Cost:\s*\\\$([\\d.]+)\s*message,\s*\\\$([\\d.]+)\s*session', clean)
        if m:
            last_cost = float(m.group(2))
        m2 = re.search(r'Tokens:\s*([\d.]+[kKmM]?)\s*sent,\s*([\d.]+[kKmM]?)\s*received', clean)
        if m2:
            last_sent = parse_tokens(m2.group(1))
            last_received = parse_tokens(m2.group(2))

metrics = {
    'input_tokens': last_sent,
    'output_tokens': last_received,
    'cache_read_tokens': 0,
    'cache_creation_tokens': 0,
    'total_cost_usd': round(last_cost, 6),
}
with open('/workspace/.thunderdome-metrics.json', 'w') as f:
    json.dump(metrics, f, indent=2)
print(f'Metrics: in={last_sent} out={last_received} cost=\${last_cost:.4f}', file=sys.stderr)
" 2>&1 || true

exit $EXIT_CODE
