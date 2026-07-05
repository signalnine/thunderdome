#!/bin/bash
set -e

# --- Claude Code with GLM-5 via z.ai Anthropic-compatible endpoint ---
# Uses anthropic_proxy.py to rewrite model names and log token usage.

[[ -f "$TASK_DESCRIPTION" ]] || { echo "Task file not found: $TASK_DESCRIPTION" >&2; exit 2; }

cd "$TASK_DIR"

# Start Anthropic proxy: rewrites claude model names to glm-5,
# forwards to z.ai's Anthropic-compatible endpoint
PROXY_PORT=18900
PROXY_LOG=/workspace/.anthropic-proxy.jsonl

python3 /usr/local/bin/anthropic_proxy.py \
  --port $PROXY_PORT \
  --log "$PROXY_LOG" \
  --upstream "https://api.z.ai/api/anthropic" \
  --model-rewrite "claude=glm-5" \
  --api-key "$ZHIPU_API_KEY" &
PROXY_PID=$!

# Wait for proxy to be ready
for i in $(seq 1 30); do
  curl -s http://localhost:$PROXY_PORT/health >/dev/null 2>&1 && break
  sleep 0.2
done

# Point Claude Code at our proxy
export ANTHROPIC_BASE_URL="http://localhost:$PROXY_PORT"
# Claude Code needs an API key even though the proxy overrides it
export ANTHROPIC_API_KEY="placeholder"

TASK_PROMPT=$(cat "$TASK_DESCRIPTION")
OUTPUT_FILE=/workspace/.thunderdome-output.jsonl

echo "=== Claude Code (GLM-5 via z.ai): Starting ==="

set +e
claude -p \
  --output-format stream-json \
  --verbose \
  --dangerously-skip-permissions \
  -- "$TASK_PROMPT" \
  > "$OUTPUT_FILE" 2>/workspace/.thunderdome-stderr.log
CLAUDE_EXIT=$?
set -e

echo "Claude Code exited: $CLAUDE_EXIT"

# Stop proxy
kill $PROXY_PID 2>/dev/null || true

# Extract metrics from proxy log (accurate token counts from z.ai)
# GLM-5 pricing: $1.00/1M input, $3.20/1M output, ~$0.10/1M cache read
python3 -c "
import json, os

log = '$PROXY_LOG'
input_t = output_t = cache_read = cache_create = turns = 0
if os.path.exists(log):
    for line in open(log):
        try:
            d = json.loads(line)
            input_t += d.get('input_tokens', 0)
            output_t += d.get('output_tokens', 0)
            cache_read += d.get('cache_read_input_tokens', 0)
            cache_create += d.get('cache_creation_input_tokens', 0)
            turns += 1
        except: pass

cost = input_t * 1.0/1e6 + output_t * 3.2/1e6 + cache_read * 0.1/1e6

metrics = {
    'input_tokens': input_t,
    'output_tokens': output_t,
    'cache_read_tokens': cache_read,
    'cache_creation_tokens': cache_create,
    'turns': turns,
    'duration_ms': 0,
    'total_cost_usd': round(cost, 6)
}

# Try to get duration from Claude Code's output
try:
    for line in open('$OUTPUT_FILE'):
        msg = json.loads(line)
        if msg.get('type') == 'result':
            metrics['duration_ms'] = msg.get('duration_ms', 0)
            break
except: pass

json.dump(metrics, open('/workspace/.thunderdome-metrics.json', 'w'), indent=2)
print(f\"Metrics: in={input_t} out={output_t} cache_read={cache_read} turns={turns} cost=\${cost:.4f}\")
"

echo "=== Claude Code (GLM-5) adapter complete ==="
exit $CLAUDE_EXIT
