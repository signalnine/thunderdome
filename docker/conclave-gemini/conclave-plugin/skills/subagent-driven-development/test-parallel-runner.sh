#!/usr/bin/env bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

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
source "$SCRIPT_DIR/lib/helpers.sh"

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
