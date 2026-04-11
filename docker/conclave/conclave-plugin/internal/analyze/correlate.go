package analyze

import (
	"math"
	"sort"
)

// SignalCorrelation holds the Pearson r for one behavioral signal vs score.
type SignalCorrelation struct {
	Name        string  // Signal name (e.g., "tdd_compliance")
	Correlation float64 // Pearson r (-1 to 1)
	MeanWhenOn  float64 // Mean score when signal is true/high (for booleans: true)
	MeanWhenOff float64 // Mean score when signal is false/low
	CountOn     int     // Number of trials where signal is true/high
	CountOff    int     // Number of trials where signal is false/low
}

// CorrelationReport holds correlation data for all signals.
type CorrelationReport struct {
	Signals      []SignalCorrelation
	TracedTrials int // Number of trials with behavioral traces
	TotalTrials  int // Total trials including those without traces
}

// Correlate computes correlations between behavioral signals and composite scores.
func Correlate(trials []TrialAnalysis) *CorrelationReport {
	// Filter to trials with traces
	var traced []TrialAnalysis
	for _, t := range trials {
		if t.Behaviors != nil && t.Behaviors.HasTrace {
			traced = append(traced, t)
		}
	}

	report := &CorrelationReport{
		TracedTrials: len(traced),
		TotalTrials:  len(trials),
	}

	if len(traced) < 3 {
		return report
	}

	scores := make([]float64, len(traced))
	for i, t := range traced {
		scores[i] = t.Score
	}

	// Boolean signals
	boolSignals := []struct {
		name string
		fn   func(*BehaviorProfile) bool
	}{
		{"tdd_compliance", func(p *BehaviorProfile) bool { return p.TDDCompliance }},
		{"verification_before_commit", func(p *BehaviorProfile) bool { return p.VerificationBeforeCommit }},
		{"final_verification", func(p *BehaviorProfile) bool { return p.FinalVerification }},
		{"build_check", func(p *BehaviorProfile) bool { return p.BuildCheck }},
		{"lint_check", func(p *BehaviorProfile) bool { return p.LintCheck }},
		{"diff_review", func(p *BehaviorProfile) bool { return p.DiffReview }},
	}

	for _, sig := range boolSignals {
		values := make([]float64, len(traced))
		var onScores, offScores []float64
		for i, t := range traced {
			if sig.fn(t.Behaviors) {
				values[i] = 1
				onScores = append(onScores, t.Score)
			} else {
				values[i] = 0
				offScores = append(offScores, t.Score)
			}
		}
		report.Signals = append(report.Signals, SignalCorrelation{
			Name:        sig.name,
			Correlation: pearson(values, scores),
			MeanWhenOn:  mean(onScores),
			MeanWhenOff: mean(offScores),
			CountOn:     len(onScores),
			CountOff:    len(offScores),
		})
	}

	// Numeric signals
	numSignals := []struct {
		name string
		fn   func(*BehaviorProfile) float64
	}{
		{"test_first_ratio", func(p *BehaviorProfile) float64 { return p.TestFirstRatio }},
		{"commit_count", func(p *BehaviorProfile) float64 { return float64(p.CommitCount) }},
		{"test_run_count", func(p *BehaviorProfile) float64 { return float64(p.TestRunCount) }},
		{"fix_cycles", func(p *BehaviorProfile) float64 { return float64(p.FixCycles) }},
	}

	for _, sig := range numSignals {
		values := make([]float64, len(traced))
		for i, t := range traced {
			values[i] = sig.fn(t.Behaviors)
		}
		// For mean-when-on/off, split at median
		median := medianVal(values)
		var highScores, lowScores []float64
		for i, v := range values {
			if v >= median {
				highScores = append(highScores, traced[i].Score)
			} else {
				lowScores = append(lowScores, traced[i].Score)
			}
		}
		report.Signals = append(report.Signals, SignalCorrelation{
			Name:        sig.name,
			Correlation: pearson(values, scores),
			MeanWhenOn:  mean(highScores),
			MeanWhenOff: mean(lowScores),
			CountOn:     len(highScores),
			CountOff:    len(lowScores),
		})
	}

	// Sort by absolute correlation descending
	sort.Slice(report.Signals, func(i, j int) bool {
		return math.Abs(report.Signals[i].Correlation) > math.Abs(report.Signals[j].Correlation)
	})

	return report
}

func pearson(x, y []float64) float64 {
	n := len(x)
	if n < 2 || n != len(y) {
		return 0
	}
	mx := mean(x)
	my := mean(y)

	var num, dx2, dy2 float64
	for i := 0; i < n; i++ {
		dx := x[i] - mx
		dy := y[i] - my
		num += dx * dy
		dx2 += dx * dx
		dy2 += dy * dy
	}
	denom := math.Sqrt(dx2 * dy2)
	if denom == 0 {
		return 0
	}
	return num / denom
}

func mean(vals []float64) float64 {
	if len(vals) == 0 {
		return 0
	}
	sum := 0.0
	for _, v := range vals {
		sum += v
	}
	return sum / float64(len(vals))
}

func medianVal(vals []float64) float64 {
	if len(vals) == 0 {
		return 0
	}
	sorted := make([]float64, len(vals))
	copy(sorted, vals)
	sort.Float64s(sorted)
	mid := len(sorted) / 2
	if len(sorted)%2 == 0 {
		return (sorted[mid-1] + sorted[mid]) / 2
	}
	return sorted[mid]
}
