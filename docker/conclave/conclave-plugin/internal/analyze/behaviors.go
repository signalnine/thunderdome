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
	FixCycles    int // test -> edit -> test sequences

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
	testFilesWritten := map[string]int{} // base name -> index
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

		// Check if a matching test file was written before this impl file
		implBase := testBaseName(tc.FilePath)
		if testIdx, exists := testFilesWritten[implBase]; exists && testIdx < tc.Index {
			testFirst++
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
	// State machine: looking for test -> edit -> test
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
