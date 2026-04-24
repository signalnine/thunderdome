package cmd

import (
	"testing"

	"github.com/signalnine/thunderdome/internal/config"
	"github.com/signalnine/thunderdome/internal/result"
)

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
