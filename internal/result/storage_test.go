package result_test

import (
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"sync"
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

// Regression guard: WriteTrialMeta must use a tmp+rename pattern so that
// crashes/SIGKILL mid-write don't leave a zero-length meta.json. We can't
// inject a crash from a unit test, so we use two proxies: (1) no
// meta.json.tmp* file leaks after a successful write, and (2) under
// concurrent writers, the final meta.json still parses.
func TestWriteTrialMetaIsAtomic(t *testing.T) {
	dir := t.TempDir()
	meta := &result.TrialMeta{Orchestrator: "x", Task: "T1", CompositeScore: 0.5}
	if err := result.WriteTrialMeta(dir, meta); err != nil {
		t.Fatal(err)
	}
	matches, _ := filepath.Glob(filepath.Join(dir, "meta.json.tmp*"))
	if len(matches) > 0 {
		t.Errorf("tmp files leaked after atomic write: %v", matches)
	}
	got, err := result.ReadTrialMeta(filepath.Join(dir, "meta.json"))
	if err != nil {
		t.Fatalf("ReadTrialMeta failed after atomic write: %v", err)
	}
	if got.Task != "T1" {
		t.Errorf("Task = %q, want T1", got.Task)
	}
}

func TestWriteTrialMetaConcurrentSafe(t *testing.T) {
	dir := t.TempDir()
	var wg sync.WaitGroup
	for i := 0; i < 10; i++ {
		wg.Add(1)
		go func(n int) {
			defer wg.Done()
			meta := &result.TrialMeta{Task: fmt.Sprintf("T%d", n)}
			if err := result.WriteTrialMeta(dir, meta); err != nil {
				t.Errorf("concurrent write: %v", err)
			}
		}(i)
	}
	wg.Wait()
	// No tmp files should remain.
	tmps, _ := filepath.Glob(filepath.Join(dir, "meta.json.tmp*"))
	if len(tmps) != 0 {
		t.Errorf("leaked tmp files: %v", tmps)
	}
	// meta.json must parse to a valid TrialMeta.
	got, err := result.ReadTrialMeta(filepath.Join(dir, "meta.json"))
	if err != nil {
		t.Fatalf("final meta.json unreadable: %v", err)
	}
	if !strings.HasPrefix(got.Task, "T") {
		t.Errorf("Task = %q, expected T-prefixed", got.Task)
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
