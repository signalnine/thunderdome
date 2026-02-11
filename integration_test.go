//go:build integration

package main

import (
	"context"
	"os"
	"os/exec"
	"path/filepath"
	"testing"
	"time"

	"github.com/signalnine/thunderdome/internal/config"
	"github.com/signalnine/thunderdome/internal/result"
	"github.com/signalnine/thunderdome/internal/runner"
)

// createFixtureRepo creates a minimal git repo for integration testing.
func createFixtureRepo(t *testing.T) string {
	t.Helper()
	dir := t.TempDir()
	cmds := [][]string{
		{"git", "init"},
		{"git", "config", "user.email", "test@test.com"},
		{"git", "config", "user.name", "Test"},
	}
	for _, args := range cmds {
		c := exec.Command(args[0], args[1:]...)
		c.Dir = dir
		if out, err := c.CombinedOutput(); err != nil {
			t.Fatalf("%v: %s", err, out)
		}
	}
	os.WriteFile(filepath.Join(dir, "hello.txt"), []byte("hello"), 0o644)
	os.WriteFile(filepath.Join(dir, "TASK.md"), []byte("Modify hello.txt to say goodbye"), 0o644)
	os.WriteFile(filepath.Join(dir, "test.sh"), []byte("#!/bin/sh\ntest -f hello.txt"), 0o755)
	for _, args := range [][]string{
		{"git", "add", "."},
		{"git", "commit", "-m", "initial"},
		{"git", "tag", "v1"},
	} {
		c := exec.Command(args[0], args[1:]...)
		c.Dir = dir
		if out, err := c.CombinedOutput(); err != nil {
			t.Fatalf("%v: %s", err, out)
		}
	}
	return dir
}

func TestNullAdapterIntegration(t *testing.T) {
	if os.Getenv("THUNDERDOME_DOCKER_TESTS") == "" {
		t.Skip("set THUNDERDOME_DOCKER_TESTS=1 to run integration tests")
	}

	fixtureDir := createFixtureRepo(t)

	resultsDir := t.TempDir()
	runDir, err := result.CreateRunDir(resultsDir)
	if err != nil {
		t.Fatalf("CreateRunDir: %v", err)
	}

	adapterPath, _ := filepath.Abs("adapters/null.sh")

	orch := &config.Orchestrator{
		Name:    "null",
		Adapter: adapterPath,
		Image:   "alpine:latest",
	}
	task := &config.Task{
		Repo:            fixtureDir,
		Tag:             "v1",
		Category:        "greenfield/simple",
		ValidationImage: "alpine:latest",
		TestCmd:         "sh test.sh",
	}

	ctx, cancel := context.WithTimeout(context.Background(), 60*time.Second)
	defer cancel()

	meta, err := runner.RunTrial(ctx, &runner.TrialOpts{
		Orchestrator: orch,
		Task:         task,
		TrialNum:     1,
		GatewayURL:   "http://localhost:0",
		RunDir:       runDir,
		Timeout:      30 * time.Second,
	})
	if err != nil {
		t.Fatalf("RunTrial: %v", err)
	}
	if meta.ExitReason != "completed" {
		t.Errorf("exit_reason: got %q, want %q", meta.ExitReason, "completed")
	}
	if meta.ExitCode != 0 {
		t.Errorf("exit_code: got %d, want 0", meta.ExitCode)
	}

	metaPath := filepath.Join(result.TrialDir(runDir, "null", filepath.Base(fixtureDir), 1), "meta.json")
	if _, err := os.Stat(metaPath); os.IsNotExist(err) {
		t.Error("meta.json not created")
	}
}
