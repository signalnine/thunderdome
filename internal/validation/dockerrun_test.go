package validation

import (
	"context"
	"os/exec"
	"strings"
	"testing"
	"time"
)

// dockerAvailable reports whether a usable Docker daemon is present. The
// container-leak test is meaningless without one.
func dockerAvailable(t *testing.T) bool {
	t.Helper()
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	return exec.CommandContext(ctx, "docker", "info").Run() == nil
}

// TestDockerRunCmdKillsContainerOnCancel is a regression test for a real leak:
// `exec.CommandContext(ctx, "docker", "run", "--rm", ...)` kills only the local
// docker CLIENT when the context is cancelled. The container keeps running on
// the daemon and `--rm` never fires, because `--rm` triggers on the container's
// own exit. That leaked 12 stray validation containers over five weeks, each
// pinning 1-2 cores on stuck vitest workers.
//
// Asserts the container is actually gone shortly after cancellation.
func TestDockerRunCmdKillsContainerOnCancel(t *testing.T) {
	if !dockerAvailable(t) {
		t.Skip("docker not available")
	}

	ctx, cancel := context.WithCancel(context.Background())
	// A container that would otherwise outlive the test by an hour.
	cmd := dockerRunCmd(ctx, "alpine:latest", "sh", "-c", "sleep 3600")

	// Recover the generated --name so we can assert on it directly.
	var name string
	for i, a := range cmd.Args {
		if a == "--name" && i+1 < len(cmd.Args) {
			name = cmd.Args[i+1]
		}
	}
	if name == "" {
		t.Fatal("dockerRunCmd did not set --name; cancellation cannot target the container")
	}

	if err := cmd.Start(); err != nil {
		t.Skipf("could not start container (image pull may be unavailable): %v", err)
	}

	// Wait for the container to actually be running before cancelling,
	// otherwise we might cancel before the daemon has created anything and the
	// test would pass vacuously.
	running := false
	for i := 0; i < 60; i++ {
		out, _ := exec.Command("docker", "ps", "--filter", "name="+name, "--format", "{{.Names}}").Output()
		if strings.TrimSpace(string(out)) == name {
			running = true
			break
		}
		time.Sleep(500 * time.Millisecond)
	}
	if !running {
		cancel()
		_ = cmd.Wait()
		_ = exec.Command("docker", "kill", name).Run()
		t.Skip("container never reached running state; environment too slow or image missing")
	}

	cancel()
	_ = cmd.Wait()

	// The container must disappear. Poll briefly: `docker kill` plus `--rm`
	// teardown is not instantaneous.
	for i := 0; i < 40; i++ {
		out, _ := exec.Command("docker", "ps", "--filter", "name="+name, "--format", "{{.Names}}").Output()
		if strings.TrimSpace(string(out)) == "" {
			return // gone -- fix works
		}
		time.Sleep(500 * time.Millisecond)
	}

	// Leaked. Clean up so a failing test does not itself leave a zombie.
	_ = exec.Command("docker", "kill", name).Run()
	t.Fatalf("container %s survived context cancellation -- the leak has regressed", name)
}
