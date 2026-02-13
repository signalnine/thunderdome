package parallel

import (
	"os"
	"os/exec"
	"path/filepath"
	"testing"

	gitpkg "github.com/signalnine/conclave/internal/git"
)

func setupRepo(t *testing.T) (string, *gitpkg.Git) {
	t.Helper()
	dir := t.TempDir()
	for _, args := range [][]string{
		{"git", "init", "-b", "main"},
		{"git", "config", "user.email", "test@test.com"},
		{"git", "config", "user.name", "Test"},
		{"git", "commit", "--allow-empty", "-m", "initial"},
	} {
		cmd := exec.Command(args[0], args[1:]...)
		cmd.Dir = dir
		if out, err := cmd.CombinedOutput(); err != nil {
			t.Fatalf("%v: %s %v", args, out, err)
		}
	}
	return dir, gitpkg.New(dir)
}

func TestMergeTaskBranch_Success(t *testing.T) {
	dir, g := setupRepo(t)
	// Create feature branch with a file
	run(t, dir, "git", "checkout", "-b", "task-1")
	os.WriteFile(filepath.Join(dir, "file.txt"), []byte("hello"), 0644)
	run(t, dir, "git", "add", "file.txt")
	run(t, dir, "git", "commit", "-m", "add file")
	run(t, dir, "git", "checkout", "main")

	err := MergeTaskBranch(g, "task-1", 1, "Create File")
	if err != nil {
		t.Fatal(err)
	}
}

func TestMergeTaskBranch_Conflict(t *testing.T) {
	dir, g := setupRepo(t)

	// Create a base file and commit
	os.WriteFile(filepath.Join(dir, "file.txt"), []byte("line1\nline2\nline3\n"), 0644)
	run(t, dir, "git", "add", "file.txt")
	run(t, dir, "git", "commit", "-m", "base file")

	// Create branch from here and modify
	run(t, dir, "git", "checkout", "-b", "task-1")
	os.WriteFile(filepath.Join(dir, "file.txt"), []byte("branch1\nbranch2\nbranch3\n"), 0644)
	run(t, dir, "git", "add", "file.txt")
	run(t, dir, "git", "commit", "-m", "branch change")

	// Back to main and make conflicting change to same lines
	run(t, dir, "git", "checkout", "main")
	os.WriteFile(filepath.Join(dir, "file.txt"), []byte("main1\nmain2\nmain3\n"), 0644)
	run(t, dir, "git", "add", "file.txt")
	run(t, dir, "git", "commit", "-m", "main change")

	err := MergeTaskBranch(g, "task-1", 1, "Conflicting")
	if err == nil {
		t.Error("expected conflict error")
	}
}

func run(t *testing.T, dir string, args ...string) {
	t.Helper()
	cmd := exec.Command(args[0], args[1:]...)
	cmd.Dir = dir
	if out, err := cmd.CombinedOutput(); err != nil {
		t.Fatalf("%v: %s %v", args, out, err)
	}
}
