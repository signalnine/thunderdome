package analyze

import (
	"encoding/json"
	"os"
	"path/filepath"
	"testing"
)

func TestDiscoverTrials(t *testing.T) {
	// Build a minimal trial directory structure
	dir := t.TempDir()
	trialDir := filepath.Join(dir, "runs", "2026-01-01T00-00-00", "trials", "test-orch", "test-task", "trial-1")
	wsDir := filepath.Join(trialDir, "workspace")
	os.MkdirAll(wsDir, 0755)

	meta := map[string]interface{}{
		"orchestrator":    "test-orch",
		"task":            "test-task",
		"trial":           1,
		"composite_score": 0.85,
		"exit_reason":     "completed",
		"duration_s":      120,
		"total_cost_usd":  2.50,
	}
	metaBytes, _ := json.Marshal(meta)
	os.WriteFile(filepath.Join(trialDir, "meta.json"), metaBytes, 0644)

	// Write a minimal NDJSON trace
	ndjson := `{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Write","input":{"file_path":"/workspace/src/__tests__/foo.test.ts","content":"x"}}]}}
{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Write","input":{"file_path":"/workspace/src/foo.ts","content":"x"}}]}}
{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Bash","input":{"command":"npm test"}}]}}
{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Bash","input":{"command":"git commit -m 'feat'"}}]}}
{"type":"result","num_turns":4,"duration_ms":60000,"total_cost_usd":2.50}
`
	os.WriteFile(filepath.Join(wsDir, ".thunderdome-output.jsonl"), []byte(ndjson), 0644)

	results, err := DiscoverTrials(filepath.Join(dir, "runs"))
	if err != nil {
		t.Fatal(err)
	}
	if len(results) != 1 {
		t.Fatalf("expected 1 trial, got %d", len(results))
	}

	r := results[0]
	if r.Orchestrator != "test-orch" {
		t.Errorf("Orchestrator = %q", r.Orchestrator)
	}
	if r.Task != "test-task" {
		t.Errorf("Task = %q", r.Task)
	}
	if r.Score != 0.85 {
		t.Errorf("Score = %f", r.Score)
	}
	if !r.Behaviors.HasTrace {
		t.Error("expected HasTrace = true")
	}
	if !r.Behaviors.TDDCompliance {
		t.Error("expected TDDCompliance = true")
	}
	if !r.Behaviors.VerificationBeforeCommit {
		t.Error("expected VerificationBeforeCommit = true")
	}
}

func TestDiscoverTrials_NoNDJSON(t *testing.T) {
	dir := t.TempDir()
	trialDir := filepath.Join(dir, "runs", "2026-01-01T00-00-00", "trials", "test-orch", "test-task", "trial-1")
	os.MkdirAll(trialDir, 0755)

	meta := map[string]interface{}{
		"orchestrator":    "test-orch",
		"task":            "test-task",
		"trial":           1,
		"composite_score": 0.70,
		"exit_reason":     "completed",
	}
	metaBytes, _ := json.Marshal(meta)
	os.WriteFile(filepath.Join(trialDir, "meta.json"), metaBytes, 0644)

	results, err := DiscoverTrials(filepath.Join(dir, "runs"))
	if err != nil {
		t.Fatal(err)
	}
	if len(results) != 1 {
		t.Fatalf("expected 1 trial, got %d", len(results))
	}
	if results[0].Behaviors.HasTrace {
		t.Error("expected HasTrace = false")
	}
}

func TestDiscoverTrials_MultipleRuns(t *testing.T) {
	dir := t.TempDir()

	// Create two runs with one trial each
	for _, ts := range []string{"2026-01-01T00-00-00", "2026-01-02T00-00-00"} {
		trialDir := filepath.Join(dir, "runs", ts, "trials", "orch-a", "task-x", "trial-1")
		os.MkdirAll(trialDir, 0755)
		meta := map[string]interface{}{
			"orchestrator":    "orch-a",
			"task":            "task-x",
			"trial":           1,
			"composite_score": 0.75,
		}
		metaBytes, _ := json.Marshal(meta)
		os.WriteFile(filepath.Join(trialDir, "meta.json"), metaBytes, 0644)
	}

	results, err := DiscoverTrials(filepath.Join(dir, "runs"))
	if err != nil {
		t.Fatal(err)
	}
	if len(results) != 2 {
		t.Fatalf("expected 2 trials, got %d", len(results))
	}
}
