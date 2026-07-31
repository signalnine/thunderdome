#!/bin/bash
set -euo pipefail

: "${TASK_DIR:?TASK_DIR not set by harness}"
: "${TASK_DESCRIPTION:?TASK_DESCRIPTION not set by harness}"

# --- OpenAI Codex CLI + GPT-5.6 Luna via OpenRouter ---
# Codex (https://github.com/openai/codex) supports arbitrary OpenAI-compatible
# backends via a [model_providers.<name>] block in config.toml. We point it at
# OpenRouter's openai/gpt-5.6-luna.
#
# Luna is the CHEAP tier of the GPT-5.6 series: $0.10/$0.60 per M against
# Terra's $1/$6 and Sol's $5/$30, at 1.05M context. Tested as a cost/value
# candidate -- for scale, Kimi K3 is $3/$15 and cost $2.99/task for 84.8%.
#
# Codex/Responses is chosen deliberately over CRUSH or Claude Code: Luna is a
# reasoning model and the Responses API PRESERVES chain-of-thought across turns.
# VERIFIED for this model, not assumed: /responses returns a reasoning item with
# encrypted_content (91 reasoning tokens on a path-counting probe), and it
# accepts codex's native tool shape -- the exact thing that BLOCKED codex for
# Poolside/Laguna ("no endpoints support the native namespace tool type").
# Note a trivial prompt returns NO reasoning item; that is the model declining to
# think, not a broken path. The Claude Code route drops unsigned thinking blocks
# between turns, which collapsed GLM-5.2 to 27.4% before Codex rescued it to 67.0%.
#
# reasoning_effort=high is kept from the K3 adapter so the two are comparable.
# Reasoning tokens bill as OUTPUT ($0.60/M), so a low-effort run is the obvious
# cost ablation. luna-pro is the SAME weights served with reasoning.mode=pro --
# same list price, more reasoning tokens, so a separate arm rather than a swap.

[[ -f "$TASK_DESCRIPTION" ]] || { echo "Task file not found: $TASK_DESCRIPTION" >&2; exit 2; }

cd "$TASK_DIR"

export HOME=/tmp
mkdir -p "$HOME/.codex"

: "${OPENROUTER_API_KEY:?OPENROUTER_API_KEY is required for this adapter}"

# Custom OpenRouter provider. env_key tells Codex which env var holds the key;
# wire_api="responses" keeps reasoning intact; model_reasoning_effort=high asks
# Codex to request maximum thinking (K3 exposes a reasoning_effort knob).
cat > "$HOME/.codex/config.toml" <<'TOML'
model = "openai/gpt-5.6-luna"
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
cost = input_tokens * 0.10 / 1e6 + output_tokens * 0.60 / 1e6

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
