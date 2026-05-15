package pricing

import (
	"fmt"
	"os"

	"gopkg.in/yaml.v3"
)

type ModelPricing struct {
	Input      float64 `yaml:"input"`
	Output     float64 `yaml:"output"`
	CacheWrite float64 `yaml:"cache_write"`
	CacheRead  float64 `yaml:"cache_read"`
}

type Table struct {
	Providers map[string]map[string]ModelPricing
}

func Load(path string) (*Table, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		return nil, fmt.Errorf("reading pricing file: %w", err)
	}
	var providers map[string]map[string]ModelPricing
	if err := yaml.Unmarshal(data, &providers); err != nil {
		return nil, fmt.Errorf("parsing pricing file: %w", err)
	}
	return &Table{Providers: providers}, nil
}

// Has reports whether the table has pricing for the given provider/model.
func (t *Table) Has(provider, model string) bool {
	if t.Providers == nil {
		return false
	}
	models, ok := t.Providers[provider]
	if !ok {
		return false
	}
	_, ok = models[model]
	return ok
}

// Cost calculates total cost for a request. Prices are per 1K tokens.
// cacheCreationTokens and cacheReadTokens cover Anthropic-style prompt
// caching; passing 0 for either is fine for providers without caching.
func (t *Table) Cost(provider, model string, inputTokens, outputTokens, cacheCreationTokens, cacheReadTokens int) float64 {
	if t.Providers == nil {
		return 0
	}
	models, ok := t.Providers[provider]
	if !ok {
		return 0
	}
	p, ok := models[model]
	if !ok {
		return 0
	}
	return (float64(inputTokens)/1000.0)*p.Input +
		(float64(outputTokens)/1000.0)*p.Output +
		(float64(cacheCreationTokens)/1000.0)*p.CacheWrite +
		(float64(cacheReadTokens)/1000.0)*p.CacheRead
}
