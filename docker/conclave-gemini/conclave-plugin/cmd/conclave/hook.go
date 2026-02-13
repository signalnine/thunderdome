package main

import (
	"fmt"
	"os"
	"path/filepath"

	"github.com/signalnine/conclave/internal/hook"
	"github.com/spf13/cobra"
)

var hookCmd = &cobra.Command{
	Use:   "hook",
	Short: "Hook handlers for Claude Code integration",
}

var hookSessionStartCmd = &cobra.Command{
	Use:   "session-start",
	Short: "Handle SessionStart hook event",
	RunE:  runHookSessionStart,
}

func init() {
	hookCmd.AddCommand(hookSessionStartCmd)
	rootCmd.AddCommand(hookCmd)
}

func runHookSessionStart(cmd *cobra.Command, args []string) error {
	// Find plugin root - look for .claude-plugin directory
	pluginRoot := findPluginRoot()
	if pluginRoot == "" {
		return fmt.Errorf("could not find plugin root (no .claude-plugin directory found)")
	}

	output, err := hook.SessionStart(pluginRoot)
	if err != nil {
		return err
	}

	fmt.Print(output)
	return nil
}

func findPluginRoot() string {
	// Check if CLAUDE_PLUGIN_ROOT is set
	if root := os.Getenv("CLAUDE_PLUGIN_ROOT"); root != "" {
		return root
	}

	// Walk up from executable location
	exe, err := os.Executable()
	if err == nil {
		dir := filepath.Dir(exe)
		for i := 0; i < 5; i++ {
			if _, err := os.Stat(filepath.Join(dir, ".claude-plugin")); err == nil {
				return dir
			}
			if _, err := os.Stat(filepath.Join(dir, "skills")); err == nil {
				return dir
			}
			dir = filepath.Dir(dir)
		}
	}

	// Fall back to current directory
	if cwd, err := os.Getwd(); err == nil {
		if _, err := os.Stat(filepath.Join(cwd, "skills")); err == nil {
			return cwd
		}
	}
	return ""
}
