package config_test

import (
	"testing"

	"github.com/signalnine/thunderdome/internal/config"
)

func TestLoadMinimal(t *testing.T) {
	cfg, err := config.Load("../../testdata/minimal.yaml")
	if err != nil {
		t.Fatalf("Load failed: %v", err)
	}
	if len(cfg.Orchestrators) != 1 {
		t.Errorf("expected 1 orchestrator, got %d", len(cfg.Orchestrators))
	}
	if cfg.Orchestrators[0].Name != "null" {
		t.Errorf("expected orchestrator name 'null', got %q", cfg.Orchestrators[0].Name)
	}
	if len(cfg.Tasks) != 1 {
		t.Errorf("expected 1 task, got %d", len(cfg.Tasks))
	}
	if cfg.Trials != 1 {
		t.Errorf("expected 1 trial, got %d", cfg.Trials)
	}
	if cfg.Proxy.BudgetPerTrialUSD != 5.0 {
		t.Errorf("expected budget 5.0, got %f", cfg.Proxy.BudgetPerTrialUSD)
	}
}

func TestLoadFull(t *testing.T) {
	cfg, err := config.Load("../../testdata/full.yaml")
	if err != nil {
		t.Fatalf("Load failed: %v", err)
	}
	if len(cfg.Orchestrators) < 2 {
		t.Errorf("expected at least 2 orchestrators, got %d", len(cfg.Orchestrators))
	}
	if len(cfg.Network.Allowlist) == 0 {
		t.Error("expected non-empty network allowlist")
	}
	if cfg.Secrets.EnvFile == "" {
		t.Error("expected secrets env_file to be set")
	}
	for _, o := range cfg.Orchestrators {
		if o.Name == "superpowers-full" && len(o.Env) == 0 {
			t.Error("expected env vars on superpowers-full")
		}
	}
	for _, task := range cfg.Tasks {
		if task.Category == "greenfield/simple" && task.ReferenceTag == "" {
			t.Error("expected reference_tag on greenfield/simple task")
		}
	}
}

func TestLoadMissing(t *testing.T) {
	_, err := config.Load("nonexistent.yaml")
	if err == nil {
		t.Error("expected error for missing file")
	}
}

func TestLoadInvalid(t *testing.T) {
	_, err := config.Load("../../testdata/invalid.yaml")
	if err == nil {
		t.Error("expected error for invalid YAML")
	}
}
