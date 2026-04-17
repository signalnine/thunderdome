#!/bin/bash
set -e

# --- Hermes Agent + Devstral (local ollama on haight:11434) ---
# Hermes parses tool calls from model text output, bypassing ollama's
# broken OpenAI tool_calls shim for Mistral models.

[[ -f "$TASK_DESCRIPTION" ]] || { echo "Task file not found: $TASK_DESCRIPTION" >&2; exit 2; }

cd "$TASK_DIR"

export HOME=/tmp

# Git identity
git config user.name "Hermes"
git config user.email "hermes@nousresearch.com"

# ============================================================================
# Phase 1: Start metrics proxy
# ============================================================================

PROXY_PORT=$(python3 -c "import socket; s=socket.socket(); s.bind(('',0)); print(s.getsockname()[1]); s.close()")
PROXY_LOG=/tmp/proxy-usage.jsonl

python3 /usr/local/bin/openai_proxy.py \
  --port "$PROXY_PORT" \
  --log "$PROXY_LOG" \
  --upstream "http://100.107.24.62:11434/v1" \
  --model-rewrite "devstral-local=devstral:latest" \
  2>/tmp/proxy-stderr.log &
PROXY_PID=$!

# Wait for proxy
for i in {1..10}; do
  if python3 -c "import urllib.request; urllib.request.urlopen('http://localhost:$PROXY_PORT/health', timeout=1)" 2>/dev/null; then
    break
  fi
  sleep 0.5
done

echo "Proxy ready on port $PROXY_PORT"

# ============================================================================
# Phase 2: Configure Hermes
# ============================================================================

cat > /tmp/.hermes/config.yaml << EOF
model:
  provider: "custom"
  default: "devstral-local"
  base_url: "http://localhost:$PROXY_PORT"

terminal:
  backend: local
  cwd: "$TASK_DIR"
  timeout: 300

agent:
  max_turns: 90

compression:
  enabled: true
  threshold: 0.50

display:
  tool_progress: off
  compact: true
EOF

cat > /tmp/.hermes/.env << EOF
OPENAI_API_KEY=not-needed
EOF

# ============================================================================
# Phase 3: Run Hermes
# ============================================================================

TASK_PROMPT=$(cat "$TASK_DESCRIPTION")
WALL_CLOCK_START=$(date +%s)

echo "=== Hermes Agent (Devstral local): Starting ==="

set +e
hermes chat \
  -q "$TASK_PROMPT" \
  --quiet \
  --yolo \
  --toolsets "terminal,file" \
  2>&1 | tee /tmp/hermes-output.txt
HERMES_EXIT=${PIPESTATUS[0]}
set -e

echo "Hermes exited: $HERMES_EXIT"

WALL_CLOCK_END=$(date +%s)
WALL_CLOCK_DURATION=$(( (WALL_CLOCK_END - WALL_CLOCK_START) * 1000 ))

# Give proxy a moment to finish writing logs
sleep 0.5

# Stop the proxy
kill $PROXY_PID 2>/dev/null || true

# ============================================================================
# Phase 4: Metrics
# ============================================================================

echo "=== Hermes Agent: Aggregating metrics ==="

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

# Count turns from proxy log
TURNS=0
if [[ -f "$PROXY_LOG" ]]; then
  TURNS=$(wc -l < "$PROXY_LOG")
fi

# Local inference — $0 cost
cat > /workspace/.thunderdome-metrics.json << EOF
{
  "input_tokens": $INPUT_TOKENS,
  "output_tokens": $OUTPUT_TOKENS,
  "cache_read_tokens": 0,
  "cache_creation_tokens": 0,
  "turns": $TURNS,
  "duration_ms": $WALL_CLOCK_DURATION,
  "total_cost_usd": 0.0
}
EOF

echo "Metrics: in=$INPUT_TOKENS out=$OUTPUT_TOKENS turns=$TURNS"
echo "=== Hermes Agent adapter complete ==="
exit $HERMES_EXIT
