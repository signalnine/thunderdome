package cmd

import (
	"context"
	"encoding/json"
	"fmt"
	"log"
	"os"
	"path/filepath"
	"strings"

	"github.com/signalnine/thunderdome/internal/config"
	"github.com/signalnine/thunderdome/internal/gateway"
	"github.com/signalnine/thunderdome/internal/gitops"
	"github.com/signalnine/thunderdome/internal/result"
	"github.com/signalnine/thunderdome/internal/validation"
	"github.com/spf13/cobra"
)

func newValidateCmd() *cobra.Command {
	return &cobra.Command{
		Use:   "validate [run-dir]",
		Short: "Re-score an existing result",
		Long:  "Walk a run directory and re-run the rubric judge on each trial's diff.patch, updating meta.json with new rubric and composite scores.",
		Args:  cobra.ExactArgs(1),
		RunE: func(cmd *cobra.Command, args []string) error {
			runDir := args[0]
			cfgPath, _ := cmd.Flags().GetString("config")
			cfg, err := config.Load(cfgPath)
			if err != nil {
				return fmt.Errorf("loading config: %w", err)
			}

			// Load secrets into process env so rubric judge can use ANTHROPIC_API_KEY
			if cfg.Secrets.EnvFile != "" {
				secrets, err := gateway.ParseEnvFile(cfg.Secrets.EnvFile)
				if err != nil {
					log.Printf("warning: could not load secrets: %v", err)
				} else {
					for k, v := range secrets {
						if os.Getenv(k) == "" {
							os.Setenv(k, v)
						}
					}
				}
			}

			if cfg.Proxy.JudgeModel != "" {
				validation.JudgeModel = cfg.Proxy.JudgeModel
			}

			// Build task lookup by TaskName (filepath.Base of repo)
			taskByName := make(map[string]*config.Task)
			for i := range cfg.Tasks {
				t := &cfg.Tasks[i]
				name := filepath.Base(t.Repo)
				taskByName[name] = t
			}

			// Find all meta.json files under the run directory
			var metaFiles []string
			err = filepath.Walk(runDir, func(path string, info os.FileInfo, err error) error {
				if err != nil {
					return nil
				}
				if info.Name() == "meta.json" {
					metaFiles = append(metaFiles, path)
				}
				return nil
			})
			if err != nil {
				return fmt.Errorf("walking run dir: %w", err)
			}

			if len(metaFiles) == 0 {
				return fmt.Errorf("no meta.json files found in %s", runDir)
			}

			ctx := context.Background()

			for _, metaPath := range metaFiles {
				trialDir := filepath.Dir(metaPath)
				meta, err := result.ReadTrialMeta(metaPath)
				if err != nil {
					log.Printf("skipping %s: %v", metaPath, err)
					continue
				}

				task, ok := taskByName[meta.Task]
				if !ok {
					log.Printf("skipping %s: task %q not found in config", metaPath, meta.Task)
					continue
				}

				if len(task.Rubric) == 0 {
					log.Printf("skipping %s: no rubric criteria defined for task %q", metaPath, meta.Task)
					continue
				}

				// Read diff and task description
				diff, err := os.ReadFile(filepath.Join(trialDir, "diff.patch"))
				if err != nil {
					log.Printf("skipping %s: %v", metaPath, err)
					continue
				}
				if len(strings.TrimSpace(string(diff))) == 0 {
					log.Printf("skipping %s: empty diff", metaPath)
					continue
				}

				taskDesc, _ := os.ReadFile(filepath.Join(trialDir, "task.md"))
				workDir := filepath.Join(trialDir, "workspace")

				fmt.Printf("Scoring %s/%s (trial %d)...\n", meta.Orchestrator, meta.Task, meta.Trial)

				// Build judge input with context
				judgeInput := validation.RubricJudgeInput{
					Rubric:    task.Rubric,
					Diff:      string(diff),
					TaskDesc:  string(taskDesc),
					Category:  task.Category,
					TestScore: meta.Scores.Tests,
					LintScore: meta.Scores.StaticAnalysis,
				}

				// For greenfield tasks, collect source files
				if task.Greenfield {
					sourceDir := workDir
					// If workspace is gone, reconstruct from v1 + diff
					if _, err := os.Stat(filepath.Join(workDir, "src")); os.IsNotExist(err) {
						repoAbs, _ := filepath.Abs(task.Repo)
						tmpDir, cleanup, err := gitops.ReconstructFromDiff(repoAbs, task.Tag, diff)
						if err != nil {
							log.Printf("  warning: could not reconstruct workspace: %v", err)
						} else {
							defer cleanup()
							sourceDir = tmpDir
						}
					}
					judgeInput.SourceFiles = validation.CollectSourceFiles(sourceDir, 100_000)
					judgeInput.TestScore = meta.Scores.HiddenTests
				}

				rubricScores, err := validation.RunRubricJudge(ctx, "", judgeInput)
				if err != nil {
					log.Printf("  rubric judge failed: %v", err)
					continue
				}

				rubricScore := validation.ComputeRubricScore(task.Rubric, rubricScores)
				oldComposite := meta.CompositeScore
				oldRubric := meta.Scores.Rubric

				meta.Scores.Rubric = rubricScore
				meta.RubricScores = rubricScores
				if task.Greenfield {
					meta.CompositeScore = validation.GreenfieldCompositeScore(meta.Scores, task.GreenWeights)
				} else {
					meta.CompositeScore = validation.CompositeScore(meta.Scores, task.Weights)
				}

				// Write updated meta
				if err := result.WriteTrialMeta(trialDir, meta); err != nil {
					log.Printf("  failed to write meta: %v", err)
					continue
				}

				// Pretty-print per-criterion scores
				scoresJSON, _ := json.Marshal(rubricScores)
				fmt.Printf("  rubric: %.2f → %.2f  %s\n", oldRubric, rubricScore, string(scoresJSON))
				fmt.Printf("  composite: %.2f → %.2f\n", oldComposite, meta.CompositeScore)
			}

			return nil
		},
	}
}
