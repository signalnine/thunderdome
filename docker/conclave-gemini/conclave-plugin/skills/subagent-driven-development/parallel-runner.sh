#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
RALPH_DIR="$(cd "$SCRIPT_DIR/../ralph-loop" && pwd)"

# Source libraries
source "$SCRIPT_DIR/lib/parse-plan.sh"
source "$SCRIPT_DIR/lib/scheduler.sh"
source "$SCRIPT_DIR/lib/merge.sh"
source "$SCRIPT_DIR/lib/helpers.sh"

#############################################
# Usage
#############################################

usage() {
    cat << EOF
Usage: parallel-runner.sh <plan-file> [options]

Parallel task execution via git worktrees and ralph-loop.

Arguments:
  plan-file           Path to implementation plan markdown file

Options:
  --max-concurrent N  Max parallel tasks (default: 3)
  --worktree-dir DIR  Where to create worktrees (default: .worktrees)
  --base-branch BR    Branch to create worktrees from (default: current)
  --non-interactive   No prompts
  --dry-run           Parse plan and show schedule, don't execute
  -h, --help          Show this help

Environment:
  PARALLEL_MAX_CONCURRENT       Max concurrent tasks (default: 3)
  PARALLEL_WORKTREE_DIR         Worktree directory (default: .worktrees)
  PARALLEL_MAX_CONFLICT_RERUNS  Max merge conflict re-runs (default: 2)
EOF
}

#############################################
# Argument Parsing
#############################################

PLAN_FILE=""
MAX_CONCURRENT="${PARALLEL_MAX_CONCURRENT:-3}"
WORKTREE_DIR="${PARALLEL_WORKTREE_DIR:-.worktrees}"
BASE_BRANCH=""
NON_INTERACTIVE=false
DRY_RUN=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --max-concurrent) MAX_CONCURRENT="$2"; shift 2 ;;
        --worktree-dir) WORKTREE_DIR="$2"; shift 2 ;;
        --base-branch) BASE_BRANCH="$2"; shift 2 ;;
        --non-interactive) NON_INTERACTIVE=true; shift ;;
        --dry-run) DRY_RUN=true; shift ;;
        -h|--help) usage; exit 0 ;;
        -*) echo "Unknown option: $1" >&2; usage; exit 1 ;;
        *)
            if [ -z "$PLAN_FILE" ]; then
                PLAN_FILE="$1"
            fi
            shift
            ;;
    esac
done

[ -z "$PLAN_FILE" ] && { echo "ERROR: Plan file required" >&2; usage; exit 1; }
[ ! -f "$PLAN_FILE" ] && { echo "ERROR: Plan file not found: $PLAN_FILE" >&2; exit 1; }

# Default base branch to current
if [ -z "$BASE_BRANCH" ]; then
    BASE_BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "main")
fi
FEATURE_BRANCH="$BASE_BRANCH"

# Safety: refuse to merge into main/master
if [ "$FEATURE_BRANCH" = "main" ] || [ "$FEATURE_BRANCH" = "master" ]; then
    echo "ERROR: Refusing to run parallel execution on protected branch '$FEATURE_BRANCH'" >&2
    echo "Create a feature branch first: git checkout -b feature/my-feature" >&2
    exit 1
fi

PROJECT_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)

echo "========================================"
echo "Parallel Runner"
echo "Plan: $PLAN_FILE"
echo "Max concurrent: $MAX_CONCURRENT"
echo "Worktree dir: $WORKTREE_DIR"
echo "Base branch: $BASE_BRANCH"
echo "========================================"

#############################################
# Phase 1: Parse Plan
#############################################

echo ""
echo "--- Phase 1: Parsing Plan ---"

if ! validate_plan "$PLAN_FILE"; then
    echo "ERROR: Plan validation failed" >&2
    exit 1
fi

# Re-parse after validation (validate_plan calls parse_tasks internally)
parse_tasks "$PLAN_FILE"
detect_file_overlaps 2>/dev/null || true
compute_waves

echo "Tasks found: ${#TASK_IDS[@]}"
echo "Waves: $((MAX_WAVE + 1))"
for ((w=0; w<=MAX_WAVE; w++)); do
    wave_tasks=$(get_wave_tasks $w)
    echo "  Wave $w: tasks $wave_tasks"
done

#############################################
# Dry Run Exit
#############################################

if [ "$DRY_RUN" = true ]; then
    echo ""
    echo "Dry run complete. Exiting."
    exit 0
fi

#############################################
# Phase 2: Setup
#############################################

echo ""
echo "--- Phase 2: Setup ---"

cleanup_stale_worktrees "$WORKTREE_DIR"
mkdir -p "$WORKTREE_DIR"

# Verify worktree dir is gitignored (for project-local dirs)
if [[ "$WORKTREE_DIR" != /* ]] && [[ "$WORKTREE_DIR" != ~* ]]; then
    if ! git check-ignore -q "$WORKTREE_DIR" 2>/dev/null; then
        echo "Adding $WORKTREE_DIR to .gitignore"
        echo "$WORKTREE_DIR" >> .gitignore
        git add .gitignore
        git commit -q -m "chore: add $WORKTREE_DIR to .gitignore"
    fi
fi

init_scheduler "$MAX_CONCURRENT"

#############################################
# Phase 3: Execute Waves
#############################################

echo ""
echo "--- Phase 3: Executing Waves ---"

GLOBAL_START=$(date +%s)

# Cleanup trap for worktrees on exit
cleanup_on_exit() {
    echo ""
    echo "--- Cleanup (exit trap) ---"
    # Kill any running task processes
    for id in "${TASK_IDS[@]}"; do
        if [ "${SCHED_TASK_STATUS[$id]}" = "RUNNING" ]; then
            local pid="${SCHED_TASK_PID[$id]}"
            kill "$pid" 2>/dev/null || true
            kill -9 "$pid" 2>/dev/null || true
        fi
    done
    # Remove worktrees
    for wt in "$WORKTREE_DIR"/task-*; do
        if [ -d "$wt" ]; then
            git worktree remove "$wt" --force 2>/dev/null || rm -rf "$wt" 2>/dev/null || true
        fi
    done
    git worktree prune 2>/dev/null || true
}
trap cleanup_on_exit EXIT

for ((wave=0; wave<=MAX_WAVE; wave++)); do
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "Wave $wave"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    # Launch and monitor tasks in this wave
    while ! wave_complete $wave; do
        # Launch ready tasks if slots available
        ready_tasks=$(get_ready_tasks $wave)
        for task_id in $ready_tasks; do
            if ! can_launch; then
                break
            fi

            local_task_name=$(get_task_name "$task_id")
            local_slug=$(slugify "$local_task_name")
            local_wt_path="$WORKTREE_DIR/task-${task_id}-${local_slug}"
            local_branch_name="task/${task_id}-${local_slug}"

            echo "[WAVE $wave] Launching Task $task_id: $local_task_name"

            # Create worktree from current feature branch (includes prior waves' merges)
            if ! git worktree add "$local_wt_path" -b "$local_branch_name" "$FEATURE_BRANCH" 2>/dev/null; then
                echo "ERROR: Failed to create worktree for task $task_id" >&2
                mark_task_done "$task_id" "FAILED"
                continue
            fi

            setup_worktree_env "$local_wt_path" "$PROJECT_ROOT"

            # Write task spec to temp file
            local_task_spec=$(mktemp --suffix=.md)
            extract_task_spec "$PLAN_FILE" "$task_id" > "$local_task_spec"

            # Launch ralph-runner.sh in background
            (
                cd "$local_wt_path"
                "$RALPH_DIR/ralph-runner.sh" \
                    "task-${task_id}-${local_slug}" \
                    "$local_task_spec" \
                    --worktree \
                    --non-interactive \
                    -d "$local_wt_path"
            ) > "$local_wt_path/.ralph-output.log" 2>&1 &
            local_pid=$!

            mark_task_running "$task_id" "$local_pid" "$local_wt_path"
        done

        # Poll running tasks for completion
        for task_id in "${TASK_IDS[@]}"; do
            [ "${SCHED_TASK_STATUS[$task_id]}" != "RUNNING" ] && continue

            local pid="${SCHED_TASK_PID[$task_id]}"
            if ! kill -0 "$pid" 2>/dev/null; then
                wait "$pid" 2>/dev/null
                local_exit=$?

                if [ $local_exit -eq 0 ]; then
                    echo "[WAVE $wave] Task $task_id COMPLETED"
                    mark_task_done "$task_id" "COMPLETED"
                else
                    echo "[WAVE $wave] Task $task_id FAILED (exit $local_exit)"
                    mark_task_done "$task_id" "FAILED"
                fi
            fi
        done

        # Don't spin too fast
        sleep 1
    done

    # --- MERGE wave results ---
    echo ""
    echo "[WAVE $wave] Merging completed tasks..."

    completed_ids=$(get_wave_completed $wave)
    if [ -n "$completed_ids" ]; then
        for task_id in $completed_ids; do
            local_task_name=$(get_task_name "$task_id")
            local_slug=$(slugify "$local_task_name")
            local_branch="task/${task_id}-${local_slug}"

            if ! merge_task_branch "$local_branch" "$task_id" "$local_task_name"; then
                echo "[WAVE $wave] CONFLICT: Task $task_id needs re-run"

                local_rerun=0
                local_merged=false
                while [ $local_rerun -lt $MAX_CONFLICT_RERUNS ] && [ "$local_merged" = false ]; do
                    local_rerun=$((local_rerun + 1))
                    echo "[WAVE $wave] Re-running Task $task_id (attempt $local_rerun/$MAX_CONFLICT_RERUNS)"

                    local_rr_path="$WORKTREE_DIR/task-${task_id}-${local_slug}-rerun-${local_rerun}"
                    local_rr_branch="task/${task_id}-${local_slug}-rerun-${local_rerun}"

                    if ! git worktree add "$local_rr_path" -b "$local_rr_branch" "$FEATURE_BRANCH" 2>/dev/null; then
                        echo "ERROR: Failed to create re-run worktree" >&2
                        break
                    fi
                    setup_worktree_env "$local_rr_path" "$PROJECT_ROOT"

                    local_rr_spec=$(mktemp --suffix=.md)
                    extract_task_spec "$PLAN_FILE" "$task_id" > "$local_rr_spec"

                    # Run synchronously for re-runs
                    (
                        cd "$local_rr_path"
                        "$RALPH_DIR/ralph-runner.sh" \
                            "task-${task_id}-${local_slug}-rerun" \
                            "$local_rr_spec" \
                            --worktree \
                            --non-interactive \
                            -d "$local_rr_path"
                    ) > "$local_rr_path/.ralph-output.log" 2>&1 || true

                    if merge_task_branch "$local_rr_branch" "$task_id" "$local_task_name"; then
                        local_merged=true
                        echo "[WAVE $wave] Re-run merge succeeded for Task $task_id"
                    fi
                done

                if [ "$local_merged" = false ]; then
                    echo "[WAVE $wave] Task $task_id FAILED after $MAX_CONFLICT_RERUNS re-runs"
                    SCHED_TASK_STATUS[$task_id]="FAILED"
                    _cascade_skip "$task_id"
                fi
            fi
        done
    else
        echo "[WAVE $wave] No tasks completed in this wave"
    fi
done

#############################################
# Phase 4: Consensus Review
#############################################

echo ""
echo "--- Phase 4: Consensus Review ---"

completed_count=0
for id in "${TASK_IDS[@]}"; do
    [ "${SCHED_TASK_STATUS[$id]}" = "COMPLETED" ] && completed_count=$((completed_count + 1))
done

if [ $completed_count -gt 0 ]; then
    if [ -f "$SCRIPT_DIR/../multi-agent-consensus/auto-review.sh" ]; then
        echo "Running consensus review on all merged changes..."
        "$SCRIPT_DIR/../multi-agent-consensus/auto-review.sh" \
            "Parallel execution: $completed_count tasks from $(basename "$PLAN_FILE")" || true
    else
        echo "WARNING: auto-review.sh not found, skipping consensus review"
    fi
else
    echo "No completed tasks to review"
fi

#############################################
# Phase 5: Cleanup & Summary
#############################################

# Cleanup is handled by EXIT trap, but print summary here
print_summary

# Report details for failed/skipped tasks
for id in "${TASK_IDS[@]}"; do
    if [ "${SCHED_TASK_STATUS[$id]}" = "FAILED" ]; then
        echo "  Task $id ($(get_task_name "$id")): FAILED - check wip/ralph-fail-* branches"
    fi
    if [ "${SCHED_TASK_STATUS[$id]}" = "SKIPPED" ]; then
        echo "  Task $id ($(get_task_name "$id")): SKIPPED (dependency failed)"
    fi
done

# Exit with error if any tasks failed
has_failures=false
for id in "${TASK_IDS[@]}"; do
    if [ "${SCHED_TASK_STATUS[$id]}" = "FAILED" ]; then
        has_failures=true
        break
    fi
done

if [ "$has_failures" = true ]; then
    exit 1
fi
exit 0
