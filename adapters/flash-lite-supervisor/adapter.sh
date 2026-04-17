#!/bin/bash
set -e

# Flash-Lite Supervisor Adapter
# Decompose → Fan-Out → Filter → Select pipeline.
# A frontier supervisor (Opus or Gemini Pro) decomposes the task into subtasks,
# then fans out parallel Flash-Lite Ralph workers per subtask, mechanically
# filters results by test score, and optionally uses the supervisor to break ties.
#
# Env vars:
#   SUPERVISOR_MODEL  — "claude-opus-4-6" or "gemini-3.1-pro-preview"
#   TASK_DIR          — /workspace
#   TASK_DESCRIPTION  — path to task.md
#   TIME_LIMIT_MINUTES (optional) — from thunderdome config

[[ -f "$TASK_DESCRIPTION" ]] || { echo "Task file not found: $TASK_DESCRIPTION" >&2; exit 2; }

cd "$TASK_DIR"
export HOME=/tmp

SUPERVISOR_MODEL="${SUPERVISOR_MODEL:-claude-opus-4-6}"
TIME_LIMIT="${TIME_LIMIT_MINUTES:-30}"
ORIGINAL_PROMPT=$(cat "$TASK_DESCRIPTION")

# Shared state
WINNER=1
SUBTASKS_FILE=/tmp/subtasks.json

# --- Credential setup ---
setup_credentials() {
  # Claude OAuth
  if [ -f /tmp/.claude-credentials.json ]; then
    mkdir -p "$HOME/.claude"
    cp /tmp/.claude-credentials.json "$HOME/.claude/.credentials.json"
  fi

  # Gemini OAuth — copy to canonical location
  if [[ -d /tmp/.gemini-host ]]; then
    cp -r /tmp/.gemini-host "$HOME/.gemini"
    chmod -R u+rw "$HOME/.gemini"
  fi
}

# --- Time budget ---
compute_budget() {
  if [ "$TIME_LIMIT" -le 15 ]; then
    MAX_SUBTASKS=2; NUM_WORKERS=2; WORKER_ITERS=2
  elif [ "$TIME_LIMIT" -le 30 ]; then
    MAX_SUBTASKS=2; NUM_WORKERS=3; WORKER_ITERS=3
  else
    MAX_SUBTASKS=3; NUM_WORKERS=3; WORKER_ITERS=3
  fi
  export MAX_SUBTASKS NUM_WORKERS WORKER_ITERS
  echo "Budget: ${MAX_SUBTASKS} subtasks, ${NUM_WORKERS} workers, ${WORKER_ITERS} iters (time_limit=${TIME_LIMIT}m)" >&2
}

# --- Supervisor invocation ---
# Calls the supervisor model with a prompt, writes response text to stdout.
# $1 = raw output file path, $2 = prompt text
run_supervisor() {
  local output_file="$1"
  local prompt="$2"
  local prompt_file="/tmp/supervisor-prompt-$$.txt"

  printf '%s' "$prompt" > "$prompt_file"

  if [[ "$SUPERVISOR_MODEL" == claude-* ]]; then
    set +e
    claude -p \
      --model "$SUPERVISOR_MODEL" \
      --output-format stream-json \
      --verbose \
      --dangerously-skip-permissions \
      --disallowed-tools "AskUserQuestion,EnterPlanMode" \
      -- "$(cat "$prompt_file")" \
      > "$output_file" 2>/tmp/supervisor-stderr.log
    local exit_code=$?
    set -e

    # Extract text from NDJSON
    python3 -c "
import json, sys
text = ''
for line in open(sys.argv[1]):
    line = line.strip()
    if not line: continue
    try:
        msg = json.loads(line)
        if msg.get('type') == 'result':
            result = msg.get('result', '')
            if isinstance(result, str):
                text = result
            elif isinstance(result, list):
                for block in result:
                    if isinstance(block, dict) and block.get('type') == 'text':
                        text += block.get('text', '')
    except: pass
if not text:
    for line in open(sys.argv[1]):
        line = line.strip()
        if not line: continue
        try:
            msg = json.loads(line)
            if msg.get('type') == 'assistant' and msg.get('message'):
                for block in msg['message'].get('content', []):
                    if isinstance(block, dict) and block.get('type') == 'text':
                        text += block.get('text', '')
        except: pass
print(text)
" "$output_file" 2>/dev/null
    return $exit_code

  else
    # Gemini CLI — clear conversation state first
    rm -rf "$HOME/.gemini/history" "$HOME/.gemini/conversations" 2>/dev/null || true
    set +e
    gemini -p "$(cat "$prompt_file")" \
      --model "$SUPERVISOR_MODEL" \
      --yolo \
      --sandbox false \
      --output-format json \
      > "$output_file" 2>/tmp/supervisor-stderr.log
    local exit_code=$?
    set -e

    python3 -c "
import json, sys
data = json.load(open(sys.argv[1]))
print(data.get('response', ''))
" "$output_file" 2>/dev/null
    return $exit_code
  fi
}

# --- Task decomposition ---
decompose_task() {
  echo "=== Decomposing task into subtasks (supervisor: $SUPERVISOR_MODEL) ===" >&2

  local decompose_prompt="You are a technical project supervisor. Decompose this programming task into $MAX_SUBTASKS ordered subtasks that can be implemented sequentially. Each subtask should be independently testable.

Output ONLY a JSON array (no markdown fences, no explanation):
[{\"id\": 1, \"description\": \"...\", \"acceptance\": \"...\", \"files_likely\": [\"...\"]}]

Rules:
- Maximum $MAX_SUBTASKS subtasks
- Each subtask should produce code that passes at least some tests
- Order subtasks so earlier ones create foundations for later ones
- Keep descriptions specific and actionable (not vague)
- First subtask should set up core structure/types
- Last subtask should handle edge cases and polish

TASK:
$ORIGINAL_PROMPT"

  local response
  response=$(run_supervisor /tmp/decompose-output.json "$decompose_prompt" || true)

  # Extract JSON array from response, write to file (avoids shell quoting)
  echo "$response" | python3 -c "
import json, re, sys

text = sys.stdin.read()
max_subtasks = int(sys.argv[1])

patterns = [
    r'\`\`\`json?\s*\n(.*?)\n\`\`\`',
    r'(\[.*\])',
]
for pat in patterns:
    m = re.search(pat, text, re.DOTALL)
    if m:
        try:
            arr = json.loads(m.group(1))
            if isinstance(arr, list) and len(arr) > 0:
                arr = arr[:max_subtasks]
                json.dump(arr, open(sys.argv[2], 'w'))
                sys.exit(0)
        except json.JSONDecodeError:
            continue

fallback = [{'id': 1, 'description': 'Complete the entire task as described.', 'acceptance': 'All tests pass.', 'files_likely': []}]
json.dump(fallback, open(sys.argv[2], 'w'))
" "$MAX_SUBTASKS" "$SUBTASKS_FILE"

  if [[ ! -s "$SUBTASKS_FILE" ]]; then
    echo "WARNING: Decomposition failed or empty response. Falling back to single subtask." >&2
    echo '[{"id": 1, "description": "Complete the entire task as described.", "acceptance": "All tests pass.", "files_likely": []}]' > "$SUBTASKS_FILE"
  fi

  NUM_SUBTASKS=$(python3 -c "import json; print(len(json.load(open('$SUBTASKS_FILE'))))")
  export NUM_SUBTASKS
  echo "Decomposed into $NUM_SUBTASKS subtasks" >&2
}

# --- Single Flash-Lite Ralph worker ---
# $1 = workspace dir, $2 = prompt file, $3 = worker id
run_worker() {
  local work_dir="$1"
  local prompt_file="$2"
  local worker_id="$3"
  local prompt
  prompt=$(cat "$prompt_file")

  # Each worker gets its own HOME to avoid Gemini state collisions
  local worker_home="/tmp/home-worker-${worker_id}"
  mkdir -p "$worker_home"
  # Copy Gemini creds to worker's home
  if [[ -d "$HOME/.gemini" ]]; then
    cp -r "$HOME/.gemini" "$worker_home/.gemini"
  fi

  cd "$work_dir"

  local discoveries=""

  for iter in $(seq 1 $WORKER_ITERS); do
    echo "  Worker $worker_id: iteration $iter/$WORKER_ITERS" >&2

    local iter_prompt="$prompt"

    if [ "$iter" -gt 1 ]; then
      local test_output
      test_output=$(cd "$work_dir" && npm test 2>&1 || true)
      local summary
      summary=$(echo "$test_output" | grep -E "Tests\s+" | tail -1)
      local failures
      failures=$(echo "$test_output" | grep -B 1 -A 5 "FAIL\|AssertionError\|Error:" | head -60)

      iter_prompt="$prompt

---
## Iteration $iter — Fix Remaining Issues

**Test summary:** $summary

**Failure details:**
\`\`\`
$failures
\`\`\`"

      if [ -n "$discoveries" ]; then
        iter_prompt="$iter_prompt

## Discoveries
$discoveries"
      fi

      iter_prompt="$iter_prompt

IMPORTANT: Read existing code first. Build on what exists. Run npm test to verify."
    fi

    local iter_prompt_file="/tmp/worker-${worker_id}-iter${iter}-prompt.txt"
    printf '%s' "$iter_prompt" > "$iter_prompt_file"

    # Clear Gemini conversation state between iterations
    rm -rf "$worker_home/.gemini/history" "$worker_home/.gemini/conversations" 2>/dev/null || true

    local output_file="$work_dir/.gemini-output-w${worker_id}-iter${iter}.json"

    set +e
    HOME="$worker_home" gemini -p "$(cat "$iter_prompt_file")" \
      --model gemini-2.5-flash-lite \
      --yolo \
      --sandbox false \
      --output-format json \
      2>"$work_dir/.worker-${worker_id}-stderr-iter${iter}.log" \
      > "$output_file"
    local cli_exit=$?
    set -e

    # Bail on quota exhaustion
    if [[ $cli_exit -ne 0 ]] && grep -qi 'quota' "$work_dir/.worker-${worker_id}-stderr-iter${iter}.log" 2>/dev/null; then
      echo "  Worker $worker_id: quota exhausted at iter $iter" >&2
      break
    fi

    # Extract discovery for next iteration
    local iter_discovery
    iter_discovery=$(python3 -c "
import json, sys
try:
    data = json.load(open(sys.argv[1]))
    r = data.get('response', '')[:300]
    print(r)
except: pass
" "$output_file" 2>/dev/null || true)
    if [ -n "$iter_discovery" ]; then
      discoveries="${discoveries}
- Iter $iter: $iter_discovery"
    fi

    # Early exit if tests pass (after at least 1 full iteration)
    if [ "$iter" -ge 2 ]; then
      set +e
      cd "$work_dir" && npm test > "/tmp/worker-${worker_id}-test.log" 2>&1
      local test_exit=$?
      set -e
      if [ $test_exit -eq 0 ]; then
        echo "  Worker $worker_id: all tests pass at iter $iter" >&2
        break
      fi
    fi
  done
}

# --- Mechanical filter ---
# Runs npm test in each worker dir, scores and ranks.
# Sets global WINNER to the best worker number.
mechanical_filter() {
  local subtask_id="$1"
  echo "=== Filtering subtask $subtask_id results ===" >&2

  local best_score=-999999
  WINNER=1

  # Write scores to a temp file so we can do tie-breaking
  local scores_file="/tmp/scores-${subtask_id}.txt"
  > "$scores_file"

  for w in $(seq 1 $NUM_WORKERS); do
    local wdir="/tmp/worker-${subtask_id}-${w}"
    [ -d "$wdir" ] || continue

    set +e
    local test_out
    test_out=$(cd "$wdir" && npm test 2>&1)
    local test_exit=$?
    set -e

    local passed=0 failed=0
    passed=$(echo "$test_out" | grep -oP '(\d+)\s+passed' | grep -oP '\d+' | tail -1 || echo "0")
    failed=$(echo "$test_out" | grep -oP '(\d+)\s+failed' | grep -oP '\d+' | tail -1 || echo "0")
    [ -z "$passed" ] && passed=0
    [ -z "$failed" ] && failed=0

    # If test exited 0 but no parsed counts, assume full pass
    if [ "$test_exit" -eq 0 ] && [ "$passed" -eq 0 ] && [ "$failed" -eq 0 ]; then
      passed=100
    fi

    # Lint check
    set +e
    cd "$wdir" && npm run lint > /dev/null 2>&1
    local lint_clean=$?
    set -e
    [ "$lint_clean" -eq 0 ] && lint_clean=1 || lint_clean=0

    # Diff size
    local diff_lines=0
    set +e
    diff_lines=$(cd "$wdir" && git diff --stat 2>/dev/null | tail -1 | grep -oP '\d+' | head -1 || echo "0")
    set -e
    [ -z "$diff_lines" ] && diff_lines=0

    local score=$(( passed * 1000 - failed * 100 + lint_clean * 50 - diff_lines ))
    echo "  Worker $w: passed=$passed failed=$failed lint=$lint_clean diff=$diff_lines -> score=$score" >&2
    echo "$w $score" >> "$scores_file"

    if [ "$score" -gt "$best_score" ]; then
      best_score=$score
      WINNER=$w
    fi
  done

  echo "  Winner: worker $WINNER (score=$best_score)" >&2

  # Check if top-2 are within 10% — invoke supervisor tie-break
  local second_best
  second_best=$(sort -k2 -rn "$scores_file" | awk 'NR==2{print $2}')
  if [ -n "$second_best" ] && [ "$best_score" -gt 0 ] && [ "$second_best" -gt 0 ]; then
    local threshold=$(( best_score * 90 / 100 ))
    if [ "$second_best" -ge "$threshold" ]; then
      echo "  Close race — invoking supervisor select" >&2
      supervisor_select "$subtask_id"
    fi
  fi
}

# --- Supervisor tie-breaker ---
supervisor_select() {
  local subtask_id="$1"

  local diffs=""
  for w in $(seq 1 $NUM_WORKERS); do
    local wdir="/tmp/worker-${subtask_id}-${w}"
    [ -d "$wdir" ] || continue
    local wdiff
    wdiff=$(cd "$wdir" && git diff 2>/dev/null | head -100)
    diffs="${diffs}

=== Worker $w ===
$wdiff"
  done

  local select_prompt="You are reviewing code changes from $NUM_WORKERS workers implementing the same subtask.
Pick the best implementation. Reply with ONLY a single digit (the worker number, 1-${NUM_WORKERS}).

$diffs"

  local response
  response=$(run_supervisor "/tmp/select-output-${subtask_id}.json" "$select_prompt" || true)

  local pick
  pick=$(echo "$response" | grep -oP '\d' | head -1)
  if [ -n "$pick" ] && [ "$pick" -ge 1 ] 2>/dev/null && [ "$pick" -le "$NUM_WORKERS" ] 2>/dev/null; then
    WINNER=$pick
    echo "  Supervisor selected worker $WINNER" >&2
  fi
}

# --- Copy winner workspace back to /workspace ---
copy_winner_back() {
  local subtask_id="$1"
  local wdir="/tmp/worker-${subtask_id}-${WINNER}"

  echo "=== Copying worker $WINNER result back to /workspace ===" >&2
  cd "$wdir"
  tar cf - --exclude='.git' --exclude='node_modules' \
           --exclude='.gemini-output-*' --exclude='.worker-*' . \
    | tar xf - -C /workspace/
  cd /workspace
}

# --- Metrics aggregation ---
aggregate_metrics() {
  echo "=== Aggregating metrics ===" >&2

  python3 << 'PYEOF'
import json, glob, os, sys

# Worker outputs are saved per-subtask before cleanup
gemini_files = glob.glob("/tmp/metrics-worker-*.json")
# Supervisor output files
supervisor_files = glob.glob("/tmp/decompose-output.json") + glob.glob("/tmp/select-output-*.json")

supervisor_model = os.environ.get("SUPERVISOR_MODEL", "unknown")

worker_input = 0
worker_output = 0
worker_cached = 0
worker_thoughts = 0
worker_turns = 0

for fp in gemini_files:
    try:
        data = json.load(open(fp))
        worker_input += data.get("input", 0)
        worker_output += data.get("output", 0)
        worker_cached += data.get("cached", 0)
        worker_thoughts += data.get("thoughts", 0)
        worker_turns += data.get("turns", 0)
    except Exception:
        continue

sup_input = 0
sup_output = 0
sup_cached = 0

for fp in supervisor_files:
    try:
        if supervisor_model.startswith("claude"):
            for line in open(fp):
                line = line.strip()
                if not line:
                    continue
                try:
                    msg = json.loads(line)
                    if msg.get("type") == "result" and msg.get("usage"):
                        u = msg["usage"]
                        sup_input += u.get("input_tokens", 0)
                        sup_output += u.get("output_tokens", 0)
                        sup_cached += u.get("cache_read_input_tokens", 0)
                except Exception:
                    continue
        else:
            data = json.load(open(fp))
            for model_name, model_data in data.get("stats", {}).get("models", {}).items():
                tokens = model_data.get("tokens", {})
                sup_input += tokens.get("input", 0)
                sup_output += tokens.get("candidates", 0)
                sup_cached += tokens.get("cached", 0)
    except Exception:
        continue

# Flash-Lite: $0.25/1M in, $1.50/1M out, $0.025/1M cached
worker_cost = (worker_input * 0.25 + (worker_output + worker_thoughts) * 1.50 + worker_cached * 0.025) / 1e6

if supervisor_model.startswith("claude"):
    # Opus OAuth = no real cost, but track notional
    sup_cost = (sup_input * 15.0 + sup_output * 75.0 + sup_cached * 3.75) / 1e6
else:
    # Gemini Pro OAuth = no real cost, but track notional
    sup_cost = (sup_input * 1.25 + sup_output * 10.0 + sup_cached * 0.3125) / 1e6

total_cost = worker_cost + sup_cost

metrics = {
    "input_tokens": worker_input + sup_input,
    "output_tokens": worker_output + sup_output,
    "cache_read_tokens": worker_cached + sup_cached,
    "cache_creation_tokens": 0,
    "thought_tokens": worker_thoughts,
    "turns": worker_turns,
    "total_cost_usd": round(total_cost, 6),
    "worker_cost_usd": round(worker_cost, 6),
    "supervisor_cost_usd": round(sup_cost, 6),
    "supervisor_model": supervisor_model,
    "note": "flash-lite-supervisor-pipeline",
}

with open("/workspace/.thunderdome-metrics.json", "w") as f:
    json.dump(metrics, f, indent=2)

print(f"Metrics: workers_in={worker_input} workers_out={worker_output} "
      f"sup_in={sup_input} sup_out={sup_output} "
      f"worker_cost=${worker_cost:.4f} sup_cost=${sup_cost:.4f} "
      f"total=${total_cost:.4f}", file=sys.stderr)
PYEOF
}

# --- Harvest worker metrics before cleanup ---
# Scans gemini output files in a worker dir, aggregates to a single summary file
harvest_worker_metrics() {
  local subtask_id="$1"
  for w in $(seq 1 $NUM_WORKERS); do
    local wdir="/tmp/worker-${subtask_id}-${w}"
    [ -d "$wdir" ] || continue

    python3 -c "
import json, glob, sys
wdir = sys.argv[1]
worker_id = sys.argv[2]
files = glob.glob(wdir + '/.gemini-output-*.json')
inp = out = cached = thoughts = turns = 0
for fp in files:
    try:
        data = json.load(open(fp))
        stats = data.get('stats', {})
        for m in stats.get('models', {}).values():
            t = m.get('tokens', {})
            inp += t.get('input', 0)
            out += t.get('candidates', 0)
            cached += t.get('cached', 0)
            thoughts += t.get('thoughts', 0)
        turns += stats.get('tools', {}).get('totalCalls', 0)
    except: continue
json.dump({'input': inp, 'output': out, 'cached': cached, 'thoughts': thoughts, 'turns': turns},
          open(f'/tmp/metrics-worker-{worker_id}.json', 'w'))
" "$wdir" "${subtask_id}-${w}"
  done
}

# =============================================================================
# MAIN
# =============================================================================

setup_credentials
compute_budget
decompose_task

# Install dependencies once in main workspace
echo "=== Installing dependencies ===" >&2
cd /workspace
npm install --ignore-scripts 2>/dev/null || npm install 2>/dev/null || true

PROGRESS_SUMMARY=""

for s in $(seq 1 $NUM_SUBTASKS); do
  # Extract subtask info from file (avoids shell quoting issues)
  SUBTASK_DESC=$(python3 -c "
import json, sys
tasks = json.load(open(sys.argv[1]))
print(tasks[int(sys.argv[2]) - 1].get('description', ''))
" "$SUBTASKS_FILE" "$s")

  SUBTASK_ACCEPT=$(python3 -c "
import json, sys
tasks = json.load(open(sys.argv[1]))
print(tasks[int(sys.argv[2]) - 1].get('acceptance', ''))
" "$SUBTASKS_FILE" "$s")

  echo "=== Subtask $s/$NUM_SUBTASKS: $SUBTASK_DESC ===" >&2

  # Build worker prompt
  WORKER_PROMPT="$ORIGINAL_PROMPT

---
## Your Focus: Subtask $s of $NUM_SUBTASKS
$SUBTASK_DESC

## Acceptance Criteria
$SUBTASK_ACCEPT"

  if [ -n "$PROGRESS_SUMMARY" ]; then
    WORKER_PROMPT="$WORKER_PROMPT

## Context from Previous Subtasks
$PROGRESS_SUMMARY"
  fi

  WORKER_PROMPT="$WORKER_PROMPT

IMPORTANT: Start by reading existing code. Build on what exists. Run npm test frequently."

  # Write prompt to file for workers to read
  WORKER_PROMPT_FILE="/tmp/worker-prompt-subtask-${s}.txt"
  printf '%s' "$WORKER_PROMPT" > "$WORKER_PROMPT_FILE"

  # --- Fan out workers ---
  echo "=== Fanning out $NUM_WORKERS workers for subtask $s ===" >&2

  for w in $(seq 1 $NUM_WORKERS); do
    local_dir="/tmp/worker-${s}-${w}"
    cp -r /workspace "$local_dir"
  done

  # Launch workers in parallel
  for w in $(seq 1 $NUM_WORKERS); do
    local_dir="/tmp/worker-${s}-${w}"
    run_worker "$local_dir" "$WORKER_PROMPT_FILE" "${s}-${w}" &
  done
  wait

  # --- Filter ---
  mechanical_filter "$s"

  # --- Copy winner back ---
  copy_winner_back "$s"

  # --- Harvest metrics before cleanup ---
  harvest_worker_metrics "$s"

  # Update progress summary
  cd /workspace
  set +e
  TEST_OUT=$(npm test 2>&1)
  TEST_SUMMARY=$(echo "$TEST_OUT" | grep -E "Tests\s+" | tail -1)
  set -e
  PROGRESS_SUMMARY="${PROGRESS_SUMMARY}
- Subtask $s ($SUBTASK_DESC): $TEST_SUMMARY"

  # Clean up worker dirs to free disk
  for w in $(seq 1 $NUM_WORKERS); do
    rm -rf "/tmp/worker-${s}-${w}" 2>/dev/null || true
  done
done

echo "=== Pipeline complete ===" >&2

aggregate_metrics

exit 0
