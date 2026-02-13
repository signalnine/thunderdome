package cmd

import (
	"context"
	"fmt"
	"os"
	"os/exec"
	"strings"
	"time"

	"github.com/signalnine/thunderdome/internal/config"
	"github.com/signalnine/thunderdome/internal/gateway"
	"github.com/signalnine/thunderdome/internal/report"
	"github.com/signalnine/thunderdome/internal/result"
	"github.com/signalnine/thunderdome/internal/runner"
	"github.com/spf13/cobra"
)

var (
	flagOrchestrator      string
	flagTask              string
	flagCategory          string
	flagTrials            int
	flagParallel          int
	flagCleanupAggressive bool
)

func newRunCmd() *cobra.Command {
	cmd := &cobra.Command{
		Use:   "run",
		Short: "Execute a benchmark run",
		RunE:  runBenchmark,
	}
	cmd.Flags().StringVar(&flagOrchestrator, "orchestrator", "", "filter to a single orchestrator")
	cmd.Flags().StringVar(&flagTask, "task", "", "filter to a single task")
	cmd.Flags().StringVar(&flagCategory, "category", "", "filter by category")
	cmd.Flags().IntVar(&flagTrials, "trials", 0, "override trial count")
	cmd.Flags().IntVar(&flagParallel, "parallel", 1, "max concurrent containers")
	cmd.Flags().BoolVar(&flagCleanupAggressive, "cleanup-aggressive", false, "remove all thunderdome Docker artifacts after run")
	return cmd
}

func runBenchmark(cmd *cobra.Command, args []string) error {
	cfg, err := config.Load(cfgFile)
	if err != nil {
		return err
	}
	if flagTrials > 0 {
		cfg.Trials = flagTrials
	}

	// Expand ${VAR} references in orchestrator env from secrets file
	// Also set secrets in process env so the rubric judge can access API keys
	if cfg.Secrets.EnvFile != "" {
		secrets, err := gateway.ParseEnvFile(cfg.Secrets.EnvFile)
		if err != nil {
			return fmt.Errorf("reading secrets: %w", err)
		}
		for k, v := range secrets {
			if os.Getenv(k) == "" {
				os.Setenv(k, v)
			}
		}
		expandOrchEnv(cfg.Orchestrators, secrets)
	}

	orchestrators := filterOrchestrators(cfg.Orchestrators, flagOrchestrator)
	tasks := filterTasks(cfg.Tasks, flagTask, flagCategory)

	runDir, err := result.CreateRunDir(cfg.Results.Dir)
	if err != nil {
		return err
	}
	fmt.Printf("Run directory: %s\n", runDir)

	ctx := context.Background()

	var gw *gateway.Gateway
	var gwAddr string
	if cfg.Proxy.Gateway != "" && cfg.Proxy.Gateway != "none" {
		gw, err = gateway.Start(ctx, &gateway.StartOpts{
			SecretsEnvFile: cfg.Secrets.EnvFile,
			LogDir:         cfg.Proxy.LogDir,
			BudgetUSD:      cfg.Proxy.BudgetPerTrialUSD,
		})
		if err != nil {
			fmt.Printf("WARNING: gateway failed to start: %v (proceeding without proxy)\n", err)
		} else {
			defer gw.Stop()
			gwAddr = fmt.Sprintf("localhost:%d", gw.Port)
		}
	}

	gwURL := ""
	if gw != nil {
		gwURL = gw.URL()
	}

	if flagParallel > 1 {
		var jobs []runner.Job
		for _, orch := range orchestrators {
			for _, task := range tasks {
				for trial := 1; trial <= cfg.Trials; trial++ {
					orch, task, trial := orch, task, trial
					jobs = append(jobs, func() error {
						fmt.Printf("Running %s × %s (trial %d/%d)...\n", orch.Name, task.Category, trial, cfg.Trials)
						meta, err := runner.RunTrial(ctx, &runner.TrialOpts{
							Orchestrator:  &orch,
							Task:          &task,
							TrialNum:      trial,
							GatewayURL:    gwURL,
							GatewayAddr:   gwAddr,
							RunDir:        runDir,
							Timeout:       timeoutForTask(&task),
							Allowlist:     cfg.Network.Allowlist,
							GatewayLogDir: cfg.Proxy.LogDir,
						})
						if err != nil {
							return err
						}
						trialDir := result.TrialDir(runDir, orch.Name, runner.TaskName(&task), trial)
						scored, err := runner.ValidateAndScore(ctx, trialDir, &task, gwURL)
						if err != nil {
							fmt.Printf("  WARNING: validation failed for %s trial %d: %v\n", task.Category, trial, err)
							fmt.Printf("  %s (duration: %ds)\n", meta.ExitReason, meta.DurationS)
						} else {
							fmt.Printf("  %s (duration: %ds, score: %.2f)\n", meta.ExitReason, meta.DurationS, scored.CompositeScore)
						}
						return nil
					})
				}
			}
		}
		errs := runner.RunPool(flagParallel, jobs)
		for _, err := range errs {
			fmt.Printf("  ERROR: %v\n", err)
		}
	} else {
		for _, orch := range orchestrators {
			for _, task := range tasks {
				for trial := 1; trial <= cfg.Trials; trial++ {
					fmt.Printf("Running %s × %s (trial %d/%d)...\n", orch.Name, task.Category, trial, cfg.Trials)
					meta, err := runner.RunTrial(ctx, &runner.TrialOpts{
						Orchestrator:  &orch,
						Task:          &task,
						TrialNum:      trial,
						GatewayURL:    gwURL,
						GatewayAddr:   gwAddr,
						GatewayLogDir: cfg.Proxy.LogDir,
						RunDir:        runDir,
						Timeout:       timeoutForTask(&task),
						Allowlist:     cfg.Network.Allowlist,
					})
					if err != nil {
						fmt.Printf("  ERROR: %v\n", err)
						continue
					}
					trialDir := result.TrialDir(runDir, orch.Name, runner.TaskName(&task), trial)
					scored, err := runner.ValidateAndScore(ctx, trialDir, &task, gwURL)
					if err != nil {
						fmt.Printf("  WARNING: validation failed for %s trial %d: %v\n", task.Category, trial, err)
						fmt.Printf("  %s (duration: %ds)\n", meta.ExitReason, meta.DurationS)
					} else {
						fmt.Printf("  %s (duration: %ds, score: %.2f)\n", meta.ExitReason, meta.DurationS, scored.CompositeScore)
					}
				}
			}
		}
	}

	if flagCleanupAggressive {
		cleanupDocker()
	}

	fmt.Println("\n--- Results ---")
	return report.Generate(runDir, "table", os.Stdout)
}

func cleanupDocker() {
	// Best-effort cleanup of thunderdome-labeled containers and images
	fmt.Println("Cleaning up Docker artifacts...")
	run := func(args ...string) {
		cmd := newExecCmd(args...)
		cmd.Run()
	}
	run("docker", "container", "prune", "-f", "--filter", "label=thunderdome=true")
	run("docker", "image", "prune", "-f")
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
	if name == "" && category == "" {
		return tasks
	}
	var filtered []config.Task
	for _, t := range tasks {
		if name != "" && t.ID != name && t.Repo != name && !strings.HasSuffix(t.Repo, "/"+name) {
			continue
		}
		if category != "" && !matchCategory(t.Category, category) {
			continue
		}
		filtered = append(filtered, t)
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

func timeoutForTask(task *config.Task) time.Duration {
	if task.TimeLimitMinutes > 0 {
		return time.Duration(task.TimeLimitMinutes) * time.Minute
	}
	// Fallback: infer from category
	switch {
	case strings.HasPrefix(task.Category, "marathon"):
		return 60 * time.Minute
	case strings.Contains(task.Category, "complex"):
		return 30 * time.Minute
	default:
		return 10 * time.Minute
	}
}

func expandOrchEnv(orchs []config.Orchestrator, secrets map[string]string) {
	for i := range orchs {
		for k, v := range orchs[i].Env {
			orchs[i].Env[k] = os.Expand(v, func(key string) string {
				if val, ok := secrets[key]; ok {
					return val
				}
				return os.Getenv(key)
			})
		}
	}
}

func newExecCmd(args ...string) *exec.Cmd {
	return exec.Command(args[0], args[1:]...)
}
