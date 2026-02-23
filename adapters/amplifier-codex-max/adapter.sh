#!/bin/bash
set -e

[[ -f "$TASK_DESCRIPTION" ]] || { echo "Task file not found: $TASK_DESCRIPTION" >&2; exit 2; }

cd "$TASK_DIR"

# Use /tmp as HOME so amplifier can write config/session files
export HOME=/tmp

# Pin both providers to the local Docker image versions.
mkdir -p "$HOME/.amplifier"
cat > "$HOME/.amplifier/settings.yaml" <<'SETTINGS'
sources:
  modules:
    provider-anthropic: /opt/amplifier-provider-anthropic
    provider-openai: /opt/amplifier-provider-openai
SETTINGS

# Configure OpenAI provider (non-interactive, reads OPENAI_API_KEY from env)
amplifier provider use openai --model gpt-5.1-codex-max --local -y

# Override reasoning_effort default — Codex models don't support 'none',
# they require low/medium/high/xhigh.
sed -i 's/reasoning_effort: none/reasoning_effort: medium/' /workspace/.amplifier/settings.local.yaml

TASK_PROMPT=$(cat "$TASK_DESCRIPTION")

set +e
amplifier run "$TASK_PROMPT" \
  -p openai \
  -m gpt-5.1-codex-max \
  2>/workspace/.thunderdome-stderr.log \
  | tee /workspace/.amplifier-stdout.log
EXIT_CODE=${PIPESTATUS[0]}
set -e

# Parse token usage from Amplifier's console output and write metrics file.
# Token usage lines are CUMULATIVE — take only the last one.
# Format: └─ Input: 46,697 (77% cached) | Output: 444 | Total: 47,141
python3 -c "
import re, json, sys

last_input = 0
last_output = 0
last_cache_pct = 0

with open('/workspace/.amplifier-stdout.log', 'r', errors='replace') as f:
    for line in f:
        clean = re.sub(r'\x1b\[[0-9;]*m', '', line)
        m = re.search(r'Input:\s*([\d,]+)\s*(?:\((\d+)%\s*cached\))?\s*\|\s*Output:\s*([\d,]+)', clean)
        if m:
            last_input = int(m.group(1).replace(',', ''))
            last_cache_pct = int(m.group(2)) if m.group(2) else 0
            last_output = int(m.group(3).replace(',', ''))

cache_read = int(last_input * last_cache_pct / 100)
non_cached_input = last_input - cache_read

# gpt-5.1-codex-max pricing per million tokens
# Input: \$1.25/1M, Output: \$10.00/1M, Cached: ~\$0.125/1M (estimate)
cost = (non_cached_input * 1.25 + last_output * 10.0 + cache_read * 0.125) / 1e6

metrics = {
    'input_tokens': non_cached_input,
    'output_tokens': last_output,
    'cache_read_tokens': cache_read,
    'cache_creation_tokens': 0,
    'total_cost_usd': round(cost, 6),
}
with open('/workspace/.thunderdome-metrics.json', 'w') as f:
    json.dump(metrics, f, indent=2)
" 2>&1 || true

exit $EXIT_CODE
