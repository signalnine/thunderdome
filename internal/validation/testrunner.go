package validation

import (
	"context"
	"fmt"
	"os/exec"
	"regexp"
	"strings"
)

type TestResult struct {
	Score    float64
	Output   string
	ExitCode int
}

// RunTests executes the test command in a validation container and returns results.
func RunTests(ctx context.Context, workDir, validationImage, installCmd, testCmd string) (*TestResult, error) {
	seccomp := "--security-opt=seccomp=unconfined"
	apparmor := "--security-opt=apparmor=unconfined"
	if installCmd != "" {
		cmd := exec.CommandContext(ctx, "docker", "run", "--rm", "--init", seccomp, apparmor,
			"-v", workDir+":/workspace", "-w", "/workspace",
			validationImage, "sh", "-c", installCmd)
		if out, err := cmd.CombinedOutput(); err != nil {
			return nil, fmt.Errorf("running install command: %s: %w", string(out), err)
		}
	}

	cmd := exec.CommandContext(ctx, "docker", "run", "--rm", "--init", seccomp, apparmor,
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
	score := parsePassRate(output)
	if exitCode == 0 && score < 0 {
		// exitCode 0 but no parseable test output — assume all passed
		score = 1.0
	}
	if score < 0 {
		score = 0.0
	}
	return &TestResult{Score: score, Output: output, ExitCode: exitCode}
}

// vitestSummaryRe matches the summary wrapper, capturing the inner
// status components and the total. The components are pipe-separated
// in any order: "N failed", "N passed", "N skipped", "N todo". Examples:
//
//	"Tests  9 failed | 31 passed (40)"
//	"Tests  40 passed (40)"
//	"Tests  5 failed (5)"
//	"Tests  3 failed | 21 passed | 42 skipped (66)"
var vitestSummaryRe = regexp.MustCompile(`^\s*Tests\s+([^()]+?)\s*\((\d+)\)\s*$`)

// vitestCountRe pulls "N <status>" pairs out of a status summary line --
// either the inner text of a vitest summary or a bare line like
// "5 passed, 3 failed, 2 skipped".
var vitestCountRe = regexp.MustCompile(`(\d+)\s+(passed|failed|skipped|todo)`)

// parsePassRate extracts pass/fail counts from test output.
// Returns -1 if no test results could be parsed (distinguishes "no output" from "0 passed").
func parsePassRate(output string) float64 {
	if strings.Contains(output, "<testsuite") {
		return parseJUnitXML(output)
	}

	lines := strings.Split(output, "\n")

	// Strategy 1: Look for vitest summary format "Tests  ... (total)"
	for _, line := range lines {
		line = strings.TrimSpace(line)
		m := vitestSummaryRe.FindStringSubmatch(line)
		if m == nil {
			continue
		}
		var total, passed int
		fmt.Sscanf(m[2], "%d", &total)
		for _, cm := range vitestCountRe.FindAllStringSubmatch(m[1], -1) {
			if cm[2] == "passed" {
				fmt.Sscanf(cm[1], "%d", &passed)
			}
		}
		if total > 0 {
			return float64(passed) / float64(total)
		}
		return 0.0
	}

	// Strategy 2: Bare line format like "N passed", "N passed, M failed",
	// or "N passed, M failed, K skipped, J todo". Skipped and todo tests
	// count toward the denominator to match Strategies 1 (vitest summary)
	// and 3 (JUnit), both of which include todo in the total.
	for _, line := range lines {
		line = strings.TrimSpace(line)
		var lead int
		if n, _ := fmt.Sscanf(line, "%d passed", &lead); n != 1 {
			continue
		}
		var passed, failed, skipped, todo int
		for _, cm := range vitestCountRe.FindAllStringSubmatch(line, -1) {
			var v int
			fmt.Sscanf(cm[1], "%d", &v)
			switch cm[2] {
			case "passed":
				passed = v
			case "failed":
				failed = v
			case "skipped":
				skipped = v
			case "todo":
				todo = v
			}
		}
		total := passed + failed + skipped + todo
		if total > 0 {
			return float64(passed) / float64(total)
		}
		// Matched "N passed" with N=0 (and any other counts zero) -- explicit
		// zero-pass signal, not "no parseable output". Matches the vitest
		// summary branch which returns 0.0 when total is 0.
		return 0.0
	}
	return -1 // no test results found
}

// testsuiteOpenRe matches an individual <testsuite> opening tag (and
// self-closing <testsuite ... />). Anchored so it does not match the
// plural <testsuites> aggregate root.
var testsuiteOpenRe = regexp.MustCompile(`<testsuite(\s[^>]*)?/?>`)

// testsuitesRootRe matches the aggregate <testsuites> root tag, used as
// a fallback when no individual <testsuite> children carry counts.
var testsuitesRootRe = regexp.MustCompile(`<testsuites(\s[^>]*)?>`)

func parseJUnitXML(output string) float64 {
	var tests, failures, errors, skipped int
	for _, m := range testsuiteOpenRe.FindAllString(output, -1) {
		var t, f, e, s int
		fmt.Sscanf(extractAttr(m, "tests"), "%d", &t)
		fmt.Sscanf(extractAttr(m, "failures"), "%d", &f)
		fmt.Sscanf(extractAttr(m, "errors"), "%d", &e)
		fmt.Sscanf(extractAttr(m, "skipped"), "%d", &s)
		tests += t
		failures += f
		errors += e
		skipped += s
	}
	if tests == 0 {
		if agg := testsuitesRootRe.FindString(output); agg != "" {
			fmt.Sscanf(extractAttr(agg, "tests"), "%d", &tests)
			fmt.Sscanf(extractAttr(agg, "failures"), "%d", &failures)
			fmt.Sscanf(extractAttr(agg, "errors"), "%d", &errors)
			fmt.Sscanf(extractAttr(agg, "skipped"), "%d", &skipped)
		}
	}
	if tests <= 0 {
		return 0.0
	}
	// Skipped tests are not passes -- they count in the denominator (total)
	// but not the numerator. All three strategies agree on this convention.
	passed := tests - failures - errors - skipped
	if passed < 0 {
		passed = 0
	}
	return float64(passed) / float64(tests)
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
