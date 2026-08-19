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

// toolingChatterRe matches package-manager output that is not a lint
// diagnostic: npm's update notice, npm warnings, and the
// "> pkg@1.0.0 lint" / "> eslint src/" banner npm prints before running a
// script (plus the yarn/pnpm equivalents).
//
// This matters because npm 12.0.1's release made node:20's bundled npm
// 10.8.2 print "npm notice New major version of npm available!" on EVERY
// script run. A perfectly clean `npm run lint` therefore produced non-empty
// output with zero parseable diagnostics, which tripped the
// unrecognized-formatter fallback below and silently downgraded every clean
// lint from 1.0 to 0.5 -- capping standard-task composites at 0.85 from
// 2026-06 onward. Note `npm ERR!` is deliberately NOT stripped: that signals
// a genuine failure and should keep the linter honest.
var toolingChatterRe = regexp.MustCompile(`^\s*(npm (notice|warn|WARN)\b|>\s|\$\s|yarn run v|\$ eslint)`)

// stripToolingChatter drops package-manager noise so that "the linter printed
// something we don't recognize" reflects the LINTER's output, not its
// launcher's. Blank lines go too, so trailing newlines can't look like output.
func stripToolingChatter(output string) string {
	var kept []string
	for _, raw := range strings.Split(output, "\n") {
		line := strings.TrimRight(raw, "\r")
		if strings.TrimSpace(line) == "" {
			continue
		}
		if toolingChatterRe.MatchString(line) {
			continue
		}
		kept = append(kept, line)
	}
	return strings.Join(kept, "\n")
}

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

	cmd := dockerRunCmd(ctx, "--security-opt=seccomp=unconfined",
		"--security-opt=apparmor=unconfined",
		"-e", "npm_config_update_notifier=false",
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
	// Judge emptiness and count diagnostics against the linter's own output,
	// with package-manager chatter removed -- see toolingChatterRe.
	meaningful := stripToolingChatter(output)

	if exitCode == 0 && meaningful == "" {
		return &LintResult{Score: 1.0, Output: output, ExitCode: exitCode}
	}
	totalIssues := 0
	for _, raw := range strings.Split(meaningful, "\n") {
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
	// If the linter produced substantive output but our parsers recognized no
	// diagnostics, the formatter is likely one we don't support (JSON, unix,
	// custom). Avoid awarding a confident 1.0 — return a conservative 0.5.
	if exitCode == 0 && totalIssues == 0 && meaningful != "" {
		return &LintResult{Score: 0.5, Output: output, ExitCode: exitCode}
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
