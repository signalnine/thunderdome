#!/bin/bash
set -e

# --- CRUSH + Qwen 3.5 40B Deckard Q4_K_M LOW THINKING (local llama.cpp on host.docker.internal:8090) ---

[[ -f "$TASK_DESCRIPTION" ]] || { echo "Task file not found: $TASK_DESCRIPTION" >&2; exit 2; }

cd "$TASK_DIR"

export HOME=/tmp

# Find a free port for the proxy
PROXY_PORT=$(python3 -c "import socket; s=socket.socket(); s.bind(('',0)); print(s.getsockname()[1]); s.close()")
PROXY_LOG=/tmp/proxy-usage.jsonl

# Start the OpenAI-compatible proxy — upstream is local llama.cpp on host.docker.internal:8090
# --reasoning-effort low limits thinking tokens for faster inference while preserving some reasoning
python3 /usr/local/bin/openai_proxy.py \
  --port "$PROXY_PORT" \
  --log "$PROXY_LOG" \
  --upstream "http://host.docker.internal:8090/v1" \
  --model-rewrite "glm-5=qwen35-40b-deckard-Q4_K_M.gguf" \
  --reasoning-effort low \
  2>/dev/null &
PROXY_PID=$!

# Wait for proxy to be ready
for i in {1..10}; do
  if python3 -c "import urllib.request; urllib.request.urlopen('http://localhost:$PROXY_PORT/health', timeout=1)" 2>/dev/null; then
    break
  fi
  sleep 0.5
done

cat > /tmp/.local/share/crush/crush.json << EOF
{"providers":{"zai":{"api_key":"not-needed","base_url":"http://localhost:$PROXY_PORT"}},"models":{"large":{"model":"glm-5","provider":"zai","max_tokens":32768},"small":{"model":"glm-5","provider":"zai","max_tokens":32768}}}
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

TASK_PROMPT=$(cat "$TASK_DESCRIPTION")
OUTPUT_FILE=/workspace/.thunderdome-output.txt
STDERR_FILE=/workspace/.thunderdome-stderr.log

set +e
crush run \
  -m zai/glm-5 \
  -c "$TASK_DIR" \
  --quiet \
  -- "$TASK_PROMPT" \
  > "$OUTPUT_FILE" 2> "$STDERR_FILE"
CRUSH_EXIT=$?
set -e

# Give proxy a moment to finish writing logs
sleep 0.5

# Stop the proxy
kill $PROXY_PID 2>/dev/null || true

# Parse proxy logs for token usage
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

# Local inference — $0 cost
cat > /workspace/.thunderdome-metrics.json << EOF
{
  "input_tokens": $INPUT_TOKENS,
  "output_tokens": $OUTPUT_TOKENS,
  "cache_read_tokens": 0,
  "cache_creation_tokens": 0,
  "turns": 1,
  "total_cost_usd": 0.0
}
EOF

exit $CRUSH_EXIT
