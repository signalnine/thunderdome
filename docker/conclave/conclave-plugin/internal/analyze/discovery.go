package analyze

import (
	"encoding/json"
	"os"
	"path/filepath"
	"strings"
)

// TrialAnalysis combines trial metadata with behavioral analysis.
type TrialAnalysis struct {
	Orchestrator string
	Task         string
	Trial        int
	Score        float64
	ExitReason   string
	DurationS    int
	CostUSD      float64
	Behaviors    *BehaviorProfile
	RunTimestamp string // from run directory name
}

// DiscoverTrials walks the results/runs/ directory tree and returns
// analyzed trials with behavioral profiles where NDJSON is available.
// Expected layout: runs/<timestamp>/trials/<orchestrator>/<task>/trial-<N>/
func DiscoverTrials(runsDir string) ([]TrialAnalysis, error) {
	var results []TrialAnalysis

	runDirs, err := os.ReadDir(runsDir)
	if err != nil {
		return nil, err
	}

	for _, runEntry := range runDirs {
		if !runEntry.IsDir() {
			continue
		}
		// Skip symlinks like "latest"
		if runEntry.Name() == "latest" {
			continue
		}
		runTimestamp := runEntry.Name()
		trialsBase := filepath.Join(runsDir, runTimestamp, "trials")

		orchDirs, err := os.ReadDir(trialsBase)
		if err != nil {
			continue
		}
		for _, orchEntry := range orchDirs {
			if !orchEntry.IsDir() {
				continue
			}
			taskDirs, err := os.ReadDir(filepath.Join(trialsBase, orchEntry.Name()))
			if err != nil {
				continue
			}
			for _, taskEntry := range taskDirs {
				if !taskEntry.IsDir() {
					continue
				}
				trialDirs, err := os.ReadDir(filepath.Join(trialsBase, orchEntry.Name(), taskEntry.Name()))
				if err != nil {
					continue
				}
				for _, trialEntry := range trialDirs {
					if !trialEntry.IsDir() || !strings.HasPrefix(trialEntry.Name(), "trial-") {
						continue
					}
					trialPath := filepath.Join(trialsBase, orchEntry.Name(), taskEntry.Name(), trialEntry.Name())
					ta, err := analyzeTrial(trialPath, runTimestamp)
					if err != nil {
						continue
					}
					results = append(results, *ta)
				}
			}
		}
	}

	return results, nil
}

func analyzeTrial(trialDir, runTimestamp string) (*TrialAnalysis, error) {
	// Read meta.json
	metaPath := filepath.Join(trialDir, "meta.json")
	metaBytes, err := os.ReadFile(metaPath)
	if err != nil {
		return nil, err
	}

	var meta struct {
		Orchestrator   string  `json:"orchestrator"`
		Task           string  `json:"task"`
		Trial          int     `json:"trial"`
		CompositeScore float64 `json:"composite_score"`
		ExitReason     string  `json:"exit_reason"`
		DurationS      int     `json:"duration_s"`
		TotalCostUSD   float64 `json:"total_cost_usd"`
	}
	if err := json.Unmarshal(metaBytes, &meta); err != nil {
		return nil, err
	}

	ta := &TrialAnalysis{
		Orchestrator: meta.Orchestrator,
		Task:         meta.Task,
		Trial:        meta.Trial,
		Score:        meta.CompositeScore,
		ExitReason:   meta.ExitReason,
		DurationS:    meta.DurationS,
		CostUSD:      meta.TotalCostUSD,
		RunTimestamp:  runTimestamp,
	}

	// Try to parse NDJSON trace
	ndjsonPath := filepath.Join(trialDir, "workspace", ".thunderdome-output.jsonl")
	if trace, err := ParseTrace(ndjsonPath); err == nil && len(trace.ToolCalls) > 0 {
		ta.Behaviors = ExtractBehaviors(trace)
	} else {
		ta.Behaviors = &BehaviorProfile{HasTrace: false}
	}

	return ta, nil
}
