package main

import (
	"fmt"
	"os"

	"github.com/spf13/cobra"
)

var rootCmd = &cobra.Command{
	Use:   "conclave",
	Short: "Multi-agent consensus development system",
	Long:  "Conclave orchestrates a council of AI reviewers (Claude, Gemini, Codex) for consensus-based development.",
}

func Execute() {
	if err := rootCmd.Execute(); err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
}
