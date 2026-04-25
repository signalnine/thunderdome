#!/bin/bash
set -e

# --- grok-agent + grok-code-fast-1 ---
# Uses https://npm.im/grok-agent (xAI coding CLI). Non-interactive mode
# via positional prompt argument. --show-usage emits a trailing
# "Tokens: in=X cached=Y out=Z | Cost: $N" line we parse.

[[ -f "$TASK_DESCRIPTION" ]] || { echo "Task file not found: $TASK_DESCRIPTION" >&2; exit 2; }

cd "$TASK_DIR"

export HOME=/tmp
mkdir -p "$HOME/.grok"

TASK_PROMPT=$(cat "$TASK_DESCRIPTION")
OUTPUT_FILE=/workspace/.thunderdome-output.log
STDERR_FILE=/workspace/.thunderdome-stderr.log

WALL_CLOCK_START=$(date +%s)

set +e
grok-agent \
  --code \
  --show-usage \
  --max-turns 400 \
  --cwd "$TASK_DIR" \
  "$TASK_PROMPT" \
  > "$OUTPUT_FILE" 2> "$STDERR_FILE"
EXIT_CODE=$?
set -e

# grok-agent writes session log to stderr (tool calls, diffs, token summary).
# Merge stderr into the file we parse for metrics.
cat "$STDERR_FILE" >> "$OUTPUT_FILE"

WALL_CLOCK_END=$(date +%s)
WALL_CLOCK_DURATION=$(( (WALL_CLOCK_END - WALL_CLOCK_START) * 1000 ))

python3 -c "
import re, json, sys

input_tokens = output_tokens = cached_tokens = 0
cost = 0.0
turns = 0

try:
    with open('$OUTPUT_FILE') as f:
        content = f.read()
    # Find last 'Tokens: in=X cached=Y out=Z | Cost: \$N.NN'
    # Numbers may contain commas (e.g. 8,268).
    m = re.findall(r'Tokens:\s*in=([\d,]+)(?:\s+cached=([\d,]+))?\s+out=([\d,]+)\s*\|\s*Cost:\s*\\\$([\d.]+)', content)
    if m:
        last = m[-1]
        input_tokens = int(last[0].replace(',', ''))
        cached_tokens = int(last[1].replace(',', '')) if last[1] else 0
        output_tokens = int(last[2].replace(',', ''))
        cost = float(last[3])
    # Count tool calls as proxy for turns
    turns = len(re.findall(r'^\s*[►✓]', content, re.MULTILINE))
except Exception as e:
    print(f'parse failed: {e}', file=sys.stderr)

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
