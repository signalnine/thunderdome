package lint

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func writeSkill(t *testing.T, dir, name, content string) string {
	t.Helper()
	skillDir := filepath.Join(dir, name)
	os.MkdirAll(skillDir, 0755)
	path := filepath.Join(skillDir, "SKILL.md")
	os.WriteFile(path, []byte(content), 0644)
	return path
}

func TestValidSkill(t *testing.T) {
	dir := t.TempDir()
	writeSkill(t, dir, "test-skill", "---\nname: test-skill\ndescription: Use when testing the linter\n---\nSome body content here.\n")
	result, err := LintSkills([]string{filepath.Join(dir, "test-skill", "SKILL.md")}, nil)
	if err != nil {
		t.Fatal(err)
	}
	for _, f := range result.Findings {
		t.Errorf("unexpected finding: %s: %s", f.Rule, f.Message)
	}
}

func TestMissingFrontmatter(t *testing.T) {
	dir := t.TempDir()
	writeSkill(t, dir, "no-fm", "No frontmatter here.\n")
	result, _ := LintSkills([]string{filepath.Join(dir, "no-fm", "SKILL.md")}, nil)
	if !hasRule(result, "frontmatter-required") {
		t.Error("expected frontmatter-required finding")
	}
}

func TestMissingFields(t *testing.T) {
	dir := t.TempDir()
	writeSkill(t, dir, "missing-desc", "---\nname: missing-desc\n---\nBody.\n")
	result, _ := LintSkills([]string{filepath.Join(dir, "missing-desc", "SKILL.md")}, nil)
	if !hasRule(result, "frontmatter-required") {
		t.Error("expected frontmatter-required for missing description")
	}
}

func TestUnexpectedFields(t *testing.T) {
	dir := t.TempDir()
	writeSkill(t, dir, "extra", "---\nname: extra\ndescription: Use when testing\ntype: rigid\n---\nBody.\n")
	result, _ := LintSkills([]string{filepath.Join(dir, "extra", "SKILL.md")}, nil)
	if !hasRule(result, "frontmatter-schema") {
		t.Error("expected frontmatter-schema for unexpected field")
	}
}

func hasRule(r *Result, rule string) bool {
	for _, f := range r.Findings {
		if f.Rule == rule {
			return true
		}
	}
	return false
}

func hasSeverity(r *Result, rule string, sev Severity) bool {
	for _, f := range r.Findings {
		if f.Rule == rule && f.Severity == sev {
			return true
		}
	}
	return false
}

// --- Task 2: Description and naming rules ---

func TestDescriptionPrefix(t *testing.T) {
	dir := t.TempDir()
	writeSkill(t, dir, "bad-desc", "---\nname: bad-desc\ndescription: Interactive design refinement\n---\nBody.\n")
	result, _ := LintSkills([]string{filepath.Join(dir, "bad-desc", "SKILL.md")}, nil)
	if !hasSeverity(result, "description-prefix", Error) {
		t.Error("expected description-prefix error")
	}
}

func TestDescriptionLength(t *testing.T) {
	dir := t.TempDir()
	longDesc := "Use when " + strings.Repeat("a", 1020)
	writeSkill(t, dir, "long-desc", fmt.Sprintf("---\nname: long-desc\ndescription: %s\n---\nBody.\n", longDesc))
	result, _ := LintSkills([]string{filepath.Join(dir, "long-desc", "SKILL.md")}, nil)
	if !hasSeverity(result, "description-length", Error) {
		t.Error("expected description-length error")
	}
}

func TestDescriptionVerbose(t *testing.T) {
	dir := t.TempDir()
	desc := "Use when " + strings.Repeat("a", 195)
	writeSkill(t, dir, "verbose", fmt.Sprintf("---\nname: verbose\ndescription: %s\n---\nBody.\n", desc))
	result, _ := LintSkills([]string{filepath.Join(dir, "verbose", "SKILL.md")}, nil)
	if !hasSeverity(result, "description-verbose", Warning) {
		t.Error("expected description-verbose warning")
	}
}

func TestSkillNamingValid(t *testing.T) {
	dir := t.TempDir()
	writeSkill(t, dir, "good-name", "---\nname: good-name-123\ndescription: Use when testing\n---\nBody.\n")
	result, _ := LintSkills([]string{filepath.Join(dir, "good-name", "SKILL.md")}, nil)
	if hasRule(result, "skill-naming") {
		t.Error("unexpected skill-naming finding for valid name")
	}
}

func TestSkillNamingInvalid(t *testing.T) {
	tests := []struct {
		name string
		val  string
	}{
		{"underscore", "bad_name"},
		{"uppercase", "BadName"},
		{"spaces", "bad name"},
		{"special", "bad@name"},
		{"trailing-hyphen", "bad-"},
		{"leading-hyphen", "-bad"},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			dir := t.TempDir()
			writeSkill(t, dir, "s", fmt.Sprintf("---\nname: %s\ndescription: Use when testing\n---\nBody.\n", tt.val))
			result, _ := LintSkills([]string{filepath.Join(dir, "s", "SKILL.md")}, nil)
			if !hasSeverity(result, "skill-naming", Error) {
				t.Errorf("expected skill-naming error for %q", tt.val)
			}
		})
	}
}

// --- Task 3: Word count ---

func TestWordCountUnder(t *testing.T) {
	dir := t.TempDir()
	writeSkill(t, dir, "short", "---\nname: short\ndescription: Use when testing\n---\nA few words.\n")
	result, _ := LintSkills([]string{filepath.Join(dir, "short", "SKILL.md")}, nil)
	if hasRule(result, "word-count") {
		t.Error("unexpected word-count finding for short skill")
	}
}

func TestWordCountOver(t *testing.T) {
	dir := t.TempDir()
	body := strings.Repeat("word ", 501)
	writeSkill(t, dir, "long", fmt.Sprintf("---\nname: long\ndescription: Use when testing\n---\n%s\n", body))
	result, _ := LintSkillsWithOptions([]string{filepath.Join(dir, "long", "SKILL.md")}, nil, LintOptions{WordLimit: 500})
	if !hasSeverity(result, "word-count", Warning) {
		t.Error("expected word-count warning")
	}
}

func TestWordCountCustomLimit(t *testing.T) {
	dir := t.TempDir()
	body := strings.Repeat("word ", 101)
	writeSkill(t, dir, "medium", fmt.Sprintf("---\nname: medium\ndescription: Use when testing\n---\n%s\n", body))
	result, _ := LintSkillsWithOptions([]string{filepath.Join(dir, "medium", "SKILL.md")}, nil, LintOptions{WordLimit: 100})
	if !hasSeverity(result, "word-count", Warning) {
		t.Error("expected word-count warning with custom limit")
	}
}

// --- Task 4: Cross-reference validation ---

func TestCrossRefValid(t *testing.T) {
	dir := t.TempDir()
	writeSkill(t, dir, "main-skill", "---\nname: main-skill\ndescription: Use when testing\n---\n**REQUIRED BACKGROUND:** You MUST understand conclave:helper-skill\n")
	known := []string{"main-skill", "helper-skill"}
	result, _ := LintSkills([]string{filepath.Join(dir, "main-skill", "SKILL.md")}, known)
	if hasRule(result, "cross-ref-valid") {
		t.Error("unexpected cross-ref-valid finding for valid reference")
	}
}

func TestCrossRefBroken(t *testing.T) {
	dir := t.TempDir()
	writeSkill(t, dir, "broken-ref", "---\nname: broken-ref\ndescription: Use when testing\n---\n**REQUIRED SUB-SKILL:** Use conclave:nonexistent-skill\n")
	known := []string{"broken-ref"}
	result, _ := LintSkills([]string{filepath.Join(dir, "broken-ref", "SKILL.md")}, known)
	if !hasSeverity(result, "cross-ref-valid", Error) {
		t.Error("expected cross-ref-valid error for broken reference")
	}
}

func TestCrossRefInInlineCode(t *testing.T) {
	dir := t.TempDir()
	writeSkill(t, dir, "example", "---\nname: example\ndescription: Use when testing\n---\n- Good: `**REQUIRED SUB-SKILL:** Use conclave:nonexistent`\n")
	known := []string{"example"}
	result, _ := LintSkills([]string{filepath.Join(dir, "example", "SKILL.md")}, known)
	if hasRule(result, "cross-ref-valid") {
		t.Error("should not lint cross-refs inside inline backtick code")
	}
}

func TestCrossRefInFencedCodeBlock(t *testing.T) {
	dir := t.TempDir()
	content := "---\nname: fenced\ndescription: Use when testing\n---\n```\n**REQUIRED SUB-SKILL:** Use conclave:nonexistent\n```\n"
	writeSkill(t, dir, "fenced", content)
	known := []string{"fenced"}
	result, _ := LintSkills([]string{filepath.Join(dir, "fenced", "SKILL.md")}, known)
	if hasRule(result, "cross-ref-valid") {
		t.Error("should not lint cross-refs inside fenced code blocks")
	}
}

func TestCrossRefSkippedWhenNoKnownSkills(t *testing.T) {
	dir := t.TempDir()
	writeSkill(t, dir, "lonely", "---\nname: lonely\ndescription: Use when testing\n---\n**REQUIRED BACKGROUND:** conclave:something\n")
	result, _ := LintSkills([]string{filepath.Join(dir, "lonely", "SKILL.md")}, nil)
	if hasRule(result, "cross-ref-valid") {
		t.Error("cross-ref check should be skipped when knownSkills is nil")
	}
}

// --- Task 5: Duplicate name detection ---

func TestDuplicateName(t *testing.T) {
	dir := t.TempDir()
	writeSkill(t, dir, "skill-a", "---\nname: same-name\ndescription: Use when testing A\n---\nBody A.\n")
	writeSkill(t, dir, "skill-b", "---\nname: same-name\ndescription: Use when testing B\n---\nBody B.\n")
	paths := []string{
		filepath.Join(dir, "skill-a", "SKILL.md"),
		filepath.Join(dir, "skill-b", "SKILL.md"),
	}
	result, _ := LintSkills(paths, nil)
	count := 0
	for _, f := range result.Findings {
		if f.Rule == "duplicate-name" {
			count++
		}
	}
	if count != 2 {
		t.Errorf("expected 2 duplicate-name findings (one per file), got %d", count)
	}
}

func TestNoDuplicateName(t *testing.T) {
	dir := t.TempDir()
	writeSkill(t, dir, "skill-a", "---\nname: unique-a\ndescription: Use when testing A\n---\nBody.\n")
	writeSkill(t, dir, "skill-b", "---\nname: unique-b\ndescription: Use when testing B\n---\nBody.\n")
	paths := []string{
		filepath.Join(dir, "skill-a", "SKILL.md"),
		filepath.Join(dir, "skill-b", "SKILL.md"),
	}
	result, _ := LintSkills(paths, nil)
	if hasRule(result, "duplicate-name") {
		t.Error("unexpected duplicate-name finding")
	}
}

// --- Task 6: Plan filename validation ---

func TestPlanFilenameValid(t *testing.T) {
	dir := t.TempDir()
	os.WriteFile(filepath.Join(dir, "2026-02-11-proxy-design.md"), []byte("content"), 0644)
	os.WriteFile(filepath.Join(dir, "2026-02-11-proxy-implementation.md"), []byte("content"), 0644)
	result, _ := LintPlanFilenames(dir)
	if hasRule(result, "plan-filename") {
		t.Error("unexpected plan-filename finding for valid filenames")
	}
	if result.Files != 2 {
		t.Errorf("files = %d, want 2", result.Files)
	}
}

func TestPlanFilenameInvalid(t *testing.T) {
	tests := []struct {
		name     string
		filename string
	}{
		{"no-date", "my-notes.md"},
		{"uppercase-topic", "2026-02-11-Proxy-design.md"},
		{"underscore-topic", "2026-02-11-proxy_cache-design.md"},
		{"missing-suffix", "2026-02-11-proxy.md"},
		{"wrong-suffix", "2026-02-11-proxy-review.md"},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			dir := t.TempDir()
			os.WriteFile(filepath.Join(dir, tt.filename), []byte("content"), 0644)
			result, _ := LintPlanFilenames(dir)
			if !hasSeverity(result, "plan-filename", Error) {
				t.Errorf("expected plan-filename error for %q", tt.filename)
			}
		})
	}
}

func TestPlanFilenameMultiWordTopic(t *testing.T) {
	dir := t.TempDir()
	os.WriteFile(filepath.Join(dir, "2026-02-11-prose-linting-design.md"), []byte("content"), 0644)
	os.WriteFile(filepath.Join(dir, "2026-02-11-token-counting-proxy-implementation.md"), []byte("content"), 0644)
	result, _ := LintPlanFilenames(dir)
	if hasRule(result, "plan-filename") {
		t.Error("unexpected plan-filename finding for multi-word topic names")
	}
	if result.Files != 2 {
		t.Errorf("files = %d, want 2", result.Files)
	}
}

func TestPlanFilenameSkipsDotfiles(t *testing.T) {
	dir := t.TempDir()
	os.WriteFile(filepath.Join(dir, ".brainstorm-checkpoint-20260211.json"), []byte("{}"), 0644)
	result, _ := LintPlanFilenames(dir)
	if result.Files != 0 {
		t.Errorf("files = %d, want 0 (dotfiles skipped)", result.Files)
	}
}

func TestPlanFilenameSkipsNonMd(t *testing.T) {
	dir := t.TempDir()
	os.WriteFile(filepath.Join(dir, "notes.txt"), []byte("content"), 0644)
	result, _ := LintPlanFilenames(dir)
	if result.Files != 0 {
		t.Errorf("files = %d, want 0 (non-md skipped)", result.Files)
	}
}

func TestPlanFilenameEmptyDir(t *testing.T) {
	dir := t.TempDir()
	result, _ := LintPlanFilenames(dir)
	if result.Files != 0 {
		t.Errorf("files = %d, want 0", result.Files)
	}
	if len(result.Findings) != 0 {
		t.Errorf("findings = %d, want 0", len(result.Findings))
	}
}

// --- Task 8: Output formatting ---

func TestFormatText(t *testing.T) {
	r := &Result{
		Files: 2,
		Findings: []Finding{
			{File: "skills/a/SKILL.md", Rule: "description-prefix", Severity: Error, Message: "description must start with \"Use when\""},
			{File: "skills/a/SKILL.md", Rule: "word-count", Severity: Warning, Message: "body is 600 words"},
			{File: "skills/b/SKILL.md", Rule: "skill-naming", Severity: Error, Message: "invalid name"},
		},
	}
	text := r.FormatText()
	if !strings.Contains(text, "skills/a/SKILL.md") {
		t.Error("missing file grouping")
	}
	if !strings.Contains(text, "2 errors") {
		t.Error("missing error count")
	}
	if !strings.Contains(text, "1 warning") {
		t.Errorf("missing warning count in: %s", text)
	}
}

func TestFormatJSON(t *testing.T) {
	r := &Result{
		Findings: []Finding{
			{File: "test.md", Rule: "test-rule", Severity: Error, Message: "test message"},
		},
	}
	out, err := r.FormatJSON()
	if err != nil {
		t.Fatal(err)
	}
	var parsed []jsonFinding
	if err := json.Unmarshal([]byte(out), &parsed); err != nil {
		t.Fatalf("invalid JSON: %v", err)
	}
	if len(parsed) != 1 {
		t.Fatalf("got %d findings, want 1", len(parsed))
	}
	if parsed[0].Severity != "error" {
		t.Errorf("severity = %q, want error", parsed[0].Severity)
	}
}

func TestFormatTextEmpty(t *testing.T) {
	r := &Result{Files: 5}
	text := r.FormatText()
	if text != "" {
		t.Errorf("expected empty string for no findings, got %q", text)
	}
}

func TestHasErrors(t *testing.T) {
	r := &Result{Findings: []Finding{
		{Severity: Warning},
	}}
	if r.HasErrors() {
		t.Error("warnings-only should not count as errors")
	}
	r.Findings = append(r.Findings, Finding{Severity: Error})
	if !r.HasErrors() {
		t.Error("should have errors")
	}
}
