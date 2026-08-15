#!/bin/bash
set -euo pipefail

: "${TASK_DIR:?TASK_DIR not set by harness}"
: "${TASK_DESCRIPTION:?TASK_DESCRIPTION not set by harness}"

# --- OpenAI Codex CLI + GLM-5.2 via Neuralwatt ---
#
# !! BROKEN as of the codex image bump to 0.145.0 (2026-07-30). Codex 0.145
# REMOVED `wire_api = "chat"` ("no longer supported ... set wire_api = responses"),
# and Neuralwatt returns 404 on /v1/responses -- so codex cannot reach Neuralwatt
# at all on this image. The bump was required for the GPT-5.6 subscription arms,
# which need codex >= 0.144.
# To re-run this arm, either pin an older codex image or port it to CRUSH, which
# is the established working Neuralwatt harness (see
# adapters/crush-qwen38-27b-neuralwatt). Results already recorded for this
# adapter predate the bump and remain valid.
# Same experiment as codex-glm52-openrouter but on Neuralwatt's energy-priced
# endpoint (model id "glm-5.2" = zai-org/GLM-5.2-FP8). Tests whether Codex's
# harness (which speaks the provider's API directly and has its own reasoning
# handling) can carry GLM-5.2's chain-of-thought where our anth2openai/Claude
# Code path could not (GLM-5.2 reasoning-ON collapsed to 27.4% there).

[[ -f "$TASK_DESCRIPTION" ]] || { echo "Task file not found: $TASK_DESCRIPTION" >&2; exit 2; }

cd "$TASK_DIR"

export HOME=/tmp
mkdir -p "$HOME/.codex"

: "${NEURALWATT_API_KEY:?NEURALWATT_API_KEY is required for this adapter}"

cat > "$HOME/.codex/config.toml" <<'TOML'
model = "glm-5.2"
model_provider = "neuralwatt"
model_reasoning_effort = "high"

[model_providers.neuralwatt]
name = "Neuralwatt"
base_url = "https://api.neuralwatt.com/v1"
env_key = "NEURALWATT_API_KEY"
wire_api = "chat"
TOML

TASK_PROMPT=$(cat "$TASK_DESCRIPTION")
OUTPUT_FILE=/workspace/.thunderdome-output.jsonl
STDERR_FILE=/workspace/.thunderdome-stderr.log

WALL_CLOCK_START=$(date +%s)

set +e
codex exec \
  --dangerously-bypass-approvals-and-sandbox \
  --skip-git-repo-check \
  --json \
  "$TASK_PROMPT" \
  > "$OUTPUT_FILE" 2> "$STDERR_FILE"
EXIT_CODE=$?
set -e

WALL_CLOCK_END=$(date +%s)
WALL_CLOCK_DURATION=$(( (WALL_CLOCK_END - WALL_CLOCK_START) * 1000 ))

python3 -c "
import json, os, sys

input_tokens = output_tokens = 0
turns = 0
try:
    with open('$OUTPUT_FILE') as f:
        for line in f:
            line = line.strip()
            if not line: continue
            try:
                ev = json.loads(line)
                msg = ev.get('msg', {})
                mtype = msg.get('type', '')
                if 'usage' in msg:
                    u = msg['usage']
                    input_tokens += u.get('input_tokens', 0) or u.get('prompt_tokens', 0) or 0
                    output_tokens += u.get('output_tokens', 0) or u.get('completion_tokens', 0) or 0
                if mtype in ('agent_message', 'task_complete'):
                    turns += 1
            except json.JSONDecodeError:
                pass
except FileNotFoundError:
    pass

# Neuralwatt is energy-priced (effectively free); report \$0.
cost = 0.0

metrics = {
    'input_tokens': input_tokens,
    'output_tokens': output_tokens,
    'cache_read_tokens': 0,
    'cache_creation_tokens': 0,
    'turns': turns,
    'duration_ms': $WALL_CLOCK_DURATION,
    'total_cost_usd': round(cost, 6),
}
with open('/workspace/.thunderdome-metrics.json', 'w') as f:
    json.dump(metrics, f, indent=2)
print(f'Metrics: in={input_tokens} out={output_tokens} turns={turns} cost=\${cost:.4f}', file=sys.stderr)
" 2>&1 || true

exit $EXIT_CODE
