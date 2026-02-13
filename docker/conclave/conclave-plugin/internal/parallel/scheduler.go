package parallel

import (
	"fmt"

	"github.com/signalnine/conclave/internal/plan"
)

type TaskStatus string

const (
	StatusPending   TaskStatus = "PENDING"
	StatusRunning   TaskStatus = "RUNNING"
	StatusCompleted TaskStatus = "COMPLETED"
	StatusFailed    TaskStatus = "FAILED"
	StatusSkipped   TaskStatus = "SKIPPED"
)

type Scheduler struct {
	tasks       []plan.Task
	waves       map[int]int
	maxConc     int
	statuses    map[int]TaskStatus
	pids        map[int]int
	worktrees   map[int]string
	activeCount int
}

func NewScheduler(tasks []plan.Task, waves map[int]int, maxConcurrent int) *Scheduler {
	s := &Scheduler{
		tasks:     tasks,
		waves:     waves,
		maxConc:   maxConcurrent,
		statuses:  make(map[int]TaskStatus),
		pids:      make(map[int]int),
		worktrees: make(map[int]string),
	}
	for _, t := range tasks {
		s.statuses[t.ID] = StatusPending
	}
	return s
}

func (s *Scheduler) GetReadyTasks(wave int) []int {
	var ready []int
	for _, t := range s.tasks {
		if s.statuses[t.ID] != StatusPending || s.waves[t.ID] != wave {
			continue
		}
		depsMet := true
		for _, dep := range t.DependsOn {
			if s.statuses[dep] != StatusCompleted {
				depsMet = false
				break
			}
		}
		if depsMet {
			ready = append(ready, t.ID)
		}
	}
	return ready
}

func (s *Scheduler) CanLaunch() bool {
	return s.activeCount < s.maxConc
}

func (s *Scheduler) MarkRunning(taskID, pid int, worktree string) {
	s.statuses[taskID] = StatusRunning
	s.pids[taskID] = pid
	s.worktrees[taskID] = worktree
	s.activeCount++
}

func (s *Scheduler) MarkDone(taskID int, status TaskStatus) {
	s.statuses[taskID] = status
	s.activeCount--
	if s.activeCount < 0 {
		s.activeCount = 0
	}
	if status == StatusFailed {
		s.cascadeSkip(taskID)
	}
}

func (s *Scheduler) cascadeSkip(failedID int) {
	for _, t := range s.tasks {
		if s.statuses[t.ID] != StatusPending {
			continue
		}
		for _, dep := range t.DependsOn {
			if dep == failedID || s.statuses[dep] == StatusSkipped {
				s.statuses[t.ID] = StatusSkipped
				fmt.Printf("[SCHEDULER] Task %d SKIPPED (dependency Task %d failed/skipped)\n", t.ID, dep)
				s.cascadeSkip(t.ID)
				break
			}
		}
	}
}

func (s *Scheduler) WaveComplete(wave int) bool {
	for _, t := range s.tasks {
		if s.waves[t.ID] != wave {
			continue
		}
		st := s.statuses[t.ID]
		if st == StatusPending || st == StatusRunning {
			return false
		}
	}
	return true
}

func (s *Scheduler) Status(taskID int) TaskStatus  { return s.statuses[taskID] }
func (s *Scheduler) HasRunning() bool               { return s.activeCount > 0 }
func (s *Scheduler) PID(taskID int) int             { return s.pids[taskID] }
func (s *Scheduler) Worktree(taskID int) string     { return s.worktrees[taskID] }

func (s *Scheduler) WaveCompletedIDs(wave int) []int {
	var ids []int
	for _, t := range s.tasks {
		if s.waves[t.ID] == wave && s.statuses[t.ID] == StatusCompleted {
			ids = append(ids, t.ID)
		}
	}
	return ids
}

func (s *Scheduler) PrintSummary() {
	var completed, failed, skipped int
	for _, t := range s.tasks {
		switch s.statuses[t.ID] {
		case StatusCompleted:
			completed++
		case StatusFailed:
			failed++
		case StatusSkipped:
			skipped++
		}
	}
	fmt.Printf("\n========================================\nPARALLEL EXECUTION SUMMARY\n========================================\n")
	fmt.Printf("  Completed: %d/%d\n  Failed:    %d\n  Skipped:   %d\n========================================\n",
		completed, len(s.tasks), failed, skipped)
}
