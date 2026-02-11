package validation

import (
	"context"
	"fmt"
	"os/exec"
	"strings"
)

type TestResult struct {
	Score    float64
	Output   string
	ExitCode int
}

// RunTests executes the test command in a validation container and returns results.
func RunTests(ctx context.Context, workDir, validationImage, installCmd, testCmd string) (*TestResult, error) {
	if installCmd != "" {
		cmd := exec.CommandContext(ctx, "docker", "run", "--rm",
			"-v", workDir+":/workspace", "-w", "/workspace",
			validationImage, "sh", "-c", installCmd)
		cmd.CombinedOutput()
	}

	cmd := exec.CommandContext(ctx, "docker", "run", "--rm",
		"-v", workDir+":/workspace", "-w", "/workspace",
		validationImage, "sh", "-c", testCmd)

	out, err := cmd.CombinedOutput()
	exitCode := 0
	if err != nil {
		if exitErr, ok := err.(*exec.ExitError); ok {
			exitCode = exitErr.ExitCode()
		} else {
			return nil, fmt.Errorf("running tests: %w", err)
		}
	}

	return &TestResult{
		Score:    ParseTestResults(string(out), exitCode).Score,
		Output:   string(out),
		ExitCode: exitCode,
	}, nil
}

// ParseTestResults interprets test output and exit code into a score.
func ParseTestResults(output string, exitCode int) *TestResult {
	if exitCode == 0 {
		return &TestResult{Score: 1.0, Output: output, ExitCode: exitCode}
	}
	score := parsePassRate(output)
	return &TestResult{Score: score, Output: output, ExitCode: exitCode}
}

func parsePassRate(output string) float64 {
	if strings.Contains(output, "<testsuite") {
		return parseJUnitXML(output)
	}

	lines := strings.Split(output, "\n")
	for _, line := range lines {
		line = strings.TrimSpace(line)
		var passed, failed int
		if n, _ := fmt.Sscanf(line, "%d passed", &passed); n == 1 {
			fmt.Sscanf(line, "%d passed, %d failed", &passed, &failed)
			total := passed + failed
			if total > 0 {
				return float64(passed) / float64(total)
			}
		}
	}
	return 0.0
}

func parseJUnitXML(output string) float64 {
	var tests, failures, errors int
	for _, line := range strings.Split(output, "\n") {
		if !strings.Contains(line, "<testsuite") {
			continue
		}
		fmt.Sscanf(extractAttr(line, "tests"), "%d", &tests)
		fmt.Sscanf(extractAttr(line, "failures"), "%d", &failures)
		fmt.Sscanf(extractAttr(line, "errors"), "%d", &errors)
		if tests > 0 {
			passed := tests - failures - errors
			if passed < 0 {
				passed = 0
			}
			return float64(passed) / float64(tests)
		}
	}
	return 0.0
}

func extractAttr(line, attr string) string {
	key := attr + `="`
	idx := strings.Index(line, key)
	if idx < 0 {
		return ""
	}
	start := idx + len(key)
	end := strings.Index(line[start:], `"`)
	if end < 0 {
		return ""
	}
	return line[start : start+end]
}
