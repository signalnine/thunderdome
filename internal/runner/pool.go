package runner

import "sync"

type Job func() error

// RunPool executes jobs with at most maxWorkers concurrently. Returns all errors.
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
