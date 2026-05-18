package result

type TrialMeta struct {
	Orchestrator        string   `json:"orchestrator"`
	Task                string   `json:"task"`
	Trial               int      `json:"trial"`
	DurationS           int      `json:"duration_s"`
	WallClockMS         int64    `json:"wall_clock_ms"`
	ExitCode            int      `json:"exit_code"`
	ExitReason          string   `json:"exit_reason"`
	NoAgentContribution bool     `json:"no_agent_contribution,omitempty"`
	Greenfield          bool     `json:"greenfield,omitempty"`
	Scores              Scores   `json:"scores"`
	ValidationErrors    []string `json:"validation_errors,omitempty"`
	CompositeScore      float64  `json:"composite_score"`
	TotalTokens         int      `json:"total_tokens"`
	TotalCostUSD        float64  `json:"total_cost_usd"`
	Error               string   `json:"error,omitempty"`
	BudgetExceeded      bool     `json:"budget_exceeded"`
	Category            string   `json:"category,omitempty"`
}

type Scores struct {
	Tests          float64 `json:"tests"`
	StaticAnalysis float64 `json:"static_analysis"`
	HiddenTests    float64 `json:"hidden_tests,omitempty"`
	AgentTests     float64 `json:"agent_tests,omitempty"`
	Coverage       float64 `json:"coverage,omitempty"`
	CodeMetrics    float64 `json:"code_metrics,omitempty"`
	// CoverageMeasured is true when RunCoverage produced a numeric result.
	// When false (e.g. environmental failure to install @vitest/coverage-v8),
	// GreenfieldCompositeScore drops the coverage multiplier so the AgentTests
	// component isn't zeroed out by something the agent can't control.
	CoverageMeasured bool `json:"coverage_measured,omitempty"`
}
