package docker

import (
	"context"
	"errors"
	"fmt"
	"io"
	"os"
	"time"

	"github.com/moby/moby/api/types/container"
	"github.com/moby/moby/api/types/mount"
	"github.com/moby/moby/client"
)

// ClassifyWaitError converts an error received on the Docker wait channel
// into a RunResult and an outbound error. context.DeadlineExceeded means the
// wait deadline expired -- a real timeout (ExitCode=124, TimedOut=true).
// Anything else is an infrastructure crash (ExitCode=125, TimedOut=false)
// that callers should surface in logs and meta.json.
func ClassifyWaitError(waitErr error, duration time.Duration) (*RunResult, error) {
	if errors.Is(waitErr, context.DeadlineExceeded) {
		return &RunResult{
			ExitCode: 124,
			TimedOut: true,
			Duration: duration,
		}, nil
	}
	return &RunResult{
		ExitCode: 125,
		TimedOut: false,
		Duration: duration,
	}, fmt.Errorf("docker wait error: %w", waitErr)
}

type RunOpts struct {
	Image       string
	Command     []string
	WorkDir     string
	Env         map[string]string
	Timeout     time.Duration
	ExtraMounts []Mount
	Allowlist   []string
	GatewayAddr string
	CPULimit    float64
	MemoryLimit int64
	UserID      string
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

	initTrue := true
	hostCfg := &container.HostConfig{
		Mounts:     mounts,
		Init:       &initTrue,
		SecurityOpt: []string{"seccomp=unconfined", "apparmor=unconfined"},
	}
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

	// Allow container to reach the host (for API proxy gateway).
	// NOTE: Domain-based allowlisting is not yet implemented. The container
	// has full network access. Budget limits are enforced by the LiteLLM proxy.
	hostCfg.ExtraHosts = []string{"host.docker.internal:host-gateway"}

	createResp, err := cli.ContainerCreate(ctx, client.ContainerCreateOptions{
		Config:     containerCfg,
		HostConfig: hostCfg,
	})
	if err != nil {
		return nil, fmt.Errorf("creating container: %w", err)
	}
	containerID := createResp.ID
	defer func() {
		cli.ContainerRemove(context.Background(), containerID, client.ContainerRemoveOptions{Force: true})
	}()

	start := time.Now()
	if _, err := cli.ContainerStart(ctx, containerID, client.ContainerStartOptions{}); err != nil {
		return nil, fmt.Errorf("starting container: %w", err)
	}

	timeoutCtx, cancel := context.WithTimeout(ctx, opts.Timeout)
	defer cancel()

	waitResult := cli.ContainerWait(timeoutCtx, containerID, client.ContainerWaitOptions{
		Condition: container.WaitConditionNotRunning,
	})
	// killAndDump is shared cleanup for ctx-cancel / timeout / error paths.
	killAndDump := func(label string) {
		// Try graceful stop first so the adapter can flush
		// .thunderdome-metrics.json and the trailing NDJSON line.
		// ContainerStopOptions.Timeout is seconds; the SDK escalates to
		// SIGKILL automatically after expiry, but we follow up with an
		// explicit ContainerKill below for paranoia.
		grace := 5
		if _, stopErr := cli.ContainerStop(context.Background(), containerID, client.ContainerStopOptions{Timeout: &grace}); stopErr != nil {
			fmt.Fprintf(os.Stderr, "container stop failed for %s (will SIGKILL): %v\n", label, stopErr)
		}
		cli.ContainerKill(context.Background(), containerID, client.ContainerKillOptions{Signal: "SIGKILL"})
		logReader, _ := cli.ContainerLogs(context.Background(), containerID, client.ContainerLogsOptions{ShowStdout: true, ShowStderr: true})
		if logReader != nil {
			logData, _ := io.ReadAll(logReader)
			logReader.Close()
			fmt.Fprintf(os.Stderr, "Container logs (%s):\n%s\n", label, string(logData))
		}
	}

	for {
		select {
		case <-ctx.Done():
			// Parent ctx cancelled (Ctrl+C, batch shutdown). Kill container.
			killAndDump("parent-ctx-cancelled")
			return &RunResult{
				ExitCode: 130,
				TimedOut: false,
				Duration: time.Since(start),
			}, ctx.Err()
		case <-timeoutCtx.Done():
			// Trial timeout fired but no result/error came through the wait channels
			// (Docker daemon hiccup, channel never delivers). Force kill so we
			// don't spin forever on a closed Error channel.
			if errors.Is(timeoutCtx.Err(), context.DeadlineExceeded) {
				killAndDump("trial-timeout")
				return &RunResult{
					ExitCode: 124,
					TimedOut: true,
					Duration: time.Since(start),
				}, nil
			}
			// timeoutCtx was canceled because the parent ctx was canceled
			// (Ctrl+C, batch shutdown). The parent-ctx case will fire on the
			// next iteration, but Done() is permanently ready -- without an
			// explicit return here, select can keep picking this case in a
			// busy spin. Treat it as a parent-cancel.
			killAndDump("parent-ctx-cancelled-via-timeoutctx")
			return &RunResult{
				ExitCode: 130,
				TimedOut: false,
				Duration: time.Since(start),
			}, ctx.Err()
		case err, ok := <-waitResult.Error:
			if !ok {
				// Channel closed without delivering a value — Docker SDK
				// signalling end-of-stream. Don't spin; force kill and bail.
				killAndDump("wait-error-channel-closed")
				return &RunResult{
					ExitCode: 125,
					TimedOut: false,
					Duration: time.Since(start),
				}, fmt.Errorf("docker wait error channel closed without value")
			}
			if err != nil {
				// Docker SDK error during wait. context.DeadlineExceeded means
				// the trial wait deadline expired -- a real timeout. Anything
				// else (daemon hiccup, container removed out-of-band, socket
				// glitch) is an infrastructure crash; surface it so meta.json
				// classifies the trial as crashed rather than timed out.
				killAndDump("wait-error")
				return ClassifyWaitError(err, time.Since(start))
			}
			// nil error received on an open channel; loop and wait for result
		case status, ok := <-waitResult.Result:
			if !ok {
				// Result channel closed without value — Docker SDK signalling
				// end-of-stream without ever delivering a status. Bail rather
				// than re-loop into the closed-channel zero-value.
				killAndDump("wait-result-channel-closed")
				return &RunResult{
					ExitCode: 125,
					TimedOut: false,
					Duration: time.Since(start),
				}, fmt.Errorf("docker wait result channel closed without value")
			}
			// Capture container logs for debugging
			logReader, _ := cli.ContainerLogs(context.Background(), containerID, client.ContainerLogsOptions{ShowStdout: true, ShowStderr: true, Tail: "100"})
			if logReader != nil {
				logData, _ := io.ReadAll(logReader)
				logReader.Close()
				if len(logData) > 0 {
					fmt.Fprintf(os.Stderr, "Container logs:\n%s\n", string(logData))
				}
			}
			return &RunResult{
				ExitCode: int(status.StatusCode),
				TimedOut: false,
				Duration: time.Since(start),
			}, nil
		}
	}
}

