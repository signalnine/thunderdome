#!/bin/bash
set -e

# --- Forge Code + Gemini 3.1 Pro (Google AI Studio) ---
# Forge's google_ai_studio provider talks directly to
# generativelanguage.googleapis.com.

[[ -f "$TASK_DESCRIPTION" ]] || { echo "Task file not found: $TASK_DESCRIPTION" >&2; exit 2; }

cd "$TASK_DIR"

export HOME=/tmp
mkdir -p "$HOME/.forge"

# Authenticate via expect since forge's login is interactive-only.
KEY="$GEMINI_API_KEY"
expect <<EXPECT
set timeout 10
log_user 0
set key "$KEY"
spawn forge provider login google_ai_studio
expect "API key"
send "\$key\r"
expect eof
EXPECT

cat > "$HOME/.forge/.forge.toml" <<EOF
[session]
provider_id = "google_ai_studio"
model_id = "gemini-3.1-pro-preview"
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

# Forge doesn't surface token counts; cost tracked via Google's dashboard.
# Gemini 3.1 Pro pricing (preview): leave at 0 until pricing is confirmed.
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
