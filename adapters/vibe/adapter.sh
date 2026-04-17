#!/bin/bash
set -e

# --- Mistral Vibe CLI (mistral-vibe-cli-latest / Devstral 2) ---

[[ -f "$TASK_DESCRIPTION" ]] || { echo "Task file not found: $TASK_DESCRIPTION" >&2; exit 2; }

cd "$TASK_DIR"

export HOME=/tmp

# Git identity
git config user.name "Vibe"
git config user.email "vibe@mistral.ai"

# ============================================================================
# Phase 1: Configure Vibe
# ============================================================================

cat > /tmp/.vibe/config.toml << 'EOF'
active_model = "devstral-2"
EOF

cat > /tmp/.vibe/.env << EOF
MISTRAL_API_KEY=$MISTRAL_API_KEY
EOF

# ============================================================================
# Phase 2: Run Vibe
# ============================================================================

TASK_PROMPT=$(cat "$TASK_DESCRIPTION")
WALL_CLOCK_START=$(date +%s)

echo "=== Vibe (Devstral 2): Starting ==="

set +e
vibe -p "$TASK_PROMPT" \
  --max-turns 90 \
  --output streaming \
  2>&1 | tee /tmp/vibe-output.txt
VIBE_EXIT=${PIPESTATUS[0]}
set -e

echo "Vibe exited: $VIBE_EXIT"

WALL_CLOCK_END=$(date +%s)
WALL_CLOCK_DURATION=$(( (WALL_CLOCK_END - WALL_CLOCK_START) * 1000 ))

# ============================================================================
# Phase 3: Parse metrics from streaming output
# ============================================================================

echo "=== Vibe: Aggregating metrics ==="

# Parse token usage from streaming JSON output
INPUT_TOKENS=0
OUTPUT_TOKENS=0
TURNS=0
# Extract metrics from vibe session logs (most reliable source)
LATEST_SESSION=$(ls -td /tmp/.vibe/logs/session/session_* 2>/dev/null | head -1)
if [[ -n "$LATEST_SESSION" && -f "$LATEST_SESSION/meta.json" ]]; then
  eval "$(python3 -c "
import json
m = json.load(open('$LATEST_SESSION/meta.json'))
s = m.get('stats', {})
print(f'INPUT_TOKENS={s.get(\"session_prompt_tokens\", 0)}')
print(f'OUTPUT_TOKENS={s.get(\"session_completion_tokens\", 0)}')
print(f'TURNS={s.get(\"steps\", 0)}')
" 2>/dev/null)" || true
fi

# Fallback: count turns from streaming output
if [[ "${TURNS:-0}" -eq 0 && -f /tmp/vibe-output.txt ]]; then
  TURNS=$(grep -c '"role": *"assistant"' /tmp/vibe-output.txt 2>/dev/null || true)
fi

# Sanitize
INPUT_TOKENS=${INPUT_TOKENS:-0}
OUTPUT_TOKENS=${OUTPUT_TOKENS:-0}
TURNS=${TURNS:-0}

# Devstral 2 (mistral-vibe-cli-latest) pricing: $0.40/M input, $2.00/M output
TOTAL_COST=$(python3 -c "print($INPUT_TOKENS * 0.40 / 1000000 + $OUTPUT_TOKENS * 2.00 / 1000000)")

cat > /workspace/.thunderdome-metrics.json << EOF
{
  "input_tokens": ${INPUT_TOKENS:-0},
  "output_tokens": ${OUTPUT_TOKENS:-0},
  "cache_read_tokens": 0,
  "cache_creation_tokens": 0,
  "turns": ${TURNS:-0},
  "duration_ms": $WALL_CLOCK_DURATION,
  "total_cost_usd": $TOTAL_COST
}
EOF

echo "Metrics: in=$INPUT_TOKENS out=$OUTPUT_TOKENS turns=$TURNS cost=\$$TOTAL_COST"
echo "=== Vibe adapter complete ==="
exit $VIBE_EXIT
