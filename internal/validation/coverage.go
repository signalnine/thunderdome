package validation

import (
	"context"
	"encoding/json"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
)

// CoverageResult holds the parsed coverage data.
type CoverageResult struct {
	Score      float64 // 0.0-1.0, average of line and branch coverage
	Lines      float64 // Line coverage percentage (0-100)
	Branches   float64 // Branch coverage percentage (0-100)
	Functions  float64 // Function coverage percentage (0-100)
	Statements float64 // Statement coverage percentage (0-100)
	Output     string
}

// RunCoverage runs the agent's own tests with vitest --coverage and parses
// the JSON coverage summary. Returns a score based on line + branch coverage.
func RunCoverage(ctx context.Context, workDir, validationImage, installCmd string) (*CoverageResult, error) {
	seccomp := "--security-opt=seccomp=unconfined"
	apparmor := "--security-opt=apparmor=unconfined"

	// Install dependencies first
	if installCmd != "" {
		cmd := exec.CommandContext(ctx, "docker", "run", "--rm", "--init", seccomp, apparmor,
			"-v", workDir+":/workspace", "-w", "/workspace",
			validationImage, "sh", "-c", installCmd)
		if out, err := cmd.CombinedOutput(); err != nil {
			return nil, fmt.Errorf("running install for coverage: %s: %w", string(out), err)
		}
	}

	// Install @vitest/coverage-v8 (required for v8 coverage provider).
	// Match the installed vitest version to avoid peer dependency conflicts.
	coverageInstall := exec.CommandContext(ctx, "docker", "run", "--rm", "--init", seccomp, apparmor,
		"-v", workDir+":/workspace", "-w", "/workspace",
		validationImage, "sh", "-c",
		`VITEST_VER=$(node -p "require('vitest/package.json').version" 2>/dev/null) && npm install --save-dev "@vitest/coverage-v8@^${VITEST_VER:-2.0.0}" 2>&1 || true`)
	coverageInstall.CombinedOutput() // best-effort

	// Run vitest with coverage enabled, outputting JSON summary.
	// Use --coverage.enabled explicitly (vitest 2.x requires it).
	// Exclude validation-tests/ in case they were already injected.
	coverageCmd := "npx vitest run --coverage.enabled --coverage.provider=v8 --coverage.reporter=json-summary --coverage.reportsDirectory=./coverage --exclude 'validation-tests/**' 2>&1 || true"
	cmd := exec.CommandContext(ctx, "docker", "run", "--rm", "--init", seccomp, apparmor,
		"-v", workDir+":/workspace", "-w", "/workspace",
		validationImage, "sh", "-c", coverageCmd)

	out, _ := cmd.CombinedOutput()

	// Parse the coverage-summary.json
	summaryPath := filepath.Join(workDir, "coverage", "coverage-summary.json")
	return parseCoverageSummary(summaryPath, string(out))
}

// coverageSummary mirrors the vitest/istanbul JSON summary format.
type coverageSummary struct {
	Total struct {
		Lines      coverageDetail `json:"lines"`
		Branches   coverageDetail `json:"branches"`
		Functions  coverageDetail `json:"functions"`
		Statements coverageDetail `json:"statements"`
	} `json:"total"`
}

type coverageDetail struct {
	Total   int     `json:"total"`
	Covered int     `json:"covered"`
	Skipped int     `json:"skipped"`
	Pct     float64 `json:"pct"`
}

func parseCoverageSummary(path, output string) (*CoverageResult, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		return &CoverageResult{Score: 0, Output: output}, fmt.Errorf("reading coverage summary: %w", err)
	}

	var summary coverageSummary
	if err := json.Unmarshal(data, &summary); err != nil {
		return &CoverageResult{Score: 0, Output: output}, fmt.Errorf("parsing coverage summary: %w", err)
	}

	lines := summary.Total.Lines.Pct
	branches := summary.Total.Branches.Pct
	functions := summary.Total.Functions.Pct
	statements := summary.Total.Statements.Pct

	// Score is average of line and branch coverage, normalized to 0-1
	score := (lines + branches) / 200.0
	if score > 1.0 {
		score = 1.0
	}

	return &CoverageResult{
		Score:      score,
		Lines:      lines,
		Branches:   branches,
		Functions:  functions,
		Statements: statements,
		Output:     output,
	}, nil
}
