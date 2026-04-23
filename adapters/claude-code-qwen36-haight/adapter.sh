#!/bin/bash
set -e

# --- Claude Code + Qwen3.6-27B-NVFP4 on local haight vLLM ---
# Uses anth2openai_proxy.py (baked into the claude-code image) to
# translate Anthropic <-> OpenAI. Local endpoint, no per-model cap
# (haight handles ~16 concurrent), so Task tool stays enabled.

[[ -f "$TASK_DESCRIPTION" ]] || { echo "Task file not found: $TASK_DESCRIPTION" >&2; exit 2; }

cd "$TASK_DIR"

PROXY_PORT=18900
PROXY_LOG=/workspace/.anthropic-proxy.jsonl

python3 /usr/local/bin/anth2openai_proxy.py \
  --port $PROXY_PORT \
  --log "$PROXY_LOG" \
  --upstream "http://haight:8080/v1" \
  --model "sakamakismile/Qwen3.6-27B-NVFP4" \
  --api-key "none" &
PROXY_PID=$!

for i in $(seq 1 30); do
  curl -s http://localhost:$PROXY_PORT/health >/dev/null 2>&1 && break
  sleep 0.2
done

export ANTHROPIC_BASE_URL="http://localhost:$PROXY_PORT"
export ANTHROPIC_API_KEY="placeholder"

TASK_PROMPT=$(cat "$TASK_DESCRIPTION")
OUTPUT_FILE=/workspace/.thunderdome-output.jsonl

echo "=== Claude Code (Qwen3.6-27B-NVFP4 on haight): Starting ==="

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
kill $PROXY_PID 2>/dev/null || true

# Local vLLM - cost $0. Still emit metrics for token accounting.
python3 -c "
import json, os
log = '$PROXY_LOG'
input_t = output_t = turns = 0
if os.path.exists(log):
    for line in open(log):
        try:
            d = json.loads(line)
            input_t += d.get('input_tokens', 0)
            output_t += d.get('output_tokens', 0)
            turns += 1
        except: pass
metrics = {
    'input_tokens': input_t,
    'output_tokens': output_t,
    'cache_read_tokens': 0,
    'cache_creation_tokens': 0,
    'turns': turns,
    'duration_ms': 0,
    'total_cost_usd': 0.0,
}
try:
    for line in open('$OUTPUT_FILE'):
        msg = json.loads(line)
        if msg.get('type') == 'result':
            metrics['duration_ms'] = msg.get('duration_ms', 0)
            break
except: pass
json.dump(metrics, open('/workspace/.thunderdome-metrics.json', 'w'), indent=2)
print(f'Metrics: in={input_t} out={output_t} turns={turns}')
"

echo "=== Claude Code (Qwen3.6-27B-NVFP4 on haight) adapter complete ==="
exit $CLAUDE_EXIT
