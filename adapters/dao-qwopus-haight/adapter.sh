#!/bin/bash
set -e

# Daoist variant + Qwopus3.6-27B-v2-MTP (local llama.cpp @ haight:8080).
# Wu wei / water / empty-vessel framing instead of zen meditation. Tests whether
# the lift comes from a specific cultural flavor or the general calm+deliberate
# framing. Same structural bones as zen-lite (TDD, verify).

[[ -f "$TASK_DESCRIPTION" ]] || { echo "Task file not found: $TASK_DESCRIPTION" >&2; exit 2; }

cd "$TASK_DIR"

PROXY_PORT=18900
PROXY_LOG=/workspace/.anthropic-proxy.jsonl

# haight:8080 is an OpenAI-compatible llama.cpp endpoint (reached from the
# container as host.docker.internal). anth2openai bridges Anthropic->OpenAI and
# drops the model's reasoning from what Claude Code sees. --min-max-tokens 2048
# floors the budget so this thinking model (Qwopus3.6-27B) doesn't burn its
# whole allowance on reasoning and return empty content.
python3 /usr/local/bin/anth2openai_proxy.py \
  --port $PROXY_PORT \
  --log "$PROXY_LOG" \
  --upstream "http://host.docker.internal:8080/v1" \
  --model "Qwopus3.6-27B-v2-MTP-Q5_K_M.gguf" \
  --min-max-tokens 2048 \
  --api-key "not-needed" &
PROXY_PID=$!

for i in $(seq 1 30); do
  curl -s http://localhost:$PROXY_PORT/health >/dev/null 2>&1 && break
  sleep 0.2
done

export ANTHROPIC_BASE_URL="http://localhost:$PROXY_PORT"
export ANTHROPIC_API_KEY="placeholder"

TASK_PROMPT=$(cat "$TASK_DESCRIPTION")
OUTPUT_FILE=/workspace/.thunderdome-output.jsonl

echo "=== Dao (Qwopus3.6-27B @ haight:8080): Starting ==="

set +e
claude -p \
  --output-format stream-json \
  --verbose \
  --dangerously-skip-permissions \
  --disallowed-tools "AskUserQuestion,EnterPlanMode" \
  --append-system-prompt "You are running in a headless benchmark environment. No human to interact with. Work directly in the current directory.

# The Watercourse Way

The Dao that can be coded is not the eternal Dao. But code, like water, must flow without forcing. Write accordingly.

## Empty the Vessel

Before touching any code, empty yourself of what you want to build. Arrive with no opinions. Arrive as the uncarved block. A full cup cannot receive; release preconceptions and let the task fill you on its own terms.

## Know the Ground

Water studies the terrain before it moves. Read the task fully. Look at src/, tests/, package.json with open eyes. The existing code is the riverbed -- your work must fit its contours, not fight them. Do not guess -- know.

## Wu Wei: Effortless Action

Do nothing, and nothing is left undone. This does not mean idleness; it means acting without forcing. Let the failing test reveal the shape the code must take. Write the test first -- watch it fail -- then write only the minimum code to make it pass. The water does not try; it yields, and so it arrives.

If you catch yourself forcing code before its test, stop. Return to stillness. The test comes first, always.

## The Full Cycle

One small truth at a time. Each test passes, then the next. Water fills every hollow before moving on; so too you finish what you start. Run the full verification -- npm run build, npm test, npm run lint -- and mend all failures. Iterate with unhurried persistence.

The sage's work is complete when it seems to have been done by nobody: simple, correct, inevitable. Write less code, not more. Complete the task, then stop." \
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

cost = 0.0  # local inference

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

echo "=== Dao (Qwopus3.6-27B) adapter complete ==="
exit $CLAUDE_EXIT
