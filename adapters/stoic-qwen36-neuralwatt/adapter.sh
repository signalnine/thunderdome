#!/bin/bash
set -e

# Stoic variant + Qwen3.6 via Neuralwatt.
# Dichotomy-of-control framing instead of zen meditation. Tests whether a
# constraint-acceptance frame ("you control your effort and method, not the
# code's existing shape") shifts behavior on debug/recovery tasks especially.
# Same structural bones as zen-lite/dao (TDD, verify).

[[ -f "$TASK_DESCRIPTION" ]] || { echo "Task file not found: $TASK_DESCRIPTION" >&2; exit 2; }

cd "$TASK_DIR"

PROXY_PORT=18900
PROXY_LOG=/workspace/.anthropic-proxy.jsonl

python3 /usr/local/bin/anth2openai_proxy.py \
  --port $PROXY_PORT \
  --log "$PROXY_LOG" \
  --upstream "https://api.neuralwatt.com/v1" \
  --model "Qwen/Qwen3.6-35B-A3B" \
  --api-key "$NEURALWATT_API_KEY" &
PROXY_PID=$!

for i in $(seq 1 30); do
  curl -s http://localhost:$PROXY_PORT/health >/dev/null 2>&1 && break
  sleep 0.2
done

export ANTHROPIC_BASE_URL="http://localhost:$PROXY_PORT"
export ANTHROPIC_API_KEY="placeholder"

TASK_PROMPT=$(cat "$TASK_DESCRIPTION")
OUTPUT_FILE=/workspace/.thunderdome-output.jsonl

echo "=== Stoic (Qwen3.6 via Neuralwatt): Starting ==="

set +e
claude -p \
  --output-format stream-json \
  --verbose \
  --dangerously-skip-permissions \
  --disallowed-tools "AskUserQuestion,EnterPlanMode,Task" \
  --append-system-prompt "You are running in a headless benchmark environment. No human to interact with. Work directly in the current directory.

# The Discipline of the Engineer

A craftsperson who would do their work well attends first to what is in their power, and accepts what is not. Proceed accordingly.

## The Dichotomy of Control

Some things are up to you: your effort, your method, your willingness to read carefully, your honesty about what failed. Other things are not: the existing code, the task as written, the tests as specified. Do not waste energy resenting constraints. The shape of the codebase, the framework's conventions, the language's quirks -- these are given. Your virtue is to act well within them.

If a test demands behavior you would not have chosen: irrelevant. The duty is to make it pass, correctly, without complaint.

## Examine Before Judging

Read the task fully. Read the existing files: src/, tests/, package.json. The Stoic does not act from impression but from examined understanding. Premature opinion is the enemy. Sit with the code as it is, not as you wish it were. Do not guess -- know.

## Right Action: Test First

For each behavior the task demands, write the test before the code. Run it. Watch it fail honestly -- the failure is information, not insult. Then write the minimum code to make it pass. The Stoic does no more than the situation requires; flourish and excess are vices, not virtues.

If you catch yourself writing code before its test, stop. That is impulse, not discipline. Delete it. Begin again with the test.

## Endurance to Completion

Run the full verification: npm install (if needed), npm run build, npm test, npm run lint. Fix every failure. The Stoic does not abandon a task because it is tedious; tedium is the field on which character is shown. Iterate with steady, unflinching attention until every test passes, the build is clean, the lint is clean.

Write the simple, correct solution. Excess code is a kind of cowardice -- a hedge against being wrong. Be willing to be plain. Complete the task, then stop." \
  -- "$TASK_PROMPT" \
  > "$OUTPUT_FILE" 2>/workspace/.thunderdome-stderr.log
CLAUDE_EXIT=$?
set -e

echo "Claude Code exited: $CLAUDE_EXIT"
kill $PROXY_PID 2>/dev/null || true

python3 -c "
import json, os

log = '$PROXY_LOG'
input_t = output_t = cache_read = cache_create = turns = 0
if os.path.exists(log):
    for line in open(log):
        try:
            d = json.loads(line)
            input_t += d.get('input_tokens', 0)
            output_t += d.get('output_tokens', 0)
            cache_read += d.get('cache_read_input_tokens', 0)
            cache_create += d.get('cache_creation_input_tokens', 0)
            turns += 1
        except: pass

cost = turns * 0.00061

metrics = {
    'input_tokens': input_t,
    'output_tokens': output_t,
    'cache_read_tokens': cache_read,
    'cache_creation_tokens': cache_create,
    'turns': turns,
    'duration_ms': 0,
    'total_cost_usd': round(cost, 6)
}

try:
    for line in open('$OUTPUT_FILE'):
        msg = json.loads(line)
        if msg.get('type') == 'result':
            metrics['duration_ms'] = msg.get('duration_ms', 0)
            break
except: pass

json.dump(metrics, open('/workspace/.thunderdome-metrics.json', 'w'), indent=2)
print(f\"Metrics: in={input_t} out={output_t} cache_read={cache_read} turns={turns} cost=\${cost:.4f}\")
"

echo "=== Stoic (Qwen3.6) adapter complete ==="
exit $CLAUDE_EXIT
