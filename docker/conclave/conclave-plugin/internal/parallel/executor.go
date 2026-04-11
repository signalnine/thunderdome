package parallel

import (
	"context"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"strings"
	"sync"

	gitpkg "github.com/signalnine/conclave/internal/git"
	"github.com/signalnine/conclave/internal/plan"
)

// CmdBuilder creates the command to execute a task in a worktree.
// Parameters: worktree path, task spec text, task ID, board dir, board topic.
type CmdBuilder func(worktree, taskSpec string, taskID int, boardDir, boardTopic string) *exec.Cmd

var slugRe = regexp.MustCompile(`[^a-z0-9]+`)

// ExecuteWave runs all ready tasks in a wave in parallel using git worktrees.
// Each task gets its own worktree branched from the current HEAD.
// Completed tasks are squash-merged back in plan order.
// Failed tasks are marked and their dependents are cascade-skipped.
func ExecuteWave(ctx context.Context, g *gitpkg.Git, sched *Scheduler, tasks []plan.Task, wave int, worktreeBaseDir, busDir string, buildCmd CmdBuilder) error {
	ready := sched.GetReadyTasks(wave)
	if len(ready) == 0 {
		return nil
	}

	if err := os.MkdirAll(worktreeBaseDir, 0755); err != nil {
		return fmt.Errorf("creating worktree dir: %w", err)
	}

	// Get current HEAD to branch from
	headRef, err := g.RevParse("HEAD")
	if err != nil {
		return fmt.Errorf("getting HEAD: %w", err)
	}

	waveTopic := fmt.Sprintf("parallel.wave-%d.board", wave)

	type result struct {
		taskID   int
		worktree string
		err      error
	}

	results := make(chan result, len(ready))
	var wg sync.WaitGroup

	for _, taskID := range ready {
		task := findTask(tasks, taskID)
		if task == nil {
			continue
		}

		slug := slugify(task.Title)
		branchName := fmt.Sprintf("task-%d-%s", taskID, slug)
		worktreePath := filepath.Join(worktreeBaseDir, branchName)

		// Clean up stale branch/worktree from previous runs
		exec.Command("git", "-C", g.Dir, "branch", "-D", branchName).Run()
		os.RemoveAll(worktreePath)

		// Create worktree
		if err := g.WorktreeAdd(worktreePath, branchName, headRef); err != nil {
			fmt.Fprintf(os.Stderr, "  Task %d: worktree creation failed: %v\n", taskID, err)
			sched.MarkRunning(taskID, 0, "")
			sched.MarkDone(taskID, StatusFailed)
			continue
		}

		// Configure git identity in worktree
		wtGit := gitpkg.New(worktreePath)
		for _, args := range [][]string{
			{"-C", worktreePath, "config", "user.email", "conclave@parallel"},
			{"-C", worktreePath, "config", "user.name", "Conclave Parallel Runner"},
		} {
			exec.Command("git", args...).Run() // best-effort
		}
		_ = wtGit

		fmt.Fprintf(os.Stderr, "  Task %d: launching in %s\n", taskID, branchName)
		sched.MarkRunning(taskID, 0, worktreePath)

		wg.Add(1)
		go func(tid int, wt string, spec string) {
			defer wg.Done()
			cmd := buildCmd(wt, spec, tid, busDir, waveTopic)
			cmd.Stdout = os.Stderr
			cmd.Stderr = os.Stderr
			err := cmd.Run()
			results <- result{taskID: tid, worktree: wt, err: err}
		}(taskID, worktreePath, task.Description)
	}

	// Wait for all tasks to finish
	go func() {
		wg.Wait()
		close(results)
	}()

	for r := range results {
		if r.err != nil {
			fmt.Fprintf(os.Stderr, "  Task %d: FAILED (%v)\n", r.taskID, r.err)
			sched.MarkDone(r.taskID, StatusFailed)
		} else {
			fmt.Fprintf(os.Stderr, "  Task %d: COMPLETED\n", r.taskID)
			sched.MarkDone(r.taskID, StatusCompleted)
		}
	}

	// Merge completed tasks in plan order
	completedIDs := sched.WaveCompletedIDs(wave)
	for _, id := range completedIDs {
		wt := sched.Worktree(id)
		if wt == "" {
			continue
		}
		task := findTask(tasks, id)
		branchName := fmt.Sprintf("task-%d-%s", id, slugify(task.Title))
		if err := MergeTaskBranch(g, branchName, id, task.Title); err != nil {
			fmt.Fprintf(os.Stderr, "  Warning: merge failed for task %d: %v\n", id, err)
		}
	}

	// Clean up worktrees
	for _, id := range ready {
		wt := sched.Worktree(id)
		if wt != "" {
			g.WorktreeRemove(wt)
		}
	}
	g.WorktreePrune()

	return nil
}

// BuildRalphCommand creates the exec.Cmd to run conclave ralph-run for a task.
func BuildRalphCommand(worktree, taskSpec string, taskID int, boardDir, boardTopic string) *exec.Cmd {
	conclaveExe, err := os.Executable()
	if err != nil {
		conclaveExe = "conclave"
	}

	args := []string{
		"ralph-run",
		"--task", taskSpec,
		"--max-iterations", "5",
		"--skip-spec",
	}
	if boardDir != "" {
		args = append(args, "--board-dir", boardDir)
	}
	if boardTopic != "" {
		args = append(args, "--board-topic", boardTopic)
	}
	args = append(args, "--task-id", fmt.Sprintf("task-%d", taskID))

	cmd := exec.CommandContext(context.Background(), conclaveExe, args...)
	cmd.Dir = worktree
	// Filter out CLAUDECODE env var to allow nested claude -p invocations
	var env []string
	for _, e := range os.Environ() {
		if !strings.HasPrefix(e, "CLAUDECODE=") {
			env = append(env, e)
		}
	}
	env = append(env, "CONCLAVE_NON_INTERACTIVE=1")
	cmd.Env = env
	return cmd
}

func findTask(tasks []plan.Task, id int) *plan.Task {
	for i := range tasks {
		if tasks[i].ID == id {
			return &tasks[i]
		}
	}
	return nil
}

func slugify(s string) string {
	s = strings.ToLower(s)
	s = slugRe.ReplaceAllString(s, "-")
	s = strings.Trim(s, "-")
	if len(s) > 30 {
		s = s[:30]
	}
	return s
}
