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
