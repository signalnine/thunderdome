#!/bin/bash
set -e

# crush-glm51-fast-neuralwatt: GLM-5.1-fast via Neuralwatt's OpenAI-compatible API.
# Uses the proxy's model-rewrite feature since CRUSH validates -m flags
# against its internal registry -- we alias the real model as "glm-5".

[[ -f "$TASK_DESCRIPTION" ]] || { echo "Task file not found: $TASK_DESCRIPTION" >&2; exit 2; }

cd "$TASK_DIR"

export HOME=/tmp

# Find a free port for the proxy
PROXY_PORT=$(python3 -c "import socket; s=socket.socket(); s.bind(('',0)); print(s.getsockname()[1]); s.close()")
PROXY_LOG=/tmp/proxy-usage.jsonl

# Start the OpenAI-compatible proxy with model rewrite
python3 /usr/local/bin/openai_proxy.py \
  --port "$PROXY_PORT" \
  --log "$PROXY_LOG" \
  --upstream "https://api.neuralwatt.com/v1" \
  --model-rewrite "glm-5=glm-5.1-fast" \
  2>/dev/null &
PROXY_PID=$!

# Wait for proxy to be ready
for i in {1..10}; do
  if python3 -c "import urllib.request; urllib.request.urlopen('http://localhost:$PROXY_PORT/health', timeout=1)" 2>/dev/null; then
    break
  fi
  sleep 0.5
done

# CRUSH sees glm-5; proxy rewrites to glm-5.1-fast for Neuralwatt
cat > /tmp/.local/share/crush/crush.json << EOF
{"providers":{"zai":{"api_key":"$NEURALWATT_API_KEY","base_url":"http://localhost:$PROXY_PORT"}},"models":{"large":{"model":"glm-5","provider":"zai","max_tokens":65536},"small":{"model":"glm-5","provider":"zai","max_tokens":65536}}}
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

sleep 0.5
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

# GLM-5.1 Fast Neuralwatt pricing: $1.10/1M input, $0.51/1M output (33% less output than GLM-5.1)
INPUT_COST=$(python3 -c "print($INPUT_TOKENS * 1.10 / 1000000)")
OUTPUT_COST=$(python3 -c "print($OUTPUT_TOKENS * 0.51 / 1000000)")
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
