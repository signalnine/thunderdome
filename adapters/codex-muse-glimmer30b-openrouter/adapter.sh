#!/bin/bash
set -euo pipefail

: "${TASK_DIR:?TASK_DIR not set by harness}"
: "${TASK_DESCRIPTION:?TASK_DESCRIPTION not set by harness}"

# --- OpenAI Codex CLI + Muse Glimmer 30B via OpenRouter ---
#
# `meta/muse-glimmer-30b`, Meta Superintelligence Labs: $0.35/$1.50 per M, 131K
# ctx. A DENSE 30B OPEN-WEIGHT multimodal model distilled from Muse Spark and
# explicitly "optimized for autonomous agents on consumer hardware".
#
# That last part matters here: open weights at 30B dense means this should fit a
# single 5090 at Q5/Q6 (~20-24 GB), so the interesting arm is eventually LOCAL
# and free. This adapter is the hosted read -- fast and comparable to the other
# OpenRouter arms -- not the final word on the model.
#
# Codex/Responses over the Claude Code path, matching the Qwen3.8-Max arm. Both
# were probed and both work (Responses -> reasoning + function_call; Anthropic ->
# thinking + tool_use), but Claude Code rejects unsigned thinking blocks, which
# is what collapsed GLM-5.2 to 27.4%.
#
# RATES ARE PER-MODEL AND MUST BE EDITED WHEN CLONING. A prior clone inherited
# Kimi K3's $3/$15 and overstated cost 30x; pricing.yaml has no entry for these
# models, so this constant is the only source of truth.

[[ -f "$TASK_DESCRIPTION" ]] || { echo "Task file not found: $TASK_DESCRIPTION" >&2; exit 2; }

cd "$TASK_DIR"

export HOME=/tmp
mkdir -p "$HOME/.codex"

: "${OPENROUTER_API_KEY:?OPENROUTER_API_KEY is required for this adapter}"

# Custom OpenRouter provider. env_key tells Codex which env var holds the key;
# wire_api="responses" keeps reasoning intact; model_reasoning_effort=high asks
# Codex to request maximum thinking (K3 exposes a reasoning_effort knob).
cat > "$HOME/.codex/config.toml" <<'TOML'
model = "meta/muse-glimmer-30b"
model_provider = "openrouter"
model_reasoning_effort = "high"

[model_providers.openrouter]
name = "OpenRouter"
base_url = "https://openrouter.ai/api/v1"
env_key = "OPENROUTER_API_KEY"
wire_api = "responses"
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

# Parse JSONL output for token usage. Codex 0.141 (Responses-API/--json) emits
# top-level events; the cumulative token usage lands in 'turn.completed' with a
# usage block {input_tokens, cached_input_tokens, output_tokens,
# reasoning_output_tokens}. usage is cumulative per turn, so take the LAST
# turn.completed rather than summing (avoids double-counting). reasoning tokens
# are already inside output_tokens and bill at the output rate.
python3 -c "
import json, os, sys

input_tokens = output_tokens = cached = 0
turns = 0
try:
    with open('$OUTPUT_FILE') as f:
        for line in f:
            line = line.strip()
            if not line: continue
            try:
                ev = json.loads(line)
            except json.JSONDecodeError:
                continue
            etype = ev.get('type', ev.get('msg', {}).get('type', ''))
            if etype == 'turn.completed':
                turns += 1
                u = ev.get('usage', {}) or {}
                # cumulative -> overwrite with latest
                input_tokens = u.get('input_tokens', input_tokens) or input_tokens
                output_tokens = u.get('output_tokens', output_tokens) or output_tokens
                cached = u.get('cached_input_tokens', cached) or cached
except FileNotFoundError:
    pass

# GPT-5.6 Luna via OpenRouter pricing: \$0.10/M input, \$0.60/M output (checked
# against the live /api/v1/models listing, not assumed). cached_input is the
# prompt-cache-hit slice of input_tokens; OpenRouter discounts it, but we bill at
# full input rate to stay conservative.
#
# THESE RATES ARE PER-MODEL AND MUST BE EDITED WHEN CLONING THIS ADAPTER. The
# first Luna smoke test inherited Kimi K3's \$3/\$15 from the clone source and
# reported \$0.749 for a trial that actually cost ~\$0.025 -- a 30x overstatement,
# on the exact metric this adapter exists to measure. pricing.yaml has no entry
# for these models, so nothing downstream catches a stale rate.
cost = input_tokens * 0.35 / 1e6 + output_tokens * 1.50 / 1e6

metrics = {
    'input_tokens': input_tokens,
    'output_tokens': output_tokens,
    'cache_read_tokens': cached,
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
