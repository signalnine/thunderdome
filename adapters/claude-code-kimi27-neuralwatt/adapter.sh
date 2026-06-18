#!/bin/bash
set -e

# --- Claude Code + kimi-k2.7-code via Neuralwatt ---
# Neuralwatt dropped their Anthropic endpoint 2026-04-22; we now bridge
# via anth2openai_proxy.py (Anthropic in, OpenAI-chat-completions out).

[[ -f "$TASK_DESCRIPTION" ]] || { echo "Task file not found: $TASK_DESCRIPTION" >&2; exit 2; }

cd "$TASK_DIR"

PROXY_PORT=18900
PROXY_LOG=/workspace/.anthropic-proxy.jsonl

python3 /usr/local/bin/anth2openai_proxy.py \
  --port $PROXY_PORT \
  --log "$PROXY_LOG" \
  --upstream "https://api.neuralwatt.com/v1" \
  --model "kimi-k2.7-code" \
  --api-key "$NEURALWATT_API_KEY" &
PROXY_PID=$!

for i in $(seq 1 30); do
  curl -s http://localhost:$PROXY_PORT/health >/dev/null 2>&1 && break
  sleep 0.2
done

export ANTHROPIC_BASE_URL="http://localhost:$PROXY_PORT"
export ANTHROPIC_API_KEY="placeholder"

TASK_PROMPT=$(cat "$TASK_DESCRIPTION")
OUTPUT_FILE=/workspace/.thunderdome-output.jsonl

echo "=== Claude Code (Kimi K2.7-Code via Neuralwatt): Starting ==="

set +e
# --disallowed-tools Task: Neuralwatt rate-limits Qwen3.6 to 2 concurrent
# requests per model. Claude Code's Task tool spawns sub-agents that fire
# parallel LLM calls, so one trial can briefly burst to 3+ concurrent and
# trigger 429 cascades. Disabling Task keeps us at 1 concurrent call per
# trial so parallel=2 stays within the budget.
claude -p \
  --output-format stream-json \
  --verbose \
  --dangerously-skip-permissions \
  --disallowed-tools "Task" \
  -- "$TASK_PROMPT" \
  > "$OUTPUT_FILE" 2>/workspace/.thunderdome-stderr.log
CLAUDE_EXIT=$?
set -e

echo "Claude Code exited: $CLAUDE_EXIT"
kill $PROXY_PID 2>/dev/null || true

# Neuralwatt Kimi K2.7-Code: energy-based pricing.
# $5.00/kWh x 121.97 mWh per request = ~$0.00061/turn.
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

cost = turns * 0.00061

metrics = {
    'input_tokens': input_t,
    'output_tokens': output_t,
    'cache_read_tokens': cache_read,
    'cache_creation_tokens': cache_create,
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
print(f\"Metrics: in={input_t} out={output_t} cache_read={cache_read} turns={turns} cost=\${cost:.4f}\")
"

echo "=== Claude Code (Kimi K2.7-Code via Neuralwatt) adapter complete ==="
exit $CLAUDE_EXIT
