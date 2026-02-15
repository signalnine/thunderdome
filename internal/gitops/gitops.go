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

// CaptureChanges stages all changes (including untracked files) and returns the diff.
func CaptureChanges(repoDir string) ([]byte, error) {
	add := exec.Command("git", "add", "-A")
	add.Dir = repoDir
	if out, err := add.CombinedOutput(); err != nil {
		return nil, fmt.Errorf("git add -A: %s: %w", out, err)
	}
	diff := exec.Command("git", "diff", "--cached")
	diff.Dir = repoDir
	out, err := diff.Output()
	if err != nil {
		return nil, fmt.Errorf("git diff --cached: %w", err)
	}
	return out, nil
}
