#!/bin/bash
set -e

# --- Forge Code + GPT-5.4 ---
# Forge (https://forgecode.dev) is the current TermBench 2.0 leader.
# Multi-agent architecture; stores credentials via interactive `forge provider login`
# so we drive the login flow with expect since the container is headless.

[[ -f "$TASK_DESCRIPTION" ]] || { echo "Task file not found: $TASK_DESCRIPTION" >&2; exit 2; }

cd "$TASK_DIR"

# Forge writes to $HOME/.forge
export HOME=/tmp
mkdir -p "$HOME/.forge"

# Authenticate OpenAI provider by scripting the interactive login.
KEY="$OPENAI_API_KEY"
expect <<EXPECT
set timeout 10
log_user 0
set key "$KEY"
spawn forge provider login openai
expect "API key"
send "\$key\r"
expect eof
EXPECT

# Set default provider and model.
cat > "$HOME/.forge/.forge.toml" <<EOF
[session]
provider_id = "openai"
model_id = "gpt-5.4"
EOF

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

# Forge doesn't emit machine-readable token counts by default; approximate cost
# by parsing its output for token usage, else leave at 0. GPT-5.4 pricing:
# $3/M input, $12/M output (placeholder -- verify against OpenAI docs).
# Without per-request tracking, we rely on OpenAI's billing dashboard.
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
