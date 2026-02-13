//go:build integration

package bus_test

import (
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
)

func TestBinaryBuildsWithBusPackage(t *testing.T) {
	root := findRepoRoot(t)
	binPath := filepath.Join(t.TempDir(), "conclave")
	build := exec.Command("go", "build", "-o", binPath, "./cmd/conclave/")
	build.Dir = root
	if out, err := build.CombinedOutput(); err != nil {
		t.Fatalf("build failed: %s\n%s", err, out)
	}

	// Verify --debate flag exists
	cmd := exec.Command(binPath, "consensus", "--help")
	out, _ := cmd.CombinedOutput()
	if !strings.Contains(string(out), "--debate") {
		t.Error("consensus command should have --debate flag")
	}

	// Verify board flags exist on ralph-run
	cmd = exec.Command(binPath, "ralph-run", "--help")
	out, _ = cmd.CombinedOutput()
	if !strings.Contains(string(out), "--board-dir") {
		t.Error("ralph-run should have --board-dir flag")
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
