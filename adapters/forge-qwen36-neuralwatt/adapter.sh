#!/bin/bash
set -e

# --- Forge Code + Qwen3.6-35B-A3B via Neuralwatt (native Anthropic endpoint) ---
# Forge is the TermBench 2.0 leader; testing whether that lift transfers to an
# open-weights 35B MoE model via Neuralwatt's Anthropic-compatible endpoint.

[[ -f "$TASK_DESCRIPTION" ]] || { echo "Task file not found: $TASK_DESCRIPTION" >&2; exit 2; }

cd "$TASK_DIR"

export HOME=/tmp
mkdir -p "$HOME/.forge"

# Define Neuralwatt as a custom Anthropic-compatible provider.
cat > "$HOME/.forge/.forge.toml" <<EOF
[session]
provider_id = "neuralwatt"
model_id = "Qwen/Qwen3.6-35B-A3B"

[[providers]]
id = "neuralwatt"
url = "https://api.neuralwatt.com/v1/messages"
models = "https://api.neuralwatt.com/v1/models"
api_key_vars = "NEURALWATT_API_KEY"
response_type = "Anthropic"
auth_methods = ["api_key"]
EOF

# Drive the interactive login to persist the key into forge's credential store.
export FORCE_KEY="$NEURALWATT_API_KEY"
expect <<EXPECT
set timeout 15
log_user 0
set key "\$env(FORCE_KEY)"
spawn forge provider login neuralwatt
expect {
    "API key" { send "\$key\r"; exp_continue }
    eof
}
EXPECT

TASK_PROMPT=$(cat "$TASK_DESCRIPTION")
OUTPUT_FILE=/workspace/.thunderdome-output.txt
STDERR_FILE=/workspace/.thunderdome-stderr.log

WALL_CLOCK_START=$(date +%s)

set +e
forge -p "$TASK_PROMPT" > "$OUTPUT_FILE" 2> "$STDERR_FILE"
EXIT_CODE=$?
set -e

WALL_CLOCK_END=$(date +%s)
WALL_CLOCK_DURATION=$(( (WALL_CLOCK_END - WALL_CLOCK_START) * 1000 ))

# Energy-billed via Neuralwatt; no per-request proxy to count turns here.
cat > /workspace/.thunderdome-metrics.json <<METRICS
{
  "input_tokens": 0,
  "output_tokens": 0,
  "cache_read_tokens": 0,
  "cache_creation_tokens": 0,
  "turns": 0,
  "duration_ms": $WALL_CLOCK_DURATION,
  "total_cost_usd": 0.0
}
METRICS

exit $EXIT_CODE
