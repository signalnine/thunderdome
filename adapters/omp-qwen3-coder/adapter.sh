#!/bin/bash
set -e

# --- oh-my-pi (omp) with Qwen3-Coder-480B via Synthetic ---

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

# Configure omp to use Synthetic provider with all model roles set to Qwen3-Coder
export SYNTHETIC_API_KEY="$SYNTHETIC_API_KEY"
export PI_MODEL="hf:Qwen/Qwen3-Coder-480B-A35B-Instruct"
export PI_SMOL_MODEL="hf:Qwen/Qwen3-Coder-480B-A35B-Instruct"
export PI_SLOW_MODEL="hf:Qwen/Qwen3-Coder-480B-A35B-Instruct"
export PI_PLAN_MODEL="hf:Qwen/Qwen3-Coder-480B-A35B-Instruct"
export PI_NO_TITLE=1

TASK_PROMPT=$(cat "$TASK_DESCRIPTION")

WALL_CLOCK_START=$(date +%s)

echo "=== omp (Qwen3-Coder-480B): Starting ==="

set +e
omp -p "IMPORTANT: Do NOT brainstorm, ask clarifying questions, or create implementation plans. Start writing code immediately. Implement the task directly, then verify with tests/build/lint before finishing.

$TASK_PROMPT" \
  --no-session \
  2>&1 | tee /workspace/.omp-stdout.log
OMP_EXIT=${PIPESTATUS[0]}
set -e

echo "omp exited: $OMP_EXIT"

WALL_CLOCK_END=$(date +%s)
WALL_CLOCK_DURATION=$(( (WALL_CLOCK_END - WALL_CLOCK_START) * 1000 ))

# Token tracking: omp doesn't easily expose tokens in -p mode
# Synthetic pricing: $2.00/M in+out — cost tracked as $0 for now
cat > /workspace/.thunderdome-metrics.json << EOF
{
  "input_tokens": 0,
  "output_tokens": 0,
  "cache_read_tokens": 0,
  "cache_creation_tokens": 0,
  "turns": 1,
  "duration_ms": $WALL_CLOCK_DURATION,
  "total_cost_usd": 0.0
}
EOF

echo "=== omp adapter complete ==="
exit $OMP_EXIT
