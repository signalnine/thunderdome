package cmd

import (
	"fmt"
	"strings"
	"time"

	"github.com/signalnine/thunderdome/internal/config"
	"github.com/spf13/cobra"
)

var (
	flagOrchestrator string
	flagTask         string
	flagCategory     string
	flagTrials       int
	flagParallel     int
)

func newRunCmd() *cobra.Command {
	cmd := &cobra.Command{
		Use:   "run",
		Short: "Execute a benchmark run",
		RunE: func(cmd *cobra.Command, args []string) error {
			fmt.Println("run: not yet implemented")
			return nil
		},
	}
	cmd.Flags().StringVar(&flagOrchestrator, "orchestrator", "", "filter to a single orchestrator")
	cmd.Flags().StringVar(&flagTask, "task", "", "filter to a single task")
	cmd.Flags().StringVar(&flagCategory, "category", "", "filter by category")
	cmd.Flags().IntVar(&flagTrials, "trials", 0, "override trial count")
	cmd.Flags().IntVar(&flagParallel, "parallel", 1, "max concurrent containers")
	return cmd
}

func filterOrchestrators(orchs []config.Orchestrator, name string) []config.Orchestrator {
	if name == "" {
		return orchs
	}
	var filtered []config.Orchestrator
	for _, o := range orchs {
		if o.Name == name {
			filtered = append(filtered, o)
		}
	}
	return filtered
}

func filterTasks(tasks []config.Task, name, category string) []config.Task {
	var filtered []config.Task
	for _, t := range tasks {
		if name != "" && t.Repo != name && !strings.HasSuffix(t.Repo, "/"+name) {
			continue
		}
		if category != "" && !matchCategory(t.Category, category) {
			continue
		}
		filtered = append(filtered, t)
	}
	if len(filtered) == 0 && name == "" && category == "" {
		return tasks
	}
	return filtered
}

func matchCategory(category, pattern string) bool {
	if strings.HasSuffix(pattern, "/*") {
		prefix := strings.TrimSuffix(pattern, "/*")
		return strings.HasPrefix(category, prefix+"/")
	}
	return category == pattern
}

func timeoutForCategory(category string) time.Duration {
	switch {
	case strings.HasPrefix(category, "marathon"):
		return 60 * time.Minute
	case strings.Contains(category, "complex"):
		return 30 * time.Minute
	default:
		return 10 * time.Minute
	}
}
