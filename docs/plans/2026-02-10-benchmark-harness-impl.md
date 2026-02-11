# Benchmark Harness Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use conclave:executing-plans to implement this plan task-by-task.

**Goal:** Build the `thunderdome` CLI tool — a Go binary that runs agentic coding orchestrators against benchmark tasks in Docker containers and scores them.

**Architecture:** Cobra CLI wrapping a pipeline: config parsing → task repo cloning → Docker container per trial → LiteLLM gateway for cost tracking → multi-layer validation → JSON results. Worker pool for parallel execution.

**Tech Stack:** Go 1.22+, Cobra (CLI), Docker SDK for Go, gopkg.in/yaml.v3, LiteLLM (external process)

**Design doc:** `docs/plans/2026-02-10-benchmark-harness-design.md`

---

### Task 1: Project Scaffolding

**Files:**
- Create: `go.mod`
- Create: `main.go`
- Create: `.gitignore`
- Create: `adapters/null.sh`

**Dependencies:** none

**Step 1: Initialize git repo**

```bash
cd /home/gabe/agentic-thunderdome
git init
```

**Step 2: Initialize Go module**

```bash
go mod init github.com/signalnine/thunderdome
```

**Step 3: Create main.go stub**

```go
// main.go
package main

import (
	"fmt"
	"os"
)

func main() {
	fmt.Println("thunderdome")
	os.Exit(0)
}
```

**Step 4: Create .gitignore**

```
# .gitignore
/thunderdome
/results/
.env.secrets
*.test
```

**Step 5: Create null adapter**

```bash
#!/bin/bash
# adapters/null.sh — baseline adapter that does nothing
exit 0
```

Make it executable: `chmod +x adapters/null.sh`

**Step 6: Verify it builds and runs**

Run: `go build -o thunderdome . && ./thunderdome`
Expected: prints "thunderdome"

**Step 7: Commit**

```bash
git add go.mod main.go .gitignore adapters/null.sh CLAUDE.md project.md docs/
git commit -m "feat: project scaffolding with Go module and null adapter"
```

---

### Task 2: Config Types and Parsing

**Files:**
- Create: `internal/config/config.go`
- Create: `internal/config/config_test.go`
- Create: `testdata/minimal.yaml`
- Create: `testdata/full.yaml`

**Dependencies:** Task 1

**Step 1: Create test fixtures**

`testdata/minimal.yaml`:
```yaml
orchestrators:
  - name: null
    adapter: ./adapters/null.sh
    image: alpine:latest

tasks:
  - repo: https://github.com/example/bench-task.git
    tag: v1
    category: greenfield/simple
    validation_image: node:20
    install_cmd: "npm install"
    test_cmd: "npm test"
    lint_cmd: "npx eslint ."

trials: 1

proxy:
  gateway: litellm
  log_dir: ./results/proxy-logs
  budget_per_trial_usd: 5.00

results:
  dir: ./results
```

`testdata/full.yaml` — includes network allowlist, secrets, multiple orchestrators/tasks, reference_tag, env vars, rubric, and validation weights.

**Step 2: Write failing tests**

`internal/config/config_test.go`:
```go
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
	// Check orchestrator env vars
	for _, o := range cfg.Orchestrators {
		if o.Name == "superpowers-full" && len(o.Env) == 0 {
			t.Error("expected env vars on superpowers-full")
		}
	}
	// Check task with reference_tag
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
```

Also create `testdata/invalid.yaml`:
```yaml
orchestrators: "not a list"
```

**Step 3: Run tests to verify they fail**

Run: `go test ./internal/config/ -v`
Expected: FAIL — package doesn't exist yet

**Step 4: Implement config types and loader**

`internal/config/config.go`:
```go
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
	Repo            string            `yaml:"repo"`
	Tag             string            `yaml:"tag"`
	ReferenceTag    string            `yaml:"reference_tag"`
	Category        string            `yaml:"category"`
	ValidationImage string            `yaml:"validation_image"`
	InstallCmd      string            `yaml:"install_cmd"`
	TestCmd         string            `yaml:"test_cmd"`
	LintCmd         string            `yaml:"lint_cmd"`
	Rubric          []RubricCriterion `yaml:"rubric"`
	Weights         ValidationWeights `yaml:"weights"`
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

type Proxy struct {
	Gateway           string  `yaml:"gateway"`
	LogDir            string  `yaml:"log_dir"`
	BudgetPerTrialUSD float64 `yaml:"budget_per_trial_usd"`
	JudgeModel        string  `yaml:"judge_model"` // Model for LLM rubric judge (default: claude-sonnet-4-5)
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
	for i, t := range cfg.Tasks {
		if t.Repo == "" {
			return fmt.Errorf("task %d: repo is required", i)
		}
		if t.Tag == "" {
			return fmt.Errorf("task %d: tag is required", i)
		}
		if t.ValidationImage == "" {
			return fmt.Errorf("task %d: validation_image is required", i)
		}
		if t.TestCmd == "" {
			return fmt.Errorf("task %d: test_cmd is required", i)
		}
	}
	if cfg.Trials < 1 {
		return fmt.Errorf("trials must be at least 1")
	}
	return nil
}
```

**Step 5: Install dependency and run tests**

Run: `go get gopkg.in/yaml.v3 && go test ./internal/config/ -v`
Expected: all PASS

**Step 6: Commit**

```bash
git add internal/config/ testdata/ go.mod go.sum
git commit -m "feat: config types and YAML parsing with validation"
```

---

### Task 3: CLI Skeleton with Cobra

**Files:**
- Create: `cmd/root.go`
- Create: `cmd/run.go`
- Create: `cmd/list.go`
- Create: `cmd/report.go`
- Create: `cmd/validate.go`
- Modify: `main.go`

**Dependencies:** Task 2

**Step 1: Install cobra**

Run: `go get github.com/spf13/cobra`

**Step 2: Create root command**

`cmd/root.go`:
```go
package cmd

import (
	"github.com/spf13/cobra"
)

var cfgFile string

func NewRootCmd() *cobra.Command {
	root := &cobra.Command{
		Use:   "thunderdome",
		Short: "Benchmark harness for agentic coding orchestrators",
	}
	root.PersistentFlags().StringVar(&cfgFile, "config", "thunderdome.yaml", "config file path")
	root.AddCommand(newRunCmd())
	root.AddCommand(newListCmd())
	root.AddCommand(newReportCmd())
	root.AddCommand(newValidateCmd())
	return root
}
```

**Step 3: Create subcommand stubs**

`cmd/run.go`:
```go
package cmd

import (
	"fmt"

	"github.com/spf13/cobra"
)

var (
	flagOrchestrator string
	flagTask         string
	flagCategory     string
	flagTrials       int
	flagParallel     int
)

func newRunCmd() *cobra.Command {
	cmd := &cobra.Command{
		Use:   "run",
		Short: "Execute a benchmark run",
		RunE: func(cmd *cobra.Command, args []string) error {
			fmt.Println("run: not yet implemented")
			return nil
		},
	}
	cmd.Flags().StringVar(&flagOrchestrator, "orchestrator", "", "filter to a single orchestrator")
	cmd.Flags().StringVar(&flagTask, "task", "", "filter to a single task")
	cmd.Flags().StringVar(&flagCategory, "category", "", "filter by category")
	cmd.Flags().IntVar(&flagTrials, "trials", 0, "override trial count")
	cmd.Flags().IntVar(&flagParallel, "parallel", 1, "max concurrent containers")
	return cmd
}
```

`cmd/list.go`:
```go
package cmd

import (
	"fmt"

	"github.com/spf13/cobra"
)

func newListCmd() *cobra.Command {
	return &cobra.Command{
		Use:   "list",
		Short: "List available tasks and orchestrators",
		RunE: func(cmd *cobra.Command, args []string) error {
			fmt.Println("list: not yet implemented")
			return nil
		},
	}
}
```

`cmd/report.go`:
```go
package cmd

import (
	"fmt"

	"github.com/spf13/cobra"
)

var flagFormat string

func newReportCmd() *cobra.Command {
	cmd := &cobra.Command{
		Use:   "report",
		Short: "Generate summary from stored results",
		RunE: func(cmd *cobra.Command, args []string) error {
			fmt.Println("report: not yet implemented")
			return nil
		},
	}
	cmd.Flags().StringVar(&flagFormat, "format", "table", "output format (table, markdown, json)")
	return cmd
}
```

`cmd/validate.go`:
```go
package cmd

import (
	"fmt"

	"github.com/spf13/cobra"
)

func newValidateCmd() *cobra.Command {
	return &cobra.Command{
		Use:   "validate [run-dir]",
		Short: "Re-score an existing result",
		Args:  cobra.ExactArgs(1),
		RunE: func(cmd *cobra.Command, args []string) error {
			fmt.Println("validate: not yet implemented")
			return nil
		},
	}
}
```

**Step 4: Update main.go**

```go
package main

import (
	"os"

	"github.com/signalnine/thunderdome/cmd"
)

func main() {
	if err := cmd.NewRootCmd().Execute(); err != nil {
		os.Exit(1)
	}
}
```

**Step 5: Build and test CLI**

Run: `go build -o thunderdome . && ./thunderdome --help`
Expected: shows help with run, list, report, validate subcommands

Run: `./thunderdome run --help`
Expected: shows run flags (--orchestrator, --task, --category, --trials, --parallel)

**Step 6: Commit**

```bash
git add cmd/ main.go go.mod go.sum
git commit -m "feat: CLI skeleton with run/list/report/validate commands"
```

---

### Task 4: Result Types and Storage

**Files:**
- Create: `internal/result/types.go`
- Create: `internal/result/storage.go`
- Create: `internal/result/storage_test.go`

**Dependencies:** Task 2

**Step 1: Write failing tests**

`internal/result/storage_test.go`:
```go
package result_test

import (
	"os"
	"path/filepath"
	"testing"

	"github.com/signalnine/thunderdome/internal/result"
)

func TestWriteAndReadTrialMeta(t *testing.T) {
	dir := t.TempDir()
	meta := &result.TrialMeta{
		Orchestrator:   "test-orch",
		Task:           "test-task",
		Trial:          1,
		DurationS:      42,
		ExitCode:       0,
		ExitReason:     "completed",
		Scores:         result.Scores{Tests: 0.9, StaticAnalysis: 0.8, Rubric: 0.7},
		CompositeScore: 0.85,
		TotalTokens:    1000,
		TotalCostUSD:   0.50,
		BudgetExceeded: false,
	}
	if err := result.WriteTrialMeta(dir, meta); err != nil {
		t.Fatalf("WriteTrialMeta: %v", err)
	}
	got, err := result.ReadTrialMeta(filepath.Join(dir, "meta.json"))
	if err != nil {
		t.Fatalf("ReadTrialMeta: %v", err)
	}
	if got.Orchestrator != meta.Orchestrator {
		t.Errorf("orchestrator: got %q, want %q", got.Orchestrator, meta.Orchestrator)
	}
	if got.CompositeScore != meta.CompositeScore {
		t.Errorf("composite_score: got %f, want %f", got.CompositeScore, meta.CompositeScore)
	}
}

func TestCreateRunDir(t *testing.T) {
	base := t.TempDir()
	runDir, err := result.CreateRunDir(base)
	if err != nil {
		t.Fatalf("CreateRunDir: %v", err)
	}
	// Verify directory exists
	if _, err := os.Stat(runDir); os.IsNotExist(err) {
		t.Errorf("run directory not created: %s", runDir)
	}
	// Verify latest symlink
	latest := filepath.Join(base, "latest")
	target, err := os.Readlink(latest)
	if err != nil {
		t.Fatalf("reading latest symlink: %v", err)
	}
	if target != runDir {
		t.Errorf("latest symlink: got %q, want %q", target, runDir)
	}
}

func TestTrialDir(t *testing.T) {
	base := t.TempDir()
	dir := result.TrialDir(base, "my-orch", "my-task", 3)
	expected := filepath.Join(base, "trials", "my-orch", "my-task", "trial-3")
	if dir != expected {
		t.Errorf("got %q, want %q", dir, expected)
	}
}
```

**Step 2: Run tests to verify they fail**

Run: `go test ./internal/result/ -v`
Expected: FAIL — package doesn't exist

**Step 3: Implement types**

`internal/result/types.go`:
```go
package result

type TrialMeta struct {
	Orchestrator   string `json:"orchestrator"`
	Task           string `json:"task"`
	Trial          int    `json:"trial"`
	DurationS      int    `json:"duration_s"`
	ExitCode       int    `json:"exit_code"`
	ExitReason     string `json:"exit_reason"`
	Scores         Scores `json:"scores"`
	CompositeScore float64 `json:"composite_score"`
	TotalTokens    int    `json:"total_tokens"`
	TotalCostUSD   float64 `json:"total_cost_usd"`
	BudgetExceeded bool   `json:"budget_exceeded"`
}

type Scores struct {
	Tests          float64 `json:"tests"`
	StaticAnalysis float64 `json:"static_analysis"`
	Rubric         float64 `json:"rubric"`
}
```

**Step 4: Implement storage**

`internal/result/storage.go`:
```go
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
	if err := os.MkdirAll(runDir, 0o755); err != nil {
		return "", fmt.Errorf("creating run dir: %w", err)
	}
	latest := filepath.Join(baseDir, "latest")
	os.Remove(latest) // ignore error — may not exist
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
```

**Step 5: Run tests**

Run: `go test ./internal/result/ -v`
Expected: all PASS

**Step 6: Commit**

```bash
git add internal/result/
git commit -m "feat: result types and filesystem storage"
```

---

### Task 5: Git Operations

**Files:**
- Create: `internal/gitops/gitops.go`
- Create: `internal/gitops/gitops_test.go`

**Dependencies:** Task 1

**Step 1: Write failing tests**

`internal/gitops/gitops_test.go`:
```go
package gitops_test

import (
	"os"
	"os/exec"
	"path/filepath"
	"testing"

	"github.com/signalnine/thunderdome/internal/gitops"
)

// createTestRepo makes a local git repo with a tagged commit for testing.
func createTestRepo(t *testing.T) string {
	t.Helper()
	dir := t.TempDir()
	cmds := [][]string{
		{"git", "init"},
		{"git", "config", "user.email", "test@test.com"},
		{"git", "config", "user.name", "Test"},
	}
	for _, args := range cmds {
		c := exec.Command(args[0], args[1:]...)
		c.Dir = dir
		if out, err := c.CombinedOutput(); err != nil {
			t.Fatalf("%v: %s", err, out)
		}
	}
	// Create a file and commit
	os.WriteFile(filepath.Join(dir, "hello.txt"), []byte("hello"), 0o644)
	for _, args := range [][]string{
		{"git", "add", "."},
		{"git", "commit", "-m", "initial"},
		{"git", "tag", "v1"},
	} {
		c := exec.Command(args[0], args[1:]...)
		c.Dir = dir
		if out, err := c.CombinedOutput(); err != nil {
			t.Fatalf("%v: %s", err, out)
		}
	}
	return dir
}

func TestCloneAndCheckout(t *testing.T) {
	repo := createTestRepo(t)
	dest := t.TempDir()
	err := gitops.CloneAndCheckout(repo, "v1", dest)
	if err != nil {
		t.Fatalf("CloneAndCheckout: %v", err)
	}
	content, err := os.ReadFile(filepath.Join(dest, "hello.txt"))
	if err != nil {
		t.Fatalf("reading cloned file: %v", err)
	}
	if string(content) != "hello" {
		t.Errorf("content: got %q, want %q", content, "hello")
	}
}

func TestCaptureChanges(t *testing.T) {
	repo := createTestRepo(t)
	dest := t.TempDir()
	gitops.CloneAndCheckout(repo, "v1", dest)
	// Simulate orchestrator work: modify a file and add a new one
	os.WriteFile(filepath.Join(dest, "hello.txt"), []byte("modified"), 0o644)
	os.WriteFile(filepath.Join(dest, "new.txt"), []byte("new file"), 0o644)
	diff, err := gitops.CaptureChanges(dest)
	if err != nil {
		t.Fatalf("CaptureChanges: %v", err)
	}
	if len(diff) == 0 {
		t.Error("expected non-empty diff")
	}
}

func TestCaptureChangesNoChanges(t *testing.T) {
	repo := createTestRepo(t)
	dest := t.TempDir()
	gitops.CloneAndCheckout(repo, "v1", dest)
	diff, err := gitops.CaptureChanges(dest)
	if err != nil {
		t.Fatalf("CaptureChanges: %v", err)
	}
	if len(diff) != 0 {
		t.Errorf("expected empty diff, got %d bytes", len(diff))
	}
}
```

**Step 2: Run tests to verify they fail**

Run: `go test ./internal/gitops/ -v`
Expected: FAIL — package doesn't exist

**Step 3: Implement git operations**

`internal/gitops/gitops.go`:
```go
package gitops

import (
	"fmt"
	"os/exec"
)

func CloneAndCheckout(repo, tag, dest string) error {
	cmd := exec.Command("git", "clone", "--branch", tag, "--depth", "1", repo, dest)
	if out, err := cmd.CombinedOutput(); err != nil {
		return fmt.Errorf("git clone: %s: %w", out, err)
	}
	return nil
}

// CaptureChanges stages all changes (including untracked files) and returns the diff.
func CaptureChanges(repoDir string) ([]byte, error) {
	// Stage everything
	add := exec.Command("git", "add", "-A")
	add.Dir = repoDir
	if out, err := add.CombinedOutput(); err != nil {
		return nil, fmt.Errorf("git add -A: %s: %w", out, err)
	}
	// Diff staged changes
	diff := exec.Command("git", "diff", "--cached")
	diff.Dir = repoDir
	out, err := diff.Output()
	if err != nil {
		return nil, fmt.Errorf("git diff --cached: %w", err)
	}
	return out, nil
}
```

**Step 4: Run tests**

Run: `go test ./internal/gitops/ -v`
Expected: all PASS

**Step 5: Commit**

```bash
git add internal/gitops/
git commit -m "feat: git clone, checkout, and diff capture"
```

---

### Task 6: Docker Container Runner

**Files:**
- Create: `internal/docker/runner.go`
- Create: `internal/docker/runner_test.go`

**Dependencies:** Task 1

Note: These tests require Docker to be running. They use `alpine:latest` as a lightweight test image.

**Step 1: Install Docker SDK**

Run: `go get github.com/docker/docker/client github.com/docker/docker/api/types`

**Step 2: Write failing tests**

`internal/docker/runner_test.go`:
```go
package docker_test

import (
	"context"
	"os"
	"path/filepath"
	"testing"
	"time"

	"github.com/signalnine/thunderdome/internal/docker"
)

func TestRunContainer(t *testing.T) {
	if os.Getenv("THUNDERDOME_DOCKER_TESTS") == "" {
		t.Skip("set THUNDERDOME_DOCKER_TESTS=1 to run Docker tests")
	}
	ctx, cancel := context.WithTimeout(context.Background(), 60*time.Second)
	defer cancel()

	workDir := t.TempDir()
	os.WriteFile(filepath.Join(workDir, "task.md"), []byte("test task"), 0o644)

	result, err := docker.RunContainer(ctx, &docker.RunOpts{
		Image:      "alpine:latest",
		Command:    []string{"sh", "-c", "echo hello > /workspace/output.txt"},
		WorkDir:    workDir,
		Env:        map[string]string{"TASK_DIR": "/workspace"},
		Timeout:    30 * time.Second,
	})
	if err != nil {
		t.Fatalf("RunContainer: %v", err)
	}
	if result.ExitCode != 0 {
		t.Errorf("exit code: got %d, want 0", result.ExitCode)
	}
	if result.TimedOut {
		t.Error("unexpected timeout")
	}
	// Verify the container wrote to the mounted workspace
	content, err := os.ReadFile(filepath.Join(workDir, "output.txt"))
	if err != nil {
		t.Fatalf("reading output: %v", err)
	}
	if string(content) != "hello\n" {
		t.Errorf("output: got %q, want %q", content, "hello\n")
	}
}

func TestRunContainerTimeout(t *testing.T) {
	if os.Getenv("THUNDERDOME_DOCKER_TESTS") == "" {
		t.Skip("set THUNDERDOME_DOCKER_TESTS=1 to run Docker tests")
	}
	ctx := context.Background()
	workDir := t.TempDir()

	result, err := docker.RunContainer(ctx, &docker.RunOpts{
		Image:   "alpine:latest",
		Command: []string{"sleep", "300"},
		WorkDir: workDir,
		Timeout: 2 * time.Second,
	})
	if err != nil {
		t.Fatalf("RunContainer: %v", err)
	}
	if !result.TimedOut {
		t.Error("expected timeout")
	}
	if result.ExitCode != 124 {
		t.Errorf("exit code: got %d, want 124", result.ExitCode)
	}
}

func TestRunContainerCrash(t *testing.T) {
	if os.Getenv("THUNDERDOME_DOCKER_TESTS") == "" {
		t.Skip("set THUNDERDOME_DOCKER_TESTS=1 to run Docker tests")
	}
	ctx := context.Background()
	workDir := t.TempDir()

	result, err := docker.RunContainer(ctx, &docker.RunOpts{
		Image:   "alpine:latest",
		Command: []string{"sh", "-c", "exit 1"},
		WorkDir: workDir,
		Timeout: 10 * time.Second,
	})
	if err != nil {
		t.Fatalf("RunContainer: %v", err)
	}
	if result.ExitCode != 1 {
		t.Errorf("exit code: got %d, want 1", result.ExitCode)
	}
}
```

**Step 3: Run tests to verify they fail**

Run: `go test ./internal/docker/ -v`
Expected: FAIL — package doesn't exist

**Step 4: Implement container runner**

`internal/docker/runner.go`:
```go
package docker

import (
	"context"
	"fmt"
	"io"
	"time"

	"github.com/docker/docker/api/types/container"
	"github.com/docker/docker/api/types/mount"
	"github.com/docker/docker/api/types/network"
	"github.com/docker/docker/client"
)

type RunOpts struct {
	Image       string
	Command     []string
	WorkDir     string
	Env         map[string]string
	Timeout     time.Duration
	ExtraMounts []Mount           // Additional bind mounts (adapter script, task desc)
	Allowlist   []string          // Hostnames the container may reach (beyond gateway)
	GatewayAddr string            // host:port of the LLM gateway
	CPULimit    float64           // CPU cores (0 = unlimited)
	MemoryLimit int64             // Bytes (0 = unlimited)
	UserID      string            // UID:GID to run as (e.g., "1000:1000")
}

type Mount struct {
	Source   string
	Target   string
	ReadOnly bool
}

type RunResult struct {
	ExitCode int
	TimedOut bool
	Duration time.Duration
}

func RunContainer(ctx context.Context, opts *RunOpts) (*RunResult, error) {
	cli, err := client.NewClientWithOpts(client.FromEnv, client.WithAPIVersionNegotiation())
	if err != nil {
		return nil, fmt.Errorf("creating docker client: %w", err)
	}
	defer cli.Close()

	envSlice := make([]string, 0, len(opts.Env))
	for k, v := range opts.Env {
		envSlice = append(envSlice, k+"="+v)
	}

	// Build mount list: workspace + any extra mounts (adapter script, task desc)
	mounts := []mount.Mount{
		{
			Type:   mount.TypeBind,
			Source: opts.WorkDir,
			Target: "/workspace",
		},
	}
	for _, m := range opts.ExtraMounts {
		mounts = append(mounts, mount.Mount{
			Type:     mount.TypeBind,
			Source:   m.Source,
			Target:   m.Target,
			ReadOnly: m.ReadOnly,
		})
	}

	// Resource constraints
	hostCfg := &container.HostConfig{Mounts: mounts}
	if opts.CPULimit > 0 {
		hostCfg.NanoCPUs = int64(opts.CPULimit * 1e9)
	}
	if opts.MemoryLimit > 0 {
		hostCfg.Memory = opts.MemoryLimit
	}

	containerCfg := &container.Config{
		Image:  opts.Image,
		Cmd:    opts.Command,
		Env:    envSlice,
		Labels: map[string]string{"thunderdome": "true"},
	}
	if opts.UserID != "" {
		containerCfg.User = opts.UserID
	}

	// Network isolation: use Docker's Internal network mode.
	// Internal networks block all external egress by default.
	// The gateway runs on the host, so we use host.docker.internal
	// or add the gateway as an extra_hosts entry.
	// For package registry access, we run a Squid forward proxy sidecar
	// on the same internal network, configured with the allowlist.
	var networkingCfg *network.NetworkingConfig
	if opts.GatewayAddr != "" || len(opts.Allowlist) > 0 {
		networkID, err := createIsolatedNetwork(ctx, cli)
		if err != nil {
			return nil, fmt.Errorf("creating isolated network: %w", err)
		}
		defer cli.NetworkRemove(context.Background(), networkID)

		networkingCfg = &network.NetworkingConfig{
			EndpointsConfig: map[string]*network.EndpointSettings{
				networkID: {},
			},
		}
		// Allow the container to reach the host (where gateway runs)
		hostCfg.ExtraHosts = []string{"host.docker.internal:host-gateway"}
	}

	resp, err := cli.ContainerCreate(ctx, containerCfg, hostCfg, networkingCfg, nil, "")
	if err != nil {
		return nil, fmt.Errorf("creating container: %w", err)
	}
	containerID := resp.ID
	defer func() {
		cli.ContainerRemove(context.Background(), containerID, container.RemoveOptions{Force: true})
	}()

	start := time.Now()
	if err := cli.ContainerStart(ctx, containerID, container.StartOptions{}); err != nil {
		return nil, fmt.Errorf("starting container: %w", err)
	}

	// Wait with timeout
	timeoutCtx, cancel := context.WithTimeout(ctx, opts.Timeout)
	defer cancel()

	statusCh, errCh := cli.ContainerWait(timeoutCtx, containerID, container.WaitConditionNotRunning)
	select {
	case err := <-errCh:
		if err != nil {
			// Timeout — kill the container
			cli.ContainerKill(context.Background(), containerID, "SIGKILL")
			// Drain logs
			logReader, _ := cli.ContainerLogs(context.Background(), containerID, container.LogsOptions{ShowStdout: true, ShowStderr: true})
			if logReader != nil {
				io.Copy(io.Discard, logReader)
				logReader.Close()
			}
			return &RunResult{
				ExitCode: 124,
				TimedOut: true,
				Duration: time.Since(start),
			}, nil
		}
	case status := <-statusCh:
		return &RunResult{
			ExitCode: int(status.StatusCode),
			TimedOut: false,
			Duration: time.Since(start),
		}, nil
	}
	return nil, fmt.Errorf("unexpected state")
}

// createIsolatedNetwork creates a Docker Internal network.
// Internal networks have no external connectivity by default — containers
// on them can only reach other containers on the same network and the host
// (via host.docker.internal). The gateway runs on the host, so LLM API
// calls work. Package registry access is handled by setting
// ExtraHosts on the container's HostConfig for host.docker.internal,
// allowing the container to reach a forward proxy on the host if needed.
//
// For MVP, this provides sufficient isolation: containers cannot reach
// arbitrary internet hosts. For production hardening, add a Squid
// forward proxy sidecar with a domain allowlist.
func createIsolatedNetwork(ctx context.Context, cli *client.Client) (string, error) {
	name := fmt.Sprintf("thunderdome-%d", time.Now().UnixNano())
	resp, err := cli.NetworkCreate(ctx, name, network.CreateOptions{
		Driver:   "bridge",
		Internal: true, // No external access
		Labels:   map[string]string{"thunderdome": "true"},
	})
	if err != nil {
		return "", err
	}
	return resp.ID, nil
}
```

**Step 5: Run tests**

Run: `THUNDERDOME_DOCKER_TESTS=1 go test ./internal/docker/ -v -timeout 120s`
Expected: all PASS (requires Docker running)

Run without Docker flag to verify skip: `go test ./internal/docker/ -v`
Expected: all SKIP

**Step 6: Commit**

```bash
git add internal/docker/ go.mod go.sum
git commit -m "feat: Docker container runner with timeout and cleanup"
```

---

### Task 7: LiteLLM Gateway Manager

**Files:**
- Create: `internal/gateway/gateway.go`
- Create: `internal/gateway/gateway_test.go`

**Dependencies:** Task 1

The gateway manager starts/stops a LiteLLM process and provides the URL for adapters. Tests use a mock HTTP server since we don't want to depend on LiteLLM being installed for unit tests.

**Step 1: Write failing tests**

`internal/gateway/gateway_test.go`:
```go
package gateway_test

import (
	"net"
	"testing"

	"github.com/signalnine/thunderdome/internal/gateway"
)

func TestFindFreePort(t *testing.T) {
	port, err := gateway.FindFreePort()
	if err != nil {
		t.Fatalf("FindFreePort: %v", err)
	}
	if port < 1024 || port > 65535 {
		t.Errorf("port out of range: %d", port)
	}
	// Verify port is actually free
	ln, err := net.Listen("tcp", fmt.Sprintf(":%d", port))
	if err != nil {
		t.Errorf("port %d not free: %v", port, err)
	} else {
		ln.Close()
	}
}

func TestGatewayURL(t *testing.T) {
	gw := &gateway.Gateway{Port: 8080}
	if gw.URL() != "http://localhost:8080" {
		t.Errorf("got %q, want %q", gw.URL(), "http://localhost:8080")
	}
}

func TestParseUsageLogs(t *testing.T) {
	dir := t.TempDir()
	logContent := `{"model":"claude-opus-4-6","provider":"anthropic","input_tokens":4200,"output_tokens":1800}
{"model":"codex-max","provider":"openai","input_tokens":1000,"output_tokens":500}
some non-json startup noise
`
	logPath := filepath.Join(dir, "proxy-log.jsonl")
	os.WriteFile(logPath, []byte(logContent), 0o644)
	records, err := gateway.ParseUsageLogs(logPath)
	if err != nil {
		t.Fatalf("ParseUsageLogs: %v", err)
	}
	if len(records) != 2 {
		t.Fatalf("expected 2 records, got %d", len(records))
	}
	inTok, outTok := gateway.TotalUsage(records)
	if inTok != 5200 {
		t.Errorf("input tokens: got %d, want 5200", inTok)
	}
	if outTok != 2300 {
		t.Errorf("output tokens: got %d, want 2300", outTok)
	}
}
```

Add missing imports: `"fmt"`, `"os"`, `"path/filepath"` in the test file.

**Step 2: Run tests to verify they fail**

Run: `go test ./internal/gateway/ -v`
Expected: FAIL — package doesn't exist

**Step 3: Implement gateway manager**

`internal/gateway/gateway.go`:
```go
package gateway

import (
	"context"
	"encoding/json"
	"fmt"
	"net"
	"os"
	"os/exec"
	"time"
)

type Gateway struct {
	Port    int
	cmd     *exec.Cmd
	logFile *os.File
}

type StartOpts struct {
	SecretsEnvFile string
	LogDir         string
	BudgetUSD      float64
}

func FindFreePort() (int, error) {
	ln, err := net.Listen("tcp", ":0")
	if err != nil {
		return 0, fmt.Errorf("finding free port: %w", err)
	}
	port := ln.Addr().(*net.TCPAddr).Port
	ln.Close()
	return port, nil
}

func (g *Gateway) URL() string {
	return fmt.Sprintf("http://localhost:%d", g.Port)
}

func Start(ctx context.Context, opts *StartOpts) (*Gateway, error) {
	port, err := FindFreePort()
	if err != nil {
		return nil, err
	}

	logPath := fmt.Sprintf("%s/litellm-%d.log", opts.LogDir, port)
	os.MkdirAll(opts.LogDir, 0o755)
	logFile, err := os.Create(logPath)
	if err != nil {
		return nil, fmt.Errorf("creating log file: %w", err)
	}

	cmd := exec.CommandContext(ctx, "litellm", "--port", fmt.Sprintf("%d", port))
	cmd.Stdout = logFile
	cmd.Stderr = logFile

	// Load secrets from env file if specified
	cmd.Env = os.Environ()
	if opts.SecretsEnvFile != "" {
		data, err := os.ReadFile(opts.SecretsEnvFile)
		if err == nil {
			// Simple line-by-line KEY=VALUE parsing
			for _, line := range splitLines(data) {
				if len(line) > 0 && line[0] != '#' {
					cmd.Env = append(cmd.Env, string(line))
				}
			}
		}
	}

	if err := cmd.Start(); err != nil {
		logFile.Close()
		return nil, fmt.Errorf("starting litellm: %w", err)
	}

	// Wait for the server to be ready
	if err := waitForPort(port, 30*time.Second); err != nil {
		cmd.Process.Kill()
		logFile.Close()
		return nil, fmt.Errorf("litellm did not start: %w", err)
	}

	return &Gateway{Port: port, cmd: cmd, logFile: logFile}, nil
}

func (g *Gateway) Stop() error {
	if g.cmd != nil && g.cmd.Process != nil {
		g.cmd.Process.Kill()
		g.cmd.Wait()
	}
	if g.logFile != nil {
		g.logFile.Close()
	}
	return nil
}

// UsageRecord represents one LLM API call extracted from gateway logs.
type UsageRecord struct {
	Provider     string `json:"provider"`
	Model        string `json:"model"`
	InputTokens  int    `json:"input_tokens"`
	OutputTokens int    `json:"output_tokens"`
}

// ParseUsageLogs reads a LiteLLM log file (JSONL) and returns per-request usage.
// Each trial gets its own log file, keyed by orchestrator/task/trial to avoid
// concurrency issues when running parallel trials against a shared gateway.
func ParseUsageLogs(logPath string) ([]UsageRecord, error) {
	data, err := os.ReadFile(logPath)
	if err != nil {
		return nil, fmt.Errorf("reading gateway log: %w", err)
	}
	var records []UsageRecord
	for _, line := range splitLines(data) {
		if len(line) == 0 {
			continue
		}
		var rec UsageRecord
		if err := json.Unmarshal(line, &rec); err != nil {
			continue // skip non-JSON lines (startup messages, etc.)
		}
		if rec.Model != "" {
			records = append(records, rec)
		}
	}
	return records, nil
}

// TotalUsage sums token counts across all records.
func TotalUsage(records []UsageRecord) (inputTokens, outputTokens int) {
	for _, r := range records {
		inputTokens += r.InputTokens
		outputTokens += r.OutputTokens
	}
	return
}

func waitForPort(port int, timeout time.Duration) error {
	deadline := time.Now().Add(timeout)
	for time.Now().Before(deadline) {
		conn, err := net.DialTimeout("tcp", fmt.Sprintf("localhost:%d", port), time.Second)
		if err == nil {
			conn.Close()
			return nil
		}
		time.Sleep(500 * time.Millisecond)
	}
	return fmt.Errorf("port %d not ready after %s", port, timeout)
}

func splitLines(data []byte) [][]byte {
	var lines [][]byte
	start := 0
	for i, b := range data {
		if b == '\n' {
			lines = append(lines, data[start:i])
			start = i + 1
		}
	}
	if start < len(data) {
		lines = append(lines, data[start:])
	}
	return lines
}
```

**Step 4: Run tests**

Run: `go test ./internal/gateway/ -v`
Expected: all PASS

**Step 5: Commit**

```bash
git add internal/gateway/
git commit -m "feat: LiteLLM gateway manager with dynamic port allocation"
```

---

### Task 8: Trial Runner

**Files:**
- Create: `internal/runner/trial.go`
- Create: `internal/runner/trial_test.go`

**Dependencies:** Task 4, Task 5, Task 6

The trial runner orchestrates a single trial: clone → container → collect results. Unit tests mock the Docker and git layers.

**Step 1: Write failing tests**

`internal/runner/trial_test.go`:
```go
package runner_test

import (
	"testing"

	"github.com/signalnine/thunderdome/internal/config"
	"github.com/signalnine/thunderdome/internal/runner"
)

func TestExitReasonFromCode(t *testing.T) {
	tests := []struct {
		code     int
		timedOut bool
		want     string
	}{
		{0, false, "completed"},
		{1, false, "crashed"},
		{2, false, "gave_up"},
		{124, true, "timeout"},
		{42, false, "crashed"},
	}
	for _, tt := range tests {
		got := runner.ExitReasonFromCode(tt.code, tt.timedOut)
		if got != tt.want {
			t.Errorf("ExitReasonFromCode(%d, %v) = %q, want %q", tt.code, tt.timedOut, got, tt.want)
		}
	}
}

func TestBuildAdapterCommand(t *testing.T) {
	orch := &config.Orchestrator{
		Name:    "test",
		Adapter: "./adapters/test.sh",
		Env:     map[string]string{"FOO": "bar"},
	}
	cmd := runner.BuildAdapterCommand(orch, "/workspace", "/task.md", "http://localhost:8080")
	if len(cmd) == 0 {
		t.Fatal("expected non-empty command")
	}
}
```

**Step 2: Run tests to verify they fail**

Run: `go test ./internal/runner/ -v`
Expected: FAIL — package doesn't exist

**Step 3: Implement trial runner**

`internal/runner/trial.go`:
```go
package runner

import (
	"context"
	"fmt"
	"os"
	"path/filepath"
	"time"

	"github.com/signalnine/thunderdome/internal/config"
	"github.com/signalnine/thunderdome/internal/docker"
	"github.com/signalnine/thunderdome/internal/gateway"
	"github.com/signalnine/thunderdome/internal/gitops"
	"github.com/signalnine/thunderdome/internal/result"
)

type TrialOpts struct {
	Orchestrator *config.Orchestrator
	Task         *config.Task
	TrialNum     int
	GatewayURL   string
	GatewayAddr  string   // host:port for network isolation
	RunDir       string
	Timeout      time.Duration
	Allowlist    []string // Network allowlist from config
	CPULimit     float64
	MemoryLimit  int64
}

func ExitReasonFromCode(code int, timedOut bool) string {
	if timedOut {
		return "timeout"
	}
	switch code {
	case 0:
		return "completed"
	case 2:
		return "gave_up"
	default:
		return "crashed"
	}
}

func BuildAdapterCommand(orch *config.Orchestrator, taskDir, taskDesc, proxyURL string) []string {
	// The adapter script is mounted at /adapter.sh inside the container.
	// Environment variables are set via Docker env, so the script can use them directly.
	return []string{"sh", "/adapter.sh"}
}

func RunTrial(ctx context.Context, opts *TrialOpts) (*result.TrialMeta, error) {
	trialDir := result.TrialDir(opts.RunDir, opts.Orchestrator.Name, taskName(opts.Task), opts.TrialNum)
	if err := os.MkdirAll(trialDir, 0o755); err != nil {
		return nil, fmt.Errorf("creating trial dir: %w", err)
	}

	// Clone task repo
	workDir := filepath.Join(trialDir, "workspace")
	if err := gitops.CloneAndCheckout(opts.Task.Repo, opts.Task.Tag, workDir); err != nil {
		return nil, fmt.Errorf("cloning task repo: %w", err)
	}

	// Write task description
	taskDescPath := filepath.Join(trialDir, "task.md")
	// Task description comes from a TASK_DESCRIPTION file in the repo, or we create a placeholder
	taskDescInRepo := filepath.Join(workDir, "TASK.md")
	if data, err := os.ReadFile(taskDescInRepo); err == nil {
		os.WriteFile(taskDescPath, data, 0o644)
	}

	// Resolve adapter to absolute path for bind mount
	adapterAbs, err := filepath.Abs(opts.Orchestrator.Adapter)
	if err != nil {
		return nil, fmt.Errorf("resolving adapter path: %w", err)
	}

	// Build env
	env := map[string]string{
		"TASK_DIR":         "/workspace",
		"TASK_DESCRIPTION": "/task.md",
		"PROXY_URL":        opts.GatewayURL,
	}
	for k, v := range opts.Orchestrator.Env {
		env[k] = v
	}

	// Get host UID:GID so container files have correct ownership
	hostUID := fmt.Sprintf("%d:%d", os.Getuid(), os.Getgid())

	// Run container with adapter script and task desc mounted
	containerResult, err := docker.RunContainer(ctx, &docker.RunOpts{
		Image:   opts.Orchestrator.Image,
		Command: BuildAdapterCommand(opts.Orchestrator, "/workspace", "/task.md", opts.GatewayURL),
		WorkDir: workDir,
		Env:     env,
		Timeout: opts.Timeout,
		ExtraMounts: []docker.Mount{
			{Source: adapterAbs, Target: "/adapter.sh", ReadOnly: true},
			{Source: taskDescPath, Target: "/task.md", ReadOnly: true},
		},
		Allowlist:   opts.Allowlist,
		GatewayAddr: opts.GatewayAddr,
		CPULimit:    opts.CPULimit,
		MemoryLimit: opts.MemoryLimit,
		UserID:      hostUID,
	})
	if err != nil {
		return nil, fmt.Errorf("running container: %w", err)
	}

	// Capture changes
	diff, err := gitops.CaptureChanges(workDir)
	if err != nil {
		return nil, fmt.Errorf("capturing changes: %w", err)
	}
	os.WriteFile(filepath.Join(trialDir, "diff.patch"), diff, 0o644)

	// Extract token usage and cost from gateway logs
	// The gateway writes per-request usage to its log file.
	// We parse it here and aggregate totals for this trial's meta.
	// Extract token usage from the gateway's per-request callback log.
	// The harness configures LiteLLM with a success_callback that writes
	// JSONL to a per-trial log file (passed via LITELLM_LOG_FILE env var).
	// This avoids concurrency issues — each trial writes to its own file.
	var totalTokens int
	proxyLogPath := filepath.Join(trialDir, "proxy-log.jsonl")
	records, err := gateway.ParseUsageLogs(proxyLogPath)
	if err == nil {
		inTok, outTok := gateway.TotalUsage(records)
		totalTokens = inTok + outTok
	}
	// Note: TotalCostUSD is calculated at report time by joining
	// proxy-log.jsonl against pricing.yaml. We store raw tokens here.

	meta := &result.TrialMeta{
		Orchestrator: opts.Orchestrator.Name,
		Task:         taskName(opts.Task),
		Trial:        opts.TrialNum,
		DurationS:    int(containerResult.Duration.Seconds()),
		ExitCode:     containerResult.ExitCode,
		ExitReason:   ExitReasonFromCode(containerResult.ExitCode, containerResult.TimedOut),
		TotalTokens:  totalTokens,
		TotalCostUSD: totalCostUSD,
	}
	if err := result.WriteTrialMeta(trialDir, meta); err != nil {
		return nil, fmt.Errorf("writing meta: %w", err)
	}

	return meta, nil
}

func taskName(t *config.Task) string {
	return filepath.Base(t.Repo)
}
```

**Step 4: Run tests**

Run: `go test ./internal/runner/ -v`
Expected: all PASS

**Step 5: Commit**

```bash
git add internal/runner/
git commit -m "feat: trial runner orchestrating clone, container, and result capture"
```

---

### Task 9: Validation — Test Runner and Static Analysis

**Files:**
- Create: `internal/validation/testrunner.go`
- Create: `internal/validation/lint.go`
- Create: `internal/validation/validation_test.go`

**Dependencies:** Task 6

**Step 1: Write failing tests**

`internal/validation/validation_test.go`:
```go
package validation_test

import (
	"testing"

	"github.com/signalnine/thunderdome/internal/validation"
)

func abs(x float64) float64 {
	if x < 0 {
		return -x
	}
	return x
}

func TestParseTestOutput(t *testing.T) {
	// Simulated pytest output
	output := `===== 8 passed, 2 failed =====`
	result := validation.ParseTestResults(output, 0)
	// With exit code 0, we treat it as a pass even if output is ambiguous
	if result.Score < 0 || result.Score > 1 {
		t.Errorf("score out of range: %f", result.Score)
	}
}

func TestParseTestOutputAllPass(t *testing.T) {
	result := validation.ParseTestResults("", 0)
	if result.Score != 1.0 {
		t.Errorf("score: got %f, want 1.0", result.Score)
	}
}

func TestParseTestOutputAllFail(t *testing.T) {
	result := validation.ParseTestResults("", 1)
	if result.Score != 0.0 {
		t.Errorf("score: got %f, want 0.0", result.Score)
	}
}

func TestParseTestOutputJUnit(t *testing.T) {
	output := `<?xml version="1.0" encoding="UTF-8"?>
<testsuite name="tests" tests="10" failures="2" errors="1" time="1.234">
</testsuite>`
	result := validation.ParseTestResults(output, 1)
	// 10 tests, 2 failures, 1 error = 7 passed / 10 = 0.7
	if abs(result.Score-0.7) > 0.001 {
		t.Errorf("score: got %f, want 0.7", result.Score)
	}
}

func TestParseLintOutput(t *testing.T) {
	result := validation.ParseLintResults("5 warnings, 2 errors", 1, 3)
	// Baseline had 3 issues, now 7 — 4 new issues
	if result.NetNewIssues < 0 {
		t.Errorf("expected non-negative net new issues, got %d", result.NetNewIssues)
	}
}

func TestParseLintOutputClean(t *testing.T) {
	result := validation.ParseLintResults("", 0, 0)
	if result.Score != 1.0 {
		t.Errorf("score: got %f, want 1.0", result.Score)
	}
}
```

**Step 2: Run tests to verify they fail**

Run: `go test ./internal/validation/ -v`
Expected: FAIL — package doesn't exist

**Step 3: Implement test runner**

`internal/validation/testrunner.go`:
```go
package validation

import (
	"context"
	"fmt"
	"os/exec"
	"strings"
	"time"
)

type TestResult struct {
	Score    float64
	Output   string
	ExitCode int
}

// RunTests executes the test command in a validation container and returns results.
func RunTests(ctx context.Context, workDir, validationImage, installCmd, testCmd string) (*TestResult, error) {
	// Run install first
	if installCmd != "" {
		cmd := exec.CommandContext(ctx, "docker", "run", "--rm",
			"-v", workDir+":/workspace", "-w", "/workspace",
			validationImage, "sh", "-c", installCmd)
		cmd.CombinedOutput() // best-effort install
	}

	// Run tests
	cmd := exec.CommandContext(ctx, "docker", "run", "--rm",
		"-v", workDir+":/workspace", "-w", "/workspace",
		validationImage, "sh", "-c", testCmd)

	out, err := cmd.CombinedOutput()
	exitCode := 0
	if err != nil {
		if exitErr, ok := err.(*exec.ExitError); ok {
			exitCode = exitErr.ExitCode()
		} else {
			return nil, fmt.Errorf("running tests: %w", err)
		}
	}

	return &TestResult{
		Score:    ParseTestResults(string(out), exitCode).Score,
		Output:   string(out),
		ExitCode: exitCode,
	}, nil
}

// ParseTestResults interprets test output and exit code into a score.
func ParseTestResults(output string, exitCode int) *TestResult {
	if exitCode == 0 {
		return &TestResult{Score: 1.0, Output: output, ExitCode: exitCode}
	}
	// Try to parse pass/fail counts from common test frameworks
	score := parsePassRate(output)
	return &TestResult{Score: score, Output: output, ExitCode: exitCode}
}

func parsePassRate(output string) float64 {
	// Strategy 1: Try JUnit XML if present (most reliable).
	// Many test frameworks can output JUnit XML (pytest --junitxml, go-junit-report, jest --reporters=jest-junit).
	// Look for <testsuite> tags and extract counts.
	if strings.Contains(output, "<testsuite") {
		return parseJUnitXML(output)
	}

	// Strategy 2: Parse structured text patterns from common frameworks.
	lines := strings.Split(output, "\n")
	for _, line := range lines {
		line = strings.TrimSpace(line)
		// pytest: "X passed, Y failed"
		// go test: "ok" / "FAIL" per package, "--- FAIL:" per test
		// jest: "Tests: X passed, Y failed"
		var passed, failed int
		if n, _ := fmt.Sscanf(line, "%d passed", &passed); n == 1 {
			fmt.Sscanf(line, "%d passed, %d failed", &passed, &failed)
			total := passed + failed
			if total > 0 {
				return float64(passed) / float64(total)
			}
		}
	}
	return 0.0
}

func parseJUnitXML(output string) float64 {
	// Simple XML extraction — avoid full XML parser dependency.
	// Look for: <testsuite ... tests="N" failures="M" errors="E" ...>
	var tests, failures, errors int
	for _, line := range strings.Split(output, "\n") {
		if !strings.Contains(line, "<testsuite") {
			continue
		}
		fmt.Sscanf(extractAttr(line, "tests"), "%d", &tests)
		fmt.Sscanf(extractAttr(line, "failures"), "%d", &failures)
		fmt.Sscanf(extractAttr(line, "errors"), "%d", &errors)
		if tests > 0 {
			passed := tests - failures - errors
			if passed < 0 {
				passed = 0
			}
			return float64(passed) / float64(tests)
		}
	}
	return 0.0
}

func extractAttr(line, attr string) string {
	key := attr + `="`
	idx := strings.Index(line, key)
	if idx < 0 {
		return ""
	}
	start := idx + len(key)
	end := strings.Index(line[start:], `"`)
	if end < 0 {
		return ""
	}
	return line[start : start+end]
}
```

**Step 4: Implement lint runner**

`internal/validation/lint.go`:
```go
package validation

import (
	"context"
	"os/exec"
	"strings"
)

type LintResult struct {
	Score        float64
	Output       string
	NetNewIssues int
	ExitCode     int
}

// RunLint executes the lint command in a validation container.
func RunLint(ctx context.Context, workDir, validationImage, lintCmd string, baselineIssues int) (*LintResult, error) {
	if lintCmd == "" {
		return &LintResult{Score: 1.0}, nil
	}

	cmd := exec.CommandContext(ctx, "docker", "run", "--rm",
		"-v", workDir+":/workspace", "-w", "/workspace",
		validationImage, "sh", "-c", lintCmd)

	out, err := cmd.CombinedOutput()
	exitCode := 0
	if err != nil {
		if exitErr, ok := err.(*exec.ExitError); ok {
			exitCode = exitErr.ExitCode()
		}
	}

	return ParseLintResults(string(out), exitCode, baselineIssues), nil
}

// ParseLintResults counts issues and computes a score.
func ParseLintResults(output string, exitCode int, baselineIssues int) *LintResult {
	if exitCode == 0 && output == "" {
		return &LintResult{Score: 1.0, Output: output, ExitCode: exitCode}
	}
	// Count lines that look like lint issues (file:line: message pattern)
	totalIssues := 0
	for _, line := range strings.Split(output, "\n") {
		line = strings.TrimSpace(line)
		if line != "" && (strings.Contains(line, ": error") || strings.Contains(line, ": warning") || strings.Contains(line, "Error:") || strings.Contains(line, "Warning:")) {
			totalIssues++
		}
	}
	netNew := totalIssues - baselineIssues
	if netNew < 0 {
		netNew = 0
	}
	score := 1.0
	if netNew > 0 {
		// Penalize: each new issue reduces score. Cap at 0.
		score = 1.0 - (float64(netNew) * 0.1)
		if score < 0 {
			score = 0
		}
	}
	return &LintResult{Score: score, Output: output, NetNewIssues: netNew, ExitCode: exitCode}
}
```

**Step 5: Run tests**

Run: `go test ./internal/validation/ -v`
Expected: all PASS

**Step 6: Commit**

```bash
git add internal/validation/
git commit -m "feat: validation pipeline — test runner and static analysis"
```

---

### Task 10: Validation — LLM Rubric Judge

**Files:**
- Create: `internal/validation/rubric.go`
- Create: `internal/validation/rubric_test.go`

**Dependencies:** Task 9

**Step 1: Write failing tests**

`internal/validation/rubric_test.go`:
```go
package validation_test

import (
	"testing"

	"github.com/signalnine/thunderdome/internal/config"
	"github.com/signalnine/thunderdome/internal/validation"
)

func TestComputeRubricScore(t *testing.T) {
	rubric := []config.RubricCriterion{
		{Criterion: "Follows patterns", Weight: 2},
		{Criterion: "Minimal diff", Weight: 1},
		{Criterion: "Edge cases", Weight: 3},
	}
	scores := map[string]float64{
		"Follows patterns": 0.8,
		"Minimal diff":     1.0,
		"Edge cases":       0.6,
	}
	got := validation.ComputeRubricScore(rubric, scores)
	// (0.8*2 + 1.0*1 + 0.6*3) / (2+1+3) = (1.6 + 1.0 + 1.8) / 6 = 4.4/6 ≈ 0.733
	want := 4.4 / 6.0
	if abs(got-want) > 0.001 {
		t.Errorf("got %f, want %f", got, want)
	}
}

func TestComputeRubricScoreEmpty(t *testing.T) {
	got := validation.ComputeRubricScore(nil, nil)
	if got != 0.0 {
		t.Errorf("got %f, want 0.0", got)
	}
}

func TestMedianScore(t *testing.T) {
	tests := []struct {
		scores []float64
		want   float64
	}{
		{[]float64{0.5, 0.7, 0.6}, 0.6},
		{[]float64{0.8, 0.8, 0.9}, 0.8},
		{[]float64{1.0}, 1.0},
	}
	for _, tt := range tests {
		got := validation.MedianScore(tt.scores)
		if abs(got-tt.want) > 0.001 {
			t.Errorf("MedianScore(%v) = %f, want %f", tt.scores, got, tt.want)
		}
	}
}

func abs(x float64) float64 {
	if x < 0 {
		return -x
	}
	return x
}
```

**Step 2: Run tests to verify they fail**

Run: `go test ./internal/validation/ -v -run Rubric`
Expected: FAIL — functions don't exist

**Step 3: Implement rubric scoring**

`internal/validation/rubric.go`:
```go
package validation

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"sort"
	"strings"

	"github.com/signalnine/thunderdome/internal/config"
)

// ComputeRubricScore calculates a weighted average from per-criterion scores.
func ComputeRubricScore(rubric []config.RubricCriterion, scores map[string]float64) float64 {
	if len(rubric) == 0 {
		return 0.0
	}
	var totalWeight, weightedSum float64
	for _, r := range rubric {
		score, ok := scores[r.Criterion]
		if !ok {
			continue
		}
		weightedSum += score * r.Weight
		totalWeight += r.Weight
	}
	if totalWeight == 0 {
		return 0.0
	}
	return weightedSum / totalWeight
}

// RunRubricJudge calls the LLM gateway to evaluate a diff against a rubric.
// It runs 3 evaluations and takes the median per criterion for reproducibility.
// JudgeModel is the model used for rubric evaluation. Configurable so
// users aren't locked to a single provider. Defaults to a cheaper model.
var JudgeModel = "claude-sonnet-4-5"

func RunRubricJudge(ctx context.Context, gatewayURL string, rubric []config.RubricCriterion, diff, taskDesc string) (map[string]float64, error) {
	if len(rubric) == 0 {
		return nil, nil
	}

	// Build the evaluation prompt
	criteriaList := ""
	for _, r := range rubric {
		criteriaList += fmt.Sprintf("- %s (weight: %.0f)\n", r.Criterion, r.Weight)
	}
	prompt := fmt.Sprintf(`You are a code review judge. Score this diff against each criterion on a scale of 0.0 to 1.0.

Task description:
%s

Criteria:
%s

Diff:
%s

Respond with ONLY a JSON object mapping criterion name to score, e.g.:
{"Follows existing code patterns": 0.8, "Minimal diff": 0.9}`, taskDesc, criteriaList, diff)

	// Run 3 evaluations for reproducibility
	allScores := make(map[string][]float64)
	for i := 0; i < 3; i++ {
		scores, err := callLLMJudge(ctx, gatewayURL, prompt)
		if err != nil {
			continue // skip failed evaluations
		}
		for k, v := range scores {
			allScores[k] = append(allScores[k], v)
		}
	}

	// Take median per criterion
	result := make(map[string]float64)
	for k, v := range allScores {
		result[k] = MedianScore(v)
	}
	return result, nil
}

// callLLMJudge sends a prompt to the gateway and parses the JSON response.
func callLLMJudge(ctx context.Context, gatewayURL, prompt string) (map[string]float64, error) {
	reqBody := map[string]interface{}{
		"model":       JudgeModel,
		"temperature": 0,
		"messages": []map[string]string{
			{"role": "user", "content": prompt},
		},
	}
	bodyBytes, _ := json.Marshal(reqBody)

	req, err := http.NewRequestWithContext(ctx, "POST", gatewayURL+"/v1/chat/completions", bytes.NewReader(bodyBytes))
	if err != nil {
		return nil, err
	}
	req.Header.Set("Content-Type", "application/json")

	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()

	var result struct {
		Choices []struct {
			Message struct {
				Content string `json:"content"`
			} `json:"message"`
		} `json:"choices"`
	}
	if err := json.NewDecoder(resp.Body).Decode(&result); err != nil {
		return nil, err
	}
	if len(result.Choices) == 0 {
		return nil, fmt.Errorf("no choices in response")
	}

	// Parse JSON scores from response content
	content := result.Choices[0].Message.Content
	// Strip markdown code fences if present
	content = strings.TrimPrefix(content, "```json")
	content = strings.TrimPrefix(content, "```")
	content = strings.TrimSuffix(content, "```")
	content = strings.TrimSpace(content)

	var scores map[string]float64
	if err := json.Unmarshal([]byte(content), &scores); err != nil {
		return nil, fmt.Errorf("parsing judge response: %w", err)
	}
	return scores, nil
}

// MedianScore returns the median of a sorted slice of scores.
func MedianScore(scores []float64) float64 {
	if len(scores) == 0 {
		return 0.0
	}
	sorted := make([]float64, len(scores))
	copy(sorted, scores)
	sort.Float64s(sorted)
	mid := len(sorted) / 2
	if len(sorted)%2 == 0 {
		return (sorted[mid-1] + sorted[mid]) / 2
	}
	return sorted[mid]
}
```

**Step 4: Run tests**

Run: `go test ./internal/validation/ -v`
Expected: all PASS

**Step 5: Commit**

```bash
git add internal/validation/rubric.go internal/validation/rubric_test.go
git commit -m "feat: LLM rubric scoring with weighted averages and median aggregation"
```

---

### Task 11: Composite Scoring

**Files:**
- Create: `internal/validation/composite.go`
- Create: `internal/validation/composite_test.go`

**Dependencies:** Task 9, Task 10

**Step 1: Write failing tests**

`internal/validation/composite_test.go`:
```go
package validation_test

import (
	"testing"

	"github.com/signalnine/thunderdome/internal/config"
	"github.com/signalnine/thunderdome/internal/result"
	"github.com/signalnine/thunderdome/internal/validation"
)

func TestCompositeScore(t *testing.T) {
	scores := result.Scores{Tests: 0.9, StaticAnalysis: 0.8, Rubric: 0.7}
	weights := config.ValidationWeights{Tests: 0.5, StaticAnalysis: 0.2, Rubric: 0.3}
	got := validation.CompositeScore(scores, weights)
	// 0.9*0.5 + 0.8*0.2 + 0.7*0.3 = 0.45 + 0.16 + 0.21 = 0.82
	if abs(got-0.82) > 0.001 {
		t.Errorf("got %f, want 0.82", got)
	}
}

func TestCompositeScoreDefaultWeights(t *testing.T) {
	scores := result.Scores{Tests: 1.0, StaticAnalysis: 1.0, Rubric: 1.0}
	weights := config.ValidationWeights{} // all zero — should use defaults
	got := validation.CompositeScore(scores, weights)
	if abs(got-1.0) > 0.001 {
		t.Errorf("got %f, want 1.0", got)
	}
}
```

**Step 2: Run tests to verify they fail**

Run: `go test ./internal/validation/ -v -run Composite`
Expected: FAIL

**Step 3: Implement composite scoring**

`internal/validation/composite.go`:
```go
package validation

import (
	"github.com/signalnine/thunderdome/internal/config"
	"github.com/signalnine/thunderdome/internal/result"
)

// Default weights if not specified in config.
var DefaultWeights = config.ValidationWeights{
	Tests:          0.5,
	StaticAnalysis: 0.2,
	Rubric:         0.3,
}

func CompositeScore(scores result.Scores, weights config.ValidationWeights) float64 {
	if weights.Tests == 0 && weights.StaticAnalysis == 0 && weights.Rubric == 0 {
		weights = DefaultWeights
	}
	total := weights.Tests + weights.StaticAnalysis + weights.Rubric
	if total == 0 {
		return 0
	}
	return (scores.Tests*weights.Tests +
		scores.StaticAnalysis*weights.StaticAnalysis +
		scores.Rubric*weights.Rubric) / total
}
```

**Step 4: Run tests**

Run: `go test ./internal/validation/ -v`
Expected: all PASS

**Step 5: Commit**

```bash
git add internal/validation/composite.go internal/validation/composite_test.go
git commit -m "feat: composite scoring with configurable weights"
```

---

### Task 12: Report Generator

**Files:**
- Create: `internal/report/report.go`
- Create: `internal/report/report_test.go`

**Dependencies:** Task 4

**Step 1: Write failing tests**

`internal/report/report_test.go`:
```go
package report_test

import (
	"bytes"
	"path/filepath"
	"testing"

	"github.com/signalnine/thunderdome/internal/report"
	"github.com/signalnine/thunderdome/internal/result"
)

func TestGenerateTable(t *testing.T) {
	// Set up a fake run directory with trial metas
	base := t.TempDir()
	runDir := filepath.Join(base, "runs", "test-run")

	metas := []*result.TrialMeta{
		{Orchestrator: "orch-a", Task: "task-1", Trial: 1, CompositeScore: 0.9, TotalTokens: 1000, TotalCostUSD: 0.5, ExitReason: "completed"},
		{Orchestrator: "orch-a", Task: "task-1", Trial: 2, CompositeScore: 0.8, TotalTokens: 1200, TotalCostUSD: 0.6, ExitReason: "completed"},
		{Orchestrator: "orch-b", Task: "task-1", Trial: 1, CompositeScore: 0.7, TotalTokens: 2000, TotalCostUSD: 1.0, ExitReason: "completed"},
		{Orchestrator: "orch-b", Task: "task-1", Trial: 2, CompositeScore: 0.6, TotalTokens: 2200, TotalCostUSD: 1.1, ExitReason: "crashed"},
	}

	for _, m := range metas {
		dir := result.TrialDir(runDir, m.Orchestrator, m.Task, m.Trial)
		result.WriteTrialMeta(dir, m)
	}

	var buf bytes.Buffer
	err := report.Generate(runDir, "table", &buf)
	if err != nil {
		t.Fatalf("Generate: %v", err)
	}
	output := buf.String()
	if output == "" {
		t.Error("expected non-empty output")
	}
	// Should contain orchestrator names
	if !bytes.Contains([]byte(output), []byte("orch-a")) {
		t.Error("expected orch-a in output")
	}
	if !bytes.Contains([]byte(output), []byte("orch-b")) {
		t.Error("expected orch-b in output")
	}
}
```

**Step 2: Run tests to verify they fail**

Run: `go test ./internal/report/ -v`
Expected: FAIL

**Step 3: Implement report generator**

`internal/report/report.go`:
```go
package report

import (
	"encoding/json"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"strings"
	"text/tabwriter"

	"github.com/signalnine/thunderdome/internal/gateway"
	"github.com/signalnine/thunderdome/internal/pricing"
	"github.com/signalnine/thunderdome/internal/result"
)

type OrchestratorSummary struct {
	Name           string
	Trials         int
	PassRate       float64
	MeanScore      float64
	MeanTokens     float64
	MeanCostUSD    float64
}

// Generate reads trial results and produces a summary report.
// If pricingPath is non-empty, costs are calculated from proxy logs + pricing table.
func Generate(runDir, format string, w io.Writer, pricingPath ...string) error {
	metas, err := collectMetas(runDir)
	if err != nil {
		return err
	}

	// Enrich metas with cost data from proxy logs + pricing table
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
				return nil // skip unreadable metas
			}
			metas = append(metas, meta)
		}
		return nil
	})
	return metas, err
}

func aggregate(metas []*result.TrialMeta) []OrchestratorSummary {
	type accum struct {
		count    int
		passed   int
		score    float64
		tokens   float64
		cost     float64
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
		if m.ExitReason == "completed" {
			a.passed++
		}
	}

	// Sort orchestrators by name for deterministic output
	var summaries []OrchestratorSummary
	for name, a := range byOrch {
		summaries = append(summaries, OrchestratorSummary{
			Name:       name,
			Trials:     a.count,
			PassRate:   float64(a.passed) / float64(a.count),
			MeanScore:  a.score / float64(a.count),
			MeanTokens: a.tokens / float64(a.count),
			MeanCostUSD: a.cost / float64(a.count),
		})
	}
	return summaries
}

// enrichCosts reads proxy-log.jsonl for each trial, joins against the pricing
// table, and populates TotalCostUSD on each meta.
func enrichCosts(runDir string, metas []*result.TrialMeta, pricingPath string) {
	table, err := pricing.Load(pricingPath)
	if err != nil {
		return // pricing file missing — skip cost enrichment
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
	return tw.Flush()
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
```

**Step 4: Run tests**

Run: `go test ./internal/report/ -v`
Expected: all PASS

**Step 5: Commit**

```bash
git add internal/report/
git commit -m "feat: report generator with table, markdown, and JSON output"
```

---

### Task 13: Wire Up CLI Commands

**Files:**
- Modify: `cmd/run.go`
- Modify: `cmd/list.go`
- Modify: `cmd/report.go`
- Modify: `cmd/validate.go`

**Dependencies:** Task 3, Task 4, Task 7, Task 8, Task 12

**Step 1: Implement `thunderdome list`**

Update `cmd/list.go` to load config and print orchestrators and tasks:

```go
func newListCmd() *cobra.Command {
	return &cobra.Command{
		Use:   "list",
		Short: "List available tasks and orchestrators",
		RunE: func(cmd *cobra.Command, args []string) error {
			cfg, err := config.Load(cfgFile)
			if err != nil {
				return err
			}
			fmt.Println("Orchestrators:")
			for _, o := range cfg.Orchestrators {
				fmt.Printf("  - %s (image: %s)\n", o.Name, o.Image)
			}
			fmt.Println("\nTasks:")
			for _, t := range cfg.Tasks {
				fmt.Printf("  - %s@%s [%s]\n", t.Repo, t.Tag, t.Category)
			}
			return nil
		},
	}
}
```

**Step 2: Implement `thunderdome report`**

Update `cmd/report.go`:

```go
func newReportCmd() *cobra.Command {
	cmd := &cobra.Command{
		Use:   "report [run-dir]",
		Short: "Generate summary from stored results",
		RunE: func(cmd *cobra.Command, args []string) error {
			cfg, err := config.Load(cfgFile)
			if err != nil {
				return err
			}
			runDir := filepath.Join(cfg.Results.Dir, "latest")
			if len(args) > 0 {
				runDir = args[0]
			}
			// Resolve symlink
			resolved, err := filepath.EvalSymlinks(runDir)
			if err != nil {
				return fmt.Errorf("resolving run dir: %w", err)
			}
			return report.Generate(resolved, flagFormat, os.Stdout)
		},
	}
	cmd.Flags().StringVar(&flagFormat, "format", "table", "output format (table, markdown, json)")
	return cmd
}
```

**Step 3: Implement `thunderdome run` (serial mode)**

Update `cmd/run.go` with the full run loop. This wires together config loading, gateway start, trial execution, and validation. For now, serial execution only (parallel comes in Task 14).

```go
func newRunCmd() *cobra.Command {
	// ... (flag definitions same as before)
	cmd := &cobra.Command{
		Use:   "run",
		Short: "Execute a benchmark run",
		RunE:  runBenchmark,
	}
	// ... (flags same as before)
	return cmd
}

func runBenchmark(cmd *cobra.Command, args []string) error {
	cfg, err := config.Load(cfgFile)
	if err != nil {
		return err
	}
	if flagTrials > 0 {
		cfg.Trials = flagTrials
	}

	// Filter orchestrators/tasks if flags set
	orchestrators := filterOrchestrators(cfg.Orchestrators, flagOrchestrator)
	tasks := filterTasks(cfg.Tasks, flagTask, flagCategory)

	// Create run directory
	runDir, err := result.CreateRunDir(cfg.Results.Dir)
	if err != nil {
		return err
	}
	fmt.Printf("Run directory: %s\n", runDir)

	ctx := context.Background()

	// Start gateway
	gw, err := gateway.Start(ctx, &gateway.StartOpts{
		SecretsEnvFile: cfg.Secrets.EnvFile,
		LogDir:         cfg.Proxy.LogDir,
		BudgetUSD:      cfg.Proxy.BudgetPerTrialUSD,
	})
	if err != nil {
		return fmt.Errorf("starting gateway: %w", err)
	}
	defer gw.Stop()

	// Run trials
	for _, orch := range orchestrators {
		for _, task := range tasks {
			for trial := 1; trial <= cfg.Trials; trial++ {
				fmt.Printf("Running %s × %s (trial %d/%d)...\n", orch.Name, task.Category, trial, cfg.Trials)
				meta, err := runner.RunTrial(ctx, &runner.TrialOpts{
					Orchestrator: &orch,
					Task:         &task,
					TrialNum:     trial,
					GatewayURL:   gw.URL(),
					RunDir:       runDir,
					Timeout:      timeoutForCategory(task.Category),
				})
				if err != nil {
					fmt.Printf("  ERROR: %v\n", err)
					continue
				}
				fmt.Printf("  %s (exit: %s, duration: %ds)\n", meta.ExitReason, meta.ExitReason, meta.DurationS)
			}
		}
	}

	// Print summary
	fmt.Println("\n--- Results ---")
	return report.Generate(runDir, "table", os.Stdout)
}
```

Include helper functions `filterOrchestrators`, `filterTasks`, `timeoutForCategory` in `cmd/run.go`.

**Step 4: Build and smoke test**

Run: `go build -o thunderdome .`
Expected: builds successfully

Run: `./thunderdome list --config testdata/minimal.yaml`
Expected: prints orchestrator and task lists

**Step 5: Commit**

```bash
git add cmd/
git commit -m "feat: wire up CLI commands — list, run, report, validate"
```

---

### Task 14: Worker Pool for Parallel Execution

**Files:**
- Create: `internal/runner/pool.go`
- Create: `internal/runner/pool_test.go`
- Modify: `cmd/run.go`

**Dependencies:** Task 8, Task 13

**Step 1: Write failing tests**

`internal/runner/pool_test.go`:
```go
package runner_test

import (
	"sync/atomic"
	"testing"

	"github.com/signalnine/thunderdome/internal/runner"
)

func TestPool(t *testing.T) {
	var count atomic.Int32
	jobs := make([]runner.Job, 10)
	for i := range jobs {
		jobs[i] = func() error {
			count.Add(1)
			return nil
		}
	}
	errs := runner.RunPool(3, jobs)
	if len(errs) != 0 {
		t.Errorf("expected no errors, got %v", errs)
	}
	if count.Load() != 10 {
		t.Errorf("expected 10 jobs, got %d", count.Load())
	}
}

func TestPoolWithErrors(t *testing.T) {
	jobs := []runner.Job{
		func() error { return nil },
		func() error { return fmt.Errorf("fail") },
		func() error { return nil },
	}
	errs := runner.RunPool(2, jobs)
	if len(errs) != 1 {
		t.Errorf("expected 1 error, got %d", len(errs))
	}
}
```

Add missing import `"fmt"`.

**Step 2: Run tests to verify they fail**

Run: `go test ./internal/runner/ -v -run Pool`
Expected: FAIL

**Step 3: Implement worker pool**

`internal/runner/pool.go`:
```go
package runner

import "sync"

type Job func() error

// RunPool executes jobs with at most maxWorkers concurrently. Returns all errors.
func RunPool(maxWorkers int, jobs []Job) []error {
	if maxWorkers < 1 {
		maxWorkers = 1
	}

	var (
		mu   sync.Mutex
		errs []error
		wg   sync.WaitGroup
	)
	sem := make(chan struct{}, maxWorkers)

	for _, job := range jobs {
		wg.Add(1)
		sem <- struct{}{}
		go func(j Job) {
			defer wg.Done()
			defer func() { <-sem }()
			if err := j(); err != nil {
				mu.Lock()
				errs = append(errs, err)
				mu.Unlock()
			}
		}(job)
	}
	wg.Wait()
	return errs
}
```

**Step 4: Run tests**

Run: `go test ./internal/runner/ -v`
Expected: all PASS

**Step 5: Update `cmd/run.go` to use pool when `--parallel > 1`**

Wire the pool into the run loop: build a slice of `Job` closures (one per trial), then dispatch them through `runner.RunPool(flagParallel, jobs)`.

**IMPORTANT:** When building Job closures inside for-range loops, capture loop variables by value to avoid the classic Go closure bug. Either use Go 1.22+ (which fixes this by default) or explicitly copy:

```go
var jobs []runner.Job
for _, orch := range orchestrators {
	for _, task := range tasks {
		for trial := 1; trial <= cfg.Trials; trial++ {
			// Capture loop variables by value
			orch, task, trial := orch, task, trial
			jobs = append(jobs, func() error {
				_, err := runner.RunTrial(ctx, &runner.TrialOpts{
					Orchestrator: &orch,
					Task:         &task,
					TrialNum:     trial,
					GatewayURL:   gw.URL(),
					GatewayAddr:  fmt.Sprintf("localhost:%d", gw.Port),
					RunDir:       runDir,
					Timeout:      timeoutForCategory(task.Category),
					Allowlist:    cfg.Network.Allowlist,
				})
				return err
			})
		}
	}
}
errs := runner.RunPool(flagParallel, jobs)
```

**Step 6: Build**

Run: `go build -o thunderdome .`
Expected: builds

**Step 7: Commit**

```bash
git add internal/runner/pool.go internal/runner/pool_test.go cmd/run.go
git commit -m "feat: worker pool for parallel trial execution"
```

---

### Task 15: Pricing and Cost Reporting

**Files:**
- Create: `internal/pricing/pricing.go`
- Create: `internal/pricing/pricing_test.go`
- Create: `pricing.yaml` (example)

**Dependencies:** Task 4

**Step 1: Write failing tests**

`internal/pricing/pricing_test.go`:
```go
package pricing_test

import (
	"os"
	"path/filepath"
	"testing"

	"github.com/signalnine/thunderdome/internal/pricing"
)

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
	// (1000/1000) * 0.015 + (500/1000) * 0.075 = 0.015 + 0.0375 = 0.0525
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

func abs(x float64) float64 {
	if x < 0 {
		return -x
	}
	return x
}
```

**Step 2: Run tests to verify they fail**

Run: `go test ./internal/pricing/ -v`
Expected: FAIL

**Step 3: Implement pricing**

`internal/pricing/pricing.go`:
```go
package pricing

import (
	"fmt"
	"os"

	"gopkg.in/yaml.v3"
)

type ModelPricing struct {
	Input  float64 `yaml:"input"`
	Output float64 `yaml:"output"`
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

// Cost calculates total cost for a request. Prices are per 1K tokens.
func (t *Table) Cost(provider, model string, inputTokens, outputTokens int) float64 {
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
	// Divide by 1000 because prices are per 1K tokens
	return (float64(inputTokens)/1000.0)*p.Input + (float64(outputTokens)/1000.0)*p.Output
}
```

**Step 4: Run tests**

Run: `go test ./internal/pricing/ -v`
Expected: all PASS

**Step 5: Create example pricing.yaml**

```yaml
# pricing.yaml — cost per 1K tokens
anthropic:
  claude-opus-4-6: { input: 0.015, output: 0.075 }
  claude-sonnet-4-5: { input: 0.003, output: 0.015 }
openai:
  codex-max: { input: 0.01, output: 0.03 }
google:
  gemini-3-pro: { input: 0.007, output: 0.021 }
```

**Step 6: Commit**

```bash
git add internal/pricing/ pricing.yaml
git commit -m "feat: pricing table for cost calculation from proxy logs"
```

---

### Task 16: Integration Test with Null Adapter

**Files:**
- Create: `integration_test.go`
- Create: `testdata/echo-task/` (a minimal git repo as a test fixture)

**Dependencies:** Task 13

This test runs the full pipeline end-to-end with the null adapter against a local test task repo. It verifies the harness can clone, run a container, capture results, and produce a report. Requires Docker.

**Step 1: Create test task fixture**

Create a minimal git repo at `testdata/echo-task/` with:
- A `hello.txt` file
- A `TASK.md` describing the task
- A simple test script (`test.sh` that checks `hello.txt` exists)
- Tagged as `v1`

Script to create it:
```bash
mkdir -p testdata/echo-task && cd testdata/echo-task
git init
git config user.email "test@test.com"
git config user.name "Test"
echo "hello" > hello.txt
echo "Modify hello.txt to say goodbye" > TASK.md
echo '#!/bin/sh
test -f hello.txt' > test.sh
chmod +x test.sh
git add .
git commit -m "initial"
git tag v1
```

**Step 2: Write integration test**

`integration_test.go`:
```go
//go:build integration

package main

import (
	"context"
	"os"
	"path/filepath"
	"testing"
	"time"

	"github.com/signalnine/thunderdome/internal/config"
	"github.com/signalnine/thunderdome/internal/gitops"
	"github.com/signalnine/thunderdome/internal/result"
	"github.com/signalnine/thunderdome/internal/runner"
)

func TestNullAdapterIntegration(t *testing.T) {
	if os.Getenv("THUNDERDOME_DOCKER_TESTS") == "" {
		t.Skip("set THUNDERDOME_DOCKER_TESTS=1 to run integration tests")
	}

	// Get absolute path to test fixture
	fixtureDir, _ := filepath.Abs("testdata/echo-task")

	resultsDir := t.TempDir()
	runDir, err := result.CreateRunDir(resultsDir)
	if err != nil {
		t.Fatalf("CreateRunDir: %v", err)
	}

	orch := &config.Orchestrator{
		Name:    "null",
		Adapter: "./adapters/null.sh",
		Image:   "alpine:latest",
	}
	task := &config.Task{
		Repo:            fixtureDir,
		Tag:             "v1",
		Category:        "greenfield/simple",
		ValidationImage: "alpine:latest",
		TestCmd:         "sh test.sh",
	}

	ctx, cancel := context.WithTimeout(context.Background(), 60*time.Second)
	defer cancel()

	meta, err := runner.RunTrial(ctx, &runner.TrialOpts{
		Orchestrator: orch,
		Task:         task,
		TrialNum:     1,
		GatewayURL:   "http://localhost:0", // null adapter doesn't use it
		RunDir:       runDir,
		Timeout:      30 * time.Second,
	})
	if err != nil {
		t.Fatalf("RunTrial: %v", err)
	}
	if meta.ExitReason != "completed" {
		t.Errorf("exit_reason: got %q, want %q", meta.ExitReason, "completed")
	}
	if meta.ExitCode != 0 {
		t.Errorf("exit_code: got %d, want 0", meta.ExitCode)
	}

	// Verify meta.json was written
	metaPath := filepath.Join(result.TrialDir(runDir, "null", filepath.Base(fixtureDir), 1), "meta.json")
	if _, err := os.Stat(metaPath); os.IsNotExist(err) {
		t.Error("meta.json not created")
	}
}
```

**Step 3: Run integration test**

Run: `THUNDERDOME_DOCKER_TESTS=1 go test -tags integration -v -timeout 120s`
Expected: PASS

**Step 4: Commit**

```bash
git add integration_test.go testdata/echo-task/
git commit -m "test: end-to-end integration test with null adapter"
```

---

### Task 17: Cleanup and Final Touches

**Files:**
- Modify: `cmd/run.go` (add `--cleanup-aggressive` flag)
- Modify: `.gitignore`
- Create: `thunderdome.yaml` (example config)

**Dependencies:** Task 13, Task 14, Task 15, Task 16

**Step 1: Add cleanup flag to run command**

Add `--cleanup-aggressive` flag to `cmd/run.go`. After the run completes, if the flag is set, prune all `thunderdome`-labeled Docker containers and dangling images.

```go
// In runBenchmark, after all trials:
if flagCleanupAggressive {
    exec.Command("docker", "container", "prune", "-f", "--filter", "label=thunderdome=true").Run()
    exec.Command("docker", "image", "prune", "-f").Run()
}
```

**Step 2: Create example thunderdome.yaml**

Use the config format from the design doc with the null adapter as a working example:

```yaml
orchestrators:
  - name: "null"
    adapter: ./adapters/null.sh
    image: alpine:latest

tasks:
  - repo: ./testdata/echo-task
    tag: v1
    category: greenfield/simple
    validation_image: alpine:latest
    test_cmd: "sh test.sh"

trials: 1

proxy:
  gateway: litellm
  log_dir: ./results/proxy-logs
  budget_per_trial_usd: 5.00

results:
  dir: ./results
```

**Step 3: Build final binary**

Run: `go build -o thunderdome .`
Expected: builds successfully

**Step 4: Run all tests**

Run: `go test ./... -v`
Expected: all PASS (non-Docker tests)

Run: `THUNDERDOME_DOCKER_TESTS=1 go test ./... -tags integration -v -timeout 300s`
Expected: all PASS (with Docker)

**Step 5: Commit**

```bash
git add cmd/run.go .gitignore thunderdome.yaml
git commit -m "feat: cleanup flag, example config, and final polish"
```
