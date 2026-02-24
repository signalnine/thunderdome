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
