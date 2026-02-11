package validation_test

import (
	"testing"

	"github.com/signalnine/thunderdome/internal/config"
	"github.com/signalnine/thunderdome/internal/validation"
)

func TestComputeRubricScore(t *testing.T) {
	rubric := []config.RubricCriterion{
		{Criterion: "Follows patterns", Weight: 2},
		{Criterion: "Minimal diff", Weight: 1},
		{Criterion: "Edge cases", Weight: 3},
	}
	scores := map[string]float64{
		"Follows patterns": 0.8,
		"Minimal diff":     1.0,
		"Edge cases":       0.6,
	}
	got := validation.ComputeRubricScore(rubric, scores)
	want := 4.4 / 6.0
	if absf(got-want) > 0.001 {
		t.Errorf("got %f, want %f", got, want)
	}
}

func TestComputeRubricScoreEmpty(t *testing.T) {
	got := validation.ComputeRubricScore(nil, nil)
	if got != 0.0 {
		t.Errorf("got %f, want 0.0", got)
	}
}

func TestMedianScore(t *testing.T) {
	tests := []struct {
		scores []float64
		want   float64
	}{
		{[]float64{0.5, 0.7, 0.6}, 0.6},
		{[]float64{0.8, 0.8, 0.9}, 0.8},
		{[]float64{1.0}, 1.0},
	}
	for _, tt := range tests {
		got := validation.MedianScore(tt.scores)
		if absf(got-tt.want) > 0.001 {
			t.Errorf("MedianScore(%v) = %f, want %f", tt.scores, got, tt.want)
		}
	}
}
