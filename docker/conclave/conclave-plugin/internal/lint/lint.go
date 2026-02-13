package lint

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"regexp"
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

	if !strings.HasPrefix(content, "---\n") {
		ps.body = content
		return ps, nil
	}

	rest := content[4:]
	end := strings.Index(rest, "\n---\n")
	if end == -1 {
		ps.body = content
		return ps, nil
	}

	fmText := rest[:end]
	ps.body = rest[end+5:]
	ps.hasFM = true

	ps.frontmatter = make(map[string]interface{})
	if err := yaml.Unmarshal([]byte(fmText), &ps.frontmatter); err != nil {
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

// DefaultWordLimit is the default word count warning threshold.
// Anthropic recommends <5,000 tokens (~3,500-4,000 words) per skill.
const DefaultWordLimit = 3500

// LintOptions configures linting behavior.
type LintOptions struct {
	WordLimit int
}

func (o LintOptions) wordLimit() int {
	if o.WordLimit > 0 {
		return o.WordLimit
	}
	return DefaultWordLimit
}

// LintSkills validates SKILL.md files and returns findings.
func LintSkills(paths []string, knownSkills []string) (*Result, error) {
	return LintSkillsWithOptions(paths, knownSkills, LintOptions{})
}

// LintSkillsWithOptions validates SKILL.md files with configurable options.
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
		if strings.HasPrefix(trimmed, "```") || strings.HasPrefix(trimmed, "~~~") {
			inFencedBlock = !inFencedBlock
			continue
		}
		if inFencedBlock {
			continue
		}
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

func truncate(s string, n int) string {
	if len(s) <= n {
		return s
	}
	return s[:n] + "..."
}

var planFilenameRe = regexp.MustCompile(`^\d{4}-\d{2}-\d{2}-[a-z0-9]+(?:-[a-z0-9]+)*-(?:design|implementation)\.md$`)

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
