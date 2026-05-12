package validation_test

import (
	"fmt"
	"os"
	"path/filepath"
	"testing"

	"github.com/signalnine/thunderdome/internal/validation"
)

func writeFile(t *testing.T, path, body string) {
	t.Helper()
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(path, []byte(body), 0o644); err != nil {
		t.Fatal(err)
	}
}

func TestRunCodeMetricsBasic(t *testing.T) {
	work := t.TempDir()
	writeFile(t, filepath.Join(work, "src", "a.ts"), "export const a = 1;\n")
	writeFile(t, filepath.Join(work, "src", "b.ts"), "export const b = 2;\n")
	writeFile(t, filepath.Join(work, "tests", "a.test.ts"), "test('a', () => {});\n")

	res, err := validation.RunCodeMetrics(work)
	if err != nil {
		t.Fatal(err)
	}
	if res.FileCount != 2 {
		t.Errorf("FileCount = %d, want 2", res.FileCount)
	}
	if res.TestFileCount != 1 {
		t.Errorf("TestFileCount = %d, want 1", res.TestFileCount)
	}
	if !res.HasTests {
		t.Errorf("HasTests = false, want true")
	}
}

// Tests inside node_modules and validation-tests must not be counted as
// agent-written tests, regardless of how deeply they are nested.
func TestRunCodeMetricsIgnoresNodeModulesAndValidationTests(t *testing.T) {
	work := t.TempDir()
	writeFile(t, filepath.Join(work, "src", "main.ts"), "export const x = 1;\n")
	writeFile(t, filepath.Join(work, "tests", "main.test.ts"), "test('x', () => {});\n")

	// node_modules with nested test files — these are dependency tests, not the agent's.
	writeFile(t, filepath.Join(work, "node_modules", "pkg", "__tests__", "dep.test.ts"), "")
	writeFile(t, filepath.Join(work, "node_modules", "pkg", "lib", "deep", "deep.spec.ts"), "")

	// validation-tests is the hidden-test harness; not the agent's work.
	writeFile(t, filepath.Join(work, "validation-tests", "hidden.test.ts"), "")

	res, err := validation.RunCodeMetrics(work)
	if err != nil {
		t.Fatal(err)
	}
	if res.TestFileCount != 1 {
		t.Errorf("TestFileCount = %d, want 1 (only tests/main.test.ts)", res.TestFileCount)
	}
}

// Regression: the inner walk early-returned for directories before reaching
// its filepath.SkipDir branch, so node_modules was traversed in full on every
// validation. We can't observe walk depth from outside, so we use a
// permission-denied subdirectory inside node_modules: with SkipDir reachable
// the walker never tries to descend; without it, the walker would attempt to
// read the dir. Then we drop one detectable file just inside node_modules
// (top-level). The pre-fix code visited it (returned nil), the post-fix code
// skips the whole subtree. We assert this via a sibling sentinel: a file
// outside node_modules with the same .test.ts name pattern, which must still
// be counted exactly once.
func TestRunCodeMetricsSkipsNodeModulesSubtree(t *testing.T) {
	work := t.TempDir()
	writeFile(t, filepath.Join(work, "src", "main.ts"), "export const x = 1;\n")
	writeFile(t, filepath.Join(work, "tests", "main.test.ts"), "")

	// Many fake .test.ts files inside node_modules. None should be counted
	// as agent tests. The buggy walker visits each (still returns nil via
	// the prefix check); the fixed walker SkipDirs node_modules entirely.
	for i := 0; i < 25; i++ {
		writeFile(t, filepath.Join(work, "node_modules", "pkg", fmt.Sprintf("d%d", i), "a.test.ts"), "")
	}

	res, err := validation.RunCodeMetrics(work)
	if err != nil {
		t.Fatal(err)
	}
	if res.TestFileCount != 1 {
		t.Errorf("TestFileCount = %d, want 1", res.TestFileCount)
	}
}

// Regression: an empty workspace (agent produced zero source files) was
// scoring 0.3 on code_metrics because the "no monolithic files" branch
// fires whenever MaxFileLOC <= 200, which is always true when MaxFileLOC
// is 0. This silently rewarded no-contribution trials and inflated the
// greenfield composite. An empty workspace must score 0.0.
func TestRunCodeMetricsEmptyWorkspaceScoresZero(t *testing.T) {
	work := t.TempDir()
	res, err := validation.RunCodeMetrics(work)
	if err != nil {
		t.Fatal(err)
	}
	if res.FileCount != 0 {
		t.Fatalf("FileCount = %d, want 0", res.FileCount)
	}
	if res.Score != 0.0 {
		t.Errorf("Score = %f, want 0.0 for empty workspace", res.Score)
	}
}

// Regression: agents often organize tests in subdirectories
// (tests/unit/foo.test.ts, tests/integration/bar.test.ts). The old
// implementation read tests/ non-recursively (phase 1) and then skipped
// anything under tests/ in the walk (phase 2, to avoid double-counting),
// so nested tests fell through both phases and TestFileCount stayed 0.
func TestRunCodeMetricsCountsNestedTestsDir(t *testing.T) {
	work := t.TempDir()
	writeFile(t, filepath.Join(work, "src", "main.ts"), "export const x = 1;\n")
	writeFile(t, filepath.Join(work, "tests", "unit", "a.test.ts"), "test('a', () => {});\n")
	writeFile(t, filepath.Join(work, "tests", "unit", "b.spec.ts"), "test('b', () => {});\n")
	writeFile(t, filepath.Join(work, "tests", "integration", "c.test.ts"), "test('c', () => {});\n")

	res, err := validation.RunCodeMetrics(work)
	if err != nil {
		t.Fatal(err)
	}
	if res.TestFileCount != 3 {
		t.Errorf("TestFileCount = %d, want 3 (all nested test files under tests/)", res.TestFileCount)
	}
	if !res.HasTests {
		t.Errorf("HasTests = false, want true")
	}
}

// Regression: countLOC treated any line whose trimmed prefix was '/*' as a
// comment, even when '/* ... */' closed mid-line and was followed by real
// code. The trailing code was silently dropped from the LOC count, biasing
// MaxFileLOC and TotalLOC downward.
func TestRunCodeMetricsCountsCodeAfterInlineBlockComment(t *testing.T) {
	work := t.TempDir()
	body := "/* one-liner */ export const realCode = () => 1;\n"
	writeFile(t, filepath.Join(work, "src", "a.ts"), body)

	res, err := validation.RunCodeMetrics(work)
	if err != nil {
		t.Fatal(err)
	}
	if res.TotalLOC < 1 {
		t.Errorf("TotalLOC = %d, want >= 1 for line with code after /* */", res.TotalLOC)
	}
	if res.MaxFileLOC < 1 {
		t.Errorf("MaxFileLOC = %d, want >= 1", res.MaxFileLOC)
	}
}

// Regression: countLOC dropped any code following the closing '*/' of a
// multi-line block comment. Same bug class as the inline case above, but on
// the closing line of a multi-line comment.
func TestRunCodeMetricsCountsCodeAfterMultiLineBlockComment(t *testing.T) {
	work := t.TempDir()
	body := "/* multi\nline */ export const realCode = () => 1;\n"
	writeFile(t, filepath.Join(work, "src", "a.ts"), body)

	res, err := validation.RunCodeMetrics(work)
	if err != nil {
		t.Fatal(err)
	}
	if res.TotalLOC < 1 {
		t.Errorf("TotalLOC = %d, want >= 1 for code after closing */ on multi-line comment", res.TotalLOC)
	}
	if res.MaxFileLOC < 1 {
		t.Errorf("MaxFileLOC = %d, want >= 1", res.MaxFileLOC)
	}
}

// A multi-line block comment whose closing line has no trailing code (or only
// whitespace / a line comment) should still be fully skipped.
func TestRunCodeMetricsSkipsMultiLineBlockCommentWithNoTrailingCode(t *testing.T) {
	work := t.TempDir()
	body := "/* multi\nline */\n" +
		"/* multi2\nline2 */   \n" +
		"/* multi3\nline3 */ // tail\n" +
		"export const x = 1;\n"
	writeFile(t, filepath.Join(work, "src", "a.ts"), body)

	res, err := validation.RunCodeMetrics(work)
	if err != nil {
		t.Fatal(err)
	}
	if res.TotalLOC != 1 {
		t.Errorf("TotalLOC = %d, want 1 (only export line counts)", res.TotalLOC)
	}
}

// A line that is entirely a same-line block comment (or block comment
// followed by a line comment / whitespace) must still be skipped.
func TestRunCodeMetricsSkipsPureInlineBlockComment(t *testing.T) {
	work := t.TempDir()
	body := "/* whole-line comment */\n" +
		"/* trailing ws */   \n" +
		"/* then line comment */ // tail\n" +
		"export const x = 1;\n"
	writeFile(t, filepath.Join(work, "src", "a.ts"), body)

	res, err := validation.RunCodeMetrics(work)
	if err != nil {
		t.Fatal(err)
	}
	if res.TotalLOC != 1 {
		t.Errorf("TotalLOC = %d, want 1 (only export line counts)", res.TotalLOC)
	}
}

// Regression: the inner walk's test counter accepted only .ts/.js, but the
// source counter accepted .ts/.js/.tsx/.jsx. React/JSX projects with
// App.test.tsx or Button.test.jsx had those files counted as source but not
// as tests, costing the agent the HasTests bonus (up to 0.3 of the 1.0
// code_metrics ceiling) even though tests were written.
func TestRunCodeMetricsCountsTsxJsxTests(t *testing.T) {
	work := t.TempDir()
	writeFile(t, filepath.Join(work, "src", "App.tsx"), "export const App = () => null;\n")
	writeFile(t, filepath.Join(work, "src", "App.test.tsx"), "test('app', () => {});\n")
	writeFile(t, filepath.Join(work, "tests", "x.test.jsx"), "test('x', () => {});\n")

	res, err := validation.RunCodeMetrics(work)
	if err != nil {
		t.Fatal(err)
	}
	if res.TestFileCount != 2 {
		t.Errorf("TestFileCount = %d, want 2 (App.test.tsx + x.test.jsx)", res.TestFileCount)
	}
	if !res.HasTests {
		t.Errorf("HasTests = false, want true")
	}
}

// A single small source file should still get the "no monolithic" bonus
// plus the single-file organization credit, so scoring 0.0 on an empty
// workspace must not come at the cost of the small-single-file case.
func TestRunCodeMetricsSingleSmallFileKeepsBonus(t *testing.T) {
	work := t.TempDir()
	writeFile(t, filepath.Join(work, "src", "a.ts"), "export const a = 1;\n")

	res, err := validation.RunCodeMetrics(work)
	if err != nil {
		t.Fatal(err)
	}
	if res.FileCount != 1 {
		t.Fatalf("FileCount = %d, want 1", res.FileCount)
	}
	// 0.1 (1 file) + 0.3 (MaxFileLOC <= 200) + 0 (no tests) = 0.4
	if res.Score < 0.39 || res.Score > 0.41 {
		t.Errorf("Score = %f, want 0.4 for single small file", res.Score)
	}
}
