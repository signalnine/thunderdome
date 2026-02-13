package skills

import (
	"testing"
)

func TestResolve_FindsInConclave(t *testing.T) {
	dir := t.TempDir()
	createSkill(t, dir, "brainstorming", "---\nname: brainstorming\n---\nContent.\n")
	s := Resolve("brainstorming", nil, dir)
	if s == nil {
		t.Fatal("not found")
	}
	if s.Source != "conclave" {
		t.Errorf("Source = %q", s.Source)
	}
}

func TestResolve_PersonalOverridesConclave(t *testing.T) {
	conclaveDir := t.TempDir()
	personalDir := t.TempDir()
	createSkill(t, conclaveDir, "brainstorming", "---\nname: brainstorming\n---\nConclave version.\n")
	createSkill(t, personalDir, "brainstorming", "---\nname: brainstorming\n---\nPersonal version.\n")
	s := Resolve("brainstorming", personalDir, conclaveDir)
	if s.Source != "personal" {
		t.Errorf("Source = %q, want personal", s.Source)
	}
}

func TestResolve_ConclavePrefix_SkipsPersonal(t *testing.T) {
	conclaveDir := t.TempDir()
	personalDir := t.TempDir()
	createSkill(t, conclaveDir, "brainstorming", "---\nname: brainstorming\n---\nConclave.\n")
	createSkill(t, personalDir, "brainstorming", "---\nname: brainstorming\n---\nPersonal.\n")
	s := Resolve("conclave:brainstorming", personalDir, conclaveDir)
	if s.Source != "conclave" {
		t.Errorf("Source = %q, want conclave", s.Source)
	}
}

func TestResolve_NotFound(t *testing.T) {
	dir := t.TempDir()
	s := Resolve("nonexistent", nil, dir)
	if s != nil {
		t.Errorf("expected nil, got %v", s)
	}
}
