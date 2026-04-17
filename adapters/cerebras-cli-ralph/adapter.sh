#!/bin/bash
set -e

# Cerebras CLI Ralph Loop Adapter
# Fresh-context Ralph loop for cerebras-cli with discovery forwarding.
# Each iteration gets fresh context but the workspace persists.
# Discoveries from previous iterations are accumulated and injected.

MIN_ITERATIONS=2
MAX_ITERATIONS=7

[[ -f "$TASK_DESCRIPTION" ]] || { echo "Task file not found: $TASK_DESCRIPTION" >&2; exit 2; }

cd "$TASK_DIR"

# Set up Cerebras auth
mkdir -p "$HOME/.local/share/opencode"
cat > "$HOME/.local/share/opencode/auth.json" <<EOF
{
  "cerebras": {
    "api_key": "${CEREBRAS_API_KEY}"
  }
}
EOF

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

  OUTPUT_FILE="/workspace/.cerebras-stdout-iter${i}.log"
  TOTAL_OUTPUT_FILES+=("$OUTPUT_FILE")

  # Clear cerebras-cli session state between iterations for fresh context
  rm -rf "$HOME/.local/share/opencode/storage" 2>/dev/null || true

  set +e
  cerebras-cli run \
    -m cerebras/gpt-oss-120b \
    --format json \
    "$(cat /tmp/ralph-iter-prompt.txt)" \
    2>"/workspace/.thunderdome-stderr-iter${i}.log" \
    | tee "$OUTPUT_FILE"
  CLI_EXIT=${PIPESTATUS[0]}
  set -e

  echo "Iteration $i: cerebras-cli exited with code $CLI_EXIT" >&2

  # Extract discoveries from this iteration's output (last text block, capped at 500 chars)
  ITER_DISCOVERY=$(python3 -c "
import json, sys

last_text = ''
with open('$OUTPUT_FILE', 'r', errors='replace') as f:
    for line in f:
        line = line.strip()
        if not line:
            continue
        try:
            event = json.loads(line)
        except json.JSONDecodeError:
            continue
        if event.get('type') == 'text':
            last_text = event.get('text', '')

# Cap at 500 chars
if len(last_text) > 500:
    last_text = last_text[:500] + '...'
print(last_text)
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
total_cache_read = 0
total_cache_write = 0

iter_files = sys.argv[1:]

for filepath in iter_files:
    try:
        with open(filepath, 'r', errors='replace') as f:
            for line in f:
                line = line.strip()
                if not line:
                    continue
                try:
                    event = json.loads(line)
                except json.JSONDecodeError:
                    continue
                if event.get('type') == 'step_finish':
                    part = event.get('part', {})
                    tokens = part.get('tokens', {})
                    total_input += tokens.get('input', 0)
                    total_output += tokens.get('output', 0)
                    cache = tokens.get('cache', {})
                    total_cache_read += cache.get('read', 0)
                    total_cache_write += cache.get('write', 0)
    except FileNotFoundError:
        print(f'File not found: {filepath}', file=sys.stderr)
        continue

metrics = {
    'input_tokens': total_input,
    'output_tokens': total_output,
    'cache_read_tokens': total_cache_read,
    'cache_creation_tokens': total_cache_write,
    'total_cost_usd': 0.0,
    'iterations': $ITERATION,
    'note': 'cerebras-cli-ralph-loop',
}
with open('/workspace/.thunderdome-metrics.json', 'w') as f:
    json.dump(metrics, f, indent=2)
print(f'Metrics: in={total_input} out={total_output} cache_r={total_cache_read} cache_w={total_cache_write} iters=$ITERATION', file=sys.stderr)
" "${TOTAL_OUTPUT_FILES[@]}" 2>&1 || true

exit 0
