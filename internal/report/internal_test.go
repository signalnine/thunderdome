package report

import (
	"bytes"
	"strings"
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

// TestMeanScoreFilteredEmittedWhenLegitimateZero verifies that a legitimate
// 0.0 filtered mean is emitted in JSON. With `omitempty` on float64, a true 0
// is indistinguishable from "no filtered trials" — using *float64 (nil when
// no filtered trials, &0 when zero) lets consumers tell the two apart.
func TestMeanScoreFilteredEmittedWhenLegitimateZero(t *testing.T) {
	metas := []*result.TrialMeta{
		{Orchestrator: "x", ExitReason: "completed", CompositeScore: 0.0, NoAgentContribution: false},
	}
	summaries := aggregate(metas)
	var buf bytes.Buffer
	if err := writeJSON(summaries, &buf); err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(buf.String(), `"mean_score_filtered"`) {
		t.Errorf("JSON output omits mean_score_filtered when value is 0:\n%s", buf.String())
	}
}

// TestWriteMarkdownEscapesPipeInName verifies that orchestrator names
// containing a `|` are escaped so they don't corrupt the markdown table.
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
		t.Errorf("expected \\| escape; got:\n%s", out)
	}
}
