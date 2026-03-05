package validation_test

import (
	"testing"

	"github.com/signalnine/thunderdome/internal/validation"
)

func absf(x float64) float64 {
	if x < 0 {
		return -x
	}
	return x
}

func TestParseTestOutput(t *testing.T) {
	output := `8 passed, 2 failed`
	result := validation.ParseTestResults(output, 1)
	if absf(result.Score-0.8) > 0.001 {
		t.Errorf("score: got %f, want 0.8", result.Score)
	}
}

func TestParseTestOutputAllPass(t *testing.T) {
	result := validation.ParseTestResults("", 0)
	if result.Score != 1.0 {
		t.Errorf("score: got %f, want 1.0", result.Score)
	}
}

func TestParseTestOutputAllFail(t *testing.T) {
	result := validation.ParseTestResults("", 1)
	if result.Score != 0.0 {
		t.Errorf("score: got %f, want 0.0", result.Score)
	}
}

func TestParseTestOutputJUnit(t *testing.T) {
	output := `<?xml version="1.0" encoding="UTF-8"?>
<testsuite name="tests" tests="10" failures="2" errors="1" time="1.234">
</testsuite>`
	result := validation.ParseTestResults(output, 1)
	if absf(result.Score-0.7) > 0.001 {
		t.Errorf("score: got %f, want 0.7", result.Score)
	}
}

// Vitest format: "Tests  N failed | N passed (total)"
func TestParseVitestFormat(t *testing.T) {
	output := ` Test Files  1 failed (1)
      Tests  9 failed | 31 passed (40)
   Start at  18:12:42
   Duration  1.48s`
	result := validation.ParseTestResults(output, 1)
	want := 31.0 / 40.0
	if absf(result.Score-want) > 0.001 {
		t.Errorf("score: got %f, want %f", result.Score, want)
	}
}

func TestParseVitestAllPass(t *testing.T) {
	output := ` Test Files  1 passed (1)
      Tests  40 passed (40)
   Duration  1.00s`
	result := validation.ParseTestResults(output, 0)
	if result.Score != 1.0 {
		t.Errorf("score: got %f, want 1.0", result.Score)
	}
}

func TestParseVitestAllFail(t *testing.T) {
	output := ` Test Files  1 failed (1)
      Tests  77 failed (77)
   Duration  1.00s`
	result := validation.ParseTestResults(output, 1)
	if result.Score != 0.0 {
		t.Errorf("score: got %f, want 0.0", result.Score)
	}
}

// No test output at all — crashed before any tests ran
func TestParseNoTestOutput(t *testing.T) {
	result := validation.ParseTestResults("error: could not import module", 1)
	if result.Score != 0.0 {
		t.Errorf("score: got %f, want 0.0", result.Score)
	}
}

// exitCode 0 but with parseable output should use parsed score
func TestParseExitZeroWithOutput(t *testing.T) {
	output := `      Tests  40 passed (40)`
	result := validation.ParseTestResults(output, 0)
	if result.Score != 1.0 {
		t.Errorf("score: got %f, want 1.0", result.Score)
	}
}

func TestParseLintOutput(t *testing.T) {
	result := validation.ParseLintResults("5 warnings, 2 errors", 1, 3)
	if result.NetNewIssues < 0 {
		t.Errorf("expected non-negative net new issues, got %d", result.NetNewIssues)
	}
}

func TestParseLintOutputClean(t *testing.T) {
	result := validation.ParseLintResults("", 0, 0)
	if result.Score != 1.0 {
		t.Errorf("score: got %f, want 1.0", result.Score)
	}
}
