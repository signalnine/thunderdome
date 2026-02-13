package consensus

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"regexp"
	"strings"

	"github.com/signalnine/conclave/internal/config"
)

// Agent runs a prompt against an LLM and returns the response text.
type Agent interface {
	Name() string
	Run(ctx context.Context, prompt string) (string, error)
	Available() bool
}

// --- Claude ---

type ClaudeAgent struct {
	cfg *config.Config
}

func NewClaudeAgent(cfg *config.Config) *ClaudeAgent {
	return &ClaudeAgent{cfg: cfg}
}

func (a *ClaudeAgent) Name() string   { return "Claude" }
func (a *ClaudeAgent) Available() bool { return a.cfg.AnthropicAPIKey != "" }

func (a *ClaudeAgent) Run(ctx context.Context, prompt string) (string, error) {
	body := map[string]any{
		"model":      a.cfg.AnthropicModel,
		"max_tokens": a.cfg.AnthropicMaxTokens,
		"messages":   []map[string]any{{"role": "user", "content": prompt}},
	}
	data, _ := json.Marshal(body)

	url := strings.TrimRight(a.cfg.AnthropicBaseURL, "/") + "/v1/messages"
	req, err := http.NewRequestWithContext(ctx, "POST", url, bytes.NewReader(data))
	if err != nil {
		return "", err
	}
	req.Header.Set("x-api-key", a.cfg.AnthropicAPIKey)
	req.Header.Set("anthropic-version", "2023-06-01")
	req.Header.Set("content-type", "application/json")

	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		return "", err
	}
	defer resp.Body.Close()

	var result struct {
		Content []struct{ Text string } `json:"content"`
		Error   *struct{ Message string } `json:"error"`
	}
	if err := json.NewDecoder(resp.Body).Decode(&result); err != nil {
		return "", fmt.Errorf("decode: %w", err)
	}
	if result.Error != nil {
		return "", fmt.Errorf("API error: %s", result.Error.Message)
	}
	if len(result.Content) == 0 || result.Content[0].Text == "" {
		return "", fmt.Errorf("empty response")
	}
	return result.Content[0].Text, nil
}

// --- Gemini ---

type GeminiAgent struct {
	cfg *config.Config
}

func NewGeminiAgent(cfg *config.Config) *GeminiAgent {
	return &GeminiAgent{cfg: cfg}
}

func (a *GeminiAgent) Name() string   { return "Gemini" }
func (a *GeminiAgent) Available() bool { return a.cfg.GeminiAPIKey != "" }

func (a *GeminiAgent) Run(ctx context.Context, prompt string) (string, error) {
	body := map[string]any{
		"contents": []map[string]any{
			{"parts": []map[string]any{{"text": prompt}}},
		},
	}
	data, _ := json.Marshal(body)

	url := fmt.Sprintf("%s/v1beta/models/%s:generateContent?key=%s",
		strings.TrimRight(a.cfg.GeminiBaseURL, "/"), a.cfg.GeminiModel, a.cfg.GeminiAPIKey)
	req, err := http.NewRequestWithContext(ctx, "POST", url, bytes.NewReader(data))
	if err != nil {
		return "", err
	}
	req.Header.Set("Content-Type", "application/json")

	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		return "", err
	}
	defer resp.Body.Close()

	var result struct {
		Candidates []struct {
			Content struct {
				Parts []struct{ Text string } `json:"parts"`
			} `json:"content"`
		} `json:"candidates"`
		Error *struct{ Message string } `json:"error"`
	}
	if err := json.NewDecoder(resp.Body).Decode(&result); err != nil {
		return "", fmt.Errorf("decode: %w", err)
	}
	if result.Error != nil {
		return "", fmt.Errorf("API error: %s", result.Error.Message)
	}
	if len(result.Candidates) == 0 || len(result.Candidates[0].Content.Parts) == 0 {
		return "", fmt.Errorf("empty response")
	}
	return result.Candidates[0].Content.Parts[0].Text, nil
}

// --- Codex (OpenAI) ---

type CodexAgent struct {
	cfg *config.Config
}

func NewCodexAgent(cfg *config.Config) *CodexAgent {
	return &CodexAgent{cfg: cfg}
}

func (a *CodexAgent) Name() string   { return "Codex" }
func (a *CodexAgent) Available() bool { return a.cfg.OpenAIAPIKey != "" }

var codexModelRe = regexp.MustCompile(`^gpt-5.*-codex`)
var chatModelRe = regexp.MustCompile(`^(gpt-4|gpt-3\.5-turbo|o1|o3)`)

func (a *CodexAgent) Run(ctx context.Context, prompt string) (string, error) {
	base := strings.TrimRight(a.cfg.OpenAIBaseURL, "/")
	var url string
	var body map[string]any

	if codexModelRe.MatchString(a.cfg.OpenAIModel) {
		// Responses API for Codex models
		url = base + "/v1/responses"
		body = map[string]any{
			"model": a.cfg.OpenAIModel,
			"input": []map[string]any{{"role": "user", "content": prompt}},
		}
	} else if chatModelRe.MatchString(a.cfg.OpenAIModel) {
		url = base + "/v1/chat/completions"
		body = map[string]any{
			"model":      a.cfg.OpenAIModel,
			"max_tokens": a.cfg.OpenAIMaxTokens,
			"messages":   []map[string]any{{"role": "user", "content": prompt}},
		}
	} else {
		url = base + "/v1/completions"
		body = map[string]any{
			"model":      a.cfg.OpenAIModel,
			"max_tokens": a.cfg.OpenAIMaxTokens,
			"prompt":     prompt,
		}
	}

	data, _ := json.Marshal(body)
	req, err := http.NewRequestWithContext(ctx, "POST", url, bytes.NewReader(data))
	if err != nil {
		return "", err
	}
	req.Header.Set("Authorization", "Bearer "+a.cfg.OpenAIAPIKey)
	req.Header.Set("Content-Type", "application/json")

	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		return "", err
	}
	defer resp.Body.Close()

	respBody, _ := io.ReadAll(resp.Body)
	return a.extractResponse(respBody)
}

func (a *CodexAgent) extractResponse(body []byte) (string, error) {
	// Try Responses API format
	if codexModelRe.MatchString(a.cfg.OpenAIModel) {
		var result struct {
			Output []struct {
				Type    string `json:"type"`
				Content []struct{ Text string } `json:"content"`
			} `json:"output"`
		}
		if err := json.Unmarshal(body, &result); err == nil {
			for _, o := range result.Output {
				if o.Type == "message" && len(o.Content) > 0 {
					return o.Content[0].Text, nil
				}
			}
		}
	}

	// Try chat completions format
	var chat struct {
		Choices []struct {
			Message struct{ Content string } `json:"message"`
		} `json:"choices"`
	}
	if err := json.Unmarshal(body, &chat); err == nil && len(chat.Choices) > 0 {
		if c := chat.Choices[0].Message.Content; c != "" {
			return c, nil
		}
	}

	// Try completions format
	var comp struct {
		Choices []struct{ Text string } `json:"choices"`
	}
	if err := json.Unmarshal(body, &comp); err == nil && len(comp.Choices) > 0 {
		if c := comp.Choices[0].Text; c != "" {
			return c, nil
		}
	}

	// Check for error
	var errResp struct {
		Error struct{ Message string } `json:"error"`
	}
	if err := json.Unmarshal(body, &errResp); err == nil && errResp.Error.Message != "" {
		return "", fmt.Errorf("API error: %s", errResp.Error.Message)
	}

	return "", fmt.Errorf("empty response")
}
