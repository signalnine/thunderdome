package docker_test

import (
	"context"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/signalnine/thunderdome/internal/docker"
)

// TestClassifyWaitError is a regression test for td-7ty.
// context.DeadlineExceeded received on the wait error channel must be
// classified as a timeout (ExitCode 124, TimedOut=true), not a crash.
// Generic Docker SDK errors must be classified as crashes (ExitCode 125,
// TimedOut=false) and the error must be surfaced to the caller.
func TestClassifyWaitError(t *testing.T) {
	dur := 5 * time.Second

	t.Run("DeadlineExceeded -> timeout", func(t *testing.T) {
		res, err := docker.ClassifyWaitError(context.DeadlineExceeded, dur)
		if err != nil {
			t.Fatalf("unexpected returned err: %v", err)
		}
		if res.ExitCode != 124 || !res.TimedOut {
			t.Errorf("got ExitCode=%d TimedOut=%v, want 124/true", res.ExitCode, res.TimedOut)
		}
	})

	t.Run("wrapped DeadlineExceeded -> timeout", func(t *testing.T) {
		wrapped := fmt.Errorf("wait failed: %w", context.DeadlineExceeded)
		res, err := docker.ClassifyWaitError(wrapped, dur)
		if err != nil {
			t.Fatalf("unexpected returned err: %v", err)
		}
		if res.ExitCode != 124 || !res.TimedOut {
			t.Errorf("got ExitCode=%d TimedOut=%v, want 124/true", res.ExitCode, res.TimedOut)
		}
	})

	t.Run("generic error -> crashed and surfaced", func(t *testing.T) {
		boom := errors.New("daemon disconnected")
		res, err := docker.ClassifyWaitError(boom, dur)
		if res.ExitCode != 125 || res.TimedOut {
			t.Errorf("got ExitCode=%d TimedOut=%v, want 125/false", res.ExitCode, res.TimedOut)
		}
		if err == nil || !errors.Is(err, boom) {
			t.Errorf("expected returned err to wrap %v, got %v", boom, err)
		}
	})

	t.Run("Canceled -> crashed (not timeout)", func(t *testing.T) {
		res, _ := docker.ClassifyWaitError(context.Canceled, dur)
		if res.TimedOut {
			t.Errorf("Canceled should not be classified as timeout")
		}
	})
}

// TestKillAndDumpAttemptsGracefulStopFirst is a source-check regression test.
// killAndDump must call ContainerStop (graceful, with timeout) before
// ContainerKill (SIGKILL) so the adapter has a chance to flush
// .thunderdome-metrics.json and the trailing NDJSON line.
func TestKillAndDumpAttemptsGracefulStopFirst(t *testing.T) {
	src, err := os.ReadFile("runner.go")
	if err != nil {
		t.Fatal(err)
	}
	text := string(src)
	stopIdx := strings.Index(text, "ContainerStop")
	killIdx := strings.Index(text, "ContainerKill")
	if stopIdx < 0 {
		t.Errorf("runner.go must call ContainerStop for graceful shutdown")
	}
	if stopIdx > killIdx && killIdx > 0 {
		t.Errorf("ContainerStop should appear before ContainerKill in the kill-and-dump path")
	}
}

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
