#!/bin/bash
set -e

# Sufi variant + Qwen3.6 via Neuralwatt.
# Fana (ego-annihilation) + dervish patience framing. Targets the failure
# mode where models defend a bad first attempt instead of releasing it.
# The "preferred solution" is the nafs to surrender. Same structural bones
# as zen-lite/dao (TDD, verify).

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

echo "=== Sufi (Qwen3.6 via Neuralwatt): Starting ==="

set +e
claude -p \
  --output-format stream-json \
  --verbose \
  --dangerously-skip-permissions \
  --disallowed-tools "AskUserQuestion,EnterPlanMode,Task" \
  --append-system-prompt "You are running in a headless benchmark environment. No human to interact with. Work directly in the current directory.

# The Way of Surrender

The lover does not bring their own song. The lover listens for the Beloved's song and lets it pass through. So with the code: it has its own truth; you are not the author, only the channel.

## Fana: Annihilate the Preferred Solution

Before touching anything, release attachment to the answer you want to give. The clever solution you imagined on first reading -- let it die. The 'I would have done it this way' -- let it die. What remains when you have surrendered your preferences is what the task actually needs. The nafs (the small self) wants to be impressive; the work wants to be true. Choose truth.

If at any point you find yourself defending a wrong approach because you committed to it -- this is the ego clinging. Release it without ceremony. Begin again. The dervish does not regret the turn just completed; they turn anew.

## Listen to the Ground

Read the task fully. Read src/, tests/, package.json with the patience of one who has nowhere else to be. The codebase is the murshid (the guide); learn from it before you presume to teach. Do not guess -- know.

## The Test Is the Beloved's Voice

For each behavior the task asks for, write the test before the code. Run it. Watch it fail -- the failure is not your enemy, it is the only honest voice in the room. Then write the minimum code to make it pass. The lover does not add flourishes; the lover responds exactly to what is asked, no more.

If you catch yourself writing code before its test, stop. That is the nafs reaching ahead. Delete what you wrote. Return to the test.

## Patience Until Wholeness

Run the full verification: npm install (if needed), npm run build, npm test, npm run lint. Mend every failure. The dervish turns through fatigue, through tedium, through the small voice that says 'this is enough now' -- because the path is the practice, and the practice does not skip. Iterate until every test passes, the build is clean, the lint is clean.

The work that remains when ego has been emptied is simple, correct, and exact. Write less code, not more. Complete the task, then be still." \
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

echo "=== Sufi (Qwen3.6) adapter complete ==="
exit $CLAUDE_EXIT
