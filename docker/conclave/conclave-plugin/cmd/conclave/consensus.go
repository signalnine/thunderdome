package main

import (
	"context"
	"fmt"
	"os"
	"time"

	"github.com/signalnine/conclave/internal/config"
	"github.com/signalnine/conclave/internal/consensus"
	gitpkg "github.com/signalnine/conclave/internal/git"
	"github.com/spf13/cobra"
)

var consensusCmd = &cobra.Command{
	Use:   "consensus",
	Short: "Multi-agent consensus analysis",
	Long:  "Two-stage consensus synthesis: parallel agent analysis, then chairman synthesis.",
	RunE:  runConsensus,
}

func init() {
	consensusCmd.Flags().String("mode", "", "Mode: code-review or general-prompt (required)")
	consensusCmd.Flags().String("base-sha", "", "Base commit SHA (code-review mode)")
	consensusCmd.Flags().String("head-sha", "", "Head commit SHA (code-review mode)")
	consensusCmd.Flags().String("description", "", "Change description (code-review mode)")
	consensusCmd.Flags().String("plan-file", "", "Path to implementation plan file")
	consensusCmd.Flags().String("prompt", "", "Question to analyze (general-prompt mode)")
	consensusCmd.Flags().String("context", "", "Additional context")
	consensusCmd.Flags().Int("stage1-timeout", 0, "Stage 1 timeout in seconds")
	consensusCmd.Flags().Int("stage2-timeout", 0, "Stage 2 timeout in seconds")
	consensusCmd.Flags().Bool("dry-run", false, "Validate arguments only")
	consensusCmd.Flags().Bool("debate", false, "Enable Stage 1.5 debate round between agents")
	consensusCmd.Flags().Int("debate-rounds", 1, "Number of debate rounds (max 2)")
	consensusCmd.Flags().Int("debate-timeout", 60, "Timeout in seconds per debate round")
	rootCmd.AddCommand(consensusCmd)
}

func runConsensus(cmd *cobra.Command, args []string) error {
	cfg := config.Load()
	mode, _ := cmd.Flags().GetString("mode")
	dryRun, _ := cmd.Flags().GetBool("dry-run")

	if mode == "" {
		return fmt.Errorf("--mode is required")
	}
	if mode != "code-review" && mode != "general-prompt" {
		return fmt.Errorf("invalid mode %q: must be code-review or general-prompt", mode)
	}

	// Override timeouts from flags
	if v, _ := cmd.Flags().GetInt("stage1-timeout"); v > 0 {
		cfg.Stage1Timeout = v
	}
	if v, _ := cmd.Flags().GetInt("stage2-timeout"); v > 0 {
		cfg.Stage2Timeout = v
	}

	// Debate flags
	debate, _ := cmd.Flags().GetBool("debate")
	debateRounds, _ := cmd.Flags().GetInt("debate-rounds")
	debateTimeout, _ := cmd.Flags().GetInt("debate-timeout")
	if debateRounds > 2 {
		debateRounds = 2
	}

	// Build stage 1 prompt and a description string used for debate chairman context
	var stage1Prompt string
	var chairmanBuilder func([]consensus.AgentResult) string
	var debateChairmanBuilder func([]consensus.AgentResult, []consensus.AgentResult) string

	if mode == "code-review" {
		baseSHA, _ := cmd.Flags().GetString("base-sha")
		headSHA, _ := cmd.Flags().GetString("head-sha")
		description, _ := cmd.Flags().GetString("description")
		planFile, _ := cmd.Flags().GetString("plan-file")

		if baseSHA == "" || headSHA == "" || description == "" {
			return fmt.Errorf("code-review mode requires --base-sha, --head-sha, --description")
		}

		if dryRun {
			fmt.Println("Dry run: Arguments validated successfully")
			fmt.Printf("Mode: %s\nBase SHA: %s\nHead SHA: %s\nDescription: %s\nDebate: %v\n", mode, baseSHA, headSHA, description, debate)
			return nil
		}

		g := gitpkg.New(".")
		diff, err := g.Diff(baseSHA, headSHA)
		if err != nil {
			return fmt.Errorf("git diff: %w", err)
		}
		files, _ := g.DiffNameOnly(baseSHA, headSHA)
		modifiedFiles := ""
		for _, f := range files {
			modifiedFiles += f + "\n"
		}
		var planContent string
		if planFile != "" {
			data, _ := os.ReadFile(planFile)
			planContent = string(data)
		}
		stage1Prompt = consensus.BuildCodeReviewPrompt(description, diff, modifiedFiles, planContent)
		chairmanBuilder = func(results []consensus.AgentResult) string {
			return consensus.BuildCodeReviewChairmanPrompt(description, modifiedFiles, results)
		}
		debateChairmanBuilder = func(results []consensus.AgentResult, rebuttals []consensus.AgentResult) string {
			return consensus.BuildDebateChairmanPrompt(description, results, rebuttals)
		}
	} else {
		prompt, _ := cmd.Flags().GetString("prompt")
		ctxStr, _ := cmd.Flags().GetString("context")
		if prompt == "" {
			return fmt.Errorf("general-prompt mode requires --prompt")
		}
		if dryRun {
			fmt.Println("Dry run: Arguments validated successfully")
			fmt.Printf("Mode: %s\nPrompt: %s\nDebate: %v\n", mode, prompt, debate)
			return nil
		}
		stage1Prompt = consensus.BuildGeneralPrompt(prompt, ctxStr)
		chairmanBuilder = func(results []consensus.AgentResult) string {
			return consensus.BuildGeneralChairmanPrompt(prompt, results)
		}
		debateChairmanBuilder = func(results []consensus.AgentResult, rebuttals []consensus.AgentResult) string {
			return consensus.BuildDebateChairmanPrompt(prompt, results, rebuttals)
		}
	}

	// Build agents
	agents := []consensus.Agent{
		consensus.NewClaudeAgent(cfg),
		consensus.NewGeminiAgent(cfg),
		consensus.NewCodexAgent(cfg),
	}

	// Run consensus (with or without debate)
	ctx := context.Background()
	var result *consensus.ConsensusResult
	var err error

	if debate {
		result, err = consensus.RunConsensusWithDebate(ctx, agents, agents, stage1Prompt, debateChairmanBuilder, cfg.Stage1Timeout, debateTimeout, cfg.Stage2Timeout, debateRounds)
	} else {
		result, err = consensus.RunConsensusWithBuilder(ctx, agents, agents, stage1Prompt, chairmanBuilder, cfg.Stage1Timeout, cfg.Stage2Timeout)
	}
	if err != nil {
		return err
	}

	// Write output file
	outputFile, err := os.CreateTemp("", "consensus-*.md")
	if err != nil {
		return err
	}
	debateLabel := ""
	if debate {
		debateLabel = fmt.Sprintf("\n**Debate:** %d round(s)", debateRounds)
	}
	fmt.Fprintf(outputFile, "# Multi-Agent Consensus Analysis\n\n**Mode:** %s\n**Date:** %s\n**Agents Succeeded:** %d/3\n**Chairman:** %s%s\n\n---\n\n",
		mode, time.Now().Format("2006-01-02 15:04:05"), result.AgentsSucceeded, result.ChairmanName, debateLabel)
	fmt.Fprintf(outputFile, "## Stage 2: Chairman Consensus (by %s)\n\n%s\n", result.ChairmanName, result.ChairmanOutput)
	outputFile.Close()

	// Print to stdout
	fmt.Fprintln(os.Stderr, "\n========================================")
	fmt.Fprintln(os.Stderr, "CONSENSUS COMPLETE")
	fmt.Fprintln(os.Stderr, "========================================")
	fmt.Println(result.ChairmanOutput)
	fmt.Fprintf(os.Stderr, "\nDetailed breakdown saved to: %s\n", outputFile.Name())
	return nil
}
