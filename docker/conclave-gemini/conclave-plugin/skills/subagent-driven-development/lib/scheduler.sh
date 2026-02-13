#!/usr/bin/env bash
# Wave-based batch-of-N scheduler for parallel-runner.sh
# Manages task lifecycle: PENDING → RUNNING → COMPLETED/FAILED/SKIPPED

SCHED_MAX_CONCURRENT=3
SCHED_ACTIVE_COUNT=0
declare -A SCHED_TASK_STATUS=()
declare -A SCHED_TASK_PID=()
declare -A SCHED_TASK_WORKTREE=()

init_scheduler() {
    local max_concurrent="${1:-3}"
    SCHED_MAX_CONCURRENT=$max_concurrent
    SCHED_ACTIVE_COUNT=0
    SCHED_TASK_STATUS=()
    SCHED_TASK_PID=()
    SCHED_TASK_WORKTREE=()
    for id in "${TASK_IDS[@]}"; do
        SCHED_TASK_STATUS[$id]="PENDING"
    done
}

get_ready_tasks() {
    local wave="$1"
    local ready=""
    for id in "${TASK_IDS[@]}"; do
        [ "${SCHED_TASK_STATUS[$id]}" != "PENDING" ] && continue
        [ "${TASK_WAVE[$id]}" != "$wave" ] && continue
        local deps="${TASK_DEPS[$id]}"
        local deps_met=true
        if [ "$deps" != "none" ] && [ -n "$deps" ]; then
            for dep_id in $deps; do
                if [ "${SCHED_TASK_STATUS[$dep_id]}" != "COMPLETED" ]; then
                    deps_met=false
                    break
                fi
            done
        fi
        if $deps_met; then
            ready="${ready:+$ready }$id"
        fi
    done
    echo "$ready"
}

can_launch() {
    [ "$SCHED_ACTIVE_COUNT" -lt "$SCHED_MAX_CONCURRENT" ]
}

mark_task_running() {
    local task_id="$1"
    local pid="$2"
    local worktree="${3:-}"
    SCHED_TASK_STATUS[$task_id]="RUNNING"
    SCHED_TASK_PID[$task_id]="$pid"
    SCHED_TASK_WORKTREE[$task_id]="$worktree"
    SCHED_ACTIVE_COUNT=$((SCHED_ACTIVE_COUNT + 1))
}

mark_task_done() {
    local task_id="$1"
    local status="$2"
    SCHED_TASK_STATUS[$task_id]="$status"
    SCHED_ACTIVE_COUNT=$((SCHED_ACTIVE_COUNT - 1))
    [ "$SCHED_ACTIVE_COUNT" -lt 0 ] && SCHED_ACTIVE_COUNT=0
    if [ "$status" = "FAILED" ]; then
        _cascade_skip "$task_id"
    fi
}

_cascade_skip() {
    local failed_id="$1"
    for id in "${TASK_IDS[@]}"; do
        [ "${SCHED_TASK_STATUS[$id]}" != "PENDING" ] && continue
        local deps="${TASK_DEPS[$id]}"
        [ "$deps" = "none" ] && continue
        [ -z "$deps" ] && continue
        for dep_id in $deps; do
            if [ "$dep_id" = "$failed_id" ] || [ "${SCHED_TASK_STATUS[$dep_id]}" = "SKIPPED" ]; then
                SCHED_TASK_STATUS[$id]="SKIPPED"
                echo "[SCHEDULER] Task $id SKIPPED (dependency Task $dep_id failed/skipped)"
                _cascade_skip "$id"
                break
            fi
        done
    done
}

has_running_tasks() {
    [ "$SCHED_ACTIVE_COUNT" -gt 0 ]
}

wave_complete() {
    local wave="$1"
    for id in "${TASK_IDS[@]}"; do
        [ "${TASK_WAVE[$id]}" != "$wave" ] && continue
        local status="${SCHED_TASK_STATUS[$id]}"
        if [ "$status" = "PENDING" ] || [ "$status" = "RUNNING" ]; then
            return 1
        fi
    done
    return 0
}

get_wave_completed() {
    local wave="$1"
    local result=""
    for id in "${TASK_IDS[@]}"; do
        [ "${TASK_WAVE[$id]}" != "$wave" ] && continue
        [ "${SCHED_TASK_STATUS[$id]}" != "COMPLETED" ] && continue
        result="${result:+$result }$id"
    done
    echo "$result"
}

print_summary() {
    local completed=0 failed=0 skipped=0
    for id in "${TASK_IDS[@]}"; do
        case "${SCHED_TASK_STATUS[$id]}" in
            COMPLETED) completed=$((completed + 1)) ;;
            FAILED)    failed=$((failed + 1)) ;;
            SKIPPED)   skipped=$((skipped + 1)) ;;
        esac
    done
    echo ""
    echo "========================================"
    echo "PARALLEL EXECUTION SUMMARY"
    echo "========================================"
    echo "  Completed: $completed/${#TASK_IDS[@]}"
    echo "  Failed:    $failed"
    echo "  Skipped:   $skipped"
    echo "========================================"
}
