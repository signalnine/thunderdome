package analyze

import (
	"bufio"
	"encoding/json"
	"os"
	"strings"
)

// ToolCall represents a single tool invocation extracted from the NDJSON trace.
type ToolCall struct {
	Name     string // Tool name: Write, Bash, Edit, Read, Glob, Grep, etc.
	FilePath string // For Write/Edit/Read: the target file path
	Command  string // For Bash: the shell command
	Index    int    // Chronological position in the trace
}

// Trace is the parsed behavioral trace from a trial's NDJSON output.
type Trace struct {
	ToolCalls    []ToolCall
	NumTurns     int
	DurationMS   int64
	TotalCostUSD float64
}

// ParseTrace reads a Claude Code stream-json NDJSON file and extracts
// the chronological sequence of tool calls plus summary metrics.
func ParseTrace(path string) (*Trace, error) {
	f, err := os.Open(path)
	if err != nil {
		return nil, err
	}
	defer f.Close()

	trace := &Trace{}
	scanner := bufio.NewScanner(f)
	scanner.Buffer(make([]byte, 0, 1024*1024), 10*1024*1024) // 10MB max line

	for scanner.Scan() {
		line := scanner.Bytes()
		if len(line) == 0 {
			continue
		}

		var env struct {
			Type    string          `json:"type"`
			Message json.RawMessage `json:"message"`
			// result fields
			NumTurns     int     `json:"num_turns"`
			DurationMS   int64   `json:"duration_ms"`
			TotalCostUSD float64 `json:"total_cost_usd"`
		}
		if err := json.Unmarshal(line, &env); err != nil {
			continue // skip malformed lines
		}

		switch env.Type {
		case "assistant":
			calls := extractToolCalls(env.Message, len(trace.ToolCalls))
			trace.ToolCalls = append(trace.ToolCalls, calls...)
		case "result":
			trace.NumTurns = env.NumTurns
			trace.DurationMS = env.DurationMS
			trace.TotalCostUSD = env.TotalCostUSD
		}
	}

	return trace, scanner.Err()
}

func extractToolCalls(raw json.RawMessage, startIndex int) []ToolCall {
	if len(raw) == 0 {
		return nil
	}

	// Handle message as either object or JSON string
	var msgBytes []byte
	if raw[0] == '"' {
		var s string
		if err := json.Unmarshal(raw, &s); err != nil {
			return nil
		}
		msgBytes = []byte(s)
	} else {
		msgBytes = raw
	}

	var msg struct {
		Content []struct {
			Type  string          `json:"type"`
			Name  string          `json:"name"`
			Input json.RawMessage `json:"input"`
		} `json:"content"`
	}
	if err := json.Unmarshal(msgBytes, &msg); err != nil {
		return nil
	}

	var calls []ToolCall
	for _, block := range msg.Content {
		if block.Type != "tool_use" {
			continue
		}
		tc := ToolCall{
			Name:  block.Name,
			Index: startIndex + len(calls),
		}
		// Extract relevant input fields
		var inp struct {
			FilePath string `json:"file_path"`
			Command  string `json:"command"`
		}
		if err := json.Unmarshal(block.Input, &inp); err == nil {
			tc.FilePath = inp.FilePath
			tc.Command = inp.Command
		}
		calls = append(calls, tc)
	}
	return calls
}

// IsTestFile returns true if the file path looks like a test file.
func IsTestFile(path string) bool {
	lower := strings.ToLower(path)
	return strings.Contains(lower, "test") ||
		strings.Contains(lower, "spec") ||
		strings.Contains(lower, "__tests__")
}

// IsImplFile returns true if the file path looks like an implementation file
// (source code that is not a test, config, or type definition).
func IsImplFile(path string) bool {
	if path == "" {
		return false
	}
	lower := strings.ToLower(path)
	// Exclude test files
	if IsTestFile(path) {
		return false
	}
	// Exclude config/meta files
	for _, exc := range []string{"package.json", "tsconfig", "vitest.config", "jest.config", ".eslint", "index.ts", "index.js"} {
		if strings.Contains(lower, exc) {
			return false
		}
	}
	// Must be a source file
	for _, ext := range []string{".ts", ".js", ".py", ".go", ".rs", ".java"} {
		if strings.HasSuffix(lower, ext) {
			return true
		}
	}
	return false
}
