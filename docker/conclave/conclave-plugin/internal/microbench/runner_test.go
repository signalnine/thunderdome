package microbench

import (
	"context"
	"encoding/json"
	"os"
	"path/filepath"
	"testing"
	"time"

	"github.com/signalnine/conclave/internal/analyze"
)

func TestDiscoverBenchmarks(t *testing.T) {
	// Create a temp dir with benchmark fixtures
	base := t.TempDir()

	// Valid benchmark: has task.md and expected_behaviors.json
	b1 := filepath.Join(base, "bench-a")
	os.MkdirAll(b1, 0755)
	os.WriteFile(filepath.Join(b1, "task.md"), []byte("Do something"), 0644)
	os.WriteFile(filepath.Join(b1, "expected_behaviors.json"), []byte(`{"tdd_compliance": true}`), 0644)

	// Valid benchmark with setup.sh
	b2 := filepath.Join(base, "bench-b")
	os.MkdirAll(b2, 0755)
	os.WriteFile(filepath.Join(b2, "task.md"), []byte("Do another thing"), 0644)
	os.WriteFile(filepath.Join(b2, "expected_behaviors.json"), []byte(`{"min_test_runs": 2}`), 0644)
	os.WriteFile(filepath.Join(b2, "setup.sh"), []byte("#!/bin/bash\necho setup"), 0755)

	// Invalid: missing task.md
	b3 := filepath.Join(base, "not-a-bench")
	os.MkdirAll(b3, 0755)
	os.WriteFile(filepath.Join(b3, "README.md"), []byte("not a benchmark"), 0644)

	// Invalid: regular file, not a directory
	os.WriteFile(filepath.Join(base, "somefile.txt"), []byte("hi"), 0644)

	benchmarks, err := DiscoverBenchmarks(base)
	if err != nil {
		t.Fatalf("DiscoverBenchmarks: %v", err)
	}

	if len(benchmarks) != 2 {
		t.Fatalf("expected 2 benchmarks, got %d", len(benchmarks))
	}

	// Check names are sorted
	names := make(map[string]bool)
	for _, b := range benchmarks {
		names[b.Name] = true
	}
	if !names["bench-a"] || !names["bench-b"] {
		t.Errorf("expected bench-a and bench-b, got %v", names)
	}

	// Check task prompt loaded
	for _, b := range benchmarks {
		if b.TaskPrompt == "" {
			t.Errorf("benchmark %s has empty task prompt", b.Name)
		}
	}

	// Check expected behaviors parsed
	for _, b := range benchmarks {
		if b.Name == "bench-a" {
			if b.ExpectedBehaviors.TDDCompliance == nil || !*b.ExpectedBehaviors.TDDCompliance {
				t.Errorf("bench-a: expected TDDCompliance=true")
			}
		}
		if b.Name == "bench-b" {
			if b.ExpectedBehaviors.MinTestRuns == nil || *b.ExpectedBehaviors.MinTestRuns != 2 {
				t.Errorf("bench-b: expected MinTestRuns=2")
			}
		}
	}
}

func TestDiscoverBenchmarks_EmptyDir(t *testing.T) {
	base := t.TempDir()
	benchmarks, err := DiscoverBenchmarks(base)
	if err != nil {
		t.Fatalf("DiscoverBenchmarks: %v", err)
	}
	if len(benchmarks) != 0 {
		t.Errorf("expected 0 benchmarks, got %d", len(benchmarks))
	}
}

func TestDiscoverBenchmarks_NonexistentDir(t *testing.T) {
	_, err := DiscoverBenchmarks("/nonexistent/path/xyz")
	if err == nil {
		t.Fatal("expected error for nonexistent directory")
	}
}

func TestCheckExpectations(t *testing.T) {
	boolPtr := func(v bool) *bool { return &v }
	intPtr := func(v int) *int { return &v }

	tests := []struct {
		name       string
		actual     analyze.BehaviorProfile
		expected   ExpectedBehaviors
		wantPass   bool
		wantViols  int
	}{
		{
			name: "all pass - TDD compliance true",
			actual: analyze.BehaviorProfile{
				TDDCompliance:            true,
				VerificationBeforeCommit: true,
				TestRunCount:             3,
			},
			expected: ExpectedBehaviors{
				TDDCompliance:            boolPtr(true),
				VerificationBeforeCommit: boolPtr(true),
				MinTestRuns:              intPtr(2),
			},
			wantPass:  true,
			wantViols: 0,
		},
		{
			name: "TDD compliance mismatch",
			actual: analyze.BehaviorProfile{
				TDDCompliance: false,
			},
			expected: ExpectedBehaviors{
				TDDCompliance: boolPtr(true),
			},
			wantPass:  false,
			wantViols: 1,
		},
		{
			name: "verification mismatch",
			actual: analyze.BehaviorProfile{
				VerificationBeforeCommit: false,
			},
			expected: ExpectedBehaviors{
				VerificationBeforeCommit: boolPtr(true),
			},
			wantPass:  false,
			wantViols: 1,
		},
		{
			name: "min test runs not met",
			actual: analyze.BehaviorProfile{
				TestRunCount: 1,
			},
			expected: ExpectedBehaviors{
				MinTestRuns: intPtr(3),
			},
			wantPass:  false,
			wantViols: 1,
		},
		{
			name: "max test runs exceeded",
			actual: analyze.BehaviorProfile{
				TestRunCount: 10,
			},
			expected: ExpectedBehaviors{
				MaxTestRuns: intPtr(5),
			},
			wantPass:  false,
			wantViols: 1,
		},
		{
			name: "min fix cycles not met",
			actual: analyze.BehaviorProfile{
				FixCycles: 0,
			},
			expected: ExpectedBehaviors{
				MinFixCycles: intPtr(1),
			},
			wantPass:  false,
			wantViols: 1,
		},
		{
			name: "diff review mismatch",
			actual: analyze.BehaviorProfile{
				DiffReview: false,
			},
			expected: ExpectedBehaviors{
				DiffReview: boolPtr(true),
			},
			wantPass:  false,
			wantViols: 1,
		},
		{
			name: "final verification mismatch",
			actual: analyze.BehaviorProfile{
				FinalVerification: false,
			},
			expected: ExpectedBehaviors{
				FinalVerification: boolPtr(true),
			},
			wantPass:  false,
			wantViols: 1,
		},
		{
			name:   "no expectations = always pass",
			actual: analyze.BehaviorProfile{},
			expected: ExpectedBehaviors{},
			wantPass:  true,
			wantViols: 0,
		},
		{
			name: "nil fields are skipped",
			actual: analyze.BehaviorProfile{
				TDDCompliance: false,
				TestRunCount:  1,
			},
			expected: ExpectedBehaviors{
				// Only check test runs, not TDD
				MinTestRuns: intPtr(1),
			},
			wantPass:  true,
			wantViols: 0,
		},
		{
			name: "multiple violations",
			actual: analyze.BehaviorProfile{
				TDDCompliance:            false,
				VerificationBeforeCommit: false,
				TestRunCount:             0,
			},
			expected: ExpectedBehaviors{
				TDDCompliance:            boolPtr(true),
				VerificationBeforeCommit: boolPtr(true),
				MinTestRuns:              intPtr(2),
			},
			wantPass:  false,
			wantViols: 3,
		},
		{
			name: "expected false matches actual false",
			actual: analyze.BehaviorProfile{
				TDDCompliance: false,
			},
			expected: ExpectedBehaviors{
				TDDCompliance: boolPtr(false),
			},
			wantPass:  true,
			wantViols: 0,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			pass, viols := CheckExpectations(tt.actual, tt.expected)
			if pass != tt.wantPass {
				t.Errorf("pass = %v, want %v", pass, tt.wantPass)
			}
			if len(viols) != tt.wantViols {
				t.Errorf("violations = %d (%v), want %d", len(viols), viols, tt.wantViols)
			}
		})
	}
}

// TestRunBenchmark uses a mock command builder to test the full pipeline
// without actually calling claude -p.
func TestRunBenchmark(t *testing.T) {
	// Create a benchmark fixture in temp dir
	base := t.TempDir()
	benchDir := filepath.Join(base, "test-bench")
	os.MkdirAll(benchDir, 0755)

	os.WriteFile(filepath.Join(benchDir, "task.md"), []byte("Add a reverse function"), 0644)
	os.WriteFile(filepath.Join(benchDir, "expected_behaviors.json"),
		[]byte(`{"tdd_compliance": true, "verification_before_commit": true, "min_test_runs": 2}`), 0644)

	// setup.sh just initializes a git repo
	os.WriteFile(filepath.Join(benchDir, "setup.sh"), []byte(`#!/bin/bash
set -euo pipefail
git init
git config user.email "test@test"
git config user.name "Test"
echo "hello" > file.txt
git add -A
git commit -m "init"
`), 0755)

	// verify.sh always passes
	os.WriteFile(filepath.Join(benchDir, "verify.sh"), []byte(`#!/bin/bash
exit 0
`), 0755)

	bench := Benchmark{
		Name:       "test-bench",
		Dir:        benchDir,
		TaskPrompt: "Add a reverse function",
		ExpectedBehaviors: ExpectedBehaviors{
			TDDCompliance:            boolPtr(true),
			VerificationBeforeCommit: boolPtr(true),
			MinTestRuns:              intPtr(2),
		},
	}

	// Create fake NDJSON output that represents: write test -> run test -> write impl -> run test -> commit -> run test
	fakeNDJSON := buildFakeNDJSON(t)

	// Use a mock command builder that writes fake NDJSON to the output file
	mockBuilder := func(workDir, outputPath, prompt string) []string {
		// Return a shell command that writes the fake NDJSON to the output path
		return []string{"bash", "-c", "cat > " + outputPath + " <<'NDJSONEOF'\n" + fakeNDJSON + "\nNDJSONEOF"}
	}

	result, err := RunBenchmark(context.Background(), bench, "skill text here", 60*time.Second, mockBuilder)
	if err != nil {
		t.Fatalf("RunBenchmark: %v", err)
	}

	if result.Benchmark != "test-bench" {
		t.Errorf("Benchmark = %q, want %q", result.Benchmark, "test-bench")
	}
	if result.SkillText != "skill text here" {
		t.Errorf("SkillText = %q, want %q", result.SkillText, "skill text here")
	}
	if !result.TaskCompleted {
		t.Error("TaskCompleted = false, want true")
	}
	if !result.Passed {
		t.Errorf("Passed = false, want true; violations: %v", result.Violations)
	}
	if !result.Behaviors.TDDCompliance {
		t.Error("TDDCompliance = false, want true")
	}
	if !result.Behaviors.VerificationBeforeCommit {
		t.Error("VerificationBeforeCommit = false, want true")
	}
	if result.Behaviors.TestRunCount < 2 {
		t.Errorf("TestRunCount = %d, want >= 2", result.Behaviors.TestRunCount)
	}
	if result.OutputPath == "" {
		t.Error("OutputPath is empty")
	}
	if result.DurationSeconds <= 0 {
		t.Error("DurationSeconds should be > 0")
	}
}

func TestRunBenchmark_VerifyFails(t *testing.T) {
	base := t.TempDir()
	benchDir := filepath.Join(base, "fail-bench")
	os.MkdirAll(benchDir, 0755)

	os.WriteFile(filepath.Join(benchDir, "task.md"), []byte("Do something"), 0644)
	os.WriteFile(filepath.Join(benchDir, "expected_behaviors.json"), []byte(`{}`), 0644)
	os.WriteFile(filepath.Join(benchDir, "setup.sh"), []byte("#!/bin/bash\ngit init\ngit config user.email t@t\ngit config user.name T\necho x > f\ngit add -A\ngit commit -m i"), 0755)
	os.WriteFile(filepath.Join(benchDir, "verify.sh"), []byte("#!/bin/bash\nexit 1"), 0755)

	bench := Benchmark{
		Name:              "fail-bench",
		Dir:               benchDir,
		TaskPrompt:        "Do something",
		ExpectedBehaviors: ExpectedBehaviors{},
	}

	fakeNDJSON := buildMinimalNDJSON()

	mockBuilder := func(workDir, outputPath, prompt string) []string {
		return []string{"bash", "-c", "cat > " + outputPath + " <<'NDJSONEOF'\n" + fakeNDJSON + "\nNDJSONEOF"}
	}

	result, err := RunBenchmark(context.Background(), bench, "", 60*time.Second, mockBuilder)
	if err != nil {
		t.Fatalf("RunBenchmark: %v", err)
	}
	if result.TaskCompleted {
		t.Error("TaskCompleted = true, want false (verify.sh exits 1)")
	}
}

func TestRunBenchmark_NoSetupSh(t *testing.T) {
	base := t.TempDir()
	benchDir := filepath.Join(base, "no-setup")
	os.MkdirAll(benchDir, 0755)

	os.WriteFile(filepath.Join(benchDir, "task.md"), []byte("Do something"), 0644)
	os.WriteFile(filepath.Join(benchDir, "expected_behaviors.json"), []byte(`{}`), 0644)
	// No setup.sh
	os.WriteFile(filepath.Join(benchDir, "verify.sh"), []byte("#!/bin/bash\nexit 0"), 0755)

	bench := Benchmark{
		Name:              "no-setup",
		Dir:               benchDir,
		TaskPrompt:        "Do something",
		ExpectedBehaviors: ExpectedBehaviors{},
	}

	fakeNDJSON := buildMinimalNDJSON()
	mockBuilder := func(workDir, outputPath, prompt string) []string {
		return []string{"bash", "-c", "cat > " + outputPath + " <<'NDJSONEOF'\n" + fakeNDJSON + "\nNDJSONEOF"}
	}

	// Should succeed even without setup.sh
	result, err := RunBenchmark(context.Background(), bench, "", 60*time.Second, mockBuilder)
	if err != nil {
		t.Fatalf("RunBenchmark: %v", err)
	}
	if !result.TaskCompleted {
		t.Error("TaskCompleted = false, want true")
	}
}

// helpers

func boolPtr(v bool) *bool { return &v }
func intPtr(v int) *int    { return &v }

// buildFakeNDJSON creates NDJSON that simulates: write test -> run test -> write impl -> run test -> commit -> run test
func buildFakeNDJSON(t *testing.T) string {
	t.Helper()

	lines := []map[string]interface{}{
		// Write test file
		{
			"type": "assistant",
			"message": map[string]interface{}{
				"content": []map[string]interface{}{
					{
						"type":  "tool_use",
						"name":  "Write",
						"input": map[string]string{"file_path": "/workspace/src/__tests__/utils.test.ts"},
					},
				},
			},
		},
		// Run tests (first run)
		{
			"type": "assistant",
			"message": map[string]interface{}{
				"content": []map[string]interface{}{
					{
						"type":  "tool_use",
						"name":  "Bash",
						"input": map[string]string{"command": "npx vitest run"},
					},
				},
			},
		},
		// Write impl file
		{
			"type": "assistant",
			"message": map[string]interface{}{
				"content": []map[string]interface{}{
					{
						"type":  "tool_use",
						"name":  "Write",
						"input": map[string]string{"file_path": "/workspace/src/utils.ts"},
					},
				},
			},
		},
		// Run tests (second run)
		{
			"type": "assistant",
			"message": map[string]interface{}{
				"content": []map[string]interface{}{
					{
						"type":  "tool_use",
						"name":  "Bash",
						"input": map[string]string{"command": "npx vitest run"},
					},
				},
			},
		},
		// Commit
		{
			"type": "assistant",
			"message": map[string]interface{}{
				"content": []map[string]interface{}{
					{
						"type":  "tool_use",
						"name":  "Bash",
						"input": map[string]string{"command": "git add -A && git commit -m 'feat: add reverse'"},
					},
				},
			},
		},
		// Final test run
		{
			"type": "assistant",
			"message": map[string]interface{}{
				"content": []map[string]interface{}{
					{
						"type":  "tool_use",
						"name":  "Bash",
						"input": map[string]string{"command": "npm test"},
					},
				},
			},
		},
		// Result
		{
			"type":           "result",
			"num_turns":      6,
			"duration_ms":    15000,
			"total_cost_usd": 0.05,
		},
	}

	var result string
	for _, line := range lines {
		b, err := json.Marshal(line)
		if err != nil {
			t.Fatalf("json.Marshal: %v", err)
		}
		result += string(b) + "\n"
	}
	return result
}

func buildMinimalNDJSON() string {
	lines := []map[string]interface{}{
		{
			"type": "assistant",
			"message": map[string]interface{}{
				"content": []map[string]interface{}{
					{
						"type":  "tool_use",
						"name":  "Bash",
						"input": map[string]string{"command": "echo hello"},
					},
				},
			},
		},
		{
			"type":           "result",
			"num_turns":      1,
			"duration_ms":    1000,
			"total_cost_usd": 0.01,
		},
	}
	var result string
	for _, line := range lines {
		b, _ := json.Marshal(line)
		result += string(b) + "\n"
	}
	return result
}
