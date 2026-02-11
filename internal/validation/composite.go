package validation

import (
	"github.com/signalnine/thunderdome/internal/config"
	"github.com/signalnine/thunderdome/internal/result"
)

var DefaultWeights = config.ValidationWeights{
	Tests:          0.5,
	StaticAnalysis: 0.2,
	Rubric:         0.3,
}

func CompositeScore(scores result.Scores, weights config.ValidationWeights) float64 {
	if weights.Tests == 0 && weights.StaticAnalysis == 0 && weights.Rubric == 0 {
		weights = DefaultWeights
	}
	total := weights.Tests + weights.StaticAnalysis + weights.Rubric
	if total == 0 {
		return 0
	}
	return (scores.Tests*weights.Tests +
		scores.StaticAnalysis*weights.StaticAnalysis +
		scores.Rubric*weights.Rubric) / total
}
