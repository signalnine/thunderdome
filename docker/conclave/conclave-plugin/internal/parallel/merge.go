package parallel

import (
	"fmt"

	gitpkg "github.com/signalnine/conclave/internal/git"
)

func MergeTaskBranch(g *gitpkg.Git, branch string, taskID int, taskName string) error {
	fmt.Printf("[MERGE] Squash-merging %s...\n", branch)

	if err := g.MergeSquash(branch); err != nil {
		fmt.Printf("[MERGE] CONFLICT in %s - aborting merge\n", branch)
		g.MergeAbort()
		return fmt.Errorf("merge conflict in %s", branch)
	}

	if !g.HasStagedChanges() {
		fmt.Printf("[MERGE] No changes to merge from %s\n", branch)
		return nil
	}

	msg := fmt.Sprintf("Task %d: %s", taskID, taskName)
	if err := g.Commit(msg); err != nil {
		return err
	}
	fmt.Printf("[MERGE] Successfully merged %s\n", branch)
	return nil
}
