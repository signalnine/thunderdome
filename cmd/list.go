package cmd

import (
	"fmt"

	"github.com/signalnine/thunderdome/internal/config"
	"github.com/spf13/cobra"
)

func newListCmd() *cobra.Command {
	return &cobra.Command{
		Use:   "list",
		Short: "List available tasks and orchestrators",
		RunE: func(cmd *cobra.Command, args []string) error {
			cfg, err := config.Load(cfgFile)
			if err != nil {
				return err
			}
			fmt.Println("Orchestrators:")
			for _, o := range cfg.Orchestrators {
				fmt.Printf("  - %s (image: %s)\n", o.Name, o.Image)
			}
			fmt.Println("\nTasks:")
			for _, t := range cfg.Tasks {
				fmt.Printf("  - %s@%s [%s]\n", t.Repo, t.Tag, t.Category)
			}
			return nil
		},
	}
}
