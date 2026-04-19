#!/bin/bash
set -e

# --- Aider + Qwen3.6-35B-A3B via Neuralwatt (OpenAI endpoint + proxy) ---
# Uses Aider's OpenAI-compat mode. Proxy handles:
# - reasoning-delta stripping (Qwen3.6 always-thinking mode)
# - developer -> system role rewrite (vLLM compat)
# - browser User-Agent (bypass Cloudflare WAF on Neuralwatt)

[[ -f "$TASK_DESCRIPTION" ]] || { echo "Task file not found: $TASK_DESCRIPTION" >&2; exit 2; }

cd "$TASK_DIR"

PROXY_PORT=$(python3 -c "import socket; s=socket.socket(); s.bind(('',0)); print(s.getsockname()[1]); s.close()")
PROXY_LOG=/tmp/aider-proxy.jsonl

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

export OPENAI_API_KEY="placeholder"
export OPENAI_API_BASE="http://localhost:$PROXY_PORT"

# Collect source files for aider to edit.
SOURCE_FILES=()
while IFS= read -r -d '' f; do
  SOURCE_FILES+=("$f")
done < <(find . -maxdepth 4 \( -name '*.ts' -o -name '*.js' -o -name '*.json' \) \
  ! -path '*/node_modules/*' ! -path '*/.git/*' ! -path '*/dist/*' ! -name 'package-lock.json' \
  -print0 2>/dev/null)

set +e
aider \
  --yes-always \
  --no-auto-commits \
  --model "openai/Qwen/Qwen3.6-35B-A3B" \
  --edit-format diff \
  --map-tokens 2048 \
  --message-file "$TASK_DESCRIPTION" \
  "${SOURCE_FILES[@]}" \
  2>/workspace/.thunderdome-stderr.log \
  | tee /workspace/.aider-stdout.log
EXIT_CODE=${PIPESTATUS[0]}
set -e

sleep 0.5
kill $PROXY_PID 2>/dev/null || true

# Parse per-turn token counts from proxy log (authoritative) + cost via energy.
INPUT_TOKENS=0
OUTPUT_TOKENS=0
TURNS=0
if [[ -f "$PROXY_LOG" ]]; then
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    in_tok=$(echo "$line" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('input_tokens',0))" 2>/dev/null || echo 0)
    out_tok=$(echo "$line" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('output_tokens',0))" 2>/dev/null || echo 0)
    INPUT_TOKENS=$((INPUT_TOKENS + in_tok))
    OUTPUT_TOKENS=$((OUTPUT_TOKENS + out_tok))
    TURNS=$((TURNS + 1))
  done < "$PROXY_LOG"
fi

# Neuralwatt real billing: $0.00208/request avg (2026-04-18).
COST=$(python3 -c "print(round($TURNS * 0.00208, 6))")

cat > /workspace/.thunderdome-metrics.json << EOF
{
  "input_tokens": $INPUT_TOKENS,
  "output_tokens": $OUTPUT_TOKENS,
  "cache_read_tokens": 0,
  "cache_creation_tokens": 0,
  "turns": $TURNS,
  "total_cost_usd": $COST
}
EOF

exit $EXIT_CODE
