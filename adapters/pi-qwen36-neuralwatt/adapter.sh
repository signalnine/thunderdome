#!/bin/bash
set -e

# --- Vanilla pi coding agent + Qwen3.6 via Neuralwatt ---
# Upstream pi (@mariozechner/pi-coding-agent), NOT oh-my-pi.

[[ -f "$TASK_DESCRIPTION" ]] || { echo "Task file not found: $TASK_DESCRIPTION" >&2; exit 2; }

cd "$TASK_DIR"

export HOME=/tmp
export PATH="/root/.bun/bin:$PATH"
export PI_CODING_AGENT_DIR="/tmp/.pi/agent"
mkdir -p "$PI_CODING_AGENT_DIR"

git config user.name "pi"
git config user.email "pi@thunderdome"

# Route pi through openai_proxy so we can rewrite developer->system (vLLM compat)
# and strip reasoning deltas if they surface.
PROXY_PORT=$(python3 -c "import socket; s=socket.socket(); s.bind(('',0)); print(s.getsockname()[1]); s.close()")
PROXY_LOG=/tmp/pi-proxy.jsonl
python3 /usr/local/bin/openai_proxy.py \
  --port "$PROXY_PORT" \
  --log "$PROXY_LOG" \
  --upstream "https://api.neuralwatt.com/v1" \
  --auth-key "$NEURALWATT_API_KEY" \
  2>/dev/null &
PROXY_PID=$!

for i in {1..10}; do
  if python3 -c "import urllib.request; urllib.request.urlopen('http://localhost:$PROXY_PORT/health', timeout=1)" 2>/dev/null; then
    break
  fi
  sleep 0.5
done

# Register Neuralwatt (through the local proxy) as custom OpenAI-compatible provider.
cat > "$PI_CODING_AGENT_DIR/models.json" <<EOF
{
  "providers": {
    "neuralwatt": {
      "baseUrl": "http://localhost:$PROXY_PORT",
      "api": "openai-completions",
      "apiKey": "NEURALWATT_API_KEY",
      "authHeader": true,
      "models": [
        {
          "id": "Qwen/Qwen3.6-35B-A3B",
          "name": "Qwen3.6 35B-A3B",
          "reasoning": true,
          "input": ["text"],
          "contextWindow": 131072,
          "maxTokens": 65536,
          "cost": { "input": 0.1, "output": 0.1, "cacheRead": 0, "cacheWrite": 0 }
        }
      ]
    }
  }
}
EOF

TASK_PROMPT=$(cat "$TASK_DESCRIPTION")

WALL_CLOCK_START=$(date +%s)

echo "=== pi (Qwen3.6 via Neuralwatt): Starting ==="

set +e
pi --provider neuralwatt --model "Qwen/Qwen3.6-35B-A3B" -p \
  "IMPORTANT: Do NOT brainstorm, ask clarifying questions, or create implementation plans. Start writing code immediately. Implement the task directly, then verify with tests/build/lint before finishing.

$TASK_PROMPT" \
  2>&1 | tee /workspace/.pi-stdout.log
PI_EXIT=${PIPESTATUS[0]}
set -e

echo "pi exited: $PI_EXIT"
kill $PROXY_PID 2>/dev/null || true

WALL_CLOCK_END=$(date +%s)
WALL_CLOCK_DURATION=$(( (WALL_CLOCK_END - WALL_CLOCK_START) * 1000 ))

# Try to extract usage from pi session JSONL if it wrote one
INPUT_TOKENS=0
OUTPUT_TOKENS=0
TURNS=0
SESSION_DIR="$PI_CODING_AGENT_DIR/sessions"
if [ -d "$SESSION_DIR" ]; then
  for f in "$SESSION_DIR"/*.jsonl; do
    [ -f "$f" ] || continue
    while IFS= read -r line; do
      [ -z "$line" ] && continue
      in_tok=$(echo "$line" | python3 -c "import sys,json
try:
    d=json.load(sys.stdin)
    u=d.get('usage',{}) or {}
    print(u.get('input',0) or u.get('promptTokens',0) or 0)
except: print(0)" 2>/dev/null || echo 0)
      out_tok=$(echo "$line" | python3 -c "import sys,json
try:
    d=json.load(sys.stdin)
    u=d.get('usage',{}) or {}
    print(u.get('output',0) or u.get('completionTokens',0) or 0)
except: print(0)" 2>/dev/null || echo 0)
      INPUT_TOKENS=$((INPUT_TOKENS + in_tok))
      OUTPUT_TOKENS=$((OUTPUT_TOKENS + out_tok))
      if [ "$in_tok" -gt 0 ] || [ "$out_tok" -gt 0 ]; then
        TURNS=$((TURNS + 1))
      fi
    done < "$f"
  done
fi

# Energy-based pricing: $0.00061/turn
COST=$(python3 -c "print(round($TURNS * 0.00061, 6))")

cat > /workspace/.thunderdome-metrics.json << EOF
{
  "input_tokens": $INPUT_TOKENS,
  "output_tokens": $OUTPUT_TOKENS,
  "cache_read_tokens": 0,
  "cache_creation_tokens": 0,
  "turns": $TURNS,
  "duration_ms": $WALL_CLOCK_DURATION,
  "total_cost_usd": $COST
}
EOF

echo "Metrics: in=$INPUT_TOKENS out=$OUTPUT_TOKENS turns=$TURNS cost=\$$COST"
exit $PI_EXIT
