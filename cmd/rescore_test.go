package cmd

import (
	"os"
	"path/filepath"
	"testing"

	"github.com/signalnine/thunderdome/internal/config"
	"github.com/signalnine/thunderdome/internal/result"
)

// Regression for agentic-thunderdome-ud8: rescoreFull's old workspace cleanup
// invoked 'sudo rm -rf' without -n, which can hang on a TTY when sudo prompts
// for a password. The cleanup must (a) succeed without sudo when files are
// owned by the running uid (the common case post-hostUID fix) and (b) never
// invoke sudo without -n.
func TestRemoveWorkspaceDirRemovesOwnedDir(t *testing.T) {
	trialDir := t.TempDir()
	wsDir := filepath.Join(trialDir, "workspace")
	if err := os.MkdirAll(filepath.Join(wsDir, "subdir"), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(wsDir, "subdir", "f.txt"), []byte("x"), 0o644); err != nil {
		t.Fatal(err)
	}

	if err := removeWorkspaceDir(wsDir); err != nil {
		t.Fatalf("removeWorkspaceDir: %v", err)
	}
	if _, err := os.Stat(wsDir); !os.IsNotExist(err) {
		t.Errorf("wsDir still exists after cleanup: stat err = %v", err)
	}
}

func TestRemoveWorkspaceDirNoOpOnMissing(t *testing.T) {
	trialDir := t.TempDir()
	wsDir := filepath.Join(trialDir, "workspace")
	if err := removeWorkspaceDir(wsDir); err != nil {
		t.Errorf("removeWorkspaceDir on missing dir should be no-op, got %v", err)
	}
}

func TestRemoveWorkspaceDirRefusesEmptyPath(t *testing.T) {
	if err := removeWorkspaceDir(""); err == nil {
		t.Error("removeWorkspaceDir(\"\") should refuse, got nil error")
	}
}

// Regression: validateGreenfield sets meta.Greenfield=true for greenfield
// trials (commit fc63c47b), but the rescore command did not, so a meta.json
// written before the Greenfield flag existed kept Greenfield=false after a
// rescore. The report aggregator then excluded fully-failed greenfield trials
// (all greenfield scores zero) from the greenfield averages via its fallback
// heuristic, biasing the means upward by silently dropping the worst trials.
//
// applyTaskMetaUpdates is the seam rescore uses to keep meta in sync with the
// task config: re-running validation on an older trial must update the flag
// to whatever the task says it should be, not leave a stale value behind.
func TestApplyTaskMetaUpdates(t *testing.T) {
	tests := []struct {
		name      string
		startMeta result.TrialMeta
		task      config.Task
		want      bool
	}{
		{
			name:      "backfills greenfield flag onto pre-flag meta",
			startMeta: result.TrialMeta{Greenfield: false},
			task:      config.Task{Greenfield: true},
			want:      true,
		},
		{
			name:      "leaves non-greenfield meta alone",
			startMeta: result.TrialMeta{Greenfield: false},
			task:      config.Task{Greenfield: false},
			want:      false,
		},
		{
			name:      "corrects mistakenly-set flag when task is non-greenfield",
			startMeta: result.TrialMeta{Greenfield: true},
			task:      config.Task{Greenfield: false},
			want:      false,
		},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			meta := tt.startMeta
			applyTaskMetaUpdates(&meta, &tt.task)
			if meta.Greenfield != tt.want {
				t.Errorf("Greenfield = %v, want %v", meta.Greenfield, tt.want)
			}
		})
	}
}
