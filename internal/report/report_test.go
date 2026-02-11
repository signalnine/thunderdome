package report_test

import (
	"bytes"
	"path/filepath"
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
