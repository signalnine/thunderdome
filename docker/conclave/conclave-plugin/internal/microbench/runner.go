// Package microbench provides a lightweight benchmark system for testing
// whether skill text changes affect agent behavioral compliance, without
// running full Thunderdome benchmark suites.
package microbench

import (
	"context"
	"encoding/json"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"sort"
	"strings"
	"time"

	"github.com/signalnine/conclave/internal/analyze"
)

// Benchmark represents a single micro-benchmark fixture.
type Benchmark struct {
	Name              string
	Dir               string
	TaskPrompt        string
	ExpectedBehaviors ExpectedBehaviors
}

// ExpectedBehaviors defines which behavioral signals we expect to see.
// Nil fields are not checked (don't care).
type ExpectedBehaviors struct {
	TDDCompliance            *bool `json:"tdd_compliance,omitempty"`
	VerificationBeforeCommit *bool `json:"verification_before_commit,omitempty"`
	FinalVerification        *bool `json:"final_verification,omitempty"`
	DiffReview               *bool `json:"diff_review,omitempty"`
	MinTestRuns              *int  `json:"min_test_runs,omitempty"`
	MaxTestRuns              *int  `json:"max_test_runs,omitempty"`
	MinFixCycles             *int  `json:"min_fix_cycles,omitempty"`
}

// Result captures the outcome of running a single benchmark.
type Result struct {
	Benchmark       string                  `json:"benchmark"`
	SkillText       string                  `json:"skill_text"`
	Behaviors       analyze.BehaviorProfile `json:"behaviors"`
	Expected        ExpectedBehaviors       `json:"expected"`
	Passed          bool                    `json:"passed"`
	Violations      []string                `json:"violations,omitempty"`
	TaskCompleted   bool                    `json:"task_completed"`
	DurationSeconds float64                 `json:"duration_seconds"`
	OutputPath      string                  `json:"output_path"`
}

// CmdBuilder creates the command arguments to run the agent.
// Parameters: workspace directory, NDJSON output file path, full prompt text.
// Returns the command as a slice of strings (program + args).
type CmdBuilder func(workDir, outputPath, prompt string) []string

// DiscoverBenchmarks finds all valid benchmark directories under baseDir.
// A valid benchmark has at least task.md and expected_behaviors.json.
func DiscoverBenchmarks(baseDir string) ([]Benchmark, error) {
	entries, err := os.ReadDir(baseDir)
	if err != nil {
		return nil, fmt.Errorf("reading benchmarks dir: %w", err)
	}

	var benchmarks []Benchmark
	for _, entry := range entries {
		if !entry.IsDir() {
			continue
		}

		dir := filepath.Join(baseDir, entry.Name())

		// Must have task.md
		taskPath := filepath.Join(dir, "task.md")
		taskBytes, err := os.ReadFile(taskPath)
		if err != nil {
			continue // skip dirs without task.md
		}

		// Must have expected_behaviors.json
		ebPath := filepath.Join(dir, "expected_behaviors.json")
		ebBytes, err := os.ReadFile(ebPath)
		if err != nil {
			continue
		}

		var eb ExpectedBehaviors
		if err := json.Unmarshal(ebBytes, &eb); err != nil {
			continue
		}

		benchmarks = append(benchmarks, Benchmark{
			Name:              entry.Name(),
			Dir:               dir,
			TaskPrompt:        strings.TrimSpace(string(taskBytes)),
			ExpectedBehaviors: eb,
		})
	}

	sort.Slice(benchmarks, func(i, j int) bool {
		return benchmarks[i].Name < benchmarks[j].Name
	})

	return benchmarks, nil
}

// RunBenchmark executes one benchmark with the given skill text.
// 1. Copy benchmark dir to a temp workspace
// 2. Run setup.sh (if present)
// 3. Run the agent command (via cmdBuilder) with skill text prepended to task prompt
// 4. Parse NDJSON output with analyze.ParseTrace
// 5. Extract behaviors with analyze.ExtractBehaviors
// 6. Run verify.sh (if present)
// 7. Compare behaviors against expected
func RunBenchmark(ctx context.Context, bench Benchmark, skillText string, timeout time.Duration, cmdBuilder CmdBuilder) (*Result, error) {
	start := time.Now()

	// Create temp workspace
	workDir, err := os.MkdirTemp("", "microbench-"+bench.Name+"-")
	if err != nil {
		return nil, fmt.Errorf("creating temp dir: %w", err)
	}

	// Copy benchmark files to workspace
	if err := copyDir(bench.Dir, workDir); err != nil {
		return nil, fmt.Errorf("copying benchmark dir: %w", err)
	}

	// Run setup.sh if present
	setupPath := filepath.Join(workDir, "setup.sh")
	if _, err := os.Stat(setupPath); err == nil {
		cmd := exec.CommandContext(ctx, "bash", setupPath)
		cmd.Dir = workDir
		cmd.Env = filterEnv()
		if out, err := cmd.CombinedOutput(); err != nil {
			return nil, fmt.Errorf("setup.sh failed: %w\n%s", err, out)
		}
	}

	// Build the prompt: skill text + task prompt
	prompt := bench.TaskPrompt
	if skillText != "" {
		prompt = skillText + "\n\n---\n\n" + bench.TaskPrompt
	}

	// Create output file for NDJSON
	outputPath := filepath.Join(workDir, "output.ndjson")

	// Build and run the agent command
	cmdArgs := cmdBuilder(workDir, outputPath, prompt)
	if len(cmdArgs) == 0 {
		return nil, fmt.Errorf("cmdBuilder returned empty command")
	}

	cmdCtx, cancel := context.WithTimeout(ctx, timeout)
	defer cancel()

	agentCmd := exec.CommandContext(cmdCtx, cmdArgs[0], cmdArgs[1:]...)
	agentCmd.Dir = workDir
	agentCmd.Env = filterEnv()
	// Capture stdout to NDJSON output file (stream-json goes to stdout)
	outFile, err := os.Create(outputPath)
	if err != nil {
		return nil, fmt.Errorf("creating output file: %w", err)
	}
	agentCmd.Stdout = outFile
	agentCmd.Stderr = os.Stderr
	// Errors from the agent are not fatal — we still analyze what happened
	_ = agentCmd.Run()
	outFile.Close()

	// Parse NDJSON output
	trace, err := analyze.ParseTrace(outputPath)
	if err != nil {
		// If no output, create empty trace
		trace = &analyze.Trace{}
	}

	// Extract behaviors
	behaviors := analyze.ExtractBehaviors(trace)

	// Run verify.sh if present
	taskCompleted := false
	verifyPath := filepath.Join(workDir, "verify.sh")
	if _, err := os.Stat(verifyPath); err == nil {
		cmd := exec.CommandContext(ctx, "bash", verifyPath)
		cmd.Dir = workDir
		cmd.Env = filterEnv()
		if err := cmd.Run(); err == nil {
			taskCompleted = true
		}
	} else {
		// No verify.sh = assume completed
		taskCompleted = true
	}

	// Check expectations
	passed, violations := CheckExpectations(*behaviors, bench.ExpectedBehaviors)

	return &Result{
		Benchmark:       bench.Name,
		SkillText:       skillText,
		Behaviors:       *behaviors,
		Expected:        bench.ExpectedBehaviors,
		Passed:          passed,
		Violations:      violations,
		TaskCompleted:   taskCompleted,
		DurationSeconds: time.Since(start).Seconds(),
		OutputPath:      outputPath,
	}, nil
}

// CheckExpectations compares actual behaviors against expected.
// Returns (allPassed, listOfViolations).
func CheckExpectations(actual analyze.BehaviorProfile, expected ExpectedBehaviors) (bool, []string) {
	var violations []string

	if expected.TDDCompliance != nil && actual.TDDCompliance != *expected.TDDCompliance {
		violations = append(violations, fmt.Sprintf(
			"tdd_compliance: expected %v, got %v", *expected.TDDCompliance, actual.TDDCompliance))
	}

	if expected.VerificationBeforeCommit != nil && actual.VerificationBeforeCommit != *expected.VerificationBeforeCommit {
		violations = append(violations, fmt.Sprintf(
			"verification_before_commit: expected %v, got %v", *expected.VerificationBeforeCommit, actual.VerificationBeforeCommit))
	}

	if expected.FinalVerification != nil && actual.FinalVerification != *expected.FinalVerification {
		violations = append(violations, fmt.Sprintf(
			"final_verification: expected %v, got %v", *expected.FinalVerification, actual.FinalVerification))
	}

	if expected.DiffReview != nil && actual.DiffReview != *expected.DiffReview {
		violations = append(violations, fmt.Sprintf(
			"diff_review: expected %v, got %v", *expected.DiffReview, actual.DiffReview))
	}

	if expected.MinTestRuns != nil && actual.TestRunCount < *expected.MinTestRuns {
		violations = append(violations, fmt.Sprintf(
			"min_test_runs: expected >= %d, got %d", *expected.MinTestRuns, actual.TestRunCount))
	}

	if expected.MaxTestRuns != nil && actual.TestRunCount > *expected.MaxTestRuns {
		violations = append(violations, fmt.Sprintf(
			"max_test_runs: expected <= %d, got %d", *expected.MaxTestRuns, actual.TestRunCount))
	}

	if expected.MinFixCycles != nil && actual.FixCycles < *expected.MinFixCycles {
		violations = append(violations, fmt.Sprintf(
			"min_fix_cycles: expected >= %d, got %d", *expected.MinFixCycles, actual.FixCycles))
	}

	return len(violations) == 0, violations
}

// DefaultCmdBuilder returns a CmdBuilder that invokes `claude -p` with
// --output-format stream-json. The prompt is written to a temp file and
// passed via stdin to avoid argument length limits.
func DefaultCmdBuilder() CmdBuilder {
	return func(workDir, outputPath, prompt string) []string {
		// Write prompt to a temp file so we can pipe it via stdin
		promptFile := filepath.Join(workDir, ".microbench-prompt.txt")
		os.WriteFile(promptFile, []byte(prompt), 0644)
		// Use bash -c to pipe the prompt file to claude
		return []string{
			"bash", "-c",
			fmt.Sprintf("cat %q | claude -p --output-format stream-json --verbose --permission-mode bypassPermissions", promptFile),
		}
	}
}

// copyDir recursively copies src to dst.
func copyDir(src, dst string) error {
	entries, err := os.ReadDir(src)
	if err != nil {
		return err
	}

	for _, entry := range entries {
		srcPath := filepath.Join(src, entry.Name())
		dstPath := filepath.Join(dst, entry.Name())

		if entry.IsDir() {
			if err := os.MkdirAll(dstPath, 0755); err != nil {
				return err
			}
			if err := copyDir(srcPath, dstPath); err != nil {
				return err
			}
		} else {
			data, err := os.ReadFile(srcPath)
			if err != nil {
				return err
			}
			info, err := entry.Info()
			if err != nil {
				return err
			}
			if err := os.WriteFile(dstPath, data, info.Mode()); err != nil {
				return err
			}
		}
	}
	return nil
}

// filterEnv returns os.Environ() with CLAUDECODE removed.
func filterEnv() []string {
	var env []string
	for _, e := range os.Environ() {
		if !strings.HasPrefix(e, "CLAUDECODE=") {
			env = append(env, e)
		}
	}
	return env
}
