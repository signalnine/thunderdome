package report_test

import (
	"bytes"
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
