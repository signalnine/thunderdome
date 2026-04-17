#!/bin/bash
set -e

[[ -f "$TASK_DESCRIPTION" ]] || { echo "Task file not found: $TASK_DESCRIPTION" >&2; exit 2; }

cd "$TASK_DIR"

# Use /tmp as HOME so amplifier can write config/session files
export HOME=/tmp

# Pin providers to the local Docker image versions.
mkdir -p "$HOME/.amplifier"
cat > "$HOME/.amplifier/settings.yaml" <<'SETTINGS'
sources:
  modules:
    provider-openai: /opt/amplifier-provider-openai
SETTINGS

# Start proxy that strips reasoning.effort="none" for OpenRouter compatibility
python3 /opt/lmstudio-proxy.py "${OPENAI_BASE_URL}" &
PROXY_PID=$!
sleep 1

# Point OpenAI provider at local proxy (which forwards to OpenRouter)
export OPENAI_BASE_URL="http://127.0.0.1:8800/v1"

MODEL="nvidia/nemotron-3-nano-30b-a3b:free"

# Configure OpenAI provider
amplifier provider use openai --model "$MODEL" --local -y

TASK_PROMPT=$(cat "$TASK_DESCRIPTION")

# Prepend instructions to skip planning
TASK_PROMPT="IMPORTANT: Do NOT brainstorm, ask clarifying questions, write design docs, or create implementation plans. Do NOT use the load_skill tool. Start writing code immediately. Implement the task directly, then verify with tests/build/lint before finishing.

${TASK_PROMPT}"

set +e
amplifier run "$TASK_PROMPT" \
  -p openai \
  -m "$MODEL" \
  2>/workspace/.thunderdome-stderr.log \
  | tee /workspace/.amplifier-stdout.log
EXIT_CODE=${PIPESTATUS[0]}
set -e

# Kill proxy
kill $PROXY_PID 2>/dev/null || true

# Parse token usage from Amplifier's console output and write metrics file.
python3 -c "
import re, json, sys

last_input = 0
last_output = 0

with open('/workspace/.amplifier-stdout.log', 'r', errors='replace') as f:
    for line in f:
        clean = re.sub(r'\x1b\[[0-9;]*m', '', line)
        m = re.search(r'Input:\s*([\d,]+)\s*(?:\(\d+%\s*cached\))?\s*\|\s*Output:\s*([\d,]+)', clean)
        if m:
            last_input = int(m.group(1).replace(',', ''))
            last_output = int(m.group(2).replace(',', ''))

# Free model — no cost
metrics = {
    'input_tokens': last_input,
    'output_tokens': last_output,
    'cache_read_tokens': 0,
    'cache_creation_tokens': 0,
    'total_cost_usd': 0.0,
}
with open('/workspace/.thunderdome-metrics.json', 'w') as f:
    json.dump(metrics, f, indent=2)
" 2>&1 || true

exit $EXIT_CODE
