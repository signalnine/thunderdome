#!/bin/bash
set -e

# --- CRUSH + GLM-5.1-fast via Neuralwatt (native Anthropic endpoint) ---
# Same pattern as crush-qwen36-neuralwatt: CRUSH's native anthropic provider
# type pointed directly at Neuralwatt. No openai_proxy in between.
# (Prior crush-glm51-fast-neuralwatt used openai-completions and crashed.)

[[ -f "$TASK_DESCRIPTION" ]] || { echo "Task file not found: $TASK_DESCRIPTION" >&2; exit 2; }

cd "$TASK_DIR"

export HOME=/tmp

mkdir -p /tmp/.local/share/crush
cat > /tmp/.local/share/crush/crush.json <<EOF
{
  "\$schema": "https://charm.land/crush.json",
  "providers": {
    "neuralwatt": {
      "type": "anthropic",
      "base_url": "https://api.neuralwatt.com",
      "api_key": "$NEURALWATT_API_KEY",
      "extra_headers": {
        "anthropic-version": "2023-06-01",
        "User-Agent": "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36"
      },
      "models": [
        {
          "id": "glm-5.1-fast",
          "name": "GLM-5.1-fast (Neuralwatt)",
          "cost_per_1m_in": 1.10,
          "cost_per_1m_out": 0.51,
          "cost_per_1m_in_cached": 0,
          "cost_per_1m_out_cached": 0,
          "context_window": 131072,
          "default_max_tokens": 32768,
          "can_reason": true,
          "supports_attachments": false
        }
      ]
    }
  },
  "models": {
    "large": {"model": "glm-5.1-fast", "provider": "neuralwatt", "max_tokens": 32768},
    "small": {"model": "glm-5.1-fast", "provider": "neuralwatt", "max_tokens": 32768}
  }
}
EOF

TASK_PROMPT=$(cat "$TASK_DESCRIPTION")
OUTPUT_FILE=/workspace/.thunderdome-output.txt
STDERR_FILE=/workspace/.thunderdome-stderr.log

set +e
crush run \
  -m neuralwatt/glm-5.1-fast \
  -c "$TASK_DIR" \
  --quiet \
  -- "$TASK_PROMPT" \
  > "$OUTPUT_FILE" 2> "$STDERR_FILE"
CRUSH_EXIT=$?
set -e

# GLM-5.1-fast listed pricing: $1.10/M in, $0.51/M out (non-energy).
# Approximate cost from session turns since no proxy log. Neuralwatt billing
# in practice is dominated by the energy component for this model too.
SESSION_TURNS=0
SESSION_DIR="/tmp/.local/share/crush/sessions"
if [ -d "$SESSION_DIR" ]; then
  SESSION_TURNS=$(find "$SESSION_DIR" -name "*.jsonl" -exec cat {} + 2>/dev/null | grep -c '"role"' || true)
fi
COST=$(python3 -c "print(round($SESSION_TURNS * 0.00208, 6))")

cat > /workspace/.thunderdome-metrics.json << EOF
{
  "input_tokens": 0,
  "output_tokens": 0,
  "cache_read_tokens": 0,
  "cache_creation_tokens": 0,
  "turns": $SESSION_TURNS,
  "total_cost_usd": $COST
}
EOF

exit $CRUSH_EXIT
