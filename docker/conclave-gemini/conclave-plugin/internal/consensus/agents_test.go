package consensus

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/signalnine/conclave/internal/config"
)

func TestClaudeAgent_Available(t *testing.T) {
	tests := []struct {
		name string
		key  string
		want bool
	}{
		{"with key", "sk-test", true},
		{"empty key", "", false},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			a := NewClaudeAgent(&config.Config{AnthropicAPIKey: tt.key})
			if got := a.Available(); got != tt.want {
				t.Errorf("Available() = %v, want %v", got, tt.want)
			}
		})
	}
}

func TestClaudeAgent_Run(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Header.Get("x-api-key") != "sk-test" {
			t.Error("missing api key header")
		}
		if r.Header.Get("anthropic-version") != "2023-06-01" {
			t.Error("missing version header")
		}
		json.NewEncoder(w).Encode(map[string]any{
			"content": []map[string]any{
				{"type": "text", "text": "claude response"},
			},
		})
	}))
	defer srv.Close()

	cfg := &config.Config{
		AnthropicAPIKey:    "sk-test",
		AnthropicModel:     "claude-test",
		AnthropicMaxTokens: 100,
		AnthropicBaseURL:   srv.URL,
	}
	a := NewClaudeAgent(cfg)
	got, err := a.Run(context.Background(), "test prompt")
	if err != nil {
		t.Fatal(err)
	}
	if got != "claude response" {
		t.Errorf("got %q", got)
	}
}

func TestClaudeAgent_APIError(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		json.NewEncoder(w).Encode(map[string]any{
			"error": map[string]any{"message": "rate limited"},
		})
	}))
	defer srv.Close()

	cfg := &config.Config{
		AnthropicAPIKey:  "sk-test",
		AnthropicBaseURL: srv.URL,
	}
	_, err := NewClaudeAgent(cfg).Run(context.Background(), "test")
	if err == nil {
		t.Error("expected error")
	}
}

func TestGeminiAgent_Run(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Query().Get("key") != "gm-test" {
			t.Error("missing api key query param")
		}
		json.NewEncoder(w).Encode(map[string]any{
			"candidates": []map[string]any{
				{"content": map[string]any{
					"parts": []map[string]any{
						{"text": "gemini response"},
					},
				}},
			},
		})
	}))
	defer srv.Close()

	cfg := &config.Config{
		GeminiAPIKey:  "gm-test",
		GeminiModel:   "gemini-test",
		GeminiBaseURL: srv.URL,
	}
	a := NewGeminiAgent(cfg)
	got, err := a.Run(context.Background(), "test prompt")
	if err != nil {
		t.Fatal(err)
	}
	if got != "gemini response" {
		t.Errorf("got %q", got)
	}
}

func TestGeminiAgent_Available(t *testing.T) {
	a := NewGeminiAgent(&config.Config{GeminiAPIKey: ""})
	if a.Available() {
		t.Error("should not be available without key")
	}
	a2 := NewGeminiAgent(&config.Config{GeminiAPIKey: "key"})
	if !a2.Available() {
		t.Error("should be available with key")
	}
}

func TestCodexAgent_Run_ResponsesAPI(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Header.Get("Authorization") != "Bearer op-test" {
			t.Error("missing auth header")
		}
		if r.URL.Path != "/v1/responses" {
			t.Errorf("path = %q, want /v1/responses", r.URL.Path)
		}
		json.NewEncoder(w).Encode(map[string]any{
			"output": []map[string]any{
				{"type": "message", "content": []map[string]any{
					{"type": "text", "text": "codex response"},
				}},
			},
		})
	}))
	defer srv.Close()

	cfg := &config.Config{
		OpenAIAPIKey:    "op-test",
		OpenAIModel:     "gpt-5.1-codex-max",
		OpenAIMaxTokens: 100,
		OpenAIBaseURL:   srv.URL,
	}
	got, err := NewCodexAgent(cfg).Run(context.Background(), "test")
	if err != nil {
		t.Fatal(err)
	}
	if got != "codex response" {
		t.Errorf("got %q", got)
	}
}

func TestCodexAgent_Run_ChatCompletions(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != "/v1/chat/completions" {
			t.Errorf("path = %q, want /v1/chat/completions", r.URL.Path)
		}
		json.NewEncoder(w).Encode(map[string]any{
			"choices": []map[string]any{
				{"message": map[string]any{"content": "chat response"}},
			},
		})
	}))
	defer srv.Close()

	cfg := &config.Config{
		OpenAIAPIKey:  "op-test",
		OpenAIModel:   "gpt-4o",
		OpenAIBaseURL: srv.URL,
	}
	got, err := NewCodexAgent(cfg).Run(context.Background(), "test")
	if err != nil {
		t.Fatal(err)
	}
	if got != "chat response" {
		t.Errorf("got %q", got)
	}
}

func TestAgent_ContextCancellation(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		<-r.Context().Done()
	}))
	defer srv.Close()

	cfg := &config.Config{
		AnthropicAPIKey:  "sk-test",
		AnthropicBaseURL: srv.URL,
	}
	ctx, cancel := context.WithCancel(context.Background())
	cancel()
	_, err := NewClaudeAgent(cfg).Run(ctx, "test")
	if err == nil {
		t.Error("expected error from cancelled context")
	}
}
