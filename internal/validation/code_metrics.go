package validation

import (
	"os"
	"path/filepath"
	"strings"
)

// CodeMetricsResult holds the computed code metrics.
type CodeMetricsResult struct {
	Score        float64 // 0.0-1.0 composite metric score
	FileCount    int     // Number of .ts/.js source files
	TotalLOC     int     // Total lines of code (non-empty, non-comment)
	MaxFileLOC   int     // LOC of the largest file
	MaxFileName  string  // Name of the largest file
	AvgFileLOC   int     // Average LOC per file
	HasTests     bool    // Whether the agent wrote any test files
	TestFileCount int    // Number of test files
}

// RunCodeMetrics analyzes the agent's workspace for code quality signals:
// - File count and LOC distribution
// - No monolithic files (penalty for >500 LOC in a single file)
// - Agent wrote their own tests (bonus)
func RunCodeMetrics(workDir string) (*CodeMetricsResult, error) {
	result := &CodeMetricsResult{}
	srcDir := filepath.Join(workDir, "src")

	// Count source files and LOC
	err := filepath.Walk(srcDir, func(path string, info os.FileInfo, err error) error {
		if err != nil {
			return nil // skip errors
		}
		if info.IsDir() {
			return nil
		}
		ext := strings.ToLower(filepath.Ext(path))
		if ext != ".ts" && ext != ".js" && ext != ".tsx" && ext != ".jsx" {
			return nil
		}
		// Skip .gitkeep and declaration files
		if info.Name() == ".gitkeep" || strings.HasSuffix(info.Name(), ".d.ts") {
			return nil
		}

		loc := countLOC(path)
		result.FileCount++
		result.TotalLOC += loc
		if loc > result.MaxFileLOC {
			result.MaxFileLOC = loc
			rel, _ := filepath.Rel(workDir, path)
			result.MaxFileName = rel
		}
		return nil
	})
	if err != nil {
		return result, err
	}

	// Count agent-written tests by walking the whole workspace. Matches
	// tests/**, __tests__/**, and inline src/**/*.test.ts (and .js variants).
	// Nested tests/ subdirs (tests/unit, tests/integration) must be counted
	// too — the earlier non-recursive tests/ read missed them.
	filepath.Walk(workDir, func(path string, info os.FileInfo, err error) error {
		if err != nil {
			return nil
		}
		rel, _ := filepath.Rel(workDir, path)
		// Skip validation-tests and node_modules. Match the directory itself
		// (rel == name) or anything under it (rel starts with "name/") so we
		// don't accidentally prune sibling dirs like "validation-tests-extra".
		if rel == "validation-tests" || rel == "node_modules" ||
			strings.HasPrefix(rel, "validation-tests"+string(filepath.Separator)) ||
			strings.HasPrefix(rel, "node_modules"+string(filepath.Separator)) {
			if info.IsDir() {
				return filepath.SkipDir
			}
			return nil
		}
		if info.IsDir() {
			return nil
		}
		if strings.Contains(rel, "__tests__") || strings.Contains(rel, ".test.") || strings.Contains(rel, ".spec.") {
			ext := strings.ToLower(filepath.Ext(info.Name()))
			if ext == ".ts" || ext == ".js" || ext == ".tsx" || ext == ".jsx" {
				result.TestFileCount++
			}
		}
		return nil
	})
	result.HasTests = result.TestFileCount > 0

	if result.FileCount > 0 {
		result.AvgFileLOC = result.TotalLOC / result.FileCount
	}

	// Compute score
	result.Score = computeMetricsScore(result)
	return result, nil
}

func computeMetricsScore(m *CodeMetricsResult) float64 {
	score := 0.0

	// An empty workspace earns nothing. Otherwise the "no monolithic files"
	// branch below (MaxFileLOC <= 200) fires for MaxFileLOC == 0 and
	// silently rewards no-contribution trials.
	if m.FileCount == 0 {
		return 0.0
	}

	// File organization: multiple files preferred over monolith (0-0.4)
	if m.FileCount >= 3 {
		score += 0.4
	} else if m.FileCount == 2 {
		score += 0.3
	} else if m.FileCount == 1 {
		score += 0.1
	}

	// No monolithic files: penalty if any file > 500 LOC (0-0.3)
	if m.MaxFileLOC <= 200 {
		score += 0.3
	} else if m.MaxFileLOC <= 500 {
		score += 0.2
	} else if m.MaxFileLOC <= 800 {
		score += 0.1
	}
	// > 800 LOC: no points

	// Agent wrote tests (0-0.3)
	if m.HasTests {
		if m.TestFileCount >= 3 {
			score += 0.3
		} else if m.TestFileCount >= 1 {
			score += 0.2
		}
	}

	if score > 1.0 {
		score = 1.0
	}
	return score
}

// countLOC counts non-empty, non-comment lines in a file.
func countLOC(path string) int {
	data, err := os.ReadFile(path)
	if err != nil {
		return 0
	}
	lines := strings.Split(string(data), "\n")
	count := 0
	inBlockComment := false
	for _, line := range lines {
		trimmed := strings.TrimSpace(line)
		if trimmed == "" {
			continue
		}
		if inBlockComment {
			idx := strings.Index(trimmed, "*/")
			if idx < 0 {
				continue
			}
			inBlockComment = false
			rest := strings.TrimSpace(trimmed[idx+2:])
			if rest == "" || strings.HasPrefix(rest, "//") {
				continue
			}
			count++
			continue
		}
		if strings.HasPrefix(trimmed, "/*") {
			if idx := strings.Index(trimmed, "*/"); idx >= 0 {
				rest := strings.TrimSpace(trimmed[idx+2:])
				if rest == "" || strings.HasPrefix(rest, "//") {
					continue
				}
				count++
				continue
			}
			inBlockComment = true
			continue
		}
		if strings.HasPrefix(trimmed, "//") {
			continue
		}
		count++
	}
	return count
}
