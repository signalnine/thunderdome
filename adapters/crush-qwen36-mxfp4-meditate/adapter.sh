#!/bin/bash
set -e

# crush-qwen36-mxfp4-meditate: CRUSH + Qwen3.6 MXFP4 (local llama.cpp on haight:8080)
# with meditation/zen discipline prompt. Tests whether the zen framing
# that gave +2.8pp on Qwen3-Coder 30B also helps the stronger Qwen3.6 model.

[[ -f "$TASK_DESCRIPTION" ]] || { echo "Task file not found: $TASK_DESCRIPTION" >&2; exit 2; }

cd "$TASK_DIR"

export HOME=/tmp

# Find a free port for the proxy
PROXY_PORT=$(python3 -c "import socket; s=socket.socket(); s.bind(('',0)); print(s.getsockname()[1]); s.close()")
PROXY_LOG=/tmp/proxy-usage.jsonl

# Start the OpenAI-compatible proxy -- upstream is local llama.cpp
python3 /usr/local/bin/openai_proxy.py \
  --port "$PROXY_PORT" \
  --log "$PROXY_LOG" \
  --upstream "http://haight:8080/v1" \
  --model-rewrite "glm-5=qwen36-mxfp4" \
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

# Meditation-adapted CRUSH.md -- zen discipline without Claude-specific plugin machinery
cat > "$TASK_DIR/CRUSH.md" << 'CRUSHMD'
# The Way of Calm Precision

You are an autonomous coding agent. Before writing any code, enter a state of calm clarity.

## First: Release Urgency

Before touching any code, pause. Release attachment to appearing clever or finishing quickly. Attend to what the code actually needs, not what you want to build. Quality emerges from stillness, not striving.

## Then: Understand

Read the task fully. Read every existing file: `ls -la`, `ls src/`, `ls tests/`. Sit with what is there before adding to it. Do not guess -- know.

## Then: Define What Done Looks Like

Before writing implementation, create CONTRACT.md -- every behavior the finished code must exhibit, how to verify each one. This is your meditation object: complete attention on what must be true.

## Then: Let the Tests Speak First

For each contract criterion, write the test BEFORE the code. Run it. Watch it fail. The failing test tells you exactly what the code needs to become. Only then write the minimum to make it pass. One small truth at a time.

If you catch yourself writing code before its test, stop. Delete it. The test comes first.

## Then: Complete the Work

A calm hand finishes what it starts. Handle all edge cases. Cover boundaries, errors, empty inputs. The complete implementation, not 90% of it.

## Then: Verify Until Clean

```bash
npm install 2>/dev/null
npm run build
npm test
npm run lint
```

Go through CONTRACT.md line by line. Fix all failures. Do not stop until every criterion passes, tests pass, build is clean, lint is clean. Keep iterating.

## CRITICAL RULES
- You MUST write code in `src/index.ts` -- that is the main deliverable
- You MUST NOT delete or modify files in `tests/`
- You MUST run `npm test` at least once before finishing
- You MUST keep trying until tests pass -- do not stop early
- Write the simple, correct solution. A calm craftsperson writes less code, not more.
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

# Local inference -- $0 cost
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
