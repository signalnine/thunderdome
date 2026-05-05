package validation

import (
	"context"
	"fmt"
	"os/exec"
	"regexp"
	"strings"
)

// eslintStylishRe matches a single diagnostic line in ESLint's default
// 'stylish' formatter, e.g. "  3:5  error  'x' is defined  no-unused-vars".
var eslintStylishRe = regexp.MustCompile(`^\s*\d+:\d+\s+(error|warning)\b`)

// eslintCompactRe matches the ESLint compact / clang-style formatter
// "<path>:<line>:<col>: error|warning ..." which most CI lint commands
// emit when run with --format=compact or via tsc/golangci-lint clones.
var eslintCompactRe = regexp.MustCompile(`^\S.*:\d+:\d+:\s+(error|warning)\b`)

// tscRe matches the TypeScript compiler's diagnostic shape
// "<path>(<line>,<col>): error TSxxxx: ..." (also "warning"). Used when
// 'tsc --noEmit' is bundled into the lint command.
var tscRe = regexp.MustCompile(`^\S.*\(\d+,\d+\):\s+(error|warning)\b`)

type LintResult struct {
	Score        float64
	Output       string
	NetNewIssues int
	ExitCode     int
}

// RunLint executes the lint command in a validation container.
func RunLint(ctx context.Context, workDir, validationImage, lintCmd string, baselineIssues int) (*LintResult, error) {
	if lintCmd == "" {
		return &LintResult{Score: 1.0}, nil
	}

	cmd := exec.CommandContext(ctx, "docker", "run", "--rm", "--init",
		"--security-opt=seccomp=unconfined",
		"--security-opt=apparmor=unconfined",
		"-v", workDir+":/workspace", "-w", "/workspace",
		validationImage, "sh", "-c", lintCmd)

	out, err := cmd.CombinedOutput()
	exitCode := 0
	if err != nil {
		if exitErr, ok := err.(*exec.ExitError); ok {
			exitCode = exitErr.ExitCode()
		} else {
			// docker daemon unreachable, image pull failure, context cancellation
			// before exec, etc. Don't silently fall through to a Score=1.0 perfect.
			return nil, fmt.Errorf("running lint: %s: %w", string(out), err)
		}
	}

	return ParseLintResults(string(out), exitCode, baselineIssues), nil
}

// ParseLintResults counts issues and computes a score.
func ParseLintResults(output string, exitCode int, baselineIssues int) *LintResult {
	if exitCode == 0 && output == "" {
		return &LintResult{Score: 1.0, Output: output, ExitCode: exitCode}
	}
	totalIssues := 0
	for _, raw := range strings.Split(output, "\n") {
		line := strings.TrimRight(raw, "\r")
		trimmed := strings.TrimSpace(line)
		if trimmed == "" {
			continue
		}
		if eslintCompactRe.MatchString(trimmed) || tscRe.MatchString(trimmed) {
			totalIssues++
			continue
		}
		if eslintStylishRe.MatchString(line) {
			totalIssues++
		}
	}
	// Nonzero exit with no parseable issues means the linter itself failed
	// (crashed, missing binary, misconfigured). Score 0 instead of rewarding
	// the failure with a perfect score.
	if exitCode != 0 && totalIssues == 0 {
		return &LintResult{Score: 0, Output: output, ExitCode: exitCode}
	}
	netNew := totalIssues - baselineIssues
	if netNew < 0 {
		netNew = 0
	}
	score := 1.0
	if netNew > 0 {
		score = 1.0 - (float64(netNew) * 0.1)
		if score < 0 {
			score = 0
		}
	}
	return &LintResult{Score: score, Output: output, NetNewIssues: netNew, ExitCode: exitCode}
}
