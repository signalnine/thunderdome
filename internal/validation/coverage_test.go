package validation_test

import (
	"os"
	"path/filepath"
	"testing"

	"github.com/signalnine/thunderdome/internal/validation"
)

// Istanbul (and v8 via istanbul-lib-coverage) emits the literal string
// "Unknown" for any pct field whose total is zero -- e.g. a project with no
// branches at all. The parser must treat that as 0 instead of erroring out
// on the whole JSON. Additionally, a metric with total==0 means "not
// applicable" -- it must be excluded from the score average rather than
// dragging the score down by being counted as 0%.
func TestParseCoverageSummaryHandlesUnknownPct(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "coverage-summary.json")
	body := `{
  "total": {
    "lines":      {"total": 100, "covered": 80, "skipped": 0, "pct": 80},
    "statements": {"total": 100, "covered": 80, "skipped": 0, "pct": 80},
    "functions":  {"total": 10,  "covered": 9,  "skipped": 0, "pct": 90},
    "branches":   {"total": 50,  "covered": 30, "skipped": 0, "pct": 60}
  }
}`
	if err := os.WriteFile(path, []byte(body), 0o644); err != nil {
		t.Fatal(err)
	}

	res, err := validation.ParseCoverageSummaryForTest(path, "")
	if err != nil {
		t.Fatalf("parseCoverageSummary: %v", err)
	}
	if res.Lines != 80 {
		t.Errorf("Lines = %f, want 80", res.Lines)
	}
	if res.Branches != 60 {
		t.Errorf("Branches = %f, want 60", res.Branches)
	}
	// Both metrics applicable -> score = (lines + branches) / 200 = 0.7
	if res.Score < 0.69 || res.Score > 0.71 {
		t.Errorf("Score = %f, want ~0.7", res.Score)
	}
}

// When branches.total == 0 the metric is not applicable to this project
// (no branching code). The score must be computed from lines alone rather
// than averaging in a 0% branch coverage that doesn't reflect the agent's
// work.
func TestParseCoverageSummaryNoBranchesScoresOnLinesOnly(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "coverage-summary.json")
	body := `{
  "total": {
    "lines":      {"total": 100, "covered": 100, "skipped": 0, "pct": 100},
    "statements": {"total": 100, "covered": 100, "skipped": 0, "pct": 100},
    "functions":  {"total": 10,  "covered": 10,  "skipped": 0, "pct": 100},
    "branches":   {"total": 0,   "covered": 0,   "skipped": 0, "pct": "Unknown"}
  }
}`
	if err := os.WriteFile(path, []byte(body), 0o644); err != nil {
		t.Fatal(err)
	}

	res, err := validation.ParseCoverageSummaryForTest(path, "")
	if err != nil {
		t.Fatalf("parseCoverageSummary: %v", err)
	}
	if res.Lines != 100 {
		t.Errorf("Lines = %f, want 100", res.Lines)
	}
	if res.Branches != 0 {
		t.Errorf("Branches = %f, want 0 (Unknown -> 0)", res.Branches)
	}
	// branches.total == 0 -> excluded; score = lines/100 = 1.0
	if res.Score < 0.99 || res.Score > 1.01 {
		t.Errorf("Score = %f, want ~1.0 (branches excluded)", res.Score)
	}
}

// If neither lines nor branches have any total (degenerate empty project)
// the score is 0 -- no applicable metrics to score on.
func TestParseCoverageSummaryNoApplicableMetricsScoresZero(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "coverage-summary.json")
	body := `{
  "total": {
    "lines":      {"total": 0, "covered": 0, "skipped": 0, "pct": "Unknown"},
    "statements": {"total": 0, "covered": 0, "skipped": 0, "pct": "Unknown"},
    "functions":  {"total": 0, "covered": 0, "skipped": 0, "pct": "Unknown"},
    "branches":   {"total": 0, "covered": 0, "skipped": 0, "pct": "Unknown"}
  }
}`
	if err := os.WriteFile(path, []byte(body), 0o644); err != nil {
		t.Fatal(err)
	}

	res, err := validation.ParseCoverageSummaryForTest(path, "")
	if err != nil {
		t.Fatalf("parseCoverageSummary: %v", err)
	}
	if res.Score != 0 {
		t.Errorf("Score = %f, want 0 (no applicable metrics)", res.Score)
	}
}
