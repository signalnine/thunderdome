#!/bin/bash
set -e

# --- oh-my-pi (omp) with GLM-5 via z.ai (native provider) ---

[[ -f "$TASK_DESCRIPTION" ]] || { echo "Task file not found: $TASK_DESCRIPTION" >&2; exit 2; }

cd "$TASK_DIR"

export HOME=/tmp
export PATH="/root/.bun/bin:$PATH"
export PI_CONFIG_DIR=".omp"
export PI_CODING_AGENT_DIR="/tmp/.omp/agent"
mkdir -p /tmp/.omp/agent

# Git identity
git config user.name "omp"
git config user.email "omp@thunderdome"

# omp has native z.ai provider support via ZAI_API_KEY
export ZAI_API_KEY="$ZHIPU_API_KEY"

# Set all model roles to GLM-5
export PI_MODEL="zai:glm-5"
export PI_SMOL_MODEL="zai:glm-5"
export PI_SLOW_MODEL="zai:glm-5"
export PI_PLAN_MODEL="zai:glm-5"
export PI_NO_TITLE=1

TASK_PROMPT=$(cat "$TASK_DESCRIPTION")

WALL_CLOCK_START=$(date +%s)

echo "=== omp (GLM-5 via z.ai): Starting ==="

set +e
omp -p "IMPORTANT: Do NOT brainstorm, ask clarifying questions, or create implementation plans. Start writing code immediately. Implement the task directly, then verify with tests/build/lint before finishing.

$TASK_PROMPT" \
  2>&1 | tee /workspace/.omp-stdout.log
OMP_EXIT=${PIPESTATUS[0]}
set -e

echo "omp exited: $OMP_EXIT"

WALL_CLOCK_END=$(date +%s)
WALL_CLOCK_DURATION=$(( (WALL_CLOCK_END - WALL_CLOCK_START) * 1000 ))

# Parse token usage from omp session JSONL
# Session files contain usage per assistant message: {"usage":{"input":N,"output":N,"cacheRead":N,...}}
SESSION_DIR="/tmp/.omp/agent/sessions"
read INPUT_TOKENS OUTPUT_TOKENS CACHE_READ_TOKENS TURNS <<< $(python3 -c "
import json, glob, os
input_t = output_t = cache_t = turns = 0
for f in glob.glob(os.path.join('$SESSION_DIR', '**/*.jsonl'), recursive=True):
    for line in open(f):
        try:
            d = json.loads(line)
            if d.get('type') == 'message' and d.get('message', {}).get('role') == 'assistant':
                u = d['message'].get('usage', {})
                input_t += u.get('input', 0)
                output_t += u.get('output', 0)
                cache_t += u.get('cacheRead', 0)
                turns += 1
        except: pass
print(f'{input_t} {output_t} {cache_t} {turns}')
" 2>/dev/null || echo "0 0 0 0")

# GLM-5 pricing: $1.00/1M input, $3.20/1M output, cache read ~$0.10/1M
INPUT_COST=$(python3 -c "print($INPUT_TOKENS * 1.0 / 1000000)")
OUTPUT_COST=$(python3 -c "print($OUTPUT_TOKENS * 3.2 / 1000000)")
CACHE_COST=$(python3 -c "print($CACHE_READ_TOKENS * 0.1 / 1000000)")
TOTAL_COST=$(python3 -c "print($INPUT_COST + $OUTPUT_COST + $CACHE_COST)")

cat > /workspace/.thunderdome-metrics.json << EOF
{
  "input_tokens": $INPUT_TOKENS,
  "output_tokens": $OUTPUT_TOKENS,
  "cache_read_tokens": $CACHE_READ_TOKENS,
  "cache_creation_tokens": 0,
  "turns": $TURNS,
  "duration_ms": $WALL_CLOCK_DURATION,
  "total_cost_usd": $TOTAL_COST
}
EOF

echo "Metrics: in=$INPUT_TOKENS out=$OUTPUT_TOKENS cache=$CACHE_READ_TOKENS turns=$TURNS cost=\$$TOTAL_COST"
echo "=== omp adapter complete ==="
exit $OMP_EXIT
