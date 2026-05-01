package runner_test

import (
	"fmt"
	"sync/atomic"
	"testing"

	"github.com/signalnine/thunderdome/internal/runner"
)

func TestPool(t *testing.T) {
	var count atomic.Int32
	jobs := make([]runner.Job, 10)
	for i := range jobs {
		jobs[i] = func() error {
			count.Add(1)
			return nil
		}
	}
	errs := runner.RunPool(3, jobs)
	if len(errs) != 0 {
		t.Errorf("expected no errors, got %v", errs)
	}
	if count.Load() != 10 {
		t.Errorf("expected 10 jobs, got %d", count.Load())
	}
}

func TestPoolWithErrors(t *testing.T) {
	jobs := []runner.Job{
		func() error { return nil },
		func() error { return fmt.Errorf("fail") },
		func() error { return nil },
	}
	errs := runner.RunPool(2, jobs)
	if len(errs) != 1 {
		t.Errorf("expected 1 error, got %d", len(errs))
	}
}

// A job that panics must be captured as an error, and remaining jobs must
// still run. Without recover() the goroutine panic tears down the whole
// 'thunderdome run --parallel N' batch.
func TestPoolRecoversPanickingJob(t *testing.T) {
	var ran atomic.Int32
	jobs := []runner.Job{
		func() error { ran.Add(1); return nil },
		func() error { panic("boom") },
		func() error { ran.Add(1); return nil },
		func() error { ran.Add(1); return nil },
	}
	errs := runner.RunPool(2, jobs)
	if len(errs) != 1 {
		t.Fatalf("expected 1 error from panic, got %d: %v", len(errs), errs)
	}
	if ran.Load() != 3 {
		t.Errorf("expected 3 non-panic jobs to run, got %d", ran.Load())
	}
}
