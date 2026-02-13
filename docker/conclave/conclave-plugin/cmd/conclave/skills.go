package main

import (
	"fmt"
	"os"
	"path/filepath"

	"github.com/signalnine/conclave/internal/skills"
	"github.com/spf13/cobra"
)

var skillsCmd = &cobra.Command{
	Use:   "skills",
	Short: "Manage and discover skills",
}

var skillsListCmd = &cobra.Command{
	Use:   "list",
	Short: "List all available skills",
	RunE:  runSkillsList,
}

var skillsResolveCmd = &cobra.Command{
	Use:   "resolve [name]",
	Short: "Resolve a skill by name",
	Args:  cobra.ExactArgs(1),
	RunE:  runSkillsResolve,
}

func init() {
	skillsCmd.AddCommand(skillsListCmd)
	skillsCmd.AddCommand(skillsResolveCmd)
	rootCmd.AddCommand(skillsCmd)
}

func runSkillsList(cmd *cobra.Command, args []string) error {
	pluginRoot := findPluginRoot()
	if pluginRoot == "" {
		return fmt.Errorf("could not find plugin root")
	}

	conclaveSkillsDir := filepath.Join(pluginRoot, "skills")
	discovered := skills.Discover(conclaveSkillsDir)

	// Also check personal skills
	home, _ := os.UserHomeDir()
	if home != "" {
		personalDir := filepath.Join(home, ".claude", "skills")
		personalSkills := skills.Discover(personalDir)
		for i := range personalSkills {
			personalSkills[i].Source = "personal"
		}
		discovered = append(discovered, personalSkills...)
	}

	if len(discovered) == 0 {
		fmt.Println("No skills found.")
		return nil
	}

	fmt.Printf("%-30s %-10s %s\n", "NAME", "SOURCE", "DESCRIPTION")
	fmt.Printf("%-30s %-10s %s\n", "----", "------", "-----------")
	for _, s := range discovered {
		source := s.Source
		if source == "" {
			source = "conclave"
		}
		desc := s.Description
		if len(desc) > 60 {
			desc = desc[:57] + "..."
		}
		fmt.Printf("%-30s %-10s %s\n", s.Name, source, desc)
	}
	return nil
}

func runSkillsResolve(cmd *cobra.Command, args []string) error {
	pluginRoot := findPluginRoot()
	if pluginRoot == "" {
		return fmt.Errorf("could not find plugin root")
	}

	conclaveSkillsDir := filepath.Join(pluginRoot, "skills")
	home, _ := os.UserHomeDir()
	var personalDir string
	if home != "" {
		personalDir = filepath.Join(home, ".claude", "skills")
	}

	s := skills.Resolve(args[0], personalDir, conclaveSkillsDir)
	if s == nil {
		return fmt.Errorf("skill %q not found", args[0])
	}

	content, err := os.ReadFile(s.SkillFile)
	if err != nil {
		return fmt.Errorf("reading skill: %w", err)
	}

	fmt.Printf("Name: %s\nSource: %s\nPath: %s\n\n", s.Name, s.Source, s.Path)
	fmt.Println(string(content))
	return nil
}
