package runner_test

import (
	"testing"

	"github.com/signalnine/thunderdome/internal/config"
	"github.com/signalnine/thunderdome/internal/runner"
)

func TestExitReasonFromCode(t *testing.T) {
	tests := []struct {
		code     int
		timedOut bool
		want     string
	}{
		{0, false, "completed"},
		{1, false, "crashed"},
		{2, false, "gave_up"},
		{124, true, "timeout"},
		{42, false, "crashed"},
	}
	for _, tt := range tests {
		got := runner.ExitReasonFromCode(tt.code, tt.timedOut)
		if got != tt.want {
			t.Errorf("ExitReasonFromCode(%d, %v) = %q, want %q", tt.code, tt.timedOut, got, tt.want)
		}
	}
}

func TestBuildAdapterCommand(t *testing.T) {
	orch := &config.Orchestrator{
		Name:    "test",
		Adapter: "./adapters/test.sh",
		Env:     map[string]string{"FOO": "bar"},
	}
	cmd := runner.BuildAdapterCommand(orch, "/workspace", "/task.md", "http://localhost:8080")
	if len(cmd) == 0 {
		t.Fatal("expected non-empty command")
	}
}
