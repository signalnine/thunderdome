package docker

import (
	"context"
	"fmt"
	"io"
	"os"
	"time"

	"github.com/moby/moby/api/types/container"
	"github.com/moby/moby/api/types/mount"
	"github.com/moby/moby/client"
)

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
	for {
		select {
		case err := <-waitResult.Error:
			if err != nil {
				cli.ContainerKill(context.Background(), containerID, client.ContainerKillOptions{Signal: "SIGKILL"})
				logReader, _ := cli.ContainerLogs(context.Background(), containerID, client.ContainerLogsOptions{ShowStdout: true, ShowStderr: true})
				if logReader != nil {
					logData, _ := io.ReadAll(logReader)
					logReader.Close()
					fmt.Fprintf(os.Stderr, "Container logs (timeout):\n%s\n", string(logData))
				}
				return &RunResult{
					ExitCode: 124,
					TimedOut: true,
					Duration: time.Since(start),
				}, nil
			}
			// nil error means no error on this channel; wait for result
		case status := <-waitResult.Result:
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

