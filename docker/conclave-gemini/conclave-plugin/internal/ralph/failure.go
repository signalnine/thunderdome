package ralph

import (
	"fmt"
	"os"
	"time"

	gitpkg "github.com/signalnine/conclave/internal/git"
)

func BranchFailedWork(g *gitpkg.Git, taskID string, state *State) error {
	timestamp := time.Now().Format("20060102-150405")
	branchName := fmt.Sprintf("wip/ralph-fail-%s-%s", taskID, timestamp)

	currentBranch, err := g.CurrentBranch()
	if err != nil {
		return fmt.Errorf("not in a git repository: %w", err)
	}

	// Safety: don't reset protected branches
	if currentBranch == "main" || currentBranch == "master" {
		g.CreateBranch(branchName)
		g.AddAll()
		msg := fmt.Sprintf("Ralph Loop failed: %s (on %s)", taskID, currentBranch)
		g.CommitAllowEmpty(msg)
		g.CheckoutBranch(currentBranch)
		fmt.Fprintf(os.Stderr, "Failed work preserved in branch: %s\n", branchName)
		return nil
	}

	if err := g.CreateBranch(branchName); err != nil {
		// Branch may exist, add timestamp suffix
		branchName = fmt.Sprintf("%s-%d", branchName, time.Now().Unix())
		if err := g.CreateBranch(branchName); err != nil {
			return err
		}
	}

	g.AddAll()
	msg := fmt.Sprintf("Ralph Loop failed: %s\n\nIterations: %d/%d\nLast gate: %s\nError hash: %s",
		taskID, state.Iteration, state.MaxIterations, state.LastGate, state.ErrorHash)
	g.CommitAllowEmpty(msg)
	g.Push(branchName) // non-fatal if no remote

	g.CheckoutBranch(currentBranch)
	fmt.Fprintf(os.Stderr, "Failed work preserved in branch: %s\n", branchName)
	return nil
}
