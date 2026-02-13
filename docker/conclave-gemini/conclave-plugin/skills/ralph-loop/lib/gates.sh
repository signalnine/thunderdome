#!/usr/bin/env bash
# Gate runner contracts for Ralph Loop
#
# Each gate function:
# - Takes: task context, prompt file, state file
# - Returns: 0 for pass, non-zero for fail
# - Outputs: gate output to stdout (captured for state)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/timeout.sh"

# Gate 1: Run tests
run_test_gate() {
    local project_dir="$1"
    local timeout=$(get_gate_timeout "test")

    echo "[GATE] Running tests..."

    # Auto-detect test runner
    if [ -f "$project_dir/package.json" ]; then
        run_with_timeout $timeout "test" npm test --prefix "$project_dir" 2>&1
    elif [ -f "$project_dir/Cargo.toml" ]; then
        run_with_timeout $timeout "test" cargo test --manifest-path "$project_dir/Cargo.toml" 2>&1
    elif [ -f "$project_dir/pyproject.toml" ] || [ -f "$project_dir/setup.py" ]; then
        run_with_timeout $timeout "test" python -m pytest "$project_dir" 2>&1
    elif [ -f "$project_dir/go.mod" ]; then
        run_with_timeout $timeout "test" go test "$project_dir/..." 2>&1
    else
        # Look for test scripts
        if [ -x "$project_dir/test.sh" ]; then
            run_with_timeout $timeout "test" "$project_dir/test.sh" 2>&1
        else
            echo "WARNING: No test runner detected, skipping test gate"
            return 0
        fi
    fi
}

# Gate 2: Spec compliance (invokes Claude Code)
run_spec_gate() {
    local task_prompt="$1"
    local context_file="$2"
    local spec_prompt="$3"
    local timeout=$(get_gate_timeout "spec")

    echo "[GATE] Running spec compliance review..."

    # Build spec review prompt
    local review_prompt="Review this implementation for spec compliance.

## Task Spec
$(cat "$task_prompt")

## Current State
$(cat "$context_file" 2>/dev/null || echo '(no context)')

## Instructions
Check if the implementation satisfies ALL requirements in the spec.
Output 'SPEC_PASS' if compliant, or list missing/extra items if not."

    # Invoke Claude Code for spec review
    run_with_timeout $timeout "spec" claude -p "$review_prompt" 2>&1
}

# Gate 3: Code quality (soft gate - warnings only)
run_quality_gate() {
    local project_dir="$1"
    local timeout=$(get_gate_timeout "quality")

    echo "[GATE] Running code quality check (soft gate)..."

    # Auto-detect linter
    local output=""
    if [ -f "$project_dir/package.json" ]; then
        output=$(run_with_timeout $timeout "quality" npm run lint --prefix "$project_dir" 2>&1 || true)
    elif [ -f "$project_dir/Cargo.toml" ]; then
        output=$(run_with_timeout $timeout "quality" cargo clippy --manifest-path "$project_dir/Cargo.toml" 2>&1 || true)
    elif [ -f "$project_dir/pyproject.toml" ]; then
        output=$(run_with_timeout $timeout "quality" python -m ruff check "$project_dir" 2>&1 || true)
    fi

    # Soft gate: always return 0, but output warnings
    if [ -n "$output" ]; then
        echo "Quality warnings (non-blocking):"
        echo "$output"
    fi
    return 0
}
