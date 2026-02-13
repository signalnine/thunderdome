#!/bin/bash
set -e

[[ -f "$TASK_DESCRIPTION" ]] || { echo "Task file not found: $TASK_DESCRIPTION" >&2; exit 2; }

cd "$TASK_DIR"

# Use /tmp as HOME so amplifier can write config/session files
export HOME=/tmp

# Configure Anthropic provider (non-interactive, reads ANTHROPIC_API_KEY from env)
amplifier provider use anthropic --model claude-sonnet-4-5 --local -y

TASK_PROMPT=$(cat "$TASK_DESCRIPTION")

set +e
amplifier run "$TASK_PROMPT" \
  -p anthropic \
  -m claude-sonnet-4-5 \
  2>/workspace/.thunderdome-stderr.log
EXIT_CODE=$?
set -e

exit $EXIT_CODE
