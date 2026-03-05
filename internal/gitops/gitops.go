package gitops

import (
	"fmt"
	"io"
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
				"core.",
			} {
				if strings.Contains(line, pattern) {
					skip = true
					break
				}
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
	cleanup := func() {
		// Docker containers create root-owned files; os.RemoveAll can't delete them.
		exec.Command("sudo", "rm", "-rf", tmpDir).Run()
	}

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

	// Create a temporary commit so all changes are reachable
	commit := exec.Command("git", "commit", "--allow-empty", "-m", "thunderdome-capture")
	commit.Dir = repoDir
	commit.CombinedOutput() // ignore error (nothing to commit is fine)

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
		return nil, fmt.Errorf("git diff %s..HEAD: %w", root[:8], err)
	}
	return out, nil
}
