package result

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"time"
)

func CreateRunDir(baseDir string) (string, error) {
	runsDir := filepath.Join(baseDir, "runs")
	stamp := time.Now().UTC().Format("2006-01-02T15-04-05")
	runDir := filepath.Join(runsDir, stamp)
	runDir, err := filepath.Abs(runDir)
	if err != nil {
		return "", fmt.Errorf("resolving run dir: %w", err)
	}
	if err := os.MkdirAll(runDir, 0o755); err != nil {
		return "", fmt.Errorf("creating run dir: %w", err)
	}
	latest := filepath.Join(baseDir, "latest")
	os.Remove(latest)
	if err := os.Symlink(runDir, latest); err != nil {
		return "", fmt.Errorf("creating latest symlink: %w", err)
	}
	return runDir, nil
}

func TrialDir(runDir, orchestrator, task string, trial int) string {
	return filepath.Join(runDir, "trials", orchestrator, task, fmt.Sprintf("trial-%d", trial))
}

func WriteTrialMeta(trialDir string, meta *TrialMeta) error {
	if err := os.MkdirAll(trialDir, 0o755); err != nil {
		return fmt.Errorf("creating trial dir: %w", err)
	}
	data, err := json.MarshalIndent(meta, "", "  ")
	if err != nil {
		return fmt.Errorf("marshaling meta: %w", err)
	}
	return os.WriteFile(filepath.Join(trialDir, "meta.json"), data, 0o644)
}

func ReadTrialMeta(path string) (*TrialMeta, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		return nil, fmt.Errorf("reading meta: %w", err)
	}
	var meta TrialMeta
	if err := json.Unmarshal(data, &meta); err != nil {
		return nil, fmt.Errorf("parsing meta: %w", err)
	}
	return &meta, nil
}
