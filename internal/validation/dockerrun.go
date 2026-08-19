package validation

import (
	"context"
	"fmt"
	"os"
	"os/exec"
	"sync/atomic"
	"time"
)

// validationRunSeq makes container names unique within a process so that
// concurrent trials (--parallel N) never collide on `--name`.
var validationRunSeq atomic.Uint64

// containerKillGrace bounds how long we wait for `docker kill` and for the
// local client to die after cancellation, so a wedged daemon cannot hang the
// whole run.
const containerKillGrace = 15 * time.Second

// dockerRunCmd builds a `docker run` command whose CONTAINER is guaranteed to
// die when ctx is cancelled.
//
// Why this exists: `exec.CommandContext(ctx, "docker", "run", "--rm", ...)`
// looks safe but leaks. On cancellation Go kills the local `docker` CLIENT
// process; the container keeps running on the daemon, and `--rm` only fires
// when the container itself exits. Every timed-out or killed validation step
// therefore orphaned a container.
//
// Observed cost of the leak: 12 stray `node:20` containers aged 7 days to 5
// weeks, each pinning 1-2 cores on stuck vitest workers (~18 of 24 cores), one
// with a defunct process holding 2d19h of CPU. Beyond the waste, that
// contention inflates wall-clock for whatever else is running, which on a suite
// with wall-clock task limits can manufacture timeout floors that look like
// model failures.
//
// The fix is to give the container a known name and explicitly `docker kill` it
// on cancellation. Callers pass everything AFTER `docker run --rm --init`.
func dockerRunCmd(ctx context.Context, args ...string) *exec.Cmd {
	name := fmt.Sprintf("td-validation-%d-%d", os.Getpid(), validationRunSeq.Add(1))
	full := append([]string{"run", "--rm", "--init", "--name", name}, args...)

	cmd := exec.CommandContext(ctx, "docker", full...)

	// exec.CommandContext installs a Cancel that only kills the client. Replace
	// it: kill the container first (that is what `--rm` keys off), then the
	// client. Uses context.WithTimeout rather than ctx -- ctx is already
	// cancelled by the time this runs, so a plain exec.CommandContext(ctx, ...)
	// here would be dead on arrival.
	cmd.Cancel = func() error {
		killCtx, cancel := context.WithTimeout(context.Background(), containerKillGrace)
		defer cancel()
		_ = exec.CommandContext(killCtx, "docker", "kill", name).Run()
		if cmd.Process != nil {
			return cmd.Process.Kill()
		}
		return nil
	}

	// Bound the wait for stdout/stderr pipes after cancellation so a container
	// that ignores SIGKILL cannot wedge the caller indefinitely.
	cmd.WaitDelay = containerKillGrace

	return cmd
}
