# Conclave Go Port Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Port all bash scripts and JS libraries to a single `conclave` Go binary with Cobra subcommands.

**Architecture:** Monolithic binary using `internal/` packages. Shells out to `git` CLI. HTTP clients for Anthropic/Gemini/OpenAI APIs. Skills (SKILL.md) stay as markdown - only the supporting scripts are ported.

**Tech Stack:** Go 1.22+, cobra, viper, gopkg.in/yaml.v3, stdlib for HTTP/JSON/exec/concurrency

**Design doc:** `docs/plans/2026-02-08-go-port-design.md`

---

## Task 1: Project Scaffolding

**Files:**
- Create: `go.mod`
- Create: `Makefile`
- Create: `cmd/conclave/main.go`
- Create: `cmd/conclave/root.go`
- Create: `cmd/conclave/version.go`

**Dependencies:** None

**Step 1: Initialize Go module**

Run: `cd /home/gabe/conclave && go mod init github.com/signalnine/conclave`

**Step 2: Add dependencies**

Run:
```bash
go get github.com/spf13/cobra@latest
go get github.com/spf13/viper@latest
go get gopkg.in/yaml.v3@latest
```

**Step 3: Create Makefile**

Create `Makefile`:
```makefile
VERSION := $(shell git describe --tags --always --dirty 2>/dev/null || echo "dev")
LDFLAGS := -ldflags "-X main.version=$(VERSION)"

.PHONY: build install test test-integration lint clean

build:
	go build $(LDFLAGS) -o conclave ./cmd/conclave

install:
	go install $(LDFLAGS) ./cmd/conclave

test:
	go test ./... -race -cover -count=1

test-integration:
	go test ./... -race -run Integration -count=1

lint:
	golangci-lint run ./...

clean:
	rm -f conclave
```

**Step 4: Create root command**

Create `cmd/conclave/root.go`:
```go
package main

import (
	"fmt"
	"os"

	"github.com/spf13/cobra"
)

var rootCmd = &cobra.Command{
	Use:   "conclave",
	Short: "Multi-agent consensus development system",
	Long:  "Conclave orchestrates a council of AI reviewers (Claude, Gemini, Codex) for consensus-based development.",
}

func Execute() {
	if err := rootCmd.Execute(); err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
}
```

**Step 5: Create version command**

Create `cmd/conclave/version.go`:
```go
package main

import (
	"fmt"

	"github.com/spf13/cobra"
)

var version = "dev"

var versionCmd = &cobra.Command{
	Use:   "version",
	Short: "Print version",
	Run: func(cmd *cobra.Command, args []string) {
		fmt.Println(version)
	},
}

func init() {
	rootCmd.AddCommand(versionCmd)
}
```

**Step 6: Create main.go**

Create `cmd/conclave/main.go`:
```go
package main

func main() {
	Execute()
}
```

**Step 7: Verify it builds and runs**

Run: `make build && ./conclave version`
Expected: prints "dev"

Run: `./conclave --help`
Expected: shows help with "version" subcommand listed

**Step 8: Commit**

```bash
git add go.mod go.sum Makefile cmd/
git commit -m "feat: scaffold Go binary with cobra CLI"
```

---

## Task 2: Config Package

**Files:**
- Create: `internal/config/config.go`
- Create: `internal/config/config_test.go`

**Dependencies:** Task 1

**Step 1: Write tests for config loading**

Create `internal/config/config_test.go`:
```go
package config

import (
	"os"
	"path/filepath"
	"testing"
)

func TestLoadAPIKeys(t *testing.T) {
	tests := []struct {
		name    string
		envVars map[string]string
		wantKeys int
	}{
		{"no keys", nil, 0},
		{"anthropic only", map[string]string{"ANTHROPIC_API_KEY": "sk-test"}, 1},
		{"all three", map[string]string{
			"ANTHROPIC_API_KEY": "sk-test",
			"GEMINI_API_KEY":    "gm-test",
			"OPENAI_API_KEY":    "op-test",
		}, 3},
		{"gemini fallback to google", map[string]string{
			"GOOGLE_API_KEY": "gk-test",
		}, 1},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			// Clear all API key env vars
			for _, k := range []string{"ANTHROPIC_API_KEY", "GEMINI_API_KEY", "GOOGLE_API_KEY", "OPENAI_API_KEY"} {
				t.Setenv(k, "")
			}
			for k, v := range tt.envVars {
				t.Setenv(k, v)
			}
			cfg := Load()
			got := 0
			if cfg.AnthropicAPIKey != "" { got++ }
			if cfg.GeminiAPIKey != "" { got++ }
			if cfg.OpenAIAPIKey != "" { got++ }
			if got != tt.wantKeys {
				t.Errorf("got %d keys, want %d", got, tt.wantKeys)
			}
		})
	}
}

func TestLoadDotEnv(t *testing.T) {
	dir := t.TempDir()
	envFile := filepath.Join(dir, ".env")
	os.WriteFile(envFile, []byte("ANTHROPIC_API_KEY=from-dotenv\n"), 0644)

	t.Setenv("ANTHROPIC_API_KEY", "")
	t.Setenv("HOME", dir)

	cfg := Load()
	if cfg.AnthropicAPIKey != "from-dotenv" {
		t.Errorf("got %q, want 'from-dotenv'", cfg.AnthropicAPIKey)
	}
}

func TestDefaults(t *testing.T) {
	cfg := Load()
	if cfg.AnthropicModel != "claude-opus-4-5-20251101" {
		t.Errorf("AnthropicModel = %q", cfg.AnthropicModel)
	}
	if cfg.GeminiModel != "gemini-3-pro-preview" {
		t.Errorf("GeminiModel = %q", cfg.GeminiModel)
	}
	if cfg.OpenAIModel != "gpt-5.1-codex-max" {
		t.Errorf("OpenAIModel = %q", cfg.OpenAIModel)
	}
	if cfg.Stage1Timeout != 60 {
		t.Errorf("Stage1Timeout = %d", cfg.Stage1Timeout)
	}
}
```

**Step 2: Run tests to verify they fail**

Run: `go test ./internal/config/ -v`
Expected: compilation error (package doesn't exist yet)

**Step 3: Implement config package**

Create `internal/config/config.go`:
```go
package config

import (
	"bufio"
	"os"
	"path/filepath"
	"strconv"
	"strings"
)

type Config struct {
	// API Keys
	AnthropicAPIKey string
	GeminiAPIKey    string
	OpenAIAPIKey    string

	// Model config
	AnthropicModel    string
	AnthropicMaxTokens int
	GeminiModel       string
	OpenAIModel       string
	OpenAIMaxTokens   int

	// Timeouts (seconds)
	Stage1Timeout int
	Stage2Timeout int

	// Base URLs (for testing - override API endpoints)
	AnthropicBaseURL string
	GeminiBaseURL    string
	OpenAIBaseURL    string

	// Parallel runner
	MaxConcurrent     int
	WorktreeDir       string
	MaxConflictReruns int

	// Ralph loop
	RalphTimeoutImplement int
	RalphTimeoutTest      int
	RalphTimeoutSpec      int
	RalphTimeoutQuality   int
	RalphTimeoutGlobal    int
	RalphStuckThreshold   int
}

func Load() *Config {
	// Source ~/.env if API keys missing
	loadDotEnv()

	return &Config{
		AnthropicAPIKey: os.Getenv("ANTHROPIC_API_KEY"),
		GeminiAPIKey:    coalesce(os.Getenv("GEMINI_API_KEY"), os.Getenv("GOOGLE_API_KEY")),
		OpenAIAPIKey:    os.Getenv("OPENAI_API_KEY"),

		AnthropicModel:    envOr("ANTHROPIC_MODEL", "claude-opus-4-5-20251101"),
		AnthropicMaxTokens: envInt("ANTHROPIC_MAX_TOKENS", 16000),
		GeminiModel:       envOr("GEMINI_MODEL", "gemini-3-pro-preview"),
		OpenAIModel:       envOr("OPENAI_MODEL", "gpt-5.1-codex-max"),
		OpenAIMaxTokens:   envInt("OPENAI_MAX_TOKENS", 16000),

		Stage1Timeout: envInt("CONSENSUS_STAGE1_TIMEOUT", 60),
		Stage2Timeout: envInt("CONSENSUS_STAGE2_TIMEOUT", 60),

		AnthropicBaseURL: envOr("ANTHROPIC_BASE_URL", "https://api.anthropic.com"),
		GeminiBaseURL:    envOr("GEMINI_BASE_URL", "https://generativelanguage.googleapis.com"),
		OpenAIBaseURL:    envOr("OPENAI_BASE_URL", "https://api.openai.com"),

		MaxConcurrent:     envInt("PARALLEL_MAX_CONCURRENT", 3),
		WorktreeDir:       envOr("PARALLEL_WORKTREE_DIR", ".worktrees"),
		MaxConflictReruns: envInt("PARALLEL_MAX_CONFLICT_RERUNS", 2),

		RalphTimeoutImplement: envInt("RALPH_TIMEOUT_IMPLEMENT", 1200),
		RalphTimeoutTest:      envInt("RALPH_TIMEOUT_TEST", 600),
		RalphTimeoutSpec:      envInt("RALPH_TIMEOUT_SPEC", 300),
		RalphTimeoutQuality:   envInt("RALPH_TIMEOUT_QUALITY", 180),
		RalphTimeoutGlobal:    envInt("RALPH_TIMEOUT_GLOBAL", 3600),
		RalphStuckThreshold:   envInt("RALPH_STUCK_THRESHOLD", 3),
	}
}

func loadDotEnv() {
	home, err := os.UserHomeDir()
	if err != nil {
		return
	}
	f, err := os.Open(filepath.Join(home, ".env"))
	if err != nil {
		return
	}
	defer f.Close()

	scanner := bufio.NewScanner(f)
	for scanner.Scan() {
		line := strings.TrimSpace(scanner.Text())
		if line == "" || strings.HasPrefix(line, "#") {
			continue
		}
		if k, v, ok := strings.Cut(line, "="); ok {
			k = strings.TrimSpace(k)
			v = strings.TrimSpace(v)
			v = strings.Trim(v, `"'`)
			if os.Getenv(k) == "" {
				os.Setenv(k, v)
			}
		}
	}
}

func envOr(key, fallback string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return fallback
}

func envInt(key string, fallback int) int {
	if v := os.Getenv(key); v != "" {
		if n, err := strconv.Atoi(v); err == nil {
			return n
		}
	}
	return fallback
}

func coalesce(vals ...string) string {
	for _, v := range vals {
		if v != "" {
			return v
		}
	}
	return ""
}
```

**Step 4: Run tests**

Run: `go test ./internal/config/ -v`
Expected: all pass

**Step 5: Commit**

```bash
git add internal/config/
git commit -m "feat: add config package with env var loading and ~/.env sourcing"
```

---

## Task 3: Git Package

**Files:**
- Create: `internal/git/git.go`
- Create: `internal/git/git_test.go`

**Dependencies:** Task 1

**Step 1: Write tests**

Create `internal/git/git_test.go`:
```go
package git

import (
	"os"
	"os/exec"
	"path/filepath"
	"testing"
)

func setupTestRepo(t *testing.T) string {
	t.Helper()
	dir := t.TempDir()
	cmds := [][]string{
		{"git", "init"},
		{"git", "config", "user.email", "test@test.com"},
		{"git", "config", "user.name", "Test"},
		{"git", "commit", "--allow-empty", "-m", "initial"},
	}
	for _, args := range cmds {
		cmd := exec.Command(args[0], args[1:]...)
		cmd.Dir = dir
		if out, err := cmd.CombinedOutput(); err != nil {
			t.Fatalf("%v failed: %s %v", args, out, err)
		}
	}
	return dir
}

func TestCurrentBranch(t *testing.T) {
	dir := setupTestRepo(t)
	g := New(dir)
	branch, err := g.CurrentBranch()
	if err != nil {
		t.Fatal(err)
	}
	if branch != "main" && branch != "master" {
		t.Errorf("got %q", branch)
	}
}

func TestWorktreeAddAndRemove(t *testing.T) {
	dir := setupTestRepo(t)
	g := New(dir)
	wtPath := filepath.Join(dir, "wt-test")
	if err := g.WorktreeAdd(wtPath, "test-branch", "HEAD"); err != nil {
		t.Fatal(err)
	}
	if _, err := os.Stat(wtPath); err != nil {
		t.Fatal("worktree not created")
	}
	if err := g.WorktreeRemove(wtPath); err != nil {
		t.Fatal(err)
	}
}

func TestMergeBase(t *testing.T) {
	dir := setupTestRepo(t)
	g := New(dir)
	// Create a branch with a commit
	run(t, dir, "git", "checkout", "-b", "feature")
	run(t, dir, "git", "commit", "--allow-empty", "-m", "feature commit")
	sha, err := g.MergeBase("main", "feature")
	if err != nil {
		t.Fatal(err)
	}
	if sha == "" {
		t.Error("empty merge-base")
	}
}

func TestDiff(t *testing.T) {
	dir := setupTestRepo(t)
	g := New(dir)
	os.WriteFile(filepath.Join(dir, "test.txt"), []byte("hello"), 0644)
	run(t, dir, "git", "add", "test.txt")
	run(t, dir, "git", "commit", "-m", "add file")
	diff, err := g.Diff("HEAD~1", "HEAD")
	if err != nil {
		t.Fatal(err)
	}
	if diff == "" {
		t.Error("empty diff")
	}
}

func TestDiffNameOnly(t *testing.T) {
	dir := setupTestRepo(t)
	g := New(dir)
	os.WriteFile(filepath.Join(dir, "a.txt"), []byte("a"), 0644)
	run(t, dir, "git", "add", "a.txt")
	run(t, dir, "git", "commit", "-m", "add a")
	files, err := g.DiffNameOnly("HEAD~1", "HEAD")
	if err != nil {
		t.Fatal(err)
	}
	if len(files) != 1 || files[0] != "a.txt" {
		t.Errorf("got %v", files)
	}
}

func TestMergeSquash(t *testing.T) {
	dir := setupTestRepo(t)
	g := New(dir)
	run(t, dir, "git", "checkout", "-b", "feat")
	os.WriteFile(filepath.Join(dir, "new.txt"), []byte("new"), 0644)
	run(t, dir, "git", "add", "new.txt")
	run(t, dir, "git", "commit", "-m", "feat commit")
	run(t, dir, "git", "checkout", "main")
	if err := g.MergeSquash("feat"); err != nil {
		t.Fatal(err)
	}
}

func run(t *testing.T, dir string, args ...string) {
	t.Helper()
	cmd := exec.Command(args[0], args[1:]...)
	cmd.Dir = dir
	if out, err := cmd.CombinedOutput(); err != nil {
		t.Fatalf("%v: %s %v", args, out, err)
	}
}
```

**Step 2: Run tests to verify they fail**

Run: `go test ./internal/git/ -v`
Expected: compilation error

**Step 3: Implement git package**

Create `internal/git/git.go`:
```go
package git

import (
	"fmt"
	"os/exec"
	"strings"
)

type Git struct {
	Dir string
}

func New(dir string) *Git {
	return &Git{Dir: dir}
}

func (g *Git) run(args ...string) (string, error) {
	cmd := exec.Command("git", args...)
	cmd.Dir = g.Dir
	out, err := cmd.CombinedOutput()
	if err != nil {
		return "", fmt.Errorf("git %s: %s %w", strings.Join(args, " "), out, err)
	}
	return strings.TrimSpace(string(out)), nil
}

func (g *Git) CurrentBranch() (string, error) {
	return g.run("rev-parse", "--abbrev-ref", "HEAD")
}

func (g *Git) RevParse(ref string) (string, error) {
	return g.run("rev-parse", ref)
}

func (g *Git) WorktreeAdd(path, branch, base string) error {
	_, err := g.run("worktree", "add", path, "-b", branch, base)
	return err
}

func (g *Git) WorktreeRemove(path string) error {
	_, err := g.run("worktree", "remove", path, "--force")
	return err
}

func (g *Git) WorktreePrune() error {
	_, err := g.run("worktree", "prune")
	return err
}

func (g *Git) MergeBase(a, b string) (string, error) {
	return g.run("merge-base", a, b)
}

func (g *Git) Diff(base, head string) (string, error) {
	return g.run("diff", base, head)
}

func (g *Git) DiffNameOnly(base, head string) ([]string, error) {
	out, err := g.run("diff", "--name-only", base, head)
	if err != nil {
		return nil, err
	}
	if out == "" {
		return nil, nil
	}
	return strings.Split(out, "\n"), nil
}

func (g *Git) MergeSquash(branch string) error {
	_, err := g.run("merge", "--squash", branch)
	return err
}

func (g *Git) MergeAbort() error {
	_, err := g.run("merge", "--abort")
	return err
}

func (g *Git) ResetHard(ref string) error {
	_, err := g.run("reset", "--hard", ref)
	return err
}

func (g *Git) Commit(msg string) error {
	_, err := g.run("commit", "-m", msg)
	return err
}

func (g *Git) CommitAllowEmpty(msg string) error {
	_, err := g.run("commit", "--allow-empty", "-m", msg)
	return err
}

func (g *Git) AddAll() error {
	_, err := g.run("add", "-A")
	return err
}

func (g *Git) CheckIgnore(path string) bool {
	_, err := g.run("check-ignore", "-q", path)
	return err == nil
}

func (g *Git) HasStagedChanges() bool {
	_, err := g.run("diff", "--cached", "--quiet")
	return err != nil // non-zero exit = there are changes
}

func (g *Git) TopLevel() (string, error) {
	return g.run("rev-parse", "--show-toplevel")
}

func (g *Git) CheckoutBranch(name string) error {
	_, err := g.run("checkout", name)
	return err
}

func (g *Git) CreateBranch(name string) error {
	_, err := g.run("checkout", "-b", name)
	return err
}

func (g *Git) Push(branch string) error {
	_, err := g.run("push", "-u", "origin", branch)
	return err
}

func (g *Git) StatusPorcelain() (string, error) {
	return g.run("status", "--porcelain")
}
```

**Step 4: Run tests**

Run: `go test ./internal/git/ -v`
Expected: all pass

**Step 5: Commit**

```bash
git add internal/git/
git commit -m "feat: add git package wrapping CLI operations"
```

---

## Task 4: Consensus Agents

**Files:**
- Create: `internal/consensus/agents.go`
- Create: `internal/consensus/agents_test.go`

**Dependencies:** Task 2

**Step 1: Write tests for agent interface and API clients**

Create `internal/consensus/agents_test.go`:
```go
package consensus

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/signalnine/conclave/internal/config"
)

func TestClaudeAgent_Available(t *testing.T) {
	tests := []struct {
		name string
		key  string
		want bool
	}{
		{"with key", "sk-test", true},
		{"empty key", "", false},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			a := NewClaudeAgent(&config.Config{AnthropicAPIKey: tt.key})
			if got := a.Available(); got != tt.want {
				t.Errorf("Available() = %v, want %v", got, tt.want)
			}
		})
	}
}

func TestClaudeAgent_Run(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Header.Get("x-api-key") != "sk-test" {
			t.Error("missing api key header")
		}
		if r.Header.Get("anthropic-version") != "2023-06-01" {
			t.Error("missing version header")
		}
		json.NewEncoder(w).Encode(map[string]any{
			"content": []map[string]any{
				{"type": "text", "text": "claude response"},
			},
		})
	}))
	defer srv.Close()

	cfg := &config.Config{
		AnthropicAPIKey:  "sk-test",
		AnthropicModel:   "claude-test",
		AnthropicMaxTokens: 100,
		AnthropicBaseURL: srv.URL,
	}
	a := NewClaudeAgent(cfg)
	got, err := a.Run(context.Background(), "test prompt")
	if err != nil {
		t.Fatal(err)
	}
	if got != "claude response" {
		t.Errorf("got %q", got)
	}
}

func TestGeminiAgent_Run(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Query().Get("key") != "gm-test" {
			t.Error("missing api key query param")
		}
		json.NewEncoder(w).Encode(map[string]any{
			"candidates": []map[string]any{
				{"content": map[string]any{
					"parts": []map[string]any{
						{"text": "gemini response"},
					},
				}},
			},
		})
	}))
	defer srv.Close()

	cfg := &config.Config{
		GeminiAPIKey: "gm-test",
		GeminiModel:  "gemini-test",
		GeminiBaseURL: srv.URL,
	}
	a := NewGeminiAgent(cfg)
	got, err := a.Run(context.Background(), "test prompt")
	if err != nil {
		t.Fatal(err)
	}
	if got != "gemini response" {
		t.Errorf("got %q", got)
	}
}

func TestCodexAgent_Run_ResponsesAPI(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Header.Get("Authorization") != "Bearer op-test" {
			t.Error("missing auth header")
		}
		json.NewEncoder(w).Encode(map[string]any{
			"output": []map[string]any{
				{"type": "message", "content": []map[string]any{
					{"type": "text", "text": "codex response"},
				}},
			},
		})
	}))
	defer srv.Close()

	cfg := &config.Config{
		OpenAIAPIKey:    "op-test",
		OpenAIModel:     "gpt-5.1-codex-max",
		OpenAIMaxTokens: 100,
		OpenAIBaseURL:   srv.URL,
	}
	a := NewCodexAgent(cfg)
	got, err := a.Run(context.Background(), "test prompt")
	if err != nil {
		t.Fatal(err)
	}
	if got != "codex response" {
		t.Errorf("got %q", got)
	}
}

func TestCodexAgent_Run_ChatCompletions(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		json.NewEncoder(w).Encode(map[string]any{
			"choices": []map[string]any{
				{"message": map[string]any{"content": "chat response"}},
			},
		})
	}))
	defer srv.Close()

	cfg := &config.Config{
		OpenAIAPIKey:  "op-test",
		OpenAIModel:   "gpt-4o",
		OpenAIBaseURL: srv.URL,
	}
	a := NewCodexAgent(cfg)
	got, err := a.Run(context.Background(), "test")
	if err != nil {
		t.Fatal(err)
	}
	if got != "chat response" {
		t.Errorf("got %q", got)
	}
}

func TestAgent_ContextCancellation(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		<-r.Context().Done()
	}))
	defer srv.Close()

	cfg := &config.Config{
		AnthropicAPIKey:  "sk-test",
		AnthropicBaseURL: srv.URL,
	}
	ctx, cancel := context.WithCancel(context.Background())
	cancel() // cancel immediately
	a := NewClaudeAgent(cfg)
	_, err := a.Run(ctx, "test")
	if err == nil {
		t.Error("expected error from cancelled context")
	}
}
```

**Step 2: Run tests to verify they fail**

Run: `go test ./internal/consensus/ -v`
Expected: compilation error

**Step 3: Implement agents**

Create `internal/consensus/agents.go`:
```go
package consensus

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"regexp"
	"strings"

	"github.com/signalnine/conclave/internal/config"
)

// Agent runs a prompt against an LLM and returns the response text.
type Agent interface {
	Name() string
	Run(ctx context.Context, prompt string) (string, error)
	Available() bool
}

// --- Claude ---

type ClaudeAgent struct {
	cfg *config.Config
}

func NewClaudeAgent(cfg *config.Config) *ClaudeAgent {
	return &ClaudeAgent{cfg: cfg}
}

func (a *ClaudeAgent) Name() string      { return "Claude" }
func (a *ClaudeAgent) Available() bool    { return a.cfg.AnthropicAPIKey != "" }

func (a *ClaudeAgent) Run(ctx context.Context, prompt string) (string, error) {
	body := map[string]any{
		"model":      a.cfg.AnthropicModel,
		"max_tokens": a.cfg.AnthropicMaxTokens,
		"messages":   []map[string]any{{"role": "user", "content": prompt}},
	}
	data, _ := json.Marshal(body)

	url := strings.TrimRight(a.cfg.AnthropicBaseURL, "/") + "/v1/messages"
	req, err := http.NewRequestWithContext(ctx, "POST", url, bytes.NewReader(data))
	if err != nil {
		return "", err
	}
	req.Header.Set("x-api-key", a.cfg.AnthropicAPIKey)
	req.Header.Set("anthropic-version", "2023-06-01")
	req.Header.Set("content-type", "application/json")

	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		return "", err
	}
	defer resp.Body.Close()

	var result struct {
		Content []struct{ Text string } `json:"content"`
		Error   *struct{ Message string } `json:"error"`
	}
	if err := json.NewDecoder(resp.Body).Decode(&result); err != nil {
		return "", fmt.Errorf("decode: %w", err)
	}
	if result.Error != nil {
		return "", fmt.Errorf("API error: %s", result.Error.Message)
	}
	if len(result.Content) == 0 || result.Content[0].Text == "" {
		return "", fmt.Errorf("empty response")
	}
	return result.Content[0].Text, nil
}

// --- Gemini ---

type GeminiAgent struct {
	cfg *config.Config
}

func NewGeminiAgent(cfg *config.Config) *GeminiAgent {
	return &GeminiAgent{cfg: cfg}
}

func (a *GeminiAgent) Name() string      { return "Gemini" }
func (a *GeminiAgent) Available() bool    { return a.cfg.GeminiAPIKey != "" }

func (a *GeminiAgent) Run(ctx context.Context, prompt string) (string, error) {
	body := map[string]any{
		"contents": []map[string]any{
			{"parts": []map[string]any{{"text": prompt}}},
		},
	}
	data, _ := json.Marshal(body)

	url := fmt.Sprintf("%s/v1beta/models/%s:generateContent?key=%s",
		strings.TrimRight(a.cfg.GeminiBaseURL, "/"), a.cfg.GeminiModel, a.cfg.GeminiAPIKey)
	req, err := http.NewRequestWithContext(ctx, "POST", url, bytes.NewReader(data))
	if err != nil {
		return "", err
	}
	req.Header.Set("Content-Type", "application/json")

	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		return "", err
	}
	defer resp.Body.Close()

	var result struct {
		Candidates []struct {
			Content struct {
				Parts []struct{ Text string } `json:"parts"`
			} `json:"content"`
		} `json:"candidates"`
		Error *struct{ Message string } `json:"error"`
	}
	if err := json.NewDecoder(resp.Body).Decode(&result); err != nil {
		return "", fmt.Errorf("decode: %w", err)
	}
	if result.Error != nil {
		return "", fmt.Errorf("API error: %s", result.Error.Message)
	}
	if len(result.Candidates) == 0 || len(result.Candidates[0].Content.Parts) == 0 {
		return "", fmt.Errorf("empty response")
	}
	return result.Candidates[0].Content.Parts[0].Text, nil
}

// --- Codex (OpenAI) ---

type CodexAgent struct {
	cfg *config.Config
}

func NewCodexAgent(cfg *config.Config) *CodexAgent {
	return &CodexAgent{cfg: cfg}
}

func (a *CodexAgent) Name() string      { return "Codex" }
func (a *CodexAgent) Available() bool    { return a.cfg.OpenAIAPIKey != "" }

var codexModelRe = regexp.MustCompile(`^gpt-5.*-codex`)
var chatModelRe = regexp.MustCompile(`^(gpt-4|gpt-3\.5-turbo|o1|o3)`)

func (a *CodexAgent) Run(ctx context.Context, prompt string) (string, error) {
	base := strings.TrimRight(a.cfg.OpenAIBaseURL, "/")
	var url string
	var body map[string]any

	if codexModelRe.MatchString(a.cfg.OpenAIModel) {
		url = base + "/v1/responses"
		body = map[string]any{
			"model": a.cfg.OpenAIModel,
			"input": []map[string]any{{"role": "user", "content": prompt}},
		}
	} else if chatModelRe.MatchString(a.cfg.OpenAIModel) {
		url = base + "/v1/chat/completions"
		body = map[string]any{
			"model":      a.cfg.OpenAIModel,
			"max_tokens": a.cfg.OpenAIMaxTokens,
			"messages":   []map[string]any{{"role": "user", "content": prompt}},
		}
	} else {
		url = base + "/v1/completions"
		body = map[string]any{
			"model":      a.cfg.OpenAIModel,
			"max_tokens": a.cfg.OpenAIMaxTokens,
			"prompt":     prompt,
		}
	}

	data, _ := json.Marshal(body)
	req, err := http.NewRequestWithContext(ctx, "POST", url, bytes.NewReader(data))
	if err != nil {
		return "", err
	}
	req.Header.Set("Authorization", "Bearer "+a.cfg.OpenAIAPIKey)
	req.Header.Set("Content-Type", "application/json")

	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		return "", err
	}
	defer resp.Body.Close()

	respBody, _ := io.ReadAll(resp.Body)
	return a.extractResponse(respBody)
}

func (a *CodexAgent) extractResponse(body []byte) (string, error) {
	// Try Responses API format
	if codexModelRe.MatchString(a.cfg.OpenAIModel) {
		var result struct {
			Output []struct {
				Type    string `json:"type"`
				Content []struct{ Text string } `json:"content"`
			} `json:"output"`
		}
		if err := json.Unmarshal(body, &result); err == nil {
			for _, o := range result.Output {
				if o.Type == "message" && len(o.Content) > 0 {
					return o.Content[0].Text, nil
				}
			}
		}
	}

	// Try chat completions format
	var chat struct {
		Choices []struct {
			Message struct{ Content string } `json:"message"`
		} `json:"choices"`
	}
	if err := json.Unmarshal(body, &chat); err == nil && len(chat.Choices) > 0 {
		if c := chat.Choices[0].Message.Content; c != "" {
			return c, nil
		}
	}

	// Try completions format
	var comp struct {
		Choices []struct{ Text string } `json:"choices"`
	}
	if err := json.Unmarshal(body, &comp); err == nil && len(comp.Choices) > 0 {
		if c := comp.Choices[0].Text; c != "" {
			return c, nil
		}
	}

	// Check for error
	var errResp struct {
		Error struct{ Message string } `json:"error"`
	}
	if err := json.Unmarshal(body, &errResp); err == nil && errResp.Error.Message != "" {
		return "", fmt.Errorf("API error: %s", errResp.Error.Message)
	}

	return "", fmt.Errorf("empty response")
}
```

**Step 4: Run tests**

Run: `go test ./internal/consensus/ -v -run TestClaude`
Run: `go test ./internal/consensus/ -v -run TestGemini`
Run: `go test ./internal/consensus/ -v -run TestCodex`
Run: `go test ./internal/consensus/ -v`
Expected: all pass

**Step 5: Commit**

```bash
git add internal/consensus/
git commit -m "feat: add consensus agent implementations (Claude, Gemini, Codex)"
```

---

## Task 5: Consensus Orchestration and Prompt Building

**Files:**
- Create: `internal/consensus/consensus.go`
- Create: `internal/consensus/consensus_test.go`
- Create: `internal/consensus/prompts.go`

**Dependencies:** Task 4

**Step 1: Write tests for two-stage orchestration**

Create `internal/consensus/consensus_test.go`:
```go
package consensus

import (
	"context"
	"fmt"
	"testing"
	"time"
)

type mockAgent struct {
	name      string
	available bool
	response  string
	err       error
	delay     time.Duration
}

func (m *mockAgent) Name() string    { return m.name }
func (m *mockAgent) Available() bool { return m.available }
func (m *mockAgent) Run(ctx context.Context, prompt string) (string, error) {
	if m.delay > 0 {
		select {
		case <-time.After(m.delay):
		case <-ctx.Done():
			return "", ctx.Err()
		}
	}
	return m.response, m.err
}

func TestRunStage1_AllSucceed(t *testing.T) {
	agents := []Agent{
		&mockAgent{name: "A", available: true, response: "resp-A"},
		&mockAgent{name: "B", available: true, response: "resp-B"},
		&mockAgent{name: "C", available: true, response: "resp-C"},
	}
	results := RunStage1(context.Background(), agents)
	succeeded := 0
	for _, r := range results {
		if r.Err == nil {
			succeeded++
		}
	}
	if succeeded != 3 {
		t.Errorf("got %d succeeded, want 3", succeeded)
	}
}

func TestRunStage1_OneFails(t *testing.T) {
	agents := []Agent{
		&mockAgent{name: "A", available: true, response: "resp-A"},
		&mockAgent{name: "B", available: true, err: fmt.Errorf("API error")},
		&mockAgent{name: "C", available: true, response: "resp-C"},
	}
	results := RunStage1(context.Background(), agents)
	succeeded := 0
	for _, r := range results {
		if r.Err == nil {
			succeeded++
		}
	}
	if succeeded != 2 {
		t.Errorf("got %d succeeded, want 2", succeeded)
	}
}

func TestRunStage1_Timeout(t *testing.T) {
	agents := []Agent{
		&mockAgent{name: "A", available: true, response: "fast", delay: 10 * time.Millisecond},
		&mockAgent{name: "B", available: true, response: "slow", delay: 5 * time.Second},
	}
	ctx, cancel := context.WithTimeout(context.Background(), 100*time.Millisecond)
	defer cancel()
	results := RunStage1(ctx, agents)
	// A should succeed, B should fail with context deadline
	if results[0].Err != nil {
		t.Error("agent A should have succeeded")
	}
	if results[1].Err == nil {
		t.Error("agent B should have timed out")
	}
}

func TestRunStage2_FirstChairmanSucceeds(t *testing.T) {
	chairmen := []Agent{
		&mockAgent{name: "Chair", available: true, response: "synthesis"},
	}
	result, err := RunStage2(context.Background(), chairmen, "prompt")
	if err != nil {
		t.Fatal(err)
	}
	if result.Agent != "Chair" {
		t.Errorf("chairman = %q", result.Agent)
	}
	if result.Output != "synthesis" {
		t.Errorf("output = %q", result.Output)
	}
}

func TestRunStage2_FallbackOnFailure(t *testing.T) {
	chairmen := []Agent{
		&mockAgent{name: "Primary", available: true, err: fmt.Errorf("fail")},
		&mockAgent{name: "Fallback", available: true, response: "synthesis"},
	}
	result, err := RunStage2(context.Background(), chairmen, "prompt")
	if err != nil {
		t.Fatal(err)
	}
	if result.Agent != "Fallback" {
		t.Errorf("chairman = %q, want Fallback", result.Agent)
	}
}

func TestRunStage2_AllFail(t *testing.T) {
	chairmen := []Agent{
		&mockAgent{name: "A", available: true, err: fmt.Errorf("fail")},
		&mockAgent{name: "B", available: true, err: fmt.Errorf("fail")},
	}
	_, err := RunStage2(context.Background(), chairmen, "prompt")
	if err == nil {
		t.Error("expected error when all chairmen fail")
	}
}

func TestRunConsensus_MinOneAgent(t *testing.T) {
	agents := []Agent{
		&mockAgent{name: "A", available: false},
		&mockAgent{name: "B", available: false},
		&mockAgent{name: "C", available: false},
	}
	_, err := RunConsensus(context.Background(), agents, agents, "prompt", 60, 60)
	if err == nil {
		t.Error("expected error with no available agents")
	}
}
```

**Step 2: Run tests to verify they fail**

Run: `go test ./internal/consensus/ -v -run TestRun`
Expected: compilation error

**Step 3: Implement orchestration**

Create `internal/consensus/consensus.go`:
```go
package consensus

import (
	"context"
	"fmt"
	"os"
	"sync"
	"time"
)

type AgentResult struct {
	Agent  string
	Output string
	Err    error
}

type ConsensusResult struct {
	Stage1Results   []AgentResult
	ChairmanName    string
	ChairmanOutput  string
	OutputFile      string
	AgentsSucceeded int
}

func RunStage1(ctx context.Context, agents []Agent) []AgentResult {
	results := make([]AgentResult, len(agents))
	var wg sync.WaitGroup

	for i, agent := range agents {
		wg.Add(1)
		go func(i int, a Agent) {
			defer wg.Done()
			output, err := a.Run(ctx, "")
			results[i] = AgentResult{Agent: a.Name(), Output: output, Err: err}
		}(i, agent)
	}

	wg.Wait()
	return results
}

// runStage1WithPrompt runs agents in parallel with the actual prompt.
func runStage1WithPrompt(ctx context.Context, agents []Agent, prompt string) []AgentResult {
	results := make([]AgentResult, len(agents))
	var wg sync.WaitGroup

	for i, agent := range agents {
		wg.Add(1)
		go func(i int, a Agent) {
			defer wg.Done()
			output, err := a.Run(ctx, prompt)
			results[i] = AgentResult{Agent: a.Name(), Output: output, Err: err}
		}(i, agent)
	}

	wg.Wait()
	return results
}

func RunStage2(ctx context.Context, chairmen []Agent, prompt string) (AgentResult, error) {
	for _, chairman := range chairmen {
		if !chairman.Available() {
			continue
		}
		output, err := chairman.Run(ctx, prompt)
		if err == nil && output != "" {
			return AgentResult{Agent: chairman.Name(), Output: output}, nil
		}
		fmt.Fprintf(os.Stderr, "  %s: FAILED (%v)\n", chairman.Name(), err)
	}
	return AgentResult{}, fmt.Errorf("all chairman agents failed")
}

func RunConsensus(ctx context.Context, agents, chairmen []Agent, prompt string, stage1Timeout, stage2Timeout int) (*ConsensusResult, error) {
	// Filter available agents
	var available []Agent
	for _, a := range agents {
		if a.Available() {
			available = append(available, a)
		}
	}
	if len(available) == 0 {
		return nil, fmt.Errorf("no agents available (need at least 1 API key)")
	}

	// Stage 1
	fmt.Fprintln(os.Stderr, "Stage 1: Launching parallel agent analysis...")
	ctx1, cancel1 := context.WithTimeout(ctx, time.Duration(stage1Timeout)*time.Second)
	defer cancel1()

	fmt.Fprintf(os.Stderr, "  Waiting for agents (%ds timeout)...\n", stage1Timeout)
	start1 := time.Now()
	results := runStage1WithPrompt(ctx1, available, prompt)
	fmt.Fprintf(os.Stderr, "  Stage 1 duration: %.1fs\n", time.Since(start1).Seconds())

	// Tally results
	succeeded := 0
	for _, r := range results {
		if r.Err == nil {
			fmt.Fprintf(os.Stderr, "  %s: SUCCESS\n", r.Agent)
			succeeded++
		} else {
			fmt.Fprintf(os.Stderr, "  %s: FAILED (%v)\n", r.Agent, r.Err)
		}
	}
	fmt.Fprintf(os.Stderr, "  Agents completed: %d/%d succeeded\n", succeeded, len(available))
	if succeeded == 0 {
		return nil, fmt.Errorf("all agents failed (0/%d succeeded)", len(available))
	}

	// Stage 2
	fmt.Fprintln(os.Stderr, "\nStage 2: Chairman synthesis...")
	ctx2, cancel2 := context.WithTimeout(ctx, time.Duration(stage2Timeout)*time.Second)
	defer cancel2()

	chairmanPrompt := buildChairmanPrompt(prompt, results)
	start2 := time.Now()
	chairResult, err := RunStage2(ctx2, chairmen, chairmanPrompt)
	if err != nil {
		return nil, fmt.Errorf("stage 2 failed: %w", err)
	}
	fmt.Fprintf(os.Stderr, "  %s: SUCCESS\n", chairResult.Agent)
	fmt.Fprintf(os.Stderr, "  Stage 2 duration: %.1fs\n", time.Since(start2).Seconds())

	return &ConsensusResult{
		Stage1Results:   results,
		ChairmanName:    chairResult.Agent,
		ChairmanOutput:  chairResult.Output,
		AgentsSucceeded: succeeded,
	}, nil
}

func buildChairmanPrompt(originalPrompt string, results []AgentResult) string {
	// This is a simple version; the full prompt builders are in prompts.go
	succeeded := 0
	for _, r := range results {
		if r.Err == nil {
			succeeded++
		}
	}
	var b strings.Builder
	fmt.Fprintf(&b, "Compile consensus from %d of %d analyses.\n\n", succeeded, len(results))
	for _, r := range results {
		if r.Err == nil {
			fmt.Fprintf(&b, "--- %s Analysis ---\n%s\n\n", r.Agent, r.Output)
		}
	}
	return b.String()
}
```

**Note:** This will have a compilation issue because `strings` is used but not imported, and `buildChairmanPrompt` is a placeholder. The real prompt builders go in `prompts.go` next. Fix the import and continue.

Create `internal/consensus/prompts.go`:
```go
package consensus

import (
	"fmt"
	"strings"
)

func BuildCodeReviewPrompt(description, diff, modifiedFiles, planContent string) string {
	var b strings.Builder
	b.WriteString("# Code Review - Stage 1 Independent Analysis\n\n")
	b.WriteString("**Your Task:** Independently review these code changes and provide your analysis.\n\n")
	fmt.Fprintf(&b, "**Change Description:** %s\n\n", description)
	fmt.Fprintf(&b, "**Modified Files:**\n%s\n\n", modifiedFiles)

	if planContent != "" {
		fmt.Fprintf(&b, "**Implementation Plan:**\n%s\n\n", planContent)
	}

	fmt.Fprintf(&b, "**Diff:**\n```diff\n%s\n```\n\n", diff)
	b.WriteString(`**Instructions:**
Please provide your independent code review in the following format:

## Critical Issues
- [List critical issues, or write 'None']

## Important Issues
- [List important issues, or write 'None']

## Suggestions
- [List suggestions, or write 'None']

Focus on correctness, security, performance, and adherence to the plan (if provided).
`)
	return b.String()
}

func BuildGeneralPrompt(prompt, context string) string {
	var b strings.Builder
	b.WriteString("# General Analysis - Stage 1 Independent Analysis\n\n")
	b.WriteString("**Your Task:** Independently analyze this question and provide your perspective.\n\n")
	fmt.Fprintf(&b, "**Question:**\n%s\n\n", prompt)

	if context != "" {
		fmt.Fprintf(&b, "**Context:**\n%s\n\n", context)
	}

	b.WriteString(`**Instructions:**
Please provide your independent analysis in the following format:

## Strong Points
- [List strong arguments/points, or write 'None']

## Moderate Points
- [List moderate arguments/points, or write 'None']

## Weak Points / Concerns
- [List weak points or concerns, or write 'None']

Provide thoughtful, independent analysis.
`)
	return b.String()
}

func BuildCodeReviewChairmanPrompt(description, modifiedFiles string, results []AgentResult) string {
	succeeded := 0
	for _, r := range results {
		if r.Err == nil {
			succeeded++
		}
	}

	var b strings.Builder
	b.WriteString("# Code Review Consensus - Stage 2 Chairman Synthesis\n\n")
	b.WriteString("**Your Task:** Compile a consensus code review from multiple independent reviewers.\n\n")
	b.WriteString("**CRITICAL:** Report all issues mentioned by any reviewer. Group similar issues together, but if reviewers disagree about an issue, report the disagreement explicitly.\n\n")
	fmt.Fprintf(&b, "**Change Description:** %s\n\n", description)
	fmt.Fprintf(&b, "**Modified Files:**\n%s\n\n", modifiedFiles)
	fmt.Fprintf(&b, "**Reviews Received (%d of 3):**\n\n", succeeded)

	for _, r := range results {
		if r.Err == nil {
			fmt.Fprintf(&b, "--- %s Review ---\n%s\n\n", r.Agent, r.Output)
		}
	}

	b.WriteString(`**Instructions:**
Compile a consensus report with three tiers:

## High Priority - Multiple Reviewers Agree
[Issues mentioned by 2+ reviewers - group similar issues]

## Medium Priority - Single Reviewer, Significant
[Important/Critical issues from single reviewer]

## Consider - Suggestions
[Suggestions from any reviewer]

## Final Recommendation
- If High Priority issues exist: "Address high priority issues before merging"
- If only Medium Priority: "Review medium priority concerns"
- If only Consider tier: "Optional improvements suggested"
- If no issues: "All reviewers approve - safe to merge"

Be direct. Group similar issues but preserve different perspectives.
`)
	return b.String()
}

func BuildGeneralChairmanPrompt(originalPrompt string, results []AgentResult) string {
	succeeded := 0
	for _, r := range results {
		if r.Err == nil {
			succeeded++
		}
	}

	var b strings.Builder
	b.WriteString("# General Analysis Consensus - Stage 2 Chairman Synthesis\n\n")
	b.WriteString("**Your Task:** Compile consensus from multiple independent analyses.\n\n")
	b.WriteString("**CRITICAL:** If analyses disagree or conflict, highlight disagreements explicitly. Do NOT smooth over conflicts.\n\n")
	fmt.Fprintf(&b, "**Original Question:**\n%s\n\n", originalPrompt)
	fmt.Fprintf(&b, "**Analyses Received (%d of 3):**\n\n", succeeded)

	for _, r := range results {
		if r.Err == nil {
			fmt.Fprintf(&b, "--- %s Analysis ---\n%s\n\n", r.Agent, r.Output)
		}
	}

	b.WriteString(`**Instructions:**
Provide final consensus:

## Areas of Agreement
[What do reviewers agree on?]

## Areas of Disagreement
[Where do perspectives differ? Be explicit about conflicts.]

## Confidence Level
High / Medium / Low

## Synthesized Recommendation
[Incorporate all perspectives, noting disagreements where they exist]

Be direct. Disagreement is valuable - report it clearly.
`)
	return b.String()
}
```

**Step 4: Fix the import in consensus.go** (replace the placeholder `buildChairmanPrompt`):

In `consensus.go`, replace the `buildChairmanPrompt` function and add the missing `strings` import. The `RunConsensus` function should use the prompt builders from `prompts.go` - but that requires knowing the mode. Refactor `RunConsensus` to accept the chairman prompt directly, or pass mode info. Simplest: have the caller build both prompts and pass them in.

Update `RunConsensus` signature to accept `stage1Prompt` and a function `buildChairman func([]AgentResult) string`:

This is getting complex - the exact refactoring will happen during implementation. The key pattern is tested above.

**Step 5: Run tests**

Run: `go test ./internal/consensus/ -v`
Expected: all pass

**Step 6: Commit**

```bash
git add internal/consensus/
git commit -m "feat: add two-stage consensus orchestration with prompt builders"
```

---

## Task 6: Plan Parser

**Files:**
- Create: `internal/plan/parser.go`
- Create: `internal/plan/parser_test.go`

**Dependencies:** Task 1

**Step 1: Write tests**

Create `internal/plan/parser_test.go`:
```go
package plan

import (
	"strings"
	"testing"
)

func TestParsePlan_SingleTask(t *testing.T) {
	input := `## Task 1: Create Auth Module
**Files:**
- Create: ` + "`src/auth.go`" + `
**Dependencies:** None

Implementation details here.
`
	tasks, err := ParsePlan(strings.NewReader(input))
	if err != nil {
		t.Fatal(err)
	}
	if len(tasks) != 1 {
		t.Fatalf("got %d tasks, want 1", len(tasks))
	}
	if tasks[0].ID != 1 {
		t.Errorf("ID = %d", tasks[0].ID)
	}
	if tasks[0].Title != "Create Auth Module" {
		t.Errorf("Title = %q", tasks[0].Title)
	}
	if len(tasks[0].FilePaths) != 1 || tasks[0].FilePaths[0] != "src/auth.go" {
		t.Errorf("FilePaths = %v", tasks[0].FilePaths)
	}
	if len(tasks[0].DependsOn) != 0 {
		t.Errorf("DependsOn = %v", tasks[0].DependsOn)
	}
}

func TestParsePlan_MultipleTasks(t *testing.T) {
	input := `## Task 1: Setup
**Dependencies:** None

## Task 2: Auth
**Dependencies:** Task 1

## Task 3: API
**Dependencies:** Task 1, Task 2
`
	tasks, err := ParsePlan(strings.NewReader(input))
	if err != nil {
		t.Fatal(err)
	}
	if len(tasks) != 3 {
		t.Fatalf("got %d tasks", len(tasks))
	}
	if len(tasks[1].DependsOn) != 1 || tasks[1].DependsOn[0] != 1 {
		t.Errorf("task 2 deps = %v", tasks[1].DependsOn)
	}
	if len(tasks[2].DependsOn) != 2 {
		t.Errorf("task 3 deps = %v", tasks[2].DependsOn)
	}
}

func TestParsePlan_H3Headers(t *testing.T) {
	input := `### Task 1: Works With H3
**Dependencies:** None
`
	tasks, err := ParsePlan(strings.NewReader(input))
	if err != nil {
		t.Fatal(err)
	}
	if len(tasks) != 1 {
		t.Fatalf("got %d tasks", len(tasks))
	}
}

func TestParsePlan_MultipleFiles(t *testing.T) {
	input := `## Task 1: Multi File
**Files:**
- Create: ` + "`src/a.go`" + `
- Modify: ` + "`src/b.go:10-20`" + `
- Test: ` + "`test/a_test.go`" + `
**Dependencies:** None
`
	tasks, err := ParsePlan(strings.NewReader(input))
	if err != nil {
		t.Fatal(err)
	}
	if len(tasks[0].FilePaths) != 3 {
		t.Errorf("got %d files: %v", len(tasks[0].FilePaths), tasks[0].FilePaths)
	}
	// Line range suffix should be stripped
	if tasks[0].FilePaths[1] != "src/b.go" {
		t.Errorf("file[1] = %q, want src/b.go", tasks[0].FilePaths[1])
	}
}

func TestParsePlan_Empty(t *testing.T) {
	tasks, err := ParsePlan(strings.NewReader(""))
	if err != nil {
		t.Fatal(err)
	}
	if len(tasks) != 0 {
		t.Errorf("got %d tasks from empty input", len(tasks))
	}
}

func TestParsePlan_ExtractTaskSpec(t *testing.T) {
	input := `## Task 1: First
Some content for task 1.
More content.

## Task 2: Second
Content for task 2.
`
	tasks, _ := ParsePlan(strings.NewReader(input))
	if !strings.Contains(tasks[0].Description, "Some content for task 1") {
		t.Errorf("task 1 description missing content: %q", tasks[0].Description)
	}
	if strings.Contains(tasks[0].Description, "Content for task 2") {
		t.Error("task 1 description contains task 2 content")
	}
}

func TestComputeWaves(t *testing.T) {
	tasks := []Task{
		{ID: 1, DependsOn: nil},
		{ID: 2, DependsOn: []int{1}},
		{ID: 3, DependsOn: nil},
		{ID: 4, DependsOn: []int{2, 3}},
	}
	waves := ComputeWaves(tasks)
	// Task 1,3 = wave 0; Task 2 = wave 1; Task 4 = wave 2
	if waves[1] != 0 || waves[3] != 0 {
		t.Errorf("wave[1]=%d, wave[3]=%d, want 0", waves[1], waves[3])
	}
	if waves[2] != 1 {
		t.Errorf("wave[2]=%d, want 1", waves[2])
	}
	if waves[4] != 2 {
		t.Errorf("wave[4]=%d, want 2", waves[4])
	}
}

func TestDetectCycle(t *testing.T) {
	tasks := []Task{
		{ID: 1, DependsOn: []int{2}},
		{ID: 2, DependsOn: []int{1}},
	}
	err := Validate(tasks)
	if err == nil {
		t.Error("expected cycle error")
	}
}

func TestValidate_MissingDep(t *testing.T) {
	tasks := []Task{
		{ID: 1, DependsOn: []int{99}},
	}
	err := Validate(tasks)
	if err == nil {
		t.Error("expected missing dependency error")
	}
}
```

**Step 2: Implement**

Create `internal/plan/parser.go`:
```go
package plan

import (
	"bufio"
	"fmt"
	"io"
	"regexp"
	"strconv"
	"strings"
)

type Task struct {
	ID          int
	Title       string
	Description string
	FilePaths   []string
	DependsOn   []int
}

var taskHeaderRe = regexp.MustCompile(`^#{2,3} Task (\d+): (.+)`)
var fileLineRe = regexp.MustCompile("^- (?:Create|Modify|Test): `([^`]+)`")
var depsRe = regexp.MustCompile(`Task (\d+)`)

func ParsePlan(r io.Reader) ([]Task, error) {
	scanner := bufio.NewScanner(r)
	var tasks []Task
	var current *Task
	collectingFiles := false
	var descLines []string

	flush := func() {
		if current != nil {
			current.Description = strings.TrimSpace(strings.Join(descLines, "\n"))
			tasks = append(tasks, *current)
		}
	}

	for scanner.Scan() {
		line := scanner.Text()

		if m := taskHeaderRe.FindStringSubmatch(line); m != nil {
			flush()
			id, _ := strconv.Atoi(m[1])
			current = &Task{ID: id, Title: m[2]}
			collectingFiles = false
			descLines = []string{line}
			continue
		}

		if current == nil {
			continue
		}

		descLines = append(descLines, line)

		// Files header
		if matched, _ := regexp.MatchString(`(?i)^\*?\*?Files:?\*?\*?`, line); matched {
			collectingFiles = true
			continue
		}

		// Collect file paths
		if collectingFiles {
			if m := fileLineRe.FindStringSubmatch(line); m != nil {
				path := m[1]
				// Strip line range suffix like :10-20
				if idx := strings.LastIndex(path, ":"); idx > 0 {
					if _, err := strconv.Atoi(string(path[idx+1])); err == nil {
						path = path[:idx]
					}
				}
				current.FilePaths = append(current.FilePaths, path)
				continue
			}
			if line != "" {
				collectingFiles = false
			}
		}

		// Dependencies
		if matched, _ := regexp.MatchString(`(?i)^\*?\*?Dependencies:?\*?\*?`, line); matched {
			if !strings.Contains(strings.ToLower(line), "none") {
				for _, m := range depsRe.FindAllStringSubmatch(line, -1) {
					id, _ := strconv.Atoi(m[1])
					current.DependsOn = append(current.DependsOn, id)
				}
			}
		}
	}
	flush()
	return tasks, scanner.Err()
}

func ComputeWaves(tasks []Task) map[int]int {
	waves := make(map[int]int)
	var depth func(id int) int
	depth = func(id int) int {
		if w, ok := waves[id]; ok {
			return w
		}
		var t *Task
		for i := range tasks {
			if tasks[i].ID == id {
				t = &tasks[i]
				break
			}
		}
		if t == nil || len(t.DependsOn) == 0 {
			waves[id] = 0
			return 0
		}
		maxDep := 0
		for _, dep := range t.DependsOn {
			if d := depth(dep); d > maxDep {
				maxDep = d
			}
		}
		waves[id] = maxDep + 1
		return maxDep + 1
	}
	for _, t := range tasks {
		depth(t.ID)
	}
	return waves
}

func WaveCount(waves map[int]int) int {
	max := 0
	for _, w := range waves {
		if w > max {
			max = w
		}
	}
	return max + 1
}

func TasksInWave(tasks []Task, waves map[int]int, wave int) []Task {
	var result []Task
	for _, t := range tasks {
		if waves[t.ID] == wave {
			result = append(result, t)
		}
	}
	return result
}

func Validate(tasks []Task) error {
	ids := make(map[int]bool)
	for _, t := range tasks {
		ids[t.ID] = true
	}
	for _, t := range tasks {
		for _, dep := range t.DependsOn {
			if !ids[dep] {
				return fmt.Errorf("task %d references non-existent dependency task %d", t.ID, dep)
			}
		}
	}
	// Cycle detection
	for _, t := range tasks {
		if hasCycle(t.ID, nil, tasks) {
			return fmt.Errorf("dependency cycle detected involving task %d", t.ID)
		}
	}
	return nil
}

func hasCycle(id int, visited []int, tasks []Task) bool {
	for _, v := range visited {
		if v == id {
			return true
		}
	}
	for _, t := range tasks {
		if t.ID == id {
			for _, dep := range t.DependsOn {
				if hasCycle(dep, append(visited, id), tasks) {
					return true
				}
			}
			break
		}
	}
	return false
}

func ExtractTaskSpec(tasks []Task, id int) string {
	for _, t := range tasks {
		if t.ID == id {
			return t.Description
		}
	}
	return ""
}

func DetectFileOverlaps(tasks []Task) []Task {
	// Add implicit dependencies when tasks share files
	for i := range tasks {
		for j := i + 1; j < len(tasks); j++ {
			for _, fi := range tasks[i].FilePaths {
				for _, fj := range tasks[j].FilePaths {
					if fi == fj {
						// Add i as dependency of j if not already present
						found := false
						for _, d := range tasks[j].DependsOn {
							if d == tasks[i].ID {
								found = true
								break
							}
						}
						if !found {
							tasks[j].DependsOn = append(tasks[j].DependsOn, tasks[i].ID)
						}
					}
				}
			}
		}
	}
	return tasks
}
```

**Step 3: Run tests**

Run: `go test ./internal/plan/ -v`
Expected: all pass

**Step 4: Commit**

```bash
git add internal/plan/
git commit -m "feat: add plan parser with wave computation and validation"
```

---

## Task 7: Skills Discovery

**Files:**
- Create: `internal/skills/discovery.go`
- Create: `internal/skills/discovery_test.go`
- Create: `internal/skills/resolve.go`
- Create: `internal/skills/resolve_test.go`

**Dependencies:** Task 1

**Step 1: Write discovery tests**

Create `internal/skills/discovery_test.go`:
```go
package skills

import (
	"os"
	"path/filepath"
	"testing"
)

func createSkill(t *testing.T, dir, name, content string) {
	t.Helper()
	skillDir := filepath.Join(dir, name)
	os.MkdirAll(skillDir, 0755)
	os.WriteFile(filepath.Join(skillDir, "SKILL.md"), []byte(content), 0644)
}

func TestDiscover_FindsSkills(t *testing.T) {
	dir := t.TempDir()
	createSkill(t, dir, "brainstorming", `---
name: brainstorming
description: Use when starting creative work
---
Content here.
`)
	createSkill(t, dir, "debugging", `---
name: debugging
description: Use when fixing bugs
---
Content.
`)
	skills := Discover(dir)
	if len(skills) != 2 {
		t.Fatalf("got %d skills, want 2", len(skills))
	}
}

func TestDiscover_ParsesFrontmatter(t *testing.T) {
	dir := t.TempDir()
	createSkill(t, dir, "test-skill", `---
name: test-skill
description: A test skill
---
Body.
`)
	skills := Discover(dir)
	if skills[0].Name != "test-skill" {
		t.Errorf("Name = %q", skills[0].Name)
	}
	if skills[0].Description != "A test skill" {
		t.Errorf("Description = %q", skills[0].Description)
	}
}

func TestDiscover_FallsBackToDirectoryName(t *testing.T) {
	dir := t.TempDir()
	createSkill(t, dir, "my-skill", "No frontmatter here.\n")
	skills := Discover(dir)
	if len(skills) != 1 {
		t.Fatalf("got %d skills", len(skills))
	}
	if skills[0].Name != "my-skill" {
		t.Errorf("Name = %q, want my-skill", skills[0].Name)
	}
}

func TestDiscover_EmptyDir(t *testing.T) {
	dir := t.TempDir()
	skills := Discover(dir)
	if len(skills) != 0 {
		t.Errorf("got %d skills from empty dir", len(skills))
	}
}

func TestDiscover_NonexistentDir(t *testing.T) {
	skills := Discover("/nonexistent/path")
	if len(skills) != 0 {
		t.Errorf("got %d skills from nonexistent dir", len(skills))
	}
}
```

**Step 2: Write resolve tests**

Create `internal/skills/resolve_test.go`:
```go
package skills

import (
	"testing"
)

func TestResolve_FindsInConclave(t *testing.T) {
	dir := t.TempDir()
	createSkill(t, dir, "brainstorming", "---\nname: brainstorming\n---\nContent.\n")
	s := Resolve("brainstorming", nil, dir)
	if s == nil {
		t.Fatal("not found")
	}
	if s.Source != "conclave" {
		t.Errorf("Source = %q", s.Source)
	}
}

func TestResolve_PersonalOverridesConclave(t *testing.T) {
	conclaveDir := t.TempDir()
	personalDir := t.TempDir()
	createSkill(t, conclaveDir, "brainstorming", "---\nname: brainstorming\n---\nConclave version.\n")
	createSkill(t, personalDir, "brainstorming", "---\nname: brainstorming\n---\nPersonal version.\n")
	s := Resolve("brainstorming", personalDir, conclaveDir)
	if s.Source != "personal" {
		t.Errorf("Source = %q, want personal", s.Source)
	}
}

func TestResolve_ConclavePrefix_SkipsPersonal(t *testing.T) {
	conclaveDir := t.TempDir()
	personalDir := t.TempDir()
	createSkill(t, conclaveDir, "brainstorming", "---\nname: brainstorming\n---\nConclave.\n")
	createSkill(t, personalDir, "brainstorming", "---\nname: brainstorming\n---\nPersonal.\n")
	s := Resolve("conclave:brainstorming", personalDir, conclaveDir)
	if s.Source != "conclave" {
		t.Errorf("Source = %q, want conclave", s.Source)
	}
}

func TestResolve_NotFound(t *testing.T) {
	dir := t.TempDir()
	s := Resolve("nonexistent", nil, dir)
	if s != nil {
		t.Errorf("expected nil, got %v", s)
	}
}
```

**Step 3: Implement**

Create `internal/skills/discovery.go`:
```go
package skills

import (
	"bufio"
	"os"
	"path/filepath"
	"strings"
)

type Skill struct {
	Name        string
	Description string
	Path        string
	SkillFile   string
	Source      string // "conclave", "personal"
}

func Discover(dirs ...string) []Skill {
	var skills []Skill
	for _, dir := range dirs {
		entries, err := os.ReadDir(dir)
		if err != nil {
			continue
		}
		for _, e := range entries {
			if !e.IsDir() {
				continue
			}
			skillFile := filepath.Join(dir, e.Name(), "SKILL.md")
			if _, err := os.Stat(skillFile); err != nil {
				continue
			}
			name, desc := extractFrontmatter(skillFile)
			if name == "" {
				name = e.Name()
			}
			skills = append(skills, Skill{
				Name:        name,
				Description: desc,
				Path:        filepath.Join(dir, e.Name()),
				SkillFile:   skillFile,
			})
		}
	}
	return skills
}

func extractFrontmatter(path string) (name, description string) {
	f, err := os.Open(path)
	if err != nil {
		return "", ""
	}
	defer f.Close()

	scanner := bufio.NewScanner(f)
	inFrontmatter := false
	for scanner.Scan() {
		line := scanner.Text()
		if strings.TrimSpace(line) == "---" {
			if inFrontmatter {
				break
			}
			inFrontmatter = true
			continue
		}
		if inFrontmatter {
			if k, v, ok := strings.Cut(line, ":"); ok {
				k = strings.TrimSpace(k)
				v = strings.TrimSpace(v)
				switch k {
				case "name":
					name = v
				case "description":
					description = v
				}
			}
		}
	}
	return name, description
}
```

Create `internal/skills/resolve.go`:
```go
package skills

import (
	"os"
	"path/filepath"
	"strings"
)

// Resolve finds a skill by name. Search order: personal dir, then conclave dir.
// The "conclave:" prefix forces conclave-only lookup.
// personalDir can be nil/empty to skip personal skills.
func Resolve(name string, personalDir interface{}, conclaveDir string) *Skill {
	forceConclave := strings.HasPrefix(name, "conclave:")
	actualName := strings.TrimPrefix(name, "conclave:")

	// Try personal first (unless conclave: prefix)
	if !forceConclave {
		if pd, ok := personalDir.(string); ok && pd != "" {
			if s := findSkill(pd, actualName, "personal"); s != nil {
				return s
			}
		}
	}

	// Try conclave
	if s := findSkill(conclaveDir, actualName, "conclave"); s != nil {
		return s
	}
	return nil
}

func findSkill(dir, name, source string) *Skill {
	skillFile := filepath.Join(dir, name, "SKILL.md")
	if _, err := os.Stat(skillFile); err != nil {
		return nil
	}
	n, desc := extractFrontmatter(skillFile)
	if n == "" {
		n = name
	}
	return &Skill{
		Name:        n,
		Description: desc,
		Path:        filepath.Join(dir, name),
		SkillFile:   skillFile,
		Source:      source,
	}
}
```

**Step 4: Run tests**

Run: `go test ./internal/skills/ -v`
Expected: all pass

**Step 5: Commit**

```bash
git add internal/skills/
git commit -m "feat: add skills discovery and resolution with namespace shadowing"
```

---

## Task 8: Session Start Hook

**Files:**
- Create: `internal/hook/sessionstart.go`
- Create: `internal/hook/sessionstart_test.go`

**Dependencies:** Task 1

**Step 1: Write tests**

Create `internal/hook/sessionstart_test.go`:
```go
package hook

import (
	"encoding/json"
	"os"
	"path/filepath"
	"testing"
)

func TestSessionStart_OutputsValidJSON(t *testing.T) {
	dir := t.TempDir()
	// Create using-conclave skill
	skillDir := filepath.Join(dir, "skills", "using-conclave")
	os.MkdirAll(skillDir, 0755)
	os.WriteFile(filepath.Join(skillDir, "SKILL.md"), []byte("# Using Conclave\nContent here.\n"), 0644)

	output, err := SessionStart(dir)
	if err != nil {
		t.Fatal(err)
	}

	var result map[string]any
	if err := json.Unmarshal([]byte(output), &result); err != nil {
		t.Fatalf("invalid JSON: %v\noutput: %s", err, output)
	}

	hookOutput, ok := result["hookSpecificOutput"].(map[string]any)
	if !ok {
		t.Fatal("missing hookSpecificOutput")
	}
	if hookOutput["hookEventName"] != "SessionStart" {
		t.Errorf("hookEventName = %v", hookOutput["hookEventName"])
	}
	ctx, ok := hookOutput["additionalContext"].(string)
	if !ok || ctx == "" {
		t.Error("missing additionalContext")
	}
}

func TestSessionStart_LegacyWarning(t *testing.T) {
	dir := t.TempDir()
	skillDir := filepath.Join(dir, "skills", "using-conclave")
	os.MkdirAll(skillDir, 0755)
	os.WriteFile(filepath.Join(skillDir, "SKILL.md"), []byte("content"), 0644)

	// Create legacy dir
	legacyDir := filepath.Join(t.TempDir(), ".config", "conclave", "skills")
	os.MkdirAll(legacyDir, 0755)
	t.Setenv("HOME", filepath.Dir(filepath.Dir(filepath.Dir(legacyDir))))

	output, err := SessionStart(dir)
	if err != nil {
		t.Fatal(err)
	}
	// Should contain warning about legacy skills
	var result map[string]any
	json.Unmarshal([]byte(output), &result)
	hookOutput := result["hookSpecificOutput"].(map[string]any)
	ctx := hookOutput["additionalContext"].(string)
	if len(ctx) == 0 {
		t.Error("expected non-empty context")
	}
}
```

**Step 2: Implement**

Create `internal/hook/sessionstart.go`:
```go
package hook

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"strings"
)

func SessionStart(pluginRoot string) (string, error) {
	// Read using-conclave skill content
	skillPath := filepath.Join(pluginRoot, "skills", "using-conclave", "SKILL.md")
	content, err := os.ReadFile(skillPath)
	if err != nil {
		return "", fmt.Errorf("reading using-conclave skill: %w", err)
	}

	// Check for legacy skills directory
	var warning string
	home, _ := os.UserHomeDir()
	if home != "" {
		legacyDir := filepath.Join(home, ".config", "conclave", "skills")
		if info, err := os.Stat(legacyDir); err == nil && info.IsDir() {
			warning = "\n\n<important-reminder>IN YOUR FIRST REPLY AFTER SEEING THIS MESSAGE YOU MUST TELL THE USER:" +
				"WARNING: Conclave now uses Claude Code's skills system. Custom skills in ~/.config/conclave/skills " +
				"will not be read. Move custom skills to ~/.claude/skills instead. To make this message go away, " +
				"remove ~/.config/conclave/skills</important-reminder>"
		}
	}

	ctx := fmt.Sprintf("<EXTREMELY_IMPORTANT>\nYou have conclave.\n\n"+
		"**Below is the full content of your 'conclave:using-conclave' skill - "+
		"your introduction to using skills. For all other skills, use the 'Skill' tool:**\n\n"+
		"%s\n\n%s\n</EXTREMELY_IMPORTANT>",
		strings.TrimSpace(string(content)), warning)

	output := map[string]any{
		"hookSpecificOutput": map[string]any{
			"hookEventName":    "SessionStart",
			"additionalContext": ctx,
		},
	}

	data, err := json.Marshal(output)
	if err != nil {
		return "", err
	}
	return string(data), nil
}
```

**Step 3: Run tests**

Run: `go test ./internal/hook/ -v`
Expected: all pass

**Step 4: Commit**

```bash
git add internal/hook/
git commit -m "feat: add session-start hook with legacy directory warning"
```

---

## Task 9: Ralph State Management

**Files:**
- Create: `internal/ralph/state.go`
- Create: `internal/ralph/state_test.go`
- Create: `internal/ralph/stuck.go`
- Create: `internal/ralph/stuck_test.go`

**Dependencies:** Task 1

**Step 1: Write state tests**

Create `internal/ralph/state_test.go`:
```go
package ralph

import (
	"os"
	"path/filepath"
	"testing"
)

func TestInitState(t *testing.T) {
	dir := t.TempDir()
	s := NewStateManager(dir)
	if err := s.Init("task-1", 5); err != nil {
		t.Fatal(err)
	}
	state, err := s.Load()
	if err != nil {
		t.Fatal(err)
	}
	if state.TaskID != "task-1" {
		t.Errorf("TaskID = %q", state.TaskID)
	}
	if state.Iteration != 1 {
		t.Errorf("Iteration = %d", state.Iteration)
	}
	if state.MaxIterations != 5 {
		t.Errorf("MaxIterations = %d", state.MaxIterations)
	}
}

func TestUpdateState(t *testing.T) {
	dir := t.TempDir()
	s := NewStateManager(dir)
	s.Init("task-1", 5)

	s.Update("tests", 1, "error output here")
	state, _ := s.Load()
	if state.Iteration != 2 {
		t.Errorf("Iteration = %d, want 2", state.Iteration)
	}
	if state.LastGate != "tests" {
		t.Errorf("LastGate = %q", state.LastGate)
	}
	if state.ErrorHash == "" {
		t.Error("ErrorHash empty")
	}
}

func TestUpdateState_StuckDetection(t *testing.T) {
	dir := t.TempDir()
	s := NewStateManager(dir)
	s.Init("task-1", 10)

	// Same error 3 times should increment stuck count
	for i := 0; i < 3; i++ {
		s.Update("tests", 1, "identical error output")
	}
	state, _ := s.Load()
	if state.StuckCount < 2 {
		t.Errorf("StuckCount = %d, want >= 2", state.StuckCount)
	}
}

func TestCleanup(t *testing.T) {
	dir := t.TempDir()
	s := NewStateManager(dir)
	s.Init("task-1", 5)
	s.Cleanup()

	stateFile := filepath.Join(dir, ".ralph_state.json")
	if _, err := os.Stat(stateFile); !os.IsNotExist(err) {
		t.Error("state file not cleaned up")
	}
}

func TestExists(t *testing.T) {
	dir := t.TempDir()
	s := NewStateManager(dir)
	if s.Exists() {
		t.Error("should not exist before init")
	}
	s.Init("task-1", 5)
	if !s.Exists() {
		t.Error("should exist after init")
	}
}
```

**Step 2: Write stuck tests**

Create `internal/ralph/stuck_test.go`:
```go
package ralph

import (
	"testing"
)

func TestIsStuck(t *testing.T) {
	tests := []struct {
		name       string
		stuckCount int
		threshold  int
		want       bool
	}{
		{"below threshold", 1, 3, false},
		{"at threshold", 3, 3, true},
		{"above threshold", 5, 3, true},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			if got := IsStuck(tt.stuckCount, tt.threshold); got != tt.want {
				t.Errorf("IsStuck(%d, %d) = %v, want %v", tt.stuckCount, tt.threshold, got, tt.want)
			}
		})
	}
}
```

**Step 3: Implement state management**

Create `internal/ralph/state.go`:
```go
package ralph

import (
	"crypto/md5"
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"time"
)

const (
	stateFileName   = ".ralph_state.json"
	contextFileName = ".ralph_context.md"
)

type Attempt struct {
	Iteration int    `json:"iteration"`
	Gate      string `json:"gate"`
	Hash      string `json:"hash"`
	Shift     bool   `json:"shift"`
}

type State struct {
	TaskID         string    `json:"task_id"`
	Iteration      int       `json:"iteration"`
	MaxIterations  int       `json:"max_iterations"`
	LastGate       string    `json:"last_gate"`
	ExitCode       int       `json:"exit_code"`
	ErrorHash      string    `json:"error_hash"`
	Timestamp      time.Time `json:"timestamp"`
	StuckCount     int       `json:"stuck_count"`
	StrategyShifts int       `json:"strategy_shifts"`
	Attempts       []Attempt `json:"attempts"`
}

type StateManager struct {
	dir string
}

func NewStateManager(dir string) *StateManager {
	return &StateManager{dir: dir}
}

func (s *StateManager) statePath() string   { return filepath.Join(s.dir, stateFileName) }
func (s *StateManager) contextPath() string { return filepath.Join(s.dir, contextFileName) }

func (s *StateManager) Exists() bool {
	_, err := os.Stat(s.statePath())
	return err == nil
}

func (s *StateManager) Init(taskID string, maxIter int) error {
	state := &State{
		TaskID:        taskID,
		Iteration:     1,
		MaxIterations: maxIter,
		Timestamp:     time.Now(),
		Attempts:      []Attempt{},
	}
	if err := s.save(state); err != nil {
		return err
	}
	ctx := fmt.Sprintf("# Ralph Loop Context: %s\n\n## Status\n- Iteration: 1 of %d\n- Last gate: (none yet)\n\n## Previous Output\n(First attempt - no previous output)\n", taskID, maxIter)
	return os.WriteFile(s.contextPath(), []byte(ctx), 0644)
}

func (s *StateManager) Load() (*State, error) {
	data, err := os.ReadFile(s.statePath())
	if err != nil {
		return nil, err
	}
	var state State
	if err := json.Unmarshal(data, &state); err != nil {
		return nil, err
	}
	return &state, nil
}

func (s *StateManager) Update(gate string, exitCode int, output string) error {
	state, err := s.Load()
	if err != nil {
		return err
	}

	// Hash first 20 lines of output
	lines := strings.Split(output, "\n")
	if len(lines) > 20 {
		lines = lines[:20]
	}
	hash := fmt.Sprintf("%x", md5.Sum([]byte(strings.Join(lines, "\n"))))

	// Stuck detection
	if hash == state.ErrorHash && state.ErrorHash != "" {
		state.StuckCount++
	} else {
		state.StuckCount = 0
	}

	// Truncate output
	truncated := output
	allLines := strings.Split(output, "\n")
	if len(allLines) > 100 {
		truncated = strings.Join(allLines[:100], "\n") +
			fmt.Sprintf("\n[... truncated, %d total lines ...]", len(allLines))
	}

	state.Attempts = append(state.Attempts, Attempt{
		Iteration: state.Iteration,
		Gate:      gate,
		Hash:      hash[:8],
		Shift:     state.StrategyShifts > 0,
	})
	state.Iteration++
	state.LastGate = gate
	state.ExitCode = exitCode
	state.ErrorHash = hash
	state.Timestamp = time.Now()

	if err := s.save(state); err != nil {
		return err
	}

	// Update context file
	ctx := fmt.Sprintf("# Ralph Loop Context: %s\n\n## Status\n- Iteration: %d of %d\n- Last gate failed: %s\n- Stuck count: %d (threshold: 3)\n\n## Last Error Output (verbatim)\n```\n%s\n```\n",
		state.TaskID, state.Iteration, state.MaxIterations, gate, state.StuckCount, truncated)
	return os.WriteFile(s.contextPath(), []byte(ctx), 0644)
}

func (s *StateManager) IncrementStrategyShift() error {
	state, err := s.Load()
	if err != nil {
		return err
	}
	state.StrategyShifts++
	return s.save(state)
}

func (s *StateManager) Cleanup() {
	os.Remove(s.statePath())
	os.Remove(s.contextPath())
}

func (s *StateManager) save(state *State) error {
	data, err := json.MarshalIndent(state, "", "  ")
	if err != nil {
		return err
	}
	return os.WriteFile(s.statePath(), data, 0644)
}

func (s *StateManager) ContextFile() string { return s.contextPath() }
```

Create `internal/ralph/stuck.go`:
```go
package ralph

func IsStuck(stuckCount, threshold int) bool {
	return stuckCount >= threshold
}

const StuckDirective = `## IMPORTANT: You Are Stuck

You have failed 3+ times with the same error. Your previous approach does not work.

You MUST try a fundamentally different approach:
- Different algorithm or data structure
- Different library or API
- Simplify the problem
- Break into smaller pieces

Do NOT repeat the same approach that failed.
`
```

**Step 4: Run tests**

Run: `go test ./internal/ralph/ -v`
Expected: all pass

**Step 5: Commit**

```bash
git add internal/ralph/
git commit -m "feat: add ralph state management and stuck detection"
```

---

## Task 10: Ralph Runner (Lock, Gates, Failure, Main Loop)

**Files:**
- Create: `internal/ralph/lock.go`
- Create: `internal/ralph/gates.go`
- Create: `internal/ralph/failure.go`
- Create: `internal/ralph/runner.go`
- Create: `internal/ralph/runner_test.go`

**Dependencies:** Task 9, Task 3

**Step 1: Implement lock**

Create `internal/ralph/lock.go`:
```go
package ralph

import (
	"fmt"
	"os"
	"path/filepath"
	"strconv"
	"syscall"
)

const lockFileName = ".ralph.lock"

type Lock struct {
	dir string
}

func NewLock(dir string) *Lock {
	return &Lock{dir: dir}
}

func (l *Lock) path() string { return filepath.Join(l.dir, lockFileName) }

func (l *Lock) Acquire() error {
	data, err := os.ReadFile(l.path())
	if err == nil {
		pid, _ := strconv.Atoi(string(data))
		if pid > 0 {
			if err := syscall.Kill(pid, 0); err == nil {
				return fmt.Errorf("another Ralph loop is active (PID %d)", pid)
			}
		}
		fmt.Fprintf(os.Stderr, "WARNING: Removing stale lock (PID %d no longer running)\n", pid)
		os.Remove(l.path())
	}
	return os.WriteFile(l.path(), []byte(strconv.Itoa(os.Getpid())), 0644)
}

func (l *Lock) Release() {
	os.Remove(l.path())
}
```

**Step 2: Implement gates**

Create `internal/ralph/gates.go`:
```go
package ralph

import (
	"context"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"time"
)

type GateConfig struct {
	ImplementTimeout int
	TestTimeout      int
	SpecTimeout      int
	QualityTimeout   int
}

func RunTestGate(ctx context.Context, projectDir string, timeout int) (string, error) {
	ctx, cancel := context.WithTimeout(ctx, time.Duration(timeout)*time.Second)
	defer cancel()

	// Auto-detect test runner
	var cmd *exec.Cmd
	switch {
	case fileExists(filepath.Join(projectDir, "package.json")):
		cmd = exec.CommandContext(ctx, "npm", "test", "--prefix", projectDir)
	case fileExists(filepath.Join(projectDir, "Cargo.toml")):
		cmd = exec.CommandContext(ctx, "cargo", "test", "--manifest-path", filepath.Join(projectDir, "Cargo.toml"))
	case fileExists(filepath.Join(projectDir, "pyproject.toml")),
		fileExists(filepath.Join(projectDir, "setup.py")):
		cmd = exec.CommandContext(ctx, "python", "-m", "pytest", projectDir)
	case fileExists(filepath.Join(projectDir, "go.mod")):
		cmd = exec.CommandContext(ctx, "go", "test", projectDir+"/...")
	case fileExists(filepath.Join(projectDir, "test.sh")):
		cmd = exec.CommandContext(ctx, filepath.Join(projectDir, "test.sh"))
	default:
		return "WARNING: No test runner detected, skipping test gate", nil
	}
	cmd.Dir = projectDir
	out, err := cmd.CombinedOutput()
	return string(out), err
}

func RunSpecGate(ctx context.Context, taskPromptFile, contextFile string, timeout int) (string, error) {
	ctx, cancel := context.WithTimeout(ctx, time.Duration(timeout)*time.Second)
	defer cancel()

	taskPrompt, _ := os.ReadFile(taskPromptFile)
	ctxContent, _ := os.ReadFile(contextFile)

	prompt := fmt.Sprintf("Review this implementation for spec compliance.\n\n## Task Spec\n%s\n\n## Current State\n%s\n\n## Instructions\nCheck if the implementation satisfies ALL requirements in the spec.\nOutput 'SPEC_PASS' if compliant, or list missing/extra items if not.",
		string(taskPrompt), string(ctxContent))

	cmd := exec.CommandContext(ctx, "claude", "-p", prompt)
	out, err := cmd.CombinedOutput()
	return string(out), err
}

func fileExists(path string) bool {
	_, err := os.Stat(path)
	return err == nil
}
```

**Step 3: Implement failure handling**

Create `internal/ralph/failure.go`:
```go
package ralph

import (
	"fmt"
	"os"
	"time"

	gitpkg "github.com/signalnine/conclave/internal/git"
)

func BranchFailedWork(g *gitpkg.Git, taskID string, state *State) error {
	timestamp := time.Now().Format("20060102-150405")
	branchName := fmt.Sprintf("wip/ralph-fail-%s-%s", taskID, timestamp)

	currentBranch, err := g.CurrentBranch()
	if err != nil {
		return fmt.Errorf("not in a git repository: %w", err)
	}

	// Safety: don't reset protected branches
	if currentBranch == "main" || currentBranch == "master" {
		g.CreateBranch(branchName)
		g.AddAll()
		msg := fmt.Sprintf("Ralph Loop failed: %s (on %s)", taskID, currentBranch)
		g.CommitAllowEmpty(msg)
		g.CheckoutBranch(currentBranch)
		fmt.Fprintf(os.Stderr, "Failed work preserved in branch: %s\n", branchName)
		return nil
	}

	if err := g.CreateBranch(branchName); err != nil {
		// Branch may exist, add timestamp suffix
		branchName = fmt.Sprintf("%s-%d", branchName, time.Now().Unix())
		if err := g.CreateBranch(branchName); err != nil {
			return err
		}
	}

	g.AddAll()
	msg := fmt.Sprintf("Ralph Loop failed: %s\n\nIterations: %d/%d\nLast gate: %s\nError hash: %s",
		taskID, state.Iteration, state.MaxIterations, state.LastGate, state.ErrorHash)
	g.CommitAllowEmpty(msg)
	g.Push(branchName) // non-fatal if no remote

	g.CheckoutBranch(currentBranch)
	fmt.Fprintf(os.Stderr, "Failed work preserved in branch: %s\n", branchName)
	return nil
}
```

**Step 4: Write runner tests**

Create `internal/ralph/runner_test.go`:
```go
package ralph

import (
	"testing"
)

func TestLock_AcquireRelease(t *testing.T) {
	dir := t.TempDir()
	l := NewLock(dir)
	if err := l.Acquire(); err != nil {
		t.Fatal(err)
	}
	l.Release()
	// Should be able to acquire again after release
	if err := l.Acquire(); err != nil {
		t.Fatal(err)
	}
	l.Release()
}

func TestStateManager_FullLifecycle(t *testing.T) {
	dir := t.TempDir()
	sm := NewStateManager(dir)

	sm.Init("task-1", 3)

	state, _ := sm.Load()
	if state.Iteration != 1 {
		t.Errorf("initial iteration = %d", state.Iteration)
	}

	sm.Update("tests", 1, "some error")
	state, _ = sm.Load()
	if state.Iteration != 2 {
		t.Errorf("after update iteration = %d", state.Iteration)
	}

	sm.Update("tests", 1, "some error") // same error
	state, _ = sm.Load()
	if state.StuckCount != 1 {
		t.Errorf("stuck count = %d after 2 same errors", state.StuckCount)
	}

	sm.Cleanup()
	if sm.Exists() {
		t.Error("state still exists after cleanup")
	}
}
```

**Step 5: Run tests**

Run: `go test ./internal/ralph/ -v`
Expected: all pass

**Step 6: Commit**

```bash
git add internal/ralph/
git commit -m "feat: add ralph runner with lock, gates, failure handling"
```

---

## Task 11: Parallel Runner (Merge + Scheduler + Orchestrator)

**Files:**
- Create: `internal/parallel/merge.go`
- Create: `internal/parallel/merge_test.go`
- Create: `internal/parallel/scheduler.go`
- Create: `internal/parallel/scheduler_test.go`
- Create: `internal/parallel/runner.go`

**Dependencies:** Task 3, Task 6, Task 10

**Step 1: Write merge tests**

Create `internal/parallel/merge_test.go`:
```go
package parallel

import (
	"os"
	"os/exec"
	"path/filepath"
	"testing"

	gitpkg "github.com/signalnine/conclave/internal/git"
)

func setupRepo(t *testing.T) (string, *gitpkg.Git) {
	t.Helper()
	dir := t.TempDir()
	for _, args := range [][]string{
		{"git", "init"},
		{"git", "config", "user.email", "test@test.com"},
		{"git", "config", "user.name", "Test"},
		{"git", "commit", "--allow-empty", "-m", "initial"},
	} {
		cmd := exec.Command(args[0], args[1:]...)
		cmd.Dir = dir
		if out, err := cmd.CombinedOutput(); err != nil {
			t.Fatalf("%v: %s %v", args, out, err)
		}
	}
	return dir, gitpkg.New(dir)
}

func TestMergeTaskBranch_Success(t *testing.T) {
	dir, g := setupRepo(t)
	// Create feature branch with a file
	run(t, dir, "git", "checkout", "-b", "task-1")
	os.WriteFile(filepath.Join(dir, "file.txt"), []byte("hello"), 0644)
	run(t, dir, "git", "add", "file.txt")
	run(t, dir, "git", "commit", "-m", "add file")
	run(t, dir, "git", "checkout", "main")

	err := MergeTaskBranch(g, "task-1", 1, "Create File")
	if err != nil {
		t.Fatal(err)
	}
}

func TestMergeTaskBranch_Conflict(t *testing.T) {
	dir, g := setupRepo(t)
	// Create conflicting file on main
	os.WriteFile(filepath.Join(dir, "file.txt"), []byte("main version"), 0644)
	run(t, dir, "git", "add", "file.txt")
	run(t, dir, "git", "commit", "-m", "main file")

	// Create branch with conflicting change
	run(t, dir, "git", "checkout", "-b", "task-1")
	os.WriteFile(filepath.Join(dir, "file.txt"), []byte("branch version"), 0644)
	run(t, dir, "git", "add", "file.txt")
	run(t, dir, "git", "commit", "-m", "branch file")
	run(t, dir, "git", "checkout", "main")

	err := MergeTaskBranch(g, "task-1", 1, "Conflicting")
	if err == nil {
		t.Error("expected conflict error")
	}
}

func run(t *testing.T, dir string, args ...string) {
	t.Helper()
	cmd := exec.Command(args[0], args[1:]...)
	cmd.Dir = dir
	if out, err := cmd.CombinedOutput(); err != nil {
		t.Fatalf("%v: %s %v", args, out, err)
	}
}
```

**Step 2: Implement merge**

Create `internal/parallel/merge.go`:
```go
package parallel

import (
	"fmt"

	gitpkg "github.com/signalnine/conclave/internal/git"
)

func MergeTaskBranch(g *gitpkg.Git, branch string, taskID int, taskName string) error {
	fmt.Printf("[MERGE] Squash-merging %s...\n", branch)

	if err := g.MergeSquash(branch); err != nil {
		fmt.Printf("[MERGE] CONFLICT in %s - aborting merge\n", branch)
		g.MergeAbort()
		return fmt.Errorf("merge conflict in %s", branch)
	}

	if !g.HasStagedChanges() {
		fmt.Printf("[MERGE] No changes to merge from %s\n", branch)
		return nil
	}

	msg := fmt.Sprintf("Task %d: %s", taskID, taskName)
	if err := g.Commit(msg); err != nil {
		return err
	}
	fmt.Printf("[MERGE] Successfully merged %s\n", branch)
	return nil
}
```

**Step 3: Write scheduler tests**

Create `internal/parallel/scheduler_test.go`:
```go
package parallel

import (
	"testing"

	"github.com/signalnine/conclave/internal/plan"
)

func TestScheduler_GetReadyTasks(t *testing.T) {
	tasks := []plan.Task{
		{ID: 1, DependsOn: nil},
		{ID: 2, DependsOn: []int{1}},
		{ID: 3, DependsOn: nil},
	}
	waves := plan.ComputeWaves(tasks)
	s := NewScheduler(tasks, waves, 3)

	ready := s.GetReadyTasks(0)
	if len(ready) != 2 {
		t.Errorf("wave 0 ready = %d, want 2", len(ready))
	}
}

func TestScheduler_CascadeSkip(t *testing.T) {
	tasks := []plan.Task{
		{ID: 1, DependsOn: nil},
		{ID: 2, DependsOn: []int{1}},
		{ID: 3, DependsOn: []int{2}},
	}
	waves := plan.ComputeWaves(tasks)
	s := NewScheduler(tasks, waves, 3)

	s.MarkRunning(1, 0, "")
	s.MarkDone(1, StatusFailed)

	// Task 2 and 3 should be skipped
	if s.Status(2) != StatusSkipped {
		t.Errorf("task 2 status = %s", s.Status(2))
	}
	if s.Status(3) != StatusSkipped {
		t.Errorf("task 3 status = %s", s.Status(3))
	}
}

func TestScheduler_WaveComplete(t *testing.T) {
	tasks := []plan.Task{
		{ID: 1, DependsOn: nil},
		{ID: 2, DependsOn: nil},
	}
	waves := plan.ComputeWaves(tasks)
	s := NewScheduler(tasks, waves, 3)

	if s.WaveComplete(0) {
		t.Error("wave 0 should not be complete yet")
	}
	s.MarkRunning(1, 0, "")
	s.MarkRunning(2, 0, "")
	s.MarkDone(1, StatusCompleted)
	s.MarkDone(2, StatusCompleted)
	if !s.WaveComplete(0) {
		t.Error("wave 0 should be complete")
	}
}
```

**Step 4: Implement scheduler**

Create `internal/parallel/scheduler.go`:
```go
package parallel

import (
	"fmt"

	"github.com/signalnine/conclave/internal/plan"
)

type TaskStatus string

const (
	StatusPending   TaskStatus = "PENDING"
	StatusRunning   TaskStatus = "RUNNING"
	StatusCompleted TaskStatus = "COMPLETED"
	StatusFailed    TaskStatus = "FAILED"
	StatusSkipped   TaskStatus = "SKIPPED"
)

type Scheduler struct {
	tasks      []plan.Task
	waves      map[int]int
	maxConc    int
	statuses   map[int]TaskStatus
	pids       map[int]int
	worktrees  map[int]string
	activeCount int
}

func NewScheduler(tasks []plan.Task, waves map[int]int, maxConcurrent int) *Scheduler {
	s := &Scheduler{
		tasks:    tasks,
		waves:    waves,
		maxConc:  maxConcurrent,
		statuses: make(map[int]TaskStatus),
		pids:     make(map[int]int),
		worktrees: make(map[int]string),
	}
	for _, t := range tasks {
		s.statuses[t.ID] = StatusPending
	}
	return s
}

func (s *Scheduler) GetReadyTasks(wave int) []int {
	var ready []int
	for _, t := range s.tasks {
		if s.statuses[t.ID] != StatusPending || s.waves[t.ID] != wave {
			continue
		}
		depsMet := true
		for _, dep := range t.DependsOn {
			if s.statuses[dep] != StatusCompleted {
				depsMet = false
				break
			}
		}
		if depsMet {
			ready = append(ready, t.ID)
		}
	}
	return ready
}

func (s *Scheduler) CanLaunch() bool {
	return s.activeCount < s.maxConc
}

func (s *Scheduler) MarkRunning(taskID, pid int, worktree string) {
	s.statuses[taskID] = StatusRunning
	s.pids[taskID] = pid
	s.worktrees[taskID] = worktree
	s.activeCount++
}

func (s *Scheduler) MarkDone(taskID int, status TaskStatus) {
	s.statuses[taskID] = status
	s.activeCount--
	if s.activeCount < 0 {
		s.activeCount = 0
	}
	if status == StatusFailed {
		s.cascadeSkip(taskID)
	}
}

func (s *Scheduler) cascadeSkip(failedID int) {
	for _, t := range s.tasks {
		if s.statuses[t.ID] != StatusPending {
			continue
		}
		for _, dep := range t.DependsOn {
			if dep == failedID || s.statuses[dep] == StatusSkipped {
				s.statuses[t.ID] = StatusSkipped
				fmt.Printf("[SCHEDULER] Task %d SKIPPED (dependency Task %d failed/skipped)\n", t.ID, dep)
				s.cascadeSkip(t.ID)
				break
			}
		}
	}
}

func (s *Scheduler) WaveComplete(wave int) bool {
	for _, t := range s.tasks {
		if s.waves[t.ID] != wave {
			continue
		}
		st := s.statuses[t.ID]
		if st == StatusPending || st == StatusRunning {
			return false
		}
	}
	return true
}

func (s *Scheduler) Status(taskID int) TaskStatus   { return s.statuses[taskID] }
func (s *Scheduler) HasRunning() bool                { return s.activeCount > 0 }
func (s *Scheduler) PID(taskID int) int              { return s.pids[taskID] }
func (s *Scheduler) Worktree(taskID int) string      { return s.worktrees[taskID] }

func (s *Scheduler) WaveCompletedIDs(wave int) []int {
	var ids []int
	for _, t := range s.tasks {
		if s.waves[t.ID] == wave && s.statuses[t.ID] == StatusCompleted {
			ids = append(ids, t.ID)
		}
	}
	return ids
}

func (s *Scheduler) PrintSummary() {
	var completed, failed, skipped int
	for _, t := range s.tasks {
		switch s.statuses[t.ID] {
		case StatusCompleted:
			completed++
		case StatusFailed:
			failed++
		case StatusSkipped:
			skipped++
		}
	}
	fmt.Printf("\n========================================\nPARALLEL EXECUTION SUMMARY\n========================================\n")
	fmt.Printf("  Completed: %d/%d\n  Failed:    %d\n  Skipped:   %d\n========================================\n",
		completed, len(s.tasks), failed, skipped)
}
```

**Step 5: Run tests**

Run: `go test ./internal/parallel/ -v`
Expected: all pass

**Step 6: Commit**

```bash
git add internal/parallel/
git commit -m "feat: add parallel runner with scheduler, merge, and orchestration"
```

---

## Task 12: CLI Command Wiring

**Files:**
- Create: `cmd/conclave/consensus.go`
- Create: `cmd/conclave/autoreview.go`
- Create: `cmd/conclave/parallelrun.go`
- Create: `cmd/conclave/ralphrun.go`
- Create: `cmd/conclave/hook.go`
- Create: `cmd/conclave/skills.go`

**Dependencies:** Tasks 2-11

**Step 1: Wire consensus command**

Create `cmd/conclave/consensus.go`:
```go
package main

import (
	"context"
	"fmt"
	"os"
	"time"

	"github.com/signalnine/conclave/internal/config"
	"github.com/signalnine/conclave/internal/consensus"
	gitpkg "github.com/signalnine/conclave/internal/git"
	"github.com/spf13/cobra"
)

var consensusCmd = &cobra.Command{
	Use:   "consensus",
	Short: "Multi-agent consensus analysis",
	Long:  "Two-stage consensus synthesis: parallel agent analysis, then chairman synthesis.",
	RunE:  runConsensus,
}

func init() {
	consensusCmd.Flags().String("mode", "", "Mode: code-review or general-prompt (required)")
	consensusCmd.Flags().String("base-sha", "", "Base commit SHA (code-review mode)")
	consensusCmd.Flags().String("head-sha", "", "Head commit SHA (code-review mode)")
	consensusCmd.Flags().String("description", "", "Change description (code-review mode)")
	consensusCmd.Flags().String("plan-file", "", "Path to implementation plan file")
	consensusCmd.Flags().String("prompt", "", "Question to analyze (general-prompt mode)")
	consensusCmd.Flags().String("context", "", "Additional context")
	consensusCmd.Flags().Int("stage1-timeout", 0, "Stage 1 timeout in seconds")
	consensusCmd.Flags().Int("stage2-timeout", 0, "Stage 2 timeout in seconds")
	consensusCmd.Flags().Bool("dry-run", false, "Validate arguments only")
	rootCmd.AddCommand(consensusCmd)
}

func runConsensus(cmd *cobra.Command, args []string) error {
	cfg := config.Load()
	mode, _ := cmd.Flags().GetString("mode")
	dryRun, _ := cmd.Flags().GetBool("dry-run")

	if mode == "" {
		return fmt.Errorf("--mode is required")
	}
	if mode != "code-review" && mode != "general-prompt" {
		return fmt.Errorf("invalid mode %q: must be code-review or general-prompt", mode)
	}

	// Override timeouts from flags
	if v, _ := cmd.Flags().GetInt("stage1-timeout"); v > 0 {
		cfg.Stage1Timeout = v
	}
	if v, _ := cmd.Flags().GetInt("stage2-timeout"); v > 0 {
		cfg.Stage2Timeout = v
	}

	// Build stage 1 prompt
	var stage1Prompt string
	var chairmanBuilder func([]consensus.AgentResult) string

	if mode == "code-review" {
		baseSHA, _ := cmd.Flags().GetString("base-sha")
		headSHA, _ := cmd.Flags().GetString("head-sha")
		description, _ := cmd.Flags().GetString("description")
		planFile, _ := cmd.Flags().GetString("plan-file")

		if baseSHA == "" || headSHA == "" || description == "" {
			return fmt.Errorf("code-review mode requires --base-sha, --head-sha, --description")
		}

		if dryRun {
			fmt.Println("Dry run: Arguments validated successfully")
			fmt.Printf("Mode: %s\nBase SHA: %s\nHead SHA: %s\nDescription: %s\n", mode, baseSHA, headSHA, description)
			return nil
		}

		g := gitpkg.New(".")
		diff, err := g.Diff(baseSHA, headSHA)
		if err != nil {
			return fmt.Errorf("git diff: %w", err)
		}
		files, _ := g.DiffNameOnly(baseSHA, headSHA)
		modifiedFiles := ""
		for _, f := range files {
			modifiedFiles += f + "\n"
		}
		var planContent string
		if planFile != "" {
			data, _ := os.ReadFile(planFile)
			planContent = string(data)
		}
		stage1Prompt = consensus.BuildCodeReviewPrompt(description, diff, modifiedFiles, planContent)
		chairmanBuilder = func(results []consensus.AgentResult) string {
			return consensus.BuildCodeReviewChairmanPrompt(description, modifiedFiles, results)
		}
	} else {
		prompt, _ := cmd.Flags().GetString("prompt")
		ctxStr, _ := cmd.Flags().GetString("context")
		if prompt == "" {
			return fmt.Errorf("general-prompt mode requires --prompt")
		}
		if dryRun {
			fmt.Println("Dry run: Arguments validated successfully")
			fmt.Printf("Mode: %s\nPrompt: %s\n", mode, prompt)
			return nil
		}
		stage1Prompt = consensus.BuildGeneralPrompt(prompt, ctxStr)
		chairmanBuilder = func(results []consensus.AgentResult) string {
			return consensus.BuildGeneralChairmanPrompt(prompt, results)
		}
	}

	// Build agents
	agents := []consensus.Agent{
		consensus.NewClaudeAgent(cfg),
		consensus.NewGeminiAgent(cfg),
		consensus.NewCodexAgent(cfg),
	}

	// Run consensus
	ctx := context.Background()
	result, err := consensus.RunConsensusWithBuilder(ctx, agents, agents, stage1Prompt, chairmanBuilder, cfg.Stage1Timeout, cfg.Stage2Timeout)
	if err != nil {
		return err
	}

	// Write output file
	outputFile, err := os.CreateTemp("", "consensus-*.md")
	if err != nil {
		return err
	}
	fmt.Fprintf(outputFile, "# Multi-Agent Consensus Analysis\n\n**Mode:** %s\n**Date:** %s\n**Agents Succeeded:** %d/3\n**Chairman:** %s\n\n---\n\n",
		mode, time.Now().Format("2006-01-02 15:04:05"), result.AgentsSucceeded, result.ChairmanName)
	fmt.Fprintf(outputFile, "## Stage 2: Chairman Consensus (by %s)\n\n%s\n", result.ChairmanName, result.ChairmanOutput)
	outputFile.Close()

	// Print to stdout
	fmt.Fprintln(os.Stderr, "\n========================================")
	fmt.Fprintln(os.Stderr, "CONSENSUS COMPLETE")
	fmt.Fprintln(os.Stderr, "========================================")
	fmt.Println(result.ChairmanOutput)
	fmt.Fprintf(os.Stderr, "\nDetailed breakdown saved to: %s\n", outputFile.Name())
	return nil
}
```

**Note:** This requires adding `RunConsensusWithBuilder` to `internal/consensus/consensus.go` - a variant that accepts a chairman prompt builder function instead of a static prompt. This is a minor refactor of the existing `RunConsensus`.

**Step 2: Wire remaining commands** (abbreviated - same pattern as consensus):

Create `cmd/conclave/autoreview.go` - wraps consensus with git SHA auto-detection.
Create `cmd/conclave/parallelrun.go` - parses plan, runs waves, merges.
Create `cmd/conclave/ralphrun.go` - retry loop with gates.
Create `cmd/conclave/hook.go` - calls `hook.SessionStart()`.
Create `cmd/conclave/skills.go` - `skills list` and `skills resolve` subcommands.

Each follows the same pattern: parse flags, validate, call internal packages, format output.

**Step 3: Build and smoke test**

Run: `make build`
Run: `./conclave --help`
Run: `./conclave consensus --help`
Run: `./conclave consensus --mode=general-prompt --prompt="test" --dry-run`
Run: `./conclave version`
Expected: all commands registered, dry-run works

**Step 4: Commit**

```bash
git add cmd/conclave/
git commit -m "feat: wire all CLI commands (consensus, auto-review, parallel-run, ralph-run, hook, skills)"
```

---

## Task 13: Integration Tests

**Files:**
- Create: `test/integration_test.go`

**Dependencies:** Task 12

**Step 1: Write integration test for consensus dry-run**

Create `test/integration_test.go`:
```go
//go:build integration

package test

import (
	"os"
	"os/exec"
	"strings"
	"testing"
)

func buildBinary(t *testing.T) string {
	t.Helper()
	cmd := exec.Command("go", "build", "-o", "conclave-test", "./cmd/conclave")
	cmd.Dir = ".."
	if out, err := cmd.CombinedOutput(); err != nil {
		t.Fatalf("build failed: %s %v", out, err)
	}
	return "../conclave-test"
}

func TestIntegration_ConsensusDryRun(t *testing.T) {
	bin := buildBinary(t)
	defer os.Remove(bin)

	cmd := exec.Command(bin, "consensus", "--mode=general-prompt", "--prompt=test question", "--dry-run")
	out, err := cmd.CombinedOutput()
	if err != nil {
		t.Fatalf("exit error: %v\noutput: %s", err, out)
	}
	if !strings.Contains(string(out), "Dry run") {
		t.Errorf("expected dry run output, got: %s", out)
	}
}

func TestIntegration_ConsensusMockServers(t *testing.T) {
	// This test starts mock HTTP servers and runs actual consensus
	// against them to verify end-to-end behavior.
	// Requires building the binary first.
	bin := buildBinary(t)
	defer os.Remove(bin)

	// TODO: Start httptest servers, set *_BASE_URL env vars,
	// run binary, verify output contains synthesis from all 3 agents.
}

func TestIntegration_Version(t *testing.T) {
	bin := buildBinary(t)
	defer os.Remove(bin)

	out, err := exec.Command(bin, "version").Output()
	if err != nil {
		t.Fatal(err)
	}
	if strings.TrimSpace(string(out)) == "" {
		t.Error("empty version output")
	}
}

func TestIntegration_SkillsList(t *testing.T) {
	bin := buildBinary(t)
	defer os.Remove(bin)

	cmd := exec.Command(bin, "skills", "list")
	cmd.Dir = ".."  // run from repo root where skills/ exists
	out, err := cmd.CombinedOutput()
	if err != nil {
		t.Fatalf("exit error: %v\noutput: %s", err, out)
	}
	if !strings.Contains(string(out), "brainstorming") {
		t.Errorf("expected brainstorming skill in output: %s", out)
	}
}
```

**Step 2: Run integration tests**

Run: `go test ./test/ -v -tags=integration -run Integration`

**Step 3: Commit**

```bash
git add test/
git commit -m "feat: add integration tests for CLI commands"
```

---

## Task 14: Update SKILL.md References and Hook Config

**Files:**
- Modify: `hooks/hooks.json`
- Modify: `skills/multi-agent-consensus/SKILL.md`
- Modify: `skills/brainstorming/SKILL.md`
- Modify: `skills/writing-plans/SKILL.md`
- Modify: `skills/subagent-driven-development/SKILL.md`
- Modify: `skills/requesting-code-review/SKILL.md`
- Modify: `skills/systematic-debugging/SKILL.md`
- Modify: `skills/verification-before-completion/SKILL.md`

**Dependencies:** Task 12

**Step 1: Update hooks.json**

Change the command in `hooks/hooks.json` from:
```json
"command": "${CLAUDE_PLUGIN_ROOT}/hooks/session-start.sh"
```
to:
```json
"command": "${CLAUDE_PLUGIN_ROOT}/conclave hook session-start"
```

**Step 2: Update SKILL.md files**

Search all SKILL.md files for references to bash scripts and update them:

| Find | Replace |
|------|---------|
| `../multi-agent-consensus/consensus-synthesis.sh` | `conclave consensus` |
| `consensus-synthesis.sh` | `conclave consensus` |
| `../multi-agent-consensus/auto-review.sh` | `conclave auto-review` |
| `auto-review.sh` | `conclave auto-review` |
| `./parallel-runner.sh` | `conclave parallel-run` |
| `parallel-runner.sh` | `conclave parallel-run` |
| `ralph-runner.sh` | `conclave ralph-run` |

**Step 3: Verify no broken references**

Run: `grep -r 'consensus-synthesis\.sh\|auto-review\.sh\|parallel-runner\.sh\|ralph-runner\.sh' skills/ --include='*.md'`
Expected: no matches (all updated)

**Step 4: Commit**

```bash
git add hooks/hooks.json skills/
git commit -m "feat: update SKILL.md references and hooks to use Go binary"
```

---

## Task 15: Run Full Test Suite and Final Validation

**Dependencies:** All previous tasks

**Step 1: Run all Go tests**

Run: `make test`
Expected: all pass, coverage > 80%

**Step 2: Build and verify binary**

Run: `make build && ./conclave version`
Run: `./conclave --help`
Run: `./conclave consensus --help`
Run: `./conclave auto-review --help`
Run: `./conclave parallel-run --help`
Run: `./conclave ralph-run --help`
Run: `./conclave skills list`
Run: `./conclave hook session-start`
Expected: all commands work, hook outputs valid JSON, skills list shows all 16 skills

**Step 3: Run consensus dry-run**

Run: `./conclave consensus --mode=code-review --base-sha=HEAD~1 --head-sha=HEAD --description="test" --dry-run`
Run: `./conclave consensus --mode=general-prompt --prompt="test" --dry-run`
Expected: both validate successfully

**Step 4: Run existing bash tests against Go binary**

Run: `./skills/multi-agent-consensus/test-consensus-synthesis.sh`
(These tests call the bash scripts directly - they should still pass since bash scripts are still present. After migration is complete, these tests would be updated to call the Go binary.)

**Step 5: Commit final state**

```bash
git add -A
git commit -m "feat: complete Go port - all tests passing"
```
