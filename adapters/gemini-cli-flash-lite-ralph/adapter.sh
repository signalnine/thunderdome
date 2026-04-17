#!/bin/bash
set -e

# Gemini CLI Flash-Lite Ralph Loop Adapter
# Fresh-context Ralph loop with discovery forwarding.
# Each iteration gets fresh context but the workspace persists.

MIN_ITERATIONS=2
MAX_ITERATIONS=7

[[ -f "$TASK_DESCRIPTION" ]] || { echo "Task file not found: $TASK_DESCRIPTION" >&2; exit 2; }

cd "$TASK_DIR"

# Copy Gemini OAuth credentials from read-only mount to writable HOME
export HOME=/tmp
if [[ -d /tmp/.gemini-host ]]; then
  cp -r /tmp/.gemini-host "$HOME/.gemini"
  chmod -R u+rw "$HOME/.gemini"
fi

ORIGINAL_PROMPT=$(cat "$TASK_DESCRIPTION")

TOTAL_OUTPUT_FILES=()
ITERATION=0
DISCOVERIES=""

for i in $(seq 1 $MAX_ITERATIONS); do
  ITERATION=$i
  echo "=== Ralph Loop: Iteration $i of $MAX_ITERATIONS ===" >&2

  # Build the prompt
  if [ $i -eq 1 ]; then
    ITER_PROMPT="$ORIGINAL_PROMPT"
  else
    # Run tests and capture output for the prompt
    cd "$TASK_DIR"
    TEST_OUTPUT=$(npm test 2>&1 || true)

    # Extract summary line
    SUMMARY=$(echo "$TEST_OUTPUT" | grep -E "Tests\s+" | tail -1)

    # Extract failure details (first 80 lines of failures)
    FAILURES=$(echo "$TEST_OUTPUT" | grep -B 1 -A 5 "FAIL\|AssertionError\|Error:" | head -80)

    ITER_PROMPT="$ORIGINAL_PROMPT

---

## Current Progress (Iteration $i of $MAX_ITERATIONS)

Previous iterations have made progress on this task. The workspace already contains code from earlier attempts.

**Test summary:** $SUMMARY

**Failure details (excerpt):**
\`\`\`
$FAILURES
\`\`\`"

    # Add accumulated discoveries if any
    if [ -n "$DISCOVERIES" ]; then
      ITER_PROMPT="$ITER_PROMPT

## Discoveries from Previous Iterations

$DISCOVERIES"
    fi

    ITER_PROMPT="$ITER_PROMPT

IMPORTANT: Start by reading the existing code in the workspace. Understand what has already been implemented. Then:
1. Run \`npm test\` to see the current state of ALL tests
2. Identify which phases/features are incomplete or broken
3. Fix issues and implement missing functionality
4. Do NOT rewrite working code — build on what exists
5. Run \`npm test\` again to verify your changes"
  fi

  # Write prompt to temp file to avoid shell escaping issues
  printf '%s' "$ITER_PROMPT" > /tmp/ralph-iter-prompt.txt

  OUTPUT_FILE="/workspace/.gemini-output-iter${i}.json"
  TOTAL_OUTPUT_FILES+=("$OUTPUT_FILE")

  # Clear Gemini CLI conversation state between iterations for fresh context
  rm -rf "$HOME/.gemini/history" "$HOME/.gemini/conversations" 2>/dev/null || true

  set +e
  gemini -p "$(cat /tmp/ralph-iter-prompt.txt)" \
    --model gemini-2.5-flash-lite \
    --yolo \
    --sandbox false \
    --output-format json \
    2>"/workspace/.thunderdome-stderr-iter${i}.log" \
    > "$OUTPUT_FILE"
  CLI_EXIT=$?
  set -e

  echo "Iteration $i: gemini exited with code $CLI_EXIT" >&2

  # Check for quota exhaustion — bail out entirely
  if [[ $CLI_EXIT -ne 0 ]] && grep -qi 'quota' "/workspace/.thunderdome-stderr-iter${i}.log" 2>/dev/null; then
    echo "ERROR: Gemini API quota exhausted at iteration $i" >&2
    break
  fi

  # Extract discovery from this iteration's output (last assistant response, capped at 500 chars)
  ITER_DISCOVERY=$(python3 -c "
import json, sys

try:
    with open('$OUTPUT_FILE', 'r') as f:
        data = json.load(f)
    response = data.get('response', '')
    # Cap at 500 chars
    if len(response) > 500:
        response = response[:500] + '...'
    print(response)
except Exception:
    pass
" 2>/dev/null || true)

  if [ -n "$ITER_DISCOVERY" ]; then
    DISCOVERIES="${DISCOVERIES}
- **Iteration $i**: $ITER_DISCOVERY"
  fi

  # After minimum iterations, check if tests pass
  if [ $i -ge $MIN_ITERATIONS ]; then
    cd "$TASK_DIR"
    set +e
    npm test > /tmp/ralph-test-check.log 2>&1
    TEST_EXIT=$?
    set -e

    if [ $TEST_EXIT -eq 0 ]; then
      echo "=== All tests pass after iteration $i! ===" >&2
      break
    else
      SUMMARY=$(grep -E "Tests\s+" /tmp/ralph-test-check.log | tail -1)
      echo "Iteration $i tests: $SUMMARY — continuing" >&2
    fi
  fi
done

echo "=== Ralph Loop complete: $ITERATION iterations ===" >&2

# Aggregate metrics across all iterations
python3 -c "
import json, sys

total_input = 0
total_output = 0
total_cached = 0
total_thoughts = 0
total_turns = 0

iter_files = sys.argv[1:]

for filepath in iter_files:
    try:
        with open(filepath, 'r') as f:
            data = json.load(f)
    except Exception:
        continue

    stats = data.get('stats', {})
    models = stats.get('models', {})
    tools = stats.get('tools', {})

    for model_name, model_data in models.items():
        tokens = model_data.get('tokens', {})
        total_input += tokens.get('input', 0)
        total_output += tokens.get('candidates', 0)
        total_cached += tokens.get('cached', 0)
        total_thoughts += tokens.get('thoughts', 0)

    total_turns += tools.get('totalCalls', 0)

# Gemini 2.5 Flash-Lite: \$0.25/1M input, \$1.50/1M output, \$0.025/1M cached
cost = (total_input * 0.25 + (total_output + total_thoughts) * 1.50 + total_cached * 0.025) / 1e6

metrics = {
    'input_tokens': total_input,
    'output_tokens': total_output,
    'cache_read_tokens': total_cached,
    'cache_creation_tokens': 0,
    'thought_tokens': total_thoughts,
    'turns': total_turns,
    'total_cost_usd': round(cost, 6),
    'iterations': $ITERATION,
    'note': 'gemini-flash-lite-ralph-loop',
}
with open('/workspace/.thunderdome-metrics.json', 'w') as f:
    json.dump(metrics, f, indent=2)
print(f'Metrics: in={total_input} out={total_output} cached={total_cached} thoughts={total_thoughts} turns={total_turns} iters=$ITERATION', file=sys.stderr)
" "${TOTAL_OUTPUT_FILES[@]}" 2>&1 || true

exit 0
