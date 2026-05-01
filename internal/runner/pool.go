package runner

import (
	"fmt"
	"runtime/debug"
	"sync"
)

type Job func() error

// RunPool executes jobs with at most maxWorkers concurrently. Returns all errors.
// A job that panics is recovered and reported as an error so a single bad job
// cannot tear down the whole batch.
func RunPool(maxWorkers int, jobs []Job) []error {
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
		sem <- struct{}{}
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
			if err := j(); err != nil {
				mu.Lock()
				errs = append(errs, err)
				mu.Unlock()
			}
		}(job)
	}
	wg.Wait()
	return errs
}
