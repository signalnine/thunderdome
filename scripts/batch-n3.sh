#!/bin/bash
#
# Batch runner: get all Claude-based orchestrators to n=3 full-suite runs
# Pacing: 1 orchestrator at a time, --parallel 2
# Rate limit: ~900 messages per 5-hour rolling window (Claude Max 20x)
# Strategy: 1 full suite run per window, then wait for window to reset
#
set -uo pipefail
# Note: no set -e — we handle errors explicitly to avoid silent deaths

THUNDERDOME="./thunderdome"
RESULTS_DIR="results"
PARALLEL=2
WINDOW_HOURS=5           # Claude Max 20x 5-hour rolling window
WINDOW_SECONDS=$((WINDOW_HOURS * 3600))
SLEEP_BETWEEN=120         # seconds between runs (within window budget)
LOG_FILE="scripts/batch-n3.log"

# Orchestrators that need full-suite runs, ordered by priority (leaderboard rank)
# Format: "orchestrator:runs_needed"
ORCHESTRATORS=(
  # conclave-v6-opus: done (n=3)
  "conclave-review-opus:3"
  "superpowers-plans-opus:3"
  "conclave-v6-sonnet:3"
  "stacked-oauth-opus:3"
  "gsd-oauth-opus:3"
  "bmad-oauth-opus:3"
  "agent-teams-oauth-opus:3"
  "metacog-oauth-opus:3"
  "gas-station-oauth-opus:3"
  "superpowers-tdd-opus:3"
  "claude-code-self-review-opus:3"
  "superpowers-brainstorm-opus:3"
  "claude-code-oauth-opus:3"
  "superpowers-verify-opus:3"
  "superpowers-debug-opus:3"
  "superpowers-review-verify-opus:3"
  "conclave-oauth-opus:3"
  "superpowers-oauth-opus:3"
  "superpowers-review-pure-opus:3"
)

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"
}

# Track when we last completed a run (epoch seconds)
LAST_RUN_FILE="scripts/.batch-n3-last-run"

get_last_run_time() {
  if [ -f "$LAST_RUN_FILE" ]; then
    cat "$LAST_RUN_FILE"
  else
    echo "0"
  fi
}

set_last_run_time() {
  date +%s > "$LAST_RUN_FILE"
}

# Count effective n for an orchestrator (min good trials across all 19 tasks)
count_full_runs() {
  local orch=$1
  python3 -c "
import json, glob
from collections import defaultdict

NO_COST = {'aider', 'aider-gemini', 'cerebras-cli', 'cerebras-cli-ralph', 'swe-agent'}
orch_name = '${orch}'

task_trials = defaultdict(int)
for f in glob.glob('${RESULTS_DIR}/runs/*/trials/${orch}/bench-*/trial-*/meta.json'):
    try:
        m = json.load(open(f))
        cost = m.get('total_cost_usd', None)
        dur = m.get('duration_s', 0) or 0
        # Crash filter: for cost-tracked orchestrators, cost=0/None is crash
        # For no-cost orchestrators, dur<15 is crash
        if orch_name in NO_COST:
            if dur < 15:
                continue
        else:
            if cost is None or cost == 0:
                continue
        parts = f.split('/')
        task = parts[5]
        task_trials[task] += 1
    except:
        pass

if len(task_trials) < 19:
    # Not all tasks covered yet — effective n = 0
    print(0)
else:
    print(min(task_trials.values()))
" 2>/dev/null
}

# Check last run for crash/rate-limit symptoms
# Returns 0 if OK, 1 if the run was mostly crashes (session exhausted)
check_run_health() {
  local run_dir=$1
  local orch=$2
  python3 -c "
import json, glob

crashes = 0
good = 0
total = 0
for f in glob.glob('${run_dir}/trials/${orch}/bench-*/trial-*/meta.json'):
    try:
        m = json.load(open(f))
        total += 1
        cost = m.get('total_cost_usd', 0) or 0
        dur = m.get('duration_s', 0) or 0
        # Crash = zero cost (agent did no useful work)
        if cost == 0 or cost is None:
            crashes += 1
        else:
            good += 1
    except:
        pass

if total == 0:
    print('WARNING: no trials found')
    exit(1)
elif crashes > total / 2:
    print(f'CRASHED: {crashes}/{total} trials were zero-cost crashes — session likely exhausted')
    exit(1)
else:
    print(f'OK: {good}/{total} good, {crashes} crashes')
    exit(0)
" 2>/dev/null
}

# Wait until enough time has passed since our last run
# Claude Max 20x: ~900 messages per 5-hour rolling window
# 1 full suite run ≈ 950 messages, so we space our runs 5 hours apart
wait_for_window() {
  local last_run
  last_run=$(get_last_run_time)
  local now
  now=$(date +%s)
  local elapsed=$((now - last_run))
  local remaining=$((WINDOW_SECONDS - elapsed))

  if [ "$remaining" -gt 0 ]; then
    local resume_time
    resume_time=$(date -d "@$((now + remaining))" '+%H:%M:%S')
    log "Window cooldown: ${remaining}s remaining (resume at ${resume_time})"
    sleep "$remaining"
  fi
  log "Window ready — proceeding"
}

# Main loop
log "=== Batch N=3 runner started ==="
log "5hr rolling window, Parallel: ${PARALLEL}, Sleep between: ${SLEEP_BETWEEN}s"
log "Orchestrators to process: ${#ORCHESTRATORS[@]}"

total_runs_done=0
total_runs_needed=0
for entry in "${ORCHESTRATORS[@]}"; do
  runs_needed=${entry##*:}
  total_runs_needed=$((total_runs_needed + runs_needed))
done
log "Total runs needed: ${total_runs_needed}"

for entry in "${ORCHESTRATORS[@]}"; do
  orch=${entry%%:*}
  runs_needed=${entry##*:}

  log "--- Processing: ${orch} (need ${runs_needed} runs) ---"

  for ((run=1; run<=runs_needed; run++)); do
    # Wait for 5-hour window to have capacity
    wait_for_window

    # Check current full run count (might have gotten runs from concurrent processes)
    current_full=$(count_full_runs "$orch")
    if [ "$current_full" -ge 3 ]; then
      log "${orch} already at n=${current_full} >= 3, skipping remaining runs"
      break
    fi

    log "Starting run ${run}/${runs_needed} for ${orch} (currently at n=${current_full})"

    # Run the suite, capturing output to extract run directory
    run_start=$(date +%s)
    run_output_tmp=$(mktemp)
    $THUNDERDOME run --orchestrator "$orch" --trials 1 --parallel "$PARALLEL" 2>&1 | tee -a "$LOG_FILE" | tee "$run_output_tmp"
    thunderdome_rc=${PIPESTATUS[0]}

    run_end=$(date +%s)
    run_duration=$((run_end - run_start))
    log "Run completed in ${run_duration}s (exit code: ${thunderdome_rc})"

    if [ "$thunderdome_rc" -eq 0 ]; then
      # Extract run directory from thunderdome output (not ls -td which races with other processes)
      run_dir=$(grep -a 'Run directory:' "$run_output_tmp" | head -1 | sed 's/.*Run directory: //')
      rm -f "$run_output_tmp"

      if [ -n "$run_dir" ] && [ -d "$run_dir" ]; then
        log "Run dir: ${run_dir}"
        # Check for session exhaustion (mass crashes)
        health_msg=$(check_run_health "$run_dir" "$orch")
        health_rc=$?
        log "$health_msg"
        if [ "$health_rc" -ne 0 ]; then
          log "Session exhausted. Waiting for full window reset (${WINDOW_HOURS}h)..."
          sleep "$WINDOW_SECONDS"
          # Re-do this run (don't increment counter)
          run=$((run - 1))
          continue
        fi
      else
        log "WARNING: could not extract run directory from output"
      fi

      set_last_run_time
      total_runs_done=$((total_runs_done + 1))
      log "Progress: ${total_runs_done}/${total_runs_needed} total runs done"
    else
      rm -f "$run_output_tmp"
      log "ERROR: thunderdome run failed for ${orch}. Pausing 5 minutes before continuing..."
      sleep 300
    fi

    # Sleep between runs
    if [ "$run" -lt "$runs_needed" ] || [ "$total_runs_done" -lt "$total_runs_needed" ]; then
      log "Sleeping ${SLEEP_BETWEEN}s before next run..."
      sleep "$SLEEP_BETWEEN"
    fi
  done
done

log "=== Batch N=3 runner complete ==="
log "Total runs executed: ${total_runs_done}/${total_runs_needed}"

# Final summary
log "--- Final full-run counts ---"
for entry in "${ORCHESTRATORS[@]}"; do
  orch=${entry%%:*}
  count=$(count_full_runs "$orch")
  log "  ${orch}: n=${count}"
done
