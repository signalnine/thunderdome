package proxy

import (
	"bufio"
	"bytes"
	"crypto/tls"
	"encoding/json"
	"fmt"
	"io"
	"log"
	"net/http"
	"net/http/httputil"
	"net/url"
	"strings"
	"sync/atomic"
)

// TokenCounter tracks token usage across proxy requests.
type TokenCounter struct {
	InputTokens  atomic.Int64
	OutputTokens atomic.Int64
	Requests     atomic.Int64
	CacheCreation atomic.Int64
	CacheRead     atomic.Int64
}

// Summary returns a formatted summary of token usage.
func (tc *TokenCounter) Summary() string {
	input := tc.InputTokens.Load()
	output := tc.OutputTokens.Load()
	requests := tc.Requests.Load()
	cacheCreation := tc.CacheCreation.Load()
	cacheRead := tc.CacheRead.Load()
	total := input + output

	var b strings.Builder
	fmt.Fprintf(&b, "Session summary:\n")
	fmt.Fprintf(&b, "  Requests:             %s\n", formatNumber(requests))
	fmt.Fprintf(&b, "  Input tokens:         %s\n", formatNumber(input))
	fmt.Fprintf(&b, "  Output tokens:        %s\n", formatNumber(output))
	if cacheCreation > 0 {
		fmt.Fprintf(&b, "  Cache creation:       %s\n", formatNumber(cacheCreation))
	}
	if cacheRead > 0 {
		fmt.Fprintf(&b, "  Cache read:           %s\n", formatNumber(cacheRead))
	}
	fmt.Fprintf(&b, "  Total tokens:         %s\n", formatNumber(total))
	return b.String()
}

// formatNumber adds comma separators to an integer.
func formatNumber(n int64) string {
	if n < 0 {
		return "-" + formatNumber(-n)
	}
	s := fmt.Sprintf("%d", n)
	if len(s) <= 3 {
		return s
	}
	var result []byte
	for i, c := range s {
		if i > 0 && (len(s)-i)%3 == 0 {
			result = append(result, ',')
		}
		result = append(result, byte(c))
	}
	return string(result)
}

// usage is the common shape of Anthropic API usage fields.
type usage struct {
	InputTokens         int64 `json:"input_tokens"`
	OutputTokens        int64 `json:"output_tokens"`
	CacheCreationTokens int64 `json:"cache_creation_input_tokens"`
	CacheReadTokens     int64 `json:"cache_read_input_tokens"`
}

// responseEnvelope is a minimal parse of the API response body.
type responseEnvelope struct {
	Usage *usage `json:"usage"`
	Model string `json:"model"`
}

// sseEvent represents a parsed SSE event.
type sseEvent struct {
	Event string
	Data  string
}

// sseEnvelope wraps the data payload of an SSE event.
type sseEnvelope struct {
	Type    string `json:"type"`
	Usage   *usage `json:"usage"`
	Message *struct {
		Model string `json:"model"`
		Usage *usage `json:"usage"`
	} `json:"message"`
}

// New creates a new reverse proxy that forwards to the given target URL
// and counts tokens from API responses.
func New(targetURL string, counter *TokenCounter) (*httputil.ReverseProxy, error) {
	target, err := url.Parse(targetURL)
	if err != nil {
		return nil, fmt.Errorf("parse target URL: %w", err)
	}

	proxy := &httputil.ReverseProxy{
		Director: func(req *http.Request) {
			req.URL.Scheme = target.Scheme
			req.URL.Host = target.Host
			req.Host = target.Host
		},
		Transport: &http.Transport{
			TLSClientConfig: &tls.Config{},
		},
		ModifyResponse: func(resp *http.Response) error {
			ct := resp.Header.Get("Content-Type")

			if strings.Contains(ct, "text/event-stream") {
				return handleStreamingResponse(resp, counter)
			}

			if strings.Contains(ct, "application/json") {
				return handleJSONResponse(resp, counter)
			}

			return nil
		},
	}

	return proxy, nil
}

// handleJSONResponse reads a non-streaming JSON response, extracts token usage,
// and reconstructs the response body.
func handleJSONResponse(resp *http.Response, counter *TokenCounter) error {
	body, err := io.ReadAll(resp.Body)
	resp.Body.Close()
	if err != nil {
		resp.Body = io.NopCloser(bytes.NewReader(nil))
		return nil
	}

	// Restore body for the client
	resp.Body = io.NopCloser(bytes.NewReader(body))

	var env responseEnvelope
	if err := json.Unmarshal(body, &env); err != nil {
		return nil
	}

	if env.Usage != nil {
		counter.InputTokens.Add(env.Usage.InputTokens)
		counter.OutputTokens.Add(env.Usage.OutputTokens)
		counter.CacheCreation.Add(env.Usage.CacheCreationTokens)
		counter.CacheRead.Add(env.Usage.CacheReadTokens)
		counter.Requests.Add(1)
		log.Printf("[proxy] model=%s input=%d output=%d cache_create=%d cache_read=%d",
			env.Model, env.Usage.InputTokens, env.Usage.OutputTokens,
			env.Usage.CacheCreationTokens, env.Usage.CacheReadTokens)
	}

	return nil
}

// handleStreamingResponse wraps the response body to scan SSE events for token
// usage while passing all data through to the client in real-time.
func handleStreamingResponse(resp *http.Response, counter *TokenCounter) error {
	original := resp.Body

	pr, pw := io.Pipe()

	go func() {
		defer pw.Close()
		defer original.Close()

		var model string
		var inputCounted bool
		reader := bufio.NewReader(original)
		var currentEvent string

		for {
			line, err := reader.ReadString('\n')
			if len(line) > 0 {
				// Write through to client immediately
				if _, werr := pw.Write([]byte(line)); werr != nil {
					return
				}

				trimmed := strings.TrimRight(line, "\r\n")

				if strings.HasPrefix(trimmed, "event: ") {
					currentEvent = strings.TrimPrefix(trimmed, "event: ")
				} else if strings.HasPrefix(trimmed, "data: ") {
					data := strings.TrimPrefix(trimmed, "data: ")
					extractSSEUsage(data, currentEvent, counter, &model, &inputCounted)
				}
			}
			if err != nil {
				return
			}
		}
	}()

	resp.Body = pr
	return nil
}

// extractSSEUsage parses an SSE data payload and accumulates token counts.
func extractSSEUsage(data, eventType string, counter *TokenCounter, model *string, inputCounted *bool) {
	var env sseEnvelope
	if err := json.Unmarshal([]byte(data), &env); err != nil {
		return
	}

	// message_start contains the initial usage (input tokens) and model
	if env.Type == "message_start" && env.Message != nil {
		if env.Message.Model != "" {
			*model = env.Message.Model
		}
		if env.Message.Usage != nil && !*inputCounted {
			counter.InputTokens.Add(env.Message.Usage.InputTokens)
			counter.CacheCreation.Add(env.Message.Usage.CacheCreationTokens)
			counter.CacheRead.Add(env.Message.Usage.CacheReadTokens)
			*inputCounted = true
		}
	}

	// message_delta contains the final usage (output tokens)
	if env.Type == "message_delta" && env.Usage != nil {
		counter.OutputTokens.Add(env.Usage.OutputTokens)
		counter.Requests.Add(1)
		log.Printf("[proxy] model=%s input=%d output=%d (streaming)",
			*model, counter.InputTokens.Load(), env.Usage.OutputTokens)
	}
}
