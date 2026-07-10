#!/bin/bash
set -e

[[ -f "$TASK_DESCRIPTION" ]] || { echo "Task file not found: $TASK_DESCRIPTION" >&2; exit 2; }

cd "$TASK_DIR"

# --- CRUSH + Poolside Laguna-M.1 via OpenRouter ---
# Codex is BLOCKED for this model: codex 0.141 sends its native `namespace`
# tool type over the Responses API, which Poolside's OpenRouter endpoint
# rejects ("No endpoints found that support the native namespace tool type").
# CRUSH sends function-format tools, which Laguna supports (verified 2026-07-10).
# Laguna is a reasoning model; --exclude-reasoning keeps reasoning ON in the
# model but strips it from the response (reasoning.exclude=true) so CRUSH's
# context stays clean between turns.

# Use /tmp as HOME so Crush can write config/session files
export HOME=/tmp

# Find a free port for the proxy
PROXY_PORT=$(python3 -c "import socket; s=socket.socket(); s.bind(('',0)); print(s.getsockname()[1]); s.close()")
PROXY_LOG=/workspace/proxy-usage.jsonl
PROXY_TRACE=/workspace/proxy-trace.log

# OpenAI-compatible proxy -> OpenRouter, rewriting the placeholder model id to
# poolside/laguna-m.1 and excluding reasoning from the returned messages.
python3 /usr/local/bin/openai_proxy.py \
  --port "$PROXY_PORT" \
  --log "$PROXY_LOG" \
  --upstream "https://openrouter.ai/api/v1" \
  --model-rewrite "*=poolside/laguna-m.1" \
  --exclude-reasoning \
  > "$PROXY_TRACE" 2>&1 &
PROXY_PID=$!

# Wait for proxy to be ready
for i in {1..10}; do
  if python3 -c "import urllib.request; urllib.request.urlopen('http://localhost:$PROXY_PORT/health', timeout=1)" 2>/dev/null; then
    break
  fi
  sleep 0.5
done

# Use glm-5 as the model ID (crush validates against its internal registry).
# The proxy rewrites glm-5 -> poolside/laguna-m.1 for the upstream API.
cat > /tmp/.local/share/crush/crush.json << EOF
{"providers":{"zai":{"api_key":"$OPENROUTER_API_KEY","base_url":"http://localhost:$PROXY_PORT"}},"models":{"large":{"model":"glm-5","provider":"zai","max_tokens":65536},"small":{"model":"glm-5","provider":"zai","max_tokens":65536}}}
EOF

TASK_PROMPT=$(cat "$TASK_DESCRIPTION")
OUTPUT_FILE=/workspace/.thunderdome-output.txt
STDERR_FILE=/workspace/.thunderdome-stderr.log

set +e
crush run \
  -m zai/glm-5 \
  -c "$TASK_DIR" \
  --quiet \
  -- "$TASK_PROMPT" \
  > "$OUTPUT_FILE" 2> "$STDERR_FILE"
CRUSH_EXIT=$?
set -e

# Give proxy a moment to finish writing logs
sleep 0.5

# Stop the proxy
kill $PROXY_PID 2>/dev/null || true

# Parse proxy logs for token usage
INPUT_TOKENS=0
OUTPUT_TOKENS=0
if [[ -f "$PROXY_LOG" ]]; then
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    in_tok=$(echo "$line" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('input_tokens',0))" 2>/dev/null || echo 0)
    out_tok=$(echo "$line" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('output_tokens',0))" 2>/dev/null || echo 0)
    INPUT_TOKENS=$((INPUT_TOKENS + in_tok))
    OUTPUT_TOKENS=$((OUTPUT_TOKENS + out_tok))
  done < "$PROXY_LOG"
fi

# Laguna-M.1 pricing per OpenRouter: $0.20/1M input, $0.40/1M output.
# Reasoning tokens (excluded from output) still bill at the output rate.
INPUT_COST=$(python3 -c "print($INPUT_TOKENS * 0.20 / 1000000)")
OUTPUT_COST=$(python3 -c "print($OUTPUT_TOKENS * 0.40 / 1000000)")
TOTAL_COST=$(python3 -c "print($INPUT_COST + $OUTPUT_COST)")

cat > /workspace/.thunderdome-metrics.json << EOF
{
  "input_tokens": $INPUT_TOKENS,
  "output_tokens": $OUTPUT_TOKENS,
  "cache_read_tokens": 0,
  "cache_creation_tokens": 0,
  "turns": 1,
  "total_cost_usd": $TOTAL_COST
}
EOF

exit $CRUSH_EXIT
