#!/bin/bash
set -e

[[ -f "$TASK_DESCRIPTION" ]] || { echo "Task file not found: $TASK_DESCRIPTION" >&2; exit 2; }

cd "$TASK_DIR"

# Aider supports Gemini natively
aider \
  --yes-always \
  --no-auto-commits \
  --message-file "$TASK_DESCRIPTION" \
  --model gemini/gemini-2.0-flash
