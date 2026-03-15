#!/bin/bash
#
# Focused batch runner: get top-10 orchestrators to n=3
# Same pacing as batch-n3.sh but only targets orchestrators that need it
#
set -uo pipefail

THUNDERDOME="./thunderdome"
RESULTS_DIR="results"
PARALLEL=2
WINDOW_HOURS=2.5
WINDOW_SECONDS=$((5 * 3600 / 2))
SLEEP_BETWEEN=120
LOG_FILE="scripts/batch-top10.log"
LAST_RUN_FILE="scripts/.batch-top10-last-run"

ORCHESTRATORS=(
  "agent-teams-oauth-opus"
  "gsd-oauth-opus"
  "bmad-oauth-opus"
  "stacked-oauth-opus"
  "metacog-error-opus"
)

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

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
count_effective_n() {
  local orch=$1
  python3 -c "
import json, glob
from collections import defaultdict

task_trials = defaultdict(int)
for f in glob.glob('${RESULTS_DIR}/runs/*/trials/${orch}/bench-*/trial-*/meta.json'):
    try:
        m = json.load(open(f))
        cost = m.get('total_cost_usd', None)
        if cost is None or cost == 0:
            continue
        task = f.split('/')[5]
        task_trials[task] += 1
    except:
        pass

if len(task_trials) < 19:
    print(0)
else:
    print(min(task_trials.values()))
" 2>/dev/null
}

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
        cost = m.get('total_cost_usd', None)
        if cost is None or cost == 0:
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
log "=== Top-10 backfill started ==="
log "Target: n=3 for ${#ORCHESTRATORS[@]} orchestrators"

for orch in "${ORCHESTRATORS[@]}"; do
  while true; do
    current_n=$(count_effective_n "$orch")
    if [ "$current_n" -ge 3 ]; then
      log "${orch}: n=${current_n} >= 3, done"
      break
    fi

    wait_for_window

    log "${orch}: n=${current_n}, starting run"

    run_output_tmp=$(mktemp)
    run_start=$(date +%s)
    $THUNDERDOME run --orchestrator "$orch" --trials 1 --parallel "$PARALLEL" 2>&1 | tee "$run_output_tmp"
    thunderdome_rc=${PIPESTATUS[0]}
    run_end=$(date +%s)
    run_duration=$((run_end - run_start))
    log "Run completed in ${run_duration}s (exit code: ${thunderdome_rc})"

    if [ "$thunderdome_rc" -eq 0 ]; then
      run_dir=$(grep -a 'Run directory:' "$run_output_tmp" | head -1 | sed 's/.*Run directory: //')
      rm -f "$run_output_tmp"

      if [ -n "$run_dir" ] && [ -d "$run_dir" ]; then
        log "Run dir: ${run_dir}"
        health_msg=$(check_run_health "$run_dir" "$orch")
        health_rc=$?
        log "$health_msg"
        if [ "$health_rc" -ne 0 ]; then
          log "Session exhausted. Waiting for full window reset..."
          sleep "$WINDOW_SECONDS"
          continue
        fi
      fi
      set_last_run_time
    else
      rm -f "$run_output_tmp"
      log "ERROR: thunderdome run failed. Pausing 5 minutes..."
      sleep 300
    fi

    sleep "$SLEEP_BETWEEN"
  done
done

log "=== Top-10 backfill complete ==="
for orch in "${ORCHESTRATORS[@]}"; do
  n=$(count_effective_n "$orch")
  log "  ${orch}: n=${n}"
done
