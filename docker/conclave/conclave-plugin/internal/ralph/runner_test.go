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

func TestStateManager_EvaluatorFields(t *testing.T) {
	dir := t.TempDir()
	sm := NewStateManager(dir)
	sm.Init("task-eval", 3)

	// Update with evaluator metadata (rawHash from raw test output)
	sm.UpdateWithEval("tests", 1, "eval feedback here", true, "raw-output-001.txt", "abc123def456")

	state, _ := sm.Load()
	if len(state.Attempts) != 1 {
		t.Fatalf("expected 1 attempt, got %d", len(state.Attempts))
	}
	if !state.Attempts[0].EvaluatorRan {
		t.Error("expected EvaluatorRan=true")
	}
	if state.Attempts[0].RawOutputRef != "raw-output-001.txt" {
		t.Errorf("expected raw output ref, got %s", state.Attempts[0].RawOutputRef)
	}

	// Verify stuck detection uses rawHash, not evaluator output hash
	sm.UpdateWithEval("tests", 1, "different eval feedback", true, "raw-output-002.txt", "abc123def456")
	state, _ = sm.Load()
	if state.StuckCount != 1 {
		t.Errorf("stuck count = %d, expected 1 (same raw hash)", state.StuckCount)
	}

	sm.Cleanup()
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
