#!/usr/bin/env bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "Testing Plan Parser..."

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
if [ "${TASK_DEPS[1]}" = "none" ]; then
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
detect_file_overlaps 2>/dev/null
if echo "${IMPLICIT_DEPS[*]}" | grep -q "1:3"; then
    echo "PASS"
else
    echo "FAIL (got: ${IMPLICIT_DEPS[*]})"
    exit 1
fi

echo ""
echo "=== Wave Computation Tests ==="

echo -n "Test: compute_waves assigns correct depths... "
compute_waves
if [ "${TASK_WAVE[1]}" = "0" ] && [ "${TASK_WAVE[2]}" = "0" ]; then
    echo "PASS"
else
    echo "FAIL (got: wave[1]=${TASK_WAVE[1]}, wave[2]=${TASK_WAVE[2]})"
    exit 1
fi

echo -n "Test: task 3 is wave 1 (depends on wave-0 tasks)... "
if [ "${TASK_WAVE[3]}" = "1" ]; then
    echo "PASS"
else
    echo "FAIL (got: wave[3]=${TASK_WAVE[3]})"
    exit 1
fi

echo -n "Test: task 4 is wave 2... "
if [ "${TASK_WAVE[4]}" = "2" ]; then
    echo "PASS"
else
    echo "FAIL (got: wave[4]=${TASK_WAVE[4]})"
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
WAVE0=$(get_wave_tasks 0)
WAVE1=$(get_wave_tasks 1)
WAVE2=$(get_wave_tasks 2)
if echo "$WAVE0" | grep -q "2" && echo "$WAVE1" | grep -q "3" && echo "$WAVE2" | grep -q "4"; then
    echo "PASS"
else
    echo "FAIL (wave0=$WAVE0, wave1=$WAVE1, wave2=$WAVE2)"
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
