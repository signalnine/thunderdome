#!/usr/bin/env bash
# Merge management for parallel-runner.sh
# Handles squash-merging task branches in plan order with conflict detection

MAX_CONFLICT_RERUNS="${PARALLEL_MAX_CONFLICT_RERUNS:-2}"

# Squash-merge a task branch into the current branch
# Returns 0 on success, 1 on conflict (merge is aborted)
merge_task_branch() {
    local branch="$1"
    local task_id="$2"
    local task_name="$3"

    echo "[MERGE] Squash-merging $branch..."

    if git merge --squash "$branch" 2>/dev/null; then
        # Check if there are changes to commit
        if git diff --cached --quiet 2>/dev/null; then
            echo "[MERGE] No changes to merge from $branch"
            return 0
        fi
        git commit -m "Task $task_id: $task_name" 2>/dev/null
        echo "[MERGE] Successfully merged $branch"
        return 0
    else
        echo "[MERGE] CONFLICT in $branch - aborting merge"
        git merge --abort 2>/dev/null || git reset --hard HEAD 2>/dev/null
        return 1
    fi
}
