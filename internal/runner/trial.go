package runner

import (
	"context"
	"fmt"
	"log"
	"os"
	"path/filepath"
	"strings"
	"time"

	"github.com/signalnine/thunderdome/internal/config"
	"github.com/signalnine/thunderdome/internal/docker"
	"github.com/signalnine/thunderdome/internal/gateway"
	"github.com/signalnine/thunderdome/internal/gitops"
	"github.com/signalnine/thunderdome/internal/result"
	"github.com/signalnine/thunderdome/internal/validation"
)

type TrialOpts struct {
	Orchestrator    *config.Orchestrator
	Task            *config.Task
	TrialNum        int
	GatewayURL      string
	GatewayAddr     string
	GatewayUsageLog string
	RunDir          string
	Timeout         time.Duration
	Allowlist       []string
	CPULimit        float64
	MemoryLimit     int64
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
	return []string{"bash", "/adapter.sh"}
}

func RunTrial(ctx context.Context, opts *TrialOpts) (*result.TrialMeta, error) {
	trialDir := result.TrialDir(opts.RunDir, opts.Orchestrator.Name, TaskName(opts.Task), opts.TrialNum)
	if err := os.MkdirAll(trialDir, 0o755); err != nil {
		return nil, fmt.Errorf("creating trial dir: %w", err)
	}

	workDir := filepath.Join(trialDir, "workspace")
	if err := gitops.CloneAndCheckout(opts.Task.Repo, opts.Task.Tag, workDir); err != nil {
		return nil, fmt.Errorf("cloning task repo: %w", err)
	}

	taskDescPath := filepath.Join(trialDir, "task.md")
	taskDescInRepo := filepath.Join(workDir, "TASK.md")
	if data, err := os.ReadFile(taskDescInRepo); err == nil {
		if writeErr := os.WriteFile(taskDescPath, data, 0o644); writeErr != nil {
			log.Printf("warning: writing task description: %v", writeErr)
		}
	} else {
		if writeErr := os.WriteFile(taskDescPath, []byte("No task description available"), 0o644); writeErr != nil {
			log.Printf("warning: writing task description: %v", writeErr)
		}
	}

	adapterAbs, err := filepath.Abs(opts.Orchestrator.Adapter)
	if err != nil {
		return nil, fmt.Errorf("resolving adapter path: %w", err)
	}

	// Replace localhost with host.docker.internal so the container can
	// reach the gateway running on the host.
	containerGatewayURL := ""
	if opts.GatewayURL != "" {
		containerGatewayURL = strings.Replace(opts.GatewayURL, "localhost", "host.docker.internal", 1)
	}
	env := map[string]string{
		"TASK_DIR":         "/workspace",
		"TASK_DESCRIPTION": "/task.md",
		"PROXY_URL":        containerGatewayURL,
	}
	for k, v := range opts.Orchestrator.Env {
		env[k] = v
	}

	hostUID := fmt.Sprintf("%d:%d", os.Getuid(), os.Getgid())

	extraMounts := []docker.Mount{
		{Source: adapterAbs, Target: "/adapter.sh", ReadOnly: true},
		{Source: taskDescPath, Target: "/task.md", ReadOnly: true},
	}

	// Mount host ~/.claude/.credentials.json to /tmp if it exists.
	// The adapter script copies it into a writable ~/.claude/ dir at runtime.
	if home, err := os.UserHomeDir(); err == nil {
		credsFile := filepath.Join(home, ".claude", ".credentials.json")
		if _, err := os.Stat(credsFile); err == nil {
			extraMounts = append(extraMounts, docker.Mount{
				Source: credsFile, Target: "/tmp/.claude-credentials.json", ReadOnly: true,
			})
		}
	}

	containerResult, err := docker.RunContainer(ctx, &docker.RunOpts{
		Image:       opts.Orchestrator.Image,
		Command:     BuildAdapterCommand(opts.Orchestrator, "/workspace", "/task.md", opts.GatewayURL),
		WorkDir:     workDir,
		Env:         env,
		Timeout:     opts.Timeout,
		ExtraMounts: extraMounts,
		Allowlist:   opts.Allowlist,
		GatewayAddr: opts.GatewayAddr,
		CPULimit:    opts.CPULimit,
		MemoryLimit: opts.MemoryLimit,
		UserID:      hostUID,
	})
	if err != nil {
		return nil, fmt.Errorf("running container: %w", err)
	}

	diff, err := gitops.CaptureChanges(workDir)
	if err != nil {
		return nil, fmt.Errorf("capturing changes: %w", err)
	}
	if err := os.WriteFile(filepath.Join(trialDir, "diff.patch"), diff, 0o644); err != nil {
		return nil, fmt.Errorf("writing diff.patch: %w", err)
	}

	var totalTokens int
	var totalCostUSD float64
	if opts.GatewayUsageLog != "" {
		records, err := gateway.ParseUsageLogs(opts.GatewayUsageLog)
		if err == nil {
			inTok, outTok := gateway.TotalUsage(records)
			totalTokens = inTok + outTok
			totalCostUSD = gateway.EstimateCost(records)
		}
	}

	meta := &result.TrialMeta{
		Orchestrator: opts.Orchestrator.Name,
		Task:         TaskName(opts.Task),
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

func TaskName(t *config.Task) string {
	return filepath.Base(t.Repo)
}

// ValidateAndScore runs the validation pipeline (tests, lint, rubric judge)
// against a completed trial and updates the meta with scores.
func ValidateAndScore(ctx context.Context, trialDir string, task *config.Task, gatewayURL string) (*result.TrialMeta, error) {
	meta, err := result.ReadTrialMeta(filepath.Join(trialDir, "meta.json"))
	if err != nil {
		return nil, fmt.Errorf("reading trial meta: %w", err)
	}

	workDir := filepath.Join(trialDir, "workspace")

	if task.Greenfield {
		return validateGreenfield(ctx, trialDir, workDir, meta, task, gatewayURL)
	}
	return validateStandard(ctx, trialDir, workDir, meta, task, gatewayURL)
}

// validateStandard runs the original validation pipeline for non-greenfield tasks.
func validateStandard(ctx context.Context, trialDir, workDir string, meta *result.TrialMeta, task *config.Task, gatewayURL string) (*result.TrialMeta, error) {
	// Run tests
	testResult, err := validation.RunTests(ctx, workDir, task.ValidationImage, task.InstallCmd, task.TestCmd)
	if err != nil {
		log.Printf("warning: tests failed for %s trial %d: %v", meta.Task, meta.Trial, err)
	} else {
		meta.Scores.Tests = testResult.Score
	}

	// Run lint
	lintResult, err := validation.RunLint(ctx, workDir, task.ValidationImage, task.LintCmd, 0)
	if err != nil {
		log.Printf("warning: lint failed for %s trial %d: %v", meta.Task, meta.Trial, err)
	} else {
		meta.Scores.StaticAnalysis = lintResult.Score
	}

	// Run rubric judge
	diff, _ := os.ReadFile(filepath.Join(trialDir, "diff.patch"))
	taskDesc, _ := os.ReadFile(filepath.Join(trialDir, "task.md"))
	rubricScores, err := validation.RunRubricJudge(ctx, gatewayURL, task.Rubric, string(diff), string(taskDesc))
	if err != nil {
		log.Printf("warning: rubric judge failed for %s trial %d: %v", meta.Task, meta.Trial, err)
	} else {
		meta.Scores.Rubric = validation.ComputeRubricScore(task.Rubric, rubricScores)
	}

	// Compute composite score
	meta.CompositeScore = validation.CompositeScore(meta.Scores, task.Weights)

	if err := result.WriteTrialMeta(trialDir, meta); err != nil {
		return nil, fmt.Errorf("writing updated meta: %w", err)
	}
	return meta, nil
}

// validateGreenfield runs the greenfield validation pipeline.
// Agent tests + coverage run BEFORE hidden test injection to avoid interference.
func validateGreenfield(ctx context.Context, trialDir, workDir string, meta *result.TrialMeta, task *config.Task, gatewayURL string) (*result.TrialMeta, error) {
	// 1. Run agent's own tests BEFORE injecting hidden tests
	if task.TestCmd != "" {
		agentTestResult, err := validation.RunTests(ctx, workDir, task.ValidationImage, task.InstallCmd, task.TestCmd)
		if err != nil {
			log.Printf("warning: agent tests failed for %s trial %d: %v", meta.Task, meta.Trial, err)
		} else {
			meta.Scores.AgentTests = agentTestResult.Score
		}
	}

	// 2. Run coverage on agent's tests BEFORE injecting hidden tests
	coverageResult, err := validation.RunCoverage(ctx, workDir, task.ValidationImage, task.InstallCmd)
	if err != nil {
		log.Printf("warning: coverage failed for %s trial %d: %v", meta.Task, meta.Trial, err)
	} else {
		meta.Scores.Coverage = coverageResult.Score
	}

	// 3. Code metrics (doesn't depend on test injection order)
	metricsResult, err := validation.RunCodeMetrics(workDir)
	if err != nil {
		log.Printf("warning: code metrics failed for %s trial %d: %v", meta.Task, meta.Trial, err)
	} else {
		meta.Scores.CodeMetrics = metricsResult.Score
	}

	// 4. Run lint
	lintResult, err := validation.RunLint(ctx, workDir, task.ValidationImage, task.LintCmd, 0)
	if err != nil {
		log.Printf("warning: lint failed for %s trial %d: %v", meta.Task, meta.Trial, err)
	} else {
		meta.Scores.StaticAnalysis = lintResult.Score
	}

	// 5. NOW inject and run hidden behavioral tests
	cleanup, err := validation.InjectHiddenTests(task.Repo, task.ValidationTag, workDir)
	if err != nil {
		log.Printf("warning: could not inject hidden tests for %s trial %d: %v", meta.Task, meta.Trial, err)
	} else {
		defer cleanup()
		hiddenResult, err := validation.RunHiddenTests(ctx, workDir, task.ValidationImage, task.InstallCmd)
		if err != nil {
			log.Printf("warning: hidden tests failed for %s trial %d: %v", meta.Task, meta.Trial, err)
		} else {
			meta.Scores.HiddenTests = hiddenResult.Score
		}
	}

	// 6. Rubric judge
	diff, _ := os.ReadFile(filepath.Join(trialDir, "diff.patch"))
	taskDesc, _ := os.ReadFile(filepath.Join(trialDir, "task.md"))
	rubricScores, err := validation.RunRubricJudge(ctx, gatewayURL, task.Rubric, string(diff), string(taskDesc))
	if err != nil {
		log.Printf("warning: rubric judge failed for %s trial %d: %v", meta.Task, meta.Trial, err)
	} else {
		meta.Scores.Rubric = validation.ComputeRubricScore(task.Rubric, rubricScores)
	}

	// Compute greenfield composite score
	meta.CompositeScore = validation.GreenfieldCompositeScore(meta.Scores, task.GreenWeights)

	if err := result.WriteTrialMeta(trialDir, meta); err != nil {
		return nil, fmt.Errorf("writing updated meta: %w", err)
	}
	return meta, nil
}
