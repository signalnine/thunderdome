# Thunderdome Behavior Analyzer Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use conclave:executing-plans to implement this plan task-by-task.

**Goal:** Add a `thunderdome analyze` subcommand that extracts behavioral signals from trial NDJSON traces and correlates them with scores to identify which agent behaviors predict high task performance.

**Architecture:** New `internal/analyze/` package with NDJSON parser, behavior extractors, and correlation engine. Wired as a Cobra subcommand alongside existing `run`, `report`, `list`, `rescore`. Reads existing trial data (meta.json + workspace/.thunderdome-output.jsonl) without modifying it.

**Tech Stack:** Go 1.24, encoding/json for NDJSON parsing, math for Pearson correlation, github.com/spf13/cobra for CLI.

**Target repo:** `/home/gabe/agentic-thunderdome/`

---

### Task 1: NDJSON Parser — Extract Tool Call Sequence

**Files:**
- Create: `internal/analyze/ndjson.go`
- Test: `internal/analyze/ndjson_test.go`

**Dependencies:** none

**Context:** The NDJSON file (`.thunderdome-output.jsonl`) contains Claude Code stream-json output. Each line is a JSON object with a `type` field. We need to extract a chronologically-ordered sequence of tool calls (name + key input fields) from `type=assistant` messages containing `tool_use` content blocks.

Message structure:
- `type=assistant` messages have a `message` field (JSON object) with `content` array
- Content blocks with `type=tool_use` have `name` (string) and `input` (object) fields
- For `Write` tool: `input.file_path` is the target file
- For `Bash` tool: `input.command` is the shell command
- For `Edit` tool: `input.file_path` is the target file
- The `message` field may be a JSON string or object — handle both

The `type=result` message contains `num_turns`, `duration_ms`, `total_cost_usd`.

**Step 1: Write the failing test**

Create `internal/analyze/ndjson_test.go`:

```go
package analyze

import (
	"os"
	"path/filepath"
	"testing"
)

func TestParseTrace_Empty(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "output.jsonl")
	os.WriteFile(path, []byte(""), 0644)

	trace, err := ParseTrace(path)
	if err != nil {
		t.Fatal(err)
	}
	if len(trace.ToolCalls) != 0 {
		t.Errorf("expected 0 tool calls, got %d", len(trace.ToolCalls))
	}
}

func TestParseTrace_ToolCalls(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "output.jsonl")

	// Minimal NDJSON with two assistant messages containing tool_use blocks
	lines := `{"type":"system","subtype":"init","session_id":"test"}
{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Write","input":{"file_path":"/workspace/src/index.ts","content":"code"}}]}}
{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Bash","input":{"command":"npm test"}}]}}
{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Write","input":{"file_path":"/workspace/src/__tests__/index.test.ts","content":"test"}}]}}
{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Bash","input":{"command":"git add -A && git commit -m 'feat: init'"}}]}}
{"type":"result","num_turns":4,"duration_ms":60000,"total_cost_usd":1.50}
`
	os.WriteFile(path, []byte(lines), 0644)

	trace, err := ParseTrace(path)
	if err != nil {
		t.Fatal(err)
	}
	if len(trace.ToolCalls) != 4 {
		t.Fatalf("expected 4 tool calls, got %d", len(trace.ToolCalls))
	}
	if trace.ToolCalls[0].Name != "Write" {
		t.Errorf("first call = %q, want Write", trace.ToolCalls[0].Name)
	}
	if trace.ToolCalls[0].FilePath != "/workspace/src/index.ts" {
		t.Errorf("file_path = %q", trace.ToolCalls[0].FilePath)
	}
	if trace.ToolCalls[1].Name != "Bash" {
		t.Errorf("second call = %q, want Bash", trace.ToolCalls[1].Name)
	}
	if trace.ToolCalls[1].Command != "npm test" {
		t.Errorf("command = %q", trace.ToolCalls[1].Command)
	}
	if trace.NumTurns != 4 {
		t.Errorf("num_turns = %d", trace.NumTurns)
	}
	if trace.DurationMS != 60000 {
		t.Errorf("duration_ms = %d", trace.DurationMS)
	}
}

func TestParseTrace_MultipleToolsPerMessage(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "output.jsonl")

	// Single assistant message with two tool_use blocks (parallel calls)
	lines := `{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Read","input":{"file_path":"/workspace/src/a.ts"}},{"type":"tool_use","name":"Read","input":{"file_path":"/workspace/src/b.ts"}}]}}
{"type":"result","num_turns":1,"duration_ms":5000,"total_cost_usd":0.10}
`
	os.WriteFile(path, []byte(lines), 0644)

	trace, err := ParseTrace(path)
	if err != nil {
		t.Fatal(err)
	}
	if len(trace.ToolCalls) != 2 {
		t.Fatalf("expected 2 tool calls, got %d", len(trace.ToolCalls))
	}
}

func TestParseTrace_StringMessage(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "output.jsonl")

	// message field as a JSON string (some Claude Code versions do this)
	lines := `{"type":"assistant","message":"{\"content\":[{\"type\":\"tool_use\",\"name\":\"Bash\",\"input\":{\"command\":\"ls\"}}]}"}
{"type":"result","num_turns":1,"duration_ms":1000,"total_cost_usd":0.01}
`
	os.WriteFile(path, []byte(lines), 0644)

	trace, err := ParseTrace(path)
	if err != nil {
		t.Fatal(err)
	}
	if len(trace.ToolCalls) != 1 {
		t.Fatalf("expected 1 tool call, got %d", len(trace.ToolCalls))
	}
	if trace.ToolCalls[0].Command != "ls" {
		t.Errorf("command = %q", trace.ToolCalls[0].Command)
	}
}
```

**Step 2: Run test to verify it fails**

Run: `cd /home/gabe/agentic-thunderdome && go test ./internal/analyze/ -run TestParseTrace -v`
Expected: FAIL — package/types don't exist yet

**Step 3: Write minimal implementation**

Create `internal/analyze/ndjson.go`:

```go
package analyze

import (
	"bufio"
	"encoding/json"
	"os"
	"strings"
)

// ToolCall represents a single tool invocation extracted from the NDJSON trace.
type ToolCall struct {
	Name     string // Tool name: Write, Bash, Edit, Read, Glob, Grep, etc.
	FilePath string // For Write/Edit/Read: the target file path
	Command  string // For Bash: the shell command
	Index    int    // Chronological position in the trace
}

// Trace is the parsed behavioral trace from a trial's NDJSON output.
type Trace struct {
	ToolCalls    []ToolCall
	NumTurns     int
	DurationMS   int64
	TotalCostUSD float64
}

// ParseTrace reads a Claude Code stream-json NDJSON file and extracts
// the chronological sequence of tool calls plus summary metrics.
func ParseTrace(path string) (*Trace, error) {
	f, err := os.Open(path)
	if err != nil {
		return nil, err
	}
	defer f.Close()

	trace := &Trace{}
	scanner := bufio.NewScanner(f)
	scanner.Buffer(make([]byte, 0, 1024*1024), 10*1024*1024) // 10MB max line

	for scanner.Scan() {
		line := scanner.Bytes()
		if len(line) == 0 {
			continue
		}

		var env struct {
			Type    string          `json:"type"`
			Message json.RawMessage `json:"message"`
			// result fields
			NumTurns     int     `json:"num_turns"`
			DurationMS   int64   `json:"duration_ms"`
			TotalCostUSD float64 `json:"total_cost_usd"`
		}
		if err := json.Unmarshal(line, &env); err != nil {
			continue // skip malformed lines
		}

		switch env.Type {
		case "assistant":
			calls := extractToolCalls(env.Message, len(trace.ToolCalls))
			trace.ToolCalls = append(trace.ToolCalls, calls...)
		case "result":
			trace.NumTurns = env.NumTurns
			trace.DurationMS = env.DurationMS
			trace.TotalCostUSD = env.TotalCostUSD
		}
	}

	return trace, scanner.Err()
}

func extractToolCalls(raw json.RawMessage, startIndex int) []ToolCall {
	if len(raw) == 0 {
		return nil
	}

	// Handle message as either object or JSON string
	var msgBytes []byte
	if raw[0] == '"' {
		var s string
		if err := json.Unmarshal(raw, &s); err != nil {
			return nil
		}
		msgBytes = []byte(s)
	} else {
		msgBytes = raw
	}

	var msg struct {
		Content []struct {
			Type  string          `json:"type"`
			Name  string          `json:"name"`
			Input json.RawMessage `json:"input"`
		} `json:"content"`
	}
	if err := json.Unmarshal(msgBytes, &msg); err != nil {
		return nil
	}

	var calls []ToolCall
	for _, block := range msg.Content {
		if block.Type != "tool_use" {
			continue
		}
		tc := ToolCall{
			Name:  block.Name,
			Index: startIndex + len(calls),
		}
		// Extract relevant input fields
		var inp struct {
			FilePath string `json:"file_path"`
			Command  string `json:"command"`
		}
		if err := json.Unmarshal(block.Input, &inp); err == nil {
			tc.FilePath = inp.FilePath
			tc.Command = inp.Command
		}
		calls = append(calls, tc)
	}
	return calls
}

// IsTestFile returns true if the file path looks like a test file.
func IsTestFile(path string) bool {
	lower := strings.ToLower(path)
	return strings.Contains(lower, "test") ||
		strings.Contains(lower, "spec") ||
		strings.Contains(lower, "__tests__")
}

// IsImplFile returns true if the file path looks like an implementation file
// (source code that is not a test, config, or type definition).
func IsImplFile(path string) bool {
	if path == "" {
		return false
	}
	lower := strings.ToLower(path)
	// Exclude test files
	if IsTestFile(path) {
		return false
	}
	// Exclude config/meta files
	for _, exc := range []string{"package.json", "tsconfig", "vitest.config", "jest.config", ".eslint", "index.ts", "index.js"} {
		if strings.Contains(lower, exc) {
			return false
		}
	}
	// Must be a source file
	for _, ext := range []string{".ts", ".js", ".py", ".go", ".rs", ".java"} {
		if strings.HasSuffix(lower, ext) {
			return true
		}
	}
	return false
}
```

**Step 4: Run test to verify it passes**

Run: `cd /home/gabe/agentic-thunderdome && go test ./internal/analyze/ -run TestParseTrace -v`
Expected: PASS (all 4 tests)

**Step 5: Commit**

```bash
cd /home/gabe/agentic-thunderdome
git add internal/analyze/ndjson.go internal/analyze/ndjson_test.go
git commit -m "feat(analyze): add NDJSON parser for extracting tool call traces"
```

---

### Task 2: Behavior Extractors

**Files:**
- Create: `internal/analyze/behaviors.go`
- Test: `internal/analyze/behaviors_test.go`

**Dependencies:** Task 1

**Context:** Each extractor takes a `*Trace` and computes one behavioral signal. The `BehaviorProfile` struct collects all signals for a trial. Extractors work purely on the tool call sequence — no file I/O.

**Behavior definitions:**

1. **TDD compliance** (`tdd_compliance: bool`): The first `Write` to a test file occurs before the first `Write` to an implementation file. This checks if the agent starts with tests.

2. **Test-first ratio** (`test_first_ratio: float64`): For each implementation file written, was a test file written before it? Ratio of impl files that had a preceding test write. Looks at `Write` and `Edit` to test files vs impl files by chronological ordering.

3. **Verification before commit** (`verification_before_commit: bool`): A Bash command matching test/build patterns (`npm test`, `vitest`, `jest`, `go test`, `pytest`) appears after the last `Write`/`Edit` and before the first `git commit`.

4. **Final verification** (`final_verification: bool`): A Bash command running tests appears after the last `git commit`. This is the completion gate — verifying after the final commit.

5. **Build check** (`build_check: bool`): A Bash command matching build patterns (`npm run build`, `tsc`, `go build`) appears at any point.

6. **Lint check** (`lint_check: bool`): A Bash command matching lint patterns (`npm run lint`, `eslint`, `golint`, `ruff`) appears at any point.

7. **Diff review** (`diff_review: bool`): A Bash command containing `git diff` appears after any `git commit`.

8. **Commit count** (`commit_count: int`): Number of Bash commands containing `git commit`.

9. **Test run count** (`test_run_count: int`): Number of Bash commands matching test patterns.

10. **Iterative fix cycles** (`fix_cycles: int`): Number of sequences where a test run is followed by `Edit`/`Write` which is followed by another test run (red-green cycles).

**Step 1: Write the failing test**

Create `internal/analyze/behaviors_test.go`:

```go
package analyze

import (
	"testing"
)

func mkTrace(calls ...ToolCall) *Trace {
	for i := range calls {
		calls[i].Index = i
	}
	return &Trace{ToolCalls: calls}
}

func w(path string) ToolCall  { return ToolCall{Name: "Write", FilePath: path} }
func e(path string) ToolCall  { return ToolCall{Name: "Edit", FilePath: path} }
func bash(cmd string) ToolCall { return ToolCall{Name: "Bash", Command: cmd} }
func read(path string) ToolCall { return ToolCall{Name: "Read", FilePath: path} }

func TestTDDCompliance(t *testing.T) {
	tests := []struct {
		name  string
		trace *Trace
		want  bool
	}{
		{
			name:  "test before impl",
			trace: mkTrace(w("/workspace/src/__tests__/foo.test.ts"), w("/workspace/src/foo.ts")),
			want:  true,
		},
		{
			name:  "impl before test",
			trace: mkTrace(w("/workspace/src/foo.ts"), w("/workspace/src/__tests__/foo.test.ts")),
			want:  false,
		},
		{
			name:  "no writes",
			trace: mkTrace(bash("ls"), read("/workspace/src/foo.ts")),
			want:  false,
		},
		{
			name:  "only test writes",
			trace: mkTrace(w("/workspace/src/__tests__/foo.test.ts")),
			want:  true,
		},
		{
			name:  "read before write is ok",
			trace: mkTrace(read("/workspace/src/foo.ts"), w("/workspace/test/foo.test.ts"), w("/workspace/src/foo.ts")),
			want:  true,
		},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			p := ExtractBehaviors(tt.trace)
			if p.TDDCompliance != tt.want {
				t.Errorf("TDDCompliance = %v, want %v", p.TDDCompliance, tt.want)
			}
		})
	}
}

func TestVerificationBeforeCommit(t *testing.T) {
	tests := []struct {
		name  string
		trace *Trace
		want  bool
	}{
		{
			name: "test then commit",
			trace: mkTrace(
				w("/workspace/src/foo.ts"),
				bash("npx vitest run"),
				bash("git add -A && git commit -m 'feat'"),
			),
			want: true,
		},
		{
			name: "commit without test",
			trace: mkTrace(
				w("/workspace/src/foo.ts"),
				bash("git add -A && git commit -m 'feat'"),
			),
			want: false,
		},
		{
			name: "test after last edit before commit",
			trace: mkTrace(
				w("/workspace/src/foo.ts"),
				bash("npm test"),
				e("/workspace/src/foo.ts"),
				bash("npx vitest run"),
				bash("git commit -m 'feat'"),
			),
			want: true,
		},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			p := ExtractBehaviors(tt.trace)
			if p.VerificationBeforeCommit != tt.want {
				t.Errorf("VerificationBeforeCommit = %v, want %v", p.VerificationBeforeCommit, tt.want)
			}
		})
	}
}

func TestFixCycles(t *testing.T) {
	// test -> edit -> test = 1 cycle
	trace := mkTrace(
		w("/workspace/src/__tests__/foo.test.ts"),
		bash("npm test"),
		e("/workspace/src/foo.ts"),
		bash("npm test"),
		e("/workspace/src/foo.ts"),
		bash("npm test"),
	)
	p := ExtractBehaviors(trace)
	if p.FixCycles != 2 {
		t.Errorf("FixCycles = %d, want 2", p.FixCycles)
	}
}

func TestCommitAndTestCounts(t *testing.T) {
	trace := mkTrace(
		bash("npm test"),
		bash("git commit -m 'a'"),
		bash("npx vitest run"),
		bash("git add -A && git commit -m 'b'"),
		bash("npm run build"),
		bash("npm run lint"),
	)
	p := ExtractBehaviors(trace)
	if p.CommitCount != 2 {
		t.Errorf("CommitCount = %d, want 2", p.CommitCount)
	}
	if p.TestRunCount != 2 {
		t.Errorf("TestRunCount = %d, want 2", p.TestRunCount)
	}
	if !p.BuildCheck {
		t.Error("BuildCheck = false, want true")
	}
	if !p.LintCheck {
		t.Error("LintCheck = false, want true")
	}
}

func TestDiffReview(t *testing.T) {
	tests := []struct {
		name  string
		trace *Trace
		want  bool
	}{
		{
			name: "diff after commit",
			trace: mkTrace(
				bash("git commit -m 'feat'"),
				bash("git diff HEAD~1"),
			),
			want: true,
		},
		{
			name: "diff before commit only",
			trace: mkTrace(
				bash("git diff"),
				bash("git commit -m 'feat'"),
			),
			want: false,
		},
		{
			name: "no diff",
			trace: mkTrace(
				bash("git commit -m 'feat'"),
			),
			want: false,
		},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			p := ExtractBehaviors(tt.trace)
			if p.DiffReview != tt.want {
				t.Errorf("DiffReview = %v, want %v", p.DiffReview, tt.want)
			}
		})
	}
}

func TestTestFirstRatio(t *testing.T) {
	// Write test for foo, then impl for foo, then impl for bar (no test)
	trace := mkTrace(
		w("/workspace/src/__tests__/foo.test.ts"),
		w("/workspace/src/foo.ts"),
		w("/workspace/src/bar.ts"),
	)
	p := ExtractBehaviors(trace)
	// foo had test before it (1/2 = 0.5), bar did not
	if p.TestFirstRatio < 0.49 || p.TestFirstRatio > 0.51 {
		t.Errorf("TestFirstRatio = %f, want ~0.5", p.TestFirstRatio)
	}
}
```

**Step 2: Run test to verify it fails**

Run: `cd /home/gabe/agentic-thunderdome && go test ./internal/analyze/ -run "TestTDD|TestVerification|TestFix|TestCommit|TestDiff|TestTestFirst" -v`
Expected: FAIL — ExtractBehaviors and BehaviorProfile don't exist

**Step 3: Write minimal implementation**

Create `internal/analyze/behaviors.go`:

```go
package analyze

import (
	"strings"
)

// BehaviorProfile captures all behavioral signals extracted from a trial trace.
type BehaviorProfile struct {
	// TDD signals
	TDDCompliance  bool    // First test write before first impl write
	TestFirstRatio float64 // Fraction of impl files with a preceding test

	// Verification signals
	VerificationBeforeCommit bool // Tests run between last edit and first commit
	FinalVerification        bool // Tests run after last commit
	BuildCheck               bool // Build command ran at any point
	LintCheck                bool // Lint command ran at any point
	DiffReview               bool // git diff after any commit

	// Iteration signals
	CommitCount  int // Number of git commits
	TestRunCount int // Number of test executions
	FixCycles    int // test → edit → test sequences

	// Source data
	HasTrace bool // Was NDJSON available (false = git-only analysis)
}

// ExtractBehaviors analyzes a parsed trace and returns a BehaviorProfile.
func ExtractBehaviors(trace *Trace) *BehaviorProfile {
	p := &BehaviorProfile{HasTrace: true}
	if len(trace.ToolCalls) == 0 {
		return p
	}

	p.TDDCompliance = checkTDDCompliance(trace)
	p.TestFirstRatio = checkTestFirstRatio(trace)
	p.VerificationBeforeCommit = checkVerificationBeforeCommit(trace)
	p.FinalVerification = checkFinalVerification(trace)
	p.BuildCheck = checkBuildCheck(trace)
	p.LintCheck = checkLintCheck(trace)
	p.DiffReview = checkDiffReview(trace)
	p.CommitCount = countCommits(trace)
	p.TestRunCount = countTestRuns(trace)
	p.FixCycles = countFixCycles(trace)

	return p
}

func checkTDDCompliance(trace *Trace) bool {
	firstTestWrite := -1
	firstImplWrite := -1
	for _, tc := range trace.ToolCalls {
		if tc.Name != "Write" {
			continue
		}
		if IsTestFile(tc.FilePath) && firstTestWrite == -1 {
			firstTestWrite = tc.Index
		}
		if IsImplFile(tc.FilePath) && firstImplWrite == -1 {
			firstImplWrite = tc.Index
		}
	}
	if firstTestWrite == -1 {
		return false
	}
	if firstImplWrite == -1 {
		return true // only test files written
	}
	return firstTestWrite < firstImplWrite
}

func checkTestFirstRatio(trace *Trace) float64 {
	// Track which test file base names have been written
	testFilesWritten := map[string]int{} // base name → index
	for _, tc := range trace.ToolCalls {
		if (tc.Name == "Write" || tc.Name == "Edit") && IsTestFile(tc.FilePath) {
			base := testBaseName(tc.FilePath)
			if _, exists := testFilesWritten[base]; !exists {
				testFilesWritten[base] = tc.Index
			}
		}
	}

	// Count impl files that had a test written before them
	implFiles := 0
	testFirst := 0
	implSeen := map[string]bool{}
	for _, tc := range trace.ToolCalls {
		if tc.Name != "Write" || !IsImplFile(tc.FilePath) {
			continue
		}
		if implSeen[tc.FilePath] {
			continue
		}
		implSeen[tc.FilePath] = true
		implFiles++

		// Check if any test file was written before this impl file
		for _, testIdx := range testFilesWritten {
			if testIdx < tc.Index {
				testFirst++
				break
			}
		}
	}

	if implFiles == 0 {
		return 0
	}
	return float64(testFirst) / float64(implFiles)
}

func checkVerificationBeforeCommit(trace *Trace) bool {
	// Find the first commit
	firstCommit := -1
	for _, tc := range trace.ToolCalls {
		if tc.Name == "Bash" && isCommitCmd(tc.Command) {
			firstCommit = tc.Index
			break
		}
	}
	if firstCommit == -1 {
		return false
	}

	// Find last edit before first commit
	lastEdit := -1
	for _, tc := range trace.ToolCalls {
		if tc.Index >= firstCommit {
			break
		}
		if tc.Name == "Write" || tc.Name == "Edit" {
			lastEdit = tc.Index
		}
	}

	// Check for test run between last edit and first commit
	for _, tc := range trace.ToolCalls {
		if tc.Index <= lastEdit {
			continue
		}
		if tc.Index >= firstCommit {
			break
		}
		if tc.Name == "Bash" && isTestCmd(tc.Command) {
			return true
		}
	}
	return false
}

func checkFinalVerification(trace *Trace) bool {
	lastCommit := -1
	for _, tc := range trace.ToolCalls {
		if tc.Name == "Bash" && isCommitCmd(tc.Command) {
			lastCommit = tc.Index
		}
	}
	if lastCommit == -1 {
		return false
	}
	for _, tc := range trace.ToolCalls {
		if tc.Index > lastCommit && tc.Name == "Bash" && isTestCmd(tc.Command) {
			return true
		}
	}
	return false
}

func checkBuildCheck(trace *Trace) bool {
	for _, tc := range trace.ToolCalls {
		if tc.Name == "Bash" && isBuildCmd(tc.Command) {
			return true
		}
	}
	return false
}

func checkLintCheck(trace *Trace) bool {
	for _, tc := range trace.ToolCalls {
		if tc.Name == "Bash" && isLintCmd(tc.Command) {
			return true
		}
	}
	return false
}

func checkDiffReview(trace *Trace) bool {
	hadCommit := false
	for _, tc := range trace.ToolCalls {
		if tc.Name == "Bash" && isCommitCmd(tc.Command) {
			hadCommit = true
		}
		if hadCommit && tc.Name == "Bash" && isDiffCmd(tc.Command) {
			return true
		}
	}
	return false
}

func countCommits(trace *Trace) int {
	n := 0
	for _, tc := range trace.ToolCalls {
		if tc.Name == "Bash" && isCommitCmd(tc.Command) {
			n++
		}
	}
	return n
}

func countTestRuns(trace *Trace) int {
	n := 0
	for _, tc := range trace.ToolCalls {
		if tc.Name == "Bash" && isTestCmd(tc.Command) {
			n++
		}
	}
	return n
}

func countFixCycles(trace *Trace) int {
	// State machine: looking for test → edit → test
	cycles := 0
	state := 0 // 0=waiting-for-test, 1=had-test-waiting-for-edit, 2=had-edit-waiting-for-test
	for _, tc := range trace.ToolCalls {
		switch state {
		case 0:
			if tc.Name == "Bash" && isTestCmd(tc.Command) {
				state = 1
			}
		case 1:
			if tc.Name == "Write" || tc.Name == "Edit" {
				state = 2
			}
		case 2:
			if tc.Name == "Bash" && isTestCmd(tc.Command) {
				cycles++
				state = 1 // This test run starts the next potential cycle
			}
		}
	}
	return cycles
}

// Command classification helpers

func isTestCmd(cmd string) bool {
	lower := strings.ToLower(cmd)
	patterns := []string{"npm test", "npx vitest", "npx jest", "go test", "pytest", "cargo test"}
	for _, p := range patterns {
		if strings.Contains(lower, p) {
			return true
		}
	}
	return false
}

func isCommitCmd(cmd string) bool {
	return strings.Contains(cmd, "git commit")
}

func isBuildCmd(cmd string) bool {
	lower := strings.ToLower(cmd)
	patterns := []string{"npm run build", "npx tsc", "tsc --", "go build", "cargo build"}
	for _, p := range patterns {
		if strings.Contains(lower, p) {
			return true
		}
	}
	return false
}

func isLintCmd(cmd string) bool {
	lower := strings.ToLower(cmd)
	patterns := []string{"npm run lint", "npx eslint", "eslint ", "golint", "ruff ", "cargo clippy"}
	for _, p := range patterns {
		if strings.Contains(lower, p) {
			return true
		}
	}
	return false
}

func isDiffCmd(cmd string) bool {
	return strings.Contains(cmd, "git diff")
}

// testBaseName extracts a simplified name from a test file path for matching.
func testBaseName(path string) string {
	lower := strings.ToLower(path)
	// Remove common test suffixes/directories
	lower = strings.ReplaceAll(lower, "__tests__/", "")
	lower = strings.ReplaceAll(lower, ".test.", ".")
	lower = strings.ReplaceAll(lower, ".spec.", ".")
	lower = strings.ReplaceAll(lower, "_test.", ".")
	return lower
}
```

**Step 4: Run test to verify it passes**

Run: `cd /home/gabe/agentic-thunderdome && go test ./internal/analyze/ -run "TestTDD|TestVerification|TestFix|TestCommit|TestDiff|TestTestFirst" -v`
Expected: PASS (all tests)

**Step 5: Commit**

```bash
cd /home/gabe/agentic-thunderdome
git add internal/analyze/behaviors.go internal/analyze/behaviors_test.go
git commit -m "feat(analyze): add behavior extractors for TDD, verification, iteration signals"
```

---

### Task 3: Trial Discovery and Profile Collection

**Files:**
- Create: `internal/analyze/discovery.go`
- Test: `internal/analyze/discovery_test.go`

**Dependencies:** Task 1, Task 2

**Context:** Walk the `results/runs/` directory tree, find all trials with meta.json, optionally parse their NDJSON traces, and return a slice of `TrialAnalysis` combining score data with behavioral profiles. Must handle the existing directory layout: `runs/<timestamp>/trials/<orchestrator>/<task>/trial-<N>/`.

**Step 1: Write the failing test**

Create `internal/analyze/discovery_test.go`:

```go
package analyze

import (
	"encoding/json"
	"os"
	"path/filepath"
	"testing"
)

func TestDiscoverTrials(t *testing.T) {
	// Build a minimal trial directory structure
	dir := t.TempDir()
	trialDir := filepath.Join(dir, "runs", "2026-01-01T00-00-00", "trials", "test-orch", "test-task", "trial-1")
	wsDir := filepath.Join(trialDir, "workspace")
	os.MkdirAll(wsDir, 0755)

	meta := map[string]interface{}{
		"orchestrator":   "test-orch",
		"task":           "test-task",
		"trial":          1,
		"composite_score": 0.85,
		"exit_reason":    "completed",
		"duration_s":     120,
		"total_cost_usd": 2.50,
	}
	metaBytes, _ := json.Marshal(meta)
	os.WriteFile(filepath.Join(trialDir, "meta.json"), metaBytes, 0644)

	// Write a minimal NDJSON trace
	ndjson := `{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Write","input":{"file_path":"/workspace/src/__tests__/foo.test.ts","content":"x"}}]}}
{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Write","input":{"file_path":"/workspace/src/foo.ts","content":"x"}}]}}
{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Bash","input":{"command":"npm test"}}]}}
{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Bash","input":{"command":"git commit -m 'feat'"}}]}}
{"type":"result","num_turns":4,"duration_ms":60000,"total_cost_usd":2.50}
`
	os.WriteFile(filepath.Join(wsDir, ".thunderdome-output.jsonl"), []byte(ndjson), 0644)

	results, err := DiscoverTrials(filepath.Join(dir, "runs"))
	if err != nil {
		t.Fatal(err)
	}
	if len(results) != 1 {
		t.Fatalf("expected 1 trial, got %d", len(results))
	}

	r := results[0]
	if r.Orchestrator != "test-orch" {
		t.Errorf("Orchestrator = %q", r.Orchestrator)
	}
	if r.Task != "test-task" {
		t.Errorf("Task = %q", r.Task)
	}
	if r.Score != 0.85 {
		t.Errorf("Score = %f", r.Score)
	}
	if !r.Behaviors.HasTrace {
		t.Error("expected HasTrace = true")
	}
	if !r.Behaviors.TDDCompliance {
		t.Error("expected TDDCompliance = true")
	}
	if !r.Behaviors.VerificationBeforeCommit {
		t.Error("expected VerificationBeforeCommit = true")
	}
}

func TestDiscoverTrials_NoNDJSON(t *testing.T) {
	dir := t.TempDir()
	trialDir := filepath.Join(dir, "runs", "2026-01-01T00-00-00", "trials", "test-orch", "test-task", "trial-1")
	os.MkdirAll(trialDir, 0755)

	meta := map[string]interface{}{
		"orchestrator":   "test-orch",
		"task":           "test-task",
		"trial":          1,
		"composite_score": 0.70,
		"exit_reason":    "completed",
	}
	metaBytes, _ := json.Marshal(meta)
	os.WriteFile(filepath.Join(trialDir, "meta.json"), metaBytes, 0644)

	results, err := DiscoverTrials(filepath.Join(dir, "runs"))
	if err != nil {
		t.Fatal(err)
	}
	if len(results) != 1 {
		t.Fatalf("expected 1 trial, got %d", len(results))
	}
	if results[0].Behaviors.HasTrace {
		t.Error("expected HasTrace = false")
	}
}
```

**Step 2: Run test to verify it fails**

Run: `cd /home/gabe/agentic-thunderdome && go test ./internal/analyze/ -run TestDiscoverTrials -v`
Expected: FAIL — DiscoverTrials and TrialAnalysis don't exist

**Step 3: Write minimal implementation**

Create `internal/analyze/discovery.go`:

```go
package analyze

import (
	"encoding/json"
	"os"
	"path/filepath"
	"strings"
)

// TrialAnalysis combines trial metadata with behavioral analysis.
type TrialAnalysis struct {
	Orchestrator string
	Task         string
	Trial        int
	Score        float64
	ExitReason   string
	DurationS    int
	CostUSD      float64
	Behaviors    *BehaviorProfile
	RunTimestamp string // from run directory name
}

// DiscoverTrials walks the results/runs/ directory tree and returns
// analyzed trials with behavioral profiles where NDJSON is available.
func DiscoverTrials(runsDir string) ([]TrialAnalysis, error) {
	var results []TrialAnalysis

	runDirs, err := os.ReadDir(runsDir)
	if err != nil {
		return nil, err
	}

	for _, runEntry := range runDirs {
		if !runEntry.IsDir() {
			continue
		}
		// Skip symlinks like "latest"
		if runEntry.Name() == "latest" {
			continue
		}
		runTimestamp := runEntry.Name()
		trialsBase := filepath.Join(runsDir, runTimestamp, "trials")

		orchDirs, err := os.ReadDir(trialsBase)
		if err != nil {
			continue
		}
		for _, orchEntry := range orchDirs {
			if !orchEntry.IsDir() {
				continue
			}
			taskDirs, err := os.ReadDir(filepath.Join(trialsBase, orchEntry.Name()))
			if err != nil {
				continue
			}
			for _, taskEntry := range taskDirs {
				if !taskEntry.IsDir() {
					continue
				}
				trialDirs, err := os.ReadDir(filepath.Join(trialsBase, orchEntry.Name(), taskEntry.Name()))
				if err != nil {
					continue
				}
				for _, trialEntry := range trialDirs {
					if !trialEntry.IsDir() || !strings.HasPrefix(trialEntry.Name(), "trial-") {
						continue
					}
					trialPath := filepath.Join(trialsBase, orchEntry.Name(), taskEntry.Name(), trialEntry.Name())
					ta, err := analyzeTrial(trialPath, runTimestamp)
					if err != nil {
						continue
					}
					results = append(results, *ta)
				}
			}
		}
	}

	return results, nil
}

func analyzeTrial(trialDir, runTimestamp string) (*TrialAnalysis, error) {
	// Read meta.json
	metaPath := filepath.Join(trialDir, "meta.json")
	metaBytes, err := os.ReadFile(metaPath)
	if err != nil {
		return nil, err
	}

	var meta struct {
		Orchestrator   string  `json:"orchestrator"`
		Task           string  `json:"task"`
		Trial          int     `json:"trial"`
		CompositeScore float64 `json:"composite_score"`
		ExitReason     string  `json:"exit_reason"`
		DurationS      int     `json:"duration_s"`
		TotalCostUSD   float64 `json:"total_cost_usd"`
	}
	if err := json.Unmarshal(metaBytes, &meta); err != nil {
		return nil, err
	}

	ta := &TrialAnalysis{
		Orchestrator: meta.Orchestrator,
		Task:         meta.Task,
		Trial:        meta.Trial,
		Score:        meta.CompositeScore,
		ExitReason:   meta.ExitReason,
		DurationS:    meta.DurationS,
		CostUSD:      meta.TotalCostUSD,
		RunTimestamp:  runTimestamp,
	}

	// Try to parse NDJSON trace
	ndjsonPath := filepath.Join(trialDir, "workspace", ".thunderdome-output.jsonl")
	if trace, err := ParseTrace(ndjsonPath); err == nil && len(trace.ToolCalls) > 0 {
		ta.Behaviors = ExtractBehaviors(trace)
	} else {
		ta.Behaviors = &BehaviorProfile{HasTrace: false}
	}

	return ta, nil
}
```

**Step 4: Run test to verify it passes**

Run: `cd /home/gabe/agentic-thunderdome && go test ./internal/analyze/ -run TestDiscoverTrials -v`
Expected: PASS

**Step 5: Commit**

```bash
cd /home/gabe/agentic-thunderdome
git add internal/analyze/discovery.go internal/analyze/discovery_test.go
git commit -m "feat(analyze): add trial discovery with behavioral profile collection"
```

---

### Task 4: Correlation Engine

**Files:**
- Create: `internal/analyze/correlate.go`
- Test: `internal/analyze/correlate_test.go`

**Dependencies:** Task 2, Task 3

**Context:** Compute Pearson correlation between each boolean/numeric behavioral signal and the composite score across all trials that have traces. Also compute per-task and per-orchestrator breakdowns.

**Step 1: Write the failing test**

Create `internal/analyze/correlate_test.go`:

```go
package analyze

import (
	"math"
	"testing"
)

func TestPearson(t *testing.T) {
	// Perfect positive correlation
	x := []float64{1, 2, 3, 4, 5}
	y := []float64{2, 4, 6, 8, 10}
	r := pearson(x, y)
	if math.Abs(r-1.0) > 0.001 {
		t.Errorf("perfect positive: r = %f, want 1.0", r)
	}

	// No correlation
	x = []float64{1, 2, 3, 4, 5}
	y = []float64{5, 3, 1, 4, 2}
	r = pearson(x, y)
	if math.Abs(r) > 0.5 {
		t.Errorf("weak/no correlation: r = %f, want near 0", r)
	}

	// Too few points
	r = pearson([]float64{1}, []float64{2})
	if r != 0 {
		t.Errorf("single point: r = %f, want 0", r)
	}
}

func TestCorrelate(t *testing.T) {
	trials := []TrialAnalysis{
		{Score: 0.90, Behaviors: &BehaviorProfile{HasTrace: true, TDDCompliance: true, TestRunCount: 5, FixCycles: 3}},
		{Score: 0.85, Behaviors: &BehaviorProfile{HasTrace: true, TDDCompliance: true, TestRunCount: 4, FixCycles: 2}},
		{Score: 0.50, Behaviors: &BehaviorProfile{HasTrace: true, TDDCompliance: false, TestRunCount: 1, FixCycles: 0}},
		{Score: 0.45, Behaviors: &BehaviorProfile{HasTrace: true, TDDCompliance: false, TestRunCount: 1, FixCycles: 0}},
		{Score: 0.70, Behaviors: &BehaviorProfile{HasTrace: false}}, // no trace, should be excluded
	}

	report := Correlate(trials)
	if len(report.Signals) == 0 {
		t.Fatal("expected signals in report")
	}

	// TDD should correlate positively with score in this dataset
	tdd := findSignal(report, "tdd_compliance")
	if tdd == nil {
		t.Fatal("tdd_compliance not in report")
	}
	if tdd.Correlation <= 0 {
		t.Errorf("tdd_compliance correlation = %f, want positive", tdd.Correlation)
	}
	if report.TracedTrials != 4 {
		t.Errorf("TracedTrials = %d, want 4", report.TracedTrials)
	}
}

func findSignal(r *CorrelationReport, name string) *SignalCorrelation {
	for i := range r.Signals {
		if r.Signals[i].Name == name {
			return &r.Signals[i]
		}
	}
	return nil
}
```

**Step 2: Run test to verify it fails**

Run: `cd /home/gabe/agentic-thunderdome && go test ./internal/analyze/ -run "TestPearson|TestCorrelate" -v`
Expected: FAIL

**Step 3: Write minimal implementation**

Create `internal/analyze/correlate.go`:

```go
package analyze

import (
	"math"
	"sort"
)

// SignalCorrelation holds the Pearson r for one behavioral signal vs score.
type SignalCorrelation struct {
	Name        string  // Signal name (e.g., "tdd_compliance")
	Correlation float64 // Pearson r (-1 to 1)
	MeanWhenOn  float64 // Mean score when signal is true/high (for booleans: true)
	MeanWhenOff float64 // Mean score when signal is false/low
	CountOn     int     // Number of trials where signal is true/high
	CountOff    int     // Number of trials where signal is false/low
}

// CorrelationReport holds correlation data for all signals.
type CorrelationReport struct {
	Signals      []SignalCorrelation
	TracedTrials int // Number of trials with behavioral traces
	TotalTrials  int // Total trials including those without traces
}

// Correlate computes correlations between behavioral signals and composite scores.
func Correlate(trials []TrialAnalysis) *CorrelationReport {
	// Filter to trials with traces
	var traced []TrialAnalysis
	for _, t := range trials {
		if t.Behaviors != nil && t.Behaviors.HasTrace {
			traced = append(traced, t)
		}
	}

	report := &CorrelationReport{
		TracedTrials: len(traced),
		TotalTrials:  len(trials),
	}

	if len(traced) < 3 {
		return report
	}

	scores := make([]float64, len(traced))
	for i, t := range traced {
		scores[i] = t.Score
	}

	// Boolean signals
	boolSignals := []struct {
		name string
		fn   func(*BehaviorProfile) bool
	}{
		{"tdd_compliance", func(p *BehaviorProfile) bool { return p.TDDCompliance }},
		{"verification_before_commit", func(p *BehaviorProfile) bool { return p.VerificationBeforeCommit }},
		{"final_verification", func(p *BehaviorProfile) bool { return p.FinalVerification }},
		{"build_check", func(p *BehaviorProfile) bool { return p.BuildCheck }},
		{"lint_check", func(p *BehaviorProfile) bool { return p.LintCheck }},
		{"diff_review", func(p *BehaviorProfile) bool { return p.DiffReview }},
	}

	for _, sig := range boolSignals {
		values := make([]float64, len(traced))
		var onScores, offScores []float64
		for i, t := range traced {
			if sig.fn(t.Behaviors) {
				values[i] = 1
				onScores = append(onScores, t.Score)
			} else {
				values[i] = 0
				offScores = append(offScores, t.Score)
			}
		}
		report.Signals = append(report.Signals, SignalCorrelation{
			Name:        sig.name,
			Correlation: pearson(values, scores),
			MeanWhenOn:  mean(onScores),
			MeanWhenOff: mean(offScores),
			CountOn:     len(onScores),
			CountOff:    len(offScores),
		})
	}

	// Numeric signals
	numSignals := []struct {
		name string
		fn   func(*BehaviorProfile) float64
	}{
		{"test_first_ratio", func(p *BehaviorProfile) float64 { return p.TestFirstRatio }},
		{"commit_count", func(p *BehaviorProfile) float64 { return float64(p.CommitCount) }},
		{"test_run_count", func(p *BehaviorProfile) float64 { return float64(p.TestRunCount) }},
		{"fix_cycles", func(p *BehaviorProfile) float64 { return float64(p.FixCycles) }},
	}

	for _, sig := range numSignals {
		values := make([]float64, len(traced))
		for i, t := range traced {
			values[i] = sig.fn(t.Behaviors)
		}
		// For mean-when-on/off, split at median
		median := medianVal(values)
		var highScores, lowScores []float64
		for i, v := range values {
			if v >= median {
				highScores = append(highScores, traced[i].Score)
			} else {
				lowScores = append(lowScores, traced[i].Score)
			}
		}
		report.Signals = append(report.Signals, SignalCorrelation{
			Name:        sig.name,
			Correlation: pearson(values, scores),
			MeanWhenOn:  mean(highScores),
			MeanWhenOff: mean(lowScores),
			CountOn:     len(highScores),
			CountOff:    len(lowScores),
		})
	}

	// Sort by absolute correlation descending
	sort.Slice(report.Signals, func(i, j int) bool {
		return math.Abs(report.Signals[i].Correlation) > math.Abs(report.Signals[j].Correlation)
	})

	return report
}

func pearson(x, y []float64) float64 {
	n := len(x)
	if n < 2 || n != len(y) {
		return 0
	}
	mx := mean(x)
	my := mean(y)

	var num, dx2, dy2 float64
	for i := 0; i < n; i++ {
		dx := x[i] - mx
		dy := y[i] - my
		num += dx * dy
		dx2 += dx * dx
		dy2 += dy * dy
	}
	denom := math.Sqrt(dx2 * dy2)
	if denom == 0 {
		return 0
	}
	return num / denom
}

func mean(vals []float64) float64 {
	if len(vals) == 0 {
		return 0
	}
	sum := 0.0
	for _, v := range vals {
		sum += v
	}
	return sum / float64(len(vals))
}

func medianVal(vals []float64) float64 {
	if len(vals) == 0 {
		return 0
	}
	sorted := make([]float64, len(vals))
	copy(sorted, vals)
	sort.Float64s(sorted)
	mid := len(sorted) / 2
	if len(sorted)%2 == 0 {
		return (sorted[mid-1] + sorted[mid]) / 2
	}
	return sorted[mid]
}
```

**Step 4: Run test to verify it passes**

Run: `cd /home/gabe/agentic-thunderdome && go test ./internal/analyze/ -run "TestPearson|TestCorrelate" -v`
Expected: PASS

**Step 5: Commit**

```bash
cd /home/gabe/agentic-thunderdome
git add internal/analyze/correlate.go internal/analyze/correlate_test.go
git commit -m "feat(analyze): add Pearson correlation engine for behavior-score analysis"
```

---

### Task 5: Report Formatters

**Files:**
- Create: `internal/analyze/report.go`
- Test: `internal/analyze/report_test.go`

**Dependencies:** Task 4

**Context:** Three output modes: (1) terminal table showing correlation report, (2) per-trial JSON with behavioral profiles, (3) aggregate CSV for external analysis. The terminal table is the primary output for `thunderdome analyze --correlate`.

**Step 1: Write the failing test**

Create `internal/analyze/report_test.go`:

```go
package analyze

import (
	"bytes"
	"encoding/csv"
	"encoding/json"
	"strings"
	"testing"
)

func TestFormatCorrelationTable(t *testing.T) {
	report := &CorrelationReport{
		TracedTrials: 100,
		TotalTrials:  200,
		Signals: []SignalCorrelation{
			{Name: "tdd_compliance", Correlation: 0.42, MeanWhenOn: 0.85, MeanWhenOff: 0.60, CountOn: 60, CountOff: 40},
			{Name: "fix_cycles", Correlation: 0.31, MeanWhenOn: 0.80, MeanWhenOff: 0.65, CountOn: 50, CountOff: 50},
		},
	}

	var buf bytes.Buffer
	FormatCorrelationTable(&buf, report)
	output := buf.String()

	if !strings.Contains(output, "tdd_compliance") {
		t.Error("missing tdd_compliance in output")
	}
	if !strings.Contains(output, "0.42") {
		t.Error("missing correlation value")
	}
	if !strings.Contains(output, "100") {
		t.Error("missing traced trial count")
	}
}

func TestFormatCSV(t *testing.T) {
	trials := []TrialAnalysis{
		{
			Orchestrator: "test-orch",
			Task:         "test-task",
			Trial:        1,
			Score:        0.85,
			Behaviors:    &BehaviorProfile{HasTrace: true, TDDCompliance: true, TestRunCount: 3},
		},
	}

	var buf bytes.Buffer
	FormatCSV(&buf, trials)

	r := csv.NewReader(&buf)
	records, err := r.ReadAll()
	if err != nil {
		t.Fatal(err)
	}
	if len(records) != 2 { // header + 1 row
		t.Fatalf("expected 2 rows, got %d", len(records))
	}
	if records[0][0] != "orchestrator" {
		t.Errorf("first header = %q, want orchestrator", records[0][0])
	}
}

func TestFormatTrialJSON(t *testing.T) {
	ta := &TrialAnalysis{
		Orchestrator: "test-orch",
		Task:         "test-task",
		Trial:        1,
		Score:        0.85,
		Behaviors:    &BehaviorProfile{HasTrace: true, TDDCompliance: true},
	}

	var buf bytes.Buffer
	FormatTrialJSON(&buf, ta)

	var result map[string]interface{}
	if err := json.Unmarshal(buf.Bytes(), &result); err != nil {
		t.Fatal(err)
	}
	if result["orchestrator"] != "test-orch" {
		t.Errorf("orchestrator = %v", result["orchestrator"])
	}
	behaviors := result["behaviors"].(map[string]interface{})
	if behaviors["tdd_compliance"] != true {
		t.Errorf("tdd_compliance = %v", behaviors["tdd_compliance"])
	}
}
```

**Step 2: Run test to verify it fails**

Run: `cd /home/gabe/agentic-thunderdome && go test ./internal/analyze/ -run "TestFormat" -v`
Expected: FAIL

**Step 3: Write minimal implementation**

Create `internal/analyze/report.go`:

```go
package analyze

import (
	"encoding/csv"
	"encoding/json"
	"fmt"
	"io"
	"strconv"
)

// FormatCorrelationTable writes a human-readable correlation report.
func FormatCorrelationTable(w io.Writer, report *CorrelationReport) {
	fmt.Fprintf(w, "Behavioral Correlation Analysis\n")
	fmt.Fprintf(w, "Traced trials: %d / %d total\n\n", report.TracedTrials, report.TotalTrials)

	fmt.Fprintf(w, "%-30s %8s %10s %10s %8s %8s\n",
		"SIGNAL", "r", "MEAN(ON)", "MEAN(OFF)", "DELTA", "N(ON)")
	fmt.Fprintf(w, "%s\n", repeatDash(86))

	for _, sig := range report.Signals {
		delta := sig.MeanWhenOn - sig.MeanWhenOff
		fmt.Fprintf(w, "%-30s %+8.3f %10.3f %10.3f %+8.3f %8d\n",
			sig.Name, sig.Correlation, sig.MeanWhenOn, sig.MeanWhenOff, delta, sig.CountOn)
	}
}

// FormatCSV writes all trial analyses as CSV for external analysis tools.
func FormatCSV(w io.Writer, trials []TrialAnalysis) {
	cw := csv.NewWriter(w)
	defer cw.Flush()

	header := []string{
		"orchestrator", "task", "trial", "score", "exit_reason",
		"duration_s", "cost_usd", "has_trace",
		"tdd_compliance", "test_first_ratio",
		"verification_before_commit", "final_verification",
		"build_check", "lint_check", "diff_review",
		"commit_count", "test_run_count", "fix_cycles",
		"run_timestamp",
	}
	cw.Write(header)

	for _, t := range trials {
		b := t.Behaviors
		row := []string{
			t.Orchestrator,
			t.Task,
			strconv.Itoa(t.Trial),
			fmt.Sprintf("%.4f", t.Score),
			t.ExitReason,
			strconv.Itoa(t.DurationS),
			fmt.Sprintf("%.4f", t.CostUSD),
			strconv.FormatBool(b.HasTrace),
			strconv.FormatBool(b.TDDCompliance),
			fmt.Sprintf("%.4f", b.TestFirstRatio),
			strconv.FormatBool(b.VerificationBeforeCommit),
			strconv.FormatBool(b.FinalVerification),
			strconv.FormatBool(b.BuildCheck),
			strconv.FormatBool(b.LintCheck),
			strconv.FormatBool(b.DiffReview),
			strconv.Itoa(b.CommitCount),
			strconv.Itoa(b.TestRunCount),
			strconv.Itoa(b.FixCycles),
			t.RunTimestamp,
		}
		cw.Write(row)
	}
}

// FormatTrialJSON writes a single trial analysis as pretty-printed JSON.
func FormatTrialJSON(w io.Writer, ta *TrialAnalysis) {
	out := map[string]interface{}{
		"orchestrator":  ta.Orchestrator,
		"task":          ta.Task,
		"trial":         ta.Trial,
		"score":         ta.Score,
		"exit_reason":   ta.ExitReason,
		"duration_s":    ta.DurationS,
		"cost_usd":      ta.CostUSD,
		"run_timestamp": ta.RunTimestamp,
		"behaviors": map[string]interface{}{
			"has_trace":                  ta.Behaviors.HasTrace,
			"tdd_compliance":             ta.Behaviors.TDDCompliance,
			"test_first_ratio":           ta.Behaviors.TestFirstRatio,
			"verification_before_commit": ta.Behaviors.VerificationBeforeCommit,
			"final_verification":         ta.Behaviors.FinalVerification,
			"build_check":               ta.Behaviors.BuildCheck,
			"lint_check":                ta.Behaviors.LintCheck,
			"diff_review":               ta.Behaviors.DiffReview,
			"commit_count":              ta.Behaviors.CommitCount,
			"test_run_count":            ta.Behaviors.TestRunCount,
			"fix_cycles":               ta.Behaviors.FixCycles,
		},
	}
	enc := json.NewEncoder(w)
	enc.SetIndent("", "  ")
	enc.Encode(out)
}

func repeatDash(n int) string {
	b := make([]byte, n)
	for i := range b {
		b[i] = '-'
	}
	return string(b)
}
```

**Step 4: Run test to verify it passes**

Run: `cd /home/gabe/agentic-thunderdome && go test ./internal/analyze/ -run "TestFormat" -v`
Expected: PASS

**Step 5: Commit**

```bash
cd /home/gabe/agentic-thunderdome
git add internal/analyze/report.go internal/analyze/report_test.go
git commit -m "feat(analyze): add report formatters (terminal table, CSV, per-trial JSON)"
```

---

### Task 6: CLI Subcommand — `thunderdome analyze`

**Files:**
- Create: `cmd/analyze.go`
- Modify: `cmd/root.go` (add one line to register the subcommand)

**Dependencies:** Task 3, Task 4, Task 5

**Context:** Wire the analyze package into the Cobra CLI. The subcommand should support these flags:
- `--run <timestamp>` — analyze a specific run
- `--orchestrator <name>` — filter to one orchestrator
- `--task <name>` — filter to one task
- `--correlate` — show correlation report (default mode)
- `--csv` — output CSV instead of table
- `--json` — output per-trial JSON (one per line)
- `--min-trials <N>` — minimum trials for correlation (default 10)

The root command file is at `/home/gabe/agentic-thunderdome/cmd/root.go`. Find the `AddCommand` calls and add one for analyze.

**Step 1: Read root.go to find AddCommand pattern**

Run: `cd /home/gabe/agentic-thunderdome && grep -n "AddCommand" cmd/root.go`
Note the exact pattern used.

**Step 2: Create `cmd/analyze.go`**

```go
package cmd

import (
	"fmt"
	"os"
	"path/filepath"
	"strings"

	"github.com/signalnine/thunderdome/internal/analyze"
	"github.com/spf13/cobra"
)

func newAnalyzeCmd() *cobra.Command {
	var (
		flagRun          string
		flagOrchestrator string
		flagTask         string
		flagCorrelate    bool
		flagCSV          bool
		flagJSON         bool
		flagMinTrials    int
	)

	cmd := &cobra.Command{
		Use:   "analyze",
		Short: "Analyze behavioral signals from trial traces and correlate with scores",
		RunE: func(cmd *cobra.Command, args []string) error {
			cfg, err := loadConfig(cmd)
			if err != nil {
				return err
			}

			runsDir := filepath.Join(cfg.Results.Dir, "runs")

			// If --run specified, scope to that run
			if flagRun != "" {
				runsDir = filepath.Join(cfg.Results.Dir, "runs")
				// Validate run exists
				runPath := filepath.Join(runsDir, flagRun)
				if _, err := os.Stat(runPath); err != nil {
					return fmt.Errorf("run directory not found: %s", flagRun)
				}
			}

			trials, err := analyze.DiscoverTrials(runsDir)
			if err != nil {
				return fmt.Errorf("discovering trials: %w", err)
			}

			// Apply filters
			if flagRun != "" {
				trials = filterByRun(trials, flagRun)
			}
			if flagOrchestrator != "" {
				trials = filterByOrchestrator(trials, flagOrchestrator)
			}
			if flagTask != "" {
				trials = filterByTask(trials, flagTask)
			}

			if len(trials) == 0 {
				return fmt.Errorf("no trials match the given filters")
			}

			// Output mode
			switch {
			case flagCSV:
				analyze.FormatCSV(os.Stdout, trials)
			case flagJSON:
				for i := range trials {
					analyze.FormatTrialJSON(os.Stdout, &trials[i])
				}
			default:
				// Correlation report (default)
				report := analyze.Correlate(trials)
				if report.TracedTrials < flagMinTrials {
					fmt.Fprintf(os.Stderr, "Warning: only %d traced trials (minimum %d recommended for reliable correlations)\n\n",
						report.TracedTrials, flagMinTrials)
				}
				analyze.FormatCorrelationTable(os.Stdout, report)
			}

			return nil
		},
	}

	cmd.Flags().StringVar(&flagRun, "run", "", "analyze a specific run (timestamp)")
	cmd.Flags().StringVar(&flagOrchestrator, "orchestrator", "", "filter to one orchestrator")
	cmd.Flags().StringVar(&flagTask, "task", "", "filter to one task")
	cmd.Flags().BoolVar(&flagCorrelate, "correlate", false, "show correlation report (default)")
	cmd.Flags().BoolVar(&flagCSV, "csv", false, "output CSV format")
	cmd.Flags().BoolVar(&flagJSON, "json", false, "output per-trial JSON")
	cmd.Flags().IntVar(&flagMinTrials, "min-trials", 10, "minimum traced trials for correlation")

	return cmd
}

func filterByRun(trials []analyze.TrialAnalysis, run string) []analyze.TrialAnalysis {
	var out []analyze.TrialAnalysis
	for _, t := range trials {
		if t.RunTimestamp == run {
			out = append(out, t)
		}
	}
	return out
}

func filterByOrchestrator(trials []analyze.TrialAnalysis, orch string) []analyze.TrialAnalysis {
	var out []analyze.TrialAnalysis
	for _, t := range trials {
		if strings.Contains(t.Orchestrator, orch) {
			out = append(out, t)
		}
	}
	return out
}

func filterByTask(trials []analyze.TrialAnalysis, task string) []analyze.TrialAnalysis {
	var out []analyze.TrialAnalysis
	for _, t := range trials {
		if strings.Contains(t.Task, task) {
			out = append(out, t)
		}
	}
	return out
}
```

**Step 3: Add subcommand to root.go**

Find the block with `AddCommand` calls and add:
```go
rootCmd.AddCommand(newAnalyzeCmd())
```

**Step 4: Build and verify**

Run: `cd /home/gabe/agentic-thunderdome && go build -o /tmp/thunderdome-test ./... && /tmp/thunderdome-test analyze --help`
Expected: Shows analyze command help with all flags

**Step 5: Commit**

```bash
cd /home/gabe/agentic-thunderdome
git add cmd/analyze.go cmd/root.go
git commit -m "feat: add 'thunderdome analyze' subcommand for behavioral analysis"
```

---

### Task 7: Integration Test — Run Against Real Data

**Files:**
- Create: `internal/analyze/integration_test.go`

**Dependencies:** Task 6

**Context:** This is a smoke test that runs the full analysis pipeline against the actual Thunderdome results directory. It verifies the tool works end-to-end on real data before we run the first correlation analysis.

**Step 1: Write integration test**

Create `internal/analyze/integration_test.go`:

```go
//go:build integration

package analyze

import (
	"os"
	"testing"
)

func TestIntegration_DiscoverRealTrials(t *testing.T) {
	runsDir := os.Getenv("THUNDERDOME_RUNS_DIR")
	if runsDir == "" {
		runsDir = "../../results/runs"
	}

	if _, err := os.Stat(runsDir); err != nil {
		t.Skipf("runs directory not found: %s", runsDir)
	}

	trials, err := DiscoverTrials(runsDir)
	if err != nil {
		t.Fatal(err)
	}

	t.Logf("Discovered %d trials", len(trials))

	traced := 0
	for _, trial := range trials {
		if trial.Behaviors.HasTrace {
			traced++
		}
	}
	t.Logf("Trials with traces: %d", traced)

	if len(trials) < 100 {
		t.Errorf("expected at least 100 trials, got %d", len(trials))
	}
	if traced < 50 {
		t.Errorf("expected at least 50 traced trials, got %d", traced)
	}

	// Run correlation
	report := Correlate(trials)
	t.Logf("Correlation report: %d signals, %d traced trials", len(report.Signals), report.TracedTrials)

	for _, sig := range report.Signals {
		t.Logf("  %-30s r=%+.3f  on=%.3f(%d)  off=%.3f(%d)",
			sig.Name, sig.Correlation, sig.MeanWhenOn, sig.CountOn, sig.MeanWhenOff, sig.CountOff)
	}
}
```

**Step 2: Run integration test**

Run: `cd /home/gabe/agentic-thunderdome && go test ./internal/analyze/ -tags=integration -run TestIntegration -v -timeout 120s`
Expected: PASS with correlation data printed

**Step 3: Build final binary and run first analysis**

```bash
cd /home/gabe/agentic-thunderdome && go build -o ./thunderdome . && ./thunderdome analyze
```

This should produce the first real correlation report showing which behaviors predict high scores.

**Step 4: Commit**

```bash
cd /home/gabe/agentic-thunderdome
git add internal/analyze/integration_test.go
git commit -m "test(analyze): add integration test for real Thunderdome data"
```

---

### Task 8: Per-Task and Per-Orchestrator Breakdown

**Files:**
- Modify: `internal/analyze/correlate.go`
- Modify: `internal/analyze/report.go`
- Test: update `internal/analyze/correlate_test.go`

**Dependencies:** Task 4, Task 5

**Context:** The initial correlation report is global (across all tasks). But behaviors may matter differently per task type (TDD may correlate strongly on greenfield tasks but not bugfix tasks). Add per-task breakdown to the correlation report and a `--by-task` flag.

**Step 1: Write the failing test**

Add to `internal/analyze/correlate_test.go`:

```go
func TestCorrelateByTask(t *testing.T) {
	trials := []TrialAnalysis{
		{Task: "bench-task-queue", Score: 0.90, Behaviors: &BehaviorProfile{HasTrace: true, TDDCompliance: true}},
		{Task: "bench-task-queue", Score: 0.50, Behaviors: &BehaviorProfile{HasTrace: true, TDDCompliance: false}},
		{Task: "bench-task-queue", Score: 0.85, Behaviors: &BehaviorProfile{HasTrace: true, TDDCompliance: true}},
		{Task: "bench-analytics", Score: 0.70, Behaviors: &BehaviorProfile{HasTrace: true, TDDCompliance: false}},
		{Task: "bench-analytics", Score: 0.75, Behaviors: &BehaviorProfile{HasTrace: true, TDDCompliance: true}},
		{Task: "bench-analytics", Score: 0.72, Behaviors: &BehaviorProfile{HasTrace: true, TDDCompliance: false}},
	}

	reports := CorrelateByTask(trials)
	if len(reports) != 2 {
		t.Fatalf("expected 2 task reports, got %d", len(reports))
	}
}
```

**Step 2: Run test to verify it fails**

Run: `cd /home/gabe/agentic-thunderdome && go test ./internal/analyze/ -run TestCorrelateByTask -v`
Expected: FAIL

**Step 3: Implement CorrelateByTask**

Add to `internal/analyze/correlate.go`:

```go
// TaskCorrelationReport is a correlation report scoped to a specific task.
type TaskCorrelationReport struct {
	Task string
	*CorrelationReport
}

// CorrelateByTask runs correlation analysis separately for each task.
func CorrelateByTask(trials []TrialAnalysis) []TaskCorrelationReport {
	byTask := map[string][]TrialAnalysis{}
	for _, t := range trials {
		byTask[t.Task] = append(byTask[t.Task], t)
	}

	var reports []TaskCorrelationReport
	for task, taskTrials := range byTask {
		report := Correlate(taskTrials)
		reports = append(reports, TaskCorrelationReport{
			Task:              task,
			CorrelationReport: report,
		})
	}

	sort.Slice(reports, func(i, j int) bool {
		return reports[i].Task < reports[j].Task
	})

	return reports
}
```

Add to `internal/analyze/report.go`:

```go
// FormatByTaskTable writes per-task correlation reports.
func FormatByTaskTable(w io.Writer, reports []analyze.TaskCorrelationReport) {
	for _, r := range reports {
		fmt.Fprintf(w, "\n=== %s (%d traced trials) ===\n", r.Task, r.TracedTrials)
		if r.TracedTrials < 3 {
			fmt.Fprintf(w, "  (too few trials for correlation)\n")
			continue
		}
		FormatCorrelationTable(w, r.CorrelationReport)
	}
}
```

Wire `--by-task` flag in `cmd/analyze.go` to call `CorrelateByTask` and `FormatByTaskTable`.

**Step 4: Run test to verify it passes**

Run: `cd /home/gabe/agentic-thunderdome && go test ./internal/analyze/ -run TestCorrelateByTask -v`
Expected: PASS

**Step 5: Commit**

```bash
cd /home/gabe/agentic-thunderdome
git add internal/analyze/correlate.go internal/analyze/correlate_test.go internal/analyze/report.go cmd/analyze.go
git commit -m "feat(analyze): add per-task correlation breakdown with --by-task flag"
```
