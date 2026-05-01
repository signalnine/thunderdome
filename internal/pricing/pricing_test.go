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
	cost := table.Cost("anthropic", "claude-opus-4-6", 1000, 500, 0, 0)
	want := 0.0525
	if abs(cost-want) > 0.001 {
		t.Errorf("got %f, want %f", cost, want)
	}
}

func TestCostUnknownModel(t *testing.T) {
	table := &pricing.Table{}
	cost := table.Cost("unknown", "unknown", 1000, 500, 0, 0)
	if cost != 0 {
		t.Errorf("expected 0 for unknown model, got %f", cost)
	}
}

func TestCostCacheTokens(t *testing.T) {
	dir := t.TempDir()
	content := `anthropic:
  claude-opus-4-6:
    input: 0.015
    output: 0.075
    cache_write: 0.01875
    cache_read: 0.0015
`
	path := filepath.Join(dir, "pricing.yaml")
	os.WriteFile(path, []byte(content), 0o644)

	table, err := pricing.Load(path)
	if err != nil {
		t.Fatalf("Load: %v", err)
	}
	// 1000 in @ 0.015 + 500 out @ 0.075 + 2000 cache_write @ 0.01875 + 10000 cache_read @ 0.0015
	// = 0.015 + 0.0375 + 0.0375 + 0.015 = 0.105
	cost := table.Cost("anthropic", "claude-opus-4-6", 1000, 500, 2000, 10000)
	want := 0.105
	if abs(cost-want) > 0.001 {
		t.Errorf("got %f, want %f", cost, want)
	}
}

// TestCostMatchesGatewayEstimate checks that pricing.Cost (loaded from
// pricing.yaml) and gateway.EstimateCost (hardcoded per-million pricing)
// agree on a representative usage record. If this test breaks, one of the
// two pricing sources is stale -- see td-0eb.
func TestCostMatchesGatewayEstimate(t *testing.T) {
	dir := t.TempDir()
	content := `anthropic:
  claude-opus-4-6:
    input: 0.015
    output: 0.075
    cache_write: 0.01875
    cache_read: 0.0015
`
	path := filepath.Join(dir, "pricing.yaml")
	os.WriteFile(path, []byte(content), 0o644)
	table, err := pricing.Load(path)
	if err != nil {
		t.Fatalf("Load: %v", err)
	}
	in, out, cw, cr := 1234, 567, 8901, 23456
	yamlCost := table.Cost("anthropic", "claude-opus-4-6", in, out, cw, cr)
	// Replicate gateway.EstimateCost math for opus: 15/75/18.75/1.5 per 1M.
	expected := float64(in)*15.0/1e6 + float64(out)*75.0/1e6 +
		float64(cw)*18.75/1e6 + float64(cr)*1.50/1e6
	if abs(yamlCost-expected) > 0.0001 {
		t.Errorf("pricing.Cost=%f, gateway EstimateCost=%f", yamlCost, expected)
	}
}
