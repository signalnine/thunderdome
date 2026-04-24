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

// JUnit XML output frequently contains one <testsuite> per test file,
// optionally wrapped in a <testsuites> root. The parser must aggregate
// counts across all individual suites, not return after the first match.
// Inputs: 5 tests (1 fail) + 10 tests (3 fail, 1 error) = 15 total, 10 passed.
// First-suite-only bug would yield 4/5=0.8, very different from 10/15.
func TestParseJUnitMultipleTestsuites(t *testing.T) {
	output := `<?xml version="1.0" encoding="UTF-8"?>
<testsuites>
<testsuite name="a" tests="5" failures="1" errors="0">
</testsuite>
<testsuite name="b" tests="10" failures="3" errors="1">
</testsuite>
</testsuites>`
	result := validation.ParseTestResults(output, 1)
	want := 10.0 / 15.0
	if absf(result.Score-want) > 0.001 {
		t.Errorf("score: got %f, want %f", result.Score, want)
	}
}

// Same multi-suite XML, but emitted on a single line (no whitespace
// between elements). Aggregation must still find every <testsuite>.
func TestParseJUnitMultipleTestsuitesSingleLine(t *testing.T) {
	output := `<testsuites><testsuite name="a" tests="5" failures="1"/><testsuite name="b" tests="10" failures="3" errors="1"/></testsuites>`
	result := validation.ParseTestResults(output, 1)
	want := 10.0 / 15.0
	if absf(result.Score-want) > 0.001 {
		t.Errorf("score: got %f, want %f", result.Score, want)
	}
}

// Tools that emit only an aggregate <testsuites tests="N"> root with no
// individual <testsuite> children must still produce a score (fall back
// to the aggregate). 7 of 10 passed.
func TestParseJUnitAggregateOnly(t *testing.T) {
	output := `<?xml version="1.0" encoding="UTF-8"?>
<testsuites name="all" tests="10" failures="2" errors="1">
</testsuites>`
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

// "0 passed" bare format (no total, no "failed" count) is an explicit
// zero-pass signal and should score 0.0, not fall through to the
// exitCode==0 "assume all passed" fallback.
func TestParseZeroPassedBareFormat(t *testing.T) {
	result := validation.ParseTestResults("0 passed", 0)
	if result.Score != 0.0 {
		t.Errorf("score: got %f, want 0.0", result.Score)
	}
}

// Mirrors the vitest-format behavior for "Tests 0 passed (0)" where
// the current code already returns 0.0. The plain-format strategy
// must agree.
func TestParseZeroPassedZeroFailed(t *testing.T) {
	result := validation.ParseTestResults("0 passed, 0 failed", 0)
	if result.Score != 0.0 {
		t.Errorf("score: got %f, want 0.0", result.Score)
	}
}

// Vitest summary line can include a "skipped" count, which the original
// regex didn't anticipate. Seen in real runs as:
//   "Tests  3 failed | 21 passed | 42 skipped (66)"
// Score must be passed/total, consistent with the other vitest variants.
func TestParseVitestWithSkipped(t *testing.T) {
	output := ` Test Files  1 failed (1)
      Tests  3 failed | 21 passed | 42 skipped (66)
   Duration  2.52s`
	result := validation.ParseTestResults(output, 1)
	want := 21.0 / 66.0
	if absf(result.Score-want) > 0.001 {
		t.Errorf("score: got %f, want %f", result.Score, want)
	}
}

// No failures, just passed + skipped.
func TestParseVitestPassedAndSkipped(t *testing.T) {
	output := `      Tests  21 passed | 42 skipped (63)`
	result := validation.ParseTestResults(output, 0)
	want := 21.0 / 63.0
	if absf(result.Score-want) > 0.001 {
		t.Errorf("score: got %f, want %f", result.Score, want)
	}
}

// All skipped — no passes — scores 0.0 under passed/total convention.
func TestParseVitestAllSkipped(t *testing.T) {
	output := `      Tests  42 skipped (42)`
	result := validation.ParseTestResults(output, 0)
	if result.Score != 0.0 {
		t.Errorf("score: got %f, want 0.0", result.Score)
	}
}

// Failed + skipped with no passes.
func TestParseVitestFailedAndSkipped(t *testing.T) {
	output := `      Tests  5 failed | 10 skipped (15)`
	result := validation.ParseTestResults(output, 1)
	if result.Score != 0.0 {
		t.Errorf("score: got %f, want 0.0", result.Score)
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
