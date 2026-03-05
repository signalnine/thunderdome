package cmd

import (
	"context"
	"fmt"
	"log"
	"os"
	"path/filepath"
	"strings"

	"github.com/signalnine/thunderdome/internal/config"
	"github.com/signalnine/thunderdome/internal/runner"
	"github.com/spf13/cobra"
)

func newRescoreCmd() *cobra.Command {
	cmd := &cobra.Command{
		Use:   "rescore [run-dir...]",
		Short: "Re-run validation and scoring on existing trial workspaces",
		Long:  "Walks trial directories, re-runs test/lint validation, and updates meta.json scores. Skips trials without a workspace directory.",
		RunE:  runRescore,
	}
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
		// Default: all run directories
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

		// Walk: trials/<orch>/<task>/trial-N/
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
					workDir := filepath.Join(trialDir, "workspace")

					if _, err := os.Stat(workDir); os.IsNotExist(err) {
						skipped++
						continue
					}

					_, err := runner.ValidateAndScore(ctx, trialDir, task, "")
					if err != nil {
						log.Printf("error rescoring %s: %v", trialDir, err)
						errored++
						continue
					}
					rescored++
				}
			}
		}
	}

	fmt.Printf("Rescore complete: %d rescored, %d skipped (no workspace), %d errors\n", rescored, skipped, errored)
	return nil
}
