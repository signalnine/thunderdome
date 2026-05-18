package runner

import (
	"context"
	"encoding/json"
	"fmt"
	"log"
	"net"
	"net/url"
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
	case 124:
		return "timeout"
	case 125:
		return "infra_error"
	case 130:
		return "cancelled"
	case 137:
		return "oom_killed"
	default:
		return "crashed"
	}
}

// HasWorkspaceChanges reports whether the captured diff includes changes
// to any file that is not a runtime artifact written by the adapter
// (metrics file, stdout NDJSON capture, amplifier log, core dumps).
// Empty input (no diff at all) returns false. Uses the same artifact
// set as gitops.stripNonRepoHunks so the two stay aligned.
func HasWorkspaceChanges(diff []byte) bool {
	if len(diff) == 0 {
		return false
	}
	for _, line := range strings.Split(string(diff), "\n") {
		if !strings.HasPrefix(line, "diff --git ") {
			continue
		}
		if !gitops.IsRuntimeArtifactDiffHeader(line) {
			return true
		}
	}
	return false
}

// DetectNoAgentContribution returns true when the agent didn't meaningfully
// contribute to the workspace. This happens when the adapter crashes
// immediately (auth failure, startup error) -- the workspace still has
// starter code that gets scored, inflating means.
//
// Detection uses workspace state (empty diff) as the primary signal,
// because totalTokens is unreliable when usage tracking isn't wired up
// (e.g. gateway: none with an adapter that doesn't write metrics, or
// writes them in a stale schema). The early-crash heuristic catches
// adapters that crash before producing any output at all.
func DetectNoAgentContribution(exitReason string, durationS int, hasChanges bool) bool {
	if !hasChanges {
		return true
	}
	switch exitReason {
	case "completed", "timeout", "cancelled", "infra_error":
		return false
	}
	if durationS < 30 {
		return true
	}
	return false
}

func BuildAdapterCommand() []string {
	return []string{"bash", "/adapter.sh"}
}

// RewriteGatewayURLForContainer rewrites loopback hosts (localhost, 127.0.0.1,
// ::1, or any 127.0.0.0/8 / ::1 address) to host.docker.internal so the
// container can reach the gateway running on the host's netns. Empty input
// returns empty. Unparseable input or non-loopback hosts are returned as-is.
func RewriteGatewayURLForContainer(rawURL string) string {
	if rawURL == "" {
		return ""
	}
	u, err := url.Parse(rawURL)
	if err != nil {
		return rawURL
	}
	host := u.Hostname()
	if !isLoopbackHost(host) {
		return rawURL
	}
	if port := u.Port(); port != "" {
		u.Host = net.JoinHostPort("host.docker.internal", port)
	} else {
		u.Host = "host.docker.internal"
	}
	return u.String()
}

func isLoopbackHost(host string) bool {
	if host == "" {
		return false
	}
	if strings.EqualFold(host, "localhost") {
		return true
	}
	ip := net.ParseIP(host)
	if ip == nil {
		return false
	}
	return ip.IsLoopback()
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

	containerGatewayURL := RewriteGatewayURLForContainer(opts.GatewayURL)
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

		// Mount host ~/.gemini to /tmp/.gemini-host if it exists (for Gemini CLI OAuth).
		geminiDir := filepath.Join(home, ".gemini")
		if info, err := os.Stat(geminiDir); err == nil && info.IsDir() {
			extraMounts = append(extraMounts, docker.Mount{
				Source: geminiDir, Target: "/tmp/.gemini-host", ReadOnly: true,
			})
		}

		// Mount host ~/.codex/auth.json and config.toml for Codex CLI ChatGPT OAuth.
		codexAuth := filepath.Join(home, ".codex", "auth.json")
		if _, err := os.Stat(codexAuth); err == nil {
			extraMounts = append(extraMounts, docker.Mount{
				Source: codexAuth, Target: "/tmp/.codex-auth.json", ReadOnly: true,
			})
		}
		codexConfig := filepath.Join(home, ".codex", "config.toml")
		if _, err := os.Stat(codexConfig); err == nil {
			extraMounts = append(extraMounts, docker.Mount{
				Source: codexConfig, Target: "/tmp/.codex-config.toml", ReadOnly: true,
			})
		}
	}

	trialStart := time.Now()
	containerResult, err := docker.RunContainer(ctx, &docker.RunOpts{
		Image:       opts.Orchestrator.Image,
		Command:     BuildAdapterCommand(),
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
		err = fmt.Errorf("running container: %w", err)
		crashMeta := SynthesizeCrashMeta(opts.Task, opts.Orchestrator.Name, opts.TrialNum, err)
		if writeErr := result.WriteTrialMeta(trialDir, crashMeta); writeErr != nil {
			log.Printf("warn: failed to write crash meta for %s/%s trial %d: %v",
				opts.Orchestrator.Name, TaskName(opts.Task), opts.TrialNum, writeErr)
		}
		return nil, err
	}
	trialEnd := time.Now()

	diff, err := gitops.CaptureChanges(workDir)
	if err != nil {
		err = fmt.Errorf("capturing changes: %w", err)
		crashMeta := SynthesizeCrashMeta(opts.Task, opts.Orchestrator.Name, opts.TrialNum, err)
		if writeErr := result.WriteTrialMeta(trialDir, crashMeta); writeErr != nil {
			log.Printf("warn: failed to write crash meta for %s/%s trial %d: %v",
				opts.Orchestrator.Name, TaskName(opts.Task), opts.TrialNum, writeErr)
		}
		return nil, err
	}
	if err := os.WriteFile(filepath.Join(trialDir, "diff.patch"), diff, 0o644); err != nil {
		return nil, fmt.Errorf("writing diff.patch: %w", err)
	}

	// Slice the shared gateway usage log to a per-trial proxy-log.jsonl using
	// the wall-clock window we just bracketed. enrichCosts (report.go) reads
	// this per-trial file; without slicing, sequential or parallel trials
	// would all see the same shared log and double-count records. The slice
	// also widens to [start-1s, end+1s] to tolerate small clock skew between
	// the proxy's time.time() and Go's time.Now().
	trialProxyLog := filepath.Join(trialDir, "proxy-log.jsonl")
	startTS := float64(trialStart.Unix()) - 1
	endTS := float64(trialEnd.Unix()) + 1
	if opts.GatewayUsageLog != "" {
		if _, err := gateway.SliceUsageLog(opts.GatewayUsageLog, trialProxyLog, startTS, endTS); err != nil {
			log.Printf("gateway: slicing usage log for trial %s: %v", trialDir, err)
		}
	}

	var totalTokens int
	var totalCostUSD float64
	if opts.GatewayUsageLog != "" {
		records, malformed, err := gateway.ParseUsageLogs(trialProxyLog)
		if err == nil {
			if malformed > 0 {
				log.Printf("gateway: %d malformed line(s) in usage log %s -- token totals may understate actual usage",
					malformed, trialProxyLog)
			}
			totalTokens = gateway.TotalTokens(records)
			totalCostUSD = gateway.EstimateCost(records)
		}
	}

	// Fallback: read adapter-written metrics file if gateway didn't capture usage.
	if totalTokens == 0 {
		metricsPath := filepath.Join(workDir, ".thunderdome-metrics.json")
		if data, err := os.ReadFile(metricsPath); err == nil {
			var adapterMetrics struct {
				InputTokens        int     `json:"input_tokens"`
				OutputTokens       int     `json:"output_tokens"`
				CacheReadTokens    int     `json:"cache_read_tokens"`
				CacheCreationTokens int    `json:"cache_creation_tokens"`
				TotalCostUSD       float64 `json:"total_cost_usd"`
			}
			if err := json.Unmarshal(data, &adapterMetrics); err == nil {
				totalTokens = adapterMetrics.InputTokens + adapterMetrics.OutputTokens + adapterMetrics.CacheReadTokens + adapterMetrics.CacheCreationTokens
				totalCostUSD = adapterMetrics.TotalCostUSD
			}
		}
	}

	exitReason := ExitReasonFromCode(containerResult.ExitCode, containerResult.TimedOut)
	durationS := int(containerResult.Duration.Seconds())
	wallClockMS := containerResult.Duration.Milliseconds()

	meta := &result.TrialMeta{
		Orchestrator: opts.Orchestrator.Name,
		Task:         TaskName(opts.Task),
		Trial:        opts.TrialNum,
		DurationS:    durationS,
		WallClockMS:  wallClockMS,
		ExitCode:     containerResult.ExitCode,
		ExitReason:   exitReason,
		TotalTokens:  totalTokens,
		TotalCostUSD: totalCostUSD,
		Category:     opts.Task.Category,
	}

	meta.NoAgentContribution = DetectNoAgentContribution(exitReason, durationS, HasWorkspaceChanges(diff))
	if err := result.WriteTrialMeta(trialDir, meta); err != nil {
		return nil, fmt.Errorf("writing meta: %w", err)
	}

	return meta, nil
}

func TaskName(t *config.Task) string {
	return filepath.Base(t.Repo)
}

// ValidationTimeout is the maximum time allowed for the entire validation
// pipeline (tests + lint + coverage + hidden tests). Prevents hangs from
// infinite loops in agent-generated code.
const ValidationTimeout = 5 * time.Minute

// ValidateAndScore runs the validation pipeline (tests, lint)
// against a completed trial and updates the meta with scores.
func ValidateAndScore(ctx context.Context, trialDir string, task *config.Task, gatewayURL string) (*result.TrialMeta, error) {
	meta, err := result.ReadTrialMeta(filepath.Join(trialDir, "meta.json"))
	if err != nil {
		return nil, fmt.Errorf("reading trial meta: %w", err)
	}

	workDir := filepath.Join(trialDir, "workspace")

	// Apply validation timeout to prevent hangs from infinite loops
	valCtx, cancel := context.WithTimeout(ctx, ValidationTimeout)
	defer cancel()

	if task.Greenfield {
		return validateGreenfield(valCtx, trialDir, workDir, meta, task, gatewayURL)
	}
	return validateStandard(valCtx, trialDir, workDir, meta, task, gatewayURL)
}

// validateStandard runs the original validation pipeline for non-greenfield tasks.
func validateStandard(ctx context.Context, trialDir, workDir string, meta *result.TrialMeta, task *config.Task, gatewayURL string) (*result.TrialMeta, error) {
	// Run tests
	testResult, err := validation.RunTests(ctx, workDir, task.ValidationImage, task.InstallCmd, task.TestCmd)
	if err != nil {
		log.Printf("warning: tests failed for %s trial %d: %v", meta.Task, meta.Trial, err)
		meta.ValidationErrors = append(meta.ValidationErrors, fmt.Sprintf("tests: %v", err))
	} else {
		meta.Scores.Tests = testResult.Score
	}

	// Run lint
	lintResult, err := validation.RunLint(ctx, workDir, task.ValidationImage, task.LintCmd, 0)
	if err != nil {
		log.Printf("warning: lint failed for %s trial %d: %v", meta.Task, meta.Trial, err)
		meta.ValidationErrors = append(meta.ValidationErrors, fmt.Sprintf("lint: %v", err))
	} else {
		meta.Scores.StaticAnalysis = lintResult.Score
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
	// Mark this trial as greenfield so the reporter can average all greenfield
	// trials (including fully-failed ones with all-zero scores), not just the
	// ones that happened to score > 0 on some component.
	meta.Greenfield = true

	// 1. Run agent's own tests BEFORE injecting hidden tests
	if task.TestCmd != "" {
		agentTestResult, err := validation.RunTests(ctx, workDir, task.ValidationImage, task.InstallCmd, task.TestCmd)
		if err != nil {
			log.Printf("warning: agent tests failed for %s trial %d: %v", meta.Task, meta.Trial, err)
			meta.ValidationErrors = append(meta.ValidationErrors, fmt.Sprintf("agent_tests: %v", err))
		} else {
			meta.Scores.AgentTests = agentTestResult.Score
		}
	}

	// 2. Run coverage on agent's tests BEFORE injecting hidden tests
	coverageResult, err := validation.RunCoverage(ctx, workDir, task.ValidationImage, task.InstallCmd)
	var coverageScore float64
	if err != nil {
		log.Printf("warning: coverage failed for %s trial %d: %v", meta.Task, meta.Trial, err)
		meta.ValidationErrors = append(meta.ValidationErrors, fmt.Sprintf("coverage: %v", err))
	} else {
		coverageScore = coverageResult.Score
		meta.Scores.Coverage = coverageScore
	}
	meta.Scores.CoverageMeasured = CoverageMeasured(coverageScore, err, meta.Scores.AgentTests > 0)

	// 3. Code metrics (doesn't depend on test injection order)
	metricsResult, err := validation.RunCodeMetrics(workDir)
	if err != nil {
		log.Printf("warning: code metrics failed for %s trial %d: %v", meta.Task, meta.Trial, err)
		meta.ValidationErrors = append(meta.ValidationErrors, fmt.Sprintf("code_metrics: %v", err))
	} else {
		meta.Scores.CodeMetrics = metricsResult.Score
	}

	// 4. Run lint
	lintResult, err := validation.RunLint(ctx, workDir, task.ValidationImage, task.LintCmd, 0)
	if err != nil {
		log.Printf("warning: lint failed for %s trial %d: %v", meta.Task, meta.Trial, err)
		meta.ValidationErrors = append(meta.ValidationErrors, fmt.Sprintf("lint: %v", err))
	} else {
		meta.Scores.StaticAnalysis = lintResult.Score
	}

	// 5. NOW inject and run hidden behavioral tests
	cleanup, err := validation.InjectHiddenTests(task.Repo, task.ValidationTag, workDir)
	if err != nil {
		log.Printf("warning: could not inject hidden tests for %s trial %d: %v", meta.Task, meta.Trial, err)
		meta.ValidationErrors = append(meta.ValidationErrors, fmt.Sprintf("hidden_tests_inject: %v", err))
	} else {
		defer cleanup()
		hiddenResult, err := validation.RunHiddenTests(ctx, workDir, task.ValidationImage, task.InstallCmd)
		if err != nil {
			log.Printf("warning: hidden tests failed for %s trial %d: %v", meta.Task, meta.Trial, err)
			meta.ValidationErrors = append(meta.ValidationErrors, fmt.Sprintf("hidden_tests: %v", err))
		} else {
			meta.Scores.HiddenTests = hiddenResult.Score
		}
	}

	// Compute greenfield composite score
	meta.CompositeScore = validation.GreenfieldCompositeScore(meta.Scores, task.GreenWeights)

	if err := result.WriteTrialMeta(trialDir, meta); err != nil {
		return nil, fmt.Errorf("writing updated meta: %w", err)
	}
	return meta, nil
}

// CoverageMeasured decides whether the coverage signal should count in the
// greenfield composite. When coverage parsing succeeds, it's always measured.
// When it fails, we only treat it as "not measured" (giving AgentTests a free
// pass) if the agent wrote no tests — otherwise the coverage failure is real
// signal and should zero out the multiplier. Without this guard, an agent that
// wrote zero tests would be rewarded the full AgentTests score because the
// missing coverage-summary.json caused RunCoverage to error.
func CoverageMeasured(coverage float64, parseErr error, agentTestsRan bool) bool {
	if parseErr == nil {
		return true
	}
	return agentTestsRan
}

// SynthesizeCrashMeta builds a minimal TrialMeta for early-error paths where
// the container ran (or failed to run) but ValidateAndScore never got the chance.
// Without this, RunTrial's `return nil, err` paths leave a trial dir with no
// meta.json — the reporter then silently drops the trial.
func SynthesizeCrashMeta(task *config.Task, orchName string, trialNum int, cause error) *result.TrialMeta {
	return &result.TrialMeta{
		Orchestrator: orchName,
		Task:         TaskName(task),
		Trial:        trialNum,
		ExitCode:     -1,
		ExitReason:   "infra_error",
		Error:        cause.Error(),
		Category:     task.Category,
	}
}
