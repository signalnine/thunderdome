package analyze

import (
	"bytes"
	"encoding/csv"
	"encoding/json"
	"strings"
	"testing"
)

func TestFormatCorrelationTable(t *testing.T) {
	report := &CorrelationReport{
		TracedTrials: 100,
		TotalTrials:  200,
		Signals: []SignalCorrelation{
			{Name: "tdd_compliance", Correlation: 0.42, MeanWhenOn: 0.85, MeanWhenOff: 0.60, CountOn: 60, CountOff: 40},
			{Name: "fix_cycles", Correlation: 0.31, MeanWhenOn: 0.80, MeanWhenOff: 0.65, CountOn: 50, CountOff: 50},
		},
	}

	var buf bytes.Buffer
	FormatCorrelationTable(&buf, report)
	output := buf.String()

	if !strings.Contains(output, "tdd_compliance") {
		t.Error("missing tdd_compliance in output")
	}
	if !strings.Contains(output, "0.42") {
		t.Error("missing correlation value")
	}
	if !strings.Contains(output, "100") {
		t.Error("missing traced trial count")
	}
	if !strings.Contains(output, "fix_cycles") {
		t.Error("missing fix_cycles in output")
	}
}

func TestFormatCSV(t *testing.T) {
	trials := []TrialAnalysis{
		{
			Orchestrator: "test-orch",
			Task:         "test-task",
			Trial:        1,
			Score:        0.85,
			Behaviors:    &BehaviorProfile{HasTrace: true, TDDCompliance: true, TestRunCount: 3},
		},
	}

	var buf bytes.Buffer
	FormatCSV(&buf, trials)

	r := csv.NewReader(&buf)
	records, err := r.ReadAll()
	if err != nil {
		t.Fatal(err)
	}
	if len(records) != 2 { // header + 1 row
		t.Fatalf("expected 2 rows, got %d", len(records))
	}
	if records[0][0] != "orchestrator" {
		t.Errorf("first header = %q, want orchestrator", records[0][0])
	}
	// Verify data row
	if records[1][0] != "test-orch" {
		t.Errorf("orchestrator = %q, want test-orch", records[1][0])
	}
}

func TestFormatCSV_MultipleTrials(t *testing.T) {
	trials := []TrialAnalysis{
		{Orchestrator: "a", Task: "t1", Trial: 1, Score: 0.9, Behaviors: &BehaviorProfile{HasTrace: true}},
		{Orchestrator: "b", Task: "t2", Trial: 2, Score: 0.5, Behaviors: &BehaviorProfile{HasTrace: false}},
	}

	var buf bytes.Buffer
	FormatCSV(&buf, trials)

	r := csv.NewReader(&buf)
	records, err := r.ReadAll()
	if err != nil {
		t.Fatal(err)
	}
	if len(records) != 3 { // header + 2 rows
		t.Fatalf("expected 3 rows, got %d", len(records))
	}
}

func TestFormatTrialJSON(t *testing.T) {
	ta := &TrialAnalysis{
		Orchestrator: "test-orch",
		Task:         "test-task",
		Trial:        1,
		Score:        0.85,
		Behaviors:    &BehaviorProfile{HasTrace: true, TDDCompliance: true},
	}

	var buf bytes.Buffer
	FormatTrialJSON(&buf, ta)

	var result map[string]interface{}
	if err := json.Unmarshal(buf.Bytes(), &result); err != nil {
		t.Fatal(err)
	}
	if result["orchestrator"] != "test-orch" {
		t.Errorf("orchestrator = %v", result["orchestrator"])
	}
	behaviors := result["behaviors"].(map[string]interface{})
	if behaviors["tdd_compliance"] != true {
		t.Errorf("tdd_compliance = %v", behaviors["tdd_compliance"])
	}
}
