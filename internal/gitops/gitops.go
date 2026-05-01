package gitops

import (
	"fmt"
	"io"
	"log"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"strings"
)

// validTag matches reasonable git tag/branch names and rejects option-like strings.
var validTag = regexp.MustCompile(`^[a-zA-Z0-9][a-zA-Z0-9._/-]*$`)

func CloneAndCheckout(repo, tag, dest string) error {
	if strings.HasPrefix(repo, "-") {
		return fmt.Errorf("invalid repo %q: must not start with -", repo)
	}
	if !validTag.MatchString(tag) {
		return fmt.Errorf("invalid tag %q: must match %s", tag, validTag.String())
	}
	cmd := exec.Command("git", "clone", "--branch", tag, "--depth", "1", repo, dest)
	if out, err := cmd.CombinedOutput(); err != nil {
		return fmt.Errorf("git clone: %s: %w", out, err)
	}
	return nil
}

// CloneTag clones a repo at a specific tag into a temporary directory and returns the path.
// Unlike CloneAndCheckout, this creates a temp dir automatically.
func CloneTag(repo, tag string) (string, error) {
	if strings.HasPrefix(repo, "-") {
		return "", fmt.Errorf("invalid repo %q: must not start with -", repo)
	}
	if !validTag.MatchString(tag) {
		return "", fmt.Errorf("invalid tag %q: must match %s", tag, validTag.String())
	}
	tmpDir, err := os.MkdirTemp("", "thunderdome-validation-*")
	if err != nil {
		return "", fmt.Errorf("creating temp dir: %w", err)
	}
	cmd := exec.Command("git", "clone", "--branch", tag, "--depth", "1", repo, tmpDir)
	if out, err := cmd.CombinedOutput(); err != nil {
		os.RemoveAll(tmpDir)
		return "", fmt.Errorf("git clone %s at %s: %s: %w", repo, tag, out, err)
	}
	return tmpDir, nil
}

// CopyDir copies the contents of src directory into dst directory.
// Only regular files and directories are copied. Existing files in dst are overwritten.
func CopyDir(src, dst string) error {
	return filepath.Walk(src, func(path string, info os.FileInfo, err error) error {
		if err != nil {
			return err
		}
		rel, err := filepath.Rel(src, path)
		if err != nil {
			return err
		}
		// Skip .git directory
		if rel == ".git" || strings.HasPrefix(rel, ".git"+string(filepath.Separator)) {
			if info.IsDir() {
				return filepath.SkipDir
			}
			return nil
		}
		target := filepath.Join(dst, rel)
		if info.IsDir() {
			return os.MkdirAll(target, info.Mode())
		}
		return copyFile(path, target, info.Mode())
	})
}

func copyFile(src, dst string, mode os.FileMode) error {
	in, err := os.Open(src)
	if err != nil {
		return err
	}
	defer in.Close()
	if err := os.MkdirAll(filepath.Dir(dst), 0o755); err != nil {
		return err
	}
	out, err := os.OpenFile(dst, os.O_WRONLY|os.O_CREATE|os.O_TRUNC, mode)
	if err != nil {
		return err
	}
	defer out.Close()
	_, err = io.Copy(out, in)
	return err
}

// coreDumpRe matches core-dump basenames like "core.12345" on a diff --git
// header. It requires the path to end at the dumped PID (numeric suffix), so
// it does not match legitimate source files such as core.ts / core.js.
var coreDumpRe = regexp.MustCompile(`[ /]core\.\d+(\s|$)`)

// stripNonRepoHunks removes diff hunks for files that are runtime artifacts
// (e.g. .thunderdome-output.jsonl, core dumps) and would cause git apply to fail.
func stripNonRepoHunks(diff []byte) []byte {
	lines := strings.Split(string(diff), "\n")
	var out []string
	skip := false
	for _, line := range lines {
		if strings.HasPrefix(line, "diff --git ") {
			skip = false
			// Skip hunks for known runtime artifacts and binary files
			for _, pattern := range []string{
				".thunderdome-output.jsonl",
				".thunderdome-metrics.json",
				".amplifier-stdout.log",
			} {
				if strings.Contains(line, pattern) {
					skip = true
					break
				}
			}
			if !skip && coreDumpRe.MatchString(line) {
				skip = true
			}
		}
		if !skip {
			out = append(out, line)
		}
	}
	return []byte(strings.Join(out, "\n"))
}

// ReconstructFromDiff clones a repo at a tag into a temp directory and applies a diff patch.
// Returns the temp directory path and a cleanup function. Caller must call cleanup when done.
func ReconstructFromDiff(repo, tag string, diff []byte) (string, func(), error) {
	tmpDir, err := CloneTag(repo, tag)
	if err != nil {
		return "", nil, err
	}
	cleanup := func() { cleanupTmpDir(tmpDir) }

	if len(diff) == 0 {
		return tmpDir, cleanup, nil
	}

	cleaned := stripNonRepoHunks(diff)

	cmd := exec.Command("git", "apply", "--allow-empty", "-")
	cmd.Dir = tmpDir
	cmd.Stdin = strings.NewReader(string(cleaned))
	if out, err := cmd.CombinedOutput(); err != nil {
		cleanup()
		return "", nil, fmt.Errorf("git apply: %s: %w", out, err)
	}
	return tmpDir, cleanup, nil
}

// CaptureChanges captures all changes from the original tag to current state,
// including committed changes, staged changes, and untracked files.
func CaptureChanges(repoDir string) ([]byte, error) {
	// Stage everything (untracked files, modifications, deletions)
	add := exec.Command("git", "add", "-A")
	add.Dir = repoDir
	if out, err := add.CombinedOutput(); err != nil {
		return nil, fmt.Errorf("git add -A: %s: %w", out, err)
	}

	// Create a temporary commit so all changes are reachable. Set identity
	// inline so this works even when the workspace clone has no configured
	// user.email/user.name (e.g. fresh CI containers); --allow-empty handles
	// the no-changes case. Any error here means the staged index will be
	// dropped from the v1..HEAD diff, so propagate instead of swallowing.
	commit := exec.Command("git",
		"-c", "user.name=thunderdome",
		"-c", "user.email=thunderdome@invalid",
		"commit", "--allow-empty", "-m", "thunderdome-capture",
	)
	commit.Dir = repoDir
	if out, err := commit.CombinedOutput(); err != nil {
		return nil, fmt.Errorf("git commit: %s: %w", out, err)
	}

	// Find the initial commit (the v1 tag clone point)
	revList := exec.Command("git", "rev-list", "--max-parents=0", "HEAD")
	revList.Dir = repoDir
	rootOut, err := revList.Output()
	if err != nil {
		// Fallback to cached diff if we can't find root
		diff := exec.Command("git", "diff", "--cached")
		diff.Dir = repoDir
		out, err := diff.Output()
		if err != nil {
			return nil, fmt.Errorf("git diff --cached: %w", err)
		}
		return out, nil
	}
	root := strings.TrimSpace(string(rootOut))

	// Diff from root commit to HEAD — captures everything including agent commits
	diff := exec.Command("git", "diff", root+"..HEAD")
	diff.Dir = repoDir
	out, err := diff.Output()
	if err != nil {
		return nil, fmt.Errorf("git diff %s..HEAD: %w", shortHash(root), err)
	}
	return out, nil
}

// cleanupTmpDir removes a temp directory created during reconstruction.
// Docker containers can create root-owned files inside the workdir; if
// os.RemoveAll cannot remove them, we fall back to 'sudo -n rm -rf' (only
// when sudo exists on PATH). Failures are logged so leaks are visible.
func cleanupTmpDir(tmpDir string) {
	if err := os.RemoveAll(tmpDir); err == nil {
		return
	}
	if _, err := exec.LookPath("sudo"); err != nil {
		log.Printf("warning: cleanup of %s failed and sudo not available; leaking temp dir", tmpDir)
		return
	}
	if out, err := exec.Command("sudo", "-n", "rm", "-rf", tmpDir).CombinedOutput(); err != nil {
		log.Printf("warning: cleanup of %s failed: %s: %v", tmpDir, strings.TrimSpace(string(out)), err)
	}
}

// shortHash returns the first 8 characters of a commit hash, or the whole
// string if it is shorter. Used only for human-readable error messages, so
// it must never panic on unexpectedly short input.
func shortHash(h string) string {
	if len(h) <= 8 {
		return h
	}
	return h[:8]
}
