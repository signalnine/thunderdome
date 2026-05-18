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
	if err := os.MkdirAll(runsDir, 0o755); err != nil {
		return "", fmt.Errorf("creating runs dir: %w", err)
	}
	stamp := time.Now().UTC().Format("2006-01-02T15-04-05")
	base := filepath.Join(runsDir, stamp)
	base, err := filepath.Abs(base)
	if err != nil {
		return "", fmt.Errorf("resolving run dir: %w", err)
	}
	// Defend against same-second collisions: try the bare stamp first, then
	// "<stamp>-1", "<stamp>-2", ... until os.Mkdir succeeds.
	runDir := base
	for i := 1; ; i++ {
		err := os.Mkdir(runDir, 0o755)
		if err == nil {
			break
		}
		if !os.IsExist(err) {
			return "", fmt.Errorf("creating run dir: %w", err)
		}
		runDir = fmt.Sprintf("%s-%d", base, i)
	}
	if err := updateLatest(baseDir, runDir); err != nil {
		return "", err
	}
	return runDir, nil
}

// updateLatest atomically points <baseDir>/latest at target. Uses a
// uniquely-named temp symlink + os.Rename so concurrent callers don't
// observe a missing symlink and don't collide on the temp name.
func updateLatest(baseDir, target string) error {
	latest := filepath.Join(baseDir, "latest")
	if fi, err := os.Lstat(latest); err == nil {
		if fi.Mode()&os.ModeSymlink == 0 {
			return fmt.Errorf("latest exists and is not a symlink: %s", latest)
		}
	} else if !os.IsNotExist(err) {
		return fmt.Errorf("stat latest: %w", err)
	}
	tmp := fmt.Sprintf("%s.tmp.%d.%d", latest, os.Getpid(), time.Now().UnixNano())
	if err := os.Symlink(target, tmp); err != nil {
		return fmt.Errorf("creating temp symlink: %w", err)
	}
	if err := os.Rename(tmp, latest); err != nil {
		os.Remove(tmp)
		return fmt.Errorf("renaming latest symlink: %w", err)
	}
	return nil
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
	target := filepath.Join(trialDir, "meta.json")
	tmp, err := os.CreateTemp(trialDir, "meta.json.tmp-*")
	if err != nil {
		return fmt.Errorf("creating tmp meta: %w", err)
	}
	tmpPath := tmp.Name()
	defer func() {
		if _, statErr := os.Stat(tmpPath); statErr == nil {
			os.Remove(tmpPath)
		}
	}()
	if _, err := tmp.Write(data); err != nil {
		tmp.Close()
		return fmt.Errorf("writing tmp meta: %w", err)
	}
	if err := tmp.Sync(); err != nil {
		tmp.Close()
		return fmt.Errorf("syncing tmp meta: %w", err)
	}
	if err := tmp.Close(); err != nil {
		return fmt.Errorf("closing tmp meta: %w", err)
	}
	return os.Rename(tmpPath, target)
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
