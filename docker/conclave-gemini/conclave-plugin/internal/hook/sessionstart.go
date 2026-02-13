package hook

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"strings"
)

func SessionStart(pluginRoot string) (string, error) {
	// Read using-conclave skill content
	skillPath := filepath.Join(pluginRoot, "skills", "using-conclave", "SKILL.md")
	content, err := os.ReadFile(skillPath)
	if err != nil {
		return "", fmt.Errorf("reading using-conclave skill: %w", err)
	}

	// Check for legacy skills directory
	var warning string
	home, _ := os.UserHomeDir()
	if home != "" {
		legacyDir := filepath.Join(home, ".config", "conclave", "skills")
		if info, err := os.Stat(legacyDir); err == nil && info.IsDir() {
			warning = "\n\n<important-reminder>IN YOUR FIRST REPLY AFTER SEEING THIS MESSAGE YOU MUST TELL THE USER:" +
				"WARNING: Conclave now uses Claude Code's skills system. Custom skills in ~/.config/conclave/skills " +
				"will not be read. Move custom skills to ~/.claude/skills instead. To make this message go away, " +
				"remove ~/.config/conclave/skills</important-reminder>"
		}
	}

	binaryPath := filepath.Join(pluginRoot, "conclave")

	ctx := fmt.Sprintf("<EXTREMELY_IMPORTANT>\nYou have conclave.\n\n"+
		"**The conclave CLI binary is at: `%s`** — always use this full path when running conclave commands.\n\n"+
		"**Below is the full content of your 'conclave:using-conclave' skill - "+
		"your introduction to using skills. For all other skills, use the 'Skill' tool:**\n\n"+
		"%s\n\n%s\n</EXTREMELY_IMPORTANT>",
		binaryPath, strings.TrimSpace(string(content)), warning)

	output := map[string]any{
		"hookSpecificOutput": map[string]any{
			"hookEventName":     "SessionStart",
			"additionalContext": ctx,
		},
	}

	data, err := json.Marshal(output)
	if err != nil {
		return "", err
	}
	return string(data), nil
}
