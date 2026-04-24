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
// on the whole JSON, otherwise a single zero-total metric collapses the
// entire coverage score to 0 even when lines/statements coverage is fine.
func TestParseCoverageSummaryHandlesUnknownPct(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "coverage-summary.json")
	body := `{
  "total": {
    "lines":      {"total": 100, "covered": 80, "skipped": 0, "pct": 80},
    "statements": {"total": 100, "covered": 80, "skipped": 0, "pct": 80},
    "functions":  {"total": 10,  "covered": 9,  "skipped": 0, "pct": 90},
    "branches":   {"total": 0,   "covered": 0,  "skipped": 0, "pct": "Unknown"}
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
	if res.Branches != 0 {
		t.Errorf("Branches = %f, want 0 (Unknown -> 0)", res.Branches)
	}
	// score = (lines + branches) / 200 = (80 + 0) / 200 = 0.4
	if res.Score < 0.39 || res.Score > 0.41 {
		t.Errorf("Score = %f, want ~0.4", res.Score)
	}
}
