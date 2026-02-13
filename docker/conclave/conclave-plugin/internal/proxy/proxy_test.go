package proxy

import (
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"net/http/httptest"
	"strings"
	"sync"
	"testing"
)

func TestNonStreamingTokenCounting(t *testing.T) {
	// Fake Anthropic API returning a non-streaming response with usage
	backend := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		resp := map[string]interface{}{
			"id":    "msg_123",
			"type":  "message",
			"model": "claude-opus-4-6",
			"usage": map[string]int{
				"input_tokens":  4231,
				"output_tokens": 892,
			},
			"content": []map[string]string{
				{"type": "text", "text": "Hello!"},
			},
		}
		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(resp)
	}))
	defer backend.Close()

	counter := &TokenCounter{}
	rp, err := New(backend.URL, counter)
	if err != nil {
		t.Fatalf("New: %v", err)
	}

	proxy := httptest.NewServer(rp)
	defer proxy.Close()

	resp, err := http.Post(proxy.URL+"/v1/messages", "application/json", strings.NewReader(`{"model":"claude-opus-4-6"}`))
	if err != nil {
		t.Fatalf("request: %v", err)
	}
	defer resp.Body.Close()
	io.ReadAll(resp.Body)

	if got := counter.InputTokens.Load(); got != 4231 {
		t.Errorf("input tokens = %d, want 4231", got)
	}
	if got := counter.OutputTokens.Load(); got != 892 {
		t.Errorf("output tokens = %d, want 892", got)
	}
	if got := counter.Requests.Load(); got != 1 {
		t.Errorf("requests = %d, want 1", got)
	}
}

func TestStreamingTokenCounting(t *testing.T) {
	// Fake Anthropic API returning an SSE stream
	backend := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "text/event-stream")
		w.Header().Set("Cache-Control", "no-cache")
		flusher, ok := w.(http.Flusher)
		if !ok {
			t.Fatal("expected flusher")
		}

		// message_start with input tokens
		fmt.Fprintf(w, "event: message_start\n")
		fmt.Fprintf(w, "data: {\"type\":\"message_start\",\"message\":{\"id\":\"msg_1\",\"model\":\"claude-opus-4-6\",\"usage\":{\"input_tokens\":5000,\"output_tokens\":0,\"cache_creation_input_tokens\":100,\"cache_read_input_tokens\":200}}}\n\n")
		flusher.Flush()

		// content_block_delta (no usage)
		fmt.Fprintf(w, "event: content_block_delta\n")
		fmt.Fprintf(w, "data: {\"type\":\"content_block_delta\",\"delta\":{\"type\":\"text_delta\",\"text\":\"Hello\"}}\n\n")
		flusher.Flush()

		// message_delta with output tokens
		fmt.Fprintf(w, "event: message_delta\n")
		fmt.Fprintf(w, "data: {\"type\":\"message_delta\",\"usage\":{\"output_tokens\":1500}}\n\n")
		flusher.Flush()

		// message_stop
		fmt.Fprintf(w, "event: message_stop\n")
		fmt.Fprintf(w, "data: {\"type\":\"message_stop\"}\n\n")
		flusher.Flush()
	}))
	defer backend.Close()

	counter := &TokenCounter{}
	rp, err := New(backend.URL, counter)
	if err != nil {
		t.Fatalf("New: %v", err)
	}

	proxy := httptest.NewServer(rp)
	defer proxy.Close()

	resp, err := http.Post(proxy.URL+"/v1/messages", "application/json", strings.NewReader(`{"model":"claude-opus-4-6","stream":true}`))
	if err != nil {
		t.Fatalf("request: %v", err)
	}
	defer resp.Body.Close()

	// Read all content to ensure streaming completes
	body, _ := io.ReadAll(resp.Body)
	bodyStr := string(body)

	// Verify content passed through
	if !strings.Contains(bodyStr, "message_start") {
		t.Error("stream missing message_start event")
	}
	if !strings.Contains(bodyStr, "Hello") {
		t.Error("stream missing content delta")
	}

	if got := counter.InputTokens.Load(); got != 5000 {
		t.Errorf("input tokens = %d, want 5000", got)
	}
	if got := counter.OutputTokens.Load(); got != 1500 {
		t.Errorf("output tokens = %d, want 1500", got)
	}
	if got := counter.CacheCreation.Load(); got != 100 {
		t.Errorf("cache creation = %d, want 100", got)
	}
	if got := counter.CacheRead.Load(); got != 200 {
		t.Errorf("cache read = %d, want 200", got)
	}
	if got := counter.Requests.Load(); got != 1 {
		t.Errorf("requests = %d, want 1", got)
	}
}

func TestPassThrough(t *testing.T) {
	// Verify that request headers, body, and response status/headers pass through
	backend := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		// Check that custom headers arrived
		if got := r.Header.Get("X-Api-Key"); got != "sk-test-123" {
			t.Errorf("x-api-key = %q, want %q", got, "sk-test-123")
		}
		if got := r.Header.Get("Anthropic-Version"); got != "2023-06-01" {
			t.Errorf("anthropic-version = %q, want %q", got, "2023-06-01")
		}

		// Check body passed through
		body, _ := io.ReadAll(r.Body)
		var req map[string]interface{}
		json.Unmarshal(body, &req)
		if req["model"] != "claude-opus-4-6" {
			t.Errorf("model = %v, want claude-opus-4-6", req["model"])
		}

		w.Header().Set("Content-Type", "application/json")
		w.Header().Set("X-Custom-Response", "test-value")
		w.WriteHeader(200)
		json.NewEncoder(w).Encode(map[string]interface{}{
			"id":    "msg_pass",
			"model": "claude-opus-4-6",
			"usage": map[string]int{"input_tokens": 10, "output_tokens": 5},
		})
	}))
	defer backend.Close()

	counter := &TokenCounter{}
	rp, err := New(backend.URL, counter)
	if err != nil {
		t.Fatalf("New: %v", err)
	}

	proxy := httptest.NewServer(rp)
	defer proxy.Close()

	req, _ := http.NewRequest("POST", proxy.URL+"/v1/messages", strings.NewReader(`{"model":"claude-opus-4-6"}`))
	req.Header.Set("X-Api-Key", "sk-test-123")
	req.Header.Set("Anthropic-Version", "2023-06-01")
	req.Header.Set("Content-Type", "application/json")

	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		t.Fatalf("request: %v", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != 200 {
		t.Errorf("status = %d, want 200", resp.StatusCode)
	}
	if got := resp.Header.Get("X-Custom-Response"); got != "test-value" {
		t.Errorf("X-Custom-Response = %q, want %q", got, "test-value")
	}

	// Body should be intact
	body, _ := io.ReadAll(resp.Body)
	var envelope map[string]interface{}
	json.Unmarshal(body, &envelope)
	if envelope["id"] != "msg_pass" {
		t.Errorf("response id = %v, want msg_pass", envelope["id"])
	}
}

func TestConcurrentRequests(t *testing.T) {
	backend := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(map[string]interface{}{
			"model": "claude-opus-4-6",
			"usage": map[string]int{"input_tokens": 100, "output_tokens": 50},
		})
	}))
	defer backend.Close()

	counter := &TokenCounter{}
	rp, err := New(backend.URL, counter)
	if err != nil {
		t.Fatalf("New: %v", err)
	}

	proxy := httptest.NewServer(rp)
	defer proxy.Close()

	const numRequests = 50
	var wg sync.WaitGroup
	wg.Add(numRequests)

	for i := 0; i < numRequests; i++ {
		go func() {
			defer wg.Done()
			resp, err := http.Post(proxy.URL+"/v1/messages", "application/json", strings.NewReader(`{}`))
			if err != nil {
				t.Errorf("request: %v", err)
				return
			}
			defer resp.Body.Close()
			io.ReadAll(resp.Body)
		}()
	}

	wg.Wait()

	if got := counter.Requests.Load(); got != int64(numRequests) {
		t.Errorf("requests = %d, want %d", got, numRequests)
	}
	if got := counter.InputTokens.Load(); got != int64(numRequests*100) {
		t.Errorf("input tokens = %d, want %d", got, numRequests*100)
	}
	if got := counter.OutputTokens.Load(); got != int64(numRequests*50) {
		t.Errorf("output tokens = %d, want %d", got, numRequests*50)
	}
}

func TestNonAPIPathPassThrough(t *testing.T) {
	backend := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		// Return plain text, not JSON
		w.Header().Set("Content-Type", "text/plain")
		w.WriteHeader(200)
		fmt.Fprint(w, "OK")
	}))
	defer backend.Close()

	counter := &TokenCounter{}
	rp, err := New(backend.URL, counter)
	if err != nil {
		t.Fatalf("New: %v", err)
	}

	proxy := httptest.NewServer(rp)
	defer proxy.Close()

	resp, err := http.Get(proxy.URL + "/health")
	if err != nil {
		t.Fatalf("request: %v", err)
	}
	defer resp.Body.Close()
	body, _ := io.ReadAll(resp.Body)

	if string(body) != "OK" {
		t.Errorf("body = %q, want %q", string(body), "OK")
	}
	if got := counter.Requests.Load(); got != 0 {
		t.Errorf("requests = %d, want 0 (non-API path)", got)
	}
}

func TestErrorResponsePassThrough(t *testing.T) {
	backend := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(429)
		json.NewEncoder(w).Encode(map[string]interface{}{
			"type": "error",
			"error": map[string]string{
				"type":    "rate_limit_error",
				"message": "Rate limited",
			},
		})
	}))
	defer backend.Close()

	counter := &TokenCounter{}
	rp, err := New(backend.URL, counter)
	if err != nil {
		t.Fatalf("New: %v", err)
	}

	proxy := httptest.NewServer(rp)
	defer proxy.Close()

	resp, err := http.Post(proxy.URL+"/v1/messages", "application/json", strings.NewReader(`{}`))
	if err != nil {
		t.Fatalf("request: %v", err)
	}
	defer resp.Body.Close()
	io.ReadAll(resp.Body)

	if resp.StatusCode != 429 {
		t.Errorf("status = %d, want 429", resp.StatusCode)
	}
	// No usage in error responses, so counters should be zero
	if got := counter.Requests.Load(); got != 0 {
		t.Errorf("requests = %d, want 0 (error response has no usage)", got)
	}
}

func TestSummaryFormatting(t *testing.T) {
	counter := &TokenCounter{}
	counter.InputTokens.Store(128432)
	counter.OutputTokens.Store(31208)
	counter.Requests.Store(47)
	counter.CacheCreation.Store(5000)
	counter.CacheRead.Store(10000)

	summary := counter.Summary()

	if !strings.Contains(summary, "128,432") {
		t.Errorf("summary missing formatted input tokens: %s", summary)
	}
	if !strings.Contains(summary, "31,208") {
		t.Errorf("summary missing formatted output tokens: %s", summary)
	}
	if !strings.Contains(summary, "159,640") {
		t.Errorf("summary missing formatted total tokens: %s", summary)
	}
	if !strings.Contains(summary, "47") {
		t.Errorf("summary missing request count: %s", summary)
	}
	if !strings.Contains(summary, "5,000") {
		t.Errorf("summary missing cache creation: %s", summary)
	}
	if !strings.Contains(summary, "10,000") {
		t.Errorf("summary missing cache read: %s", summary)
	}
}

func TestFormatNumber(t *testing.T) {
	tests := []struct {
		input int64
		want  string
	}{
		{0, "0"},
		{999, "999"},
		{1000, "1,000"},
		{1234567, "1,234,567"},
		{100, "100"},
	}
	for _, tt := range tests {
		got := formatNumber(tt.input)
		if got != tt.want {
			t.Errorf("formatNumber(%d) = %q, want %q", tt.input, got, tt.want)
		}
	}
}
