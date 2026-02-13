package parallel

import (
	"testing"

	"github.com/signalnine/conclave/internal/plan"
)

func TestScheduler_GetReadyTasks(t *testing.T) {
	tasks := []plan.Task{
		{ID: 1, DependsOn: nil},
		{ID: 2, DependsOn: []int{1}},
		{ID: 3, DependsOn: nil},
	}
	waves := plan.ComputeWaves(tasks)
	s := NewScheduler(tasks, waves, 3)

	ready := s.GetReadyTasks(0)
	if len(ready) != 2 {
		t.Errorf("wave 0 ready = %d, want 2", len(ready))
	}
}

func TestScheduler_CascadeSkip(t *testing.T) {
	tasks := []plan.Task{
		{ID: 1, DependsOn: nil},
		{ID: 2, DependsOn: []int{1}},
		{ID: 3, DependsOn: []int{2}},
	}
	waves := plan.ComputeWaves(tasks)
	s := NewScheduler(tasks, waves, 3)

	s.MarkRunning(1, 0, "")
	s.MarkDone(1, StatusFailed)

	// Task 2 and 3 should be skipped
	if s.Status(2) != StatusSkipped {
		t.Errorf("task 2 status = %s", s.Status(2))
	}
	if s.Status(3) != StatusSkipped {
		t.Errorf("task 3 status = %s", s.Status(3))
	}
}

func TestScheduler_WaveComplete(t *testing.T) {
	tasks := []plan.Task{
		{ID: 1, DependsOn: nil},
		{ID: 2, DependsOn: nil},
	}
	waves := plan.ComputeWaves(tasks)
	s := NewScheduler(tasks, waves, 3)

	if s.WaveComplete(0) {
		t.Error("wave 0 should not be complete yet")
	}
	s.MarkRunning(1, 0, "")
	s.MarkRunning(2, 0, "")
	s.MarkDone(1, StatusCompleted)
	s.MarkDone(2, StatusCompleted)
	if !s.WaveComplete(0) {
		t.Error("wave 0 should be complete")
	}
}
