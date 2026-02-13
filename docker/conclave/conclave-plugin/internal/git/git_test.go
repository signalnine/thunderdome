package git

import (
	"os"
	"os/exec"
	"path/filepath"
	"testing"
)

func setupTestRepo(t *testing.T) string {
	t.Helper()
	dir := t.TempDir()
	cmds := [][]string{
		{"git", "init", "-b", "main"},
		{"git", "config", "user.email", "test@test.com"},
		{"git", "config", "user.name", "Test"},
		{"git", "commit", "--allow-empty", "-m", "initial"},
	}
	for _, args := range cmds {
		cmd := exec.Command(args[0], args[1:]...)
		cmd.Dir = dir
		if out, err := cmd.CombinedOutput(); err != nil {
			t.Fatalf("%v failed: %s %v", args, out, err)
		}
	}
	return dir
}

func run(t *testing.T, dir string, args ...string) {
	t.Helper()
	cmd := exec.Command(args[0], args[1:]...)
	cmd.Dir = dir
	if out, err := cmd.CombinedOutput(); err != nil {
		t.Fatalf("%v: %s %v", args, out, err)
	}
}

func TestCurrentBranch(t *testing.T) {
	dir := setupTestRepo(t)
	g := New(dir)
	branch, err := g.CurrentBranch()
	if err != nil {
		t.Fatal(err)
	}
	if branch != "main" {
		t.Errorf("got %q, want main", branch)
	}
}

func TestWorktreeAddAndRemove(t *testing.T) {
	dir := setupTestRepo(t)
	g := New(dir)
	wtPath := filepath.Join(dir, "wt-test")
	if err := g.WorktreeAdd(wtPath, "test-branch", "HEAD"); err != nil {
		t.Fatal(err)
	}
	if _, err := os.Stat(wtPath); err != nil {
		t.Fatal("worktree not created")
	}
	if err := g.WorktreeRemove(wtPath); err != nil {
		t.Fatal(err)
	}
}

func TestMergeBase(t *testing.T) {
	dir := setupTestRepo(t)
	g := New(dir)
	run(t, dir, "git", "checkout", "-b", "feature")
	run(t, dir, "git", "commit", "--allow-empty", "-m", "feature commit")
	sha, err := g.MergeBase("main", "feature")
	if err != nil {
		t.Fatal(err)
	}
	if sha == "" {
		t.Error("empty merge-base")
	}
}

func TestDiff(t *testing.T) {
	dir := setupTestRepo(t)
	g := New(dir)
	os.WriteFile(filepath.Join(dir, "test.txt"), []byte("hello"), 0644)
	run(t, dir, "git", "add", "test.txt")
	run(t, dir, "git", "commit", "-m", "add file")
	diff, err := g.Diff("HEAD~1", "HEAD")
	if err != nil {
		t.Fatal(err)
	}
	if diff == "" {
		t.Error("empty diff")
	}
}

func TestDiffNameOnly(t *testing.T) {
	dir := setupTestRepo(t)
	g := New(dir)
	os.WriteFile(filepath.Join(dir, "a.txt"), []byte("a"), 0644)
	run(t, dir, "git", "add", "a.txt")
	run(t, dir, "git", "commit", "-m", "add a")
	files, err := g.DiffNameOnly("HEAD~1", "HEAD")
	if err != nil {
		t.Fatal(err)
	}
	if len(files) != 1 || files[0] != "a.txt" {
		t.Errorf("got %v", files)
	}
}

func TestMergeSquash(t *testing.T) {
	dir := setupTestRepo(t)
	g := New(dir)
	run(t, dir, "git", "checkout", "-b", "feat")
	os.WriteFile(filepath.Join(dir, "new.txt"), []byte("new"), 0644)
	run(t, dir, "git", "add", "new.txt")
	run(t, dir, "git", "commit", "-m", "feat commit")
	run(t, dir, "git", "checkout", "main")
	if err := g.MergeSquash("feat"); err != nil {
		t.Fatal(err)
	}
}

func TestHasStagedChanges(t *testing.T) {
	dir := setupTestRepo(t)
	g := New(dir)

	// No staged changes
	if g.HasStagedChanges() {
		t.Error("expected no staged changes")
	}

	// Add a file
	os.WriteFile(filepath.Join(dir, "staged.txt"), []byte("staged"), 0644)
	run(t, dir, "git", "add", "staged.txt")

	if !g.HasStagedChanges() {
		t.Error("expected staged changes")
	}
}

func TestRevParse(t *testing.T) {
	dir := setupTestRepo(t)
	g := New(dir)
	sha, err := g.RevParse("HEAD")
	if err != nil {
		t.Fatal(err)
	}
	if len(sha) != 40 {
		t.Errorf("sha length = %d, want 40", len(sha))
	}
}
