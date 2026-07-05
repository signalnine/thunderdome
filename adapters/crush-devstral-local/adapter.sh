#!/bin/bash
set -e

# --- CRUSH + Devstral AWQ (local vLLM on host.docker.internal:8080) ---
# vLLM with --enable-auto-tool-choice --tool-call-parser mistral
# provides proper structured tool_calls for Devstral.

[[ -f "$TASK_DESCRIPTION" ]] || { echo "Task file not found: $TASK_DESCRIPTION" >&2; exit 2; }

cd "$TASK_DIR"

export HOME=/tmp

# Git identity
git config user.name "CRUSH"
git config user.email "crush@devstral.local"

# ============================================================================
# Phase 1: Start metrics proxy
# ============================================================================

PROXY_PORT=$(python3 -c "import socket; s=socket.socket(); s.bind(('',0)); print(s.getsockname()[1]); s.close()")
PROXY_LOG=/tmp/proxy-usage.jsonl

python3 /usr/local/bin/openai_proxy.py \
  --port "$PROXY_PORT" \
  --log "$PROXY_LOG" \
  --upstream "http://100.107.24.62:8080/v1" \
  --model-rewrite "glm-5=cyankiwi/Devstral-Small-2-24B-Instruct-2512-AWQ-4bit" \
  --max-tokens 8192 \
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
# Phase 2: Configure CRUSH
# ============================================================================

# max_tokens must fit within vLLM's max_model_len (16384)
cat > /tmp/.local/share/crush/crush.json << EOF
{"providers":{"zai":{"api_key":"not-needed","base_url":"http://localhost:$PROXY_PORT"}},"models":{"large":{"model":"glm-5","provider":"zai","max_tokens":8192},"small":{"model":"glm-5","provider":"zai","max_tokens":8192}}}
EOF

# Write project instructions that CRUSH reads automatically
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

# ============================================================================
# Phase 3: Run CRUSH
# ============================================================================

TASK_PROMPT=$(cat "$TASK_DESCRIPTION")
WALL_CLOCK_START=$(date +%s)
OUTPUT_FILE=/workspace/.thunderdome-output.txt
STDERR_FILE=/workspace/.thunderdome-stderr.log

echo "=== CRUSH + Devstral (vLLM): Starting ==="

set +e
crush run \
  -m zai/glm-5 \
  -c "$TASK_DIR" \
  --quiet \
  -- "$TASK_PROMPT" \
  > "$OUTPUT_FILE" 2> "$STDERR_FILE"
CRUSH_EXIT=$?
set -e

echo "CRUSH exited: $CRUSH_EXIT"

WALL_CLOCK_END=$(date +%s)
WALL_CLOCK_DURATION=$(( (WALL_CLOCK_END - WALL_CLOCK_START) * 1000 ))

# Give proxy a moment to finish writing logs
sleep 0.5

# Stop the proxy
kill $PROXY_PID 2>/dev/null || true

# ============================================================================
# Phase 4: Metrics
# ============================================================================

echo "=== CRUSH + Devstral: Aggregating metrics ==="

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

# Local inference — $0 cost
cat > /workspace/.thunderdome-metrics.json << EOF
{
  "input_tokens": $INPUT_TOKENS,
  "output_tokens": $OUTPUT_TOKENS,
  "cache_read_tokens": 0,
  "cache_creation_tokens": 0,
  "turns": $TURNS,
  "duration_ms": $WALL_CLOCK_DURATION,
  "total_cost_usd": 0.0
}
EOF

echo "Metrics: in=$INPUT_TOKENS out=$OUTPUT_TOKENS turns=$TURNS"
echo "=== CRUSH + Devstral adapter complete ==="
exit $CRUSH_EXIT
