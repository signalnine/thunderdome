package result_test

import (
	"os"
	"path/filepath"
	"testing"

	"github.com/signalnine/thunderdome/internal/result"
)

func TestWriteAndReadTrialMeta(t *testing.T) {
	dir := t.TempDir()
	meta := &result.TrialMeta{
		Orchestrator:   "test-orch",
		Task:           "test-task",
		Trial:          1,
		DurationS:      42,
		ExitCode:       0,
		ExitReason:     "completed",
		Scores:         result.Scores{Tests: 0.9, StaticAnalysis: 0.8, Rubric: 0.7},
		CompositeScore: 0.85,
		TotalTokens:    1000,
		TotalCostUSD:   0.50,
		BudgetExceeded: false,
	}
	if err := result.WriteTrialMeta(dir, meta); err != nil {
		t.Fatalf("WriteTrialMeta: %v", err)
	}
	got, err := result.ReadTrialMeta(filepath.Join(dir, "meta.json"))
	if err != nil {
		t.Fatalf("ReadTrialMeta: %v", err)
	}
	if got.Orchestrator != meta.Orchestrator {
		t.Errorf("orchestrator: got %q, want %q", got.Orchestrator, meta.Orchestrator)
	}
	if got.CompositeScore != meta.CompositeScore {
		t.Errorf("composite_score: got %f, want %f", got.CompositeScore, meta.CompositeScore)
	}
}

func TestCreateRunDir(t *testing.T) {
	base := t.TempDir()
	runDir, err := result.CreateRunDir(base)
	if err != nil {
		t.Fatalf("CreateRunDir: %v", err)
	}
	if _, err := os.Stat(runDir); os.IsNotExist(err) {
		t.Errorf("run directory not created: %s", runDir)
	}
	latest := filepath.Join(base, "latest")
	target, err := os.Readlink(latest)
	if err != nil {
		t.Fatalf("reading latest symlink: %v", err)
	}
	if target != runDir {
		t.Errorf("latest symlink: got %q, want %q", target, runDir)
	}
}

func TestTrialDir(t *testing.T) {
	base := t.TempDir()
	dir := result.TrialDir(base, "my-orch", "my-task", 3)
	expected := filepath.Join(base, "trials", "my-orch", "my-task", "trial-3")
	if dir != expected {
		t.Errorf("got %q, want %q", dir, expected)
	}
}
