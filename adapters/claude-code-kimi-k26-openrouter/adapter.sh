#!/bin/bash
set -e

# --- Claude Code + Kimi K2.6 via OpenRouter ---
# Kimi K2.6 (moonshotai/kimi-k2.6) at $0.74/M input, $4.66/M output, 256K ctx.
# OpenRouter is OpenAI-compatible, so anth2openai_proxy.py (baked into the
# claude-code image) does Anthropic <-> OpenAI translation. Routes Claude
# Code's tool_use blocks through OpenAI tool calling and back.

[[ -f "$TASK_DESCRIPTION" ]] || { echo "Task file not found: $TASK_DESCRIPTION" >&2; exit 2; }

cd "$TASK_DIR"

PROXY_PORT=18900
PROXY_LOG=/workspace/.anthropic-proxy.jsonl

python3 /usr/local/bin/anth2openai_proxy.py \
  --port $PROXY_PORT \
  --log "$PROXY_LOG" \
  --upstream "https://openrouter.ai/api/v1" \
  --model "moonshotai/kimi-k2.6" \
  --api-key "$OPENROUTER_API_KEY" &
PROXY_PID=$!

for i in $(seq 1 30); do
  curl -s http://localhost:$PROXY_PORT/health >/dev/null 2>&1 && break
  sleep 0.2
done

export ANTHROPIC_BASE_URL="http://localhost:$PROXY_PORT"
export ANTHROPIC_API_KEY="placeholder"

TASK_PROMPT=$(cat "$TASK_DESCRIPTION")
OUTPUT_FILE=/workspace/.thunderdome-output.jsonl

echo "=== Claude Code (Kimi K2.6 via OpenRouter): Starting ==="

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

# Kimi K2.6 pricing per OpenRouter: $0.74/M input, $4.66/M output.
# K2.6 is a thinking model -- reasoning tokens billed at output rate.
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

cost = input_t * 0.74/1e6 + output_t * 4.66/1e6

metrics = {
    'input_tokens': input_t,
    'output_tokens': output_t,
    'cache_read_tokens': 0,
    'cache_creation_tokens': 0,
    'turns': turns,
    'duration_ms': 0,
    'total_cost_usd': round(cost, 6)
}
try:
    for line in open('$OUTPUT_FILE'):
        msg = json.loads(line)
        if msg.get('type') == 'result':
            metrics['duration_ms'] = msg.get('duration_ms', 0)
            break
except: pass
json.dump(metrics, open('/workspace/.thunderdome-metrics.json', 'w'), indent=2)
print(f'Metrics: in={input_t} out={output_t} turns={turns} cost=\${cost:.4f}')
"

echo "=== Claude Code (Kimi K2.6) adapter complete ==="
exit $CLAUDE_EXIT
