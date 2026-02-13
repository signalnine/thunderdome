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
