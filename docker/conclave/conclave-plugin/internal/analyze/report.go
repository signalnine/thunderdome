package analyze

import (
	"encoding/csv"
	"encoding/json"
	"fmt"
	"io"
	"strconv"
)

// FormatCorrelationTable writes a human-readable correlation report.
func FormatCorrelationTable(w io.Writer, report *CorrelationReport) {
	fmt.Fprintf(w, "Behavioral Correlation Analysis\n")
	fmt.Fprintf(w, "Traced trials: %d / %d total\n\n", report.TracedTrials, report.TotalTrials)

	fmt.Fprintf(w, "%-30s %8s %10s %10s %8s %8s\n",
		"SIGNAL", "r", "MEAN(ON)", "MEAN(OFF)", "DELTA", "N(ON)")
	fmt.Fprintf(w, "%s\n", repeatDash(86))

	for _, sig := range report.Signals {
		delta := sig.MeanWhenOn - sig.MeanWhenOff
		fmt.Fprintf(w, "%-30s %+8.3f %10.3f %10.3f %+8.3f %8d\n",
			sig.Name, sig.Correlation, sig.MeanWhenOn, sig.MeanWhenOff, delta, sig.CountOn)
	}
}

// FormatCSV writes all trial analyses as CSV for external analysis tools.
func FormatCSV(w io.Writer, trials []TrialAnalysis) {
	cw := csv.NewWriter(w)
	defer cw.Flush()

	header := []string{
		"orchestrator", "task", "trial", "score", "exit_reason",
		"duration_s", "cost_usd", "has_trace",
		"tdd_compliance", "test_first_ratio",
		"verification_before_commit", "final_verification",
		"build_check", "lint_check", "diff_review",
		"commit_count", "test_run_count", "fix_cycles",
		"run_timestamp",
	}
	cw.Write(header)

	for _, t := range trials {
		b := t.Behaviors
		row := []string{
			t.Orchestrator,
			t.Task,
			strconv.Itoa(t.Trial),
			fmt.Sprintf("%.4f", t.Score),
			t.ExitReason,
			strconv.Itoa(t.DurationS),
			fmt.Sprintf("%.4f", t.CostUSD),
			strconv.FormatBool(b.HasTrace),
			strconv.FormatBool(b.TDDCompliance),
			fmt.Sprintf("%.4f", b.TestFirstRatio),
			strconv.FormatBool(b.VerificationBeforeCommit),
			strconv.FormatBool(b.FinalVerification),
			strconv.FormatBool(b.BuildCheck),
			strconv.FormatBool(b.LintCheck),
			strconv.FormatBool(b.DiffReview),
			strconv.Itoa(b.CommitCount),
			strconv.Itoa(b.TestRunCount),
			strconv.Itoa(b.FixCycles),
			t.RunTimestamp,
		}
		cw.Write(row)
	}
}

// FormatTrialJSON writes a single trial analysis as pretty-printed JSON.
func FormatTrialJSON(w io.Writer, ta *TrialAnalysis) {
	out := map[string]interface{}{
		"orchestrator":  ta.Orchestrator,
		"task":          ta.Task,
		"trial":         ta.Trial,
		"score":         ta.Score,
		"exit_reason":   ta.ExitReason,
		"duration_s":    ta.DurationS,
		"cost_usd":      ta.CostUSD,
		"run_timestamp": ta.RunTimestamp,
		"behaviors": map[string]interface{}{
			"has_trace":                  ta.Behaviors.HasTrace,
			"tdd_compliance":             ta.Behaviors.TDDCompliance,
			"test_first_ratio":           ta.Behaviors.TestFirstRatio,
			"verification_before_commit": ta.Behaviors.VerificationBeforeCommit,
			"final_verification":         ta.Behaviors.FinalVerification,
			"build_check":               ta.Behaviors.BuildCheck,
			"lint_check":                ta.Behaviors.LintCheck,
			"diff_review":               ta.Behaviors.DiffReview,
			"commit_count":              ta.Behaviors.CommitCount,
			"test_run_count":            ta.Behaviors.TestRunCount,
			"fix_cycles":               ta.Behaviors.FixCycles,
		},
	}
	enc := json.NewEncoder(w)
	enc.SetIndent("", "  ")
	enc.Encode(out)
}

func repeatDash(n int) string {
	b := make([]byte, n)
	for i := range b {
		b[i] = '-'
	}
	return string(b)
}
