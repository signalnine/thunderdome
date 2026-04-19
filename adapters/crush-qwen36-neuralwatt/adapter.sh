#!/bin/bash
set -e

# --- CRUSH + Qwen3.6-35B-A3B via Neuralwatt (native Anthropic endpoint) ---
# Uses CRUSH's built-in anthropic provider type pointed directly at
# https://api.neuralwatt.com. No proxy needed -- CRUSH speaks native Anthropic
# format and Neuralwatt serves /v1/messages with native thinking blocks.

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
          "id": "Qwen/Qwen3.6-35B-A3B",
          "name": "Qwen3.6 35B-A3B (Neuralwatt)",
          "cost_per_1m_in": 0.1,
          "cost_per_1m_out": 0.1,
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
    "large": {"model": "Qwen/Qwen3.6-35B-A3B", "provider": "neuralwatt", "max_tokens": 32768},
    "small": {"model": "Qwen/Qwen3.6-35B-A3B", "provider": "neuralwatt", "max_tokens": 32768}
  }
}
EOF

TASK_PROMPT=$(cat "$TASK_DESCRIPTION")
OUTPUT_FILE=/workspace/.thunderdome-output.txt
STDERR_FILE=/workspace/.thunderdome-stderr.log

set +e
crush run \
  -m neuralwatt/Qwen/Qwen3.6-35B-A3B \
  -c "$TASK_DIR" \
  --quiet \
  -- "$TASK_PROMPT" \
  > "$OUTPUT_FILE" 2> "$STDERR_FILE"
CRUSH_EXIT=$?
set -e

# No proxy = no per-request usage log. Cost estimated post-hoc from session turns.
# Neuralwatt actual billing is effectively zero in practice (energy-based).
SESSION_TURNS=0
SESSION_DIR="/tmp/.local/share/crush/sessions"
if [ -d "$SESSION_DIR" ]; then
  SESSION_TURNS=$(find "$SESSION_DIR" -name "*.jsonl" -exec cat {} + 2>/dev/null | grep -c '"role"' || true)
fi
# Empirical: Neuralwatt billing (2026-04-18) = $0.71 / 342 requests = $0.00208/req avg.
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
