#!/bin/bash
set -e

# --- Hermes Agent + MiMo-V2-Flash + System Prompt ---
# Same as hermes-mimo-v2-flash but with CRUSH-style system prompt prepended.
# Ablation: does the structured prompt help MiMo like it helped Qwen 3.5?

[[ -f "$TASK_DESCRIPTION" ]] || { echo "Task file not found: $TASK_DESCRIPTION" >&2; exit 2; }

cd "$TASK_DIR"

export HOME=/tmp

# Git identity
git config user.name "Hermes"
git config user.email "hermes@mimo.local"

# ============================================================================
# Phase 1: Start metrics proxy
# ============================================================================

PROXY_PORT=$(python3 -c "import socket; s=socket.socket(); s.bind(('',0)); print(s.getsockname()[1]); s.close()")
PROXY_LOG=/tmp/proxy-usage.jsonl

python3 /usr/local/bin/openai_proxy.py \
  --port "$PROXY_PORT" \
  --log "$PROXY_LOG" \
  --upstream "https://openrouter.ai/api/v1" \
  --model-rewrite "mimo-v2-flash=xiaomi/mimo-v2-flash" \
  --auth-key "$OPENROUTER_API_KEY" \
  2>/tmp/proxy-stderr.log &
PROXY_PID=$!

# Wait for proxy
for i in {1..10}; do
  if python3 -c "import urllib.request; urllib.request.urlopen('http://localhost:$PROXY_PORT/health', timeout=1)" 2>/dev/null; then
    break
  fi
  sleep 0.5
done

echo "Proxy ready on port $PROXY_PORT"

# ============================================================================
# Phase 2: Configure Hermes
# ============================================================================

cat > /tmp/.hermes/config.yaml << EOF
model:
  provider: "custom"
  default: "mimo-v2-flash"
  base_url: "http://localhost:$PROXY_PORT"

terminal:
  backend: local
  cwd: "$TASK_DIR"
  timeout: 300

agent:
  max_turns: 90

compression:
  enabled: true
  threshold: 0.50

display:
  tool_progress: off
  compact: true
EOF

# API key via env file (proxy handles auth rewrite)
cat > /tmp/.hermes/.env << EOF
OPENAI_API_KEY=placeholder
EOF

# ============================================================================
# Phase 3: Build prompted task
# ============================================================================

SYSTEM_PROMPT='# STOP — Read this before doing anything

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
- You MUST keep trying until tests pass — do not stop early'

TASK_CONTENT=$(cat "$TASK_DESCRIPTION")
TASK_PROMPT="$SYSTEM_PROMPT

---

$TASK_CONTENT"

# ============================================================================
# Phase 4: Run Hermes
# ============================================================================

WALL_CLOCK_START=$(date +%s)

echo "=== Hermes + MiMo-V2-Flash (prompted): Starting ==="

set +e
hermes chat \
  -q "$TASK_PROMPT" \
  --quiet \
  --yolo \
  --toolsets "terminal,file" \
  2>&1 | tee /tmp/hermes-output.txt
HERMES_EXIT=${PIPESTATUS[0]}
set -e

echo "Hermes exited: $HERMES_EXIT"

WALL_CLOCK_END=$(date +%s)
WALL_CLOCK_DURATION=$(( (WALL_CLOCK_END - WALL_CLOCK_START) * 1000 ))

# Give proxy a moment to finish writing logs
sleep 0.5

# Stop the proxy
kill $PROXY_PID 2>/dev/null || true

# ============================================================================
# Phase 5: Metrics
# ============================================================================

echo "=== Hermes + MiMo-V2-Flash (prompted): Aggregating metrics ==="

INPUT_TOKENS=0
OUTPUT_TOKENS=0
if [[ -f "$PROXY_LOG" ]]; then
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    in_tok=$(echo "$line" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('input_tokens',0))" 2>/dev/null || echo 0)
    out_tok=$(echo "$line" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('output_tokens',0))" 2>/dev/null || echo 0)
    INPUT_TOKENS=$((INPUT_TOKENS + in_tok))
    OUTPUT_TOKENS=$((OUTPUT_TOKENS + out_tok))
  done < "$PROXY_LOG"
fi

# Count turns from proxy log
TURNS=0
if [[ -f "$PROXY_LOG" ]]; then
  TURNS=$(wc -l < "$PROXY_LOG")
fi

# MiMo-V2-Flash pricing via OpenRouter: $0.09/M input, $0.29/M output
INPUT_COST=$(python3 -c "print($INPUT_TOKENS * 0.09 / 1000000)")
OUTPUT_COST=$(python3 -c "print($OUTPUT_TOKENS * 0.29 / 1000000)")
TOTAL_COST=$(python3 -c "print($INPUT_COST + $OUTPUT_COST)")

cat > /workspace/.thunderdome-metrics.json << EOF
{
  "input_tokens": $INPUT_TOKENS,
  "output_tokens": $OUTPUT_TOKENS,
  "cache_read_tokens": 0,
  "cache_creation_tokens": 0,
  "turns": $TURNS,
  "duration_ms": $WALL_CLOCK_DURATION,
  "total_cost_usd": $TOTAL_COST
}
EOF

echo "Metrics: in=$INPUT_TOKENS out=$OUTPUT_TOKENS turns=$TURNS cost=\$$TOTAL_COST"
echo "=== Hermes + MiMo-V2-Flash (prompted) adapter complete ==="
exit $HERMES_EXIT
