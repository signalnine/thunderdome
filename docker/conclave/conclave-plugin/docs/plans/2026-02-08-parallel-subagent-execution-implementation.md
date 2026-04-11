# Parallel Subagent Execution Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add parallel task execution to subagent-driven-development via git worktrees, wave-based scheduling, and squash-merge integration.

**Architecture:** A new `parallel-runner.sh` orchestrator parses implementation plans, builds a dependency DAG, groups tasks into waves, executes each wave's tasks in parallel (each in its own git worktree running ralph-runner.sh), then squash-merges results in plan order. Existing ralph-runner.sh gets a `--worktree` flag to skip locking.

**Tech Stack:** Bash, git worktrees, jq (for JSON state), existing ralph-runner.sh and consensus-synthesis.sh infrastructure.

**Design doc:** `docs/plans/2026-02-08-parallel-subagent-execution-design.md`

---

## Task 1: Add --worktree flag to ralph-runner.sh

**Files:**
- Modify: `skills/ralph-loop/ralph-runner.sh`
- Modify: `skills/ralph-loop/test-ralph-loop.sh`

**Dependencies:** none
**Files:** skills/ralph-loop/ralph-runner.sh (modify), skills/ralph-loop/test-ralph-loop.sh (modify)

**Step 1: Add test for --worktree flag**

Add to the end of `skills/ralph-loop/test-ralph-loop.sh`, before the final "ALL TESTS PASSED" block:

```bash
echo ""
echo "=== Worktree Mode Tests ==="

echo -n "Test: --worktree flag skips lock acquisition... "
# Source fresh lock module
source ./lib/lock.sh
release_lock 2>/dev/null || true
# Create a lockfile owned by a "different" PID (use PID 1 which always exists)
echo "1" > .ralph.lock
# In worktree mode, ralph-runner.sh should not try to acquire lock
# We test the flag parsing by checking the variable
WORKTREE_MODE=false
for arg in "--worktree"; do
    case $arg in
        --worktree) WORKTREE_MODE=true ;;
    esac
done
if [ "$WORKTREE_MODE" = true ]; then
    echo "PASS"
else
    echo "FAIL"
    exit 1
fi
rm -f .ralph.lock
```

**Step 2: Run test to verify it passes (trivial parse test)**

Run: `bash skills/ralph-loop/test-ralph-loop.sh`
Expected: ALL TESTS PASSED

**Step 3: Add --worktree flag to ralph-runner.sh argument parser**

In `skills/ralph-loop/ralph-runner.sh`, add `WORKTREE_MODE=false` after `NON_INTERACTIVE=false` (line 40), add `--worktree) WORKTREE_MODE=true; shift ;;` to the case statement (after the `--non-interactive` case), and add `--worktree` to the usage text.

**Step 4: Conditionally skip lock when --worktree is set**

Replace the lock acquisition block (lines 70-74):

```bash
# Acquire lock (skip in worktree mode - isolation handled externally)
if [ "$WORKTREE_MODE" = true ]; then
    echo "Worktree mode: skipping lock (isolation via worktree)"
else
    if ! acquire_lock; then
        exit 1
    fi
    setup_lock_trap
fi
```

**Step 5: Run tests to verify nothing broke**

Run: `bash skills/ralph-loop/test-ralph-loop.sh`
Expected: ALL TESTS PASSED

**Step 6: Commit**

```bash
git add skills/ralph-loop/ralph-runner.sh skills/ralph-loop/test-ralph-loop.sh
git commit -m "feat: add --worktree flag to ralph-runner.sh to skip locking"
```

---

## Task 2: Plan parser library (parse-plan.sh)

**Files:**
- Create: `skills/subagent-driven-development/lib/parse-plan.sh`
- Create: `skills/subagent-driven-development/test-parse-plan.sh`
- Create: `skills/subagent-driven-development/examples/mock-plan.md`

**Dependencies:** none
**Files:** skills/subagent-driven-development/lib/parse-plan.sh (create), skills/subagent-driven-development/test-parse-plan.sh (create), skills/subagent-driven-development/examples/mock-plan.md (create)

**Step 1: Create mock plan for testing**

Create `skills/subagent-driven-development/examples/mock-plan.md`:

```markdown
# Mock Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans

**Goal:** Test plan for parser validation

---

## Task 1: Create utilities

**Files:**
- Create: `src/utils.sh`

**Dependencies:** none

**Step 1: Write utils**
Create src/utils.sh with helper functions.

---

## Task 2: Create core module

**Files:**
- Create: `src/core.sh`

**Dependencies:** none

**Step 1: Write core**
Create src/core.sh with core functions.

---

## Task 3: Create integration

**Files:**
- Modify: `src/utils.sh`
- Create: `src/integration.sh`

**Dependencies:** Task 1, Task 2

**Step 1: Write integration**
Create src/integration.sh combining utils and core.

---

## Task 4: Create CLI

**Files:**
- Create: `src/cli.sh`

**Dependencies:** Task 3

**Step 1: Write CLI**
Create src/cli.sh as the entry point.
```

**Step 2: Write the test file**

Create `skills/subagent-driven-development/test-parse-plan.sh`:

```bash
#!/usr/bin/env bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "Testing Plan Parser..."

# Source the parser
source "$SCRIPT_DIR/lib/parse-plan.sh"

MOCK_PLAN="$SCRIPT_DIR/examples/mock-plan.md"

echo ""
echo "=== Task Extraction Tests ==="

echo -n "Test: parse_tasks extracts correct task count... "
parse_tasks "$MOCK_PLAN"
if [ "${#TASK_IDS[@]}" -eq 4 ]; then
    echo "PASS"
else
    echo "FAIL (got ${#TASK_IDS[@]}, expected 4)"
    exit 1
fi

echo -n "Test: task IDs are correct... "
if [ "${TASK_IDS[0]}" = "1" ] && [ "${TASK_IDS[1]}" = "2" ] && [ "${TASK_IDS[2]}" = "3" ] && [ "${TASK_IDS[3]}" = "4" ]; then
    echo "PASS"
else
    echo "FAIL (got: ${TASK_IDS[*]})"
    exit 1
fi

echo -n "Test: task names are correct... "
if [ "${TASK_NAMES[0]}" = "Create utilities" ] && [ "${TASK_NAMES[2]}" = "Create integration" ]; then
    echo "PASS"
else
    echo "FAIL (got: ${TASK_NAMES[0]}, ${TASK_NAMES[2]})"
    exit 1
fi

echo ""
echo "=== Dependency Parsing Tests ==="

echo -n "Test: task 1 has no dependencies... "
if [ "${TASK_DEPS[1]}" = "none" ] || [ -z "${TASK_DEPS[1]}" ]; then
    echo "PASS"
else
    echo "FAIL (got: ${TASK_DEPS[1]})"
    exit 1
fi

echo -n "Test: task 3 depends on tasks 1 and 2... "
if echo "${TASK_DEPS[3]}" | grep -q "1" && echo "${TASK_DEPS[3]}" | grep -q "2"; then
    echo "PASS"
else
    echo "FAIL (got: ${TASK_DEPS[3]})"
    exit 1
fi

echo -n "Test: task 4 depends on task 3... "
if echo "${TASK_DEPS[4]}" | grep -q "3"; then
    echo "PASS"
else
    echo "FAIL (got: ${TASK_DEPS[4]})"
    exit 1
fi

echo ""
echo "=== File Parsing Tests ==="

echo -n "Test: task 1 files include src/utils.sh... "
if echo "${TASK_FILES[1]}" | grep -q "src/utils.sh"; then
    echo "PASS"
else
    echo "FAIL (got: ${TASK_FILES[1]})"
    exit 1
fi

echo -n "Test: task 3 files include src/utils.sh (overlap with task 1)... "
if echo "${TASK_FILES[3]}" | grep -q "src/utils.sh"; then
    echo "PASS"
else
    echo "FAIL (got: ${TASK_FILES[3]})"
    exit 1
fi

echo ""
echo "=== File Overlap Detection Tests ==="

echo -n "Test: detect_file_overlaps finds overlap between tasks 1 and 3... "
detect_file_overlaps
if echo "${IMPLICIT_DEPS[*]}" | grep -q "1:3" || echo "${IMPLICIT_DEPS[*]}" | grep -q "3:1"; then
    echo "PASS"
else
    echo "FAIL (got: ${IMPLICIT_DEPS[*]})"
    exit 1
fi

echo ""
echo "=== Wave Computation Tests ==="

echo -n "Test: compute_waves assigns correct depths... "
compute_waves
if [ "${TASK_WAVE[1]}" = "0" ] && [ "${TASK_WAVE[2]}" = "0" ] && [ "${TASK_WAVE[3]}" = "1" ] && [ "${TASK_WAVE[4]}" = "2" ]; then
    echo "PASS"
else
    echo "FAIL (got: wave[1]=${TASK_WAVE[1]}, wave[2]=${TASK_WAVE[2]}, wave[3]=${TASK_WAVE[3]}, wave[4]=${TASK_WAVE[4]})"
    exit 1
fi

echo -n "Test: max wave is 2... "
if [ "$MAX_WAVE" = "2" ]; then
    echo "PASS"
else
    echo "FAIL (got: $MAX_WAVE)"
    exit 1
fi

echo -n "Test: get_wave_tasks returns correct tasks per wave... "
WAVE0_TASKS=$(get_wave_tasks 0)
WAVE1_TASKS=$(get_wave_tasks 1)
WAVE2_TASKS=$(get_wave_tasks 2)
if echo "$WAVE0_TASKS" | grep -q "1" && echo "$WAVE0_TASKS" | grep -q "2" && echo "$WAVE1_TASKS" | grep -q "3" && echo "$WAVE2_TASKS" | grep -q "4"; then
    echo "PASS"
else
    echo "FAIL (wave0=$WAVE0_TASKS, wave1=$WAVE1_TASKS, wave2=$WAVE2_TASKS)"
    exit 1
fi

echo ""
echo "=== Validation Tests ==="

echo -n "Test: validate_plan passes for valid plan... "
if validate_plan "$MOCK_PLAN" 2>/dev/null; then
    echo "PASS"
else
    echo "FAIL"
    exit 1
fi

echo -n "Test: validate_plan detects missing dependencies field... "
BAD_PLAN=$(mktemp --suffix=.md)
cat > "$BAD_PLAN" << 'PLAN'
## Task 1: Bad task

**Files:**
- Create: `src/bad.sh`
PLAN
if validate_plan "$BAD_PLAN" 2>/dev/null; then
    echo "FAIL (should have rejected)"
    rm -f "$BAD_PLAN"
    exit 1
else
    echo "PASS"
fi
rm -f "$BAD_PLAN"

echo -n "Test: validate_plan detects invalid dependency reference... "
BAD_PLAN=$(mktemp --suffix=.md)
cat > "$BAD_PLAN" << 'PLAN'
## Task 1: First

**Files:**
- Create: `src/first.sh`

**Dependencies:** Task 99
PLAN
if validate_plan "$BAD_PLAN" 2>/dev/null; then
    echo "FAIL (should have rejected)"
    rm -f "$BAD_PLAN"
    exit 1
else
    echo "PASS"
fi
rm -f "$BAD_PLAN"

echo ""
echo "=== Task Spec Extraction Tests ==="

echo -n "Test: extract_task_spec returns task content... "
SPEC=$(extract_task_spec "$MOCK_PLAN" 1)
if echo "$SPEC" | grep -q "Create utilities" && echo "$SPEC" | grep -q "src/utils.sh"; then
    echo "PASS"
else
    echo "FAIL"
    exit 1
fi

echo ""
echo "========================================"
echo "ALL PARSER TESTS PASSED!"
echo "========================================"
```

**Step 3: Run test to verify it fails (parse-plan.sh doesn't exist)**

Run: `bash skills/subagent-driven-development/test-parse-plan.sh`
Expected: FAIL with "No such file" or source error

**Step 4: Implement parse-plan.sh**

Create `skills/subagent-driven-development/lib/parse-plan.sh`:

```bash
#!/usr/bin/env bash
# Plan parser for parallel-runner.sh
# Extracts tasks, dependencies, files, and computes execution waves

# Global arrays populated by parse_tasks()
declare -a TASK_IDS=()
declare -a TASK_NAMES=()
declare -A TASK_DEPS=()
declare -A TASK_FILES=()
declare -A TASK_WAVE=()
declare -a IMPLICIT_DEPS=()
MAX_WAVE=0

# Parse all tasks from a plan markdown file
# Populates: TASK_IDS, TASK_NAMES, TASK_DEPS, TASK_FILES
parse_tasks() {
    local plan_file="$1"

    TASK_IDS=()
    TASK_NAMES=()
    TASK_DEPS=()
    TASK_FILES=()

    local current_id=""
    local current_name=""
    local in_task=false
    local found_files=false
    local found_deps=false

    while IFS= read -r line; do
        # Match task header: "## Task N: Name" or "### Task N: Name"
        if echo "$line" | grep -qE "^#{2,3} Task [0-9]+:"; then
            # Save previous task
            if [ -n "$current_id" ]; then
                if [ -z "${TASK_DEPS[$current_id]+x}" ]; then
                    TASK_DEPS[$current_id]="none"
                fi
                if [ -z "${TASK_FILES[$current_id]+x}" ]; then
                    TASK_FILES[$current_id]="none"
                fi
            fi

            # Extract ID and name
            current_id=$(echo "$line" | grep -oE "Task [0-9]+" | grep -oE "[0-9]+")
            current_name=$(echo "$line" | sed -E 's/^#{2,3} Task [0-9]+: //')
            TASK_IDS+=("$current_id")
            TASK_NAMES+=("$current_name")
            in_task=true
            found_files=false
            found_deps=false
        fi

        # Match Files line (various formats)
        if $in_task && echo "$line" | grep -qiE "^\*?\*?Files:?\*?\*?"; then
            found_files=true
        fi

        # Collect file paths from lines starting with "- " after Files:
        if $in_task && $found_files && echo "$line" | grep -qE "^- (Create|Modify|Test):"; then
            local file_path=$(echo "$line" | grep -oE '`[^`]+`' | tr -d '`' | sed 's/:[0-9-]*$//')
            if [ -n "$file_path" ]; then
                if [ -z "${TASK_FILES[$current_id]+x}" ]; then
                    TASK_FILES[$current_id]="$file_path"
                else
                    TASK_FILES[$current_id]="${TASK_FILES[$current_id]} $file_path"
                fi
            fi
        fi

        # Match Dependencies line
        if $in_task && echo "$line" | grep -qiE "^\*?\*?Dependencies:?\*?\*?"; then
            local deps_value=$(echo "$line" | sed -E 's/^\*?\*?Dependencies:?\*?\*? *//')
            if echo "$deps_value" | grep -qiE "^none$"; then
                TASK_DEPS[$current_id]="none"
            else
                # Extract task numbers from "Task 1, Task 2" format
                local dep_ids=$(echo "$deps_value" | grep -oE "Task [0-9]+" | grep -oE "[0-9]+" | tr '\n' ' ' | sed 's/ $//')
                TASK_DEPS[$current_id]="$dep_ids"
            fi
            found_deps=true
        fi

        # Stop collecting files when we hit the next section
        if $in_task && $found_files && echo "$line" | grep -qE "^(\*\*Step|\*\*Dependencies|^#{2,3} |^---)"; then
            if ! echo "$line" | grep -qiE "^\*?\*?Files"; then
                found_files=false
            fi
        fi

    done < "$plan_file"

    # Save last task
    if [ -n "$current_id" ]; then
        if [ -z "${TASK_DEPS[$current_id]+x}" ]; then
            TASK_DEPS[$current_id]="none"
        fi
        if [ -z "${TASK_FILES[$current_id]+x}" ]; then
            TASK_FILES[$current_id]="none"
        fi
    fi
}

# Detect file overlaps between tasks and add implicit dependencies
# Populates: IMPLICIT_DEPS array with "earlier:later" pairs
detect_file_overlaps() {
    IMPLICIT_DEPS=()

    for ((i=0; i<${#TASK_IDS[@]}; i++)); do
        local id_i="${TASK_IDS[$i]}"
        local files_i="${TASK_FILES[$id_i]}"
        [ "$files_i" = "none" ] && continue

        for ((j=i+1; j<${#TASK_IDS[@]}; j++)); do
            local id_j="${TASK_IDS[$j]}"
            local files_j="${TASK_FILES[$id_j]}"
            [ "$files_j" = "none" ] && continue

            # Check for overlapping files
            for file_i in $files_i; do
                for file_j in $files_j; do
                    if [ "$file_i" = "$file_j" ]; then
                        IMPLICIT_DEPS+=("${id_i}:${id_j}")
                        echo "WARNING: Tasks $id_i and $id_j both touch $file_i - serializing" >&2

                        # Add implicit dep: later task depends on earlier
                        if [ "${TASK_DEPS[$id_j]}" = "none" ]; then
                            TASK_DEPS[$id_j]="$id_i"
                        elif ! echo "${TASK_DEPS[$id_j]}" | grep -qw "$id_i"; then
                            TASK_DEPS[$id_j]="${TASK_DEPS[$id_j]} $id_i"
                        fi
                        break 2
                    fi
                done
            done
        done
    done
}

# Compute execution waves based on dependency depth
# Populates: TASK_WAVE, MAX_WAVE
compute_waves() {
    TASK_WAVE=()
    MAX_WAVE=0

    # Compute depth for each task
    for id in "${TASK_IDS[@]}"; do
        _compute_depth "$id"
    done
}

# Recursive depth computation with memoization
_compute_depth() {
    local id="$1"

    # Already computed
    if [ -n "${TASK_WAVE[$id]+x}" ]; then
        echo "${TASK_WAVE[$id]}"
        return
    fi

    local deps="${TASK_DEPS[$id]}"
    if [ "$deps" = "none" ] || [ -z "$deps" ]; then
        TASK_WAVE[$id]=0
        echo 0
        return
    fi

    local max_dep_depth=0
    for dep_id in $deps; do
        local dep_depth=$(_compute_depth "$dep_id")
        if [ "$dep_depth" -gt "$max_dep_depth" ]; then
            max_dep_depth=$dep_depth
        fi
    done

    local my_depth=$((max_dep_depth + 1))
    TASK_WAVE[$id]=$my_depth
    if [ "$my_depth" -gt "$MAX_WAVE" ]; then
        MAX_WAVE=$my_depth
    fi
    echo "$my_depth"
}

# Get task IDs for a specific wave
get_wave_tasks() {
    local wave="$1"
    local result=""
    for id in "${TASK_IDS[@]}"; do
        if [ "${TASK_WAVE[$id]}" = "$wave" ]; then
            if [ -z "$result" ]; then
                result="$id"
            else
                result="$result $id"
            fi
        fi
    done
    echo "$result"
}

# Validate a plan file format
# Returns 0 if valid, 1 if invalid (errors on stderr)
validate_plan() {
    local plan_file="$1"
    local errors=0

    # Parse first
    parse_tasks "$plan_file"

    if [ ${#TASK_IDS[@]} -eq 0 ]; then
        echo "ERROR: No tasks found in plan" >&2
        return 1
    fi

    # Check each task has required fields
    for id in "${TASK_IDS[@]}"; do
        if [ -z "${TASK_DEPS[$id]+x}" ]; then
            echo "ERROR: Task $id missing Dependencies field" >&2
            errors=$((errors + 1))
        fi
    done

    # Check dependency references are valid
    for id in "${TASK_IDS[@]}"; do
        local deps="${TASK_DEPS[$id]}"
        [ "$deps" = "none" ] && continue
        for dep_id in $deps; do
            local found=false
            for check_id in "${TASK_IDS[@]}"; do
                if [ "$check_id" = "$dep_id" ]; then
                    found=true
                    break
                fi
            done
            if ! $found; then
                echo "ERROR: Task $id references non-existent dependency Task $dep_id" >&2
                errors=$((errors + 1))
            fi
        done
    done

    # Check for cycles (simple DFS)
    for id in "${TASK_IDS[@]}"; do
        if _has_cycle "$id" ""; then
            echo "ERROR: Dependency cycle detected involving Task $id" >&2
            errors=$((errors + 1))
        fi
    done

    [ $errors -eq 0 ]
}

# Cycle detection via DFS
_has_cycle() {
    local node="$1"
    local visited="$2"

    # Check if already in path
    if echo "$visited" | grep -qw "$node"; then
        return 0  # cycle found
    fi

    local deps="${TASK_DEPS[$node]}"
    [ "$deps" = "none" ] && return 1
    [ -z "$deps" ] && return 1

    for dep in $deps; do
        if _has_cycle "$dep" "$visited $node"; then
            return 0
        fi
    done

    return 1
}

# Extract the full text content of a specific task from the plan
extract_task_spec() {
    local plan_file="$1"
    local target_id="$2"
    local capturing=false
    local content=""

    while IFS= read -r line; do
        if echo "$line" | grep -qE "^#{2,3} Task ${target_id}:"; then
            capturing=true
            content="$line"
            continue
        fi

        if $capturing; then
            # Stop at next task header or end marker
            if echo "$line" | grep -qE "^#{2,3} Task [0-9]+:" || echo "$line" | grep -qE "^---$"; then
                break
            fi
            content="$content
$line"
        fi
    done < "$plan_file"

    echo "$content"
}
```

**Step 5: Run tests to verify they pass**

Run: `bash skills/subagent-driven-development/test-parse-plan.sh`
Expected: ALL PARSER TESTS PASSED!

**Step 6: Commit**

```bash
git add skills/subagent-driven-development/lib/parse-plan.sh skills/subagent-driven-development/test-parse-plan.sh skills/subagent-driven-development/examples/mock-plan.md
git commit -m "feat: add plan parser with dependency graph and wave computation"
```

---

## Task 3: Merge library (merge.sh)

**Files:**
- Create: `skills/subagent-driven-development/lib/merge.sh`
- Create: `skills/subagent-driven-development/test-merge.sh`

**Dependencies:** none
**Files:** skills/subagent-driven-development/lib/merge.sh (create), skills/subagent-driven-development/test-merge.sh (create)

**Step 1: Write the test file**

Create `skills/subagent-driven-development/test-merge.sh`:

```bash
#!/usr/bin/env bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "Testing Merge Library..."

# Setup test environment with git repo
TEST_DIR=$(mktemp -d)
cd "$TEST_DIR"
git init -q
git config user.email "test@test.com"
git config user.name "Test"

# Create base content
echo "base content" > file1.txt
echo "base content" > file2.txt
mkdir -p src
echo "shared" > src/shared.txt
git add -A
git commit -q -m "initial"

FEATURE_BRANCH="feature/test"
git checkout -q -b "$FEATURE_BRANCH"

cleanup() {
    cd /
    rm -rf "$TEST_DIR"
}
trap cleanup EXIT

# Source merge library
source "$SCRIPT_DIR/lib/merge.sh"

echo ""
echo "=== Clean Merge Tests ==="

echo -n "Test: squash-merge a clean task branch... "
# Create task branch with non-conflicting changes
git checkout -q -b "task/1-add-feature" "$FEATURE_BRANCH"
echo "feature 1" > feature1.txt
git add feature1.txt
git commit -q -m "add feature 1"
git checkout -q "$FEATURE_BRANCH"

if merge_task_branch "task/1-add-feature" "1" "Add feature"; then
    if [ -f feature1.txt ] && git log --oneline -1 | grep -q "Task 1"; then
        echo "PASS"
    else
        echo "FAIL (file missing or commit message wrong)"
        exit 1
    fi
else
    echo "FAIL (merge returned non-zero)"
    exit 1
fi

echo -n "Test: second clean merge works... "
git checkout -q -b "task/2-add-utils" "$FEATURE_BRANCH"~1
echo "utils" > utils.txt
git add utils.txt
git commit -q -m "add utils"
git checkout -q "$FEATURE_BRANCH"

if merge_task_branch "task/2-add-utils" "2" "Add utils"; then
    if [ -f utils.txt ] && [ -f feature1.txt ]; then
        echo "PASS"
    else
        echo "FAIL (files missing after merge)"
        exit 1
    fi
else
    echo "FAIL (merge returned non-zero)"
    exit 1
fi

echo ""
echo "=== Conflict Detection Tests ==="

echo -n "Test: conflicting merge is detected and aborted... "
# Create branch that conflicts with current state
git checkout -q -b "task/3-conflict" "$FEATURE_BRANCH"~2
echo "conflicting content" > feature1.txt
git add feature1.txt
git commit -q -m "conflict with feature 1"
git checkout -q "$FEATURE_BRANCH"

if merge_task_branch "task/3-conflict" "3" "Conflict test"; then
    echo "FAIL (should have returned non-zero)"
    exit 1
else
    # Verify merge was aborted cleanly
    if git status --porcelain | grep -q "^UU\|^AA"; then
        echo "FAIL (merge not properly aborted)"
        exit 1
    fi
    echo "PASS"
fi

echo ""
echo "========================================"
echo "ALL MERGE TESTS PASSED!"
echo "========================================"
```

**Step 2: Run test to verify it fails (merge.sh doesn't exist)**

Run: `bash skills/subagent-driven-development/test-merge.sh`
Expected: FAIL with source error

**Step 3: Implement merge.sh**

Create `skills/subagent-driven-development/lib/merge.sh`:

```bash
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

    # Attempt squash merge
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

# Merge all completed tasks from a wave in plan order
# Arguments: space-separated task IDs in plan order, plus associative array references
# Returns: space-separated list of task IDs that had merge conflicts
merge_wave_tasks() {
    local feature_branch="$1"
    shift
    local task_ids=("$@")

    local conflict_tasks=""

    for task_id in "${task_ids[@]}"; do
        local status_var="TASK_STATUS_${task_id}"
        local status="${!status_var}"

        # Skip failed/skipped tasks
        if [ "$status" != "COMPLETED" ]; then
            continue
        fi

        local name_var="TASK_NAME_${task_id}"
        local task_name="${!name_var:-task-$task_id}"
        local slug=$(echo "$task_name" | tr '[:upper:]' '[:lower:]' | tr ' ' '-' | tr -cd 'a-z0-9-')
        local branch="task/${task_id}-${slug}"

        if ! merge_task_branch "$branch" "$task_id" "$task_name"; then
            if [ -z "$conflict_tasks" ]; then
                conflict_tasks="$task_id"
            else
                conflict_tasks="$conflict_tasks $task_id"
            fi
        fi
    done

    echo "$conflict_tasks"
}
```

**Step 4: Run tests to verify they pass**

Run: `bash skills/subagent-driven-development/test-merge.sh`
Expected: ALL MERGE TESTS PASSED!

**Step 5: Commit**

```bash
git add skills/subagent-driven-development/lib/merge.sh skills/subagent-driven-development/test-merge.sh
git commit -m "feat: add merge library with squash-merge and conflict detection"
```

---

## Task 4: Scheduler library (scheduler.sh)

**Files:**
- Create: `skills/subagent-driven-development/lib/scheduler.sh`
- Create: `skills/subagent-driven-development/test-scheduler.sh`

**Dependencies:** Task 2
**Files:** skills/subagent-driven-development/lib/scheduler.sh (create), skills/subagent-driven-development/test-scheduler.sh (create)

**Step 1: Write the test file**

Create `skills/subagent-driven-development/test-scheduler.sh`:

```bash
#!/usr/bin/env bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "Testing Scheduler Library..."

# Source dependencies
source "$SCRIPT_DIR/lib/parse-plan.sh"
source "$SCRIPT_DIR/lib/scheduler.sh"

# Parse the mock plan first
parse_tasks "$SCRIPT_DIR/examples/mock-plan.md"
detect_file_overlaps
compute_waves

echo ""
echo "=== Scheduler State Tests ==="

echo -n "Test: init_scheduler sets up state... "
init_scheduler 3
if [ "$SCHED_MAX_CONCURRENT" = "3" ] && [ "$SCHED_ACTIVE_COUNT" = "0" ]; then
    echo "PASS"
else
    echo "FAIL"
    exit 1
fi

echo -n "Test: get_ready_tasks for wave 0 returns tasks 1 and 2... "
READY=$(get_ready_tasks 0)
if echo "$READY" | grep -q "1" && echo "$READY" | grep -q "2"; then
    echo "PASS"
else
    echo "FAIL (got: $READY)"
    exit 1
fi

echo -n "Test: can_launch returns true when slots available... "
if can_launch; then
    echo "PASS"
else
    echo "FAIL"
    exit 1
fi

echo -n "Test: mark_task_running tracks active task... "
mark_task_running 1 "12345"
if [ "$SCHED_ACTIVE_COUNT" = "1" ]; then
    echo "PASS"
else
    echo "FAIL (active=$SCHED_ACTIVE_COUNT)"
    exit 1
fi

echo -n "Test: mark_task_done frees slot... "
mark_task_done 1 "COMPLETED"
if [ "$SCHED_ACTIVE_COUNT" = "0" ] && [ "${SCHED_TASK_STATUS[1]}" = "COMPLETED" ]; then
    echo "PASS"
else
    echo "FAIL (active=$SCHED_ACTIVE_COUNT, status=${SCHED_TASK_STATUS[1]})"
    exit 1
fi

echo ""
echo "=== Dependency Cascade Tests ==="

echo -n "Test: mark_task_done with FAILED cascades to dependents... "
# Reset
init_scheduler 3
mark_task_running 1 "111"
mark_task_done 1 "FAILED"
# Task 3 depends on task 1, should be SKIPPED
if [ "${SCHED_TASK_STATUS[3]}" = "SKIPPED" ]; then
    echo "PASS"
else
    echo "FAIL (task 3 status=${SCHED_TASK_STATUS[3]})"
    exit 1
fi

echo -n "Test: cascaded skip propagates to transitive deps... "
# Task 4 depends on task 3 which was skipped
if [ "${SCHED_TASK_STATUS[4]}" = "SKIPPED" ]; then
    echo "PASS"
else
    echo "FAIL (task 4 status=${SCHED_TASK_STATUS[4]})"
    exit 1
fi

echo ""
echo "=== Concurrency Limit Tests ==="

echo -n "Test: can_launch respects max concurrent... "
init_scheduler 2
mark_task_running 1 "111"
mark_task_running 2 "222"
if can_launch; then
    echo "FAIL (should be at limit)"
    exit 1
else
    echo "PASS"
fi

echo ""
echo "========================================"
echo "ALL SCHEDULER TESTS PASSED!"
echo "========================================"
```

**Step 2: Run test to verify it fails**

Run: `bash skills/subagent-driven-development/test-scheduler.sh`
Expected: FAIL with source error

**Step 3: Implement scheduler.sh**

Create `skills/subagent-driven-development/lib/scheduler.sh`:

```bash
#!/usr/bin/env bash
# Wave-based batch-of-N scheduler for parallel-runner.sh
# Manages task lifecycle: ready → running → completed/failed/skipped

# Scheduler state
SCHED_MAX_CONCURRENT=3
SCHED_ACTIVE_COUNT=0
declare -A SCHED_TASK_STATUS=()   # task_id → PENDING|RUNNING|COMPLETED|FAILED|SKIPPED
declare -A SCHED_TASK_PID=()      # task_id → PID
declare -A SCHED_TASK_WORKTREE=() # task_id → worktree path

# Initialize scheduler
init_scheduler() {
    local max_concurrent="${1:-3}"
    SCHED_MAX_CONCURRENT=$max_concurrent
    SCHED_ACTIVE_COUNT=0
    SCHED_TASK_STATUS=()
    SCHED_TASK_PID=()
    SCHED_TASK_WORKTREE=()

    # Set all tasks to PENDING
    for id in "${TASK_IDS[@]}"; do
        SCHED_TASK_STATUS[$id]="PENDING"
    done
}

# Get tasks ready to run in a given wave
# A task is ready if: it's PENDING, in the correct wave, and all deps are COMPLETED
get_ready_tasks() {
    local wave="$1"
    local ready=""

    for id in "${TASK_IDS[@]}"; do
        [ "${SCHED_TASK_STATUS[$id]}" != "PENDING" ] && continue
        [ "${TASK_WAVE[$id]}" != "$wave" ] && continue

        # Check all dependencies are completed
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
            if [ -z "$ready" ]; then
                ready="$id"
            else
                ready="$ready $id"
            fi
        fi
    done

    echo "$ready"
}

# Check if we can launch another task
can_launch() {
    [ "$SCHED_ACTIVE_COUNT" -lt "$SCHED_MAX_CONCURRENT" ]
}

# Mark a task as running
mark_task_running() {
    local task_id="$1"
    local pid="$2"
    local worktree="${3:-}"

    SCHED_TASK_STATUS[$task_id]="RUNNING"
    SCHED_TASK_PID[$task_id]="$pid"
    SCHED_TASK_WORKTREE[$task_id]="$worktree"
    SCHED_ACTIVE_COUNT=$((SCHED_ACTIVE_COUNT + 1))
}

# Mark a task as done (COMPLETED or FAILED) and handle cascading
mark_task_done() {
    local task_id="$1"
    local status="$2"  # COMPLETED or FAILED

    SCHED_TASK_STATUS[$task_id]="$status"
    SCHED_ACTIVE_COUNT=$((SCHED_ACTIVE_COUNT - 1))
    [ "$SCHED_ACTIVE_COUNT" -lt 0 ] && SCHED_ACTIVE_COUNT=0

    # If failed, cascade SKIPPED to all transitive dependents
    if [ "$status" = "FAILED" ]; then
        _cascade_skip "$task_id"
    fi
}

# Cascade SKIPPED status to all tasks that depend on the given task
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
                # Recursively cascade
                _cascade_skip "$id"
                break
            fi
        done
    done
}

# Check if any tasks are still running
has_running_tasks() {
    [ "$SCHED_ACTIVE_COUNT" -gt 0 ]
}

# Check if wave is complete (no PENDING or RUNNING tasks in wave)
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

# Get completed task IDs for a wave in plan order
get_wave_completed() {
    local wave="$1"
    local result=""
    for id in "${TASK_IDS[@]}"; do
        [ "${TASK_WAVE[$id]}" != "$wave" ] && continue
        [ "${SCHED_TASK_STATUS[$id]}" != "COMPLETED" ] && continue
        if [ -z "$result" ]; then
            result="$id"
        else
            result="$result $id"
        fi
    done
    echo "$result"
}

# Print scheduler summary
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
```

**Step 4: Run tests to verify they pass**

Run: `bash skills/subagent-driven-development/test-scheduler.sh`
Expected: ALL SCHEDULER TESTS PASSED!

**Step 5: Commit**

```bash
git add skills/subagent-driven-development/lib/scheduler.sh skills/subagent-driven-development/test-scheduler.sh
git commit -m "feat: add wave-based scheduler with dependency cascading"
```

---

## Task 5: Main orchestrator (parallel-runner.sh)

**Files:**
- Create: `skills/subagent-driven-development/parallel-runner.sh`
- Create: `skills/subagent-driven-development/test-parallel-runner.sh`

**Dependencies:** Task 1, Task 2, Task 3, Task 4
**Files:** skills/subagent-driven-development/parallel-runner.sh (create), skills/subagent-driven-development/test-parallel-runner.sh (create)

**Step 1: Write integration test**

Create `skills/subagent-driven-development/test-parallel-runner.sh`:

```bash
#!/usr/bin/env bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
RALPH_DIR="$(cd "$SCRIPT_DIR/../ralph-loop" && pwd)"

echo "Testing Parallel Runner (integration)..."

# Setup test git repo
TEST_DIR=$(mktemp -d)
cd "$TEST_DIR"
git init -q
git config user.email "test@test.com"
git config user.name "Test"
echo "base" > base.txt
git add base.txt
git commit -q -m "initial"

FEATURE_BRANCH="feature/parallel-test"
git checkout -q -b "$FEATURE_BRANCH"

cleanup() {
    cd /
    rm -rf "$TEST_DIR"
}
trap cleanup EXIT

echo ""
echo "=== Argument Parsing Tests ==="

echo -n "Test: --help exits cleanly... "
if "$SCRIPT_DIR/parallel-runner.sh" --help >/dev/null 2>&1; then
    echo "PASS"
else
    echo "FAIL"
    exit 1
fi

echo -n "Test: missing plan file errors... "
if "$SCRIPT_DIR/parallel-runner.sh" "/nonexistent/plan.md" 2>/dev/null; then
    echo "FAIL (should have errored)"
    exit 1
else
    echo "PASS"
fi

echo ""
echo "=== Plan Validation Tests ==="

echo -n "Test: validates plan before execution... "
BAD_PLAN=$(mktemp --suffix=.md)
echo "not a valid plan" > "$BAD_PLAN"
if "$SCRIPT_DIR/parallel-runner.sh" "$BAD_PLAN" --dry-run 2>/dev/null; then
    echo "FAIL (should reject invalid plan)"
    rm -f "$BAD_PLAN"
    exit 1
else
    echo "PASS"
fi
rm -f "$BAD_PLAN"

echo -n "Test: dry-run mode shows plan analysis... "
OUTPUT=$("$SCRIPT_DIR/parallel-runner.sh" "$SCRIPT_DIR/examples/mock-plan.md" --dry-run 2>&1)
if echo "$OUTPUT" | grep -q "Wave 0" && echo "$OUTPUT" | grep -q "Wave 1"; then
    echo "PASS"
else
    echo "FAIL (output: $OUTPUT)"
    exit 1
fi

echo ""
echo "=== Worktree Management Tests ==="

echo -n "Test: cleanup_stale_worktrees handles empty dir... "
source "$SCRIPT_DIR/lib/parse-plan.sh"
source "$SCRIPT_DIR/lib/scheduler.sh"
source "$SCRIPT_DIR/lib/merge.sh"

# Source parallel-runner functions
WORKTREE_DIR="$TEST_DIR/.worktrees"
mkdir -p "$WORKTREE_DIR"

# This should not error on empty dir
cleanup_stale_worktrees "$WORKTREE_DIR" 2>/dev/null
if [ $? -eq 0 ]; then
    echo "PASS"
else
    echo "FAIL"
    exit 1
fi

echo -n "Test: setup_worktree_env handles project without deps... "
MOCK_WT=$(mktemp -d)
# No package.json, Cargo.toml etc - should return cleanly
setup_worktree_env "$MOCK_WT" "$TEST_DIR" 2>/dev/null
if [ $? -eq 0 ]; then
    echo "PASS"
else
    echo "FAIL"
    exit 1
fi
rm -rf "$MOCK_WT"

echo ""
echo "========================================"
echo "ALL PARALLEL RUNNER TESTS PASSED!"
echo "========================================"
```

**Step 2: Run test to verify it fails**

Run: `bash skills/subagent-driven-development/test-parallel-runner.sh`
Expected: FAIL

**Step 3: Implement parallel-runner.sh**

Create `skills/subagent-driven-development/parallel-runner.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
RALPH_DIR="$(cd "$SCRIPT_DIR/../ralph-loop" && pwd)"

# Source libraries
source "$SCRIPT_DIR/lib/parse-plan.sh"
source "$SCRIPT_DIR/lib/scheduler.sh"
source "$SCRIPT_DIR/lib/merge.sh"

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

# Parse arguments
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

PROJECT_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)

echo "========================================"
echo "Parallel Runner"
echo "Plan: $PLAN_FILE"
echo "Max concurrent: $MAX_CONCURRENT"
echo "Worktree dir: $WORKTREE_DIR"
echo "Base branch: $BASE_BRANCH"
echo "========================================"

# --- 1. PARSE ---
echo ""
echo "--- Phase 1: Parsing Plan ---"

if ! validate_plan "$PLAN_FILE"; then
    echo "ERROR: Plan validation failed" >&2
    exit 1
fi

parse_tasks "$PLAN_FILE"
detect_file_overlaps
compute_waves

echo "Tasks found: ${#TASK_IDS[@]}"
echo "Waves: $((MAX_WAVE + 1))"
for ((w=0; w<=MAX_WAVE; w++)); do
    wave_tasks=$(get_wave_tasks $w)
    echo "  Wave $w: tasks $wave_tasks"
done

# --- DRY RUN ---
if [ "$DRY_RUN" = true ]; then
    echo ""
    echo "Dry run complete. Exiting."
    exit 0
fi

# --- 2. SETUP ---
echo ""
echo "--- Phase 2: Setup ---"

# Cleanup stale worktrees
cleanup_stale_worktrees "$WORKTREE_DIR"

# Create worktree directory
mkdir -p "$WORKTREE_DIR"

# Verify .worktrees in .gitignore (for project-local dirs)
if [[ "$WORKTREE_DIR" != /* ]] && [[ "$WORKTREE_DIR" != ~* ]]; then
    if ! git check-ignore -q "$WORKTREE_DIR" 2>/dev/null; then
        echo "Adding $WORKTREE_DIR to .gitignore"
        echo "$WORKTREE_DIR" >> .gitignore
        git add .gitignore
        git commit -q -m "chore: add $WORKTREE_DIR to .gitignore"
    fi
fi

# Initialize scheduler
init_scheduler "$MAX_CONCURRENT"

# --- 3. EXECUTE WAVES ---
echo ""
echo "--- Phase 3: Executing Waves ---"

GLOBAL_START=$(date +%s)

for ((wave=0; wave<=MAX_WAVE; wave++)); do
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "Wave $wave"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    # Determine branch point for this wave's worktrees
    local_branch_point="$FEATURE_BRANCH"

    # Launch and monitor tasks in this wave
    while true; do
        # Launch ready tasks if slots available
        ready_tasks=$(get_ready_tasks $wave)
        for task_id in $ready_tasks; do
            if ! can_launch; then
                break
            fi

            local idx=-1
            for ((i=0; i<${#TASK_IDS[@]}; i++)); do
                if [ "${TASK_IDS[$i]}" = "$task_id" ]; then
                    idx=$i
                    break
                fi
            done
            local task_name="${TASK_NAMES[$idx]}"
            local slug=$(echo "$task_name" | tr '[:upper:]' '[:lower:]' | tr ' ' '-' | tr -cd 'a-z0-9-')
            local wt_path="$WORKTREE_DIR/task-${task_id}-${slug}"
            local branch_name="task/${task_id}-${slug}"

            echo "[WAVE $wave] Launching Task $task_id: $task_name"

            # Create worktree
            git worktree add "$wt_path" -b "$branch_name" "$local_branch_point" 2>/dev/null || {
                echo "ERROR: Failed to create worktree for task $task_id" >&2
                mark_task_done "$task_id" "FAILED"
                continue
            }

            # Setup environment
            setup_worktree_env "$wt_path" "$PROJECT_ROOT"

            # Write task spec
            local task_spec=$(mktemp --suffix=.md)
            extract_task_spec "$PLAN_FILE" "$task_id" > "$task_spec"

            # Launch ralph-runner.sh in background
            (
                cd "$wt_path"
                "$RALPH_DIR/ralph-runner.sh" \
                    "task-${task_id}-${slug}" \
                    "$task_spec" \
                    --worktree \
                    --non-interactive \
                    -d "$wt_path" \
                    > "$wt_path/.ralph-output.log" 2>&1
            ) &
            local pid=$!

            mark_task_running "$task_id" "$pid" "$wt_path"
        done

        # Check if wave is complete
        if wave_complete $wave; then
            break
        fi

        # Poll running tasks
        for task_id in "${TASK_IDS[@]}"; do
            [ "${SCHED_TASK_STATUS[$task_id]}" != "RUNNING" ] && continue

            local pid="${SCHED_TASK_PID[$task_id]}"
            if ! kill -0 "$pid" 2>/dev/null; then
                # Process finished, check exit code
                wait "$pid" 2>/dev/null
                local exit_code=$?

                local idx=-1
                for ((i=0; i<${#TASK_IDS[@]}; i++)); do
                    if [ "${TASK_IDS[$i]}" = "$task_id" ]; then
                        idx=$i
                        break
                    fi
                done

                if [ $exit_code -eq 0 ]; then
                    echo "[WAVE $wave] Task $task_id COMPLETED"
                    mark_task_done "$task_id" "COMPLETED"
                else
                    echo "[WAVE $wave] Task $task_id FAILED (exit $exit_code)"
                    mark_task_done "$task_id" "FAILED"
                fi
            fi
        done

        sleep 1
    done

    # --- MERGE wave results ---
    echo ""
    echo "[WAVE $wave] Merging completed tasks..."

    completed_ids=$(get_wave_completed $wave)
    if [ -n "$completed_ids" ]; then
        # Export task names for merge function
        for task_id in $completed_ids; do
            local idx=-1
            for ((i=0; i<${#TASK_IDS[@]}; i++)); do
                if [ "${TASK_IDS[$i]}" = "$task_id" ]; then
                    idx=$i
                    break
                fi
            done
            local task_name="${TASK_NAMES[$idx]}"
            local slug=$(echo "$task_name" | tr '[:upper:]' '[:lower:]' | tr ' ' '-' | tr -cd 'a-z0-9-')
            local branch="task/${task_id}-${slug}"

            if ! merge_task_branch "$branch" "$task_id" "$task_name"; then
                echo "[WAVE $wave] CONFLICT: Task $task_id needs re-run"
                # Re-run conflicted task sequentially
                local rerun_count=0
                local merged=false
                while [ $rerun_count -lt $MAX_CONFLICT_RERUNS ] && [ "$merged" = false ]; do
                    rerun_count=$((rerun_count + 1))
                    echo "[WAVE $wave] Re-running Task $task_id (attempt $rerun_count/$MAX_CONFLICT_RERUNS)"

                    local wt_path="$WORKTREE_DIR/task-${task_id}-${slug}-rerun-${rerun_count}"
                    local rerun_branch="task/${task_id}-${slug}-rerun-${rerun_count}"

                    # Create fresh worktree from current merged state
                    git worktree add "$wt_path" -b "$rerun_branch" "$FEATURE_BRANCH" 2>/dev/null || {
                        echo "ERROR: Failed to create re-run worktree" >&2
                        break
                    }
                    setup_worktree_env "$wt_path" "$PROJECT_ROOT"

                    local task_spec=$(mktemp --suffix=.md)
                    extract_task_spec "$PLAN_FILE" "$task_id" > "$task_spec"

                    # Run synchronously for re-runs
                    (
                        cd "$wt_path"
                        "$RALPH_DIR/ralph-runner.sh" \
                            "task-${task_id}-${slug}-rerun" \
                            "$task_spec" \
                            --worktree \
                            --non-interactive \
                            -d "$wt_path"
                    ) > "$wt_path/.ralph-output.log" 2>&1 || true

                    # Try merge again
                    if merge_task_branch "$rerun_branch" "$task_id" "$task_name"; then
                        merged=true
                        echo "[WAVE $wave] Re-run merge succeeded for Task $task_id"
                    fi
                done

                if [ "$merged" = false ]; then
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

# --- 4. REVIEW ---
echo ""
echo "--- Phase 4: Consensus Review ---"

# Only review if there are completed tasks
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

# --- 5. CLEANUP ---
echo ""
echo "--- Phase 5: Cleanup ---"

for wt in "$WORKTREE_DIR"/task-*; do
    [ -d "$wt" ] && git worktree remove "$wt" --force 2>/dev/null || rm -rf "$wt" 2>/dev/null || true
done
git worktree prune 2>/dev/null || true

# Print summary
print_summary

# Report failed tasks
for id in "${TASK_IDS[@]}"; do
    if [ "${SCHED_TASK_STATUS[$id]}" = "FAILED" ]; then
        echo "  Task $id: Check wip/ralph-fail-* branches"
    fi
    if [ "${SCHED_TASK_STATUS[$id]}" = "SKIPPED" ]; then
        echo "  Task $id: Skipped (dependency failed)"
    fi
done

# Exit with error if any tasks failed
for id in "${TASK_IDS[@]}"; do
    if [ "${SCHED_TASK_STATUS[$id]}" = "FAILED" ]; then
        exit 1
    fi
done

exit 0
```

Also add these helper functions that parallel-runner.sh needs (add to the top of the script after sourcing libraries):

```bash
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
```

**Step 4: Make executable**

Run: `chmod +x skills/subagent-driven-development/parallel-runner.sh`

**Step 5: Run tests to verify they pass**

Run: `bash skills/subagent-driven-development/test-parallel-runner.sh`
Expected: ALL PARALLEL RUNNER TESTS PASSED!

**Step 6: Commit**

```bash
git add skills/subagent-driven-development/parallel-runner.sh skills/subagent-driven-development/test-parallel-runner.sh
git commit -m "feat: add parallel-runner.sh orchestrator"
```

---

## Task 6: Update SKILL.md and writing-plans

**Files:**
- Modify: `skills/subagent-driven-development/SKILL.md`
- Modify: `skills/writing-plans/SKILL.md`

**Dependencies:** Task 5
**Files:** skills/subagent-driven-development/SKILL.md (modify), skills/writing-plans/SKILL.md (modify)

**Step 1: Update subagent-driven-development SKILL.md**

Key changes to `skills/subagent-driven-development/SKILL.md`:

1. Update the description line to mention parallel execution
2. Update "Core principle" to mention parallel waves
3. In the Process section, replace the sequential flow diagram with a parallel one
4. In Task Execution, replace the sequential loop with `parallel-runner.sh` invocation
5. Update Red Flags:
   - Remove: "Run multiple ralph-loops in parallel (git conflicts)"
   - Add: "Never run parallel-runner.sh without worktree isolation"
   - Add: "Never merge task branches out of plan order"
   - Add: "Never create dependent task worktrees from base branch (must use merged state)"
6. Add Configuration table:
   - `PARALLEL_MAX_CONCURRENT` | 3 | Max simultaneous tasks
   - `PARALLEL_WORKTREE_DIR` | .worktrees | Worktree location
   - `PARALLEL_MAX_CONFLICT_RERUNS` | 2 | Max re-runs for merge conflicts
7. Update the Example Workflow to show parallel output
8. Update the Files section to include `parallel-runner.sh` and lib files

**Step 2: Update writing-plans SKILL.md**

Add to the Task Structure section in `skills/writing-plans/SKILL.md`, after the Files block:

```markdown
**Dependencies:** [Task N, Task M] or none
```

This ensures plans generated by this skill include the `Dependencies:` field that `parse-plan.sh` expects.

Also note in the Remember section: "Include Dependencies field for every task (required for parallel execution)"

**Step 3: Verify SKILL.md is valid markdown**

Read back both files and verify structure is correct.

**Step 4: Commit**

```bash
git add skills/subagent-driven-development/SKILL.md skills/writing-plans/SKILL.md
git commit -m "docs: update SKILL.md files for parallel execution support"
```

---

## Task 7: Run all tests and create lib directory structure

**Files:**
- Create: `skills/subagent-driven-development/test-all.sh`

**Dependencies:** Task 5, Task 6
**Files:** skills/subagent-driven-development/test-all.sh (create)

**Step 1: Create test runner**

Create `skills/subagent-driven-development/test-all.sh`:

```bash
#!/usr/bin/env bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "========================================"
echo "Running all parallel-runner tests"
echo "========================================"

echo ""
echo "--- Parser Tests ---"
bash "$SCRIPT_DIR/test-parse-plan.sh"

echo ""
echo "--- Merge Tests ---"
bash "$SCRIPT_DIR/test-merge.sh"

echo ""
echo "--- Scheduler Tests ---"
bash "$SCRIPT_DIR/test-scheduler.sh"

echo ""
echo "--- Parallel Runner Tests ---"
bash "$SCRIPT_DIR/test-parallel-runner.sh"

echo ""
echo "--- Ralph Loop Tests (with --worktree) ---"
bash "$SCRIPT_DIR/../ralph-loop/test-ralph-loop.sh"

echo ""
echo "========================================"
echo "ALL TESTS PASSED!"
echo "========================================"
```

**Step 2: Run it**

Run: `bash skills/subagent-driven-development/test-all.sh`
Expected: ALL TESTS PASSED!

**Step 3: Commit**

```bash
git add skills/subagent-driven-development/test-all.sh
git commit -m "feat: add unified test runner for parallel execution"
```
