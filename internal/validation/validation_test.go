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

// Skipped tests must not count as passed -- this matches the vitest line
// format which scores "3 failed | 21 passed | 42 skipped (66)" as 21/66.
// JUnit emits the same data as tests=66, failures=3, skipped=42, and the
// score must be the same regardless of which output format the same run
// produces.
func TestParseJUnitWithSkipped(t *testing.T) {
	output := `<?xml version="1.0" encoding="UTF-8"?>
<testsuite name="tests" tests="66" failures="3" errors="0" skipped="42" time="2.52">
</testsuite>`
	result := validation.ParseTestResults(output, 1)
	want := 21.0 / 66.0
	if absf(result.Score-want) > 0.001 {
		t.Errorf("score: got %f, want %f", result.Score, want)
	}
}

// Skipped aggregates across multiple <testsuite> elements, just like
// failures and errors do.
func TestParseJUnitMultipleTestsuitesWithSkipped(t *testing.T) {
	// 5 tests (1 fail, 1 skipped) + 10 tests (2 fail, 1 error, 3 skipped)
	// = 15 total, 7 passed.
	output := `<?xml version="1.0" encoding="UTF-8"?>
<testsuites>
<testsuite name="a" tests="5" failures="1" errors="0" skipped="1">
</testsuite>
<testsuite name="b" tests="10" failures="2" errors="1" skipped="3">
</testsuite>
</testsuites>`
	result := validation.ParseTestResults(output, 1)
	want := 7.0 / 15.0
	if absf(result.Score-want) > 0.001 {
		t.Errorf("score: got %f, want %f", result.Score, want)
	}
}

// When only the aggregate <testsuites tests="N"> root carries counts,
// the skipped attribute on the root must be honored too.
func TestParseJUnitAggregateOnlyWithSkipped(t *testing.T) {
	output := `<?xml version="1.0" encoding="UTF-8"?>
<testsuites name="all" tests="10" failures="2" errors="0" skipped="3">
</testsuites>`
	result := validation.ParseTestResults(output, 1)
	want := 5.0 / 10.0
	if absf(result.Score-want) > 0.001 {
		t.Errorf("score: got %f, want %f", result.Score, want)
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

// Bare line format "N passed, M failed, K skipped" must score the same as
// the equivalent JUnit XML. Previously Strategy 2 dropped skipped from the
// denominator, inflating scores relative to Strategies 1 and 3.
func TestParseBareLineWithSkippedMatchesJUnit(t *testing.T) {
	bare := validation.ParseTestResults("5 passed, 3 failed, 2 skipped", 1)
	junit := validation.ParseTestResults(
		`<testsuite name="t" tests="10" failures="3" errors="0" skipped="2"></testsuite>`, 1)
	want := 5.0 / 10.0
	if absf(bare.Score-want) > 0.001 {
		t.Errorf("bare score: got %f, want %f", bare.Score, want)
	}
	if absf(bare.Score-junit.Score) > 0.001 {
		t.Errorf("bare and junit disagree: bare=%f junit=%f", bare.Score, junit.Score)
	}
}

// Bare line with skipped but no failures.
func TestParseBareLinePassedAndSkipped(t *testing.T) {
	result := validation.ParseTestResults("21 passed, 42 skipped", 0)
	want := 21.0 / 63.0
	if absf(result.Score-want) > 0.001 {
		t.Errorf("score: got %f, want %f", result.Score, want)
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

// A lint command that exited non-zero with no parseable output (crashed
// linter, OOM, missing binary, misconfigured eslint) must NOT score 1.0.
// Previously the loop counted 0 issues and netNew clamped to 0, silently
// rewarding the failure with a perfect score.
func TestParseLintCrashedEmptyOutput(t *testing.T) {
	result := validation.ParseLintResults("", 1, 0)
	if result.Score >= 1.0 {
		t.Errorf("crashed lint with empty output should not score 1.0, got %f", result.Score)
	}
	if result.ExitCode != 1 {
		t.Errorf("expected ExitCode=1, got %d", result.ExitCode)
	}
}

// Same crash signal but with output that has no parseable issues.
// A nonzero exit with output that the parser can't decode should also
// not be rewarded with a perfect score.
func TestParseLintCrashedUnparseableOutput(t *testing.T) {
	result := validation.ParseLintResults("docker: command not found\n", 127, 0)
	if result.Score >= 1.0 {
		t.Errorf("crashed lint should not score 1.0, got %f", result.Score)
	}
}

// ESLint's default 'stylish' formatter prints diagnostics as
// "  line:col  error  message  rule" -- whitespace separated, no colon
// after "error" or "warning". The parser must count these as issues.
// Sample contains 1 error and 1 warning -> totalIssues >= 2; score < 1.0.
func TestParseLintESLintStylishFormat(t *testing.T) {
	output := `/workspace/src/foo.ts
  3:5  error    'x' is defined but never used  no-unused-vars
  8:1  warning  Unexpected console statement   no-console

` + "✖" + ` 2 problems (1 error, 1 warning)
`
	result := validation.ParseLintResults(output, 0, 0)
	if result.NetNewIssues < 2 {
		t.Errorf("expected NetNewIssues >= 2 for two stylish diagnostics, got %d", result.NetNewIssues)
	}
	if result.Score >= 1.0 {
		t.Errorf("expected score < 1.0 with two new issues, got %f", result.Score)
	}
}

// Regression for agentic-thunderdome-69g: ParseLintResults previously
// counted any line containing the substring "Error:" or "Warning:" (or
// ": error" / ": warning") as a lint diagnostic. That over-counts on:
//   - npm install warnings emitted before the lint output
//   - Node.js exception stack traces piped into the lint stream
//   - lint diagnostics that quote user code which prints "Error:" / "Warning:"
// Each false positive drops the score by 0.1, saturating to 0 with ten hits.
// Diagnostics must be matched by their file:line:col shape, not by loose
// substrings.
func TestParseLintIgnoresNpmWarning(t *testing.T) {
	output := "npm WARN deprecated foo@1.0.0\n" +
		"Warning: a peer dependency is missing\n"
	result := validation.ParseLintResults(output, 0, 0)
	if result.NetNewIssues != 0 {
		t.Errorf("npm/peer-dep warnings must not count as lint issues, got NetNewIssues=%d", result.NetNewIssues)
	}
}

func TestParseLintIgnoresNodeStackTrace(t *testing.T) {
	output := "Error: Cannot find module 'eslint-plugin-foo'\n" +
		"    at Function.Module._resolveFilename (node:internal/modules/cjs/loader:1075:15)\n"
	result := validation.ParseLintResults(output, 0, 0)
	if result.NetNewIssues != 0 {
		t.Errorf("Node.js stack trace must not count as lint issues, got NetNewIssues=%d", result.NetNewIssues)
	}
}

func TestParseLintIgnoresConsoleStringContents(t *testing.T) {
	output := `/workspace/src/foo.ts
  10:5  warning  Unexpected console statement: 'Warning: do not log this'  no-console

` + "✖" + ` 1 problem (0 errors, 1 warning)
`
	result := validation.ParseLintResults(output, 0, 0)
	// Exactly one diagnostic: the eslint stylish line. The literal
	// "Warning:" inside the message string must not double-count.
	if result.NetNewIssues != 1 {
		t.Errorf("substring 'Warning:' inside diagnostic message must not double-count, got NetNewIssues=%d", result.NetNewIssues)
	}
}

// ESLint compact formatter ("file:line:col: severity message") must still
// be recognized as a diagnostic now that the loose substring rules are gone.
func TestParseLintESLintCompactFormat(t *testing.T) {
	output := "/workspace/src/foo.ts:10:5: error: 'x' is defined but never used (no-unused-vars)\n" +
		"/workspace/src/foo.ts:11:1: warning: Unexpected console statement (no-console)\n"
	result := validation.ParseLintResults(output, 1, 0)
	if result.NetNewIssues < 2 {
		t.Errorf("expected NetNewIssues >= 2 for two compact-format diagnostics, got %d", result.NetNewIssues)
	}
}

// TypeScript compiler ("tsc") emits "file(line,col): error TSxxxx: ..." which
// is a real diagnostic that must count.
func TestParseLintTscFormat(t *testing.T) {
	output := "src/foo.ts(10,5): error TS2304: Cannot find name 'x'.\n" +
		"src/foo.ts(11,1): error TS7006: Parameter 'y' implicitly has an 'any' type.\n"
	result := validation.ParseLintResults(output, 1, 0)
	if result.NetNewIssues < 2 {
		t.Errorf("expected NetNewIssues >= 2 for two tsc diagnostics, got %d", result.NetNewIssues)
	}
}

// Warnings-only ESLint stylish output (lint exits 0 because warnings
// are under the --max-warnings threshold). The parser must still count
// them so score reflects the agent-introduced warnings.
func TestParseLintESLintStylishWarningsOnly(t *testing.T) {
	output := `/workspace/src/foo.ts
  8:1  warning  Unexpected console statement  no-console
  9:1  warning  Missing semicolon              semi

` + "✖" + ` 2 problems (0 errors, 2 warnings)
`
	result := validation.ParseLintResults(output, 0, 0)
	if result.NetNewIssues < 2 {
		t.Errorf("expected NetNewIssues >= 2 for two stylish warnings, got %d", result.NetNewIssues)
	}
	if result.Score >= 1.0 {
		t.Errorf("expected score < 1.0 for warning-only output, got %f", result.Score)
	}
}

// Regression for uzx: Strategy 2 (bare line parser) must count "todo" in the
// denominator so it matches Strategy 1 (vitest summary), which includes todo
// in the (N) total.
func TestParsePassRateBareLineIncludesTodo(t *testing.T) {
	bare := validation.ParsePassRateForTest("5 passed, 2 failed, 3 todo")
	summary := validation.ParsePassRateForTest("Tests  2 failed | 5 passed | 3 todo (10)")
	if absf(bare-summary) > 0.0001 {
		t.Errorf("bare-line vs vitest-summary disagree: bare=%f summary=%f (todo should be in denominator)", bare, summary)
	}
	want := 0.5 // 5 / (5+2+3)
	if absf(bare-want) > 0.0001 {
		t.Errorf("bare-line pass rate = %f, want %f", bare, want)
	}
}

func TestParseVitestSummaryIgnoresPerTestLines(t *testing.T) {
	output := `
 ✓ src/foo.test.ts > Tests > does a thing (5)
 ✓ src/bar.test.ts > greets (1)

 Test Files  2 passed (2)
      Tests  6 passed (6)
   Start at  10:00:00
   Duration  1.23s
`
	result := validation.ParseTestResults(output, 0)
	if absf(result.Score-1.0) > 0.001 {
		t.Errorf("score: got %f, want 1.0 (parser locked onto per-test line instead of summary)", result.Score)
	}
}

func TestParseEmptyJUnitSuiteWithExitZero(t *testing.T) {
	output := `<?xml version="1.0"?><testsuites><testsuite name="x" tests="0" failures="0"></testsuite></testsuites>`
	result := validation.ParseTestResults(output, 0)
	if absf(result.Score-1.0) > 0.001 {
		t.Errorf("score: got %f, want 1.0 (empty suite + exit 0 should pass)", result.Score)
	}
}

func TestParseLintResultsDoesNotRewardUnparseableOutput(t *testing.T) {
	// ESLint JSON output: exit 0, non-empty stdout, no stylish/compact/tsc lines.
	jsonOut := `[{"filePath":"/x/a.ts","messages":[]}]`
	res := validation.ParseLintResults(jsonOut, 0, 0)
	if res.Score >= 1.0 {
		t.Errorf("Score = %f; expected < 1.0 for unparseable output (would confidently pass real warnings)", res.Score)
	}
}
