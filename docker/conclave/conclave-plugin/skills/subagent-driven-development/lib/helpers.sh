#!/usr/bin/env bash
# Helper functions for parallel-runner.sh

# Cleanup stale worktrees from previous runs
cleanup_stale_worktrees() {
    local worktree_dir="$1"
    if [ -d "$worktree_dir" ]; then
        git worktree prune 2>/dev/null || true
        for stale in "$worktree_dir"/task-*; do
            if [ -d "$stale" ]; then
                echo "WARNING: Removing stale worktree: $stale"
                git worktree remove "$stale" --force 2>/dev/null || rm -rf "$stale"
            fi
        done
    fi
}

# Setup environment in a worktree (install dependencies)
setup_worktree_env() {
    local worktree="$1"
    local project_root="$2"

    # Node.js: hardlink node_modules for speed
    if [ -f "$worktree/package.json" ] && [ -d "$project_root/node_modules" ]; then
        cp -al "$project_root/node_modules" "$worktree/node_modules" 2>/dev/null || true
        (cd "$worktree" && npm install --prefer-offline 2>/dev/null) || true
    fi

    # Rust
    if [ -f "$worktree/Cargo.toml" ]; then
        (cd "$worktree" && cargo build 2>/dev/null) || true
    fi

    # Python
    if [ -f "$worktree/requirements.txt" ]; then
        (cd "$worktree" && pip install -r requirements.txt 2>/dev/null) || true
    fi
    if [ -f "$worktree/pyproject.toml" ]; then
        (cd "$worktree" && pip install -e . 2>/dev/null) || true
    fi

    # Go
    if [ -f "$worktree/go.mod" ]; then
        (cd "$worktree" && go mod download 2>/dev/null) || true
    fi
}

# Get task name by ID (index lookup into TASK_NAMES)
get_task_name() {
    local target_id="$1"
    for ((i=0; i<${#TASK_IDS[@]}; i++)); do
        if [ "${TASK_IDS[$i]}" = "$target_id" ]; then
            echo "${TASK_NAMES[$i]}"
            return
        fi
    done
    echo "task-$target_id"
}

# Convert task name to slug for branch/directory names
slugify() {
    echo "$1" | tr '[:upper:]' '[:lower:]' | tr ' ' '-' | tr -cd 'a-z0-9-'
}
