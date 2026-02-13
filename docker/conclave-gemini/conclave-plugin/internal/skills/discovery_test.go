package skills

import (
	"os"
	"path/filepath"
	"testing"
)

func createSkill(t *testing.T, dir, name, content string) {
	t.Helper()
	skillDir := filepath.Join(dir, name)
	os.MkdirAll(skillDir, 0755)
	os.WriteFile(filepath.Join(skillDir, "SKILL.md"), []byte(content), 0644)
}

func TestDiscover_FindsSkills(t *testing.T) {
	dir := t.TempDir()
	createSkill(t, dir, "brainstorming", "---\nname: brainstorming\ndescription: Use when starting creative work\n---\nContent here.\n")
	createSkill(t, dir, "debugging", "---\nname: debugging\ndescription: Use when fixing bugs\n---\nContent.\n")
	skills := Discover(dir)
	if len(skills) != 2 {
		t.Fatalf("got %d skills, want 2", len(skills))
	}
}

func TestDiscover_ParsesFrontmatter(t *testing.T) {
	dir := t.TempDir()
	createSkill(t, dir, "test-skill", "---\nname: test-skill\ndescription: A test skill\n---\nBody.\n")
	skills := Discover(dir)
	if skills[0].Name != "test-skill" {
		t.Errorf("Name = %q", skills[0].Name)
	}
	if skills[0].Description != "A test skill" {
		t.Errorf("Description = %q", skills[0].Description)
	}
}

func TestDiscover_FallsBackToDirectoryName(t *testing.T) {
	dir := t.TempDir()
	createSkill(t, dir, "my-skill", "No frontmatter here.\n")
	skills := Discover(dir)
	if len(skills) != 1 {
		t.Fatalf("got %d skills", len(skills))
	}
	if skills[0].Name != "my-skill" {
		t.Errorf("Name = %q, want my-skill", skills[0].Name)
	}
}

func TestDiscover_EmptyDir(t *testing.T) {
	dir := t.TempDir()
	skills := Discover(dir)
	if len(skills) != 0 {
		t.Errorf("got %d skills from empty dir", len(skills))
	}
}

func TestDiscover_NonexistentDir(t *testing.T) {
	skills := Discover("/nonexistent/path")
	if len(skills) != 0 {
		t.Errorf("got %d skills from nonexistent dir", len(skills))
	}
}
