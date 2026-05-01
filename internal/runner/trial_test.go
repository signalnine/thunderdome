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
		// Docker SDK wait error: code 125 + TimedOut=false should not be
		// classified as a timeout (regression for agentic-thunderdome-001).
		{125, false, "crashed"},
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
		name       string
		exitReason string
		durationS  int
		hasChanges bool
		want       bool
	}{
		{"crashed fast no diff", "crashed", 2, false, true},
		{"crashed fast with diff", "crashed", 2, true, true},
		{"crashed slow with diff", "crashed", 120, true, false},
		{"completed fast no diff", "completed", 5, false, true},
		{"completed normal with diff", "completed", 60, true, false},
		{"timeout with diff", "timeout", 600, true, false},
		{"timeout no diff", "timeout", 600, false, true},
		{"gave_up fast no diff", "gave_up", 3, false, true},
		{"gave_up slow with diff", "gave_up", 60, true, false},
		{"crashed at 29s with diff", "crashed", 29, true, true},
		{"crashed at 31s with diff", "crashed", 31, true, false},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got := runner.DetectNoAgentContribution(tt.exitReason, tt.durationS, tt.hasChanges)
			if got != tt.want {
				t.Errorf("DetectNoAgentContribution(%q, %d, %v) = %v, want %v",
					tt.exitReason, tt.durationS, tt.hasChanges, got, tt.want)
			}
		})
	}
}

func TestHasWorkspaceChanges(t *testing.T) {
	tests := []struct {
		name string
		diff string
		want bool
	}{
		{"empty", "", false},
		{
			"only metrics file",
			"diff --git a/.thunderdome-metrics.json b/.thunderdome-metrics.json\n" +
				"new file mode 100644\n@@ -0,0 +1 @@\n+{}\n",
			false,
		},
		{
			"real source change",
			"diff --git a/src/main.ts b/src/main.ts\n@@ -1 +1 @@\n-old\n+new\n",
			true,
		},
		{
			"metrics plus real change",
			"diff --git a/.thunderdome-metrics.json b/.thunderdome-metrics.json\n@@ -0,0 +1 @@\n+{}\n" +
				"diff --git a/src/main.ts b/src/main.ts\n@@ -1 +1 @@\n-x\n+y\n",
			true,
		},
		{
			"diff with no git header",
			"some random non-diff text",
			false,
		},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got := runner.HasWorkspaceChanges([]byte(tt.diff))
			if got != tt.want {
				t.Errorf("HasWorkspaceChanges(%q) = %v, want %v", tt.diff, got, tt.want)
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
