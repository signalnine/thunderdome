#!/bin/bash
set -e

[[ -f "$TASK_DESCRIPTION" ]] || { echo "Task file not found: $TASK_DESCRIPTION" >&2; exit 2; }

cd "$TASK_DIR"

# Set up auth for OpenRouter
mkdir -p $HOME/.local/share/opencode
cat > $HOME/.local/share/opencode/auth.json <<EOF
{
  "openrouter": {
    "api_key": "${OPENROUTER_API_KEY}"
  }
}
EOF

# Write opencode config
cat > .opencode.json <<'CONFIG'
{
  "$schema": "https://opencode.ai/config.json",
  "provider": {
    "openrouter": {
      "models": {
        "nvidia/nemotron-3-nano-30b-a3b:free": {
          "name": "Nemotron 3 Nano",
          "limit": {
            "context": 256000,
            "output": 8192
          }
        }
      }
    }
  },
  "agent": {
    "coder": {
      "model": "openrouter/nvidia/nemotron-3-nano-30b-a3b:free"
    },
    "task": {
      "model": "openrouter/nvidia/nemotron-3-nano-30b-a3b:free"
    }
  }
}
CONFIG

# Build prompt file (avoids shell quoting issues with -p)
cat > /tmp/prompt.txt <<'PREAMBLE'
IMPORTANT: Do NOT brainstorm, ask clarifying questions, or create implementation plans. Start writing code immediately. Implement the task directly, then verify with tests/build/lint before finishing.

PREAMBLE
cat "$TASK_DESCRIPTION" >> /tmp/prompt.txt

TASK_PROMPT=$(cat /tmp/prompt.txt)

set +e
opencode -p "$TASK_PROMPT" -q 2>&1 | tee /workspace/.opencode-stdout.log
EXIT_CODE=${PIPESTATUS[0]}
set -e

# Write metrics (free model, no cost)
cat > /workspace/.thunderdome-metrics.json <<'METRICS'
{
  "input_tokens": 0,
  "output_tokens": 0,
  "cache_read_tokens": 0,
  "cache_creation_tokens": 0,
  "total_cost_usd": 0.0
}
METRICS

exit $EXIT_CODE
