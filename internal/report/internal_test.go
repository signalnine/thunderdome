package report

import (
	"testing"

	"github.com/signalnine/thunderdome/internal/result"
)

func absf(x float64) float64 {
	if x < 0 {
		return -x
	}
	return x
}

// TestPassRateFilteredExcludesCrashes verifies that PassRateFiltered is the
// ratio of completed-and-contributing trials over only the trials where the
// agent contributed (i.e. NoAgentContribution=false). A crashed trial flagged
// as no-contribution must not enter either numerator or denominator.
func TestPassRateFilteredExcludesCrashes(t *testing.T) {
	metas := []*result.TrialMeta{
		{Orchestrator: "x", ExitReason: "completed", CompositeScore: 1.0, NoAgentContribution: false},
		{Orchestrator: "x", ExitReason: "crashed", CompositeScore: 0.0, NoAgentContribution: true},
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
