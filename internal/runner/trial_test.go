package runner_test

import (
	"testing"

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

func TestNoAgentContributionDetection(t *testing.T) {
	tests := []struct {
		name        string
		exitReason  string
		durationS   int
		totalTokens int
		want        bool
	}{
		{"crashed fast no tokens", "crashed", 2, 0, true},
		{"crashed fast with tokens", "crashed", 2, 500, true},
		{"crashed slow with tokens", "crashed", 120, 5000, false},
		{"completed fast no tokens", "completed", 5, 0, true},
		{"completed normal", "completed", 60, 10000, false},
		{"timeout with tokens", "timeout", 600, 50000, false},
		{"timeout no tokens", "timeout", 600, 0, true},
		{"gave_up fast", "gave_up", 3, 0, true},
		{"gave_up slow with work", "gave_up", 60, 8000, false},
		{"crashed at 29s", "crashed", 29, 1000, true},
		{"crashed at 31s", "crashed", 31, 1000, false},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got := runner.DetectNoAgentContribution(tt.exitReason, tt.durationS, tt.totalTokens)
			if got != tt.want {
				t.Errorf("DetectNoAgentContribution(%q, %d, %d) = %v, want %v",
					tt.exitReason, tt.durationS, tt.totalTokens, got, tt.want)
			}
		})
	}
}

func TestBuildAdapterCommand(t *testing.T) {
	cmd := runner.BuildAdapterCommand()
	if len(cmd) == 0 {
		t.Fatal("expected non-empty command")
	}
}
