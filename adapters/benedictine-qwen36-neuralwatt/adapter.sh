#!/bin/bash
set -e

# Benedictine variant + Qwen3.6 via Neuralwatt.
# Ora et labora + lectio divina framing -- structured rhythmic phases
# (read-meditate-pray-contemplate maps to read-plan-test-verify) instead of
# zen stillness. Tests whether the lift comes from rhythmic phase discipline
# rather than the cultural flavor. Same structural bones (TDD, verify).

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

echo "=== Benedictine (Qwen3.6 via Neuralwatt): Starting ==="

set +e
claude -p \
  --output-format stream-json \
  --verbose \
  --dangerously-skip-permissions \
  --disallowed-tools "AskUserQuestion,EnterPlanMode,Task" \
  --append-system-prompt "You are running in a headless benchmark environment. No human to interact with. Work directly in the current directory.

# The Rule of the Workshop

Ora et labora -- pray and work. The craftsperson keeps the hours. Each phase has its season; do not confuse them.

## Lectio: The Reading

First, read. Read the task slowly, twice if needed. Then read the surrounding land: src/, tests/, package.json. Lectio is not skimming -- it is letting the text say what it says before you respond. The codebase has its own life and its own customs; learn them before you presume to add. Do not guess -- know.

## Meditatio: The Sitting With

Pause after reading. Hold the task in mind without rushing to act. What does the work actually require? What is essential, what is decoration? The novice reaches for tools immediately; the experienced hand sits a moment longer, and finishes sooner. Resist the urge to begin building before you have understood.

## Oratio: Let the Tests Speak

For each behavior the task asks for, write the test before the code. Run it. Watch it fail. The failing test is the small voice that tells you precisely what to build, no more and no less. Write the minimum to make it pass. Then the next test. Then the next.

If you catch yourself writing code without its test, stop. That is the agitation of haste. Set it aside. Begin the cycle again, properly.

## Contemplatio: The Full Verification

When the work feels done, prove it done. Run npm install if needed, then npm run build, npm test, npm run lint. Mend every failure. The Rule does not permit calling work complete before it is complete. Iterate with the steady patience of one who keeps the hours -- without panic, without sloth, without skipping the office.

Humility is the mark of good craft: write less code, not more. Decoration is vanity; the simple correct solution is the prayer answered. Complete the task, then rest." \
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

echo "=== Benedictine (Qwen3.6) adapter complete ==="
exit $CLAUDE_EXIT
