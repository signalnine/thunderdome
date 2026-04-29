#!/bin/bash
set -e

# --- Claude Code + Kimi K2-0905 via OpenRouter ---
# Kimi K2-0905 (moonshotai/kimi-k2-0905) at $0.40/M input, $2.00/M output, 256K ctx.
# OpenRouter is OpenAI-compatible, so anth2openai_proxy.py (baked into the
# claude-code image) does Anthropic <-> OpenAI translation. Routes Claude
# Code's tool_use blocks through OpenAI tool calling and back.

[[ -f "$TASK_DESCRIPTION" ]] || { echo "Task file not found: $TASK_DESCRIPTION" >&2; exit 2; }

cd "$TASK_DIR"

PROXY_PORT=18900
PROXY_LOG=/workspace/.anthropic-proxy.jsonl
PROXY_TRACE=/workspace/.anthropic-proxy.trace.jsonl

python3 /usr/local/bin/anth2openai_proxy.py \
  --port $PROXY_PORT \
  --log "$PROXY_LOG" \
  --trace "$PROXY_TRACE" \
  --upstream "https://openrouter.ai/api/v1" \
  --model "moonshotai/kimi-k2-0905" \
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

echo "=== Claude Code (Kimi K2-0905 via OpenRouter): Starting ==="

set +e
# K2 family on Claude Code: TodoWrite is a trap. The system prompt biases K2
# to call TodoWrite first; K2 then treats the planning call as sufficient
# work and end_turns. Disallowing TodoWrite forces K2 to engage real work
# tools (Read, Write, Edit, Bash) on the first turn.
claude -p \
  --output-format stream-json \
  --verbose \
  --dangerously-skip-permissions \
  --disallowed-tools "TodoWrite,Task,AskUserQuestion,EnterPlanMode" \
  --append-system-prompt "Do NOT plan before working. Start writing code immediately. Use Read, Write, Edit, and Bash tools to inspect the codebase and make changes. Run tests after each change. Continue working until all tests pass." \
  -- "$TASK_PROMPT" \
  > "$OUTPUT_FILE" 2>/workspace/.thunderdome-stderr.log
CLAUDE_EXIT=$?
set -e

echo "Claude Code exited: $CLAUDE_EXIT"
kill $PROXY_PID 2>/dev/null || true

# Kimi K2-0905 pricing per OpenRouter: $0.40/M input, $2.00/M output.
# K2-0905 is non-thinking -- standard tool-use loop.
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

cost = input_t * 0.40/1e6 + output_t * 2.00/1e6

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

echo "=== Claude Code (Kimi K2-0905) adapter complete ==="
exit $CLAUDE_EXIT
