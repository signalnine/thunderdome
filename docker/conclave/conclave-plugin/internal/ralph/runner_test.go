package ralph

import (
	"testing"
)

func TestLock_AcquireRelease(t *testing.T) {
	dir := t.TempDir()
	l := NewLock(dir)
	if err := l.Acquire(); err != nil {
		t.Fatal(err)
	}
	l.Release()
	// Should be able to acquire again after release
	if err := l.Acquire(); err != nil {
		t.Fatal(err)
	}
	l.Release()
}

func TestStateManager_FullLifecycle(t *testing.T) {
	dir := t.TempDir()
	sm := NewStateManager(dir)

	sm.Init("task-1", 3)

	state, _ := sm.Load()
	if state.Iteration != 1 {
		t.Errorf("initial iteration = %d", state.Iteration)
	}

	sm.Update("tests", 1, "some error")
	state, _ = sm.Load()
	if state.Iteration != 2 {
		t.Errorf("after update iteration = %d", state.Iteration)
	}

	sm.Update("tests", 1, "some error") // same error
	state, _ = sm.Load()
	if state.StuckCount != 1 {
		t.Errorf("stuck count = %d after 2 same errors", state.StuckCount)
	}

	sm.Cleanup()
	if sm.Exists() {
		t.Error("state still exists after cleanup")
	}
}
