package skills

import (
	"bufio"
	"os"
	"path/filepath"
	"strings"
)

type Skill struct {
	Name        string
	Description string
	Path        string
	SkillFile   string
	Source      string // "conclave", "personal"
}

func Discover(dirs ...string) []Skill {
	var skills []Skill
	for _, dir := range dirs {
		entries, err := os.ReadDir(dir)
		if err != nil {
			continue
		}
		for _, e := range entries {
			if !e.IsDir() {
				continue
			}
			skillFile := filepath.Join(dir, e.Name(), "SKILL.md")
			if _, err := os.Stat(skillFile); err != nil {
				continue
			}
			name, desc := extractFrontmatter(skillFile)
			if name == "" {
				name = e.Name()
			}
			skills = append(skills, Skill{
				Name:        name,
				Description: desc,
				Path:        filepath.Join(dir, e.Name()),
				SkillFile:   skillFile,
			})
		}
	}
	return skills
}

func extractFrontmatter(path string) (name, description string) {
	f, err := os.Open(path)
	if err != nil {
		return "", ""
	}
	defer f.Close()

	scanner := bufio.NewScanner(f)
	inFrontmatter := false
	for scanner.Scan() {
		line := scanner.Text()
		if strings.TrimSpace(line) == "---" {
			if inFrontmatter {
				break
			}
			inFrontmatter = true
			continue
		}
		if inFrontmatter {
			if k, v, ok := strings.Cut(line, ":"); ok {
				k = strings.TrimSpace(k)
				v = strings.TrimSpace(v)
				switch k {
				case "name":
					name = v
				case "description":
					description = v
				}
			}
		}
	}
	return name, description
}
