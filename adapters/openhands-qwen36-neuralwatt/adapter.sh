#!/bin/bash
set -e

# --- OpenHands + Qwen3.6-35B-A3B via Neuralwatt ---
# OpenHands (ex-OpenDevin, Terminal-Bench 2.0 rank ~50) uses LiteLLM for model
# routing. We point it at Neuralwatt's Anthropic endpoint with an anthropic/
# prefix and override the base URL.

[[ -f "$TASK_DESCRIPTION" ]] || { echo "Task file not found: $TASK_DESCRIPTION" >&2; exit 2; }

cd "$TASK_DIR"

export HOME=/tmp

# LiteLLM env-var routing. The anthropic/ prefix tells LiteLLM to speak
# Anthropic protocol; LLM_BASE_URL overrides where to send requests.
export LLM_MODEL="anthropic/Qwen/Qwen3.6-35B-A3B"
export LLM_BASE_URL="https://api.neuralwatt.com"
export LLM_API_KEY="$NEURALWATT_API_KEY"

# Neuralwatt needs a browser User-Agent to bypass its Cloudflare WAF; LiteLLM
# picks up extra headers via env var or config file. OpenHands doesn't surface
# extra_headers, so this path may or may not bypass -- if it 403s we'll see it.

TASK_PROMPT=$(cat "$TASK_DESCRIPTION")
OUTPUT_FILE=/workspace/.thunderdome-output.log
STDERR_FILE=/workspace/.thunderdome-stderr.log

WALL_CLOCK_START=$(date +%s)

set +e
openhands --headless --json --override-with-envs -t "$TASK_PROMPT" > "$OUTPUT_FILE" 2> "$STDERR_FILE"
EXIT_CODE=$?
set -e

WALL_CLOCK_END=$(date +%s)
WALL_CLOCK_DURATION=$(( (WALL_CLOCK_END - WALL_CLOCK_START) * 1000 ))

# Parse token usage from OpenHands JSONL output (if any).
python3 -c "
import json, os, sys
input_tok = output_tok = turns = 0
try:
    with open('$OUTPUT_FILE') as f:
        for line in f:
            try:
                e = json.loads(line)
                if 'usage' in e:
                    u = e['usage'] if isinstance(e['usage'], dict) else {}
                    input_tok += u.get('prompt_tokens', 0) or u.get('input_tokens', 0) or 0
                    output_tok += u.get('completion_tokens', 0) or u.get('output_tokens', 0) or 0
                if e.get('action') or e.get('observation'):
                    turns += 1
            except: pass
except: pass

cost = turns * 0.00208  # Neuralwatt energy-priced

metrics = {
    'input_tokens': input_tok,
    'output_tokens': output_tok,
    'cache_read_tokens': 0,
    'cache_creation_tokens': 0,
    'turns': turns,
    'duration_ms': $WALL_CLOCK_DURATION,
    'total_cost_usd': round(cost, 6),
}
with open('/workspace/.thunderdome-metrics.json', 'w') as f:
    json.dump(metrics, f, indent=2)
" 2>&1 || true

exit $EXIT_CODE
