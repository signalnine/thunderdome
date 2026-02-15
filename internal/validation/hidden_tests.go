package validation

import (
	"context"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"

	"github.com/signalnine/thunderdome/internal/gitops"
)

// InjectHiddenTests clones the validation tag from the task repo and copies
// the validation-tests/ directory and validation-vitest.config.ts into the
// agent's workspace. Returns a cleanup function to remove the temp clone.
func InjectHiddenTests(repo, validationTag, workDir string) (cleanup func(), err error) {
	tmpDir, err := gitops.CloneTag(repo, validationTag)
	if err != nil {
		return nil, fmt.Errorf("cloning validation tag %s: %w", validationTag, err)
	}
	cleanup = func() { os.RemoveAll(tmpDir) }

	// Copy validation-tests/ into workspace
	srcTests := filepath.Join(tmpDir, "validation-tests")
	dstTests := filepath.Join(workDir, "validation-tests")
	if _, err := os.Stat(srcTests); err == nil {
		if err := gitops.CopyDir(srcTests, dstTests); err != nil {
			cleanup()
			return nil, fmt.Errorf("copying validation-tests: %w", err)
		}
	} else {
		cleanup()
		return nil, fmt.Errorf("validation-tests/ not found in %s tag", validationTag)
	}

	// Copy validation-vitest.config.ts if present
	srcConfig := filepath.Join(tmpDir, "validation-vitest.config.ts")
	dstConfig := filepath.Join(workDir, "validation-vitest.config.ts")
	if _, err := os.Stat(srcConfig); err == nil {
		data, err := os.ReadFile(srcConfig)
		if err != nil {
			cleanup()
			return nil, fmt.Errorf("reading validation vitest config: %w", err)
		}
		if err := os.WriteFile(dstConfig, data, 0o644); err != nil {
			cleanup()
			return nil, fmt.Errorf("writing validation vitest config: %w", err)
		}
	}

	return cleanup, nil
}

// RunHiddenTests executes the hidden validation tests against the agent's workspace.
// It first installs dependencies, then runs vitest with the validation config.
func RunHiddenTests(ctx context.Context, workDir, validationImage, installCmd string) (*TestResult, error) {
	seccomp := "--security-opt=seccomp=unconfined"
	apparmor := "--security-opt=apparmor=unconfined"

	// Install dependencies (may need additional packages for validation tests)
	if installCmd != "" {
		cmd := exec.CommandContext(ctx, "docker", "run", "--rm", "--init", seccomp, apparmor,
			"-v", workDir+":/workspace", "-w", "/workspace",
			validationImage, "sh", "-c", installCmd)
		if out, err := cmd.CombinedOutput(); err != nil {
			return nil, fmt.Errorf("running install for hidden tests: %s: %w", string(out), err)
		}
	}

	// Run validation tests with the separate vitest config
	testCmd := "npx vitest run --config validation-vitest.config.ts"
	cmd := exec.CommandContext(ctx, "docker", "run", "--rm", "--init", seccomp, apparmor,
		"-v", workDir+":/workspace", "-w", "/workspace",
		validationImage, "sh", "-c", testCmd)

	out, err := cmd.CombinedOutput()
	exitCode := 0
	if err != nil {
		if exitErr, ok := err.(*exec.ExitError); ok {
			exitCode = exitErr.ExitCode()
		} else {
			return nil, fmt.Errorf("running hidden tests: %w", err)
		}
	}

	return &TestResult{
		Score:    ParseTestResults(string(out), exitCode).Score,
		Output:   string(out),
		ExitCode: exitCode,
	}, nil
}
