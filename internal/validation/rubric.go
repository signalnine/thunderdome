package validation

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"os"
	"path/filepath"
	"sort"
	"strings"

	"github.com/signalnine/thunderdome/internal/config"
)

// ComputeRubricScore calculates a weighted average from per-criterion scores.
func ComputeRubricScore(rubric []config.RubricCriterion, scores map[string]float64) float64 {
	if len(rubric) == 0 {
		return 0.0
	}
	var totalWeight, weightedSum float64
	for _, r := range rubric {
		score, ok := scores[r.Criterion]
		if !ok {
			continue
		}
		weightedSum += score * r.Weight
		totalWeight += r.Weight
	}
	if totalWeight == 0 {
		return 0.0
	}
	return weightedSum / totalWeight
}

// JudgeModel is the model used for rubric evaluation.
var JudgeModel = "gemini-2.0-flash"

// RubricJudgeInput contains all context for the rubric judge.
type RubricJudgeInput struct {
	Rubric      []config.RubricCriterion
	Diff        string
	SourceFiles string  // concatenated src/**/*.ts for greenfield tasks
	TaskDesc    string
	Category    string
	TestScore   float64
	LintScore   float64
}

// RunRubricJudge evaluates code against a rubric using an LLM.
// Runs 5 evaluations and takes the median per criterion for reproducibility.
func RunRubricJudge(ctx context.Context, gatewayURL string, input RubricJudgeInput) (map[string]float64, error) {
	if len(input.Rubric) == 0 {
		return nil, nil
	}

	prompt := buildRubricPrompt(input)

	allScores := make(map[string][]float64)
	for i := 0; i < 5; i++ {
		var scores map[string]float64
		var err error
		if gatewayURL != "" {
			scores, err = callLLMJudgeViaGateway(ctx, gatewayURL, prompt)
		} else {
			scores, err = callLLMJudgeDirect(ctx, prompt)
		}
		if err != nil {
			log.Printf("rubric judge attempt %d failed: %v", i+1, err)
			continue
		}
		for k, v := range scores {
			allScores[k] = append(allScores[k], v)
		}
	}

	result := make(map[string]float64)
	for k, v := range allScores {
		result[k] = MedianScore(v)
	}
	return result, nil
}

// buildRubricPrompt constructs the judge prompt with criterion descriptions,
// test/lint context, and either source files (greenfield) or diff.
func buildRubricPrompt(input RubricJudgeInput) string {
	var b strings.Builder

	b.WriteString("You are a code review judge. Score the code against each criterion on a scale of 0.0 to 1.0.\n\n")

	// Task context
	b.WriteString("## Task\n")
	b.WriteString(input.TaskDesc)
	b.WriteString("\n\n")

	// Test/lint context to anchor scoring
	b.WriteString(fmt.Sprintf("## Context\n- Test pass rate: %.0f%%\n- Lint score: %.0f%%\n", input.TestScore*100, input.LintScore*100))
	b.WriteString("Do NOT re-evaluate functional correctness unless a criterion specifically asks for it.\n\n")

	// Criteria with descriptions
	b.WriteString("## Criteria\nScore each of the following:\n")
	for _, r := range input.Rubric {
		if r.Description != "" {
			b.WriteString(fmt.Sprintf("- **%s** (weight: %.0f): %s\n", r.Criterion, r.Weight, r.Description))
		} else {
			b.WriteString(fmt.Sprintf("- **%s** (weight: %.0f)\n", r.Criterion, r.Weight))
		}
	}
	b.WriteString("\n")

	// Code to evaluate — source files for greenfield, diff otherwise
	if input.SourceFiles != "" {
		b.WriteString("## Source Files\n```\n")
		b.WriteString(input.SourceFiles)
		b.WriteString("\n```\n")
	} else {
		diff := smartTruncateDiff(input.Diff, 100_000)
		b.WriteString("## Diff\n```diff\n")
		b.WriteString(diff)
		b.WriteString("\n```\n")
	}

	// Response format
	b.WriteString("\nRespond with ONLY a JSON object mapping criterion name to score, e.g.:\n")
	b.WriteString("{")
	for i, r := range input.Rubric {
		if i > 0 {
			b.WriteString(", ")
		}
		b.WriteString(fmt.Sprintf("%q: 0.8", r.Criterion))
	}
	b.WriteString("}")

	return b.String()
}

// smartTruncateDiff truncates a diff while preserving the diffstat header
// and sampling proportionally across files.
func smartTruncateDiff(diff string, maxChars int) string {
	if len(diff) <= maxChars {
		return diff
	}

	// Try to find the end of the diffstat header (first "diff --git" line)
	lines := strings.SplitAfter(diff, "\n")
	var headerEnd int
	var headerLen int
	for i, line := range lines {
		if strings.HasPrefix(line, "diff --git ") {
			headerEnd = i
			break
		}
		headerLen += len(line)
	}

	// If no diffstat header, just truncate naively
	if headerEnd == 0 {
		return diff[:maxChars] + fmt.Sprintf("\n\n... [diff truncated from %d to %d chars] ...", len(diff), maxChars)
	}

	// Split into file diffs
	type fileDiff struct {
		header string
		body   string
	}
	var fileDiffs []fileDiff
	var current strings.Builder
	var currentHeader string

	for i := headerEnd; i < len(lines); i++ {
		if strings.HasPrefix(lines[i], "diff --git ") && current.Len() > 0 {
			fileDiffs = append(fileDiffs, fileDiff{header: currentHeader, body: current.String()})
			current.Reset()
			currentHeader = lines[i]
			current.WriteString(lines[i])
		} else {
			if current.Len() == 0 {
				currentHeader = lines[i]
			}
			current.WriteString(lines[i])
		}
	}
	if current.Len() > 0 {
		fileDiffs = append(fileDiffs, fileDiff{header: currentHeader, body: current.String()})
	}

	if len(fileDiffs) == 0 {
		return diff[:maxChars] + fmt.Sprintf("\n\n... [diff truncated from %d to %d chars] ...", len(diff), maxChars)
	}

	// Budget remaining chars across files proportionally
	budget := maxChars - headerLen - 100 // reserve for truncation notice
	if budget < 1000 {
		budget = 1000
	}
	perFile := budget / len(fileDiffs)

	var result strings.Builder
	// Write diffstat header
	for i := 0; i < headerEnd; i++ {
		result.WriteString(lines[i])
	}

	truncated := 0
	for _, fd := range fileDiffs {
		if len(fd.body) <= perFile {
			result.WriteString(fd.body)
		} else {
			result.WriteString(fd.body[:perFile])
			result.WriteString(fmt.Sprintf("\n... [file truncated at %d chars] ...\n", perFile))
			truncated++
		}
	}

	if truncated > 0 {
		result.WriteString(fmt.Sprintf("\n... [%d/%d files truncated, total %d → ~%d chars] ...\n",
			truncated, len(fileDiffs), len(diff), result.Len()))
	}

	return result.String()
}

// CollectSourceFiles walks the src/ directory and concatenates files with headers.
// Returns empty string if src/ doesn't exist or has no files.
func CollectSourceFiles(workDir string, maxChars int) string {
	srcDir := filepath.Join(workDir, "src")
	if _, err := os.Stat(srcDir); os.IsNotExist(err) {
		return ""
	}

	var result strings.Builder
	totalChars := 0

	filepath.Walk(srcDir, func(path string, info os.FileInfo, err error) error {
		if err != nil || info.IsDir() {
			return nil
		}
		ext := strings.ToLower(filepath.Ext(path))
		if ext != ".ts" && ext != ".js" && ext != ".tsx" && ext != ".jsx" {
			return nil
		}
		if info.Name() == ".gitkeep" || strings.HasSuffix(info.Name(), ".d.ts") {
			return nil
		}
		// Skip test files
		name := info.Name()
		if strings.Contains(name, ".test.") || strings.Contains(name, ".spec.") {
			return nil
		}

		data, err := os.ReadFile(path)
		if err != nil {
			return nil
		}

		rel, _ := filepath.Rel(workDir, path)
		header := fmt.Sprintf("// === %s ===\n", rel)

		if totalChars+len(header)+len(data) > maxChars {
			remaining := maxChars - totalChars - len(header) - 50
			if remaining > 100 {
				result.WriteString(header)
				result.Write(data[:remaining])
				result.WriteString("\n// ... [truncated] ...\n")
			}
			return filepath.SkipAll
		}

		result.WriteString(header)
		result.Write(data)
		result.WriteString("\n")
		totalChars += len(header) + len(data) + 1
		return nil
	})

	return result.String()
}

// callLLMJudgeDirect calls an LLM API via its OpenAI-compatible endpoint.
// Tries GEMINI_API_KEY first, then falls back to NVIDIA_API_KEY with OPENAI_BASE_URL.
func callLLMJudgeDirect(ctx context.Context, prompt string) (map[string]float64, error) {
	apiKey := os.Getenv("GEMINI_API_KEY")
	baseURL := "https://generativelanguage.googleapis.com/v1beta/openai"
	model := JudgeModel

	if apiKey == "" {
		// Fallback: NVIDIA inference API (OpenAI-compatible)
		apiKey = os.Getenv("NVIDIA_API_KEY")
		if envBase := os.Getenv("OPENAI_BASE_URL"); envBase != "" {
			baseURL = strings.TrimRight(envBase, "/")
		}
		if envModel := os.Getenv("JUDGE_MODEL"); envModel != "" {
			model = envModel
		}
	}
	if apiKey == "" {
		return nil, fmt.Errorf("GEMINI_API_KEY or NVIDIA_API_KEY not set")
	}

	reqBody := map[string]interface{}{
		"model":       model,
		"temperature": 0,
		"max_tokens":  4096,
		"messages": []map[string]string{
			{"role": "user", "content": prompt},
		},
	}
	bodyBytes, _ := json.Marshal(reqBody)

	req, err := http.NewRequestWithContext(ctx, "POST",
		baseURL+"/chat/completions",
		bytes.NewReader(bodyBytes))
	if err != nil {
		return nil, err
	}
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Authorization", "Bearer "+apiKey)

	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		var errBody map[string]interface{}
		json.NewDecoder(resp.Body).Decode(&errBody)
		return nil, fmt.Errorf("API returned %d: %v", resp.StatusCode, errBody)
	}

	var chatResult struct {
		Choices []struct {
			Message struct {
				Content string `json:"content"`
			} `json:"message"`
		} `json:"choices"`
	}
	if err := json.NewDecoder(resp.Body).Decode(&chatResult); err != nil {
		return nil, err
	}
	if len(chatResult.Choices) == 0 {
		return nil, fmt.Errorf("no choices in response")
	}

	return ParseJudgeResponse(chatResult.Choices[0].Message.Content)
}

// callLLMJudgeViaGateway calls an OpenAI-compatible gateway.
func callLLMJudgeViaGateway(ctx context.Context, gatewayURL, prompt string) (map[string]float64, error) {
	reqBody := map[string]interface{}{
		"model":       JudgeModel,
		"temperature": 0,
		"messages": []map[string]string{
			{"role": "user", "content": prompt},
		},
	}
	bodyBytes, _ := json.Marshal(reqBody)

	req, err := http.NewRequestWithContext(ctx, "POST", gatewayURL+"/v1/chat/completions", bytes.NewReader(bodyBytes))
	if err != nil {
		return nil, err
	}
	req.Header.Set("Content-Type", "application/json")

	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()

	var chatResult struct {
		Choices []struct {
			Message struct {
				Content string `json:"content"`
			} `json:"message"`
		} `json:"choices"`
	}
	if err := json.NewDecoder(resp.Body).Decode(&chatResult); err != nil {
		return nil, err
	}
	if len(chatResult.Choices) == 0 {
		return nil, fmt.Errorf("no choices in response")
	}

	return ParseJudgeResponse(chatResult.Choices[0].Message.Content)
}

// ParseJudgeResponse extracts a JSON score map from an LLM response.
// Handles markdown fences, preamble text, and trailing explanations.
func ParseJudgeResponse(content string) (map[string]float64, error) {
	// Extract JSON object by finding the first '{' and last '}'.
	// This handles markdown fences, preamble text, trailing explanations, etc.
	start := strings.Index(content, "{")
	end := strings.LastIndex(content, "}")
	if start == -1 || end == -1 || end <= start {
		return nil, fmt.Errorf("parsing judge response: no JSON object found in: %s", truncate(content, 200))
	}
	jsonStr := content[start : end+1]

	var scores map[string]float64
	if err := json.Unmarshal([]byte(jsonStr), &scores); err != nil {
		return nil, fmt.Errorf("parsing judge response: %w\ncontent: %s", err, truncate(jsonStr, 200))
	}
	return scores, nil
}

func truncate(s string, n int) string {
	if len(s) <= n {
		return s
	}
	return s[:n] + "..."
}

// MedianScore returns the median of a sorted slice of scores.
func MedianScore(scores []float64) float64 {
	if len(scores) == 0 {
		return 0.0
	}
	sorted := make([]float64, len(scores))
	copy(sorted, scores)
	sort.Float64s(sorted)
	mid := len(sorted) / 2
	if len(sorted)%2 == 0 {
		return (sorted[mid-1] + sorted[mid]) / 2
	}
	return sorted[mid]
}
