#!/bin/bash
set -e

[[ -f "$TASK_DESCRIPTION" ]] || { echo "Task file not found: $TASK_DESCRIPTION" >&2; exit 2; }

cd "$TASK_DIR"

# Use /tmp as HOME so Crush can write config/session files
export HOME=/tmp

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

# Crush doesn't expose structured token usage in non-interactive mode.
# Write placeholder metrics - actual token counts would require API-level access.
# Cost for GLM-5 via Zhipu AI is typically very low (~$0.14/1M input tokens)
cat > /workspace/.thunderdome-metrics.json << 'EOF'
{
  "input_tokens": 0,
  "output_tokens": 0,
  "cache_read_tokens": 0,
  "cache_creation_tokens": 0,
  "turns": 1,
  "total_cost_usd": 0,
  "note": "crush-glm5-no-structured-metrics"
}
EOF

exit $CRUSH_EXIT
