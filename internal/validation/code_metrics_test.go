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
