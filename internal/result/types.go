package result

type TrialMeta struct {
	Orchestrator   string  `json:"orchestrator"`
	Task           string  `json:"task"`
	Trial          int     `json:"trial"`
	DurationS      int     `json:"duration_s"`
	ExitCode       int     `json:"exit_code"`
	ExitReason     string  `json:"exit_reason"`
	Scores         Scores  `json:"scores"`
	CompositeScore float64 `json:"composite_score"`
	TotalTokens    int     `json:"total_tokens"`
	TotalCostUSD   float64 `json:"total_cost_usd"`
	BudgetExceeded bool    `json:"budget_exceeded"`
}

type Scores struct {
	Tests          float64 `json:"tests"`
	StaticAnalysis float64 `json:"static_analysis"`
	Rubric         float64 `json:"rubric"`
	HiddenTests    float64 `json:"hidden_tests,omitempty"`
	AgentTests     float64 `json:"agent_tests,omitempty"`
	Coverage       float64 `json:"coverage,omitempty"`
	CodeMetrics    float64 `json:"code_metrics,omitempty"`
}
