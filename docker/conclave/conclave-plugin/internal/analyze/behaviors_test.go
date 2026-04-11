package analyze

import (
	"testing"
)

func mkTrace(calls ...ToolCall) *Trace {
	for i := range calls {
		calls[i].Index = i
	}
	return &Trace{ToolCalls: calls}
}

func w(path string) ToolCall  { return ToolCall{Name: "Write", FilePath: path} }
func e(path string) ToolCall  { return ToolCall{Name: "Edit", FilePath: path} }
func bash(cmd string) ToolCall { return ToolCall{Name: "Bash", Command: cmd} }
func read(path string) ToolCall { return ToolCall{Name: "Read", FilePath: path} }

func TestTDDCompliance(t *testing.T) {
	tests := []struct {
		name  string
		trace *Trace
		want  bool
	}{
		{
			name:  "test before impl",
			trace: mkTrace(w("/workspace/src/__tests__/foo.test.ts"), w("/workspace/src/foo.ts")),
			want:  true,
		},
		{
			name:  "impl before test",
			trace: mkTrace(w("/workspace/src/foo.ts"), w("/workspace/src/__tests__/foo.test.ts")),
			want:  false,
		},
		{
			name:  "no writes",
			trace: mkTrace(bash("ls"), read("/workspace/src/foo.ts")),
			want:  false,
		},
		{
			name:  "only test writes",
			trace: mkTrace(w("/workspace/src/__tests__/foo.test.ts")),
			want:  true,
		},
		{
			name:  "read before write is ok",
			trace: mkTrace(read("/workspace/src/foo.ts"), w("/workspace/test/foo.test.ts"), w("/workspace/src/foo.ts")),
			want:  true,
		},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			p := ExtractBehaviors(tt.trace)
			if p.TDDCompliance != tt.want {
				t.Errorf("TDDCompliance = %v, want %v", p.TDDCompliance, tt.want)
			}
		})
	}
}

func TestVerificationBeforeCommit(t *testing.T) {
	tests := []struct {
		name  string
		trace *Trace
		want  bool
	}{
		{
			name: "test then commit",
			trace: mkTrace(
				w("/workspace/src/foo.ts"),
				bash("npx vitest run"),
				bash("git add -A && git commit -m 'feat'"),
			),
			want: true,
		},
		{
			name: "commit without test",
			trace: mkTrace(
				w("/workspace/src/foo.ts"),
				bash("git add -A && git commit -m 'feat'"),
			),
			want: false,
		},
		{
			name: "test after last edit before commit",
			trace: mkTrace(
				w("/workspace/src/foo.ts"),
				bash("npm test"),
				e("/workspace/src/foo.ts"),
				bash("npx vitest run"),
				bash("git commit -m 'feat'"),
			),
			want: true,
		},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			p := ExtractBehaviors(tt.trace)
			if p.VerificationBeforeCommit != tt.want {
				t.Errorf("VerificationBeforeCommit = %v, want %v", p.VerificationBeforeCommit, tt.want)
			}
		})
	}
}

func TestFixCycles(t *testing.T) {
	// test -> edit -> test = 1 cycle
	trace := mkTrace(
		w("/workspace/src/__tests__/foo.test.ts"),
		bash("npm test"),
		e("/workspace/src/foo.ts"),
		bash("npm test"),
		e("/workspace/src/foo.ts"),
		bash("npm test"),
	)
	p := ExtractBehaviors(trace)
	if p.FixCycles != 2 {
		t.Errorf("FixCycles = %d, want 2", p.FixCycles)
	}
}

func TestCommitAndTestCounts(t *testing.T) {
	trace := mkTrace(
		bash("npm test"),
		bash("git commit -m 'a'"),
		bash("npx vitest run"),
		bash("git add -A && git commit -m 'b'"),
		bash("npm run build"),
		bash("npm run lint"),
	)
	p := ExtractBehaviors(trace)
	if p.CommitCount != 2 {
		t.Errorf("CommitCount = %d, want 2", p.CommitCount)
	}
	if p.TestRunCount != 2 {
		t.Errorf("TestRunCount = %d, want 2", p.TestRunCount)
	}
	if !p.BuildCheck {
		t.Error("BuildCheck = false, want true")
	}
	if !p.LintCheck {
		t.Error("LintCheck = false, want true")
	}
}

func TestDiffReview(t *testing.T) {
	tests := []struct {
		name  string
		trace *Trace
		want  bool
	}{
		{
			name: "diff after commit",
			trace: mkTrace(
				bash("git commit -m 'feat'"),
				bash("git diff HEAD~1"),
			),
			want: true,
		},
		{
			name: "diff before commit only",
			trace: mkTrace(
				bash("git diff"),
				bash("git commit -m 'feat'"),
			),
			want: false,
		},
		{
			name: "no diff",
			trace: mkTrace(
				bash("git commit -m 'feat'"),
			),
			want: false,
		},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			p := ExtractBehaviors(tt.trace)
			if p.DiffReview != tt.want {
				t.Errorf("DiffReview = %v, want %v", p.DiffReview, tt.want)
			}
		})
	}
}

func TestTestFirstRatio(t *testing.T) {
	// Write test for foo, then impl for foo, then impl for bar (no test)
	trace := mkTrace(
		w("/workspace/src/__tests__/foo.test.ts"),
		w("/workspace/src/foo.ts"),
		w("/workspace/src/bar.ts"),
	)
	p := ExtractBehaviors(trace)
	// foo had test before it (1/2 = 0.5), bar did not
	if p.TestFirstRatio < 0.49 || p.TestFirstRatio > 0.51 {
		t.Errorf("TestFirstRatio = %f, want ~0.5", p.TestFirstRatio)
	}
}

func TestFinalVerification(t *testing.T) {
	tests := []struct {
		name  string
		trace *Trace
		want  bool
	}{
		{
			name: "test after last commit",
			trace: mkTrace(
				bash("git commit -m 'feat'"),
				bash("npm test"),
			),
			want: true,
		},
		{
			name: "no test after commit",
			trace: mkTrace(
				bash("npm test"),
				bash("git commit -m 'feat'"),
			),
			want: false,
		},
		{
			name: "no commit at all",
			trace: mkTrace(
				bash("npm test"),
			),
			want: false,
		},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			p := ExtractBehaviors(tt.trace)
			if p.FinalVerification != tt.want {
				t.Errorf("FinalVerification = %v, want %v", p.FinalVerification, tt.want)
			}
		})
	}
}
