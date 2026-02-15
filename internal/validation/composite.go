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

var DefaultGreenWeights = config.GreenWeights{
	Rubric:      0.35,
	HiddenTests: 0.25,
	AgentTests:  0.20,
	BuildLint:   0.10,
	CodeMetrics: 0.10,
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

// GreenfieldCompositeScore computes a weighted score for greenfield tasks.
// Components: rubric (35%), hidden behavioral tests (25%), agent test quality (20%),
// build+lint (10%), code metrics (10%).
func GreenfieldCompositeScore(scores result.Scores, gw config.GreenWeights) float64 {
	if gw.Rubric == 0 && gw.HiddenTests == 0 && gw.AgentTests == 0 && gw.BuildLint == 0 && gw.CodeMetrics == 0 {
		gw = DefaultGreenWeights
	}
	total := gw.Rubric + gw.HiddenTests + gw.AgentTests + gw.BuildLint + gw.CodeMetrics
	if total == 0 {
		return 0
	}

	// AgentTests score = agent test pass rate × coverage
	// If agent wrote no tests, agentTestScore = 0
	agentTestScore := scores.AgentTests * scores.Coverage

	// BuildLint = average of build success (from StaticAnalysis) — we reuse Tests for build
	// Actually: build success is binary (pass/fail) and lint is a score.
	// For greenfield, Tests holds agent test pass rate, StaticAnalysis holds lint score.
	// We combine build (1.0 if builds, 0 if not) with lint.
	buildLintScore := scores.StaticAnalysis // lint score; build pass is implicit if tests ran

	return (scores.Rubric*gw.Rubric +
		scores.HiddenTests*gw.HiddenTests +
		agentTestScore*gw.AgentTests +
		buildLintScore*gw.BuildLint +
		scores.CodeMetrics*gw.CodeMetrics) / total
}
