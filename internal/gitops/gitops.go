package gitops

import (
	"fmt"
	"os/exec"
)

func CloneAndCheckout(repo, tag, dest string) error {
	cmd := exec.Command("git", "clone", "--branch", tag, "--depth", "1", repo, dest)
	if out, err := cmd.CombinedOutput(); err != nil {
		return fmt.Errorf("git clone: %s: %w", out, err)
	}
	return nil
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
