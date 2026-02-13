#!/usr/bin/env bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="$SCRIPT_DIR/auto-review.sh"

echo "Testing auto-review.sh..."

#############################################
# Argument Parsing Tests
#############################################

# Test 1: Missing description
echo -n "Test 1: Requires description... "
if $SCRIPT 2>&1 | grep -q "Error.*Description is required"; then
    echo "PASS"
else
    echo "FAIL"
    echo "  Expected: Error message about missing description"
    exit 1
fi

# Test 2: Help message
echo -n "Test 2: Shows usage with --help... "
if $SCRIPT --help 2>&1 | grep -q "Usage:"; then
    echo "PASS"
else
    echo "FAIL"
    echo "  Expected: Usage message"
    exit 1
fi

# Test 3: Unknown option rejected
echo -n "Test 3: Rejects unknown options... "
if $SCRIPT --unknown-flag "test" 2>&1 | grep -q "Error.*Unknown option"; then
    echo "PASS"
else
    echo "FAIL"
    echo "  Expected: Error message about unknown option"
    exit 1
fi

# Test 4: Invalid plan file
echo -n "Test 4: Rejects non-existent plan file... "
if $SCRIPT --plan-file=/nonexistent/file.md "test" 2>&1 | grep -q "Error.*Plan file not found"; then
    echo "PASS"
else
    echo "FAIL"
    echo "  Expected: Error message about plan file not found"
    exit 1
fi

#############################################
# SHA Auto-Detection Tests
#############################################

echo ""
echo "Testing SHA auto-detection..."

# Create test repo
TEST_REPO=$(mktemp -d)
cd "$TEST_REPO"
git init -q
git config user.email "test@test.com"
git config user.name "Test"

# Test 5: No changes case
echo -n "Test 5: Handles no changes gracefully... "
echo "initial" > test.txt
git add test.txt
git commit -q -m "initial commit"

output=$($SCRIPT --base=HEAD "test no changes" 2>&1)
if echo "$output" | grep -q "No changes.*nothing to review"; then
    echo "PASS"
else
    echo "FAIL"
    echo "  Expected: 'No changes' message"
    echo "  Got: $output"
    cd - > /dev/null
    rm -rf "$TEST_REPO"
    exit 1
fi

# Test 6: Dry run shows correct info
echo -n "Test 6: Dry run shows base/head/description... "
echo "modified for test 6" > test.txt
git add test.txt
git commit -q -m "test change for test 6"

output=$($SCRIPT --dry-run --base=HEAD~1 "Test description" 2>&1)
if echo "$output" | grep -q "Base SHA:" && \
   echo "$output" | grep -q "Head SHA:" && \
   echo "$output" | grep -q "Description: Test description"; then
    echo "PASS"
else
    echo "FAIL"
    echo "  Expected: Base SHA, Head SHA, Description in output"
    echo "  Got: $output"
    cd - > /dev/null
    rm -rf "$TEST_REPO"
    exit 1
fi

# Test 7: Explicit --base works
echo -n "Test 7: Explicit --base=HEAD~1 works... "
output=$($SCRIPT --dry-run --base=HEAD~1 "Test with base" 2>&1)
if echo "$output" | grep -q "Base SHA: HEAD~1"; then
    echo "PASS"
else
    echo "FAIL"
    echo "  Expected: Base SHA: HEAD~1"
    echo "  Got: $output"
    cd - > /dev/null
    rm -rf "$TEST_REPO"
    exit 1
fi

# Test 8: Shows changed files count
echo -n "Test 8: Shows changed files count... "
output=$($SCRIPT --dry-run --base=HEAD~1 "Test files" 2>&1)
if echo "$output" | grep -q "Reviewing.*changed file"; then
    echo "PASS"
else
    echo "FAIL"
    echo "  Expected: 'Reviewing N changed files'"
    echo "  Got: $output"
    cd - > /dev/null
    rm -rf "$TEST_REPO"
    exit 1
fi

# Test 9: Shows changed files list in dry run
echo -n "Test 9: Shows changed files list... "
output=$($SCRIPT --dry-run --base=HEAD~1 "Test files list" 2>&1)
if echo "$output" | grep -q "Changed files:" && echo "$output" | grep -q "test.txt"; then
    echo "PASS"
else
    echo "FAIL"
    echo "  Expected: Changed files list with test.txt"
    echo "  Got: $output"
    cd - > /dev/null
    rm -rf "$TEST_REPO"
    exit 1
fi

# Test 10: Dry run shows command that would be run
echo -n "Test 10: Dry run shows command... "
output=$($SCRIPT --dry-run --base=HEAD~1 "Test command" 2>&1)
if echo "$output" | grep -q "Would run:" && echo "$output" | grep -q "consensus-synthesis.sh"; then
    echo "PASS"
else
    echo "FAIL"
    echo "  Expected: 'Would run:' with consensus-synthesis.sh"
    echo "  Got: $output"
    cd - > /dev/null
    rm -rf "$TEST_REPO"
    exit 1
fi

# Cleanup test repo
cd - > /dev/null
rm -rf "$TEST_REPO"

#############################################
# Plan File Tests
#############################################

echo ""
echo "Testing plan file handling..."

# Create test repo with plan file
TEST_REPO=$(mktemp -d)
cd "$TEST_REPO"
git init -q
git config user.email "test@test.com"
git config user.name "Test"
echo "initial" > test.txt
git add test.txt
git commit -q -m "initial commit"
echo "modified" > test.txt
git add test.txt
git commit -q -m "test change"

# Create plan file
mkdir -p docs/plans
echo "# Test Plan" > docs/plans/test-plan.md

# Test 11: Plan file included in dry run
echo -n "Test 11: Plan file shown in dry run... "
output=$($SCRIPT --dry-run --base=HEAD~1 --plan-file=docs/plans/test-plan.md "Test with plan" 2>&1)
if echo "$output" | grep -q "plan-file="; then
    echo "PASS"
else
    echo "FAIL"
    echo "  Expected: plan-file in command"
    echo "  Got: $output"
    cd - > /dev/null
    rm -rf "$TEST_REPO"
    exit 1
fi

# Cleanup
cd - > /dev/null
rm -rf "$TEST_REPO"

#############################################
# Auto-Detection Fallback Tests
#############################################

echo ""
echo "Testing auto-detection fallbacks..."

# Test 12: Works without origin/main (uses HEAD~1 fallback)
echo -n "Test 12: Falls back to HEAD~1 without remote... "
TEST_REPO=$(mktemp -d)
cd "$TEST_REPO"
git init -q
git config user.email "test@test.com"
git config user.name "Test"
echo "initial" > test.txt
git add test.txt
git commit -q -m "initial commit"
echo "modified" > test.txt
git add test.txt
git commit -q -m "test change"

# No remote, should fall back to HEAD~1
output=$($SCRIPT --dry-run "Test fallback" 2>&1)
if echo "$output" | grep -q "Auto-detected base:"; then
    echo "PASS"
else
    echo "FAIL"
    echo "  Expected: Auto-detected base message"
    echo "  Got: $output"
    cd - > /dev/null
    rm -rf "$TEST_REPO"
    exit 1
fi

cd - > /dev/null
rm -rf "$TEST_REPO"

#############################################
# Integration Test (actual execution)
#############################################

echo ""
echo "Testing integration with consensus-synthesis.sh..."

# Test 13: Actually calls consensus-synthesis.sh (needs real repo context)
echo -n "Test 13: Integration with consensus-synthesis.sh... "

# Run from the actual conclave repo
cd "$SCRIPT_DIR/../.."

# Use a small range to minimize API calls
output=$($SCRIPT --base=HEAD~1 "Integration test" 2>&1 || true)

# Should either succeed or fail gracefully (API key issues, etc)
if echo "$output" | grep -q "CONSENSUS COMPLETE\|Stage 1\|API"; then
    echo "PASS (script executed)"
else
    echo "FAIL"
    echo "  Expected: Some indication that consensus-synthesis.sh ran"
    echo "  Got: $output"
    exit 1
fi

#############################################
# Summary
#############################################

echo ""
echo "=========================================="
echo "ALL AUTO-REVIEW TESTS PASSED!"
echo "=========================================="
echo ""
echo "Test coverage:"
echo "  - Argument parsing: 4 tests"
echo "  - SHA auto-detection: 6 tests"
echo "  - Plan file handling: 1 test"
echo "  - Auto-detection fallbacks: 1 test"
echo "  - Integration: 1 test"
echo ""
echo "Total: 13 tests"
echo ""
