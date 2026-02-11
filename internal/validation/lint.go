package validation

import (
	"context"
	"os/exec"
	"strings"
)

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

	cmd := exec.CommandContext(ctx, "docker", "run", "--rm",
		"-v", workDir+":/workspace", "-w", "/workspace",
		validationImage, "sh", "-c", lintCmd)

	out, err := cmd.CombinedOutput()
	exitCode := 0
	if err != nil {
		if exitErr, ok := err.(*exec.ExitError); ok {
			exitCode = exitErr.ExitCode()
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
	for _, line := range strings.Split(output, "\n") {
		line = strings.TrimSpace(line)
		if line != "" && (strings.Contains(line, ": error") || strings.Contains(line, ": warning") || strings.Contains(line, "Error:") || strings.Contains(line, "Warning:")) {
			totalIssues++
		}
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
