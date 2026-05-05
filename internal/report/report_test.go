package report_test

import (
	"bytes"
	"encoding/json"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/signalnine/thunderdome/internal/report"
	"github.com/signalnine/thunderdome/internal/result"
)

func TestGenerateTable(t *testing.T) {
	base := t.TempDir()
	runDir := filepath.Join(base, "runs", "test-run")

	metas := []*result.TrialMeta{
		{Orchestrator: "orch-a", Task: "task-1", Trial: 1, CompositeScore: 0.9, TotalTokens: 1000, TotalCostUSD: 0.5, ExitReason: "completed"},
		{Orchestrator: "orch-a", Task: "task-1", Trial: 2, CompositeScore: 0.8, TotalTokens: 1200, TotalCostUSD: 0.6, ExitReason: "completed"},
		{Orchestrator: "orch-b", Task: "task-1", Trial: 1, CompositeScore: 0.7, TotalTokens: 2000, TotalCostUSD: 1.0, ExitReason: "completed"},
		{Orchestrator: "orch-b", Task: "task-1", Trial: 2, CompositeScore: 0.6, TotalTokens: 2200, TotalCostUSD: 1.1, ExitReason: "crashed"},
	}

	for _, m := range metas {
		dir := result.TrialDir(runDir, m.Orchestrator, m.Task, m.Trial)
		result.WriteTrialMeta(dir, m)
	}

	var buf bytes.Buffer
	err := report.Generate(runDir, "table", &buf)
	if err != nil {
		t.Fatalf("Generate: %v", err)
	}
	output := buf.String()
	if output == "" {
		t.Error("expected non-empty output")
	}
	if !bytes.Contains([]byte(output), []byte("orch-a")) {
		t.Error("expected orch-a in output")
	}
	if !bytes.Contains([]byte(output), []byte("orch-b")) {
		t.Error("expected orch-b in output")
	}
}

func TestGreenfieldMeansNotDilutedByNonGreenfield(t *testing.T) {
	base := t.TempDir()
	runDir := filepath.Join(base, "runs", "test-run")

	// Mixed orchestrator: 2 greenfield trials (HiddenTests=0.8, AgentTests=0.6,
	// Coverage=0.5, CodeMetrics=0.4) and 2 non-greenfield trials (all zero
	// greenfield fields). The greenfield means must be the average over the
	// 2 greenfield trials, not the 4 total trials.
	metas := []*result.TrialMeta{
		{
			Orchestrator: "mixed-orch", Task: "green-1", Trial: 1,
			CompositeScore: 0.7, ExitReason: "completed",
			Scores: result.Scores{HiddenTests: 0.8, AgentTests: 0.6, Coverage: 0.5, CodeMetrics: 0.4},
		},
		{
			Orchestrator: "mixed-orch", Task: "green-1", Trial: 2,
			CompositeScore: 0.7, ExitReason: "completed",
			Scores: result.Scores{HiddenTests: 0.8, AgentTests: 0.6, Coverage: 0.5, CodeMetrics: 0.4},
		},
		{
			Orchestrator: "mixed-orch", Task: "std-1", Trial: 1,
			CompositeScore: 0.9, ExitReason: "completed",
			Scores: result.Scores{Tests: 0.9, StaticAnalysis: 0.8},
		},
		{
			Orchestrator: "mixed-orch", Task: "std-1", Trial: 2,
			CompositeScore: 0.9, ExitReason: "completed",
			Scores: result.Scores{Tests: 0.9, StaticAnalysis: 0.8},
		},
	}

	for _, m := range metas {
		dir := result.TrialDir(runDir, m.Orchestrator, m.Task, m.Trial)
		if err := result.WriteTrialMeta(dir, m); err != nil {
			t.Fatal(err)
		}
	}

	var buf bytes.Buffer
	if err := report.Generate(runDir, "json", &buf); err != nil {
		t.Fatalf("Generate: %v", err)
	}

	var got []report.OrchestratorSummary
	if err := json.Unmarshal(buf.Bytes(), &got); err != nil {
		t.Fatalf("unmarshal: %v", err)
	}
	if len(got) != 1 {
		t.Fatalf("expected 1 summary, got %d", len(got))
	}
	s := got[0]
	if !s.HasGreenfield {
		t.Fatal("expected HasGreenfield=true")
	}

	const eps = 1e-9
	checks := []struct {
		name string
		got  float64
		want float64
	}{
		{"MeanHiddenTests", s.MeanHiddenTests, 0.8},
		{"MeanAgentTests", s.MeanAgentTests, 0.6},
		{"MeanCoverage", s.MeanCoverage, 0.5},
		{"MeanCodeMetrics", s.MeanCodeMetrics, 0.4},
	}
	for _, c := range checks {
		if c.got < c.want-eps || c.got > c.want+eps {
			t.Errorf("%s: got %f, want %f (means must be averaged over greenfield trials only, not diluted by non-greenfield trials)", c.name, c.got, c.want)
		}
	}
}

// Regression: a greenfield trial that fails on every greenfield component
// (HiddenTests=0, AgentTests=0, CodeMetrics=0, Coverage=0) is indistinguishable
// from a non-greenfield trial under the old "any score > 0" heuristic, so it
// was excluded from greenCount and the greenfield means were biased upward by
// dropping the worst trials. With an explicit Greenfield flag on TrialMeta,
// failed greenfield trials must still contribute zeros to the greenfield means.
func TestGreenfieldMeansIncludeFailedTrials(t *testing.T) {
	base := t.TempDir()
	runDir := filepath.Join(base, "runs", "test-run")

	// Two greenfield trials: one fully passing, one fully failed (all zeros).
	// Mean should be the average over both -- 0.4 for HiddenTests, etc. -- not
	// 0.8 (the passing trial alone, with the failed one silently excluded).
	metas := []*result.TrialMeta{
		{
			Orchestrator: "fail-orch", Task: "green-1", Trial: 1,
			CompositeScore: 0.7, ExitReason: "completed", Greenfield: true,
			Scores: result.Scores{HiddenTests: 0.8, AgentTests: 0.6, Coverage: 0.5, CodeMetrics: 0.4},
		},
		{
			Orchestrator: "fail-orch", Task: "green-1", Trial: 2,
			CompositeScore: 0.0, ExitReason: "crashed", Greenfield: true,
			Scores: result.Scores{HiddenTests: 0, AgentTests: 0, Coverage: 0, CodeMetrics: 0},
		},
	}

	for _, m := range metas {
		dir := result.TrialDir(runDir, m.Orchestrator, m.Task, m.Trial)
		if err := result.WriteTrialMeta(dir, m); err != nil {
			t.Fatal(err)
		}
	}

	var buf bytes.Buffer
	if err := report.Generate(runDir, "json", &buf); err != nil {
		t.Fatalf("Generate: %v", err)
	}

	var got []report.OrchestratorSummary
	if err := json.Unmarshal(buf.Bytes(), &got); err != nil {
		t.Fatalf("unmarshal: %v", err)
	}
	if len(got) != 1 {
		t.Fatalf("expected 1 summary, got %d", len(got))
	}
	s := got[0]
	if !s.HasGreenfield {
		t.Fatal("expected HasGreenfield=true")
	}

	const eps = 1e-9
	checks := []struct {
		name string
		got  float64
		want float64
	}{
		{"MeanHiddenTests", s.MeanHiddenTests, 0.4},
		{"MeanAgentTests", s.MeanAgentTests, 0.3},
		{"MeanCoverage", s.MeanCoverage, 0.25},
		{"MeanCodeMetrics", s.MeanCodeMetrics, 0.2},
	}
	for _, c := range checks {
		if c.got < c.want-eps || c.got > c.want+eps {
			t.Errorf("%s: got %f, want %f (failed greenfield trials must be averaged in, not silently excluded)", c.name, c.got, c.want)
		}
	}
}

func TestMarkdownGreenfieldBreakdown(t *testing.T) {
	base := t.TempDir()
	runDir := filepath.Join(base, "runs", "test-run")

	metas := []*result.TrialMeta{
		{
			Orchestrator: "green-orch", Task: "green-1", Trial: 1,
			CompositeScore: 0.7, ExitReason: "completed", Greenfield: true,
			Scores: result.Scores{HiddenTests: 0.8, AgentTests: 0.6, Coverage: 0.5, CodeMetrics: 0.4},
		},
		{
			Orchestrator: "green-orch", Task: "green-1", Trial: 2,
			CompositeScore: 0.7, ExitReason: "completed", Greenfield: true,
			Scores: result.Scores{HiddenTests: 0.8, AgentTests: 0.6, Coverage: 0.5, CodeMetrics: 0.4},
		},
	}

	for _, m := range metas {
		dir := result.TrialDir(runDir, m.Orchestrator, m.Task, m.Trial)
		if err := result.WriteTrialMeta(dir, m); err != nil {
			t.Fatal(err)
		}
	}

	var buf bytes.Buffer
	if err := report.Generate(runDir, "markdown", &buf); err != nil {
		t.Fatalf("Generate: %v", err)
	}
	output := buf.String()

	if !strings.Contains(output, "Greenfield Breakdown") {
		t.Errorf("expected 'Greenfield Breakdown' header in markdown output, got:\n%s", output)
	}
	for _, col := range []string{"Hidden Tests", "Agent Tests", "Coverage", "Code Metrics"} {
		if !strings.Contains(output, col) {
			t.Errorf("expected column %q in markdown greenfield section, got:\n%s", col, output)
		}
	}
	for _, val := range []string{"0.800", "0.600", "0.500", "0.400"} {
		if !strings.Contains(output, val) {
			t.Errorf("expected value %q in markdown greenfield section, got:\n%s", val, output)
		}
	}
}

func TestMarkdownOmitsGreenfieldWhenAbsent(t *testing.T) {
	base := t.TempDir()
	runDir := filepath.Join(base, "runs", "test-run")

	metas := []*result.TrialMeta{
		{Orchestrator: "std-orch", Task: "task-1", Trial: 1, CompositeScore: 0.9, ExitReason: "completed"},
	}
	for _, m := range metas {
		dir := result.TrialDir(runDir, m.Orchestrator, m.Task, m.Trial)
		if err := result.WriteTrialMeta(dir, m); err != nil {
			t.Fatal(err)
		}
	}

	var buf bytes.Buffer
	if err := report.Generate(runDir, "markdown", &buf); err != nil {
		t.Fatalf("Generate: %v", err)
	}
	if strings.Contains(buf.String(), "Greenfield Breakdown") {
		t.Errorf("did not expect greenfield section when no summary has greenfield results, got:\n%s", buf.String())
	}
}

func TestNoContributionReport(t *testing.T) {
	base := t.TempDir()
	runDir := filepath.Join(base, "runs", "test-run")

	metas := []*result.TrialMeta{
		{Orchestrator: "good-orch", Task: "task-1", Trial: 1, CompositeScore: 0.9, TotalTokens: 5000, ExitReason: "completed"},
		{Orchestrator: "good-orch", Task: "task-1", Trial: 2, CompositeScore: 0.8, TotalTokens: 4000, ExitReason: "completed"},
		{Orchestrator: "crashy-orch", Task: "task-1", Trial: 1, CompositeScore: 0.75, TotalTokens: 0, ExitReason: "crashed", DurationS: 2, NoAgentContribution: true},
		{Orchestrator: "crashy-orch", Task: "task-1", Trial: 2, CompositeScore: 0.6, TotalTokens: 3000, ExitReason: "completed"},
	}

	for _, m := range metas {
		dir := result.TrialDir(runDir, m.Orchestrator, m.Task, m.Trial)
		result.WriteTrialMeta(dir, m)
	}

	var buf bytes.Buffer
	err := report.Generate(runDir, "table", &buf)
	if err != nil {
		t.Fatalf("Generate: %v", err)
	}
	output := buf.String()

	// Should show the no-contribution section
	if !strings.Contains(output, "NO-CONTRIBUTION") {
		t.Error("expected NO-CONTRIBUTION section in output")
	}
	if !strings.Contains(output, "crashy-orch") {
		t.Error("expected crashy-orch in no-contribution section")
	}
	// good-orch should NOT appear in no-contribution section
	// (it appears in the main table but not the flagged section)

	// JSON format should include the fields
	var jsonBuf bytes.Buffer
	err = report.Generate(runDir, "json", &jsonBuf)
	if err != nil {
		t.Fatalf("Generate JSON: %v", err)
	}
	if !strings.Contains(jsonBuf.String(), "no_contribution_trials") {
		t.Error("expected no_contribution_trials in JSON output")
	}
	if !strings.Contains(jsonBuf.String(), "mean_score_filtered") {
		t.Error("expected mean_score_filtered in JSON output")
	}
}

// Regression: enrichCosts unconditionally overwrote m.TotalCostUSD with the
// proxy-log-derived cost, including when the proxy log was present but
// contained zero parseable records (a common state when the agent bypassed
// PROXY_URL but the proxy still wrote startup noise to its log file).
// This silently zeroed adapter-recorded costs that came from
// .thunderdome-metrics.json. enrichCosts must preserve the adapter-recorded
// value when the proxy log yields no records.
func TestGenerateDoesNotZeroAdapterCostOnEmptyProxyLog(t *testing.T) {
	base := t.TempDir()
	runDir := filepath.Join(base, "runs", "test-run")
	pricingPath := filepath.Join(base, "pricing.yaml")
	if err := os.WriteFile(pricingPath, []byte("anthropic:\n  claude-sonnet-4-5: { input: 0.003, output: 0.015, cache_write: 0.00375, cache_read: 0.0003 }\n"), 0o644); err != nil {
		t.Fatal(err)
	}

	meta := &result.TrialMeta{
		Orchestrator:   "adapter-only",
		Task:           "task-1",
		Trial:          1,
		CompositeScore: 0.9,
		TotalTokens:    5000,
		TotalCostUSD:   1.23,
		ExitReason:     "completed",
	}
	dir := result.TrialDir(runDir, meta.Orchestrator, meta.Task, meta.Trial)
	if err := result.WriteTrialMeta(dir, meta); err != nil {
		t.Fatalf("WriteTrialMeta: %v", err)
	}
	// Empty proxy log file -- present but no records (agent bypassed proxy).
	logPath := filepath.Join(dir, "proxy-log.jsonl")
	if err := os.WriteFile(logPath, []byte{}, 0o644); err != nil {
		t.Fatalf("write empty proxy log: %v", err)
	}

	var buf bytes.Buffer
	if err := report.Generate(runDir, "json", &buf, pricingPath); err != nil {
		t.Fatalf("Generate: %v", err)
	}

	var parsed []struct {
		Name        string  `json:"name"`
		MeanCostUSD float64 `json:"mean_cost_usd"`
	}
	if err := json.Unmarshal(buf.Bytes(), &parsed); err != nil {
		t.Fatalf("unmarshal: %v\noutput: %s", err, buf.String())
	}
	if len(parsed) != 1 {
		t.Fatalf("got %d orchestrators, want 1", len(parsed))
	}
	if got := parsed[0].MeanCostUSD; got != 1.23 {
		t.Errorf("MeanCostUSD = %v, want 1.23 (adapter cost should not be zeroed by empty proxy log)", got)
	}
}
