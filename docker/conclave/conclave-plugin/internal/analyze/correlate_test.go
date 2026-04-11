package analyze

import (
	"math"
	"testing"
)

func TestPearson(t *testing.T) {
	// Perfect positive correlation
	x := []float64{1, 2, 3, 4, 5}
	y := []float64{2, 4, 6, 8, 10}
	r := pearson(x, y)
	if math.Abs(r-1.0) > 0.001 {
		t.Errorf("perfect positive: r = %f, want 1.0", r)
	}

	// Perfect negative correlation
	x = []float64{1, 2, 3, 4, 5}
	y = []float64{10, 8, 6, 4, 2}
	r = pearson(x, y)
	if math.Abs(r-(-1.0)) > 0.001 {
		t.Errorf("perfect negative: r = %f, want -1.0", r)
	}

	// No correlation
	x = []float64{1, 2, 3, 4, 5}
	y = []float64{5, 3, 1, 4, 2}
	r = pearson(x, y)
	if math.Abs(r) > 0.5 {
		t.Errorf("weak/no correlation: r = %f, want near 0", r)
	}

	// Too few points
	r = pearson([]float64{1}, []float64{2})
	if r != 0 {
		t.Errorf("single point: r = %f, want 0", r)
	}

	// Constant values (zero variance)
	r = pearson([]float64{3, 3, 3}, []float64{1, 2, 3})
	if r != 0 {
		t.Errorf("constant x: r = %f, want 0", r)
	}
}

func TestCorrelate(t *testing.T) {
	trials := []TrialAnalysis{
		{Score: 0.90, Behaviors: &BehaviorProfile{HasTrace: true, TDDCompliance: true, TestRunCount: 5, FixCycles: 3}},
		{Score: 0.85, Behaviors: &BehaviorProfile{HasTrace: true, TDDCompliance: true, TestRunCount: 4, FixCycles: 2}},
		{Score: 0.50, Behaviors: &BehaviorProfile{HasTrace: true, TDDCompliance: false, TestRunCount: 1, FixCycles: 0}},
		{Score: 0.45, Behaviors: &BehaviorProfile{HasTrace: true, TDDCompliance: false, TestRunCount: 1, FixCycles: 0}},
		{Score: 0.70, Behaviors: &BehaviorProfile{HasTrace: false}}, // no trace, should be excluded
	}

	report := Correlate(trials)
	if len(report.Signals) == 0 {
		t.Fatal("expected signals in report")
	}

	// TDD should correlate positively with score in this dataset
	tdd := findSignal(report, "tdd_compliance")
	if tdd == nil {
		t.Fatal("tdd_compliance not in report")
	}
	if tdd.Correlation <= 0 {
		t.Errorf("tdd_compliance correlation = %f, want positive", tdd.Correlation)
	}
	if report.TracedTrials != 4 {
		t.Errorf("TracedTrials = %d, want 4", report.TracedTrials)
	}
	if report.TotalTrials != 5 {
		t.Errorf("TotalTrials = %d, want 5", report.TotalTrials)
	}
}

func TestCorrelate_TooFewTrials(t *testing.T) {
	trials := []TrialAnalysis{
		{Score: 0.90, Behaviors: &BehaviorProfile{HasTrace: true}},
		{Score: 0.50, Behaviors: &BehaviorProfile{HasTrace: true}},
	}
	report := Correlate(trials)
	if len(report.Signals) != 0 {
		t.Errorf("expected 0 signals with too few trials, got %d", len(report.Signals))
	}
}

func TestCorrelate_SortedByAbsCorrelation(t *testing.T) {
	trials := []TrialAnalysis{
		{Score: 0.90, Behaviors: &BehaviorProfile{HasTrace: true, TDDCompliance: true, TestRunCount: 10, CommitCount: 1}},
		{Score: 0.85, Behaviors: &BehaviorProfile{HasTrace: true, TDDCompliance: true, TestRunCount: 8, CommitCount: 2}},
		{Score: 0.40, Behaviors: &BehaviorProfile{HasTrace: true, TDDCompliance: false, TestRunCount: 1, CommitCount: 3}},
		{Score: 0.35, Behaviors: &BehaviorProfile{HasTrace: true, TDDCompliance: false, TestRunCount: 0, CommitCount: 4}},
	}

	report := Correlate(trials)
	// Verify sorted by absolute correlation descending
	for i := 1; i < len(report.Signals); i++ {
		if math.Abs(report.Signals[i].Correlation) > math.Abs(report.Signals[i-1].Correlation) {
			t.Errorf("signals not sorted: [%d] |%f| > [%d] |%f|",
				i, report.Signals[i].Correlation, i-1, report.Signals[i-1].Correlation)
		}
	}
}

func findSignal(r *CorrelationReport, name string) *SignalCorrelation {
	for i := range r.Signals {
		if r.Signals[i].Name == name {
			return &r.Signals[i]
		}
	}
	return nil
}
