package validation_test

import (
	"testing"

	"github.com/signalnine/thunderdome/internal/config"
	"github.com/signalnine/thunderdome/internal/result"
	"github.com/signalnine/thunderdome/internal/validation"
)

func TestCompositeScore(t *testing.T) {
	scores := result.Scores{Tests: 0.9, StaticAnalysis: 0.8}
	weights := config.ValidationWeights{Tests: 0.7, StaticAnalysis: 0.3}
	got := validation.CompositeScore(scores, weights)
	// (0.9*0.7 + 0.8*0.3) / 1.0 = 0.63 + 0.24 = 0.87
	if absf(got-0.87) > 0.001 {
		t.Errorf("got %f, want 0.87", got)
	}
}

func TestCompositeScoreDefaultWeights(t *testing.T) {
	scores := result.Scores{Tests: 1.0, StaticAnalysis: 1.0}
	weights := config.ValidationWeights{}
	got := validation.CompositeScore(scores, weights)
	if absf(got-1.0) > 0.001 {
		t.Errorf("got %f, want 1.0", got)
	}
}

// When coverage measurement fails for environmental reasons (e.g.
// @vitest/coverage-v8 install fails), the AgentTests component should
// fall back to the raw test pass rate instead of being multiplied by 0.
func TestGreenfieldCompositeScoreCoverageUnmeasured(t *testing.T) {
	scores := result.Scores{
		HiddenTests:      1.0,
		AgentTests:       1.0,
		Coverage:         0.0,
		CodeMetrics:      1.0,
		StaticAnalysis:   1.0,
		CoverageMeasured: false,
	}
	got := validation.GreenfieldCompositeScore(scores, validation.DefaultGreenWeights)
	// All components 1.0 -> composite should be 1.0 when we don't penalize
	// for unmeasured coverage.
	if absf(got-1.0) > 0.001 {
		t.Errorf("unmeasured coverage: got %f, want 1.0", got)
	}
}

// When coverage was measured at 0 (agent wrote no tests, or tests cover
// nothing), the multiplicative penalty must still apply.
func TestGreenfieldCompositeScoreCoverageMeasuredZero(t *testing.T) {
	scores := result.Scores{
		HiddenTests:      1.0,
		AgentTests:       1.0,
		Coverage:         0.0,
		CodeMetrics:      1.0,
		StaticAnalysis:   1.0,
		CoverageMeasured: true,
	}
	got := validation.GreenfieldCompositeScore(scores, validation.DefaultGreenWeights)
	// AgentTests*Coverage = 0, so the AgentTests component (weight 0.308)
	// drops out of the weighted sum: (1.0*0.385 + 0*0.308 + 1.0*0.154 +
	// 1.0*0.154) / 1.001 ≈ 0.692.
	want := (1.0*0.385 + 0.0*0.308 + 1.0*0.154 + 1.0*0.154) / (0.385 + 0.308 + 0.154 + 0.154)
	if absf(got-want) > 0.001 {
		t.Errorf("measured zero coverage: got %f, want %f", got, want)
	}
}

// Regression: with coverage measured at 1.0 and all components passing,
// composite should be 1.0.
func TestGreenfieldCompositeScoreFullPass(t *testing.T) {
	scores := result.Scores{
		HiddenTests:      1.0,
		AgentTests:       1.0,
		Coverage:         1.0,
		CodeMetrics:      1.0,
		StaticAnalysis:   1.0,
		CoverageMeasured: true,
	}
	got := validation.GreenfieldCompositeScore(scores, validation.DefaultGreenWeights)
	if absf(got-1.0) > 0.001 {
		t.Errorf("full pass: got %f, want 1.0", got)
	}
}
