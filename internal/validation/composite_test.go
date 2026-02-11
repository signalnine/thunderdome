package validation_test

import (
	"testing"

	"github.com/signalnine/thunderdome/internal/config"
	"github.com/signalnine/thunderdome/internal/result"
	"github.com/signalnine/thunderdome/internal/validation"
)

func TestCompositeScore(t *testing.T) {
	scores := result.Scores{Tests: 0.9, StaticAnalysis: 0.8, Rubric: 0.7}
	weights := config.ValidationWeights{Tests: 0.5, StaticAnalysis: 0.2, Rubric: 0.3}
	got := validation.CompositeScore(scores, weights)
	if absf(got-0.82) > 0.001 {
		t.Errorf("got %f, want 0.82", got)
	}
}

func TestCompositeScoreDefaultWeights(t *testing.T) {
	scores := result.Scores{Tests: 1.0, StaticAnalysis: 1.0, Rubric: 1.0}
	weights := config.ValidationWeights{}
	got := validation.CompositeScore(scores, weights)
	if absf(got-1.0) > 0.001 {
		t.Errorf("got %f, want 1.0", got)
	}
}
