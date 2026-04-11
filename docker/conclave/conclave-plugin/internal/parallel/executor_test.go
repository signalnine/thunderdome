package parallel

import (
	"context"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"

	"github.com/signalnine/conclave/internal/plan"
)

func TestExecuteWave_CreatesWorktrees(t *testing.T) {
	dir, g := setupRepo(t)
	worktreeDir := filepath.Join(dir, ".worktrees")

	tasks := []plan.Task{
		{ID: 1, Title: "Create Parser", Description: "### Task 1: Create Parser\nBuild a parser."},
		{ID: 2, Title: "Create Lexer", Description: "### Task 2: Create Lexer\nBuild a lexer."},
	}
	waves := map[int]int{1: 0, 2: 0}
	sched := NewScheduler(tasks, waves, 3)

	// Use a fake command that creates a file and commits in the worktree
	cmdBuilder := func(worktree, taskSpec string, taskID int, boardDir, boardTopic string) *exec.Cmd {
		script := fmt.Sprintf("cd %s && echo 'task %d ran' > proof.txt && git add -A && git commit -m 'task %d done'", worktree, taskID, taskID)
		cmd := exec.Command("bash", "-c", script)
		cmd.Dir = worktree
		return cmd
	}

	err := ExecuteWave(context.Background(), g, sched, tasks, 0, worktreeDir, "", cmdBuilder)
	if err != nil {
		t.Fatal(err)
	}

	// Both tasks should be completed
	if sched.Status(1) != StatusCompleted {
		t.Errorf("task 1 status = %s, want COMPLETED", sched.Status(1))
	}
	if sched.Status(2) != StatusCompleted {
		t.Errorf("task 2 status = %s, want COMPLETED", sched.Status(2))
	}
}

func TestExecuteWave_FailedTaskMarkedFailed(t *testing.T) {
	dir, g := setupRepo(t)
	worktreeDir := filepath.Join(dir, ".worktrees")

	tasks := []plan.Task{
		{ID: 1, Title: "Failing Task", Description: "### Task 1: Failing Task\nThis will fail."},
	}
	waves := map[int]int{1: 0}
	sched := NewScheduler(tasks, waves, 3)

	cmdBuilder := func(worktree, taskSpec string, taskID int, boardDir, boardTopic string) *exec.Cmd {
		return exec.Command("bash", "-c", "exit 1")
	}

	err := ExecuteWave(context.Background(), g, sched, tasks, 0, worktreeDir, "", cmdBuilder)
	if err != nil {
		t.Fatal(err)
	}

	if sched.Status(1) != StatusFailed {
		t.Errorf("task 1 status = %s, want FAILED", sched.Status(1))
	}
}

func TestExecuteWave_MergesCompletedTasks(t *testing.T) {
	dir, g := setupRepo(t)
	worktreeDir := filepath.Join(dir, ".worktrees")

	tasks := []plan.Task{
		{ID: 1, Title: "Add File", Description: "### Task 1: Add File\nCreate a file."},
	}
	waves := map[int]int{1: 0}
	sched := NewScheduler(tasks, waves, 3)

	// Command creates a real file and commits in the worktree
	cmdBuilder := func(worktree, taskSpec string, taskID int, boardDir, boardTopic string) *exec.Cmd {
		script := fmt.Sprintf(`
			cd %s
			echo "hello from task %d" > task-%d.txt
			git add -A
			git commit -m "task %d: add file"
		`, worktree, taskID, taskID, taskID)
		return exec.Command("bash", "-c", script)
	}

	err := ExecuteWave(context.Background(), g, sched, tasks, 0, worktreeDir, "", cmdBuilder)
	if err != nil {
		t.Fatal(err)
	}

	// File should exist on the main branch after merge
	content, err := os.ReadFile(filepath.Join(dir, "task-1.txt"))
	if err != nil {
		t.Fatalf("merged file not found: %v", err)
	}
	if !strings.Contains(string(content), "hello from task 1") {
		t.Errorf("unexpected content: %s", content)
	}
}

func TestExecuteWave_CleansUpWorktrees(t *testing.T) {
	dir, g := setupRepo(t)
	worktreeDir := filepath.Join(dir, ".worktrees")

	tasks := []plan.Task{
		{ID: 1, Title: "Temp Task", Description: "### Task 1: Temp Task\nDo something."},
	}
	waves := map[int]int{1: 0}
	sched := NewScheduler(tasks, waves, 3)

	cmdBuilder := func(worktree, taskSpec string, taskID int, boardDir, boardTopic string) *exec.Cmd {
		return exec.Command("bash", "-c", fmt.Sprintf("cd %s && echo x > f.txt && git add -A && git commit -m done", worktree))
	}

	err := ExecuteWave(context.Background(), g, sched, tasks, 0, worktreeDir, "", cmdBuilder)
	if err != nil {
		t.Fatal(err)
	}

	// Worktree directory should be cleaned up
	entries, _ := os.ReadDir(worktreeDir)
	if len(entries) > 0 {
		t.Errorf("worktree dir not cleaned up, has %d entries", len(entries))
	}
}

func TestExecuteWave_PassesTaskSpecToCommand(t *testing.T) {
	dir, g := setupRepo(t)
	worktreeDir := filepath.Join(dir, ".worktrees")

	tasks := []plan.Task{
		{ID: 1, Title: "Parser", Description: "### Task 1: Parser\n\nBuild a **markdown** parser with TDD."},
	}
	waves := map[int]int{1: 0}
	sched := NewScheduler(tasks, waves, 3)

	var capturedSpec string
	cmdBuilder := func(worktree, taskSpec string, taskID int, boardDir, boardTopic string) *exec.Cmd {
		capturedSpec = taskSpec
		return exec.Command("bash", "-c", fmt.Sprintf("cd %s && echo x > f.txt && git add -A && git commit -m done", worktree))
	}

	ExecuteWave(context.Background(), g, sched, tasks, 0, worktreeDir, "", cmdBuilder)

	if !strings.Contains(capturedSpec, "markdown") {
		t.Errorf("task spec not passed correctly, got: %s", capturedSpec[:min(len(capturedSpec), 100)])
	}
}

func TestBuildRalphCommand(t *testing.T) {
	cmd := BuildRalphCommand("/tmp/wt", "do stuff", 1, "/tmp/bus", "wave-0")
	args := cmd.Args

	// Should invoke conclave ralph-run
	found := false
	for _, a := range args {
		if a == "ralph-run" {
			found = true
			break
		}
	}
	if !found {
		t.Errorf("expected ralph-run in args: %v", args)
	}

	joined := strings.Join(args, " ")
	if !strings.Contains(joined, "--board-dir") {
		t.Error("missing --board-dir flag")
	}
	if !strings.Contains(joined, "--board-topic") {
		t.Error("missing --board-topic flag")
	}
	if !strings.Contains(joined, "--task-id") {
		t.Error("missing --task-id flag")
	}
	if cmd.Dir != "/tmp/wt" {
		t.Errorf("Dir = %q, want /tmp/wt", cmd.Dir)
	}
}

func min(a, b int) int {
	if a < b {
		return a
	}
	return b
}
