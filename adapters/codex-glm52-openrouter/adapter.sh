#!/bin/bash
set -euo pipefail

: "${TASK_DIR:?TASK_DIR not set by harness}"
: "${TASK_DESCRIPTION:?TASK_DESCRIPTION not set by harness}"

# --- OpenAI Codex CLI + GLM-5.2 via OpenRouter ---
# Codex (https://github.com/openai/codex) supports arbitrary OpenAI-compatible
# backends via a [model_providers.<name>] block in config.toml. We point it at
# OpenRouter's z-ai/glm-5.2. The experiment: GLM-5.2 reasoning-ON collapsed
# (27.4%) through our anth2openai/Claude Code path because that path DROPS the
# model's chain-of-thought between turns (Claude Code rejects unsigned thinking
# blocks). Codex is a different harness with its own reasoning handling -- this
# tests whether GLM-5.2's collapse is a model problem or a harness problem.

[[ -f "$TASK_DESCRIPTION" ]] || { echo "Task file not found: $TASK_DESCRIPTION" >&2; exit 2; }

cd "$TASK_DIR"

export HOME=/tmp
mkdir -p "$HOME/.codex"

: "${OPENROUTER_API_KEY:?OPENROUTER_API_KEY is required for this adapter}"

# Custom OpenRouter provider. env_key tells Codex which env var holds the key;
# wire_api="chat" uses OpenAI chat-completions (the shape non-OpenAI models
# speak). model_reasoning_effort=high asks Codex to request maximum thinking.
cat > "$HOME/.codex/config.toml" <<'TOML'
model = "z-ai/glm-5.2"
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

# GLM-5.2 via OpenRouter pricing: \$1.40/M input, \$4.40/M output. cached_input
# is the prompt-cache-hit slice of input_tokens (OpenRouter discounts it, but we
# bill at full input rate here to stay conservative).
cost = input_tokens * 1.40 / 1e6 + output_tokens * 4.40 / 1e6

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
