//go:build integration

package test

import (
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
)

func buildBinary(t *testing.T) string {
	t.Helper()
	dir := filepath.Join(t.TempDir(), "conclave-test")
	cmd := exec.Command("go", "build", "-o", dir, "./cmd/conclave")
	cmd.Dir = ".."
	if out, err := cmd.CombinedOutput(); err != nil {
		t.Fatalf("build failed: %s %v", out, err)
	}
	return dir
}

func TestIntegration_Version(t *testing.T) {
	bin := buildBinary(t)
	out, err := exec.Command(bin, "version").Output()
	if err != nil {
		t.Fatal(err)
	}
	if strings.TrimSpace(string(out)) == "" {
		t.Error("empty version output")
	}
}

func TestIntegration_ConsensusDryRun_GeneralPrompt(t *testing.T) {
	bin := buildBinary(t)
	cmd := exec.Command(bin, "consensus", "--mode=general-prompt", "--prompt=test question", "--dry-run")
	out, err := cmd.CombinedOutput()
	if err != nil {
		t.Fatalf("exit error: %v\noutput: %s", err, out)
	}
	if !strings.Contains(string(out), "Dry run") {
		t.Errorf("expected dry run output, got: %s", out)
	}
}

func TestIntegration_ConsensusDryRun_CodeReview(t *testing.T) {
	bin := buildBinary(t)
	cmd := exec.Command(bin, "consensus",
		"--mode=code-review",
		"--base-sha=abc123",
		"--head-sha=def456",
		"--description=test review",
		"--dry-run")
	out, err := cmd.CombinedOutput()
	if err != nil {
		t.Fatalf("exit error: %v\noutput: %s", err, out)
	}
	if !strings.Contains(string(out), "Dry run") {
		t.Errorf("expected dry run output, got: %s", out)
	}
}

func TestIntegration_ConsensusRequiresMode(t *testing.T) {
	bin := buildBinary(t)
	cmd := exec.Command(bin, "consensus")
	out, err := cmd.CombinedOutput()
	if err == nil {
		t.Error("expected error without --mode")
	}
	if !strings.Contains(string(out), "--mode is required") {
		t.Errorf("expected mode error, got: %s", out)
	}
}

func TestIntegration_SkillsList(t *testing.T) {
	bin := buildBinary(t)
	cmd := exec.Command(bin, "skills", "list")
	cmd.Dir = ".." // run from repo root where skills/ exists
	out, err := cmd.CombinedOutput()
	if err != nil {
		t.Fatalf("exit error: %v\noutput: %s", err, out)
	}
	if !strings.Contains(string(out), "brainstorming") {
		t.Errorf("expected brainstorming skill in output: %s", out)
	}
}

func TestIntegration_SkillsResolve(t *testing.T) {
	bin := buildBinary(t)
	cmd := exec.Command(bin, "skills", "resolve", "brainstorming")
	cmd.Dir = ".." // run from repo root
	out, err := cmd.CombinedOutput()
	if err != nil {
		t.Fatalf("exit error: %v\noutput: %s", err, out)
	}
	if !strings.Contains(string(out), "Name: brainstorming") {
		t.Errorf("expected skill details, got: %s", out)
	}
}

func TestIntegration_ParallelRunDryRun(t *testing.T) {
	bin := buildBinary(t)
	// Create a simple plan file
	planFile := filepath.Join(t.TempDir(), "plan.md")
	os.WriteFile(planFile, []byte("## Task 1: Setup\n**Dependencies:** None\n\n## Task 2: Build\n**Dependencies:** Task 1\n"), 0644)

	cmd := exec.Command(bin, "parallel-run", "--plan="+planFile, "--dry-run")
	out, err := cmd.CombinedOutput()
	if err != nil {
		t.Fatalf("exit error: %v\noutput: %s", err, out)
	}
	if !strings.Contains(string(out), "Dry run") {
		t.Errorf("expected dry run output, got: %s", out)
	}
	if !strings.Contains(string(out), "Wave 0") {
		t.Errorf("expected wave info, got: %s", out)
	}
}

func TestIntegration_HookSessionStart(t *testing.T) {
	bin := buildBinary(t)
	cmd := exec.Command(bin, "hook", "session-start")
	cmd.Dir = ".." // run from repo root
	out, err := cmd.CombinedOutput()
	if err != nil {
		t.Fatalf("exit error: %v\noutput: %s", err, out)
	}
	if !strings.Contains(string(out), "hookSpecificOutput") {
		t.Errorf("expected hook JSON output, got: %s", out)
	}
}

func TestIntegration_Help(t *testing.T) {
	bin := buildBinary(t)
	out, err := exec.Command(bin, "--help").CombinedOutput()
	if err != nil {
		t.Fatalf("exit error: %v\noutput: %s", err, out)
	}
	// Verify all commands are registered
	for _, cmd := range []string{"consensus", "auto-review", "parallel-run", "ralph-run", "hook", "skills", "version"} {
		if !strings.Contains(string(out), cmd) {
			t.Errorf("missing command %q in help output", cmd)
		}
	}
}
