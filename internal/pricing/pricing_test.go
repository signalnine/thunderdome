package pricing_test

import (
	"os"
	"path/filepath"
	"testing"

	"github.com/signalnine/thunderdome/internal/pricing"
)

func abs(x float64) float64 {
	if x < 0 {
		return -x
	}
	return x
}

func TestLoadPricing(t *testing.T) {
	dir := t.TempDir()
	content := `anthropic:
  claude-opus-4-6:
    input: 0.015
    output: 0.075
openai:
  codex-max:
    input: 0.01
    output: 0.03
`
	path := filepath.Join(dir, "pricing.yaml")
	os.WriteFile(path, []byte(content), 0o644)

	table, err := pricing.Load(path)
	if err != nil {
		t.Fatalf("Load: %v", err)
	}
	cost := table.Cost("anthropic", "claude-opus-4-6", 1000, 500)
	want := 0.0525
	if abs(cost-want) > 0.001 {
		t.Errorf("got %f, want %f", cost, want)
	}
}

func TestCostUnknownModel(t *testing.T) {
	table := &pricing.Table{}
	cost := table.Cost("unknown", "unknown", 1000, 500)
	if cost != 0 {
		t.Errorf("expected 0 for unknown model, got %f", cost)
	}
}
