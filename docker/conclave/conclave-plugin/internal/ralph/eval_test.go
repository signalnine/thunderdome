package ralph

import (
	"context"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

func TestExtractFilePaths_NodeJS(t *testing.T) {
	output := `FAIL src/routes/users.test.js
  ● POST /users › returns 201

    TypeError: Cannot read properties of undefined
      at Object.<anonymous> (src/routes/users.js:45:12)
      at processTicksAndRejections (node:internal/process/task_queues:95:5)

  ● GET /users › returns list

    Error: expected 200 got 404
      at Object.<anonymous> (src/routes/users.js:12:5)
      at Object.<anonymous> (src/middleware/auth.js:8:3)`

	paths := ExtractFilePathsFromOutput(output)
	expected := map[string]bool{
		"src/routes/users.js":      true,
		"src/middleware/auth.js":    true,
		"src/routes/users.test.js": true,
	}
	for _, p := range paths {
		if !expected[p] {
			t.Errorf("unexpected path: %s", p)
		}
		delete(expected, p)
	}
	for p := range expected {
		t.Errorf("missing path: %s", p)
	}
}

func TestExtractFilePaths_Python(t *testing.T) {
	output := `FAILED tests/test_api.py::test_create_user
  File "src/api/users.py", line 23, in create_user
    raise ValueError("invalid email")
  File "src/api/validators.py", line 8, in validate_email
    return re.match(pattern, email)`

	paths := ExtractFilePathsFromOutput(output)
	expected := map[string]bool{
		"src/api/users.py":      true,
		"src/api/validators.py": true,
		"tests/test_api.py":     true,
	}
	for _, p := range paths {
		if !expected[p] {
			t.Errorf("unexpected path: %s", p)
		}
		delete(expected, p)
	}
	for p := range expected {
		t.Errorf("missing path: %s", p)
	}
}

func TestExtractFilePaths_Go(t *testing.T) {
	output := "--- FAIL: TestCreateUser (0.01s)\n    users_test.go:34: expected 201 got 500\ngoroutine 1 [running]:\nmain.createUser(...)\n\tcmd/server/handlers.go:45\nmain.validateInput(...)\n\tinternal/validation/input.go:12"

	paths := ExtractFilePathsFromOutput(output)
	expected := map[string]bool{
		"cmd/server/handlers.go":       true,
		"internal/validation/input.go": true,
	}
	for _, p := range paths {
		if !expected[p] {
			t.Errorf("unexpected path: %s", p)
		}
		delete(expected, p)
	}
	for p := range expected {
		t.Errorf("missing path: %s", p)
	}
}

func TestExtractFilePaths_FiltersNodeModules(t *testing.T) {
	output := `Error: foo
      at Object.<anonymous> (node_modules/express/lib/router.js:12:5)
      at Object.<anonymous> (src/app.js:3:10)`

	paths := ExtractFilePathsFromOutput(output)
	for _, p := range paths {
		if p == "node_modules/express/lib/router.js" {
			t.Error("should filter node_modules")
		}
	}
	found := false
	for _, p := range paths {
		if p == "src/app.js" {
			found = true
		}
	}
	if !found {
		t.Error("should include src/app.js")
	}
}

func TestExtractFilePaths_Empty(t *testing.T) {
	paths := ExtractFilePathsFromOutput("")
	if len(paths) != 0 {
		t.Errorf("expected empty, got %v", paths)
	}
}

func TestCollectRelevantFiles(t *testing.T) {
	dir := t.TempDir()

	os.MkdirAll(filepath.Join(dir, "src"), 0755)
	os.WriteFile(filepath.Join(dir, "src", "app.js"), []byte("const x = 1;\n"), 0644)
	os.WriteFile(filepath.Join(dir, "src", "util.js"), []byte("module.exports = {};\n"), 0644)
	os.MkdirAll(filepath.Join(dir, "node_modules", "express"), 0755)
	os.WriteFile(filepath.Join(dir, "node_modules", "express", "index.js"), []byte("nope"), 0644)

	diffFiles := []string{"src/app.js", "src/util.js"}
	traceFiles := []string{"src/app.js"}

	files, err := CollectRelevantFiles(dir, diffFiles, traceFiles, 8000)
	if err != nil {
		t.Fatal(err)
	}

	if len(files) != 2 {
		t.Fatalf("expected 2 files, got %d", len(files))
	}

	// Files in both lists should come first (src/app.js)
	if files[0].Path != "src/app.js" {
		t.Errorf("expected src/app.js first (in both lists), got %s", files[0].Path)
	}
}

func TestCollectRelevantFiles_LineCap(t *testing.T) {
	dir := t.TempDir()

	var content strings.Builder
	for i := 0; i < 100; i++ {
		content.WriteString("line\n")
	}
	os.WriteFile(filepath.Join(dir, "big.js"), []byte(content.String()), 0644)
	os.WriteFile(filepath.Join(dir, "aaa.js"), []byte("tiny\n"), 0644)

	// aaa.js sorts first, gets included (2 lines), then big.js is skipped (2+101 > 50)
	diffFiles := []string{"big.js", "aaa.js"}

	files, err := CollectRelevantFiles(dir, diffFiles, nil, 50)
	if err != nil {
		t.Fatal(err)
	}

	totalLines := 0
	for _, f := range files {
		totalLines += strings.Count(f.Content, "\n") + 1
	}
	if totalLines > 50 {
		t.Errorf("total lines %d exceeds cap 50", totalLines)
	}
}

func TestCollectRelevantFiles_FiltersBinaryAndTraversal(t *testing.T) {
	dir := t.TempDir()

	os.WriteFile(filepath.Join(dir, "image.png"), []byte("binary"), 0644)
	os.WriteFile(filepath.Join(dir, "code.js"), []byte("ok\n"), 0644)

	diffFiles := []string{"image.png", "code.js", "../../etc/passwd"}

	files, err := CollectRelevantFiles(dir, diffFiles, nil, 8000)
	if err != nil {
		t.Fatal(err)
	}

	for _, f := range files {
		if f.Path == "image.png" {
			t.Error("should filter binary files")
		}
		if f.Path == "../../etc/passwd" {
			t.Error("should filter path traversal")
		}
	}
	if len(files) != 1 || files[0].Path != "code.js" {
		t.Errorf("expected only code.js, got %v", files)
	}
}

func TestBuildEvalPrompt(t *testing.T) {
	spec := "Build a REST API with POST /users endpoint"
	testOutput := "FAIL: expected 201 got 404"
	files := []FileContent{
		{Path: "src/routes.js", Content: "const express = require('express');\n"},
	}

	prompt := BuildEvalPrompt(spec, testOutput, files)

	required := []string{
		"diagnostic assistant",
		"## Task Spec",
		"Build a REST API",
		"## Test Output",
		"expected 201 got 404",
		"## Source Files",
		"### src/routes.js",
		"## Instructions",
		"## Failing Tests",
		"## Unmet Requirements",
		"## Priority Fix",
		"## Suggested Approach",
	}
	for _, s := range required {
		if !strings.Contains(prompt, s) {
			t.Errorf("prompt missing: %q", s)
		}
	}
}

func TestBuildEvalPrompt_TruncatesTestOutput(t *testing.T) {
	spec := "task"
	var lines []string
	for i := 0; i < 300; i++ {
		lines = append(lines, "error line")
	}
	testOutput := strings.Join(lines, "\n")

	prompt := BuildEvalPrompt(spec, testOutput, nil)

	if strings.Count(prompt, "error line") > 200 {
		t.Error("test output should be truncated to 200 lines")
	}
	if !strings.Contains(prompt, "truncated") {
		t.Error("should contain truncation notice")
	}
}

func TestRunEvalGate_NoPanic(t *testing.T) {
	// Verify RunEvalGate doesn't panic even with invalid inputs
	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
	defer cancel()
	dir := t.TempDir()

	// Should return error (no git repo, no claude), not panic
	_, err := RunEvalGate(ctx, dir, "build something", "test failed", "", 2)
	if err == nil {
		t.Log("RunEvalGate succeeded unexpectedly (claude available)")
	}
}
