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
