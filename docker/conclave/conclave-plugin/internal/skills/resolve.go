package skills

import (
	"os"
	"path/filepath"
	"strings"
)

// Resolve finds a skill by name. Search order: personal dir, then conclave dir.
// The "conclave:" prefix forces conclave-only lookup.
// personalDir can be nil/empty to skip personal skills.
func Resolve(name string, personalDir interface{}, conclaveDir string) *Skill {
	forceConclave := strings.HasPrefix(name, "conclave:")
	actualName := strings.TrimPrefix(name, "conclave:")

	// Try personal first (unless conclave: prefix)
	if !forceConclave {
		if pd, ok := personalDir.(string); ok && pd != "" {
			if s := findSkill(pd, actualName, "personal"); s != nil {
				return s
			}
		}
	}

	// Try conclave
	if s := findSkill(conclaveDir, actualName, "conclave"); s != nil {
		return s
	}
	return nil
}

func findSkill(dir, name, source string) *Skill {
	skillFile := filepath.Join(dir, name, "SKILL.md")
	if _, err := os.Stat(skillFile); err != nil {
		return nil
	}
	n, desc := extractFrontmatter(skillFile)
	if n == "" {
		n = name
	}
	return &Skill{
		Name:        n,
		Description: desc,
		Path:        filepath.Join(dir, name),
		SkillFile:   skillFile,
		Source:      source,
	}
}
