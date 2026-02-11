package main

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"testing"
	"time"

	"nhooyr.io/websocket"
)

// helper: connect to a test server running the SDK protocol handler
func setupTestServer(t *testing.T, taskPrompt, metricsFile string) (*Server, *websocket.Conn) {
	t.Helper()

	srv := NewServer(taskPrompt, metricsFile, 5*time.Minute, true)

	connCh := make(chan *websocket.Conn, 1)
	httpSrv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		conn, err := websocket.Accept(w, r, &websocket.AcceptOptions{InsecureSkipVerify: true})
		if err != nil {
			t.Fatalf("accept: %v", err)
		}
		connCh <- conn
	}))
	t.Cleanup(httpSrv.Close)

	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	t.Cleanup(cancel)

	clientConn, _, err := websocket.Dial(ctx, "ws"+httpSrv.URL[4:], nil)
	if err != nil {
		t.Fatalf("dial: %v", err)
	}
	t.Cleanup(func() { clientConn.Close(websocket.StatusNormalClosure, "") })

	// Get server-side connection
	serverConn := <-connCh

	// Run server handler in background
	go func() {
		srv.HandleConnection(context.Background(), serverConn)
		serverConn.Close(websocket.StatusNormalClosure, "done")
	}()

	return srv, clientConn
}

func sendJSON(t *testing.T, conn *websocket.Conn, msg any) {
	t.Helper()
	data, err := json.Marshal(msg)
	if err != nil {
		t.Fatalf("marshal: %v", err)
	}
	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
	defer cancel()
	if err := conn.Write(ctx, websocket.MessageText, data); err != nil {
		t.Fatalf("write: %v", err)
	}
}

func readJSON(t *testing.T, conn *websocket.Conn) Message {
	t.Helper()
	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
	defer cancel()
	_, data, err := conn.Read(ctx)
	if err != nil {
		t.Fatalf("read: %v", err)
	}
	var msg Message
	if err := json.Unmarshal(data, &msg); err != nil {
		t.Fatalf("unmarshal: %v", err)
	}
	return msg
}

func TestInitHandshake(t *testing.T) {
	_, client := setupTestServer(t, "Build a CLI tool", "")

	// Send initialize request
	sendJSON(t, client, map[string]any{
		"type":                 "control_request",
		"subtype":              "initialize",
		"supportedApiVersions": []string{"1"},
	})

	// Expect initialize response
	resp := readJSON(t, client)
	if resp.Type != "control_response" || resp.Subtype != "initialize" {
		t.Errorf("expected control_response/initialize, got %s/%s", resp.Type, resp.Subtype)
	}
	if resp.APIVersion != "1" {
		t.Errorf("expected apiVersion 1, got %s", resp.APIVersion)
	}

	// Expect task prompt
	prompt := readJSON(t, client)
	if prompt.Type != "user" {
		t.Errorf("expected user message, got %s", prompt.Type)
	}

	var content []map[string]string
	if err := json.Unmarshal(prompt.Content, &content); err != nil {
		t.Fatalf("unmarshal content: %v", err)
	}
	if len(content) == 0 || content[0]["text"] != "Build a CLI tool" {
		t.Errorf("expected task prompt in content, got %v", content)
	}
}

func TestToolApproval(t *testing.T) {
	_, client := setupTestServer(t, "Test task", "")

	// Complete handshake
	sendJSON(t, client, map[string]any{
		"type":    "control_request",
		"subtype": "initialize",
	})
	readJSON(t, client) // init response
	readJSON(t, client) // task prompt

	// Send tool permission request
	sendJSON(t, client, map[string]any{
		"type":     "control_request",
		"subtype":  "can_use_tool",
		"toolName": "Bash",
		"input":    map[string]string{"command": "npm install"},
	})

	resp := readJSON(t, client)
	if resp.Type != "control_response" || resp.Subtype != "can_use_tool" {
		t.Errorf("expected can_use_tool response, got %s/%s", resp.Type, resp.Subtype)
	}
	if resp.Allowed == nil || !*resp.Allowed {
		t.Error("expected tool to be allowed")
	}
}

func TestResultExtraction(t *testing.T) {
	tmpDir := t.TempDir()
	metricsFile := filepath.Join(tmpDir, "metrics.json")

	srv, client := setupTestServer(t, "Test task", metricsFile)

	// Complete handshake
	sendJSON(t, client, map[string]any{
		"type":    "control_request",
		"subtype": "initialize",
	})
	readJSON(t, client) // init response
	readJSON(t, client) // task prompt

	// Send some assistant messages (count turns)
	sendJSON(t, client, map[string]any{"type": "assistant", "content": "thinking..."})
	sendJSON(t, client, map[string]any{"type": "assistant", "content": "more work..."})

	// Send tool request to track tools
	sendJSON(t, client, map[string]any{
		"type":     "control_request",
		"subtype":  "can_use_tool",
		"toolName": "Write",
	})
	readJSON(t, client) // tool response

	// Send result
	sendJSON(t, client, map[string]any{
		"type":   "result",
		"result": "Task completed",
		"usage": map[string]int{
			"input_tokens":  12000,
			"output_tokens": 4500,
		},
	})

	// Wait for metrics file to be written
	time.Sleep(200 * time.Millisecond)

	if srv.state != StateDone {
		t.Errorf("expected DONE state, got %s", srv.state)
	}

	data, err := os.ReadFile(metricsFile)
	if err != nil {
		t.Fatalf("read metrics: %v", err)
	}

	var metrics Metrics
	if err := json.Unmarshal(data, &metrics); err != nil {
		t.Fatalf("unmarshal metrics: %v", err)
	}

	if metrics.InputTokens != 12000 {
		t.Errorf("expected 12000 input tokens, got %d", metrics.InputTokens)
	}
	if metrics.OutputTokens != 4500 {
		t.Errorf("expected 4500 output tokens, got %d", metrics.OutputTokens)
	}
	if metrics.Turns != 2 {
		t.Errorf("expected 2 turns, got %d", metrics.Turns)
	}
	if len(metrics.ToolsUsed) != 1 || metrics.ToolsUsed[0] != "Write" {
		t.Errorf("expected [Write], got %v", metrics.ToolsUsed)
	}
}

func TestMultipleToolsTracked(t *testing.T) {
	srv, client := setupTestServer(t, "Test task", "")

	// Complete handshake
	sendJSON(t, client, map[string]any{
		"type":    "control_request",
		"subtype": "initialize",
	})
	readJSON(t, client) // init response
	readJSON(t, client) // task prompt

	// Send multiple tool requests (including duplicate)
	tools := []string{"Bash", "Read", "Write", "Bash"}
	for _, tool := range tools {
		sendJSON(t, client, map[string]any{
			"type":     "control_request",
			"subtype":  "can_use_tool",
			"toolName": tool,
		})
		readJSON(t, client)
	}

	// Bash should only appear once (deduped)
	if len(srv.metrics.ToolsUsed) != 3 {
		t.Errorf("expected 3 unique tools, got %d: %v", len(srv.metrics.ToolsUsed), srv.metrics.ToolsUsed)
	}
}

func TestInvalidInitMessage(t *testing.T) {
	srv := NewServer("test", "", 5*time.Minute, true)
	srv.state = StateInitializing

	_, err := srv.handleMessage(&Message{
		Type:    "user",
		Subtype: "",
	})

	if err == nil {
		t.Error("expected error for non-initialize message during init")
	}
}

func TestStateTransitions(t *testing.T) {
	srv := NewServer("task", "", 5*time.Minute, false)
	if srv.state != StateWaiting {
		t.Errorf("initial state should be WAITING, got %s", srv.state)
	}

	// Simulate connection → INITIALIZING
	srv.state = StateInitializing

	// Handle init → RUNNING
	responses, err := srv.handleMessage(&Message{
		Type:    "control_request",
		Subtype: "initialize",
	})
	if err != nil {
		t.Fatalf("init: %v", err)
	}
	if srv.state != StateRunning {
		t.Errorf("expected RUNNING after init, got %s", srv.state)
	}
	if len(responses) != 2 {
		t.Fatalf("expected 2 responses (init + prompt), got %d", len(responses))
	}

	// Handle result → DONE
	_, err = srv.handleMessage(&Message{
		Type:   "result",
		Result: "done",
		Usage:  &Usage{InputTokens: 100, OutputTokens: 50},
	})
	if err != nil {
		t.Fatalf("result: %v", err)
	}
	if srv.state != StateDone {
		t.Errorf("expected DONE after result, got %s", srv.state)
	}
	if srv.metrics.InputTokens != 100 {
		t.Errorf("expected 100 input tokens, got %d", srv.metrics.InputTokens)
	}
}
