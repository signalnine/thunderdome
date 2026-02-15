#!/bin/bash
set -e

[[ -f "$TASK_DESCRIPTION" ]] || { echo "Task file not found: $TASK_DESCRIPTION" >&2; exit 2; }

cd "$TASK_DIR"

# Use /tmp as HOME so amplifier can write config/session files
export HOME=/tmp

# Set up OAuth credentials — Amplifier uses Claude Code under the hood
if [ -f /tmp/.claude-credentials.json ]; then
  mkdir -p "$HOME/.claude"
  cp /tmp/.claude-credentials.json "$HOME/.claude/.credentials.json"
fi

# Pin provider-anthropic to the local Docker image version.
# Without this, bundle preparation downloads @main from GitHub which may
# reference symbols not in this image's amplifier_core (e.g. AccessDeniedError).
mkdir -p "$HOME/.amplifier"
cat > "$HOME/.amplifier/settings.yaml" <<'SETTINGS'
sources:
  modules:
    provider-anthropic: /opt/amplifier-provider-anthropic
SETTINGS

# Configure Anthropic provider with Opus
amplifier provider use anthropic --model claude-opus-4-6 --local -y

TASK_PROMPT=$(cat "$TASK_DESCRIPTION")

set +e
amplifier run "$TASK_PROMPT" \
  -p anthropic \
  -m claude-opus-4-6 \
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

# Opus pricing per million tokens
cost = (non_cached_input * 15.0 + last_output * 75.0 + cache_read * 1.50) / 1e6

metrics = {
    'input_tokens': non_cached_input,
    'output_tokens': last_output,
    'cache_read_tokens': cache_read,
    'cache_creation_tokens': 0,
    'total_cost_usd': round(cost, 6),
}
with open('/workspace/.thunderdome-metrics.json', 'w') as f:
    json.dump(metrics, f, indent=2)
print(f'Metrics: in={non_cached_input} out={last_output} cache_read={cache_read} cost=\${cost:.4f}', file=sys.stderr)
" 2>&1 || true

exit $EXIT_CODE
