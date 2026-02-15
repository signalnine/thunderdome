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

func TestParseJudgeResponseCleanJSON(t *testing.T) {
	scores, err := validation.ParseJudgeResponse(`{"Correct": 0.9, "Clean": 0.8}`)
	if err != nil {
		t.Fatal(err)
	}
	if absf(scores["Correct"]-0.9) > 0.001 {
		t.Errorf("Correct: got %f, want 0.9", scores["Correct"])
	}
}

func TestParseJudgeResponseMarkdownFences(t *testing.T) {
	input := "```json\n{\"Correct\": 0.9, \"Clean\": 0.8}\n```"
	scores, err := validation.ParseJudgeResponse(input)
	if err != nil {
		t.Fatal(err)
	}
	if absf(scores["Clean"]-0.8) > 0.001 {
		t.Errorf("Clean: got %f, want 0.8", scores["Clean"])
	}
}

func TestParseJudgeResponsePreamble(t *testing.T) {
	input := "Okay, here are the scores:\n\n{\"Correct\": 0.7, \"Clean\": 0.6}\n\nLet me know if you need more details."
	scores, err := validation.ParseJudgeResponse(input)
	if err != nil {
		t.Fatal(err)
	}
	if absf(scores["Correct"]-0.7) > 0.001 {
		t.Errorf("Correct: got %f, want 0.7", scores["Correct"])
	}
}

func TestParseJudgeResponseFencesWithPreamble(t *testing.T) {
	input := "Here are my scores:\n```json\n{\"Correct\": 0.85}\n```\nHope that helps!"
	scores, err := validation.ParseJudgeResponse(input)
	if err != nil {
		t.Fatal(err)
	}
	if absf(scores["Correct"]-0.85) > 0.001 {
		t.Errorf("Correct: got %f, want 0.85", scores["Correct"])
	}
}

func TestParseJudgeResponseNoJSON(t *testing.T) {
	_, err := validation.ParseJudgeResponse("I cannot evaluate this code.")
	if err == nil {
		t.Error("expected error for response with no JSON")
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
