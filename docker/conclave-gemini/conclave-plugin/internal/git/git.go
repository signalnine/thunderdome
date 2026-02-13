package git

import (
	"fmt"
	"os/exec"
	"strings"
)

type Git struct {
	Dir string
}

func New(dir string) *Git {
	return &Git{Dir: dir}
}

func (g *Git) run(args ...string) (string, error) {
	cmd := exec.Command("git", args...)
	cmd.Dir = g.Dir
	out, err := cmd.CombinedOutput()
	if err != nil {
		return "", fmt.Errorf("git %s: %s %w", strings.Join(args, " "), string(out), err)
	}
	return strings.TrimSpace(string(out)), nil
}

func (g *Git) CurrentBranch() (string, error) {
	return g.run("rev-parse", "--abbrev-ref", "HEAD")
}

func (g *Git) RevParse(ref string) (string, error) {
	return g.run("rev-parse", ref)
}

func (g *Git) WorktreeAdd(path, branch, base string) error {
	_, err := g.run("worktree", "add", path, "-b", branch, base)
	return err
}

func (g *Git) WorktreeRemove(path string) error {
	_, err := g.run("worktree", "remove", path, "--force")
	return err
}

func (g *Git) WorktreePrune() error {
	_, err := g.run("worktree", "prune")
	return err
}

func (g *Git) MergeBase(a, b string) (string, error) {
	return g.run("merge-base", a, b)
}

func (g *Git) Diff(base, head string) (string, error) {
	return g.run("diff", base, head)
}

func (g *Git) DiffNameOnly(base, head string) ([]string, error) {
	out, err := g.run("diff", "--name-only", base, head)
	if err != nil {
		return nil, err
	}
	if out == "" {
		return nil, nil
	}
	return strings.Split(out, "\n"), nil
}

func (g *Git) MergeSquash(branch string) error {
	_, err := g.run("merge", "--squash", branch)
	return err
}

func (g *Git) MergeAbort() error {
	_, err := g.run("merge", "--abort")
	return err
}

func (g *Git) ResetHard(ref string) error {
	_, err := g.run("reset", "--hard", ref)
	return err
}

func (g *Git) Commit(msg string) error {
	_, err := g.run("commit", "-m", msg)
	return err
}

func (g *Git) CommitAllowEmpty(msg string) error {
	_, err := g.run("commit", "--allow-empty", "-m", msg)
	return err
}

func (g *Git) AddAll() error {
	_, err := g.run("add", "-A")
	return err
}

func (g *Git) Add(paths ...string) error {
	args := append([]string{"add"}, paths...)
	_, err := g.run(args...)
	return err
}

func (g *Git) CheckIgnore(path string) bool {
	_, err := g.run("check-ignore", "-q", path)
	return err == nil
}

func (g *Git) HasStagedChanges() bool {
	_, err := g.run("diff", "--cached", "--quiet")
	return err != nil // non-zero exit = there are changes
}

func (g *Git) TopLevel() (string, error) {
	return g.run("rev-parse", "--show-toplevel")
}

func (g *Git) CheckoutBranch(name string) error {
	_, err := g.run("checkout", name)
	return err
}

func (g *Git) CreateBranch(name string) error {
	_, err := g.run("checkout", "-b", name)
	return err
}

func (g *Git) Push(branch string) error {
	_, err := g.run("push", "-u", "origin", branch)
	return err
}

func (g *Git) StatusPorcelain() (string, error) {
	return g.run("status", "--porcelain")
}

func (g *Git) Log(format string, n int) (string, error) {
	return g.run("log", fmt.Sprintf("--format=%s", format), fmt.Sprintf("-n%d", n))
}
