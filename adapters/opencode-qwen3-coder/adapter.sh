#!/bin/bash
set -e

[[ -f "$TASK_DESCRIPTION" ]] || { echo "Task file not found: $TASK_DESCRIPTION" >&2; exit 2; }

cd "$TASK_DIR"

export HOME=/tmp

# Git identity
git config user.name "OpenCode"
git config user.email "opencode@thunderdome"

# Find a free port for the proxy
PROXY_PORT=$(python3 -c "import socket; s=socket.socket(); s.bind(('',0)); print(s.getsockname()[1]); s.close()")
PROXY_LOG=/tmp/proxy-usage.jsonl

# Start the OpenAI-compatible proxy in the background
python3 /usr/local/bin/openai_proxy.py \
  --port "$PROXY_PORT" \
  --log "$PROXY_LOG" \
  --upstream "https://api.synthetic.new/openai/v1" \
  --auth-key "$SYNTHETIC_API_KEY" \
  2>/dev/null &
PROXY_PID=$!

# Wait for proxy to be ready
for i in {1..10}; do
  if python3 -c "import urllib.request; urllib.request.urlopen('http://localhost:$PROXY_PORT/health', timeout=1)" 2>/dev/null; then
    break
  fi
  sleep 0.5
done

# OpenCode uses LOCAL_ENDPOINT to auto-discover models from /v1/models
export LOCAL_ENDPOINT="http://localhost:$PROXY_PORT"

# Configure all four agents to use the discovered model
cat > .opencode.json <<EOF
{
  "agents": {
    "coder": {
      "model": "local.hf:Qwen/Qwen3-Coder-480B-A35B-Instruct",
      "maxTokens": 65536
    },
    "task": {
      "model": "local.hf:Qwen/Qwen3-Coder-480B-A35B-Instruct",
      "maxTokens": 65536
    },
    "summarizer": {
      "model": "local.hf:Qwen/Qwen3-Coder-480B-A35B-Instruct",
      "maxTokens": 65536
    },
    "title": {
      "model": "local.hf:Qwen/Qwen3-Coder-480B-A35B-Instruct",
      "maxTokens": 80
    }
  }
}
EOF

TASK_PROMPT=$(cat "$TASK_DESCRIPTION")

WALL_CLOCK_START=$(date +%s)

set +e
opencode -p "IMPORTANT: Do NOT brainstorm, ask clarifying questions, or create implementation plans. Start writing code immediately. Implement the task directly, then verify with tests/build/lint before finishing.

$TASK_PROMPT" -q 2>&1 | tee /workspace/.opencode-stdout.log
EXIT_CODE=${PIPESTATUS[0]}
set -e

WALL_CLOCK_END=$(date +%s)
WALL_CLOCK_DURATION=$(( (WALL_CLOCK_END - WALL_CLOCK_START) * 1000 ))

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

# Qwen3-Coder-480B pricing on Synthetic: $2.00/1M input, $2.00/1M output
INPUT_COST=$(python3 -c "print($INPUT_TOKENS * 2.00 / 1000000)")
OUTPUT_COST=$(python3 -c "print($OUTPUT_TOKENS * 2.00 / 1000000)")
TOTAL_COST=$(python3 -c "print($INPUT_COST + $OUTPUT_COST)")

cat > /workspace/.thunderdome-metrics.json << EOF
{
  "input_tokens": $INPUT_TOKENS,
  "output_tokens": $OUTPUT_TOKENS,
  "cache_read_tokens": 0,
  "cache_creation_tokens": 0,
  "turns": 1,
  "duration_ms": $WALL_CLOCK_DURATION,
  "total_cost_usd": $TOTAL_COST
}
EOF

echo "Metrics: in=$INPUT_TOKENS out=$OUTPUT_TOKENS cost=\$$TOTAL_COST"
exit $EXIT_CODE
