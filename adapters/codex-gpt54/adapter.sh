#!/bin/bash
set -euo pipefail

: "${TASK_DIR:?TASK_DIR not set by harness}"
: "${TASK_DESCRIPTION:?TASK_DESCRIPTION not set by harness}"

# --- OpenAI Codex CLI + GPT-5.4 ---
# Codex (https://github.com/openai/codex) is OpenAI's official coding agent.
# Uses `codex exec` for non-interactive one-shot prompts.

[[ -f "$TASK_DESCRIPTION" ]] || { echo "Task file not found: $TASK_DESCRIPTION" >&2; exit 2; }

cd "$TASK_DIR"

export HOME=/tmp
mkdir -p "$HOME/.codex"

# Codex requires login via --with-api-key (stdin); env var alone is ignored.
: "${OPENAI_API_KEY:?OPENAI_API_KEY is required for this adapter}"
printenv OPENAI_API_KEY | codex login --with-api-key | tail -3
codex_status=${PIPESTATUS[1]}
if [[ $codex_status -ne 0 ]]; then
    echo "codex login failed (exit $codex_status)" >&2
    exit 2
fi

TASK_PROMPT=$(cat "$TASK_DESCRIPTION")
OUTPUT_FILE=/workspace/.thunderdome-output.jsonl
STDERR_FILE=/workspace/.thunderdome-stderr.log

WALL_CLOCK_START=$(date +%s)

set +e
codex exec \
  -m gpt-5.4 \
  --dangerously-bypass-approvals-and-sandbox \
  --skip-git-repo-check \
  --json \
  "$TASK_PROMPT" \
  > "$OUTPUT_FILE" 2> "$STDERR_FILE"
EXIT_CODE=$?
set -e

WALL_CLOCK_END=$(date +%s)
WALL_CLOCK_DURATION=$(( (WALL_CLOCK_END - WALL_CLOCK_START) * 1000 ))

# Parse JSONL output for token usage. Codex emits per-turn events including
# token counts in message_delta / task_complete blocks.
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
                # Look for token usage in various event shapes
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

# GPT-5.4 pricing: \$1.25/M input, \$10/M output (matches gpt-5 pricing).
cost = input_tokens * 1.25 / 1e6 + output_tokens * 10.0 / 1e6

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
