# Prose Linting Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use conclave:executing-plans to implement this plan task-by-task.

**Goal:** Add `conclave lint` command that validates SKILL.md files and docs/plans/ filenames against Conclave's authoring standards.

**Architecture:** New `internal/lint` package with pure Go rule functions, each taking parsed skill data and returning `Finding` values. Cobra CLI command in `cmd/conclave/lint.go` handles path resolution, output formatting, and exit codes.

**Tech Stack:** Go stdlib (`strings`, `regexp`, `path/filepath`, `os`), `gopkg.in/yaml.v3` (already in go.mod), `github.com/spf13/cobra` (already in go.mod), `internal/git` (for `TopLevel()`), `internal/skills` (for `Discover()`)

---

### Task 1: Core types and frontmatter parser

**Files:**
- Create: `internal/lint/lint.go`
- Test: `internal/lint/lint_test.go`

**Dependencies:** none

**Step 1: Write failing tests for types and frontmatter parsing**

Create `internal/lint/lint_test.go`:

```go
package lint

import (
	"os"
	"path/filepath"
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
```

**Step 2: Run tests to verify they fail**

Run: `go test ./internal/lint/ -run 'TestValidSkill|TestMissingFrontmatter|TestMissingFields|TestUnexpectedFields' -v`
Expected: FAIL — package does not exist yet

**Step 3: Write minimal implementation**

Create `internal/lint/lint.go`:

```go
package lint

import (
	"fmt"
	"os"
	"strings"

	"gopkg.in/yaml.v3"
)

type Severity int

const (
	Error   Severity = iota
	Warning
)

func (s Severity) String() string {
	if s == Warning {
		return "warning"
	}
	return "error"
}

type Finding struct {
	File     string
	Rule     string
	Severity Severity
	Message  string
}

type Result struct {
	Findings []Finding
	Files    int
}

func (r *Result) HasErrors() bool {
	for _, f := range r.Findings {
		if f.Severity == Error {
			return true
		}
	}
	return false
}

func (r *Result) Merge(other *Result) {
	r.Findings = append(r.Findings, other.Findings...)
	r.Files += other.Files
}

type parsedSkill struct {
	file        string
	frontmatter map[string]interface{}
	body        string
	hasFM       bool
}

func parseSkillFile(path string) (*parsedSkill, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		return nil, err
	}
	content := string(data)
	ps := &parsedSkill{file: path}

	// Split on --- delimiters
	if !strings.HasPrefix(content, "---\n") {
		ps.body = content
		return ps, nil
	}

	rest := content[4:] // skip opening ---\n
	end := strings.Index(rest, "\n---\n")
	if end == -1 {
		// No closing ---, treat as no frontmatter
		ps.body = content
		return ps, nil
	}

	fmText := rest[:end]
	ps.body = rest[end+5:] // skip \n---\n
	ps.hasFM = true

	// Parse YAML into map using yaml.v3 to detect unexpected fields
	ps.frontmatter = make(map[string]interface{})
	if err := yaml.Unmarshal([]byte(fmText), &ps.frontmatter); err != nil {
		// Treat YAML parse errors as missing frontmatter
		ps.hasFM = false
		ps.body = content
	}

	return ps, nil
}

var allowedFrontmatterKeys = map[string]bool{
	"name":        true,
	"description": true,
}

func lintFrontmatter(ps *parsedSkill) []Finding {
	var findings []Finding

	if !ps.hasFM {
		findings = append(findings, Finding{
			File: ps.file, Rule: "frontmatter-required", Severity: Error,
			Message: "SKILL.md must have YAML frontmatter delimited by ---",
		})
		return findings
	}

	// Check required fields
	name, hasName := ps.frontmatter["name"]
	desc, hasDesc := ps.frontmatter["description"]
	if !hasName || fmt.Sprint(name) == "" {
		findings = append(findings, Finding{
			File: ps.file, Rule: "frontmatter-required", Severity: Error,
			Message: "frontmatter missing required field: name",
		})
	}
	if !hasDesc || fmt.Sprint(desc) == "" {
		findings = append(findings, Finding{
			File: ps.file, Rule: "frontmatter-required", Severity: Error,
			Message: "frontmatter missing required field: description",
		})
	}

	// Check for unexpected fields
	for key := range ps.frontmatter {
		if !allowedFrontmatterKeys[key] {
			findings = append(findings, Finding{
				File: ps.file, Rule: "frontmatter-schema", Severity: Error,
				Message: fmt.Sprintf("unexpected frontmatter field: %s", key),
			})
		}
	}

	return findings
}

// LintSkills validates SKILL.md files and returns findings.
// knownSkills is used for cross-ref validation; pass nil to skip.
func LintSkills(paths []string, knownSkills []string) (*Result, error) {
	result := &Result{}
	for _, path := range paths {
		result.Files++
		ps, err := parseSkillFile(path)
		if err != nil {
			return nil, err
		}
		result.Findings = append(result.Findings, lintFrontmatter(ps)...)
	}
	return result, nil
}
```

**Step 4: Run tests to verify they pass**

Run: `go test ./internal/lint/ -run 'TestValidSkill|TestMissingFrontmatter|TestMissingFields|TestUnexpectedFields' -v`
Expected: PASS

**Step 5: Commit**

```bash
git add internal/lint/lint.go internal/lint/lint_test.go
git commit -m "feat(lint): add core types and frontmatter validation"
```

---

### Task 2: Description and naming rules

**Files:**
- Modify: `internal/lint/lint.go`
- Modify: `internal/lint/lint_test.go`

**Dependencies:** Task 1

**Step 1: Write failing tests**

Append to `internal/lint/lint_test.go`:

```go
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
```

Add `"fmt"` and `"strings"` to the test file imports.

**Step 2: Run tests to verify they fail**

Run: `go test ./internal/lint/ -run 'TestDescription|TestSkillNaming' -v`
Expected: FAIL — rules not implemented

**Step 3: Write minimal implementation**

Add to `internal/lint/lint.go`:

```go
import "regexp"

var skillNameRe = regexp.MustCompile(`^[a-z0-9]+(-[a-z0-9]+)*$`)

func lintDescription(ps *parsedSkill) []Finding {
	var findings []Finding
	desc := fmt.Sprint(ps.frontmatter["description"])

	if !strings.HasPrefix(desc, "Use when") {
		findings = append(findings, Finding{
			File: ps.file, Rule: "description-prefix", Severity: Error,
			Message: fmt.Sprintf("description must start with \"Use when\" (got: %q)", truncate(desc, 50)),
		})
	}

	if len(desc) > 1024 {
		findings = append(findings, Finding{
			File: ps.file, Rule: "description-length", Severity: Error,
			Message: fmt.Sprintf("description is %d characters, max 1024", len(desc)),
		})
	}

	if len(desc) > 200 {
		findings = append(findings, Finding{
			File: ps.file, Rule: "description-verbose", Severity: Warning,
			Message: fmt.Sprintf("description is %d characters, consider shortening to under 200", len(desc)),
		})
	}

	return findings
}

func lintSkillName(ps *parsedSkill) []Finding {
	name := fmt.Sprint(ps.frontmatter["name"])
	if !skillNameRe.MatchString(name) {
		return []Finding{{
			File: ps.file, Rule: "skill-naming", Severity: Error,
			Message: fmt.Sprintf("skill name %q must be lowercase alphanumeric with hyphens (a-z, 0-9, -)", name),
		}}
	}
	return nil
}

func truncate(s string, n int) string {
	if len(s) <= n {
		return s
	}
	return s[:n] + "..."
}
```

Update `LintSkills` to call these new rules:

```go
func LintSkills(paths []string, knownSkills []string) (*Result, error) {
	result := &Result{}
	for _, path := range paths {
		result.Files++
		ps, err := parseSkillFile(path)
		if err != nil {
			return nil, err
		}
		result.Findings = append(result.Findings, lintFrontmatter(ps)...)
		// Only run further rules if frontmatter exists and has required fields
		if ps.hasFM && ps.frontmatter["name"] != nil && ps.frontmatter["description"] != nil {
			result.Findings = append(result.Findings, lintDescription(ps)...)
			result.Findings = append(result.Findings, lintSkillName(ps)...)
		}
	}
	return result, nil
}
```

**Step 4: Run tests to verify they pass**

Run: `go test ./internal/lint/ -v`
Expected: PASS (all tests from Task 1 and Task 2)

**Step 5: Commit**

```bash
git add internal/lint/lint.go internal/lint/lint_test.go
git commit -m "feat(lint): add description and naming validation rules"
```

---

### Task 3: Word count rule

**Files:**
- Modify: `internal/lint/lint.go`
- Modify: `internal/lint/lint_test.go`

**Dependencies:** Task 1

**Step 1: Write failing tests**

Append to `internal/lint/lint_test.go`:

```go
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
```

**Step 2: Run tests to verify they fail**

Run: `go test ./internal/lint/ -run 'TestWordCount' -v`
Expected: FAIL — `LintSkillsWithOptions` does not exist

**Step 3: Write minimal implementation**

Add to `internal/lint/lint.go`:

```go
const DefaultWordLimit = 500

type LintOptions struct {
	WordLimit int
}

func (o LintOptions) wordLimit() int {
	if o.WordLimit > 0 {
		return o.WordLimit
	}
	return DefaultWordLimit
}

func lintWordCount(ps *parsedSkill, limit int) []Finding {
	words := len(strings.Fields(ps.body))
	if words > limit {
		return []Finding{{
			File: ps.file, Rule: "word-count", Severity: Warning,
			Message: fmt.Sprintf("body is %d words, exceeds %d word target", words, limit),
		}}
	}
	return nil
}
```

Add `LintSkillsWithOptions` and update `LintSkills` to delegate to it:

```go
func LintSkills(paths []string, knownSkills []string) (*Result, error) {
	return LintSkillsWithOptions(paths, knownSkills, LintOptions{})
}

func LintSkillsWithOptions(paths []string, knownSkills []string, opts LintOptions) (*Result, error) {
	result := &Result{}
	for _, path := range paths {
		result.Files++
		ps, err := parseSkillFile(path)
		if err != nil {
			return nil, err
		}
		result.Findings = append(result.Findings, lintFrontmatter(ps)...)
		if ps.hasFM && ps.frontmatter["name"] != nil && ps.frontmatter["description"] != nil {
			result.Findings = append(result.Findings, lintDescription(ps)...)
			result.Findings = append(result.Findings, lintSkillName(ps)...)
			result.Findings = append(result.Findings, lintWordCount(ps, opts.wordLimit())...)
		}
	}
	return result, nil
}
```

**Step 4: Run tests to verify they pass**

Run: `go test ./internal/lint/ -v`
Expected: PASS

**Step 5: Commit**

```bash
git add internal/lint/lint.go internal/lint/lint_test.go
git commit -m "feat(lint): add word count validation with configurable limit"
```

---

### Task 4: Cross-reference validation

**Files:**
- Modify: `internal/lint/lint.go`
- Modify: `internal/lint/lint_test.go`

**Dependencies:** Task 1

**Step 1: Write failing tests**

Append to `internal/lint/lint_test.go`:

```go
func TestCrossRefValid(t *testing.T) {
	dir := t.TempDir()
	writeSkill(t, dir, "main-skill", "---\nname: main-skill\ndescription: Use when testing\n---\n**REQUIRED BACKGROUND:** You MUST understand conclave:helper-skill\n")
	writeSkill(t, dir, "helper-skill", "---\nname: helper-skill\ndescription: Use when helping\n---\nBody.\n")
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
	// References inside backtick code examples should be ignored
	writeSkill(t, dir, "example", "---\nname: example\ndescription: Use when testing\n---\n- Good: `**REQUIRED SUB-SKILL:** Use conclave:nonexistent`\n")
	known := []string{"example"}
	result, _ := LintSkills([]string{filepath.Join(dir, "example", "SKILL.md")}, known)
	if hasRule(result, "cross-ref-valid") {
		t.Error("should not lint cross-refs inside inline backtick code")
	}
}

func TestCrossRefInFencedCodeBlock(t *testing.T) {
	dir := t.TempDir()
	// References inside fenced code blocks should be ignored
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
```

**Step 2: Run tests to verify they fail**

Run: `go test ./internal/lint/ -run 'TestCrossRef' -v`
Expected: FAIL — cross-ref logic not implemented

**Step 3: Write minimal implementation**

Add to `internal/lint/lint.go`:

```go
import "regexp"

var crossRefRe = regexp.MustCompile(`\*\*REQUIRED (?:BACKGROUND|SUB-SKILL):\*\*[^\n]*conclave:([a-z0-9-]+)`)

func lintCrossRefs(ps *parsedSkill, knownSkills []string) []Finding {
	if knownSkills == nil {
		return nil
	}

	known := make(map[string]bool, len(knownSkills))
	for _, s := range knownSkills {
		known[s] = true
	}

	var findings []Finding
	inFencedBlock := false
	for _, line := range strings.Split(ps.body, "\n") {
		trimmed := strings.TrimSpace(line)
		// Track fenced code blocks (``` or ~~~)
		if strings.HasPrefix(trimmed, "```") || strings.HasPrefix(trimmed, "~~~") {
			inFencedBlock = !inFencedBlock
			continue
		}
		if inFencedBlock {
			continue
		}
		// Skip lines that contain backtick-wrapped markers (inline code examples)
		if strings.Contains(line, "`**REQUIRED") {
			continue
		}
		for _, match := range crossRefRe.FindAllStringSubmatch(line, -1) {
			ref := match[1]
			if !known[ref] {
				findings = append(findings, Finding{
					File: ps.file, Rule: "cross-ref-valid", Severity: Error,
					Message: fmt.Sprintf("cross-reference to unknown skill: conclave:%s", ref),
				})
			}
		}
	}
	return findings
}
```

Add `lintCrossRefs` call in `LintSkillsWithOptions` inside the `hasFM` block:

```go
result.Findings = append(result.Findings, lintCrossRefs(ps, knownSkills)...)
```

**Step 4: Run tests to verify they pass**

Run: `go test ./internal/lint/ -v`
Expected: PASS

**Step 5: Commit**

```bash
git add internal/lint/lint.go internal/lint/lint_test.go
git commit -m "feat(lint): add cross-reference validation"
```

---

### Task 5: Duplicate name detection

**Files:**
- Modify: `internal/lint/lint.go`
- Modify: `internal/lint/lint_test.go`

**Dependencies:** Task 1

**Step 1: Write failing tests**

Append to `internal/lint/lint_test.go`:

```go
func TestDuplicateName(t *testing.T) {
	dir := t.TempDir()
	writeSkill(t, dir, "skill-a", "---\nname: same-name\ndescription: Use when testing A\n---\nBody A.\n")
	writeSkill(t, dir, "skill-b", "---\nname: same-name\ndescription: Use when testing B\n---\nBody B.\n")
	paths := []string{
		filepath.Join(dir, "skill-a", "SKILL.md"),
		filepath.Join(dir, "skill-b", "SKILL.md"),
	}
	result, _ := LintSkills(paths, nil)
	// Should report both files
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
```

**Step 2: Run tests to verify they fail**

Run: `go test ./internal/lint/ -run 'TestDuplicate|TestNoDuplicate' -v`
Expected: FAIL — duplicate detection not implemented

**Step 3: Write minimal implementation**

Add duplicate checking in `LintSkillsWithOptions`, after the per-file loop:

```go
func LintSkillsWithOptions(paths []string, knownSkills []string, opts LintOptions) (*Result, error) {
	result := &Result{}
	seen := make(map[string]string) // name -> first file path

	for _, path := range paths {
		result.Files++
		ps, err := parseSkillFile(path)
		if err != nil {
			return nil, err
		}
		result.Findings = append(result.Findings, lintFrontmatter(ps)...)
		if ps.hasFM && ps.frontmatter["name"] != nil && ps.frontmatter["description"] != nil {
			result.Findings = append(result.Findings, lintDescription(ps)...)
			result.Findings = append(result.Findings, lintSkillName(ps)...)
			result.Findings = append(result.Findings, lintWordCount(ps, opts.wordLimit())...)
			result.Findings = append(result.Findings, lintCrossRefs(ps, knownSkills)...)

			// Track names for duplicate detection
			name := fmt.Sprint(ps.frontmatter["name"])
			if first, exists := seen[name]; exists {
				result.Findings = append(result.Findings, Finding{
					File: ps.file, Rule: "duplicate-name", Severity: Error,
					Message: fmt.Sprintf("duplicate skill name %q (also in %s)", name, first),
				})
				result.Findings = append(result.Findings, Finding{
					File: first, Rule: "duplicate-name", Severity: Error,
					Message: fmt.Sprintf("duplicate skill name %q (also in %s)", name, ps.file),
				})
			} else {
				seen[name] = ps.file
			}
		}
	}
	return result, nil
}
```

**Step 4: Run tests to verify they pass**

Run: `go test ./internal/lint/ -v`
Expected: PASS

**Step 5: Commit**

```bash
git add internal/lint/lint.go internal/lint/lint_test.go
git commit -m "feat(lint): add duplicate skill name detection"
```

---

### Task 6: Plan filename validation

**Files:**
- Modify: `internal/lint/lint.go`
- Modify: `internal/lint/lint_test.go`

**Dependencies:** Task 1

**Step 1: Write failing tests**

Append to `internal/lint/lint_test.go`:

```go
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
	dir := t.TempDir()
	os.WriteFile(filepath.Join(dir, "my-notes.md"), []byte("content"), 0644)
	result, _ := LintPlanFilenames(dir)
	if !hasSeverity(result, "plan-filename", Error) {
		t.Error("expected plan-filename error")
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
```

**Step 2: Run tests to verify they fail**

Run: `go test ./internal/lint/ -run 'TestPlanFilename' -v`
Expected: FAIL — `LintPlanFilenames` not implemented

**Step 3: Write minimal implementation**

Add to `internal/lint/lint.go`:

```go
import "path/filepath"

var planFilenameRe = regexp.MustCompile(`^\d{4}-\d{2}-\d{2}-.+-(?:design|implementation)\.md$`)

// LintPlanFilenames validates filenames in a docs/plans/ directory.
func LintPlanFilenames(dir string) (*Result, error) {
	result := &Result{}

	entries, err := os.ReadDir(dir)
	if err != nil {
		if os.IsNotExist(err) {
			return result, nil
		}
		return nil, err
	}

	for _, e := range entries {
		if e.IsDir() {
			continue
		}
		name := e.Name()
		// Skip dotfiles and non-markdown
		if strings.HasPrefix(name, ".") {
			continue
		}
		if !strings.HasSuffix(name, ".md") {
			continue
		}

		result.Files++
		if !planFilenameRe.MatchString(name) {
			result.Findings = append(result.Findings, Finding{
				File:     filepath.Join(dir, name),
				Rule:     "plan-filename",
				Severity: Error,
				Message:  fmt.Sprintf("filename %q must match YYYY-MM-DD-<topic>-{design,implementation}.md", name),
			})
		}
	}
	return result, nil
}
```

**Step 4: Run tests to verify they pass**

Run: `go test ./internal/lint/ -v`
Expected: PASS

**Step 5: Commit**

```bash
git add internal/lint/lint.go internal/lint/lint_test.go
git commit -m "feat(lint): add plan filename validation"
```

---

### Task 7: CLI command

**Files:**
- Create: `cmd/conclave/lint.go`
- Modify: `internal/lint/lint.go` (add `FormatText` and `FormatJSON`)

**Dependencies:** Task 1, Task 2, Task 3, Task 4, Task 5, Task 6

**Step 1: Add output formatting to lint package**

Add to `internal/lint/lint.go`:

```go
import "encoding/json"

// FormatText returns human-readable output grouped by file.
func (r *Result) FormatText() string {
	if len(r.Findings) == 0 {
		return ""
	}

	var b strings.Builder
	grouped := make(map[string][]Finding)
	var order []string
	for _, f := range r.Findings {
		if _, seen := grouped[f.File]; !seen {
			order = append(order, f.File)
		}
		grouped[f.File] = append(grouped[f.File], f)
	}

	for _, file := range order {
		fmt.Fprintf(&b, "%s\n", file)
		for _, f := range grouped[file] {
			fmt.Fprintf(&b, "  %s: %s\n", f.Severity, f.Message)
		}
		b.WriteString("\n")
	}

	errors, warnings := 0, 0
	for _, f := range r.Findings {
		if f.Severity == Error {
			errors++
		} else {
			warnings++
		}
	}
	fmt.Fprintf(&b, "Found %d errors, %d warnings in %d files\n", errors, warnings, r.Files)
	return b.String()
}

type jsonFinding struct {
	File     string `json:"file"`
	Rule     string `json:"rule"`
	Severity string `json:"severity"`
	Message  string `json:"message"`
}

// FormatJSON returns JSON output.
func (r *Result) FormatJSON() (string, error) {
	out := make([]jsonFinding, len(r.Findings))
	for i, f := range r.Findings {
		out[i] = jsonFinding{
			File:     f.File,
			Rule:     f.Rule,
			Severity: f.Severity.String(),
			Message:  f.Message,
		}
	}
	data, err := json.MarshalIndent(out, "", "  ")
	if err != nil {
		return "", err
	}
	return string(data) + "\n", nil
}
```

**Step 2: Write the CLI command**

Create `cmd/conclave/lint.go`:

```go
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
		os.Exit(1)
	}
	return nil
}
```

**Step 3: Build to verify compilation**

Run: `go build ./cmd/conclave/`
Expected: Compiles without errors

**Step 4: Verify command appears in help**

Run: `go run ./cmd/conclave/ lint --help`
Expected: Shows lint command help with `--json` and `--word-limit` flags

**Step 5: Commit**

```bash
git add cmd/conclave/lint.go internal/lint/lint.go
git commit -m "feat(lint): add conclave lint CLI command with text and JSON output"
```

---

### Task 8: Output formatting tests

**Files:**
- Modify: `internal/lint/lint_test.go`

**Dependencies:** Task 7

**Step 1: Write tests for text and JSON formatting**

Append to `internal/lint/lint_test.go`:

```go
import "encoding/json"

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
```

**Step 2: Run tests to verify they pass**

Run: `go test ./internal/lint/ -v`
Expected: PASS (all tests)

**Step 3: Commit**

```bash
git add internal/lint/lint_test.go
git commit -m "test(lint): add output formatting and HasErrors tests"
```

---

### Task 9: Integration smoke test

**Files:**
- Create: `internal/lint/lint_integration_test.go`

**Dependencies:** Task 7

**Step 1: Write integration test**

Create `internal/lint/lint_integration_test.go`:

```go
//go:build integration

package lint_test

import (
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
)

func TestLintRealSkills(t *testing.T) {
	// Build the binary
	binPath := filepath.Join(t.TempDir(), "conclave")
	build := exec.Command("go", "build", "-o", binPath, "./cmd/conclave/")
	// Build from repo root
	build.Dir = findRepoRoot(t)
	if out, err := build.CombinedOutput(); err != nil {
		t.Fatalf("build failed: %s\n%s", err, out)
	}

	// Run lint on real skills directory
	cmd := exec.Command(binPath, "lint")
	cmd.Dir = findRepoRoot(t)
	out, err := cmd.CombinedOutput()
	t.Logf("Output:\n%s", out)

	// We expect this to succeed (exit 0) — our real skills should be valid
	if err != nil {
		t.Errorf("conclave lint failed on real skills: %v\n%s", err, out)
	}
}

func TestLintBadFixtures(t *testing.T) {
	binPath := filepath.Join(t.TempDir(), "conclave")
	build := exec.Command("go", "build", "-o", binPath, "./cmd/conclave/")
	build.Dir = findRepoRoot(t)
	if out, err := build.CombinedOutput(); err != nil {
		t.Fatalf("build failed: %s\n%s", err, out)
	}

	// Create a bad skill
	dir := t.TempDir()
	skillDir := filepath.Join(dir, "skills", "Bad_Skill")
	os.MkdirAll(skillDir, 0755)
	os.WriteFile(filepath.Join(skillDir, "SKILL.md"), []byte("---\nname: Bad_Skill\ndescription: Does stuff\n---\nBody.\n"), 0644)

	cmd := exec.Command(binPath, "lint", filepath.Join(dir, "skills"))
	cmd.Dir = dir
	out, _ := cmd.CombinedOutput()
	t.Logf("Output:\n%s", out)

	if cmd.ProcessState.ExitCode() == 0 {
		t.Error("expected non-zero exit for bad fixtures")
	}
}

func findRepoRoot(t *testing.T) string {
	t.Helper()
	cmd := exec.Command("git", "rev-parse", "--show-toplevel")
	out, err := cmd.Output()
	if err != nil {
		t.Fatal("not in a git repo")
	}
	return strings.TrimSpace(string(out))
}
```

**Step 2: Run the integration test**

Run: `go test ./internal/lint/ -tags=integration -run 'TestLintReal|TestLintBad' -v`
Expected: PASS (real skills are valid, bad fixtures fail)

**Step 3: Commit**

```bash
git add internal/lint/lint_integration_test.go
git commit -m "test(lint): add integration smoke tests"
```

---

### Task 10: Run full test suite and verify

**Files:** none (verification only)

**Dependencies:** Task 1, Task 2, Task 3, Task 4, Task 5, Task 6, Task 7, Task 8, Task 9

**Step 1: Run all lint package tests**

Run: `go test ./internal/lint/ -v -race`
Expected: PASS — all unit tests green

**Step 2: Run all project tests**

Run: `go test ./... -race`
Expected: PASS — no regressions in any package

**Step 3: Build binary and test CLI end-to-end**

Run: `go build -o /tmp/conclave-lint-test ./cmd/conclave/ && /tmp/conclave-lint-test lint`
Expected: Runs lint on real skills, prints results (should be exit 0 if all skills are valid)

Run: `/tmp/conclave-lint-test lint --json`
Expected: JSON array output

Run: `/tmp/conclave-lint-test lint --word-limit 10`
Expected: Word count warnings for most skills

**Step 4: Clean up temp binary**

Run: `rm /tmp/conclave-lint-test`
