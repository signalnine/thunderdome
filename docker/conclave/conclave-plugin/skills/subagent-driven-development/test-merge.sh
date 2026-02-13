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
git checkout -q -b "task/1-add-feature" "$FEATURE_BRANCH"
echo "feature 1" > feature1.txt
git add feature1.txt
git commit -q -m "add feature 1"
git checkout -q "$FEATURE_BRANCH"

if merge_task_branch "task/1-add-feature" "1" "Add feature" >/dev/null 2>&1; then
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

echo -n "Test: second clean merge preserves first... "
# Branch from before our merge to simulate parallel work
git checkout -q -b "task/2-add-utils" HEAD~1
echo "utils" > utils.txt
git add utils.txt
git commit -q -m "add utils"
git checkout -q "$FEATURE_BRANCH"

if merge_task_branch "task/2-add-utils" "2" "Add utils" >/dev/null 2>&1; then
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
git checkout -q -b "task/3-conflict" HEAD~2
echo "conflicting content" > feature1.txt
git add feature1.txt
git commit -q -m "conflict with feature 1"
git checkout -q "$FEATURE_BRANCH"

if merge_task_branch "task/3-conflict" "3" "Conflict test" >/dev/null 2>&1; then
    echo "FAIL (should have returned non-zero)"
    exit 1
else
    # Verify working tree is clean after abort
    if [ -z "$(git status --porcelain)" ]; then
        echo "PASS"
    else
        echo "FAIL (dirty state after abort)"
        git status --porcelain
        exit 1
    fi
fi

echo ""
echo "========================================"
echo "ALL MERGE TESTS PASSED!"
echo "========================================"
