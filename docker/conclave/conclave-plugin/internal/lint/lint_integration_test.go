//go:build integration

package lint_test

import (
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
)

func TestLintRealSkills(t *testing.T) {
	root := findRepoRoot(t)
	binPath := filepath.Join(t.TempDir(), "conclave")
	build := exec.Command("go", "build", "-o", binPath, "./cmd/conclave/")
	build.Dir = root
	if out, err := build.CombinedOutput(); err != nil {
		t.Fatalf("build failed: %s\n%s", err, out)
	}

	// Run lint — real skills may have warnings/errors
	// Verify it runs without crashing and produces output
	cmd := exec.Command(binPath, "lint")
	cmd.Dir = root
	out, err := cmd.CombinedOutput()
	t.Logf("Output:\n%s", out)
	t.Logf("Exit code: %d", cmd.ProcessState.ExitCode())

	// Verify it produced output (not empty crash)
	if len(out) == 0 {
		t.Error("expected non-empty output from lint")
	}
	// Exit code should be 0 (clean) or 1 (lint errors found) — not a crash
	exitCode := cmd.ProcessState.ExitCode()
	if exitCode != 0 && exitCode != 1 {
		t.Errorf("unexpected exit code %d (expected 0 or 1): %v", exitCode, err)
	}
}

func TestLintBadFixtures(t *testing.T) {
	root := findRepoRoot(t)
	binPath := filepath.Join(t.TempDir(), "conclave")
	build := exec.Command("go", "build", "-o", binPath, "./cmd/conclave/")
	build.Dir = root
	if out, err := build.CombinedOutput(); err != nil {
		t.Fatalf("build failed: %s\n%s", err, out)
	}

	dir := t.TempDir()
	skillDir := filepath.Join(dir, "skills", "Bad_Skill")
	os.MkdirAll(skillDir, 0755)
	os.WriteFile(filepath.Join(skillDir, "SKILL.md"), []byte("---\nname: Bad_Skill\ndescription: Does stuff\n---\nBody.\n"), 0644)

	cmd := exec.Command(binPath, "lint", filepath.Join(dir, "skills"))
	cmd.Dir = dir
	out, _ := cmd.CombinedOutput()
	t.Logf("Output:\n%s", out)

	if cmd.ProcessState.ExitCode() == 0 {
		t.Error("expected non-zero exit for bad fixtures")
	}
}

func findRepoRoot(t *testing.T) string {
	t.Helper()
	cmd := exec.Command("git", "rev-parse", "--show-toplevel")
	out, err := cmd.Output()
	if err != nil {
		t.Fatal("not in a git repo")
	}
	return strings.TrimSpace(string(out))
}
