package cmd

import (
	"github.com/spf13/cobra"
)

var cfgFile string

func NewRootCmd() *cobra.Command {
	root := &cobra.Command{
		Use:   "thunderdome",
		Short: "Benchmark harness for agentic coding orchestrators",
	}
	root.PersistentFlags().StringVar(&cfgFile, "config", "thunderdome.yaml", "config file path")
	root.AddCommand(newRunCmd())
	root.AddCommand(newListCmd())
	root.AddCommand(newReportCmd())
	root.AddCommand(newValidateCmd())
	return root
}
