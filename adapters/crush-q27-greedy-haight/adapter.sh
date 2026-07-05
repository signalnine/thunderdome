#!/bin/bash
set -e

# crush-q27-greedy-haight: CRUSH + q27 v1.4 4-bit engine on host.docker.internal:8081
# via q27-server's NATIVE Anthropic endpoint (tool_use, streaming). No proxy.
# Quant A/B test leg vs crush-q5km-greedy-haight (Q5_K_M via llama.cpp+openai_proxy).
# Both legs no-think (server runs --no-think) and greedy (q27 is greedy-only).

[[ -f "$TASK_DESCRIPTION" ]] || { echo "Task file not found: $TASK_DESCRIPTION" >&2; exit 2; }

cd "$TASK_DIR"

export HOME=/tmp

mkdir -p /tmp/.local/share/crush
cat > /tmp/.local/share/crush/crush.json <<EOF
{
  "\$schema": "https://charm.land/crush.json",
  "providers": {
    "q27": {
      "type": "anthropic",
      "base_url": "http://host.docker.internal:8081",
      "api_key": "not-needed",
      "models": [
        {
          "id": "q27-qwopus-27b",
          "name": "q27 Qwopus3.6-27B v1.4 (local)",
          "cost_per_1m_in": 0,
          "cost_per_1m_out": 0,
          "cost_per_1m_in_cached": 0,
          "cost_per_1m_out_cached": 0,
          "context_window": 131072,
          "default_max_tokens": 32768,
          "can_reason": false,
          "supports_attachments": false
        }
      ]
    }
  },
  "models": {
    "large": {"model": "q27-qwopus-27b", "provider": "q27", "max_tokens": 32768},
    "small": {"model": "q27-qwopus-27b", "provider": "q27", "max_tokens": 32768}
  }
}
EOF

# Write project instructions that CRUSH reads automatically (IDENTICAL to the
# crush-q5km-greedy-haight leg -- do not edit one without the other)
cat > "$TASK_DIR/CRUSH.md" << 'CRUSHMD'
# STOP — Read this before doing anything

You are an autonomous coding agent. Your job is to WRITE CODE that passes tests.

## Step 1: Understand the task
- Read TASK.md to understand what to build
- Look at existing files: `ls -la`, `ls src/`, `ls tests/`

## Step 2: Write the code
- Create/edit files in `src/` — this is where your implementation goes
- Write complete, working TypeScript code
- NEVER delete test files or modify package.json/tsconfig.json

## Step 3: Verify (MANDATORY — do this EVERY time after writing code)
```bash
npm install 2>/dev/null
npm run build
npm test
npm run lint
```

## Step 4: Fix and repeat
- If build fails: fix TypeScript errors, go to step 3
- If tests fail: read the errors, fix your code, go to step 3
- If lint fails: fix lint issues, go to step 3
- Keep iterating until ALL THREE pass

## CRITICAL RULES
- You MUST write code in `src/index.ts` — that is the main deliverable
- You MUST NOT delete or modify files in `tests/`
- You MUST run `npm test` at least once before finishing
- You MUST keep trying until tests pass — do not stop early
CRUSHMD

TASK_PROMPT=$(cat "$TASK_DESCRIPTION")
OUTPUT_FILE=/workspace/.thunderdome-output.txt
STDERR_FILE=/workspace/.thunderdome-stderr.log

set +e
crush run \
  -m q27/q27-qwopus-27b \
  -c "$TASK_DIR" \
  --quiet \
  -- "$TASK_PROMPT" \
  > "$OUTPUT_FILE" 2> "$STDERR_FILE"
CRUSH_EXIT=$?
set -e

# Local inference, no proxy log -- approximate turns from CRUSH session files
SESSION_TURNS=0
SESSION_DIR="/tmp/.local/share/crush/sessions"
if [ -d "$SESSION_DIR" ]; then
  SESSION_TURNS=$(find "$SESSION_DIR" -name "*.jsonl" -exec cat {} + 2>/dev/null | grep -c '"role"' || true)
fi

cat > /workspace/.thunderdome-metrics.json << EOF
{
  "input_tokens": 0,
  "output_tokens": 0,
  "cache_read_tokens": 0,
  "cache_creation_tokens": 0,
  "turns": $SESSION_TURNS,
  "total_cost_usd": 0.0
}
EOF

exit $CRUSH_EXIT
