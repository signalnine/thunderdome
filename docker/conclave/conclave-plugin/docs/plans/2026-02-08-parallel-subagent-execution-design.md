# Parallel Subagent Execution Design

**Date:** 2026-02-08
**Status:** Validated
**Designed via:** Consensus Autopilot (6 questions, all unanimous or near-unanimous)
**Validated via:** Multi-agent review (Claude, Gemini, Codex) - critical issues addressed

## Problem

`subagent-driven-development` runs tasks sequentially through ralph-loop. A 5-task plan takes 5x the time. The skill explicitly forbids parallel ralph-loops due to git conflicts. Independent tasks should run concurrently.

## Design Decisions (Consensus)

| # | Question | Decision | Confidence |
|---|----------|----------|------------|
| 1 | Isolation | Git worktrees per task | High |
| 2 | Parallelism | Batch-of-N, N=3-4 default | High |
| 3 | Merge | Batched sequential squash-merge in plan order | Medium-High |
| 4 | Locking | No lock in worktree mode, legacy lock for standalone | Medium |
| 5 | Architecture | Shell script (parallel-runner.sh) | High |
| 6 | Dependencies | Explicit + file-overlap safety net | High |

## Architecture

```
SKILL.md instructions
  └── parallel-runner.sh (new - manages worktrees, scheduling, merging)
        ├── ralph-runner.sh (task 1, worktree 1)
        ├── ralph-runner.sh (task 2, worktree 2)
        └── ralph-runner.sh (task 3, worktree 3)
              └── claude -p (implementation)
```

### Interface

```bash
parallel-runner.sh <plan-file> [options]
  --max-concurrent N    # Max parallel tasks (default: 3)
  --worktree-dir DIR    # Where to create worktrees (default: .worktrees)
  --base-branch BRANCH  # Branch to create worktrees from
  --non-interactive     # No prompts
```

## Execution Flow

Tasks execute in **waves** determined by the dependency graph. Each wave runs in parallel; waves execute sequentially. Dependent tasks branch from merged results of their predecessors.

```
parallel-runner.sh receives plan file
│
├── 1. PARSE: Extract tasks, dependencies, file lists from plan
│     ├── Build dependency DAG (explicit deps + file-overlap detection)
│     ├── Validate plan format (abort on missing fields or cycles)
│     └── Compute waves: group tasks by dependency depth
│
├── 2. SETUP
│     ├── Clean up orphaned worktrees from previous runs
│     ├── Create worktree directory, validate base branch
│     └── Verify .worktrees is in .gitignore
│
├── 3. EXECUTE WAVES
│     │
│     ├── Wave 1: Independent tasks (no dependencies)
│     │     ├── Create worktrees from BASE_BRANCH
│     │     ├── Launch up to N ralph-runner.sh in parallel
│     │     ├── Poll for completions (sleep 1 loop)
│     │     │     ├── Task succeeded (exit 0): mark complete, free slot
│     │     │     ├── Task failed (exit 1): mark failed, free slot
│     │     │     └── Fill open slots with remaining wave-1 tasks
│     │     └── When all wave-1 tasks done: MERGE wave-1 results
│     │
│     ├── Merge wave 1: squash-merge completed tasks in plan order
│     │     ├── On conflict: mark task for re-run (max 2 re-runs)
│     │     └── Re-run conflicted tasks sequentially against merged state
│     │
│     ├── Wave 2: Tasks whose dependencies are all in wave 1
│     │     ├── Create worktrees from MERGED STATE (not base branch)
│     │     ├── Launch up to N ralph-runner.sh in parallel
│     │     ├── Same polling/completion logic as wave 1
│     │     └── When all wave-2 tasks done: MERGE wave-2 results
│     │
│     └── Continue waves until all tasks executed or skipped
│
├── 4. REVIEW: Run consensus review on all merged changes
│
└── 5. CLEANUP: Remove worktrees, report summary
```

### Dependency Propagation (Critical)

Dependent tasks MUST have access to their predecessors' output. This is achieved by the wave model:

- **Wave 1** tasks branch from `BASE_BRANCH` (no dependencies)
- After wave 1, all completed work is squash-merged into the feature branch
- **Wave 2** tasks branch from the **merged feature branch** (includes wave 1's work)
- This continues per-wave, so each wave sees all prior waves' output

This ensures Task 3 (depends on Task 1) actually has Task 1's code in its worktree.

### Wave Computation

```bash
# Assign each task a depth based on its longest dependency chain
# depth 0 = no dependencies (wave 1)
# depth 1 = depends only on depth-0 tasks (wave 2)
# depth N = depends on tasks up to depth N-1 (wave N+1)
compute_waves() {
    for task in all_tasks; do
        if no_dependencies(task); then
            depth[task]=0
        else
            depth[task] = max(depth[dep] for dep in deps[task]) + 1
        fi
    done
    # Group tasks by depth into waves
}
```

## Plan Parsing & Dependency Graph

### Expected Plan Format

```markdown
## Task 1: Hook installation script
Files: src/hooks/install.sh (create), src/hooks/utils.sh (create)
Dependencies: none

## Task 2: Recovery modes
Files: src/recovery/modes.ts (create), src/recovery/index.ts (create)
Dependencies: none

## Task 3: CLI integration
Files: src/cli/main.ts (modify), src/hooks/install.sh (modify)
Dependencies: Task 1, Task 2
```

### Parsing Approach

- Line-based grep/awk - no complex markdown parsing
- `grep -E "^## Task [0-9]+"` to find task boundaries
- `grep -E "^Dependencies:"` and `grep -E "^Files:"` within each task block
- Store as simple arrays: `TASK_IDS`, `TASK_NAMES`, `TASK_DEPS[N]`, `TASK_FILES[N]`

### Format Validation

Before scheduling, validate the plan:
```bash
validate_plan() {
    # Every task has a "## Task N:" header
    # Every task has a "Files:" line (can be "Files: none")
    # Every task has a "Dependencies:" line (can be "Dependencies: none")
    # All referenced dependencies exist (e.g., "Task 1" refers to a real task)
    # No cycles in dependency graph
    # Abort with clear error message on any violation
}
```

### Dependency Graph Construction

1. Build explicit edges from `Dependencies:` field
2. Scan for file overlaps between tasks - if two tasks both list the same file, add an implicit edge (earlier task blocks later)
3. When file overlap creates an implicit dep, log a warning: `"WARNING: Tasks 1 and 3 both touch src/hooks/install.sh - serializing"`
4. Detect cycles (simple DFS) - abort with error if found

### Known Limitation: File Lists

Declared file lists may be incomplete. Subagents may touch files not listed in the plan. File-overlap detection catches declared overlaps only. Undeclared overlaps are caught at merge time (conflict) or by the post-merge consensus review.

### Ready-to-Run Check

```bash
task_is_ready() {
    # All explicit + implicit deps completed AND merged
    # No running task touches same files
    # Task is in the current wave
}
```

## Changes to ralph-runner.sh

Minimal - add `--worktree` flag:

- When `--worktree` is set, skip `acquire_lock` / `setup_lock_trap`
- Everything else unchanged (gates, stuck detection, failure branching)
- Standalone mode (no `--worktree`) keeps current locking behavior
- ~10-line diff

## Worktree & Merge Management

### Worktree Creation (per task)

```bash
# For wave 1 (independent tasks): branch from base
WORKTREE_PATH="$WORKTREE_DIR/task-$TASK_NUM-$TASK_SLUG"
git worktree add "$WORKTREE_PATH" -b "task/$TASK_NUM-$TASK_SLUG" "$BASE_BRANCH"

# For wave 2+ (dependent tasks): branch from current merged state
git worktree add "$WORKTREE_PATH" -b "task/$TASK_NUM-$TASK_SLUG" "$FEATURE_BRANCH"
```

### Environment Setup

After creating each worktree, auto-detect and install dependencies:

```bash
setup_worktree_env() {
    local worktree="$1"
    cd "$worktree"

    # Node.js: symlink node_modules from base for speed, then install
    if [ -f package.json ] && [ -d "$PROJECT_ROOT/node_modules" ]; then
        cp -al "$PROJECT_ROOT/node_modules" ./node_modules 2>/dev/null || true
        npm install 2>/dev/null || true
    fi

    # Other ecosystems: standard install
    if [ -f Cargo.toml ]; then cargo build 2>/dev/null || true; fi
    if [ -f requirements.txt ]; then pip install -r requirements.txt 2>/dev/null || true; fi
    if [ -f go.mod ]; then go mod download 2>/dev/null || true; fi
}
```

Note: `cp -al` creates hardlinks for node_modules, avoiding full copy. Falls back to regular install if hardlinks fail (e.g., cross-filesystem).

### Merge Phase (after each wave completes)

```bash
MAX_CONFLICT_RERUNS=2

merge_wave() {
    local conflict_tasks=()

    for task in plan_order_within_wave; do
        if task completed successfully; then
            git merge --squash "task/$N-$SLUG"
            if merge conflict; then
                git merge --abort
                conflict_tasks+=("$task")
            else
                git commit -m "Task $N: $TASK_NAME"
            fi
        fi
    done

    # Re-run conflicted tasks sequentially (capped)
    local rerun_count=0
    for task in conflict_tasks; do
        if [ $rerun_count -ge $MAX_CONFLICT_RERUNS ]; then
            echo "ERROR: Max conflict re-runs ($MAX_CONFLICT_RERUNS) exceeded"
            mark_task_failed "$task" "merge conflict after $MAX_CONFLICT_RERUNS re-runs"
            continue
        fi

        # Create fresh worktree from current merged state
        # Run ralph-runner.sh again with merged state as base
        # Attempt merge again
        rerun_count=$((rerun_count + 1))
    done
}
```

### Startup Cleanup

```bash
cleanup_stale() {
    # Remove orphaned worktrees from crashed previous runs
    if [ -d "$WORKTREE_DIR" ]; then
        git worktree prune
        for stale in "$WORKTREE_DIR"/task-*; do
            if [ -d "$stale" ]; then
                echo "WARNING: Removing stale worktree: $stale"
                git worktree remove "$stale" --force 2>/dev/null || rm -rf "$stale"
            fi
        done
    fi
}
```

### Final Cleanup

```bash
for worktree in "$WORKTREE_DIR"/task-*; do
    git worktree remove "$worktree" --force
done
git worktree prune
# Branches kept for audit trail (prunable later)
```

### Failure Handling

- ralph-loop already creates `wip/ralph-fail-*` branch on failure
- parallel-runner.sh records failure and frees the slot
- Failed tasks skipped in merge phase
- Dependency cascade: if task 1 fails, task 3 (depends on 1) marked `SKIPPED`
- Merge conflict after max re-runs: task marked `FAILED`

## SKILL.md Updates

### Process Section

Replace sequential ralph-loop calls with:
```bash
./skills/subagent-driven-development/parallel-runner.sh \
    "$PLAN_FILE" \
    --max-concurrent 3 \
    --worktree-dir "$WORKTREE_DIR" \
    --base-branch "$(git branch --show-current)" \
    --non-interactive
```

### Red Flags Section

- Remove: "Never run multiple ralph-loops in parallel (git conflicts)"
- Add: "Never run parallel-runner.sh without worktree isolation"
- Add: "Never merge task branches out of plan order"
- Add: "Never create dependent task worktrees from base branch (must use merged state)"

### Configuration

| Variable | Default | Description |
|----------|---------|-------------|
| `PARALLEL_MAX_CONCURRENT` | 3 | Max simultaneous tasks |
| `PARALLEL_WORKTREE_DIR` | .worktrees | Worktree location |
| `PARALLEL_MAX_CONFLICT_RERUNS` | 2 | Max re-runs for merge conflicts |

Sequential fallback: `--max-concurrent 1` degrades to current sequential behavior.

## File Summary

### New Files

| File | Purpose | ~Lines |
|------|---------|--------|
| `skills/subagent-driven-development/parallel-runner.sh` | Orchestrator: wave scheduling, worktree mgmt, merging | ~400 |
| `skills/subagent-driven-development/lib/parse-plan.sh` | Plan parsing, validation & dependency graph | ~150 |
| `skills/subagent-driven-development/lib/scheduler.sh` | Wave computation & batch-of-N scheduling | ~120 |
| `skills/subagent-driven-development/lib/merge.sh` | Squash-merge with conflict re-run handling | ~100 |

### Modified Files

| File | Change | ~Lines changed |
|------|--------|---------------|
| `skills/ralph-loop/ralph-runner.sh` | Add `--worktree` flag, skip lock when set | ~10 |
| `skills/subagent-driven-development/SKILL.md` | Update process to use parallel-runner.sh | ~40 |
| `skills/writing-plans/SKILL.md` | Document required `Files:` and `Dependencies:` fields | ~10 |

### Not Changed

- `consensus-synthesis.sh` - used as-is for post-merge review
- `auto-review.sh` - used as-is
- `ralph-loop` internals (gates, stuck detection, state, timeout) - untouched
- `using-git-worktrees` skill - parallel-runner.sh handles worktrees directly

**Total scope:** ~770 new lines, ~60 modified lines across 7 files.
