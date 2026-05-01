package gitops_test

import (
	"bytes"
	"os"
	"os/exec"
	"path/filepath"
	"testing"

	"github.com/signalnine/thunderdome/internal/gitops"
)

// stripNonRepoHunks used Contains(line, "core.") to drop core-dump hunks, but
// that pattern also matches legitimate source files whose basename begins with
// "core." (e.g. core.ts, core.js). An agent that creates or edits such a file
// would have its diff silently dropped during workspace reconstruction. The
// detector must only fire for core-dump paths (basename "core.<numeric-pid>").
func TestStripNonRepoHunks_keepsLegitimateCoreSourceFiles(t *testing.T) {
	diff := []byte(`diff --git a/src/core.ts b/src/core.ts
index 1111111..2222222 100644
--- a/src/core.ts
+++ b/src/core.ts
@@ -1 +1 @@
-export const old = 1;
+export const newer = 2;
diff --git a/core.js b/core.js
new file mode 100644
index 0000000..3333333
--- /dev/null
+++ b/core.js
@@ -0,0 +1 @@
+module.exports = {};
`)
	out := gitops.StripNonRepoHunksForTest(diff)
	if !bytes.Contains(out, []byte("src/core.ts")) {
		t.Errorf("legitimate src/core.ts hunk was stripped:\n%s", out)
	}
	if !bytes.Contains(out, []byte("export const newer")) {
		t.Errorf("content of src/core.ts hunk was stripped:\n%s", out)
	}
	if !bytes.Contains(out, []byte("b/core.js")) {
		t.Errorf("top-level core.js hunk was stripped:\n%s", out)
	}
}

// Core-dump hunks (core.<pid>) must still be removed so git apply doesn't
// choke on binary crash dumps.
func TestStripNonRepoHunks_dropsCoreDumpPaths(t *testing.T) {
	diff := []byte(`diff --git a/core.12345 b/core.12345
new file mode 100644
index 0000000..4444444
Binary files /dev/null and b/core.12345 differ
diff --git a/src/app.ts b/src/app.ts
index 5555555..6666666 100644
--- a/src/app.ts
+++ b/src/app.ts
@@ -1 +1 @@
-const x = 1;
+const x = 2;
`)
	out := gitops.StripNonRepoHunksForTest(diff)
	if bytes.Contains(out, []byte("core.12345")) {
		t.Errorf("core-dump hunk was not stripped:\n%s", out)
	}
	if !bytes.Contains(out, []byte("src/app.ts")) {
		t.Errorf("legitimate src/app.ts hunk was stripped:\n%s", out)
	}
}

func TestShortHashDoesNotPanicOnShortInput(t *testing.T) {
	cases := []struct {
		in, want string
	}{
		{"", ""},
		{"abc", "abc"},
		{"abcdefgh", "abcdefgh"},
		{"abcdefghi", "abcdefgh"},
		{"abcdef1234567890", "abcdef12"},
	}
	for _, tc := range cases {
		if got := gitops.ShortHashForTest(tc.in); got != tc.want {
			t.Errorf("ShortHashForTest(%q) = %q, want %q", tc.in, got, tc.want)
		}
	}
}

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

// cleanupTmpDir previously shelled out to 'sudo rm -rf' unconditionally. On
// hosts without passwordless sudo (developer laptops), that silently failed
// and leaked /tmp/thunderdome-validation-* dirs. The cleanup must try
// os.RemoveAll first and only escalate to sudo when regular removal fails.
func TestCleanupTmpDir_doesNotInvokeSudoForRemovableDirs(t *testing.T) {
	fakeBin := t.TempDir()
	markerDir := t.TempDir()
	sudoMarker := filepath.Join(markerDir, "sudo-was-called")
	fakeSudo := filepath.Join(fakeBin, "sudo")
	script := "#!/bin/sh\ntouch " + sudoMarker + "\n/bin/rm -rf \"$@\"\nexit 0\n"
	if err := os.WriteFile(fakeSudo, []byte(script), 0o755); err != nil {
		t.Fatalf("writing fake sudo: %v", err)
	}

	t.Setenv("PATH", fakeBin+string(os.PathListSeparator)+os.Getenv("PATH"))

	target := filepath.Join(t.TempDir(), "subject")
	if err := os.MkdirAll(target, 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(target, "f.txt"), []byte("x"), 0o644); err != nil {
		t.Fatal(err)
	}

	gitops.CleanupTmpDirForTest(target)

	if _, err := os.Stat(target); !os.IsNotExist(err) {
		t.Errorf("expected tmpDir to be removed, got stat err: %v", err)
	}
	if _, err := os.Stat(sudoMarker); err == nil {
		t.Errorf("sudo was invoked for a regular removable directory")
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

// CaptureChanges must produce a complete diff even when the host git has no
// user.email/user.name configured. Previously the temp commit silently failed
// in that env, leaving HEAD at v1 and producing an empty diff that hid all
// agent work.
func TestCaptureChangesWithoutGitIdentity(t *testing.T) {
	repo := createTestRepo(t)
	dest := t.TempDir()
	if err := gitops.CloneAndCheckout(repo, "v1", dest); err != nil {
		t.Fatalf("CloneAndCheckout: %v", err)
	}

	// Strip any local identity that the clone might have inherited.
	for _, key := range []string{"user.email", "user.name"} {
		c := exec.Command("git", "config", "--unset-all", key)
		c.Dir = dest
		c.Run() // ignore: may not be set
	}

	// Point git at empty HOME and a writable but blank global config so it
	// cannot fall back to the developer's real ~/.gitconfig.
	emptyHome := t.TempDir()
	emptyGlobal := filepath.Join(t.TempDir(), "gitconfig")
	if err := os.WriteFile(emptyGlobal, []byte{}, 0o644); err != nil {
		t.Fatal(err)
	}
	t.Setenv("HOME", emptyHome)
	t.Setenv("XDG_CONFIG_HOME", emptyHome)
	t.Setenv("GIT_CONFIG_GLOBAL", emptyGlobal)
	t.Setenv("GIT_CONFIG_SYSTEM", "/dev/null")
	// Unset any author/committer overrides inherited from the parent process so
	// git really has nowhere to find an identity (this is the bug scenario).
	for _, k := range []string{"GIT_AUTHOR_NAME", "GIT_AUTHOR_EMAIL", "GIT_COMMITTER_NAME", "GIT_COMMITTER_EMAIL", "EMAIL"} {
		if _, ok := os.LookupEnv(k); ok {
			prev := os.Getenv(k)
			os.Unsetenv(k)
			t.Cleanup(func() { os.Setenv(k, prev) })
		}
	}

	if err := os.WriteFile(filepath.Join(dest, "hello.txt"), []byte("modified"), 0o644); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(dest, "new.txt"), []byte("new file"), 0o644); err != nil {
		t.Fatal(err)
	}

	diff, err := gitops.CaptureChanges(dest)
	if err != nil {
		t.Fatalf("CaptureChanges: %v", err)
	}
	if len(diff) == 0 {
		t.Fatal("expected non-empty diff with no host git identity, got empty")
	}
	if !bytes.Contains(diff, []byte("new file")) && !bytes.Contains(diff, []byte("new.txt")) {
		t.Errorf("expected diff to mention agent changes, got:\n%s", diff)
	}
}
