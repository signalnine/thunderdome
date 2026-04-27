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
		Scores:         result.Scores{Tests: 0.9, StaticAnalysis: 0.8},
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

// Regression: CreateRunDir formatted the run timestamp at second precision
// and unconditionally overwrote results/latest. Two runs started in the
// same wall-clock second collided into the same dir; the latest symlink
// also raced.
func TestCreateRunDirSameSecondProducesDistinctDirs(t *testing.T) {
	base := t.TempDir()
	a, err := result.CreateRunDir(base)
	if err != nil {
		t.Fatalf("CreateRunDir #1: %v", err)
	}
	b, err := result.CreateRunDir(base)
	if err != nil {
		t.Fatalf("CreateRunDir #2: %v", err)
	}
	if a == b {
		t.Fatalf("two CreateRunDir calls produced the same dir: %s", a)
	}
	if _, err := os.Stat(a); err != nil {
		t.Errorf("first run dir missing: %v", err)
	}
	if _, err := os.Stat(b); err != nil {
		t.Errorf("second run dir missing: %v", err)
	}
	// latest must point to the most recent (b)
	target, err := os.Readlink(filepath.Join(base, "latest"))
	if err != nil {
		t.Fatalf("readlink latest: %v", err)
	}
	if target != b {
		t.Errorf("latest = %q, want %q", target, b)
	}
}

// If results/latest is a real directory (not a symlink) - say a user
// accidentally created it - CreateRunDir must surface a clear error
// instead of silently failing on Symlink with EEXIST.
func TestCreateRunDirRejectsLatestRealDirectory(t *testing.T) {
	base := t.TempDir()
	if err := os.MkdirAll(filepath.Join(base, "latest"), 0o755); err != nil {
		t.Fatal(err)
	}
	_, err := result.CreateRunDir(base)
	if err == nil {
		t.Fatal("CreateRunDir succeeded with real-directory latest, want error")
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
