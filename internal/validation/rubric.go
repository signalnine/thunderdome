package validation

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"net/http"
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
var JudgeModel = "claude-sonnet-4-5"

// RunRubricJudge calls the LLM gateway to evaluate a diff against a rubric.
// It runs 3 evaluations and takes the median per criterion for reproducibility.
func RunRubricJudge(ctx context.Context, gatewayURL string, rubric []config.RubricCriterion, diff, taskDesc string) (map[string]float64, error) {
	if len(rubric) == 0 {
		return nil, nil
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
{"Follows existing code patterns": 0.8, "Minimal diff": 0.9}`, taskDesc, criteriaList, diff)

	allScores := make(map[string][]float64)
	for i := 0; i < 3; i++ {
		scores, err := callLLMJudge(ctx, gatewayURL, prompt)
		if err != nil {
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

func callLLMJudge(ctx context.Context, gatewayURL, prompt string) (map[string]float64, error) {
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

	content := chatResult.Choices[0].Message.Content
	content = strings.TrimPrefix(content, "```json")
	content = strings.TrimPrefix(content, "```")
	content = strings.TrimSuffix(content, "```")
	content = strings.TrimSpace(content)

	var scores map[string]float64
	if err := json.Unmarshal([]byte(content), &scores); err != nil {
		return nil, fmt.Errorf("parsing judge response: %w", err)
	}
	return scores, nil
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
