package validation

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"os"
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

// RunRubricJudge evaluates a diff against a rubric using an LLM.
// If gatewayURL is set, uses the proxy. Otherwise calls the Gemini API directly.
// Runs 3 evaluations and takes the median per criterion for reproducibility.
func RunRubricJudge(ctx context.Context, gatewayURL string, rubric []config.RubricCriterion, diff, taskDesc string) (map[string]float64, error) {
	if len(rubric) == 0 {
		return nil, nil
	}

	// Truncate large diffs to avoid exceeding model context window.
	// ~100K chars ≈ 25-30K tokens, leaving room for prompt and response.
	const maxDiffChars = 100_000
	if len(diff) > maxDiffChars {
		diff = diff[:maxDiffChars] + fmt.Sprintf("\n\n... [diff truncated from %d to %d chars] ...", len(diff), maxDiffChars)
	}

	criteriaList := ""
	for _, r := range rubric {
		criteriaList += fmt.Sprintf("- %s (weight: %.0f)\n", r.Criterion, r.Weight)
	}
	prompt := fmt.Sprintf(`You are a code review judge. Score this diff against each criterion on a scale of 0.0 to 1.0.

Task description:
%s

Criteria:
%s

Diff:
%s

Respond with ONLY a JSON object mapping criterion name to score, e.g.:
{"Concise": 0.8, "Correct": 0.9}`, taskDesc, criteriaList, diff)

	allScores := make(map[string][]float64)
	for i := 0; i < 3; i++ {
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
		"model":      model,
		"max_tokens": 4096,
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
