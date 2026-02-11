package cmd

import (
	"fmt"
	"os"
	"path/filepath"

	"github.com/signalnine/thunderdome/internal/config"
	"github.com/signalnine/thunderdome/internal/report"
	"github.com/spf13/cobra"
)

var flagFormat string

func newReportCmd() *cobra.Command {
	cmd := &cobra.Command{
		Use:   "report [run-dir]",
		Short: "Generate summary from stored results",
		RunE: func(cmd *cobra.Command, args []string) error {
			cfg, err := config.Load(cfgFile)
			if err != nil {
				return err
			}
			runDir := filepath.Join(cfg.Results.Dir, "latest")
			if len(args) > 0 {
				runDir = args[0]
			}
			resolved, err := filepath.EvalSymlinks(runDir)
			if err != nil {
				return fmt.Errorf("resolving run dir: %w", err)
			}
			return report.Generate(resolved, flagFormat, os.Stdout)
		},
	}
	cmd.Flags().StringVar(&flagFormat, "format", "table", "output format (table, markdown, json)")
	return cmd
}
