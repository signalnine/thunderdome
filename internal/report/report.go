package report

import (
	"encoding/json"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"sort"
	"strings"
	"text/tabwriter"

	"github.com/signalnine/thunderdome/internal/gateway"
	"github.com/signalnine/thunderdome/internal/pricing"
	"github.com/signalnine/thunderdome/internal/result"
)

type OrchestratorSummary struct {
	Name            string  `json:"name"`
	Trials          int     `json:"trials"`
	PassRate        float64 `json:"pass_rate"`
	MeanScore       float64 `json:"mean_score"`
	MeanTokens      float64 `json:"mean_tokens"`
	MeanCostUSD     float64 `json:"mean_cost_usd"`
	HasGreenfield   bool    `json:"has_greenfield,omitempty"`
	MeanHiddenTests float64 `json:"mean_hidden_tests,omitempty"`
	MeanAgentTests  float64 `json:"mean_agent_tests,omitempty"`
	MeanCoverage    float64 `json:"mean_coverage,omitempty"`
	MeanCodeMetrics float64 `json:"mean_code_metrics,omitempty"`
	MeanRubric      float64 `json:"mean_rubric,omitempty"`
}

// Generate reads trial results and produces a summary report.
func Generate(runDir, format string, w io.Writer, pricingPath ...string) error {
	metas, err := collectMetas(runDir)
	if err != nil {
		return err
	}

	if len(pricingPath) > 0 && pricingPath[0] != "" {
		enrichCosts(runDir, metas, pricingPath[0])
	}

	summaries := aggregate(metas)

	switch format {
	case "markdown":
		return writeMarkdown(summaries, w)
	case "json":
		return writeJSON(summaries, w)
	default:
		return writeTable(summaries, w)
	}
}

func collectMetas(runDir string) ([]*result.TrialMeta, error) {
	var metas []*result.TrialMeta
	err := filepath.Walk(runDir, func(path string, info os.FileInfo, err error) error {
		if err != nil {
			return err
		}
		if info.Name() == "meta.json" {
			meta, err := result.ReadTrialMeta(path)
			if err != nil {
				return nil
			}
			metas = append(metas, meta)
		}
		return nil
	})
	return metas, err
}

func aggregate(metas []*result.TrialMeta) []OrchestratorSummary {
	type accum struct {
		count        int
		passed       int
		score        float64
		tokens       float64
		cost         float64
		hiddenTests  float64
		agentTests   float64
		coverage     float64
		codeMetrics  float64
		rubric       float64
		hasGreenfield bool
	}
	byOrch := map[string]*accum{}

	for _, m := range metas {
		a, ok := byOrch[m.Orchestrator]
		if !ok {
			a = &accum{}
			byOrch[m.Orchestrator] = a
		}
		a.count++
		a.score += m.CompositeScore
		a.tokens += float64(m.TotalTokens)
		a.cost += m.TotalCostUSD
		a.rubric += m.Scores.Rubric
		if m.ExitReason == "completed" {
			a.passed++
		}
		// Track greenfield-specific scores
		if m.Scores.HiddenTests > 0 || m.Scores.AgentTests > 0 || m.Scores.CodeMetrics > 0 {
			a.hasGreenfield = true
			a.hiddenTests += m.Scores.HiddenTests
			a.agentTests += m.Scores.AgentTests
			a.coverage += m.Scores.Coverage
			a.codeMetrics += m.Scores.CodeMetrics
		}
	}

	var summaries []OrchestratorSummary
	for name, a := range byOrch {
		s := OrchestratorSummary{
			Name:        name,
			Trials:      a.count,
			PassRate:    float64(a.passed) / float64(a.count),
			MeanScore:   a.score / float64(a.count),
			MeanTokens:  a.tokens / float64(a.count),
			MeanCostUSD: a.cost / float64(a.count),
			MeanRubric:  a.rubric / float64(a.count),
		}
		if a.hasGreenfield {
			s.HasGreenfield = true
			s.MeanHiddenTests = a.hiddenTests / float64(a.count)
			s.MeanAgentTests = a.agentTests / float64(a.count)
			s.MeanCoverage = a.coverage / float64(a.count)
			s.MeanCodeMetrics = a.codeMetrics / float64(a.count)
		}
		summaries = append(summaries, s)
	}
	sort.Slice(summaries, func(i, j int) bool {
		return summaries[i].Name < summaries[j].Name
	})
	return summaries
}

func enrichCosts(runDir string, metas []*result.TrialMeta, pricingPath string) {
	table, err := pricing.Load(pricingPath)
	if err != nil {
		return
	}
	for _, m := range metas {
		logPath := filepath.Join(
			result.TrialDir(runDir, m.Orchestrator, m.Task, m.Trial),
			"proxy-log.jsonl",
		)
		records, err := gateway.ParseUsageLogs(logPath)
		if err != nil {
			continue
		}
		var totalCost float64
		for _, r := range records {
			totalCost += table.Cost(r.Provider, r.Model, r.InputTokens, r.OutputTokens)
		}
		m.TotalCostUSD = totalCost
	}
}

func writeTable(summaries []OrchestratorSummary, w io.Writer) error {
	tw := tabwriter.NewWriter(w, 0, 4, 2, ' ', 0)
	fmt.Fprintln(tw, "ORCHESTRATOR\tTRIALS\tPASS RATE\tMEAN SCORE\tMEAN TOKENS\tMEAN COST")
	fmt.Fprintln(tw, strings.Repeat("-", 80))
	for _, s := range summaries {
		fmt.Fprintf(tw, "%s\t%d\t%.0f%%\t%.3f\t%.0f\t$%.2f\n",
			s.Name, s.Trials, s.PassRate*100, s.MeanScore, s.MeanTokens, s.MeanCostUSD)
	}
	if err := tw.Flush(); err != nil {
		return err
	}

	// Print greenfield breakdown if any orchestrator has greenfield results
	hasGreen := false
	for _, s := range summaries {
		if s.HasGreenfield {
			hasGreen = true
			break
		}
	}
	if hasGreen {
		fmt.Fprintln(w)
		tw2 := tabwriter.NewWriter(w, 0, 4, 2, ' ', 0)
		fmt.Fprintln(tw2, "GREENFIELD BREAKDOWN")
		fmt.Fprintln(tw2, "ORCHESTRATOR\tHIDDEN TESTS\tAGENT TESTS\tCOVERAGE\tCODE METRICS\tRUBRIC")
		fmt.Fprintln(tw2, strings.Repeat("-", 80))
		for _, s := range summaries {
			if s.HasGreenfield {
				fmt.Fprintf(tw2, "%s\t%.3f\t%.3f\t%.3f\t%.3f\t%.3f\n",
					s.Name, s.MeanHiddenTests, s.MeanAgentTests, s.MeanCoverage, s.MeanCodeMetrics, s.MeanRubric)
			}
		}
		return tw2.Flush()
	}
	return nil
}

func writeMarkdown(summaries []OrchestratorSummary, w io.Writer) error {
	fmt.Fprintln(w, "| Orchestrator | Trials | Pass Rate | Mean Score | Mean Tokens | Mean Cost |")
	fmt.Fprintln(w, "|---|---|---|---|---|---|")
	for _, s := range summaries {
		fmt.Fprintf(w, "| %s | %d | %.0f%% | %.3f | %.0f | $%.2f |\n",
			s.Name, s.Trials, s.PassRate*100, s.MeanScore, s.MeanTokens, s.MeanCostUSD)
	}
	return nil
}

func writeJSON(summaries []OrchestratorSummary, w io.Writer) error {
	enc := json.NewEncoder(w)
	enc.SetIndent("", "  ")
	return enc.Encode(summaries)
}
