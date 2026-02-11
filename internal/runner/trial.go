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
	GatewayAddr  string
	RunDir       string
	Timeout      time.Duration
	Allowlist    []string
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
	return []string{"sh", "/adapter.sh"}
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
		os.WriteFile(taskDescPath, data, 0o644)
	} else {
		os.WriteFile(taskDescPath, []byte("No task description available"), 0o644)
	}

	adapterAbs, err := filepath.Abs(opts.Orchestrator.Adapter)
	if err != nil {
		return nil, fmt.Errorf("resolving adapter path: %w", err)
	}

	env := map[string]string{
		"TASK_DIR":         "/workspace",
		"TASK_DESCRIPTION": "/task.md",
		"PROXY_URL":        opts.GatewayURL,
	}
	for k, v := range opts.Orchestrator.Env {
		env[k] = v
	}

	hostUID := fmt.Sprintf("%d:%d", os.Getuid(), os.Getgid())

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

	diff, err := gitops.CaptureChanges(workDir)
	if err != nil {
		return nil, fmt.Errorf("capturing changes: %w", err)
	}
	os.WriteFile(filepath.Join(trialDir, "diff.patch"), diff, 0o644)

	var totalTokens int
	proxyLogPath := filepath.Join(trialDir, "proxy-log.jsonl")
	records, err := gateway.ParseUsageLogs(proxyLogPath)
	if err == nil {
		inTok, outTok := gateway.TotalUsage(records)
		totalTokens = inTok + outTok
	}

	meta := &result.TrialMeta{
		Orchestrator: opts.Orchestrator.Name,
		Task:         TaskName(opts.Task),
		Trial:        opts.TrialNum,
		DurationS:    int(containerResult.Duration.Seconds()),
		ExitCode:     containerResult.ExitCode,
		ExitReason:   ExitReasonFromCode(containerResult.ExitCode, containerResult.TimedOut),
		TotalTokens:  totalTokens,
	}
	if err := result.WriteTrialMeta(trialDir, meta); err != nil {
		return nil, fmt.Errorf("writing meta: %w", err)
	}

	return meta, nil
}

func TaskName(t *config.Task) string {
	return filepath.Base(t.Repo)
}
