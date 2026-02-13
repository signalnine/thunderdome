#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Source library functions
source "$SCRIPT_DIR/lib/state.sh"
source "$SCRIPT_DIR/lib/lock.sh"
source "$SCRIPT_DIR/lib/timeout.sh"
source "$SCRIPT_DIR/lib/stuck.sh"
source "$SCRIPT_DIR/lib/failure.sh"
source "$SCRIPT_DIR/lib/gates.sh"

usage() {
    cat << EOF
Usage: ralph-runner.sh <task-id> <task-prompt-file> [options]

Arguments:
  task-id           Unique identifier for this task
  task-prompt-file  Path to markdown file with task spec

Options:
  -n, --max-iter N  Maximum iterations (default: 5)
  -d, --dir DIR     Project directory (default: current)
  --non-interactive Don't prompt for resume, auto-fresh
  --worktree        Skip lock (for parallel worktree execution)
  -h, --help        Show this help

Environment:
  RALPH_TIMEOUT_IMPLEMENT  Implement timeout in seconds (default: 1200)
  RALPH_TIMEOUT_TEST       Test timeout in seconds (default: 600)
  RALPH_TIMEOUT_GLOBAL     Global timeout in seconds (default: 3600)
EOF
}

# Parse arguments
TASK_ID=""
TASK_PROMPT=""
MAX_ITER=5
PROJECT_DIR="."
NON_INTERACTIVE=false
WORKTREE_MODE=false

while [[ $# -gt 0 ]]; do
    case $1 in
        -n|--max-iter) MAX_ITER="$2"; shift 2 ;;
        -d|--dir) PROJECT_DIR="$2"; shift 2 ;;
        --non-interactive) NON_INTERACTIVE=true; shift ;;
        --worktree) WORKTREE_MODE=true; shift ;;
        -h|--help) usage; exit 0 ;;
        -*) echo "Unknown option: $1" >&2; usage; exit 1 ;;
        *)
            if [ -z "$TASK_ID" ]; then
                TASK_ID="$1"
            elif [ -z "$TASK_PROMPT" ]; then
                TASK_PROMPT="$1"
            fi
            shift
            ;;
    esac
done

[ -z "$TASK_ID" ] && { echo "ERROR: Task ID required" >&2; usage; exit 1; }
[ -z "$TASK_PROMPT" ] && { echo "ERROR: Task prompt file required" >&2; usage; exit 1; }
[ ! -f "$TASK_PROMPT" ] && { echo "ERROR: Task prompt file not found: $TASK_PROMPT" >&2; exit 1; }

echo "========================================"
echo "Ralph Loop: $TASK_ID"
echo "Max iterations: $MAX_ITER"
echo "Project: $PROJECT_DIR"
echo "========================================"

# Acquire lock (skip in worktree mode - isolation handled externally)
if [ "$WORKTREE_MODE" = true ]; then
    echo "Worktree mode: skipping lock (isolation via worktree)"
else
    if ! acquire_lock; then
        exit 1
    fi
    setup_lock_trap
fi

# Check for existing state (resume vs fresh)
if state_exists; then
    if [ "$NON_INTERACTIVE" = true ]; then
        echo "Non-interactive mode: starting fresh"
        cleanup_state
        init_state "$TASK_ID" "$MAX_ITER"
    else
        echo "Found existing state file (iteration $(get_iteration))."
        read -p "Resume? [y/N] " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            cleanup_state
            init_state "$TASK_ID" "$MAX_ITER"
        fi
    fi
else
    init_state "$TASK_ID" "$MAX_ITER"
fi

# Global timeout tracking
GLOBAL_START=$(date +%s)

# Main loop
while [ "$(get_iteration)" -le "$MAX_ITER" ]; do
    ITER=$(get_iteration)
    echo ""
    echo "========== Iteration $ITER/$MAX_ITER =========="

    # Check global timeout
    if ! check_global_timeout $GLOBAL_START; then
        echo "Aborting due to global timeout"
        branch_failed_work "$TASK_ID"
        exit 1
    fi

    # Check if stuck
    if is_stuck; then
        echo "STUCK: Same error $STUCK_THRESHOLD times"
        increment_strategy_shift
        echo "$(get_stuck_directive)" >> "$CONTEXT_FILE"
    fi

    # Build implementation prompt
    IMPL_PROMPT=$(cat << EOF
# Task: $TASK_ID

## Spec
$(cat "$TASK_PROMPT")

## Previous Attempts
$(cat "$CONTEXT_FILE" 2>/dev/null || echo "(First attempt)")

## Instructions
1. Read the spec carefully
2. Write failing tests first (TDD)
3. Implement minimal code to pass tests
4. Commit your changes
5. Report SUCCESS or describe what failed
EOF
)

    # === GATE 1: Implementation ===
    echo "[1/3] Implementation..."
    IMPL_TIMEOUT=$(get_gate_timeout "implement")

    # Invoke Claude Code for implementation
    IMPL_OUTPUT=$(run_with_timeout $IMPL_TIMEOUT "implement" \
        claude -p "$IMPL_PROMPT" --allowedTools "Bash,Read,Write,Edit,Glob,Grep" 2>&1) || true

    # === GATE 2: Tests ===
    echo "[2/3] Running tests..."
    TEST_OUTPUT=$(run_test_gate "$PROJECT_DIR" 2>&1)
    TEST_EXIT=$?

    if [ $TEST_EXIT -ne 0 ]; then
        echo "FAIL: Tests failed"
        update_state "tests" $TEST_EXIT "$TEST_OUTPUT"
        continue
    fi
    echo "PASS: Tests passed"

    # === GATE 3: Spec Compliance ===
    echo "[3/3] Spec compliance review..."
    SPEC_OUTPUT=$(run_spec_gate "$TASK_PROMPT" "$CONTEXT_FILE" 2>&1)

    if ! echo "$SPEC_OUTPUT" | grep -q "SPEC_PASS"; then
        echo "FAIL: Spec compliance failed"
        update_state "spec" 1 "$SPEC_OUTPUT"
        continue
    fi
    echo "PASS: Spec compliant"

    # === SOFT GATE: Quality (non-blocking) ===
    echo "[soft] Code quality check..."
    run_quality_gate "$PROJECT_DIR" || true

    # === SUCCESS ===
    echo ""
    echo "========================================"
    echo "SUCCESS: $TASK_ID completed in $ITER iterations"
    echo "========================================"
    cleanup_state
    exit 0
done

# Cap hit
echo ""
echo "========================================"
echo "CAP HIT: $TASK_ID failed after $MAX_ITER iterations"
echo "========================================"
branch_failed_work "$TASK_ID"
exit 1
