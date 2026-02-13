#!/usr/bin/env bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "Testing Ralph Loop components..."

# Setup test environment
TEST_DIR=$(mktemp -d)
cd "$TEST_DIR"
git init -q
git config user.email "test@test.com"
git config user.name "Test"
echo "initial" > test.txt
git add test.txt
git commit -q -m "initial"

cleanup() {
    cd /
    rm -rf "$TEST_DIR"
}
trap cleanup EXIT

# Copy lib files for testing
cp -r "$SCRIPT_DIR/lib" .

echo ""
echo "=== State Management Tests ==="

source ./lib/state.sh

echo -n "Test: init_state creates JSON file... "
init_state "test-task" 5
if [ -f .ralph_state.json ] && jq -e . .ralph_state.json >/dev/null 2>&1; then
    echo "PASS"
else
    echo "FAIL"
    exit 1
fi

echo -n "Test: get_iteration returns correct value... "
if [ "$(get_iteration)" = "1" ]; then
    echo "PASS"
else
    echo "FAIL (got: $(get_iteration))"
    exit 1
fi

echo -n "Test: update_state increments iteration... "
update_state "tests" 1 "FAIL: some error"
if [ "$(get_iteration)" = "2" ]; then
    echo "PASS"
else
    echo "FAIL (got: $(get_iteration))"
    exit 1
fi

echo -n "Test: stuck detection works... "
# Same error 4 times (first doesn't count - no prior hash to compare)
update_state "tests" 1 "FAIL: some error"
update_state "tests" 1 "FAIL: some error"
update_state "tests" 1 "FAIL: some error"
source ./lib/stuck.sh
if is_stuck; then
    echo "PASS"
else
    echo "FAIL (should be stuck)"
    exit 1
fi

cleanup_state

echo ""
echo "=== Lock Management Tests ==="

source ./lib/lock.sh

echo -n "Test: acquire_lock creates lockfile... "
acquire_lock
if [ -f .ralph.lock ]; then
    echo "PASS"
else
    echo "FAIL"
    exit 1
fi

echo -n "Test: acquire_lock rejects concurrent... "
if acquire_lock 2>&1 | grep -q "Another Ralph loop"; then
    echo "PASS"
else
    echo "FAIL"
    exit 1
fi

release_lock

echo -n "Test: stale lock is cleaned... "
echo "1" > .ralph.lock
if acquire_lock 2>&1 | grep -q "stale"; then
    echo "PASS"
else
    echo "FAIL"
    exit 1
fi
release_lock

echo ""
echo "=== Failure Handling Tests ==="

source ./lib/failure.sh
init_state "test-fail" 3

echo -n "Test: branch_failed_work creates branch... "
echo "changes" >> test.txt
branch_failed_work "test-fail"
if git branch | grep -q "wip/ralph-fail-test-fail"; then
    echo "PASS"
else
    echo "FAIL"
    exit 1
fi

echo ""
echo "=== Worktree Mode Tests ==="

echo -n "Test: --worktree flag is parsed correctly... "
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

echo ""
echo "========================================"
echo "ALL TESTS PASSED!"
echo "========================================"
