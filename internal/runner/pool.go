package runner

import (
	"context"
	"fmt"
	"runtime/debug"
	"sync"
)

type Job func(ctx context.Context) error

// RunPool executes jobs with at most maxWorkers concurrently. Returns all errors.
// A job that panics is recovered and reported as an error so a single bad job
// cannot tear down the whole batch. If ctx is cancelled before a job is
// dispatched, the remaining jobs are skipped.
func RunPool(ctx context.Context, maxWorkers int, jobs []Job) []error {
	if maxWorkers < 1 {
		maxWorkers = 1
	}

	var (
		mu   sync.Mutex
		errs []error
		wg   sync.WaitGroup
	)
	sem := make(chan struct{}, maxWorkers)

	for _, job := range jobs {
		wg.Add(1)
		select {
		case sem <- struct{}{}:
		case <-ctx.Done():
			wg.Done()
			continue
		}
		go func(j Job) {
			defer wg.Done()
			defer func() { <-sem }()
			defer func() {
				if r := recover(); r != nil {
					mu.Lock()
					errs = append(errs, fmt.Errorf("job panic: %v\n%s", r, debug.Stack()))
					mu.Unlock()
				}
			}()
			if err := j(ctx); err != nil {
				mu.Lock()
				errs = append(errs, err)
				mu.Unlock()
			}
		}(job)
	}
	wg.Wait()
	return errs
}
