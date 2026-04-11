package ralph

import (
	"context"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"sort"
	"strings"
	"time"

	gitpkg "github.com/signalnine/conclave/internal/git"
)

var filteredPrefixes = []string{
	"node_modules/", "vendor/", ".venv/", "venv/",
	"__pycache__/", ".git/",
}

var textExtensions = map[string]bool{
	".go": true, ".js": true, ".ts": true, ".jsx": true, ".tsx": true,
	".py": true, ".rb": true, ".rs": true, ".java": true, ".c": true,
	".h": true, ".cpp": true, ".cs": true, ".php": true, ".swift": true,
	".kt": true, ".scala": true, ".sh": true, ".bash": true, ".zsh": true,
	".json": true, ".yaml": true, ".yml": true, ".toml": true, ".xml": true,
	".html": true, ".css": true, ".scss": true, ".less": true, ".sql": true,
	".md": true, ".txt": true, ".cfg": true, ".ini": true, ".env": true,
	".graphql": true, ".proto": true, ".vue": true, ".svelte": true,
}

func ExtractFilePathsFromOutput(output string) []string {
	patterns := []*regexp.Regexp{
		regexp.MustCompile(`\(([a-zA-Z0-9_./-]+\.[a-zA-Z]+):\d+(?::\d+)?\)`),
		regexp.MustCompile(`(?m)^FAIL\s+([a-zA-Z0-9_./-]+\.[a-zA-Z]+)`),
		regexp.MustCompile(`File "([a-zA-Z0-9_./-]+\.[a-zA-Z]+)", line \d+`),
		regexp.MustCompile(`(?m)^FAILED\s+([a-zA-Z0-9_./-]+\.[a-zA-Z]+)::`),
		regexp.MustCompile(`(?m)^\t([a-zA-Z0-9_./-]+\.go):\d+`),
	}

	seen := make(map[string]bool)
	var result []string

	for _, re := range patterns {
		for _, match := range re.FindAllStringSubmatch(output, -1) {
			path := match[1]
			if seen[path] || isFiltered(path) || strings.HasPrefix(path, "node:") {
				continue
			}
			seen[path] = true
			result = append(result, path)
		}
	}
	return result
}

func isFiltered(path string) bool {
	for _, prefix := range filteredPrefixes {
		if strings.HasPrefix(path, prefix) || strings.Contains(path, "/"+prefix) {
			return true
		}
	}
	return false
}

func isTextFile(path string) bool {
	ext := filepath.Ext(path)
	return textExtensions[ext]
}

// FileContent holds a file's relative path and its text content.
type FileContent struct {
	Path    string
	Content string
}

// CollectRelevantFiles reads files from diffFiles and traceFiles, prioritizing
// files that appear in both lists, then diff-only, then trace-only. It filters
// out binary files, vendor directories, and path traversal attempts. Reading
// stops when maxLines would be exceeded.
func CollectRelevantFiles(projectDir string, diffFiles, traceFiles []string, maxLines int) ([]FileContent, error) {
	diffSet := make(map[string]bool)
	for _, f := range diffFiles {
		diffSet[f] = true
	}
	traceSet := make(map[string]bool)
	for _, f := range traceFiles {
		traceSet[f] = true
	}

	allFiles := make(map[string]bool)
	for _, f := range diffFiles {
		allFiles[f] = true
	}
	for _, f := range traceFiles {
		allFiles[f] = true
	}

	var bothFiles, diffOnly, traceOnly []string
	for f := range allFiles {
		if isFiltered(f) || !isTextFile(f) || !isInsideDir(projectDir, f) {
			continue
		}
		inDiff := diffSet[f]
		inTrace := traceSet[f]
		switch {
		case inDiff && inTrace:
			bothFiles = append(bothFiles, f)
		case inDiff:
			diffOnly = append(diffOnly, f)
		default:
			traceOnly = append(traceOnly, f)
		}
	}

	sort.Strings(bothFiles)
	sort.Strings(diffOnly)
	sort.Strings(traceOnly)
	ordered := append(append(bothFiles, diffOnly...), traceOnly...)

	var result []FileContent
	totalLines := 0

	for _, f := range ordered {
		fullPath := filepath.Join(projectDir, f)
		data, err := os.ReadFile(fullPath)
		if err != nil {
			continue
		}
		content := string(data)
		lines := strings.Count(content, "\n")
		if len(content) > 0 && content[len(content)-1] != '\n' {
			lines++ // Only add 1 for non-newline-terminated files
		}

		if totalLines+lines > maxLines && totalLines > 0 {
			break
		}
		result = append(result, FileContent{Path: f, Content: content})
		totalLines += lines
	}

	return result, nil
}

func isInsideDir(baseDir, path string) bool {
	abs, err := filepath.Abs(filepath.Join(baseDir, path))
	if err != nil {
		return false
	}
	absBase, err := filepath.Abs(baseDir)
	if err != nil {
		return false
	}
	return strings.HasPrefix(abs, absBase+string(filepath.Separator)) || abs == absBase
}

const evalPreamble = `You are a diagnostic assistant. Analyze the test/build/lint failures below, identify root causes, and specify the single most impactful fix. Base your conclusions only on the provided spec, test output, and source files. If the root cause appears to be outside the provided files, say so explicitly rather than speculating.`

const evalTemplate = `## Instructions
Respond using EXACTLY this template. Maximum 5 bullets per section.
Do not restate raw test output verbatim — synthesize into root causes.

## Failing Tests
- [group by root cause, not by test name]

## Unmet Requirements
- [only spec violations evidenced by actual failures]

## Priority Fix
- [exactly one highest-leverage fix, one sentence]

## Suggested Approach
- [3-5 concrete steps at the design/logic level, no code]`

const maxTestOutputLines = 200

// BuildEvalPrompt constructs the prompt sent to the evaluator LLM,
// combining the task spec, test output, and relevant source files.
func BuildEvalPrompt(spec, testOutput string, files []FileContent) string {
	truncated := testOutput
	lines := strings.Split(testOutput, "\n")
	if len(lines) > maxTestOutputLines {
		truncated = strings.Join(lines[:maxTestOutputLines], "\n") +
			fmt.Sprintf("\n[... truncated, %d total lines ...]", len(lines))
	}

	var b strings.Builder
	b.WriteString(evalPreamble)
	b.WriteString("\n\n## Task Spec\n")
	b.WriteString(spec)
	b.WriteString("\n\n## Test Output (verbatim)\n```\n")
	b.WriteString(truncated)
	b.WriteString("\n```\n")

	if len(files) > 0 {
		b.WriteString("\n## Source Files\n")
		for _, f := range files {
			fmt.Fprintf(&b, "\n### %s\n```\n%s\n```\n", f.Path, f.Content)
		}
	}

	b.WriteString("\n")
	b.WriteString(evalTemplate)
	return b.String()
}

const defaultMaxSourceLines = 8000

// RunEvalGate runs the evaluator: collects relevant files from git diff and
// test output traces, builds a prompt, and sends it to claude for analysis.
func RunEvalGate(ctx context.Context, projectDir, specContent, testOutput, evalModel string, timeout int) (string, error) {
	ctx, cancel := context.WithTimeout(ctx, time.Duration(timeout)*time.Second)
	defer cancel()

	g := gitpkg.New(projectDir)
	diffFiles, _ := g.DiffNameOnlyHead()
	traceFiles := ExtractFilePathsFromOutput(testOutput)

	files, err := CollectRelevantFiles(projectDir, diffFiles, traceFiles, defaultMaxSourceLines)
	if err != nil {
		return "", fmt.Errorf("collecting files: %w", err)
	}

	prompt := BuildEvalPrompt(specContent, testOutput, files)

	// Build command — prompt via stdin to avoid OS arg length limits
	cmdArgs := []string{"-p", "--output-format", "text"}
	if evalModel != "" {
		cmdArgs = append(cmdArgs, "--model", evalModel)
	}

	cmd := exec.CommandContext(ctx, "claude", cmdArgs...)
	cmd.Dir = projectDir
	cmd.Stdin = strings.NewReader(prompt)
	out, err := cmd.CombinedOutput()
	if err != nil {
		return "", fmt.Errorf("evaluator failed: %w\noutput: %s", err, string(out))
	}

	return string(out), nil
}
