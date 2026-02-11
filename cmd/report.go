package cmd

import (
	"fmt"

	"github.com/spf13/cobra"
)

var flagFormat string

func newReportCmd() *cobra.Command {
	cmd := &cobra.Command{
		Use:   "report [run-dir]",
		Short: "Generate summary from stored results",
		RunE: func(cmd *cobra.Command, args []string) error {
			fmt.Println("report: not yet implemented")
			return nil
		},
	}
	cmd.Flags().StringVar(&flagFormat, "format", "table", "output format (table, markdown, json)")
	return cmd
}
