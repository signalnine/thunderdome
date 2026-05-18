# Bug-Fix Sweep: HIGH + MED Severity Implementation Plan (v2)

> **For Claude:** REQUIRED SUB-SKILL: Use `conclave:executing-plans` (or `conclave:subagent-driven-development`) to implement this plan task-by-task.

> **v2 changes from v1:** API references reconciled against the actual codebase after a consensus review found ~13 mismatches (unexported names, invented `TrialMeta` fields, wrong SDK identifiers, wrong function signatures). Tests for Wave 2 are now in-package (`package report`) so they can use the real unexported names (`aggregate`, `writeMarkdown`, `enrichCosts`, `OrchestratorSummary`). New fields on `TrialMeta` are declared explicitly as part of the tasks that need them.

**Goal:** Fix all 9 HIGH-severity and 12 MED-severity bugs from the 2026-05-18 audit, with each fix landing as its own commit, covered by a regression test (Go) or a smoke check (bash adapters).

**Architecture:** No architectural changes. Each task is a localized fix to a single concern. Five "waves" organize tasks by file area; within a wave, tasks that share a file are sequenced via the `Dependencies` field.

**Tech Stack:** Go 1.x (Cobra CLI, `github.com/moby/moby/client` Docker SDK, `testing` stdlib), bash adapter scripts, Vitest output formats, YAML config.

**Test conventions (verified):**
- External tests use `package <name>_test` (e.g. `validation_test`, `runner_test`)
- White-box tests for unexported names use `package <name>` (we use this for Wave 2 since `aggregate`/`writeMarkdown`/`enrichCosts` are unexported)
- `t.TempDir()` for filesystem tests; `absf(x-want) > 0.001` for float comparisons
- Commit messages: `fix(scope): lowercase summary, no trailing period` — match `git log --oneline -10` style

**Verification gate per task (@conclave:verification-before-completion):**
1. Run the specific package test (`go test ./internal/<pkg>/...`)
2. Run `go test ./...` for cross-package regression
3. Commit only after both pass

---

## Wave Overview

| Wave | Area | Tasks | Parallel-safe? |
|---|---|---|---|
| 1 | `internal/validation/` | T1–T5 | Yes — each touches a different file |
| 2 | `internal/report/` (+ `result/types.go` for T10) | T6–T10 | Serialize (all touch `report.go`) |
| 3 | `internal/runner/`, `internal/result/storage.go`, `cmd/run.go` | T11–T14 | Serialize T12/T13/T14 (all touch `trial.go`); T11 independent |
| 4 | `internal/docker/`, `internal/gateway/` | T15–T17 | Serialize T16/T17 (both touch `gateway.go`); T15 independent |
| 5 | `cmd/run.go`, `adapters/*` | T18–T21 | Yes — different files |

**Recommended order:** Waves 1 → 2 → 3 → 4 → 5. Within a wave, run parallel-safe tasks via @conclave:subagent-driven-development.

---

# WAVE 1 — `internal/validation/`

## Task 1: Anchor the Vitest summary regex

**Bug:** `vitestSummaryRe` is unanchored (`Tests\s+([^()]+?)\s*\((\d+)\)`) — verbose Vitest output with per-test lines like `✓ src/foo.test.ts > Tests > something (5)` matches before reaching the real summary; scoring returns 0/N when everything actually passed.

**Files:**
- Modify: `internal/validation/testrunner.go:72`
- Test: `internal/validation/validation_test.go`

**Dependencies:** none

**Step 1: Write the failing test** (append to `validation_test.go`):

```go
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
```

**Step 2: Run test → expect FAIL**

```bash
go test ./internal/validation/ -run TestParseVitestSummaryIgnoresPerTestLines -v
```

**Step 3: Implement** — change `internal/validation/testrunner.go:72` from:
```go
var vitestSummaryRe = regexp.MustCompile(`Tests\s+([^()]+?)\s*\((\d+)\)`)
```
to:
```go
var vitestSummaryRe = regexp.MustCompile(`^\s*Tests\s+([^()]+?)\s*\((\d+)\)\s*$`)
```

(The loop body already iterates lines, so the anchor will scope matching correctly.)

**Step 4: Run all package tests → expect PASS**

```bash
go test ./internal/validation/ -v
```

**Step 5: Commit**

```bash
git add internal/validation/testrunner.go internal/validation/validation_test.go
git commit -m "fix(validation): anchor vitest summary regex to avoid matching per-test lines"
```

---

## Task 2: Filter test files from `code_metrics` source walk

**Bug:** `RunCodeMetrics` first `filepath.Walk` over `src/` has no `.test.`/`.spec.` filter, so `src/foo.test.ts` is counted both as source (`FileCount`) and test (`TestFileCount`).

**Files:**
- Modify: `internal/validation/code_metrics.go:30-55`
- Test: `internal/validation/code_metrics_test.go`

**Dependencies:** none

**Step 1: Write the failing test** (append to `code_metrics_test.go`):

```go
func TestRunCodeMetricsExcludesInlineTestsFromSrcCount(t *testing.T) {
	work := t.TempDir()
	writeFile(t, filepath.Join(work, "src", "main.ts"), "export const a = 1;\n")
	writeFile(t, filepath.Join(work, "src", "foo.test.ts"), "test('a', () => {});\n")

	res, err := validation.RunCodeMetrics(work)
	if err != nil {
		t.Fatal(err)
	}
	if res.FileCount != 1 {
		t.Errorf("FileCount = %d, want 1 (inline test file should not count as source)", res.FileCount)
	}
	if res.TestFileCount != 1 {
		t.Errorf("TestFileCount = %d, want 1", res.TestFileCount)
	}
}
```

**Step 2: Run → expect FAIL** (`FileCount = 2, want 1`)

```bash
go test ./internal/validation/ -run TestRunCodeMetricsExcludesInlineTestsFromSrcCount -v
```

**Step 3: Implement** — in the first walk body (`code_metrics.go:30-55`), after the existing extension/declaration-file guards add:

```go
// Skip inline test/spec files — they're counted in the test walk below.
rel, _ := filepath.Rel(workDir, path)
if strings.Contains(rel, "__tests__") || strings.Contains(info.Name(), ".test.") || strings.Contains(info.Name(), ".spec.") {
    return nil
}
```

**Step 4: Verify**

```bash
go test ./internal/validation/ -v
```

**Step 5: Commit**

```bash
git add internal/validation/code_metrics.go internal/validation/code_metrics_test.go
git commit -m "fix(validation): exclude inline test files from code_metrics source count"
```

---

## Task 3: Treat empty JUnit suites with exit 0 as passing

**Bug:** `parseJUnitXML` (returns `float64`) returns `0.0` for `<testsuite tests="0">`, indistinguishable from a 100%-failing suite. Should return a sentinel so caller's `exitCode == 0 → 1.0` path wins.

**Files:**
- Modify: `internal/validation/testrunner.go` `parseJUnitXML` function
- Test: `internal/validation/validation_test.go`

**Dependencies:** none

**Step 1: Write the failing test**

```go
func TestParseEmptyJUnitSuiteWithExitZero(t *testing.T) {
	output := `<?xml version="1.0"?><testsuites><testsuite name="x" tests="0" failures="0"></testsuite></testsuites>`
	result := validation.ParseTestResults(output, 0)
	if absf(result.Score-1.0) > 0.001 {
		t.Errorf("score: got %f, want 1.0 (empty suite + exit 0 should pass)", result.Score)
	}
}
```

**Step 2: Run → expect FAIL** (`got 0.000000, want 1.0`)

**Step 3: Implement** — locate `parseJUnitXML` (signature: `func parseJUnitXML(output string) float64`). At the point where the function returns when `total <= 0`, change to return `-1` (or whatever sentinel `ParseTestResults` interprets as "no output"). Confirm by reading `ParseTestResults` first:

```bash
grep -n "func ParseTestResults\|parseJUnitXML\|parsePassRate" internal/validation/testrunner.go
```

Then in `parseJUnitXML`, when the count is zero, `return -1` (caller checks `< 0` to fall back to exit-code-based scoring).

**Step 4 & 5: Verify and commit**

```bash
go test ./internal/validation/ -v
git add internal/validation/testrunner.go internal/validation/validation_test.go
git commit -m "fix(validation): treat empty JUnit suite as no-output sentinel"
```

---

## Task 4: Detect unparseable lint output (minimal fix)

**Bug:** `ParseLintResults` returns `Score: 1.0` when `exitCode == 0` and stdout is non-empty but no recognized diagnostic lines parse (e.g. `eslint --format json` with banner). Real warnings are invisible.

**Files:**
- Modify: `internal/validation/lint.go` `ParseLintResults` (`:60-97`)
- Test: `internal/validation/validation_test.go`

**Dependencies:** none

**Scope discipline:** minimal fix only — return a sentinel score lower than 1.0 when output is non-empty but no issues parsed. No new fields, no JSON probe (that's a separate feature).

**Step 1: Write the failing test**

```go
func TestParseLintResultsDoesNotRewardUnparseableOutput(t *testing.T) {
	// ESLint JSON output: exit 0, non-empty stdout, no stylish/compact/tsc lines.
	jsonOut := `[{"filePath":"/x/a.ts","messages":[]}]`
	res := validation.ParseLintResults(jsonOut, 0, 0)
	if res.Score >= 1.0 {
		t.Errorf("Score = %f; expected < 1.0 for unparseable output (would confidently pass real warnings)", res.Score)
	}
}
```

**Step 2: Run → expect FAIL** (currently returns 1.0)

```bash
go test ./internal/validation/ -run TestParseLintResultsDoesNotRewardUnparseableOutput -v
```

**Step 3: Implement** — in `lint.go:60-97`, just before the final `return &LintResult{Score: score, …}`, add a guard:

```go
// If the linter produced substantive output but our parsers recognized no
// diagnostics, the formatter is likely one we don't support (JSON, unix,
// custom). Avoid awarding a confident 1.0 — return a conservative 0.5.
if exitCode == 0 && totalIssues == 0 && strings.TrimSpace(output) != "" {
    return &LintResult{Score: 0.5, Output: output, ExitCode: exitCode}
}
```

This sits above the netNew block. Add `"strings"` to imports if not already present (it is).

**Step 4 & 5:**

```bash
go test ./internal/validation/ -v
git add internal/validation/lint.go internal/validation/validation_test.go
git commit -m "fix(validation): score unparseable lint output at 0.5 instead of 1.0"
```

---

## Task 5: Refine `CoverageMeasured` so coverage failure doesn't reward zero-test agents

**Bug:** `GreenfieldCompositeScore` at `composite.go:67-69` passes `agentTestScore = scores.AgentTests` (no coverage multiplier) when `CoverageMeasured == false`. Intended as protection against environmental coverage-tool failures, but it also fires when the agent legitimately wrote zero tests and `RunCoverage` errored on the missing `coverage-summary.json` — rewarding the failure on the 30.8% AgentTests axis.

**Files:**
- Modify: `internal/runner/trial.go` `validateGreenfield` (the block that sets `meta.Scores.CoverageMeasured`)
- Test: `internal/runner/trial_test.go` or `internal/validation/composite_test.go` (whichever is easier — coverage is set in trial.go, so trial_test.go is closer to the bug)

**Dependencies:** none for code, but **coordinate with Wave 3 tasks** — T12/T13/T14 also touch `trial.go`. Execute T5 *before* Wave 3 to avoid merge conflicts, or batch with Wave 3.

**Step 1: Inspect the current code** — find where `CoverageMeasured` is set:

```bash
grep -n "CoverageMeasured" internal/runner/trial.go internal/validation/composite.go
```

**Step 2: Write the failing test** in `internal/runner/trial_test.go`:

```go
// Test the helper that decides whether coverage should be considered measured.
// Extract logic into a small package-private function for testability:
//   coverageMeasured(coverageScore float64, parseErr error, agentTestsRan bool) bool
// Then assert: when coverage parse fails AND the agent had tests, treat as measured-at-zero.
func TestCoverageMeasuredFalseRewardsCoverageFailureBug(t *testing.T) {
	// Case A: coverage tool failed but agent wrote tests → MUST be measured (so multiplier zeroes out the credit)
	if !runner.CoverageMeasured(0, errors.New("file not found"), true) {
		t.Errorf("agent wrote tests + coverage failed: expected measured=true, got false")
	}
	// Case B: coverage tool failed AND agent wrote no tests → can be unmeasured (skip multiplier)
	if runner.CoverageMeasured(0, errors.New("file not found"), false) {
		t.Errorf("no tests + coverage failed: expected measured=false, got true")
	}
	// Case C: coverage parsed successfully → measured
	if !runner.CoverageMeasured(0.85, nil, true) {
		t.Errorf("coverage parsed: expected measured=true")
	}
}
```

**Step 3: Implement**

In `internal/runner/trial.go`, extract the logic into a package-public helper:

```go
// CoverageMeasured decides whether the coverage signal should count in the
// greenfield composite. When coverage parsing succeeds, it's always measured.
// When it fails, we only treat it as "not measured" (giving AgentTests a free
// pass) if the agent wrote no tests — otherwise the coverage failure is real
// signal and should zero out the multiplier.
func CoverageMeasured(coverage float64, parseErr error, agentTestsRan bool) bool {
    if parseErr == nil {
        return true
    }
    return agentTestsRan
}
```

Then in `validateGreenfield`, replace the existing CoverageMeasured assignment with a call to this helper, passing in `meta.Scores.AgentTests > 0` as `agentTestsRan`.

**Step 4 & 5:**

```bash
go test ./internal/runner/ ./internal/validation/ -v
git add internal/runner/trial.go internal/runner/trial_test.go
git commit -m "fix(runner): mark coverage measured-at-zero when agent had tests but parse failed"
```

---

# WAVE 2 — `internal/report/` (white-box tests for unexported APIs)

> All five tasks touch `internal/report/report.go`. Execute serially. Tests use `package report` (white-box) so they can call `aggregate`, `writeMarkdown`, `enrichCosts`, and reference `OrchestratorSummary` directly.

## Task 6: Filtered pass rate that excludes crashes

**Bug:** `PassRate = float64(a.passed) / float64(a.count)` (`report.go:137`) includes `NoAgentContribution=true` trials in the denominator. README says crashes are excluded from leaderboard numbers; only `MeanScoreFiltered` honors that today.

**Files:**
- Modify: `internal/report/report.go` (`OrchestratorSummary` struct + `aggregate` body + writers)
- Test: `internal/report/report_test.go`

**Dependencies:** none (first task in Wave 2)

**Step 1: Write the failing test** — `report_test.go` (verify package declaration is `package report`):

```go
func TestPassRateFilteredExcludesCrashes(t *testing.T) {
	metas := []*result.TrialMeta{
		{Orchestrator: "x", ExitReason: "completed", CompositeScore: 1.0, NoAgentContribution: false},
		{Orchestrator: "x", ExitReason: "crashed",   CompositeScore: 0.0, NoAgentContribution: true},
		{Orchestrator: "x", ExitReason: "completed", CompositeScore: 1.0, NoAgentContribution: false},
	}
	summaries := aggregate(metas)
	if len(summaries) != 1 {
		t.Fatalf("expected 1 summary, got %d", len(summaries))
	}
	got := summaries[0].PassRateFiltered
	if absf(got-1.0) > 0.001 {
		t.Errorf("PassRateFiltered = %f, want 1.0 (2 of 2 non-crash trials completed)", got)
	}
}
```

You may need a local `absf` helper at the top of `report_test.go`:
```go
func absf(x float64) float64 { if x < 0 { return -x }; return x }
```

**Step 2: Run → expect compile error** (`summaries[0].PassRateFiltered undefined`)

```bash
go test ./internal/report/ -run TestPassRateFilteredExcludesCrashes -v
```

**Step 3: Implement**

In `report.go`:
1. Add field to `OrchestratorSummary`:
   ```go
   PassRateFiltered float64 `json:"pass_rate_filtered"`
   ```
2. In the `accum` struct (`aggregate` body), add `passedFiltered int`.
3. In the aggregation loop (around `:105-113`), change the pass counting:
   ```go
   if m.ExitReason == "completed" {
       a.passed++
       if !m.NoAgentContribution {
           a.passedFiltered++
       }
   }
   ```
4. After the loop, compute (with zero-guard):
   ```go
   if a.countFiltered > 0 {
       s.PassRateFiltered = float64(a.passedFiltered) / float64(a.countFiltered)
   }
   ```
5. Update `writeTable` and `writeMarkdown` headers/rows to include the new column. Keep `PassRate` (unfiltered) for backward-compat.

**Step 4 & 5:**

```bash
go test ./internal/report/ -v
git add internal/report/report.go internal/report/report_test.go
git commit -m "fix(report): add pass_rate_filtered excluding crash trials"
```

---

## Task 7: Drop `omitempty` from `MeanScoreFiltered`

**Bug:** `MeanScoreFiltered float64 \`json:"mean_score_filtered,omitempty"\`` (`report.go:25`) — legitimate 0.0 values are dropped from JSON. Consumers can't distinguish "no filtered trials" from "filtered mean is exactly 0".

**Files:**
- Modify: `internal/report/report.go:25`
- Test: `internal/report/report_test.go`

**Dependencies:** Task 6

**Step 1: Write the failing test**

```go
func TestMeanScoreFilteredEmittedWhenLegitimateZero(t *testing.T) {
	metas := []*result.TrialMeta{
		{Orchestrator: "x", CompositeScore: 0.0, NoAgentContribution: false, ExitReason: "completed"},
	}
	summaries := aggregate(metas)

	var buf bytes.Buffer
	if err := writeJSON(summaries, &buf); err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(buf.String(), `"mean_score_filtered":0`) {
		t.Errorf("JSON output omits mean_score_filtered when value is 0:\n%s", buf.String())
	}
}
```

**Step 2: Run → expect FAIL**

```bash
go test ./internal/report/ -run TestMeanScoreFilteredEmittedWhenLegitimateZero -v
```

**Step 3: Implement** — change `OrchestratorSummary.MeanScoreFiltered` from `float64` with `omitempty` to a pointer:

```go
MeanScoreFiltered *float64 `json:"mean_score_filtered"`
```

In `aggregate`:
```go
if a.countFiltered > 0 {
    v := a.scoreFiltered / float64(a.countFiltered)
    s.MeanScoreFiltered = &v
}
```

In `writeTable` and `writeMarkdown` (locations: `report.go:231` and `:288`), update the dereferences:
```go
var msf float64
if s.MeanScoreFiltered != nil {
    msf = *s.MeanScoreFiltered
}
// then use msf in the Fprintf
```

**Step 4 & 5:**

```bash
go test ./internal/report/ -v
git add internal/report/report.go internal/report/report_test.go
git commit -m "fix(report): emit mean_score_filtered even when zero (use pointer)"
```

---

## Task 8: Escape `|` in markdown writer

**Bug:** `writeMarkdown` interpolates `s.Name` raw between table delimiters; an orchestrator name containing `|` corrupts the table.

**Files:**
- Modify: `internal/report/report.go:264-313` (`writeMarkdown`)
- Test: `internal/report/report_test.go`

**Dependencies:** Task 7

**Step 1: Write the failing test**

```go
func TestWriteMarkdownEscapesPipeInName(t *testing.T) {
	summaries := []OrchestratorSummary{{Name: "foo|bar", Trials: 1, PassRate: 1.0}}
	var buf bytes.Buffer
	if err := writeMarkdown(summaries, &buf); err != nil {
		t.Fatal(err)
	}
	out := buf.String()
	if strings.Contains(out, "| foo|bar |") {
		t.Errorf("unescaped pipe in markdown row:\n%s", out)
	}
	if !strings.Contains(out, `foo\|bar`) {
		t.Errorf(`expected \| escape; got:\n%s`, out)
	}
}
```

**Step 2: Run → expect FAIL**

**Step 3: Implement** — add a helper at the top of `report.go`:

```go
func mdEscape(s string) string {
    s = strings.ReplaceAll(s, `|`, `\|`)
    s = strings.ReplaceAll(s, "\n", " ")
    return s
}
```

Apply to every `s.Name` Fprintf in `writeMarkdown` (three call sites: main table, no-contribution table, greenfield table).

**Step 4 & 5:**

```bash
go test ./internal/report/ -v
git add internal/report/report.go internal/report/report_test.go
git commit -m "fix(report): escape pipe and newline characters in markdown writer"
```

---

## Task 9: Preserve adapter cost when ANY usage record is unpriced

**Bug:** `enrichCosts` (`report.go:161-200`) currently does:
```go
if !priced { continue }   // line 195 — ALL records unpriced → keep adapter total
m.TotalCostUSD = totalCost  // line 198
```
The branch only protects the "no records priced" case. When some records are priced and some aren't, `priced = true`, and `m.TotalCostUSD` is overwritten with the partial sum (priced models only), dropping the unpriced model's spend recorded by the adapter.

**Files:**
- Modify: `internal/report/report.go:161-200` (`enrichCosts`)
- Test: `internal/report/report_test.go` (use a fixture proxy-log.jsonl on disk)

**Dependencies:** Task 8

**Step 1: Inspect existing test setup** — `report_test.go` may already have fixture builders; reuse them:

```bash
grep -n "proxy-log\|enrichCosts\|TestEnrich" internal/report/report_test.go
```

**Step 2: Write the failing test** — uses real `enrichCosts` against a temp fixture:

```go
func TestEnrichCostsPreservesAdapterTotalWhenAnyModelUnpriced(t *testing.T) {
	runDir := t.TempDir()
	trialDir := result.TrialDir(runDir, "x", "T1", 1)
	if err := os.MkdirAll(trialDir, 0o755); err != nil { t.Fatal(err) }

	// Two usage records: one priced (anthropic/claude-opus-4-6), one unpriced (some-unlisted/model).
	proxyLog := filepath.Join(trialDir, "proxy-log.jsonl")
	body := strings.Join([]string{
		`{"provider":"anthropic","model":"claude-opus-4-6","input_tokens":1000,"output_tokens":500,"timestamp":1}`,
		`{"provider":"some-unlisted","model":"unpriced-model","input_tokens":5000,"output_tokens":1000,"timestamp":2}`,
		``,
	}, "\n")
	if err := os.WriteFile(proxyLog, []byte(body), 0o644); err != nil { t.Fatal(err) }

	// Adapter recorded a $0.50 total covering both models.
	m := &result.TrialMeta{Orchestrator: "x", Task: "T1", Trial: 1, TotalCostUSD: 0.50}
	enrichCosts(runDir, []*result.TrialMeta{m}, "../../pricing.yaml")
	// (Path adjusted: pricing.yaml lives at repo root; test runs from internal/report)

	// With the fix: because one model is unpriced, m.TotalCostUSD stays at 0.50.
	if m.TotalCostUSD < 0.49 {
		t.Errorf("TotalCostUSD = %f; expected adapter total (~0.50) preserved when an unpriced model is present", m.TotalCostUSD)
	}
}
```

> Note: the test depends on `pricing.yaml` having `anthropic/claude-opus-4-6` but NOT `some-unlisted/unpriced-model`. Verify with `grep -E "claude-opus-4-6|unpriced-model" pricing.yaml` before running.

**Step 3: Run → expect FAIL** (or skip if pricing.yaml setup differs)

**Step 4: Implement** — in `enrichCosts` (`report.go:185-198`), change the priced-tracking logic:

```go
var totalCost float64
allPriced := true
for _, r := range records {
    if !table.Has(r.Provider, r.Model) {
        allPriced = false
    }
    totalCost += table.Cost(r.Provider, r.Model, r.InputTokens, r.OutputTokens, r.CacheCreationTokens, r.CacheReadTokens)
}
// Only overwrite the adapter-recorded total when we successfully priced EVERY
// record. Partial overwrite would silently drop the unpriced model's spend.
if !allPriced {
    continue
}
m.TotalCostUSD = totalCost
```

This is minimal: replaces `priced bool` with `allPriced bool`, inverts the check, and the `continue` semantics carry over.

**Step 5: Verify and commit**

```bash
go test ./internal/report/ -v
git add internal/report/report.go internal/report/report_test.go
git commit -m "fix(report): preserve adapter cost when any usage record is unpriced"
```

---

## Task 10: Add min-N trial qualification gate

**Bug:** No gating exists; the leaderboard publishes orchestrators with 1 trial alongside ones with 200. README documents an "8+ standard AND 8+ hard non-crash trials" rule.

**Files:**
- Modify: `internal/result/types.go` — add a `Category` field to `TrialMeta`
- Modify: `internal/runner/trial.go` — populate `meta.Category = task.Category` in `RunTrial`
- Modify: `internal/report/report.go` — count standard vs hard per orchestrator; set `Qualified` flag
- Test: `internal/report/report_test.go`

**Dependencies:** Task 9 (`report.go` serial), Wave 3 tasks (`trial.go` serial — execute T10 AFTER Wave 3, or batch the `trial.go` edit with T11/T13/T14)

**Scope justification:** README publishes this rule; it's not feature creep. We're surfacing the existing convention to the reporter.

**Step 1: Decide category classification** — for now, classify by `strings.HasPrefix(category, "greenfield")` or `category == "hard"` etc. Spec: anything matching `greenfield/*` is "hard"; everything else is "standard". (Verify against `thunderdome.yaml` task categories first: `grep "^    category:" thunderdome.yaml | sort -u`.)

**Step 2: Write the failing test**

```go
func TestQualifiedFlagRequires8PerSuite(t *testing.T) {
	var metas []*result.TrialMeta
	mk := func(orch, cat string, crash bool) *result.TrialMeta {
		return &result.TrialMeta{Orchestrator: orch, Category: cat, NoAgentContribution: crash, ExitReason: "completed"}
	}
	// x: 8 standard non-crash + 8 hard non-crash → qualified
	for i := 0; i < 8; i++ { metas = append(metas, mk("x", "features", false)) }
	for i := 0; i < 8; i++ { metas = append(metas, mk("x", "greenfield/hard", false)) }
	// y: 7 standard + 8 hard → NOT qualified
	for i := 0; i < 7; i++ { metas = append(metas, mk("y", "features", false)) }
	for i := 0; i < 8; i++ { metas = append(metas, mk("y", "greenfield/hard", false)) }

	summaries := aggregate(metas)
	for _, s := range summaries {
		switch s.Name {
		case "x": if !s.Qualified { t.Errorf("x: expected Qualified=true") }
		case "y": if s.Qualified  { t.Errorf("y: expected Qualified=false (only 7 standard non-crash)") }
		}
	}
}
```

**Step 3: Implement**

1. **`internal/result/types.go`** — add to `TrialMeta`:
   ```go
   Category string `json:"category,omitempty"`
   ```
2. **`internal/runner/trial.go`** — find where the initial `TrialMeta` is constructed in `RunTrial` and set:
   ```go
   meta.Category = task.Category
   ```
3. **`internal/report/report.go`**:
   - Add field: `Qualified bool \`json:"qualified"\``
   - In `accum`, add `standardNonCrash, hardNonCrash int`.
   - During the loop, when `!m.NoAgentContribution`:
     ```go
     if strings.HasPrefix(m.Category, "greenfield") {
         a.hardNonCrash++
     } else {
         a.standardNonCrash++
     }
     ```
   - After loop: `s.Qualified = a.standardNonCrash >= 8 && a.hardNonCrash >= 8`.
   - Surface `Qualified` in the table writer (add a `(*)` marker or a new column).

**Step 4 & 5:**

```bash
go test ./internal/report/ ./internal/runner/ -v
git add internal/result/types.go internal/runner/trial.go internal/report/report.go internal/report/report_test.go
git commit -m "fix(report): add qualified flag for 8+ standard and 8+ hard non-crash trials"
```

---

# WAVE 3 — Runner, Result, Top-Level Context

## Task 11: Atomic `WriteTrialMeta` (write-then-rename)

**Bug:** `internal/result/storage.go:76` uses `os.WriteFile`, which truncates before writing. SIGKILL/OOM/power loss mid-write leaves a zero-length `meta.json` silently dropped by `report.collectMetas` (the JSON unmarshal fails and `nil` is appended to nothing).

**Files:**
- Modify: `internal/result/storage.go` (`WriteTrialMeta`)
- Test: `internal/result/storage_test.go`

**Dependencies:** none

> Note: `updateLatest` at `storage.go:44-62` already uses the tmp+rename pattern — copy that approach.

**Step 1: Write the failing test**

```go
func TestWriteTrialMetaIsAtomic(t *testing.T) {
	dir := t.TempDir()
	meta := &result.TrialMeta{Orchestrator: "x", Task: "T1", CompositeScore: 0.5}
	if err := result.WriteTrialMeta(dir, meta); err != nil {
		t.Fatal(err)
	}
	// No tmp file should leak after a successful write.
	matches, _ := filepath.Glob(filepath.Join(dir, "meta.json.tmp*"))
	if len(matches) > 0 {
		t.Errorf("tmp files leaked after atomic write: %v", matches)
	}
	// meta.json must parse.
	got, err := result.ReadTrialMeta(filepath.Join(dir, "meta.json"))
	if err != nil {
		t.Fatalf("ReadTrialMeta failed after atomic write: %v", err)
	}
	if got.Task != "T1" {
		t.Errorf("Task = %q, want T1", got.Task)
	}
}
```

**Step 2: Run → may PASS** (this test verifies the pattern; if it passes immediately, the failure-mode test below is what fails first):

Also add a stricter test that verifies tmp + rename happens (white-box, in `package result`):

```go
// In storage_test.go, package result:
func TestWriteTrialMetaDoesNotLeavePartial(t *testing.T) {
	dir := t.TempDir()
	meta := &TrialMeta{Task: "T1"}
	if err := WriteTrialMeta(dir, meta); err != nil { t.Fatal(err) }
	// Before fix: meta.json is written via os.WriteFile (atomic on most FSs for small writes,
	// but truncates first on others). After fix: a Glob for tmp-files MUST find none.
	tmps, _ := filepath.Glob(filepath.Join(dir, "meta.json.tmp*"))
	if len(tmps) != 0 {
		t.Errorf("leaked tmps: %v", tmps)
	}
}
```

The behavior-focused test for atomicity is hard to write without a crash injection. The presence of `meta.json.tmp*` glob is the cleanest proxy.

**Step 3: Implement** — replace `WriteTrialMeta` in `internal/result/storage.go:68-77` with:

```go
func WriteTrialMeta(trialDir string, meta *TrialMeta) error {
    if err := os.MkdirAll(trialDir, 0o755); err != nil {
        return fmt.Errorf("creating trial dir: %w", err)
    }
    data, err := json.MarshalIndent(meta, "", "  ")
    if err != nil {
        return fmt.Errorf("marshaling meta: %w", err)
    }
    target := filepath.Join(trialDir, "meta.json")
    tmp, err := os.CreateTemp(trialDir, "meta.json.tmp-*")
    if err != nil {
        return fmt.Errorf("creating tmp meta: %w", err)
    }
    tmpPath := tmp.Name()
    defer func() {
        if _, statErr := os.Stat(tmpPath); statErr == nil {
            os.Remove(tmpPath)
        }
    }()
    if _, err := tmp.Write(data); err != nil {
        tmp.Close()
        return fmt.Errorf("writing tmp meta: %w", err)
    }
    if err := tmp.Sync(); err != nil {
        tmp.Close()
        return fmt.Errorf("syncing tmp meta: %w", err)
    }
    if err := tmp.Close(); err != nil {
        return fmt.Errorf("closing tmp meta: %w", err)
    }
    return os.Rename(tmpPath, target)
}
```

**Step 4 & 5:**

```bash
go test ./internal/result/ ./internal/runner/ -v
git add internal/result/storage.go internal/result/storage_test.go
git commit -m "fix(result): atomic meta.json write via tmp+rename"
```

---

## Task 12: Wire `signal.NotifyContext` into the run command

**Bug:** `cmd/run.go:78` uses `ctx := context.Background()`. Ctrl-C hits Go's default handler and skips the careful `<-ctx.Done()` cleanup in `docker/runner.go:154` and the deferred `gw.Stop()` at `cmd/run.go:91`. In `--parallel N` mode, up to N-1 containers and the gateway port can leak.

**Files:**
- Modify: `cmd/run.go:78` (the assignment) and imports
- Modify: `internal/runner/pool.go` — change `Job` to accept ctx, and `RunPool` to accept and respect ctx
- Modify: `cmd/run.go:104-141` — Job closures take ctx
- Modify: `internal/runner/pool_test.go` — existing callers will need ctx
- Search for other `RunPool` callers: `grep -rn "runner.RunPool\|runner.Job" internal/ cmd/`

**Dependencies:** none, but **batch with T13/T14 + T5** if you don't want trial.go merge conflicts

**Step 1: Check the full caller surface**

```bash
grep -rn "runner.RunPool\|runner.Job\b" internal/ cmd/
```

Expected callers: `cmd/run.go:142` and the three tests in `internal/runner/pool_test.go`. If `cmd/rescore.go` uses RunPool, add it to the modify list.

**Step 2: Write the failing test** (append to `pool_test.go`):

```go
func TestPoolRespectsContextCancel(t *testing.T) {
	ctx, cancel := context.WithCancel(context.Background())
	started := make(chan struct{}, 2)
	job := func(ctx context.Context) error {
		started <- struct{}{}
		<-ctx.Done()
		return ctx.Err()
	}
	go func() {
		<-started
		cancel()
	}()
	errs := runner.RunPool(ctx, 2, []runner.Job{job, job})
	for _, e := range errs {
		if e != nil && !errors.Is(e, context.Canceled) {
			t.Errorf("unexpected error: %v", e)
		}
	}
}
```

This requires the new signature.

**Step 3: Implement**

1. **`internal/runner/pool.go`** — change signatures:
   ```go
   type Job func(ctx context.Context) error

   func RunPool(ctx context.Context, maxWorkers int, jobs []Job) []error {
       // ...
       for _, job := range jobs {
           wg.Add(1)
           select {
           case sem <- struct{}{}:
           case <-ctx.Done():
               wg.Done()
               continue
           }
           go func(j Job) {
               defer wg.Done()
               defer func() { <-sem }()
               // panic recovery as before
               if err := j(ctx); err != nil {
                   mu.Lock(); errs = append(errs, err); mu.Unlock()
               }
           }(job)
       }
       wg.Wait()
       return errs
   }
   ```

2. **`cmd/run.go:78`** — replace with:
   ```go
   ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
   defer stop()
   ```
   Add imports: `"os/signal"`, `"syscall"`.

3. **`cmd/run.go:109-138`** — change the job closure signature:
   ```go
   jobs = append(jobs, func(ctx context.Context) error {
       // ... use this ctx, not the outer one
   })
   ```
   And the call: `errs := runner.RunPool(ctx, flagParallel, jobs)`.

4. **`internal/runner/pool_test.go`** — update the three existing tests (`TestPool`, `TestPoolWithErrors`, `TestPoolRecoversPanickingJob`) to use the new `Job` signature and pass `context.Background()` to `RunPool`.

**Step 4: Verify**

```bash
go test ./... -count=1
```

Smoke check Ctrl-C cleanup:
```bash
make build
./thunderdome run --orchestrator null --task T1 --parallel 2 --trials 4 &
PID=$!; sleep 5; kill -INT $PID; wait $PID 2>/dev/null
docker ps -a --filter "label=thunderdome=true" --format "{{.ID}} {{.Status}}"
```
Expected: no orphan containers.

**Step 5: Commit**

```bash
git add cmd/run.go internal/runner/pool.go internal/runner/pool_test.go
git commit -m "fix(runner): wire signal.NotifyContext through RunPool for clean Ctrl-C cleanup"
```

---

## Task 13: Write crash-meta on early-error paths in `RunTrial`

**Bug:** When `docker.RunContainer` errors after a long run (`internal/runner/trial.go` around `:225-227`), `RunTrial` returns `nil, err` *before* writing `meta.json`. Same for `gitops.CaptureChanges` failure later. Token/cost/exit-reason for that trial is unrecoverable.

**Files:**
- Modify: `internal/runner/trial.go` (early-error paths)
- Modify: `internal/result/types.go` — add `Error string` field
- Test: `internal/runner/trial_test.go`

**Dependencies:** Task 12 (`trial.go` serial)

**Step 1: Locate the error paths**

```bash
grep -n "docker.RunContainer\|gitops.CaptureChanges\|return nil, err" internal/runner/trial.go
```

**Step 2: Write the failing test** — this needs an injection point. The simplest is a unit test against a helper:

```go
// In trial_test.go:
func TestSynthesizeCrashMeta(t *testing.T) {
	got := runner.SynthesizeCrashMeta(&config.Task{ID: "T1", Repo: "./benchmarks/bench-time-tracker"},
		"my-orch", 1, fmt.Errorf("docker daemon unreachable"))
	if got.ExitReason == "completed" {
		t.Errorf("ExitReason = %q, want crash-related", got.ExitReason)
	}
	if got.Error == "" {
		t.Errorf("Error field empty; expected diagnostic message")
	}
}
```

**Step 3: Implement**

1. **`internal/result/types.go`** — add:
   ```go
   Error string `json:"error,omitempty"`
   ```

2. **`internal/runner/trial.go`** — add helper:
   ```go
   func SynthesizeCrashMeta(task *config.Task, orchName string, trialNum int, cause error) *result.TrialMeta {
       return &result.TrialMeta{
           Orchestrator: orchName,
           Task:         TaskName(task),
           Trial:        trialNum,
           Category:     task.Category,
           ExitCode:     -1,
           ExitReason:   "infra_error",
           Error:        cause.Error(),
       }
   }
   ```

3. **`internal/runner/trial.go`** — at every `return nil, err` after the trial directory is created (post-container, post-diff), replace with:
   ```go
   crashMeta := SynthesizeCrashMeta(opts.Task, opts.Orchestrator.Name, opts.TrialNum, err)
   if writeErr := result.WriteTrialMeta(trialDir, crashMeta); writeErr != nil {
       log.Printf("warn: failed to write crash meta for %s/%s trial %d: %v",
           opts.Orchestrator.Name, TaskName(opts.Task), opts.TrialNum, writeErr)
   }
   return nil, err
   ```

**Step 4 & 5:**

```bash
go test ./internal/runner/ ./internal/result/ -v
git add internal/runner/trial.go internal/result/types.go internal/runner/trial_test.go
git commit -m "fix(runner): write crash meta.json on container and diff capture failures"
```

---

## Task 14: Distinguish OOM, cancel, and infra errors in `ExitReasonFromCode`

**Bug:** Exit 137 (OOM-kill), 130 (Ctrl-C cascade), and 125 (Docker infra error) all collapse into `"crashed"`, indistinguishable from a real agent bug.

**Files:**
- Modify: `internal/runner/trial.go` (`ExitReasonFromCode` around `:37`)
- Modify: `internal/runner/trial.go` (`DetectNoAgentContribution` if needed)
- Test: `internal/runner/trial_test.go`

**Dependencies:** Task 13 (`trial.go` serial)

**Step 1: Write the failing test** — extend the existing `TestExitReasonFromCode`:

```go
func TestExitReasonFromCodeDistinguishesOOMCancelInfra(t *testing.T) {
	cases := []struct{ code int; timedOut bool; want string }{
		{0,   false, "completed"},
		{2,   false, "gave_up"},
		{124, true,  "timeout"},
		{125, false, "infra_error"},
		{130, false, "cancelled"},
		{137, false, "oom_killed"},
		{1,   false, "crashed"},
	}
	for _, c := range cases {
		got := runner.ExitReasonFromCode(c.code, c.timedOut)
		if got != c.want {
			t.Errorf("ExitReasonFromCode(%d, %v) = %q, want %q", c.code, c.timedOut, got, c.want)
		}
	}
}
```

**Step 2: Run → expect FAIL**

**Step 3: Implement** — rewrite `ExitReasonFromCode`:

```go
func ExitReasonFromCode(code int, timedOut bool) string {
    if timedOut { return "timeout" }
    switch code {
    case 0:   return "completed"
    case 2:   return "gave_up"
    case 124: return "timeout"
    case 125: return "infra_error"
    case 130: return "cancelled"
    case 137: return "oom_killed"
    default:  return "crashed"
    }
}
```

Then update `DetectNoAgentContribution` to forgive `"cancelled"` and `"infra_error"` in addition to whatever it already forgives — those are host-caused, not agent-caused.

**Step 4 & 5:**

```bash
go test ./internal/runner/ -v
git add internal/runner/trial.go internal/runner/trial_test.go
git commit -m "fix(runner): distinguish oom_killed/cancelled/infra_error in ExitReasonFromCode"
```

---

# WAVE 4 — Docker & Gateway

## Task 15: `ContainerStop` grace period before `SIGKILL`

**Bug:** `internal/docker/runner.go:142-150` (`killAndDump`) calls `cli.ContainerKill(..., client.ContainerKillOptions{Signal: "SIGKILL"})` directly. The adapter has no chance to flush `.thunderdome-metrics.json` or write the trailing NDJSON line.

**Files:**
- Modify: `internal/docker/runner.go:142-150`
- Test: `internal/docker/runner_test.go` (verification via source check or integration smoke)

**Dependencies:** none

> SDK note: this repo uses `github.com/moby/moby/client` (verified: `go.mod` has `github.com/moby/moby/client v0.2.2`). The stop API is exposed as `client.ContainerStopOptions` (verify with `go doc github.com/moby/moby/client.Client.ContainerStop`).

**Step 1: Verify the stop API**

```bash
go doc github.com/moby/moby/client.Client.ContainerStop 2>/dev/null || \
  grep -rn "ContainerStop\|ContainerStopOptions" go.sum vendor/ 2>/dev/null | head
```

You should see something like `ContainerStop(ctx context.Context, containerID string, options ContainerStopOptions) error` with `ContainerStopOptions{Timeout *int}` or `{Signal string, Timeout *int}`.

**Step 2: Write the test (source-check style)**

```go
func TestKillAndDumpAttemptsGracefulStopFirst(t *testing.T) {
    src, err := os.ReadFile("runner.go")
    if err != nil { t.Fatal(err) }
    text := string(src)
    stopIdx := strings.Index(text, "ContainerStop")
    killIdx := strings.Index(text, "ContainerKill")
    if stopIdx < 0 {
        t.Errorf("runner.go must call ContainerStop for graceful shutdown")
    }
    if stopIdx > killIdx && killIdx > 0 {
        t.Errorf("ContainerStop should appear before ContainerKill in the kill-and-dump path")
    }
}
```

**Step 3: Implement** — in `killAndDump` (line 142). Note: `ContainerStop` returns `(ContainerStopResult, error)` per `go doc`; the SDK's `ContainerStopOptions{Signal, Timeout *int}` already escalates to SIGKILL after the timeout expires, so the explicit `ContainerKill` becomes belt-and-suspenders.

```go
killAndDump := func(label string) {
    // Try graceful stop first. ContainerStopOptions.Timeout is a pointer to seconds;
    // the SDK escalates to SIGKILL automatically after expiry, but we follow up with
    // ContainerKill below for paranoia.
    grace := 5
    if _, stopErr := cli.ContainerStop(context.Background(), containerID, client.ContainerStopOptions{Timeout: &grace}); stopErr != nil {
        fmt.Fprintf(os.Stderr, "container stop failed for %s (will SIGKILL): %v\n", label, stopErr)
    }
    cli.ContainerKill(context.Background(), containerID, client.ContainerKillOptions{Signal: "SIGKILL"})
    // existing log capture unchanged
    logReader, _ := cli.ContainerLogs(context.Background(), containerID, client.ContainerLogsOptions{ShowStdout: true, ShowStderr: true})
    if logReader != nil {
        logData, _ := io.ReadAll(logReader)
        logReader.Close()
        fmt.Fprintf(os.Stderr, "Container logs (%s):\n%s\n", label, string(logData))
    }
}
```

**Verified via `go doc github.com/moby/moby/client.ContainerStopOptions`:** the option struct has `Signal string` and `Timeout *int` (seconds; nil = engine default; -1 = no timeout; 0 = immediate kill).

**Step 4: Verify**

```bash
go test ./internal/docker/ -v
make smoke
```

Manual smoke: run a trial with a short timeout and confirm `.thunderdome-metrics.json` contains a complete final line.

**Step 5: Commit**

```bash
git add internal/docker/runner.go internal/docker/runner_test.go
git commit -m "fix(docker): graceful ContainerStop before SIGKILL to flush adapter metrics"
```

---

## Task 16: Gateway `Stop()` — graceful shutdown

**Bug:** `internal/gateway/gateway.go:146-155` calls `g.cmd.Process.Kill()` (SIGKILL) directly. `proxy.py` has no signal handler; in-flight `proxy-usage-*.jsonl` writes may be lost.

**Files:**
- Modify: `internal/gateway/gateway.go:146-155` (`Stop`)
- Modify: `internal/gateway/proxy.py` — add a SIGTERM handler
- Test: `internal/gateway/gateway_test.go`

**Dependencies:** none

**Step 1: Inspect `proxy.py`** to find the log fd variable name:

```bash
grep -n "open\|log" internal/gateway/proxy.py | head -20
```

**Step 2: Write the failing test** (source-check style, since spawning a real proxy in unit tests is heavy):

```go
func TestGatewayStopSignalsTerminateBeforeKill(t *testing.T) {
    src, err := os.ReadFile("gateway.go")
    if err != nil { t.Fatal(err) }
    text := string(src)
    sigTermIdx := strings.Index(text, "syscall.SIGTERM")
    killIdx := strings.Index(text, "Process.Kill")
    if sigTermIdx < 0 {
        t.Errorf("Stop should send SIGTERM before SIGKILL")
    }
    if sigTermIdx > killIdx && killIdx > 0 {
        t.Errorf("SIGTERM should precede Process.Kill")
    }
}
```

**Step 3: Implement**

1. **`internal/gateway/gateway.go:146`** — replace `Stop` with:
   ```go
   func (g *Gateway) Stop() error {
       if g.cmd == nil || g.cmd.Process == nil {
           if g.logFile != nil { g.logFile.Close() }
           return nil
       }
       // Graceful: SIGTERM, then wait up to 5s, then SIGKILL.
       _ = g.cmd.Process.Signal(syscall.SIGTERM)
       done := make(chan error, 1)
       go func() { done <- g.cmd.Wait() }()
       select {
       case <-done:
       case <-time.After(5 * time.Second):
           _ = g.cmd.Process.Kill()
           <-done
       }
       if g.logFile != nil {
           g.logFile.Close()
       }
       return nil
   }
   ```
   Add `"syscall"` to imports.

2. **`internal/gateway/proxy.py`** — at the top (after the existing imports):
   ```python
   import signal, sys
   def _on_sigterm(signum, frame):
       try:
           sys.stdout.flush()
           sys.stderr.flush()
           # Flush whatever the usage-log fd is — inspect the file to find the name.
           # If the proxy uses `log_fd`, flush it here.
       finally:
           sys.exit(0)
   signal.signal(signal.SIGTERM, _on_sigterm)
   ```
   Adjust the comment / fd name after inspecting `proxy.py` in Step 1.

**Step 4: Verify**

```bash
go test ./internal/gateway/ -v
```

For a meaningful integration test, optional manual smoke:
```bash
make build
./thunderdome run --orchestrator null --task T1 --trials 1
# Confirm proxy-usage-*.jsonl in run dir has no truncated lines.
```

**Step 5: Commit**

```bash
git add internal/gateway/gateway.go internal/gateway/proxy.py internal/gateway/gateway_test.go
git commit -m "fix(gateway): SIGTERM + wait before SIGKILL to flush proxy usage log"
```

---

## Task 17: Remove dead `BudgetUSD` / `SecretsEnvFile` from `StartOpts`

**Bug:** `gateway.StartOpts.BudgetUSD` and `SecretsEnvFile` are passed by `cmd/run.go:83-87` and accepted by `gateway.Start` but the proxy script is invoked with only `--port` and `--log`. Budget enforcement and secrets injection are not implemented.

**Files:**
- Modify: `internal/gateway/gateway.go:25-29` — remove the dead fields
- Modify: `cmd/run.go:83-87` — remove the (now invalid) field assignments
- Modify: `internal/gateway/gateway_test.go` (regression test)

**Dependencies:** Task 16 (gateway.go serial)

**Decision:** removal-only, no replacement. If budget enforcement is desired later it's a separate plan/feature.

**Step 1: Write the failing test**

```go
func TestStartOptsHasNoDeadFields(t *testing.T) {
    v := reflect.TypeOf(gateway.StartOpts{})
    for i := 0; i < v.NumField(); i++ {
        switch v.Field(i).Name {
        case "BudgetUSD", "SecretsEnvFile":
            t.Errorf("StartOpts still has dead field %s", v.Field(i).Name)
        }
    }
}
```

**Step 2: Run → expect FAIL** (both fields currently exist)

**Step 3: Implement**

1. **`internal/gateway/gateway.go:25-29`** — remove the two unused fields:
   ```go
   type StartOpts struct {
       LogDir string
   }
   ```

2. **`cmd/run.go:83-87`** — remove the assignments:
   ```go
   gw, err = gateway.Start(ctx, &gateway.StartOpts{
       LogDir: cfg.Proxy.LogDir,
   })
   ```

3. If `cfg.Proxy.BudgetPerTrialUSD > 0` in `thunderdome.yaml`, log a warning at startup so users aren't surprised:
   ```go
   if cfg.Proxy.BudgetPerTrialUSD > 0 {
       fmt.Fprintln(os.Stderr, "WARNING: budget_per_trial_usd is set but gateway budget enforcement is not implemented; ignoring")
   }
   ```

**Step 4: Verify**

```bash
go test ./... -count=1
```

**Step 5: Commit**

```bash
git add internal/gateway/gateway.go cmd/run.go internal/gateway/gateway_test.go
git commit -m "fix(gateway): remove dead StartOpts.BudgetUSD and SecretsEnvFile"
```

---

# WAVE 5 — Config & Adapter Scripts

## Task 18: Fail loud on unset secrets in `expandOrchEnv`

**Bug:** `cmd/run.go:294-305` uses `os.Expand` with a callback that returns empty string for unknown keys. A typo'd `${ANTHROPC_KEY}` becomes empty; the container starts; the trial fails late with an obscure auth error.

**Files:**
- Modify: `cmd/run.go:294-305` — change signature to return an error
- Modify: `cmd/run.go:63` — propagate the error
- Test: `cmd/run_test.go` (create if absent — note: `cmd` is a `package main`; tests live in `package main`)

**Dependencies:** none

**Step 1: Verify the test package layout**

```bash
ls cmd/*_test.go 2>/dev/null
head -3 cmd/list.go  # should show `package main`
```

If no test file exists, create `cmd/run_test.go` with `package main`.

**Step 2: Write the failing test**

```go
package main

import (
    "strings"
    "testing"

    "github.com/signalnine/thunderdome/internal/config"
)

func TestExpandOrchEnvErrorsOnMissingSecret(t *testing.T) {
    orchs := []config.Orchestrator{
        {Name: "x", Env: map[string]string{"API": "${MISSING_KEY_XYZ}"}},
    }
    err := expandOrchEnv(orchs, map[string]string{"PRESENT": "yes"})
    if err == nil {
        t.Fatal("expected error for missing secret, got nil")
    }
    if !strings.Contains(err.Error(), "MISSING_KEY_XYZ") {
        t.Errorf("error should name the missing key; got: %v", err)
    }
}
```

This requires the signature change.

**Step 3: Implement** — rewrite `expandOrchEnv` to return an error and propagate:

```go
func expandOrchEnv(orchs []config.Orchestrator, secrets map[string]string) error {
    var missing []string
    for i := range orchs {
        for k, v := range orchs[i].Env {
            orchs[i].Env[k] = os.Expand(v, func(key string) string {
                if val, ok := secrets[key]; ok {
                    return val
                }
                if val, ok := os.LookupEnv(key); ok {
                    return val
                }
                missing = append(missing, fmt.Sprintf("${%s} (in %s.env[%s])", key, orchs[i].Name, k))
                return ""
            })
        }
    }
    if len(missing) > 0 {
        return fmt.Errorf("missing secrets: %s", strings.Join(missing, ", "))
    }
    return nil
}
```

Update call site at `cmd/run.go:63`:
```go
if err := expandOrchEnv(cfg.Orchestrators, secrets); err != nil {
    return err
}
```

**Step 4 & 5:**

```bash
go test ./...
git add cmd/run.go cmd/run_test.go
git commit -m "fix(config): fail loudly when orchestrator env references unset secret"
```

---

## Task 19: Aider adapter cost regex — bash double-escape

**Bug:** `adapters/aider/adapter.sh:46` (verify exact line: `grep -n "Cost:" adapters/aider/adapter.sh`) embeds a Python regex inside a bash double-quoted `python3 -c "..."`. The `\\$` survives bash unescape as `\$`, which Python's regex reads as an end-of-string anchor — `total_cost_usd` is always `0.0`.

**Files:**
- Modify: `adapters/aider/adapter.sh` (the metrics-parsing block)
- Test: a small shell-level test under `adapters/aider/`

**Dependencies:** none

**Step 1: Verify and locate the current parser**

```bash
grep -n "python3\|Cost\|message,\|session" adapters/aider/adapter.sh
```

**Step 2: Write a verification script** — `adapters/aider/test_metrics_parse.sh`:

```bash
#!/bin/bash
set -euo pipefail
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

cat > "$tmp/aider-output.txt" <<'EOF'
> aider message about something
Tokens: 1,234 sent, 567 received.
Cost: $0.0123 message, $0.0456 session.
EOF

# Run the parser block from adapter.sh against the fixture (extract it into a
# standalone helper if necessary). Expected: metrics.json reports 0.0456 cost.
metrics="$tmp/metrics.json"
python3 <<'PYEOF' "$tmp/aider-output.txt" "$metrics"
import json, re, sys
with open(sys.argv[1]) as f:
    text = f.read()
cost_re = re.compile(r'Cost:\s*\$([\d.]+)\s*message,\s*\$([\d.]+)\s*session', re.MULTILINE)
tok_re  = re.compile(r'Tokens:\s*([\d,]+)\s*sent,\s*([\d,]+)\s*received', re.MULTILINE)
session_cost = 0.0
inp, outp = 0, 0
for m in cost_re.finditer(text):
    session_cost = float(m.group(2))
for m in tok_re.finditer(text):
    inp  += int(m.group(1).replace(',', ''))
    outp += int(m.group(2).replace(',', ''))
with open(sys.argv[2], 'w') as f:
    json.dump({"input_tokens": inp, "output_tokens": outp, "total_cost_usd": session_cost}, f)
PYEOF

got=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["total_cost_usd"])' "$metrics")
expected="0.0456"
if [[ "$got" != "$expected" ]]; then
    echo "FAIL: total_cost_usd = $got, expected $expected" >&2
    exit 1
fi
echo "PASS: cost parsed correctly"
```

`chmod +x adapters/aider/test_metrics_parse.sh`.

**Step 3: Verify current breakage** — run the test against an unmodified adapter.sh (extract its parser block first if needed); confirm it fails.

**Step 4: Implement** — in `adapters/aider/adapter.sh`, replace the broken `python3 -c "..."` block with a quoted heredoc:

```bash
python3 <<'PYEOF' "$OUTPUT_FILE" "/workspace/.thunderdome-metrics.json"
import json, re, sys
out_path, metrics_path = sys.argv[1], sys.argv[2]
with open(out_path) as f:
    text = f.read()
cost_re = re.compile(r'Cost:\s*\$([\d.]+)\s*message,\s*\$([\d.]+)\s*session', re.MULTILINE)
tok_re  = re.compile(r'Tokens:\s*([\d,]+)\s*sent,\s*([\d,]+)\s*received', re.MULTILINE)
session_cost = 0.0
inp, outp = 0, 0
for m in cost_re.finditer(text):
    session_cost = float(m.group(2))
for m in tok_re.finditer(text):
    inp  += int(m.group(1).replace(',', ''))
    outp += int(m.group(2).replace(',', ''))
with open(metrics_path, 'w') as f:
    json.dump({"input_tokens": inp, "output_tokens": outp, "total_cost_usd": session_cost}, f)
PYEOF
```

The `<<'PYEOF'` quoted heredoc prevents bash from touching `$` or `\`.

**Step 5: Verify and commit**

```bash
bash adapters/aider/test_metrics_parse.sh   # should PASS
git add adapters/aider/adapter.sh adapters/aider/test_metrics_parse.sh
git commit -m "fix(adapters/aider): use quoted heredoc so cost regex matches \$N.NN"
```

---

## Task 20: Codex adapter — guard `OPENAI_API_KEY`, check `PIPESTATUS`

**Bug:** `adapters/codex-gpt54/adapter.sh:16` (verify with `grep -n "printenv OPENAI" adapters/codex*/adapter.sh`) pipes the key through `codex login` then `tail -3` with `2>&1`. Missing key silently proceeds; stderr-merge could echo the key on parse error.

**Files:**
- Modify: `adapters/codex-gpt54/adapter.sh`
- Modify: `adapters/codex-gpt54-mini/adapter.sh`
- Search for siblings: `grep -rln "printenv OPENAI_API_KEY" adapters/`

**Dependencies:** none

**Step 1: Locate**

```bash
grep -rn "printenv OPENAI_API_KEY" adapters/
```

**Step 2: Verify failure** — run with unset key:

```bash
unset OPENAI_API_KEY
bash adapters/codex-gpt54/adapter.sh </dev/null 2>&1 | head -5
# Expected today: proceeds past the login pipe and fails later in codex exec.
```

**Step 3: Implement** — in each affected adapter, replace:

```bash
printenv OPENAI_API_KEY | codex login --with-api-key 2>&1 | tail -3
```
with:
```bash
: "${OPENAI_API_KEY:?OPENAI_API_KEY is required for this adapter}"
printenv OPENAI_API_KEY | codex login --with-api-key | tail -3
codex_status=${PIPESTATUS[1]}
if [[ $codex_status -ne 0 ]]; then
    echo "codex login failed (exit $codex_status)" >&2
    exit 2
fi
```

(`2>&1` removed — codex's stderr could echo the key on parse error.)

**Step 4: Verify**

```bash
unset OPENAI_API_KEY
bash adapters/codex-gpt54/adapter.sh </dev/null
# Expected: "OPENAI_API_KEY is required..." and exit 1.
```

**Step 5: Commit**

```bash
git add adapters/codex-gpt54/adapter.sh adapters/codex-gpt54-mini/adapter.sh
git commit -m "fix(adapters/codex): assert OPENAI_API_KEY and check PIPESTATUS"
```

---

## Task 21: `set -euo pipefail` + env guards in core adapters

**Bug:** Adapters use only `set -e`. A future harness regression that drops `TASK_DIR` would make `cd ""` a no-op (or `cd $HOME` depending on shell), and the agent writes to the wrong tree.

**Scope:** apply to the 4 most-used adapters only. A repo-wide sweep across all ~200 adapters is a separate cleanup (each adapter has its own quirks; bulk sed is risky). The 4 we touch are:
- `adapters/claude-code/adapter.sh`
- `adapters/aider/adapter.sh` (combine with T19's edit if convenient)
- `adapters/codex-gpt54/adapter.sh` (combine with T20)
- `adapters/conclave-v8-no-review-opus/adapter.sh`

**Files:** the 4 above.

**Dependencies:** T19 (aider), T20 (codex) — sequence or batch the edits.

**Step 1: Verify the failure** — for each adapter, run with `TASK_DIR` unset and confirm it proceeds further than it should.

**Step 2: Implement** — at the top of each adapter, replace `set -e` with:

```bash
#!/bin/bash
set -euo pipefail

: "${TASK_DIR:?TASK_DIR not set by harness}"
: "${TASK_DESCRIPTION:?TASK_DESCRIPTION not set by harness}"
```

For codex variants that use `PROXY_URL`, optionally also guard that — but most adapters check it with `if [ -n "$PROXY_URL" ]` already, which works under `set -u` only if the var is set OR you use `${PROXY_URL:-}`. Audit each adapter; replace any bare `$PROXY_URL` references with `${PROXY_URL:-}` to keep `set -u` happy.

**Step 3: Verify**

```bash
make smoke    # null adapter trial; ensures none of these are broken
unset TASK_DIR
bash adapters/claude-code/adapter.sh </dev/null   # expected: fast fail
```

**Step 4: Commit**

```bash
git add adapters/claude-code/adapter.sh adapters/aider/adapter.sh adapters/codex-gpt54/adapter.sh adapters/conclave-v8-no-review-opus/adapter.sh
git commit -m "fix(adapters): set -euo pipefail and assert required env vars"
```

---

# Final Verification

After all 21 commits land:

```bash
# 1. Full Go test suite
go test ./...

# 2. Build + smoke
make build && make smoke

# 3. End-to-end on a small set
./thunderdome run --orchestrator null --parallel 2 --trials 2 --task T1
./thunderdome report results/latest --format markdown

# 4. Ctrl-C cleanup verification
./thunderdome run --orchestrator null --task T1 --parallel 4 --trials 4 &
PID=$!; sleep 5; kill -INT $PID; wait $PID 2>/dev/null
docker ps -a --filter "label=thunderdome=true" --format "{{.ID}} {{.Status}}"
# Expected: no orphan containers.

# 5. Push
git pull --rebase
git push
```

---

# Risk Register

| Risk | Mitigation |
|---|---|
| Vitest regex anchor change might miss summary variants with leading non-space chars | `\s*` at start covers whitespace; verify against existing testrunner_test.go fixtures. |
| `signal.NotifyContext` refactor changes `runner.Job` and `RunPool` signatures — ripples to all callers | Search-first: `grep -rn "runner.RunPool\|runner.Job"` before starting. Expected callers: cmd/run.go, pool_test.go (3 tests). Update them all in the same commit. |
| Pricing fix (T9) changes published numbers retroactively for old runs | Expected and desirable. Re-run `./thunderdome report results/latest` after the fix. |
| Adapter `set -u` (T21) surfaces previously-tolerated unset-var bugs in odd corners | Roll out only to 4 named adapters. Run `make smoke` after each edit. If a smoke regression appears, revert the specific adapter or add `${VAR:-}` defaults. |
| Min-N gate (T10) hides orchestrators users want to see | Default writers still show unqualified rows with `Qualified: false`. Don't filter outright. |
| Adding `Category` to `TrialMeta` (T10) makes old `meta.json` files lack the field | Field is `omitempty` and a missing field unmarshals to `""`. Old rows would all be classified as standard. Acceptable — they're historical. |
| T15's `client.ContainerStopOptions` field name may not be `Timeout` exactly | Verify with `go doc github.com/moby/moby/client.Client.ContainerStop` before writing the call. |
| T16's proxy.py SIGTERM handler references a log fd that may not exist by that name | Inspect proxy.py first (Step 1 of T16); adjust the handler to match. |
| Atomic-write fix (T11) writes to a tmp file in the same dir — fails if dir is RO | Trial dirs are always writable (we create them). No-op concern. |

---

# Notes for the Executor

- **Test discipline**: Follow @conclave:test-driven-development. Write the test, watch it fail, implement, watch it pass.
- **Verification gate**: @conclave:verification-before-completion — run `go test ./...` before each commit. Stop and fix on red.
- **Commits**: one fix per commit, lowercase `fix(scope): …`, no trailing period. Match recent log (`git log --oneline -10`).
- **API verification**: before writing any test that calls a function, confirm the signature with `grep -n "^func" <file>` or `go doc`. This plan was rewritten after an audit found ~13 hallucinated APIs — don't repeat that pattern.
- **White-box tests**: Wave 2 tests live in `package report` (no `_test` suffix on the package name) because the functions they test (`aggregate`, `writeMarkdown`, `enrichCosts`, `writeJSON`) are unexported. Existing `internal/report/report_test.go` shows the convention.
- **Worktree**: optional — each task is small. If you want isolation use @conclave:using-git-worktrees.
- **Skip on infeasibility**: T15 and T16 use source-check style tests because mocking the Docker SDK and gateway process is heavy. If a fuller test is cheap, write it. Otherwise document manual verification in the commit body.
