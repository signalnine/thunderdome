#!/usr/bin/env bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "Testing Scheduler Library..."

source "$SCRIPT_DIR/lib/parse-plan.sh"
source "$SCRIPT_DIR/lib/scheduler.sh"

parse_tasks "$SCRIPT_DIR/examples/mock-plan.md"
detect_file_overlaps 2>/dev/null
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

echo -n "Test: get_ready_tasks for wave 0 returns independent tasks... "
READY=$(get_ready_tasks 0)
if echo "$READY" | grep -q "2"; then
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

echo -n "Test: FAILED task cascades to dependents... "
init_scheduler 3
mark_task_running 1 "111"
mark_task_done 1 "FAILED"
if [ "${SCHED_TASK_STATUS[3]}" = "SKIPPED" ]; then
    echo "PASS"
else
    echo "FAIL (task 3 status=${SCHED_TASK_STATUS[3]})"
    exit 1
fi

echo -n "Test: cascaded skip propagates transitively... "
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
echo "=== Wave Completion Tests ==="

echo -n "Test: wave_complete detects incomplete wave... "
init_scheduler 3
if wave_complete 0; then
    echo "FAIL (wave 0 should not be complete)"
    exit 1
else
    echo "PASS"
fi

echo -n "Test: wave_complete detects completed wave... "
# Complete all wave-0 tasks
for id in $(get_wave_tasks 0); do
    mark_task_running "$id" "$$"
    mark_task_done "$id" "COMPLETED"
done
if wave_complete 0; then
    echo "PASS"
else
    echo "FAIL"
    exit 1
fi

echo -n "Test: get_wave_completed returns completed tasks... "
COMPLETED=$(get_wave_completed 0)
if [ -n "$COMPLETED" ]; then
    echo "PASS (completed: $COMPLETED)"
else
    echo "FAIL (empty)"
    exit 1
fi

echo ""
echo "========================================"
echo "ALL SCHEDULER TESTS PASSED!"
echo "========================================"
