package config

import (
	"fmt"
	"os"

	"gopkg.in/yaml.v3"
)

type Config struct {
	Orchestrators []Orchestrator `yaml:"orchestrators"`
	Tasks         []Task         `yaml:"tasks"`
	Trials        int            `yaml:"trials"`
	Proxy         Proxy          `yaml:"proxy"`
	Network       Network        `yaml:"network"`
	Secrets       Secrets        `yaml:"secrets"`
	Results       Results        `yaml:"results"`
}

type Orchestrator struct {
	Name    string            `yaml:"name"`
	Adapter string            `yaml:"adapter"`
	Image   string            `yaml:"image"`
	Env     map[string]string `yaml:"env"`
}

type Task struct {
	ID               string            `yaml:"id"`
	Name             string            `yaml:"name"`
	Repo             string            `yaml:"repo"`
	Tag              string            `yaml:"tag"`
	ReferenceTag     string            `yaml:"reference_tag"`
	Category         string            `yaml:"category"`
	ValidationImage  string            `yaml:"validation_image"`
	InstallCmd       string            `yaml:"install_cmd"`
	TestCmd          string            `yaml:"test_cmd"`
	BuildCmd         string            `yaml:"build_cmd"`
	LintCmd          string            `yaml:"lint_cmd"`
	TimeLimitMinutes int               `yaml:"time_limit_minutes"`
	Rubric           []RubricCriterion `yaml:"rubric"`
	Weights          ValidationWeights `yaml:"weights"`
	Greenfield       bool              `yaml:"greenfield"`
	ValidationTag    string            `yaml:"validation_tag"`
	GreenWeights     GreenWeights      `yaml:"green_weights"`
}

type RubricCriterion struct {
	Criterion string  `yaml:"criterion"`
	Weight    float64 `yaml:"weight"`
}

type ValidationWeights struct {
	Tests          float64 `yaml:"tests"`
	StaticAnalysis float64 `yaml:"static_analysis"`
	Rubric         float64 `yaml:"rubric"`
}

// GreenWeights defines scoring weights for greenfield tasks.
type GreenWeights struct {
	Rubric      float64 `yaml:"rubric"`
	HiddenTests float64 `yaml:"hidden_tests"`
	AgentTests  float64 `yaml:"agent_tests"`
	BuildLint   float64 `yaml:"build_lint"`
	CodeMetrics float64 `yaml:"code_metrics"`
}

type Proxy struct {
	Gateway           string  `yaml:"gateway"`
	LogDir            string  `yaml:"log_dir"`
	BudgetPerTrialUSD float64 `yaml:"budget_per_trial_usd"`
	JudgeModel        string  `yaml:"judge_model"`
}

type Network struct {
	Allowlist []string `yaml:"allowlist"`
}

type Secrets struct {
	EnvFile string `yaml:"env_file"`
}

type Results struct {
	Dir string `yaml:"dir"`
}

func Load(path string) (*Config, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		return nil, fmt.Errorf("reading config %s: %w", path, err)
	}
	var cfg Config
	if err := yaml.Unmarshal(data, &cfg); err != nil {
		return nil, fmt.Errorf("parsing config %s: %w", path, err)
	}
	if err := validate(&cfg); err != nil {
		return nil, fmt.Errorf("invalid config %s: %w", path, err)
	}
	return &cfg, nil
}

func validate(cfg *Config) error {
	if len(cfg.Orchestrators) == 0 {
		return fmt.Errorf("no orchestrators defined")
	}
	for i, o := range cfg.Orchestrators {
		if o.Name == "" {
			return fmt.Errorf("orchestrator %d: name is required", i)
		}
		if o.Adapter == "" {
			return fmt.Errorf("orchestrator %q: adapter is required", o.Name)
		}
		if o.Image == "" {
			return fmt.Errorf("orchestrator %q: image is required", o.Name)
		}
	}
	if len(cfg.Tasks) == 0 {
		return fmt.Errorf("no tasks defined")
	}
	for i := range cfg.Tasks {
		t := &cfg.Tasks[i]
		if t.Repo == "" {
			return fmt.Errorf("task %d: repo is required", i)
		}
		if t.Tag == "" {
			return fmt.Errorf("task %d: tag is required", i)
		}
		if t.ValidationImage == "" {
			t.ValidationImage = "node:20"
		}
		if t.TestCmd == "" && !t.Greenfield {
			return fmt.Errorf("task %d: test_cmd is required for non-greenfield tasks", i)
		}
		if t.Greenfield && t.ValidationTag == "" {
			t.ValidationTag = "v1-validation"
		}
		if t.InstallCmd == "" {
			t.InstallCmd = "npm install"
		}
	}
	if cfg.Trials < 1 {
		return fmt.Errorf("trials must be at least 1")
	}
	return nil
}
