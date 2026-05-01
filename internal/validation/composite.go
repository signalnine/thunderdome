package validation

import (
	"math"

	"github.com/signalnine/thunderdome/internal/config"
	"github.com/signalnine/thunderdome/internal/result"
)

// safeScore clamps NaN/Inf to 0 and >1 to 1. Returning NaN/Inf would later
// fail json.Marshal and silently lose the trial's meta.json.
func safeScore(x float64) float64 {
	if math.IsNaN(x) || math.IsInf(x, 0) {
		return 0
	}
	if x < 0 {
		return 0
	}
	if x > 1 {
		return 1
	}
	return x
}

var DefaultWeights = config.ValidationWeights{
	Tests:          0.7,
	StaticAnalysis: 0.3,
}

var DefaultGreenWeights = config.GreenWeights{
	HiddenTests: 0.385,
	AgentTests:  0.308,
	BuildLint:   0.154,
	CodeMetrics: 0.154,
}

func CompositeScore(scores result.Scores, weights config.ValidationWeights) float64 {
	if weights.Tests == 0 && weights.StaticAnalysis == 0 {
		weights = DefaultWeights
	}
	total := weights.Tests + weights.StaticAnalysis
	if total == 0 {
		return 0
	}
	return safeScore((scores.Tests*weights.Tests +
		scores.StaticAnalysis*weights.StaticAnalysis) / total)
}

// GreenfieldCompositeScore computes a weighted score for greenfield tasks.
// Components: hidden behavioral tests (38.5%), agent test quality (30.8%),
// build+lint (15.4%), code metrics (15.4%).
func GreenfieldCompositeScore(scores result.Scores, gw config.GreenWeights) float64 {
	if gw.HiddenTests == 0 && gw.AgentTests == 0 && gw.BuildLint == 0 && gw.CodeMetrics == 0 {
		gw = DefaultGreenWeights
	}
	total := gw.HiddenTests + gw.AgentTests + gw.BuildLint + gw.CodeMetrics
	if total == 0 {
		return 0
	}

	// AgentTests score = agent test pass rate × coverage.
	// If agent wrote no tests, agentTestScore = 0.
	// If coverage couldn't be measured (e.g. @vitest/coverage-v8 install
	// failed for environmental reasons), drop the multiplier — otherwise an
	// infrastructure failure would zero out 30.8% of the greenfield composite
	// even when the agent's tests passed cleanly.
	agentTestScore := scores.AgentTests * scores.Coverage
	if !scores.CoverageMeasured {
		agentTestScore = scores.AgentTests
	}

	// BuildLint = average of build success (from StaticAnalysis) — we reuse Tests for build
	// Actually: build success is binary (pass/fail) and lint is a score.
	// For greenfield, Tests holds agent test pass rate, StaticAnalysis holds lint score.
	// We combine build (1.0 if builds, 0 if not) with lint.
	buildLintScore := scores.StaticAnalysis // lint score; build pass is implicit if tests ran

	return safeScore((scores.HiddenTests*gw.HiddenTests +
		agentTestScore*gw.AgentTests +
		buildLintScore*gw.BuildLint +
		scores.CodeMetrics*gw.CodeMetrics) / total)
}
