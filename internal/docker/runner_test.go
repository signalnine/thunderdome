package docker_test

import (
	"context"
	"os"
	"path/filepath"
	"testing"
	"time"

	"github.com/signalnine/thunderdome/internal/docker"
)

func TestRunContainer(t *testing.T) {
	if os.Getenv("THUNDERDOME_DOCKER_TESTS") == "" {
		t.Skip("set THUNDERDOME_DOCKER_TESTS=1 to run Docker tests")
	}
	ctx, cancel := context.WithTimeout(context.Background(), 60*time.Second)
	defer cancel()

	workDir := t.TempDir()
	os.WriteFile(filepath.Join(workDir, "task.md"), []byte("test task"), 0o644)

	result, err := docker.RunContainer(ctx, &docker.RunOpts{
		Image:   "alpine:latest",
		Command: []string{"sh", "-c", "echo hello > /workspace/output.txt"},
		WorkDir: workDir,
		Env:     map[string]string{"TASK_DIR": "/workspace"},
		Timeout: 30 * time.Second,
	})
	if err != nil {
		t.Fatalf("RunContainer: %v", err)
	}
	if result.ExitCode != 0 {
		t.Errorf("exit code: got %d, want 0", result.ExitCode)
	}
	if result.TimedOut {
		t.Error("unexpected timeout")
	}
	content, err := os.ReadFile(filepath.Join(workDir, "output.txt"))
	if err != nil {
		t.Fatalf("reading output: %v", err)
	}
	if string(content) != "hello\n" {
		t.Errorf("output: got %q, want %q", content, "hello\n")
	}
}

func TestRunContainerTimeout(t *testing.T) {
	if os.Getenv("THUNDERDOME_DOCKER_TESTS") == "" {
		t.Skip("set THUNDERDOME_DOCKER_TESTS=1 to run Docker tests")
	}
	ctx := context.Background()
	workDir := t.TempDir()

	result, err := docker.RunContainer(ctx, &docker.RunOpts{
		Image:   "alpine:latest",
		Command: []string{"sleep", "300"},
		WorkDir: workDir,
		Timeout: 2 * time.Second,
	})
	if err != nil {
		t.Fatalf("RunContainer: %v", err)
	}
	if !result.TimedOut {
		t.Error("expected timeout")
	}
	if result.ExitCode != 124 {
		t.Errorf("exit code: got %d, want 124", result.ExitCode)
	}
}

func TestRunContainerCrash(t *testing.T) {
	if os.Getenv("THUNDERDOME_DOCKER_TESTS") == "" {
		t.Skip("set THUNDERDOME_DOCKER_TESTS=1 to run Docker tests")
	}
	ctx := context.Background()
	workDir := t.TempDir()

	result, err := docker.RunContainer(ctx, &docker.RunOpts{
		Image:   "alpine:latest",
		Command: []string{"sh", "-c", "exit 1"},
		WorkDir: workDir,
		Timeout: 10 * time.Second,
	})
	if err != nil {
		t.Fatalf("RunContainer: %v", err)
	}
	if result.ExitCode != 1 {
		t.Errorf("exit code: got %d, want 1", result.ExitCode)
	}
}
