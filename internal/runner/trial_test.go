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
		// Regression cases for agentic-thunderdome-5a6: runtime artifact files
		// other than .thunderdome-metrics.json (notably .thunderdome-output.jsonl
		// from ~60 adapters, .amplifier-stdout.log from the amplifier family,
		// and core dumps) must not be treated as agent contribution.
		{
			"only thunderdome-output.jsonl",
			"diff --git a/.thunderdome-output.jsonl b/.thunderdome-output.jsonl\n" +
				"new file mode 100644\n@@ -0,0 +1 @@\n+{\"x\":1}\n",
			false,
		},
		{
			"only amplifier-stdout.log",
			"diff --git a/.amplifier-stdout.log b/.amplifier-stdout.log\n" +
				"new file mode 100644\n@@ -0,0 +1 @@\n+log line\n",
			false,
		},
		{
			"only core dump",
			"diff --git a/core.12345 b/core.12345\n" +
				"new file mode 100644\n@@ -0,0 +1 @@\n+binary noise\n",
			false,
		},
		{
			"all artifacts together",
			"diff --git a/.thunderdome-metrics.json b/.thunderdome-metrics.json\n@@ -0,0 +1 @@\n+{}\n" +
				"diff --git a/.thunderdome-output.jsonl b/.thunderdome-output.jsonl\n@@ -0,0 +1 @@\n+{}\n" +
				"diff --git a/.amplifier-stdout.log b/.amplifier-stdout.log\n@@ -0,0 +1 @@\n+log\n" +
				"diff --git a/core.999 b/core.999\n@@ -0,0 +1 @@\n+dump\n",
			false,
		},
		{
			"output.jsonl plus real change",
			"diff --git a/.thunderdome-output.jsonl b/.thunderdome-output.jsonl\n@@ -0,0 +1 @@\n+log\n" +
				"diff --git a/src/main.ts b/src/main.ts\n@@ -1 +1 @@\n-x\n+y\n",
			true,
		},
		{
			"amplifier log plus real change",
			"diff --git a/.amplifier-stdout.log b/.amplifier-stdout.log\n@@ -0,0 +1 @@\n+log\n" +
				"diff --git a/lib/foo.ts b/lib/foo.ts\n@@ -1 +1 @@\n-a\n+b\n",
			true,
		},
		{
			"core.ts source file is not a core dump",
			"diff --git a/src/core.ts b/src/core.ts\n@@ -1 +1 @@\n-x\n+y\n",
			true,
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

// TestRewriteGatewayURLForContainer is a regression test for td-8nq.
// Containers cannot reach loopback addresses on the host's netns, so any
// loopback host (localhost, 127.0.0.1, ::1) must be rewritten to
// host.docker.internal. The previous implementation only matched the literal
// string "localhost".
func TestRewriteGatewayURLForContainer(t *testing.T) {
	tests := []struct {
		name string
		in   string
		want string
	}{
		{"empty", "", ""},
		{"localhost", "http://localhost:8080", "http://host.docker.internal:8080"},
		{"127.0.0.1", "http://127.0.0.1:8080", "http://host.docker.internal:8080"},
		{"ipv6 loopback", "http://[::1]:8080", "http://host.docker.internal:8080"},
		{"localhost no port", "http://localhost/x", "http://host.docker.internal/x"},
		{"non-loopback host untouched", "http://gateway.internal:8080", "http://gateway.internal:8080"},
		{"localhost in path not rewritten", "http://gateway.internal:8080/localhost", "http://gateway.internal:8080/localhost"},
		{"preserves path and query", "http://localhost:8080/v1/messages?x=1", "http://host.docker.internal:8080/v1/messages?x=1"},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got := runner.RewriteGatewayURLForContainer(tt.in)
			if got != tt.want {
				t.Errorf("RewriteGatewayURLForContainer(%q) = %q, want %q", tt.in, got, tt.want)
			}
		})
	}
}
