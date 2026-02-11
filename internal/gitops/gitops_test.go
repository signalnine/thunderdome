package gitops_test

import (
	"os"
	"os/exec"
	"path/filepath"
	"testing"

	"github.com/signalnine/thunderdome/internal/gitops"
)

func createTestRepo(t *testing.T) string {
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

func TestCloneAndCheckout(t *testing.T) {
	repo := createTestRepo(t)
	dest := t.TempDir()
	err := gitops.CloneAndCheckout(repo, "v1", dest)
	if err != nil {
		t.Fatalf("CloneAndCheckout: %v", err)
	}
	content, err := os.ReadFile(filepath.Join(dest, "hello.txt"))
	if err != nil {
		t.Fatalf("reading cloned file: %v", err)
	}
	if string(content) != "hello" {
		t.Errorf("content: got %q, want %q", content, "hello")
	}
}

func TestCaptureChanges(t *testing.T) {
	repo := createTestRepo(t)
	dest := t.TempDir()
	gitops.CloneAndCheckout(repo, "v1", dest)
	os.WriteFile(filepath.Join(dest, "hello.txt"), []byte("modified"), 0o644)
	os.WriteFile(filepath.Join(dest, "new.txt"), []byte("new file"), 0o644)
	diff, err := gitops.CaptureChanges(dest)
	if err != nil {
		t.Fatalf("CaptureChanges: %v", err)
	}
	if len(diff) == 0 {
		t.Error("expected non-empty diff")
	}
}

func TestCloneRejectsOptionLikeRepo(t *testing.T) {
	err := gitops.CloneAndCheckout("--upload-pack=evil", "v1", t.TempDir())
	if err == nil {
		t.Fatal("expected error for option-like repo")
	}
}

func TestCloneRejectsInvalidTag(t *testing.T) {
	for _, tag := range []string{"--option", "", " spaces", "../escape"} {
		err := gitops.CloneAndCheckout("/tmp/repo", tag, t.TempDir())
		if err == nil {
			t.Errorf("expected error for tag %q", tag)
		}
	}
}

func TestCaptureChangesNoChanges(t *testing.T) {
	repo := createTestRepo(t)
	dest := t.TempDir()
	gitops.CloneAndCheckout(repo, "v1", dest)
	diff, err := gitops.CaptureChanges(dest)
	if err != nil {
		t.Fatalf("CaptureChanges: %v", err)
	}
	if len(diff) != 0 {
		t.Errorf("expected empty diff, got %d bytes", len(diff))
	}
}
