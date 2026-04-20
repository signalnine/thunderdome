#!/bin/bash
set -e

# --- Mini-SWE-Agent + Qwen3.6-35B-A3B via Neuralwatt ---
# Princeton's minimalist SWE-agent. Uses LiteLLM for model routing.

[[ -f "$TASK_DESCRIPTION" ]] || { echo "Task file not found: $TASK_DESCRIPTION" >&2; exit 2; }

cd "$TASK_DIR"

export HOME=/tmp

# Pre-populate mini-swe's config directory so it doesn't prompt for setup.
mkdir -p "$HOME/.config/mini-swe-agent"
cat > "$HOME/.config/mini-swe-agent/.env" <<EOF
MSWEA_MODEL_NAME='anthropic/Qwen/Qwen3.6-35B-A3B'
ANTHROPIC_API_KEY='$NEURALWATT_API_KEY'
ANTHROPIC_BASE_URL='https://api.neuralwatt.com'
EOF

export MSWEA_MODEL_NAME="anthropic/Qwen/Qwen3.6-35B-A3B"
export ANTHROPIC_API_KEY="$NEURALWATT_API_KEY"
export ANTHROPIC_BASE_URL="https://api.neuralwatt.com"
export MSWEA_CONFIGURED=1  # skip first-run interactive setup
export MSWEA_COST_TRACKING=ignore_errors  # Qwen3.6 not in LiteLLM pricing DB

TASK_PROMPT=$(cat "$TASK_DESCRIPTION")
OUTPUT_FILE=/workspace/.thunderdome-output.log
STDERR_FILE=/workspace/.thunderdome-stderr.log

WALL_CLOCK_START=$(date +%s)

set +e
mini --yolo \
  -m "anthropic/Qwen/Qwen3.6-35B-A3B" \
  -t "$TASK_PROMPT" \
  --cost-limit 0 \
  > "$OUTPUT_FILE" 2> "$STDERR_FILE"
EXIT_CODE=$?
set -e

WALL_CLOCK_END=$(date +%s)
WALL_CLOCK_DURATION=$(( (WALL_CLOCK_END - WALL_CLOCK_START) * 1000 ))

# Mini-SWE doesn't emit structured usage; estimate cost from a traj file if present.
# Neuralwatt energy-priced ~$0.00208/turn.
TURNS=$(grep -c "Turn " "$OUTPUT_FILE" 2>/dev/null || echo 0)
COST=$(python3 -c "print(round($TURNS * 0.00208, 6))")

cat > /workspace/.thunderdome-metrics.json <<METRICS
{
  "input_tokens": 0,
  "output_tokens": 0,
  "cache_read_tokens": 0,
  "cache_creation_tokens": 0,
  "turns": $TURNS,
  "duration_ms": $WALL_CLOCK_DURATION,
  "total_cost_usd": $COST
}
METRICS

exit $EXIT_CODE
