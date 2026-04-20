#!/bin/bash
set -e

# --- Goose + Qwen3.6-35B-A3B via Neuralwatt ---
# Block/AAIF's Rust-based coding agent (Terminal-Bench 2.0 rank 45).
# Uses Goose's native anthropic provider with ANTHROPIC_HOST override.

[[ -f "$TASK_DESCRIPTION" ]] || { echo "Task file not found: $TASK_DESCRIPTION" >&2; exit 2; }

cd "$TASK_DIR"

export HOME=/tmp

export GOOSE_PROVIDER=anthropic
export GOOSE_MODEL="Qwen/Qwen3.6-35B-A3B"
export ANTHROPIC_API_KEY="$NEURALWATT_API_KEY"
export ANTHROPIC_HOST="https://api.neuralwatt.com"
export GOOSE_MODE=auto
export GOOSE_DISABLE_SESSION_NAMING=true

TASK_PROMPT=$(cat "$TASK_DESCRIPTION")
OUTPUT_FILE=/workspace/.thunderdome-output.log
STDERR_FILE=/workspace/.thunderdome-stderr.log

WALL_CLOCK_START=$(date +%s)

set +e
goose run --no-session --quiet --max-turns 100 -t "$TASK_PROMPT" > "$OUTPUT_FILE" 2> "$STDERR_FILE"
EXIT_CODE=$?
set -e

WALL_CLOCK_END=$(date +%s)
WALL_CLOCK_DURATION=$(( (WALL_CLOCK_END - WALL_CLOCK_START) * 1000 ))

# Goose doesn't emit machine-readable token counts in text output; estimate
# cost from turn count if we can find it, else leave at 0.
TURNS=0
COST=0.0

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
