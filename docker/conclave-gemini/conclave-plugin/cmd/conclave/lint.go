package main

import (
	"fmt"
	"os"
	"path/filepath"
	"strings"

	gitpkg "github.com/signalnine/conclave/internal/git"
	"github.com/signalnine/conclave/internal/lint"
	"github.com/signalnine/conclave/internal/skills"
	"github.com/spf13/cobra"
)

var lintCmd = &cobra.Command{
	Use:   "lint [paths...]",
	Short: "Validate SKILL.md files and plan filenames",
	Long:  "Checks SKILL.md files against authoring standards (frontmatter, naming, word count, cross-references) and validates docs/plans/ filenames.",
	RunE:  runLint,
}

func init() {
	lintCmd.Flags().Bool("json", false, "Output results as JSON")
	lintCmd.Flags().Int("word-limit", lint.DefaultWordLimit, "Word count warning threshold")
	rootCmd.AddCommand(lintCmd)
}

func runLint(cmd *cobra.Command, args []string) error {
	jsonOutput, _ := cmd.Flags().GetBool("json")
	wordLimit, _ := cmd.Flags().GetInt("word-limit")

	// Find repo root
	g := gitpkg.New(".")
	root, err := g.TopLevel()
	if err != nil {
		root = "."
	}

	// Discover all known skills for cross-ref and duplicate checking
	skillsDir := filepath.Join(root, "skills")
	allSkills := skills.Discover(skillsDir)
	knownNames := make([]string, len(allSkills))
	for i, s := range allSkills {
		knownNames[i] = s.Name
	}

	// Determine what to lint
	var skillPaths []string
	var plansDir string

	if len(args) == 0 {
		// Default: scan skills/ and docs/plans/
		for _, s := range allSkills {
			skillPaths = append(skillPaths, s.SkillFile)
		}
		plansDir = filepath.Join(root, "docs", "plans")
	} else {
		for _, arg := range args {
			info, err := os.Stat(arg)
			if err != nil {
				return fmt.Errorf("path %q: %w", arg, err)
			}
			if info.IsDir() {
				if strings.HasSuffix(filepath.Clean(arg), filepath.Join("docs", "plans")) || strings.HasSuffix(filepath.Clean(arg), "plans") {
					plansDir = arg
				} else {
					// Treat as skills directory — find SKILL.md files
					dirSkills := skills.Discover(arg)
					for _, s := range dirSkills {
						skillPaths = append(skillPaths, s.SkillFile)
					}
				}
			} else if strings.HasSuffix(arg, "SKILL.md") {
				skillPaths = append(skillPaths, arg)
			}
		}
	}

	// Run linting
	result := &lint.Result{}

	if len(skillPaths) > 0 {
		skillResult, err := lint.LintSkillsWithOptions(skillPaths, knownNames, lint.LintOptions{WordLimit: wordLimit})
		if err != nil {
			return fmt.Errorf("lint skills: %w", err)
		}
		result.Merge(skillResult)
	}

	if plansDir != "" {
		planResult, err := lint.LintPlanFilenames(plansDir)
		if err != nil {
			return fmt.Errorf("lint plans: %w", err)
		}
		result.Merge(planResult)
	}

	// Output
	if jsonOutput {
		out, err := result.FormatJSON()
		if err != nil {
			return err
		}
		fmt.Print(out)
	} else if len(result.Findings) > 0 {
		fmt.Print(result.FormatText())
	}

	if result.HasErrors() {
		cmd.SilenceUsage = true
		os.Exit(1)
	}
	return nil
}
