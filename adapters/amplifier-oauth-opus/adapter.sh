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
  2>/workspace/.thunderdome-stderr.log
EXIT_CODE=$?
set -e

exit $EXIT_CODE
