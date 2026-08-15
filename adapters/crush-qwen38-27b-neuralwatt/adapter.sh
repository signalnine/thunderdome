#!/bin/bash
# --- CRUSH + Qwen3.8-27B via Neuralwatt (energy-priced, ~$0) ---
#
# Model id is `Qwen/Qwen3.8-27B-FP8` -- the full HF-style path, NOT a short name
# like the other Neuralwatt models. Passed via the proxy's --model-rewrite since
# CRUSH validates -m flags against its own model list.
#
# HARNESS NOTE: this was FIRST built on Codex, matching the
# codex-qwen38-max-openrouter arm so the 27B-vs-Max family comparison would be
# harness-matched. That is no longer possible: bumping the codex image to 0.145
# (needed for the GPT-5.6 subscription arms, which require >= 0.144) REMOVED
# `wire_api = "chat"`, and Neuralwatt returns 404 on /v1/responses -- so codex
# 0.145 cannot talk to Neuralwatt at all. The same bump silently broke the
# pre-existing codex-glm52-neuralwatt adapter.
# CRUSH is the established working harness for Neuralwatt (its openai_proxy.py
# already handles the `: energy`/`: cost` SSE telemetry that otherwise makes
# CRUSH abort with "unexpected end of JSON input").
# CONSEQUENCE: 27B-vs-Max is NOT harness-matched. Harness effects on this suite
# are large -- CRUSH cost GLM-5.1-fast 10.8pp versus the Claude Code harness --
# so treat that particular comparison as indicative only.
#
# --no-think is deliberately NOT set. It is used for GLM-5.2 because that model
# breaks CRUSH's tool loop when thinking; Qwen3.8-27B was probed first and is
# well-behaved -- tool_calls work, a reasoning field is returned, and latency is
# ~1.5s, with none of the ~5 min/turn wall that made GLM-5.2 reasoning-ON
# unusable on this provider.
#
# Same parameter class as the local qwopus-27b (a Qwen3.6-27B fine-tune) but two
# generations newer, so it isolates generational gain at fixed size.

# Find a free port for the proxy
PROXY_PORT=$(python3 -c "import socket; s=socket.socket(); s.bind(('',0)); print(s.getsockname()[1]); s.close()")
PROXY_LOG=/tmp/proxy-usage.jsonl

# Start the OpenAI-compatible proxy with model rewrite
python3 /usr/local/bin/openai_proxy.py \
  --port "$PROXY_PORT" \
  --log "$PROXY_LOG" \
  --upstream "https://api.neuralwatt.com/v1" \
  --model-rewrite "glm-5=Qwen/Qwen3.8-27B-FP8" \
  2>/dev/null &
PROXY_PID=$!

# Wait for proxy to be ready
for i in {1..10}; do
  if python3 -c "import urllib.request; urllib.request.urlopen('http://localhost:$PROXY_PORT/health', timeout=1)" 2>/dev/null; then
    break
  fi
  sleep 0.5
done

# CRUSH sees glm-5; proxy rewrites to glm-5.2 for Neuralwatt
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

# NOTE: GLM-5.2 Neuralwatt pricing not published; using GLM-5.1-fast rates as a
# placeholder ($1.10/1M in, $0.51/1M out). Neuralwatt is energy-billed (the API
# returns an `energy` block), so $/task here is an estimate -- effectively free.
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
