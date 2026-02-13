package main

import (
	"fmt"
	"os"
	"strings"

	gitpkg "github.com/signalnine/conclave/internal/git"
	"github.com/spf13/cobra"
)

var autoReviewCmd = &cobra.Command{
	Use:   "auto-review [description]",
	Short: "Auto-detect SHAs and run consensus code review",
	Long:  "Convenience wrapper that auto-detects base/head SHAs from git history, then runs consensus code review.",
	Args:  cobra.MinimumNArgs(1),
	RunE:  runAutoReview,
}

func init() {
	autoReviewCmd.Flags().String("base-sha", "", "Override base SHA (default: auto-detect from origin/main)")
	autoReviewCmd.Flags().String("head-sha", "", "Override head SHA (default: HEAD)")
	autoReviewCmd.Flags().String("plan-file", "", "Path to implementation plan file")
	autoReviewCmd.Flags().Bool("debate", false, "Enable Stage 1.5 debate round between agents")
	autoReviewCmd.Flags().Int("debate-rounds", 1, "Number of debate rounds (max 2)")
	autoReviewCmd.Flags().Int("debate-timeout", 60, "Timeout in seconds per debate round")
	rootCmd.AddCommand(autoReviewCmd)
}

func runAutoReview(cmd *cobra.Command, args []string) error {
	description := strings.Join(args, " ")
	g := gitpkg.New(".")

	baseSHA, _ := cmd.Flags().GetString("base-sha")
	headSHA, _ := cmd.Flags().GetString("head-sha")

	if headSHA == "" {
		var err error
		headSHA, err = g.RevParse("HEAD")
		if err != nil {
			return fmt.Errorf("failed to get HEAD: %w", err)
		}
	}

	if baseSHA == "" {
		// Try origin/main first, fall back to main
		var err error
		baseSHA, err = g.MergeBase("origin/main", headSHA)
		if err != nil {
			baseSHA, err = g.MergeBase("main", headSHA)
			if err != nil {
				baseSHA, err = g.MergeBase("origin/master", headSHA)
				if err != nil {
					baseSHA, err = g.MergeBase("master", headSHA)
					if err != nil {
						return fmt.Errorf("could not determine base SHA: %w", err)
					}
				}
			}
		}
	}

	shortBase := baseSHA
	if len(shortBase) > 8 {
		shortBase = shortBase[:8]
	}
	shortHead := headSHA
	if len(shortHead) > 8 {
		shortHead = shortHead[:8]
	}
	fmt.Fprintf(os.Stderr, "Auto-review: base=%s head=%s\n", shortBase, shortHead)

	// Set flags on consensus command and run it directly
	planFile, _ := cmd.Flags().GetString("plan-file")
	consensusCmd.Flags().Set("mode", "code-review")
	consensusCmd.Flags().Set("base-sha", baseSHA)
	consensusCmd.Flags().Set("head-sha", headSHA)
	consensusCmd.Flags().Set("description", description)
	if planFile != "" {
		consensusCmd.Flags().Set("plan-file", planFile)
	}

	// Pass through debate flags
	debate, _ := cmd.Flags().GetBool("debate")
	if debate {
		consensusCmd.Flags().Set("debate", "true")
	}
	debateRounds, _ := cmd.Flags().GetInt("debate-rounds")
	consensusCmd.Flags().Set("debate-rounds", fmt.Sprintf("%d", debateRounds))
	debateTimeout, _ := cmd.Flags().GetInt("debate-timeout")
	consensusCmd.Flags().Set("debate-timeout", fmt.Sprintf("%d", debateTimeout))

	return runConsensus(consensusCmd, nil)
}
