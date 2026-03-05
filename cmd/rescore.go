package cmd

import (
	"context"
	"fmt"
	"log"
	"os"
	"os/exec"
	"path/filepath"
	"strings"

	"github.com/signalnine/thunderdome/internal/config"
	"github.com/signalnine/thunderdome/internal/gitops"
	"github.com/signalnine/thunderdome/internal/result"
	"github.com/signalnine/thunderdome/internal/validation"
	"github.com/spf13/cobra"
)

var flagRescoreFull bool

func newRescoreCmd() *cobra.Command {
	cmd := &cobra.Command{
		Use:   "rescore [run-dir...]",
		Short: "Re-run validation and scoring on existing trial workspaces",
		Long: `Walks trial directories, reconstructs workspaces from v1 + diff.patch,
re-runs test validation, and updates meta.json scores.

By default, only re-runs tests (agent tests + hidden tests) and recomputes
composite scores, keeping existing lint/coverage/code_metrics scores.
Use --full to re-run the entire validation pipeline.`,
		RunE: runRescore,
	}
	cmd.Flags().BoolVar(&flagRescoreFull, "full", false, "re-run full validation pipeline (slower)")
	return cmd
}

func runRescore(cmd *cobra.Command, args []string) error {
	cfg, err := config.Load(cfgFile)
	if err != nil {
		return err
	}

	// Build task lookup by repo basename (e.g. "bench-phantom-invoice")
	taskByName := make(map[string]*config.Task)
	for i := range cfg.Tasks {
		t := &cfg.Tasks[i]
		name := filepath.Base(t.Repo)
		taskByName[name] = t
	}

	// Determine which run directories to scan
	var runDirs []string
	if len(args) > 0 {
		for _, a := range args {
			abs, err := filepath.Abs(a)
			if err != nil {
				return fmt.Errorf("resolving path %s: %w", a, err)
			}
			runDirs = append(runDirs, abs)
		}
	} else {
		runsDir, _ := filepath.Abs(filepath.Join(cfg.Results.Dir, "runs"))
		entries, err := os.ReadDir(runsDir)
		if err != nil {
			return fmt.Errorf("reading runs directory: %w", err)
		}
		for _, e := range entries {
			if e.IsDir() {
				runDirs = append(runDirs, filepath.Join(runsDir, e.Name()))
			}
		}
	}

	ctx := context.Background()
	var rescored, skipped, errored int

	for _, runDir := range runDirs {
		trialsDir := filepath.Join(runDir, "trials")
		if _, err := os.Stat(trialsDir); os.IsNotExist(err) {
			continue
		}

		orchEntries, _ := os.ReadDir(trialsDir)
		for _, oe := range orchEntries {
			if !oe.IsDir() {
				continue
			}
			taskEntries, _ := os.ReadDir(filepath.Join(trialsDir, oe.Name()))
			for _, te := range taskEntries {
				if !te.IsDir() {
					continue
				}
				taskName := te.Name()
				task, ok := taskByName[taskName]
				if !ok {
					continue
				}

				trialEntries, _ := os.ReadDir(filepath.Join(trialsDir, oe.Name(), taskName))
				for _, tre := range trialEntries {
					if !tre.IsDir() || !strings.HasPrefix(tre.Name(), "trial-") {
						continue
					}
					trialDir := filepath.Join(trialsDir, oe.Name(), taskName, tre.Name())

					diffPath := filepath.Join(trialDir, "diff.patch")
					if _, err := os.Stat(diffPath); os.IsNotExist(err) {
						skipped++
						continue
					}

					var err error
					if flagRescoreFull {
						err = rescoreFull(ctx, trialDir, task)
					} else {
						err = rescoreTestsOnly(ctx, trialDir, task)
					}
					if err != nil {
						log.Printf("error %s/%s/%s: %v", oe.Name(), taskName, tre.Name(), err)
						errored++
						continue
					}
					rescored++
					if rescored%25 == 0 {
						fmt.Printf("  progress: %d rescored, %d skipped, %d errors\n",
							rescored, skipped, errored)
					}
				}
			}
		}
	}

	fmt.Printf("Rescore complete: %d rescored, %d skipped, %d errors\n", rescored, skipped, errored)
	return nil
}

// rescoreTestsOnly re-runs only test commands and recomputes composite scores.
// Keeps existing lint, coverage, and code_metrics scores unchanged.
func rescoreTestsOnly(ctx context.Context, trialDir string, task *config.Task) error {
	meta, err := result.ReadTrialMeta(filepath.Join(trialDir, "meta.json"))
	if err != nil {
		return fmt.Errorf("reading meta: %w", err)
	}

	workDir, cleanup, err := reconstructToTempDir(trialDir, task)
	if err != nil {
		return err
	}
	defer cleanup()

	if task.Greenfield {
		// Re-run agent tests
		if task.TestCmd != "" {
			agentResult, err := validation.RunTests(ctx, workDir, task.ValidationImage, task.InstallCmd, task.TestCmd)
			if err != nil {
				log.Printf("  warning: agent tests: %v", err)
			} else {
				meta.Scores.AgentTests = agentResult.Score
			}
		}

		// Re-run hidden tests
		hiddenCleanup, err := validation.InjectHiddenTests(task.Repo, task.ValidationTag, workDir)
		if err != nil {
			log.Printf("  warning: inject hidden tests: %v", err)
		} else {
			defer hiddenCleanup()
			hiddenResult, err := validation.RunHiddenTests(ctx, workDir, task.ValidationImage, task.InstallCmd)
			if err != nil {
				log.Printf("  warning: hidden tests: %v", err)
			} else {
				meta.Scores.HiddenTests = hiddenResult.Score
			}
		}

		meta.CompositeScore = validation.GreenfieldCompositeScore(meta.Scores, task.GreenWeights)
	} else {
		// Standard task: re-run tests only
		testResult, err := validation.RunTests(ctx, workDir, task.ValidationImage, task.InstallCmd, task.TestCmd)
		if err != nil {
			log.Printf("  warning: tests: %v", err)
		} else {
			meta.Scores.Tests = testResult.Score
		}

		meta.CompositeScore = validation.CompositeScore(meta.Scores, task.Weights)
	}

	return result.WriteTrialMeta(trialDir, meta)
}

// rescoreFull re-runs the entire validation pipeline via runner.ValidateAndScore.
func rescoreFull(ctx context.Context, trialDir string, task *config.Task) error {
	workDir, cleanup, err := reconstructToTempDir(trialDir, task)
	if err != nil {
		return err
	}
	defer cleanup()

	// Point the trial workspace at our reconstructed dir
	wsDir := filepath.Join(trialDir, "workspace")
	exec.Command("sudo", "rm", "-rf", wsDir).Run()
	if err := os.Symlink(workDir, wsDir); err != nil {
		// Fall back to copy if symlink fails
		if err := gitops.CopyDir(workDir, wsDir); err != nil {
			return fmt.Errorf("setup workspace: %w", err)
		}
	}

	meta, err := result.ReadTrialMeta(filepath.Join(trialDir, "meta.json"))
	if err != nil {
		return fmt.Errorf("reading meta: %w", err)
	}

	if task.Greenfield {
		// Re-run full greenfield pipeline
		if task.TestCmd != "" {
			agentResult, err := validation.RunTests(ctx, wsDir, task.ValidationImage, task.InstallCmd, task.TestCmd)
			if err != nil {
				log.Printf("  warning: agent tests: %v", err)
			} else {
				meta.Scores.AgentTests = agentResult.Score
			}
		}
		coverageResult, err := validation.RunCoverage(ctx, wsDir, task.ValidationImage, task.InstallCmd)
		if err != nil {
			log.Printf("  warning: coverage: %v", err)
		} else {
			meta.Scores.Coverage = coverageResult.Score
		}
		metricsResult, err := validation.RunCodeMetrics(wsDir)
		if err != nil {
			log.Printf("  warning: code metrics: %v", err)
		} else {
			meta.Scores.CodeMetrics = metricsResult.Score
		}
		lintResult, err := validation.RunLint(ctx, wsDir, task.ValidationImage, task.LintCmd, 0)
		if err != nil {
			log.Printf("  warning: lint: %v", err)
		} else {
			meta.Scores.StaticAnalysis = lintResult.Score
		}
		hiddenCleanup, err := validation.InjectHiddenTests(task.Repo, task.ValidationTag, wsDir)
		if err != nil {
			log.Printf("  warning: inject hidden tests: %v", err)
		} else {
			defer hiddenCleanup()
			hiddenResult, err := validation.RunHiddenTests(ctx, wsDir, task.ValidationImage, task.InstallCmd)
			if err != nil {
				log.Printf("  warning: hidden tests: %v", err)
			} else {
				meta.Scores.HiddenTests = hiddenResult.Score
			}
		}
		meta.CompositeScore = validation.GreenfieldCompositeScore(meta.Scores, task.GreenWeights)
	} else {
		testResult, err := validation.RunTests(ctx, wsDir, task.ValidationImage, task.InstallCmd, task.TestCmd)
		if err != nil {
			log.Printf("  warning: tests: %v", err)
		} else {
			meta.Scores.Tests = testResult.Score
		}
		lintResult, err := validation.RunLint(ctx, wsDir, task.ValidationImage, task.LintCmd, 0)
		if err != nil {
			log.Printf("  warning: lint: %v", err)
		} else {
			meta.Scores.StaticAnalysis = lintResult.Score
		}
		meta.CompositeScore = validation.CompositeScore(meta.Scores, task.Weights)
	}

	return result.WriteTrialMeta(trialDir, meta)
}

// reconstructToTempDir clones v1 + applies diff.patch into a temp dir with npm install.
// Returns the temp dir path and a cleanup function.
func reconstructToTempDir(trialDir string, task *config.Task) (string, func(), error) {
	diff, err := os.ReadFile(filepath.Join(trialDir, "diff.patch"))
	if err != nil {
		return "", nil, fmt.Errorf("reading diff: %w", err)
	}

	repoAbs, err := filepath.Abs(task.Repo)
	if err != nil {
		return "", nil, fmt.Errorf("resolving repo: %w", err)
	}

	tmpDir, cleanup, err := gitops.ReconstructFromDiff(repoAbs, task.Tag, diff)
	if err != nil {
		return "", nil, fmt.Errorf("reconstruct: %w", err)
	}

	return tmpDir, cleanup, nil
}
