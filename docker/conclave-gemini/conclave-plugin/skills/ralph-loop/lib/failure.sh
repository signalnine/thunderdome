#!/usr/bin/env bash
# Failure handling for Ralph Loop

branch_failed_work() {
    local task_id="$1"
    local state_file="${2:-.ralph_state.json}"
    local timestamp=$(date +%Y%m%d-%H%M%S)
    local branch_name="wip/ralph-fail-${task_id}-${timestamp}"
    local working_branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null)

    if [ -z "$working_branch" ]; then
        echo "ERROR: Not in a git repository" >&2
        return 1
    fi

    echo "Creating failure branch: $branch_name"

    # Safety check: ensure we're not on main/master
    if [ "$working_branch" = "main" ] || [ "$working_branch" = "master" ]; then
        echo "WARNING: On protected branch $working_branch, creating branch without reset"
        git checkout -b "$branch_name"
        git add -A
        git commit -m "Ralph Loop failed: ${task_id} (on $working_branch)" --allow-empty || true
        git checkout "$working_branch"
        echo "Failed work preserved in branch: $branch_name"
        return 0
    fi

    # Safety check: verify clean-ish state before destructive operations
    local uncommitted=$(git status --porcelain 2>/dev/null | wc -l)

    # Create failure branch from current state
    git checkout -b "$branch_name" 2>/dev/null || {
        # Branch might exist, add timestamp suffix
        branch_name="${branch_name}-$(date +%s)"
        git checkout -b "$branch_name"
    }

    # Stage and commit everything
    git add -A
    local iter=$(jq -r '.iteration' "$state_file" 2>/dev/null || echo "?")
    local max_iter=$(jq -r '.max_iterations' "$state_file" 2>/dev/null || echo "?")
    local last_gate=$(jq -r '.last_gate' "$state_file" 2>/dev/null || echo "?")
    local error_hash=$(jq -r '.error_hash' "$state_file" 2>/dev/null || echo "?")

    git commit -m "Ralph Loop failed: ${task_id}

Iterations: ${iter}/${max_iter}
Last gate: ${last_gate}
Error hash: ${error_hash}

See .ralph_state.json and .ralph_context.md for details" --allow-empty

    # Try to push (non-fatal if no remote)
    git push -u origin "$branch_name" 2>/dev/null || true

    # Return to working branch
    git checkout "$working_branch" 2>/dev/null || git checkout -

    echo "Failed work preserved in branch: $branch_name"
    echo "To review: git checkout $branch_name"
}
