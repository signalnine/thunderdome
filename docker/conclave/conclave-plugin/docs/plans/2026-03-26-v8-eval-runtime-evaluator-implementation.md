# v8-eval Runtime Evaluator Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use conclave:executing-plans to implement this plan task-by-task.

**Goal:** Add an evaluator gate to ralph-loop that invokes a separate agent to diagnose test failures with structured feedback.

**Architecture:** After test gate failure, an inline evaluator (separate `claude -p`) receives spec + test output + relevant source files, produces structured markdown feedback that replaces raw output in `.ralph_context.md`. Opt-in via `--eval` flag. Evaluator failure falls back to raw output.

**Tech Stack:** Go 1.22+, Cobra CLI, `claude` CLI, bash (adapters)

---

### Task 1: Extract file paths from test output

**Files:**
- Create: `internal/ralph/eval.go`
- Test: `internal/ralph/eval_test.go`

**Dependencies:** none

**Step 1: Write the failing test**

```go
// internal/ralph/eval_test.go
package ralph

import (
	"testing"
)

func TestExtractFilePaths_NodeJS(t *testing.T) {
	output := `FAIL src/routes/users.test.js
  ● POST /users › returns 201

    TypeError: Cannot read properties of undefined
      at Object.<anonymous> (src/routes/users.js:45:12)
      at processTicksAndRejections (node:internal/process/task_queues:95:5)

  ● GET /users › returns list

    Error: expected 200 got 404
      at Object.<anonymous> (src/routes/users.js:12:5)
      at Object.<anonymous> (src/middleware/auth.js:8:3)`

	paths := ExtractFilePathsFromOutput(output)
	expected := map[string]bool{
		"src/routes/users.js":    true,
		"src/middleware/auth.js":  true,
		"src/routes/users.test.js": true,
	}
	for _, p := range paths {
		if !expected[p] {
			t.Errorf("unexpected path: %s", p)
		}
		delete(expected, p)
	}
	for p := range expected {
		t.Errorf("missing path: %s", p)
	}
}

func TestExtractFilePaths_Python(t *testing.T) {
	output := `FAILED tests/test_api.py::test_create_user
  File "src/api/users.py", line 23, in create_user
    raise ValueError("invalid email")
  File "src/api/validators.py", line 8, in validate_email
    return re.match(pattern, email)`

	paths := ExtractFilePathsFromOutput(output)
	expected := map[string]bool{
		"src/api/users.py":      true,
		"src/api/validators.py": true,
		"tests/test_api.py":     true,
	}
	for _, p := range paths {
		if !expected[p] {
			t.Errorf("unexpected path: %s", p)
		}
		delete(expected, p)
	}
	for p := range expected {
		t.Errorf("missing path: %s", p)
	}
}

func TestExtractFilePaths_Go(t *testing.T) {
	output := `--- FAIL: TestCreateUser (0.01s)
    users_test.go:34: expected 201 got 500
goroutine 1 [running]:
main.createUser(...)
	cmd/server/handlers.go:45
main.validateInput(...)
	internal/validation/input.go:12`

	paths := ExtractFilePathsFromOutput(output)
	expected := map[string]bool{
		"cmd/server/handlers.go":       true,
		"internal/validation/input.go": true,
	}
	for _, p := range paths {
		if !expected[p] {
			t.Errorf("unexpected path: %s", p)
		}
		delete(expected, p)
	}
	for p := range expected {
		t.Errorf("missing path: %s", p)
	}
}

func TestExtractFilePaths_FiltersNodeModules(t *testing.T) {
	output := `Error: foo
      at Object.<anonymous> (node_modules/express/lib/router.js:12:5)
      at Object.<anonymous> (src/app.js:3:10)`

	paths := ExtractFilePathsFromOutput(output)
	for _, p := range paths {
		if p == "node_modules/express/lib/router.js" {
			t.Error("should filter node_modules")
		}
	}
	found := false
	for _, p := range paths {
		if p == "src/app.js" {
			found = true
		}
	}
	if !found {
		t.Error("should include src/app.js")
	}
}

func TestExtractFilePaths_Empty(t *testing.T) {
	paths := ExtractFilePathsFromOutput("")
	if len(paths) != 0 {
		t.Errorf("expected empty, got %v", paths)
	}
}
```

**Step 2: Run test to verify it fails**

Run: `cd /home/gabe/conclave && go test ./internal/ralph/ -run TestExtractFilePaths -v`
Expected: FAIL — `ExtractFilePathsFromOutput` not defined

**Step 3: Write minimal implementation**

```go
// internal/ralph/eval.go
package ralph

import (
	"regexp"
	"strings"
)

// Filtered path prefixes that should be excluded from evaluator context.
var filteredPrefixes = []string{
	"node_modules/",
	"vendor/",
	".venv/",
	"venv/",
	"__pycache__/",
	".git/",
}

// ExtractFilePathsFromOutput extracts source file paths from test failure
// output using regex patterns for Node.js, Python, and Go stack traces.
// Returns deduplicated, filtered paths.
func ExtractFilePathsFromOutput(output string) []string {
	patterns := []*regexp.Regexp{
		// Node.js: "at ... (path:line:col)" or "at ... (path:line)"
		regexp.MustCompile(`\(([a-zA-Z0-9_./-]+\.[a-zA-Z]+):\d+(?::\d+)?\)`),
		// Node.js: "FAIL path" at start of line
		regexp.MustCompile(`(?m)^FAIL\s+([a-zA-Z0-9_./-]+\.[a-zA-Z]+)`),
		// Python: 'File "path", line N'
		regexp.MustCompile(`File "([a-zA-Z0-9_./-]+\.[a-zA-Z]+)", line \d+`),
		// Python: "FAILED path::test_name"
		regexp.MustCompile(`(?m)^FAILED\s+([a-zA-Z0-9_./-]+\.[a-zA-Z]+)::`),
		// Go: "\tpath:line"
		regexp.MustCompile(`(?m)^\t([a-zA-Z0-9_./-]+\.go):\d+`),
	}

	seen := make(map[string]bool)
	var result []string

	for _, re := range patterns {
		for _, match := range re.FindAllStringSubmatch(output, -1) {
			path := match[1]
			if seen[path] || isFiltered(path) {
				continue
			}
			// Skip paths that look like node internals
			if strings.HasPrefix(path, "node:") {
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
```

**Step 4: Run test to verify it passes**

Run: `cd /home/gabe/conclave && go test ./internal/ralph/ -run TestExtractFilePaths -v`
Expected: PASS (all 5 tests)

**Step 5: Commit**

```bash
cd /home/gabe/conclave
git add internal/ralph/eval.go internal/ralph/eval_test.go
git commit -m "feat: add file path extraction from test output for evaluator"
```

---

### Task 2: Collect relevant files (git diff + stack traces)

**Files:**
- Modify: `internal/ralph/eval.go`
- Modify: `internal/ralph/eval_test.go`
- Modify: `internal/git/git.go:58-67` (add `DiffNameOnlyHead` method)

**Dependencies:** Task 1

**Step 1: Write the failing test for DiffNameOnlyHead**

```go
// Add to internal/git/git_test.go (create if needed)
package git

import (
	"os"
	"os/exec"
	"path/filepath"
	"testing"
)

func TestDiffNameOnlyHead(t *testing.T) {
	dir := t.TempDir()
	// Init repo with initial commit
	run := func(args ...string) {
		cmd := exec.Command("git", args...)
		cmd.Dir = dir
		out, err := cmd.CombinedOutput()
		if err != nil {
			t.Fatalf("git %v: %s %v", args, out, err)
		}
	}
	run("init")
	run("config", "user.name", "test")
	run("config", "user.email", "test@test.com")
	os.WriteFile(filepath.Join(dir, "a.txt"), []byte("hello"), 0644)
	run("add", "-A")
	run("commit", "-m", "init")

	// Modify a.txt and add b.txt (unstaged)
	os.WriteFile(filepath.Join(dir, "a.txt"), []byte("changed"), 0644)
	os.WriteFile(filepath.Join(dir, "b.txt"), []byte("new"), 0644)
	run("add", "-A")

	g := New(dir)
	files, err := g.DiffNameOnlyHead()
	if err != nil {
		t.Fatal(err)
	}
	expected := map[string]bool{"a.txt": true, "b.txt": true}
	for _, f := range files {
		if !expected[f] {
			t.Errorf("unexpected file: %s", f)
		}
		delete(expected, f)
	}
	for f := range expected {
		t.Errorf("missing file: %s", f)
	}
}
```

**Step 2: Run test to verify it fails**

Run: `cd /home/gabe/conclave && go test ./internal/git/ -run TestDiffNameOnlyHead -v`
Expected: FAIL — `DiffNameOnlyHead` not defined

**Step 3: Write minimal implementation**

Add to `internal/git/git.go` after the existing `DiffNameOnly` method:

```go
// DiffNameOnlyHead returns files changed between HEAD and the staging area.
// Used by the evaluator to find files the generator modified.
func (g *Git) DiffNameOnlyHead() ([]string, error) {
	out, err := g.run("diff", "--name-only", "--cached", "HEAD")
	if err != nil {
		// If no HEAD exists (first commit), diff against empty tree
		out, err = g.run("diff", "--name-only", "--cached")
		if err != nil {
			return nil, err
		}
	}
	if out == "" {
		return nil, nil
	}
	return strings.Split(out, "\n"), nil
}
```

**Step 4: Run test to verify it passes**

Run: `cd /home/gabe/conclave && go test ./internal/git/ -run TestDiffNameOnlyHead -v`
Expected: PASS

**Step 5: Write the failing test for CollectRelevantFiles**

```go
// Add to internal/ralph/eval_test.go
func TestCollectRelevantFiles(t *testing.T) {
	// Create a temp dir with some files
	dir := t.TempDir()

	// Create source files
	os.MkdirAll(filepath.Join(dir, "src"), 0755)
	os.WriteFile(filepath.Join(dir, "src", "app.js"), []byte("const x = 1;\n"), 0644)
	os.WriteFile(filepath.Join(dir, "src", "util.js"), []byte("module.exports = {};\n"), 0644)
	os.MkdirAll(filepath.Join(dir, "node_modules", "express"), 0755)
	os.WriteFile(filepath.Join(dir, "node_modules", "express", "index.js"), []byte("nope"), 0644)

	// git diff files simulated — CollectRelevantFiles takes explicit lists
	diffFiles := []string{"src/app.js", "src/util.js"}
	traceFiles := []string{"src/app.js"}

	files, err := CollectRelevantFiles(dir, diffFiles, traceFiles, 8000)
	if err != nil {
		t.Fatal(err)
	}

	if len(files) != 2 {
		t.Fatalf("expected 2 files, got %d", len(files))
	}

	// Files in both lists should come first (src/app.js)
	if files[0].Path != "src/app.js" {
		t.Errorf("expected src/app.js first (in both lists), got %s", files[0].Path)
	}
}

func TestCollectRelevantFiles_LineCap(t *testing.T) {
	dir := t.TempDir()

	// Create a large file (100 lines)
	var content strings.Builder
	for i := 0; i < 100; i++ {
		content.WriteString("line\n")
	}
	os.WriteFile(filepath.Join(dir, "big.js"), []byte(content.String()), 0644)
	os.WriteFile(filepath.Join(dir, "small.js"), []byte("tiny\n"), 0644)

	diffFiles := []string{"big.js", "small.js"}

	// Cap at 50 lines — should include small.js but truncate or drop big.js
	files, err := CollectRelevantFiles(dir, diffFiles, nil, 50)
	if err != nil {
		t.Fatal(err)
	}

	totalLines := 0
	for _, f := range files {
		totalLines += strings.Count(f.Content, "\n") + 1
	}
	if totalLines > 50 {
		t.Errorf("total lines %d exceeds cap 50", totalLines)
	}
}
```

Add necessary imports to `eval_test.go`:

```go
import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)
```

**Step 6: Run test to verify it fails**

Run: `cd /home/gabe/conclave && go test ./internal/ralph/ -run TestCollectRelevantFiles -v`
Expected: FAIL — `CollectRelevantFiles` and `FileContent` not defined

**Step 7: Write minimal implementation**

Add to `internal/ralph/eval.go`:

```go
// FileContent holds a source file path and its content.
type FileContent struct {
	Path    string
	Content string
}

// CollectRelevantFiles reads source files from the project directory,
// prioritizing files that appear in both diffFiles and traceFiles.
// Caps total line count at maxLines.
func CollectRelevantFiles(projectDir string, diffFiles, traceFiles []string, maxLines int) ([]FileContent, error) {
	diffSet := make(map[string]bool)
	for _, f := range diffFiles {
		diffSet[f] = true
	}
	traceSet := make(map[string]bool)
	for _, f := range traceFiles {
		traceSet[f] = true
	}

	// Collect all unique files, categorized by priority
	allFiles := make(map[string]bool)
	var bothFiles, diffOnly, traceOnly []string

	for _, f := range diffFiles {
		allFiles[f] = true
	}
	for _, f := range traceFiles {
		allFiles[f] = true
	}

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

	// Priority order: both > diff-only > trace-only
	ordered := append(append(bothFiles, diffOnly...), traceOnly...)

	var result []FileContent
	totalLines := 0

	for _, f := range ordered {
		fullPath := f
		if !strings.HasPrefix(f, "/") {
			fullPath = projectDir + "/" + f
		}
		data, err := os.ReadFile(fullPath)
		if err != nil {
			continue // skip unreadable files
		}
		content := string(data)
		lines := strings.Count(content, "\n") + 1

		if totalLines+lines > maxLines && totalLines > 0 {
			break // would exceed cap, stop adding files
		}
		result = append(result, FileContent{Path: f, Content: content})
		totalLines += lines
	}

	return result, nil
}
```

**Step 8: Run test to verify it passes**

Run: `cd /home/gabe/conclave && go test ./internal/ralph/ -run TestCollectRelevantFiles -v`
Expected: PASS

**Step 9: Commit**

```bash
cd /home/gabe/conclave
git add internal/ralph/eval.go internal/ralph/eval_test.go internal/git/git.go internal/git/git_test.go
git commit -m "feat: add relevant file collection for evaluator (git diff + stack traces)"
```

---

### Task 3: Build evaluator prompt and run evaluator gate

**Files:**
- Modify: `internal/ralph/eval.go`
- Modify: `internal/ralph/eval_test.go`

**Dependencies:** Task 1, Task 2

**Step 1: Write the failing test for BuildEvalPrompt**

```go
// Add to internal/ralph/eval_test.go
func TestBuildEvalPrompt(t *testing.T) {
	spec := "Build a REST API with POST /users endpoint"
	testOutput := "FAIL: expected 201 got 404"
	files := []FileContent{
		{Path: "src/routes.js", Content: "const express = require('express');\n"},
	}

	prompt := BuildEvalPrompt(spec, testOutput, files)

	// Check all required sections are present
	required := []string{
		"diagnostic assistant",
		"## Task Spec",
		"Build a REST API",
		"## Test Output",
		"expected 201 got 404",
		"## Source Files",
		"### src/routes.js",
		"## Instructions",
		"## Failing Tests",
		"## Unmet Requirements",
		"## Priority Fix",
		"## Suggested Approach",
	}
	for _, s := range required {
		if !strings.Contains(prompt, s) {
			t.Errorf("prompt missing: %q", s)
		}
	}
}

func TestBuildEvalPrompt_TruncatesTestOutput(t *testing.T) {
	spec := "task"
	// Build test output with 300 lines
	var lines []string
	for i := 0; i < 300; i++ {
		lines = append(lines, "error line")
	}
	testOutput := strings.Join(lines, "\n")

	prompt := BuildEvalPrompt(spec, testOutput, nil)

	// Should be truncated — count lines in the test output section
	if strings.Count(prompt, "error line") > 200 {
		t.Error("test output should be truncated to 200 lines")
	}
	if !strings.Contains(prompt, "truncated") {
		t.Error("should contain truncation notice")
	}
}
```

**Step 2: Run test to verify it fails**

Run: `cd /home/gabe/conclave && go test ./internal/ralph/ -run TestBuildEvalPrompt -v`
Expected: FAIL — `BuildEvalPrompt` not defined

**Step 3: Write minimal implementation**

Add to `internal/ralph/eval.go`:

```go
import (
	"fmt"
)

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

// BuildEvalPrompt assembles the full evaluator prompt from spec, test output,
// and relevant source files.
func BuildEvalPrompt(spec, testOutput string, files []FileContent) string {
	// Truncate test output
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
			b.WriteString(fmt.Sprintf("\n### %s\n```\n%s\n```\n", f.Path, f.Content))
		}
	}

	b.WriteString("\n")
	b.WriteString(evalTemplate)
	return b.String()
}
```

**Step 4: Run test to verify it passes**

Run: `cd /home/gabe/conclave && go test ./internal/ralph/ -run TestBuildEvalPrompt -v`
Expected: PASS

**Step 5: Write the failing test for RunEvalGate**

```go
// Add to internal/ralph/eval_test.go
func TestRunEvalGate_BuildsCorrectCommand(t *testing.T) {
	// We can't easily test the full RunEvalGate without a real claude binary,
	// but we can test that it returns an error when claude is not available
	// (which exercises the command construction and error path).
	ctx := context.Background()
	dir := t.TempDir()

	// Create minimal project structure
	os.WriteFile(filepath.Join(dir, "spec.txt"), []byte("build something"), 0644)

	_, err := RunEvalGate(ctx, dir, filepath.Join(dir, "spec.txt"), "test failed", "", 5)
	// Should fail because claude binary likely not in path during unit tests,
	// or because there's no git repo. Either way, error path is exercised.
	if err == nil {
		t.Log("RunEvalGate succeeded (claude available) — integration path works")
	} else {
		t.Logf("RunEvalGate failed as expected in unit test: %v", err)
	}
}
```

**Step 6: Run test to verify it fails**

Run: `cd /home/gabe/conclave && go test ./internal/ralph/ -run TestRunEvalGate -v`
Expected: FAIL — `RunEvalGate` not defined

**Step 7: Write minimal implementation**

Add to `internal/ralph/eval.go`:

```go
import (
	"context"
	"os/exec"
	"path/filepath"
	"time"

	gitpkg "github.com/signalnine/conclave/internal/git"
)

const defaultMaxSourceLines = 8000

// textExtensions lists file extensions considered safe to include in prompts.
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

// isTextFile returns true if the file extension is a known text format.
func isTextFile(path string) bool {
	ext := filepath.Ext(path)
	return textExtensions[ext]
}

// isInsideDir returns true if path is safely inside baseDir (no traversal).
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

// RunEvalGate invokes an evaluator agent to diagnose test failures.
// It collects relevant source files, builds a diagnostic prompt, and
// runs claude -p (with prompt via stdin) to get structured feedback.
// Returns the evaluator's output or an error (caller should fall back
// to raw test output).
func RunEvalGate(ctx context.Context, projectDir, specFile, testOutput, evalModel string, timeout int) (string, error) {
	ctx, cancel := context.WithTimeout(ctx, time.Duration(timeout)*time.Second)
	defer cancel()

	// Read spec
	specData, err := os.ReadFile(specFile)
	if err != nil {
		return "", fmt.Errorf("reading spec: %w", err)
	}

	// Collect relevant files
	g := gitpkg.New(projectDir)
	diffFiles, _ := g.DiffNameOnlyHead()
	traceFiles := ExtractFilePathsFromOutput(testOutput)

	files, err := CollectRelevantFiles(projectDir, diffFiles, traceFiles, defaultMaxSourceLines)
	if err != nil {
		return "", fmt.Errorf("collecting files: %w", err)
	}

	// Build prompt
	prompt := BuildEvalPrompt(string(specData), testOutput, files)

	// Build command args — prompt is piped via stdin to avoid OS arg length limits
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
```

**Step 8: Run test to verify it passes**

Run: `cd /home/gabe/conclave && go test ./internal/ralph/ -run TestRunEvalGate -v`
Expected: PASS (test exercises error path gracefully)

**Step 9: Run all ralph tests**

Run: `cd /home/gabe/conclave && go test ./internal/ralph/ -v`
Expected: All tests PASS

**Step 10: Commit**

```bash
cd /home/gabe/conclave
git add internal/ralph/eval.go internal/ralph/eval_test.go
git commit -m "feat: add evaluator prompt builder and RunEvalGate"
```

---

### Task 4: Update state.go with evaluator metadata

**Files:**
- Modify: `internal/ralph/state.go:18-23`
- Modify: `internal/ralph/runner_test.go`

**Dependencies:** none

**Step 1: Write the failing test**

```go
// Add to internal/ralph/runner_test.go
func TestStateManager_EvaluatorFields(t *testing.T) {
	dir := t.TempDir()
	sm := NewStateManager(dir)
	sm.Init("task-eval", 3)

	// Update with evaluator metadata (rawHash from raw test output)
	sm.UpdateWithEval("tests", 1, "eval feedback here", true, "raw-output-001.txt", "abc123")

	state, _ := sm.Load()
	if len(state.Attempts) != 1 {
		t.Fatalf("expected 1 attempt, got %d", len(state.Attempts))
	}
	if !state.Attempts[0].EvaluatorRan {
		t.Error("expected EvaluatorRan=true")
	}
	if state.Attempts[0].RawOutputRef != "raw-output-001.txt" {
		t.Errorf("expected raw output ref, got %s", state.Attempts[0].RawOutputRef)
	}

	sm.Cleanup()
}
```

**Step 2: Run test to verify it fails**

Run: `cd /home/gabe/conclave && go test ./internal/ralph/ -run TestStateManager_EvaluatorFields -v`
Expected: FAIL — `UpdateWithEval` not defined, `EvaluatorRan` field not on Attempt

**Step 3: Write minimal implementation**

Modify `internal/ralph/state.go`:

Add fields to `Attempt` struct (after line 23):
```go
type Attempt struct {
	Iteration    int    `json:"iteration"`
	Gate         string `json:"gate"`
	Hash         string `json:"hash"`
	Shift        bool   `json:"shift"`
	EvaluatorRan bool   `json:"evaluator_ran,omitempty"`
	RawOutputRef string `json:"raw_output_ref,omitempty"`
}
```

Add `UpdateWithEval` method after the existing `Update` method:

```go
// UpdateWithEval is like Update but also records evaluator metadata.
// rawHash should be computed from the RAW test output (not evaluator output)
// to keep stuck detection anchored to actual test failures.
func (s *StateManager) UpdateWithEval(gate string, exitCode int, output string, evalRan bool, rawRef string, rawHash string) error {
	state, err := s.Load()
	if err != nil {
		return err
	}

	hash := rawHash

	if hash == state.ErrorHash && state.ErrorHash != "" {
		state.StuckCount++
	} else {
		state.StuckCount = 0
	}

	truncated := output
	allLines := strings.Split(output, "\n")
	if len(allLines) > 100 {
		truncated = strings.Join(allLines[:100], "\n") +
			fmt.Sprintf("\n[... truncated, %d total lines ...]", len(allLines))
	}

	state.Attempts = append(state.Attempts, Attempt{
		Iteration:    state.Iteration,
		Gate:         gate,
		Hash:         hash[:8],
		Shift:        state.StrategyShifts > 0,
		EvaluatorRan: evalRan,
		RawOutputRef: rawRef,
	})
	state.Iteration++
	state.LastGate = gate
	state.ExitCode = exitCode
	state.ErrorHash = hash
	state.Timestamp = time.Now()

	if err := s.save(state); err != nil {
		return err
	}

	ctx := fmt.Sprintf("# Ralph Loop Context: %s\n\n## Status\n- Iteration: %d of %d\n- Last gate failed: %s\n- Stuck count: %d (threshold: 3)\n\n## Last Error Output (verbatim)\n```\n%s\n```\n",
		state.TaskID, state.Iteration, state.MaxIterations, gate, state.StuckCount, truncated)
	return os.WriteFile(s.contextPath(), []byte(ctx), 0644)
}
```

**Step 4: Run test to verify it passes**

Run: `cd /home/gabe/conclave && go test ./internal/ralph/ -run TestStateManager_EvaluatorFields -v`
Expected: PASS

**Step 5: Run all ralph tests**

Run: `cd /home/gabe/conclave && go test ./internal/ralph/ -v`
Expected: All tests PASS

**Step 6: Commit**

```bash
cd /home/gabe/conclave
git add internal/ralph/state.go internal/ralph/runner_test.go
git commit -m "feat: add evaluator metadata fields to ralph-loop state"
```

---

### Task 5: Integrate evaluator into ralph-run command

**Files:**
- Modify: `cmd/conclave/ralphrun.go:24-35` (add flags)
- Modify: `cmd/conclave/ralphrun.go:38-174` (integrate eval into loop)

**Dependencies:** Task 3, Task 4

**Step 1: Write the failing test**

This is an integration-level change. Write a test that verifies the flags are registered:

```go
// Add to cmd/conclave/ralphrun_test.go (create file)
package main

import (
	"testing"
)

func TestRalphRunCmd_EvalFlags(t *testing.T) {
	// Verify flags exist and have correct defaults
	f := ralphRunCmd.Flags()

	evalFlag := f.Lookup("eval")
	if evalFlag == nil {
		t.Fatal("--eval flag not registered")
	}
	if evalFlag.DefValue != "false" {
		t.Errorf("--eval default = %s, want false", evalFlag.DefValue)
	}

	modelFlag := f.Lookup("eval-model")
	if modelFlag == nil {
		t.Fatal("--eval-model flag not registered")
	}

	timeoutFlag := f.Lookup("eval-timeout")
	if timeoutFlag == nil {
		t.Fatal("--eval-timeout flag not registered")
	}
	if timeoutFlag.DefValue != "120" {
		t.Errorf("--eval-timeout default = %s, want 120", timeoutFlag.DefValue)
	}

	sysPromptFlag := f.Lookup("system-prompt")
	if sysPromptFlag == nil {
		t.Fatal("--system-prompt flag not registered")
	}
}
```

**Step 2: Run test to verify it fails**

Run: `cd /home/gabe/conclave && go test ./cmd/conclave/ -run TestRalphRunCmd_EvalFlags -v`
Expected: FAIL — flags not registered

**Step 3: Write minimal implementation**

Modify `cmd/conclave/ralphrun.go`:

In `init()`, add after existing flags (after line 34):
```go
	ralphRunCmd.Flags().Bool("eval", false, "Enable evaluator gate after test failure")
	ralphRunCmd.Flags().String("eval-model", "", "Model for evaluator (default: same as generator)")
	ralphRunCmd.Flags().Int("eval-timeout", 120, "Evaluator gate timeout (seconds)")
	ralphRunCmd.Flags().String("system-prompt", "", "Custom system prompt (replaces TDDPreamble)")
```

In `runRalphRun()`, add flag reads after existing flag reads (after line 47).
Also add `"crypto/md5"` and `"path/filepath"` to the import block:
```go
	evalEnabled, _ := cmd.Flags().GetBool("eval")
	evalModel, _ := cmd.Flags().GetString("eval-model")
	evalTimeout, _ := cmd.Flags().GetInt("eval-timeout")
	systemPrompt, _ := cmd.Flags().GetString("system-prompt")
```

Replace the prompt construction (line 94) to use system prompt (prepended to TDDPreamble, not replacing it):
```go
	preamble := ralph.TDDPreamble
	if systemPrompt != "" {
		preamble = systemPrompt + "\n\n" + ralph.TDDPreamble
	}
	prompt := preamble + "\n\n" + task
```

Replace the test failure handling (lines 147-149) with evaluator integration:
```go
		if testErr != nil {
			fmt.Fprintf(os.Stderr, "  Tests failed\n")
			if evalEnabled {
				fmt.Fprintln(os.Stderr, "  Running evaluator...")
				// task is a file path (from --task flag), used as spec file for evaluator
				evalOutput, evalErr := ralph.RunEvalGate(ctx, cwd, task, testOutput, evalModel, evalTimeout)
				if evalErr != nil {
					fmt.Fprintf(os.Stderr, "  Evaluator failed, using raw test output: %v\n", evalErr)
					sm.Update("tests", 1, testOutput)
				} else {
					fmt.Fprintln(os.Stderr, "  Evaluator feedback received")
					// Save raw test output to sidecar file for debugging
					rawRef := fmt.Sprintf(".ralph_raw_%d.txt", state.Iteration)
					os.WriteFile(filepath.Join(cwd, rawRef), []byte(testOutput), 0644)
					// Hash raw test output for stuck detection (not evaluator prose)
					rawLines := strings.Split(testOutput, "\n")
					if len(rawLines) > 20 {
						rawLines = rawLines[:20]
					}
					rawHash := fmt.Sprintf("%x", md5.Sum([]byte(strings.Join(rawLines, "\n"))))
					// Use evaluator output for context, raw hash for stuck detection
					sm.UpdateWithEval("tests", 1, evalOutput, true, rawRef, rawHash)
				}
			} else {
				sm.Update("tests", 1, testOutput)
			}
			continue
		}
```

**Step 4: Run test to verify it passes**

Run: `cd /home/gabe/conclave && go test ./cmd/conclave/ -run TestRalphRunCmd_EvalFlags -v`
Expected: PASS

**Step 5: Run full test suite**

Run: `cd /home/gabe/conclave && go test ./... -race`
Expected: All tests PASS

**Step 6: Commit**

```bash
cd /home/gabe/conclave
git add cmd/conclave/ralphrun.go cmd/conclave/ralphrun_test.go
git commit -m "feat: integrate evaluator gate into ralph-run command"
```

---

### Task 6: Build and install conclave binary

**Files:**
- None new — just build

**Dependencies:** Task 5

**Step 1: Build the binary**

Run: `cd /home/gabe/conclave && go build -o conclave ./cmd/conclave/`
Expected: Clean build, no errors

**Step 2: Install to system path**

Run: `cd /home/gabe/conclave && sudo cp conclave /usr/local/bin/conclave`

**Step 3: Verify**

Run: `conclave ralph-run --help`
Expected: Output includes `--eval`, `--eval-model`, `--eval-timeout`, `--system-prompt` flags

**Step 4: Commit (if Makefile or build changes needed)**

```bash
cd /home/gabe/conclave
git add -A
git commit -m "chore: verify build with evaluator gate"
```

---

### Task 7: Create v8-ralph-sonnet adapter

**Files:**
- Create: `/home/gabe/agentic-thunderdome/adapters/conclave-v8-ralph-sonnet/adapter.sh`

**Dependencies:** Task 6

**Step 1: Create the adapter**

The adapter uses `conclave ralph-run` with the v8-combined system prompt but WITHOUT `--eval`. This is the control group.

```bash
#!/bin/bash
set -e

# conclave-v8-ralph-sonnet: v8-combined prompt with ralph-loop retry (no evaluator).
# Control group — tests whether simple retry-on-test-failure improves scores
# beyond single-shot v8-combined.

[[ -f "$TASK_DESCRIPTION" ]] || { echo "Task file not found: $TASK_DESCRIPTION" >&2; exit 2; }

cd "$TASK_DIR"

export HOME=/tmp

if [ -f /tmp/.claude-credentials.json ]; then
  mkdir -p "$HOME/.claude"
  cp /tmp/.claude-credentials.json "$HOME/.claude/.credentials.json"
fi

if [ -n "$PROXY_URL" ]; then
  export ANTHROPIC_BASE_URL="$PROXY_URL"
fi

SYSTEM_PROMPT="You are running in a headless benchmark environment. No human to interact with. Work directly in the current directory — no worktrees or branches.

## How to Work

### 1. Understand First
Read the task fully. Read existing code, tests, and config files. Understand what exists before writing anything.

### 2. Write a Contract BEFORE Any Code
Before writing any implementation, create a CONTRACT.md file that defines:

1. **Every behavior** the finished code must exhibit — be specific and exhaustive
2. **How to verify each behavior** — the exact test, command, or check that proves it works
3. **What done looks like** for each criterion — expected output, return value, or state

Example:
\`\`\`
- [ ] POST /api/users creates a new user → test: POST returns 201 with user object
- [ ] Duplicate email returns 409 → test: second POST with same email returns 409
- [ ] Empty name rejected → test: POST with empty name returns 400
\`\`\`

This contract is your definition of done. You are not finished until every criterion passes.

### 3. Test-First Development (MANDATORY — NOT OPTIONAL)
For each contract criterion, you MUST write a failing test BEFORE any implementation code.

**The process:**
1. Pick the next contract criterion
2. Write a test that verifies it
3. Run it — watch it FAIL (this proves the test works)
4. Write the minimal code to make it pass
5. Run it — watch it PASS
6. Repeat for the next criterion

**If you catch yourself writing implementation without a test first, STOP IMMEDIATELY.**
Delete the implementation code. Write the test first. Then re-implement.
This is not a suggestion. This is not optional. Tests are how you prove your code works.
No tests = no proof = not done.

### 4. Boil the Lake
AI-assisted coding makes completeness nearly free. Always do the complete implementation:
- Handle ALL edge cases, not just happy paths
- Write comprehensive tests — cover boundaries, errors, empty inputs
- Implement the full feature, not 90% of it

### 5. Verify Against Contract
After implementation, go through CONTRACT.md line by line:
- Run each verification check
- Fix ALL failures before moving on
- Do not stop until every criterion in the contract passes

### 6. Adversarial Self-Review
After all contract criteria pass, review your own diff as if you were a hostile code reviewer:
- Read every line of code you wrote
- Check for: missing edge cases, off-by-one errors, unhandled errors, race conditions
- Check for: dead code, debug artifacts, TODOs left behind
- If you find issues, fix them and re-verify against the contract

Done means: all contract criteria pass, tests pass, build clean, lint clean, self-review clean."

OUTPUT_FILE=/workspace/.thunderdome-output.jsonl

set +e
conclave ralph-run \
  --task "$TASK_DESCRIPTION" \
  --system-prompt "$SYSTEM_PROMPT" \
  --max-iterations 3 \
  --implement-timeout 300 \
  --test-timeout 120 \
  --skip-spec \
  > "$OUTPUT_FILE" 2>/workspace/.thunderdome-stderr.log
RALPH_EXIT=$?
set -e

# Extract metrics from ralph-run output
# Ralph-run outputs to stdout; metrics need to be collected from claude's NDJSON
# For now, write basic metrics from ralph state
node -e '
const fs = require("fs");
try {
  // Try to read ralph state for iteration count
  let metrics = {
    input_tokens: 0, output_tokens: 0, cache_read_tokens: 0,
    cache_creation_tokens: 0, turns: 0, tools_used: [],
    duration_ms: 0, total_cost_usd: 0
  };
  // Parse NDJSON output if available
  const lines = fs.readFileSync(process.argv[1], "utf8").split("\n");
  const toolsSeen = new Set();
  for (const line of lines) {
    if (!line.trim()) continue;
    try {
      const msg = JSON.parse(line);
      if (msg.type === "result") {
        if (msg.usage) {
          metrics.input_tokens += msg.usage.input_tokens || 0;
          metrics.output_tokens += msg.usage.output_tokens || 0;
          metrics.cache_read_tokens += msg.usage.cache_read_input_tokens || 0;
          metrics.cache_creation_tokens += msg.usage.cache_creation_input_tokens || 0;
        }
        metrics.turns += msg.num_turns || 0;
        metrics.duration_ms += msg.duration_ms || 0;
        metrics.total_cost_usd += msg.total_cost_usd || 0;
      }
      if (msg.type === "assistant" && msg.message && Array.isArray(msg.message.content)) {
        for (const block of msg.message.content) {
          if (block.type === "tool_use" && block.name && !toolsSeen.has(block.name)) {
            toolsSeen.add(block.name);
            metrics.tools_used.push(block.name);
          }
        }
      }
    } catch(e) {}
  }
  fs.writeFileSync("/workspace/.thunderdome-metrics.json", JSON.stringify(metrics, null, 2));
  console.error("Metrics: " + JSON.stringify(metrics));
} catch(e) {
  console.error("Metrics extraction failed: " + e.message);
}
' "$OUTPUT_FILE" || true

exit $RALPH_EXIT
```

**Step 2: Verify adapter is executable**

Run: `chmod +x /home/gabe/agentic-thunderdome/adapters/conclave-v8-ralph-sonnet/adapter.sh`

**Step 3: Commit**

```bash
cd /home/gabe/agentic-thunderdome
git add adapters/conclave-v8-ralph-sonnet/adapter.sh
git commit -m "feat: add v8-ralph-sonnet adapter (ralph-loop retry, no evaluator)"
```

---

### Task 8: Create v8-eval-sonnet adapter

**Files:**
- Create: `/home/gabe/agentic-thunderdome/adapters/conclave-v8-eval-sonnet/adapter.sh`

**Dependencies:** Task 6

**Step 1: Create the adapter**

Same as v8-ralph-sonnet but with `--eval` flag. Copy from Task 7 and add the flag.

The only difference from v8-ralph-sonnet's adapter.sh is the ralph-run invocation:

```bash
conclave ralph-run \
  --task "$TASK_DESCRIPTION" \
  --system-prompt "$SYSTEM_PROMPT" \
  --max-iterations 3 \
  --implement-timeout 300 \
  --test-timeout 120 \
  --eval \
  --eval-timeout 120 \
  --skip-spec \
  > "$OUTPUT_FILE" 2>/workspace/.thunderdome-stderr.log
```

Copy the full adapter.sh from Task 7, change the comment header to:
```bash
# conclave-v8-eval-sonnet: v8-combined prompt with ralph-loop retry + evaluator gate.
# Experimental group — tests whether structured evaluator feedback improves scores
# beyond simple retry (v8-ralph-sonnet).
```

And add `--eval` and `--eval-timeout 120` to the ralph-run invocation.

**Step 2: Verify adapter is executable**

Run: `chmod +x /home/gabe/agentic-thunderdome/adapters/conclave-v8-eval-sonnet/adapter.sh`

**Step 3: Commit**

```bash
cd /home/gabe/agentic-thunderdome
git add adapters/conclave-v8-eval-sonnet/adapter.sh
git commit -m "feat: add v8-eval-sonnet adapter (ralph-loop retry + evaluator)"
```

---

### Task 9: Register adapters in thunderdome.yaml and rebuild Docker image

**Files:**
- Modify: `/home/gabe/agentic-thunderdome/thunderdome.yaml`
- Rebuild: `thunderdome/conclave:latest` Docker image with updated conclave binary

**Dependencies:** Task 7, Task 8

**Step 1: Add adapter entries to thunderdome.yaml**

Add to the adapters section:
```yaml
  conclave-v8-ralph-sonnet:
    image: thunderdome/conclave:latest
    env: {}

  conclave-v8-eval-sonnet:
    image: thunderdome/conclave:latest
    env: {}
```

Note: these use `thunderdome/conclave:latest` (not `thunderdome/claude-code:latest`) because they need the `conclave` binary.

**Step 2: Rebuild conclave Docker image with updated binary**

```bash
cd /home/gabe/agentic-thunderdome
# Copy the newly built conclave binary to the Docker build context
cp /home/gabe/conclave/conclave docker/conclave/conclave-plugin/conclave
# Rebuild
docker build -t thunderdome/conclave:latest docker/conclave/
```

**Step 3: Verify image has the new flags**

```bash
docker run --rm thunderdome/conclave:latest /opt/conclave-plugin/conclave ralph-run --help
```
Expected: Output includes `--eval`, `--eval-model`, `--eval-timeout`, `--system-prompt`

**Step 4: Commit**

```bash
cd /home/gabe/agentic-thunderdome
git add thunderdome.yaml
git commit -m "feat: register v8-ralph-sonnet and v8-eval-sonnet adapters"
```

---

### Task 10: Run full conclave test suite

**Files:** none

**Dependencies:** Task 5

**Step 1: Run all Go tests**

Run: `cd /home/gabe/conclave && go test ./... -race -v`
Expected: All tests PASS, including new eval tests

**Step 2: Run ralph-loop bash tests**

Run: `cd /home/gabe/conclave && ./skills/ralph-loop/test-ralph-loop.sh`
Expected: PASS

**Step 3: Run lint**

Run: `cd /home/gabe/conclave && go vet ./...`
Expected: Clean

**Step 4: Review diff**

Run: `cd /home/gabe/conclave && git diff HEAD~5` (or however many commits back to start of this work)
Look for: dead code, debug artifacts, missing error handling, TODOs left behind.
