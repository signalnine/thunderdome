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

func readRawJSON(t *testing.T, conn *websocket.Conn) map[string]any {
	t.Helper()
	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
	defer cancel()
	_, data, err := conn.Read(ctx)
	if err != nil {
		t.Fatalf("read: %v", err)
	}
	var msg map[string]any
	if err := json.Unmarshal(data, &msg); err != nil {
		t.Fatalf("unmarshal: %v", err)
	}
	return msg
}

// sendSystemInit sends the system/init message that Claude Code sends first.
func sendSystemInit(t *testing.T, conn *websocket.Conn) {
	t.Helper()
	sendJSON(t, conn, map[string]any{
		"type":                "system",
		"subtype":             "init",
		"uuid":                "test-uuid-1234",
		"session_id":          "test-session-5678",
		"cwd":                 "/workspace",
		"tools":               []string{"Bash", "Read", "Write", "Edit", "Glob", "Grep"},
		"model":               "claude-sonnet-4-5-20250929",
		"permissionMode":      "default",
		"claude_code_version": "2.1.39",
	})
}

func TestInitHandshake(t *testing.T) {
	_, client := setupTestServer(t, "Build a CLI tool", "")

	// Send system/init (what Claude Code sends first)
	sendSystemInit(t, client)

	// Expect task prompt as user message
	prompt := readRawJSON(t, client)
	if prompt["type"] != "user" {
		t.Errorf("expected user message, got %s", prompt["type"])
	}

	// Check nested message structure
	msg, ok := prompt["message"].(map[string]any)
	if !ok {
		t.Fatalf("expected message to be object, got %T", prompt["message"])
	}
	if msg["role"] != "user" {
		t.Errorf("expected role=user, got %s", msg["role"])
	}
	if msg["content"] != "Build a CLI tool" {
		t.Errorf("expected task prompt in content, got %v", msg["content"])
	}

	// parent_tool_use_id should be null
	if prompt["parent_tool_use_id"] != nil {
		t.Errorf("expected parent_tool_use_id=null, got %v", prompt["parent_tool_use_id"])
	}

	// session_id should match init
	if prompt["session_id"] != "test-session-5678" {
		t.Errorf("expected session_id=test-session-5678, got %v", prompt["session_id"])
	}
}

func TestToolApproval(t *testing.T) {
	_, client := setupTestServer(t, "Test task", "")

	// Complete handshake
	sendSystemInit(t, client)
	readRawJSON(t, client) // task prompt

	// Send tool permission request (new nested format)
	sendJSON(t, client, map[string]any{
		"type":       "control_request",
		"request_id": "req-001",
		"request": map[string]any{
			"subtype":     "can_use_tool",
			"tool_name":   "Bash",
			"input":       map[string]string{"command": "npm install"},
			"tool_use_id": "toolu_01ABC",
		},
	})

	resp := readRawJSON(t, client)
	if resp["type"] != "control_response" {
		t.Errorf("expected control_response, got %s", resp["type"])
	}

	// Check nested response structure
	respBody, ok := resp["response"].(map[string]any)
	if !ok {
		t.Fatalf("expected response to be object, got %T", resp["response"])
	}
	if respBody["subtype"] != "success" {
		t.Errorf("expected subtype=success, got %s", respBody["subtype"])
	}
	if respBody["request_id"] != "req-001" {
		t.Errorf("expected request_id=req-001, got %s", respBody["request_id"])
	}

	innerResp, ok := respBody["response"].(map[string]any)
	if !ok {
		t.Fatalf("expected inner response to be object, got %T", respBody["response"])
	}
	if innerResp["behavior"] != "allow" {
		t.Errorf("expected behavior=allow, got %s", innerResp["behavior"])
	}

	// updatedInput should match original input
	updatedInput, ok := innerResp["updatedInput"].(map[string]any)
	if !ok {
		t.Fatalf("expected updatedInput to be object, got %T", innerResp["updatedInput"])
	}
	if updatedInput["command"] != "npm install" {
		t.Errorf("expected command=npm install, got %v", updatedInput["command"])
	}
}

func TestResultExtraction(t *testing.T) {
	tmpDir := t.TempDir()
	metricsFile := filepath.Join(tmpDir, "metrics.json")

	srv, client := setupTestServer(t, "Test task", metricsFile)

	// Complete handshake
	sendSystemInit(t, client)
	readRawJSON(t, client) // task prompt

	// Send some assistant messages (count turns)
	sendJSON(t, client, map[string]any{
		"type":       "assistant",
		"uuid":       "msg-1",
		"session_id": "test-session-5678",
		"message": map[string]any{
			"role":    "assistant",
			"content": []map[string]any{{"type": "text", "text": "thinking..."}},
			"usage": map[string]int{
				"input_tokens":  5000,
				"output_tokens": 1000,
			},
		},
	})
	sendJSON(t, client, map[string]any{
		"type":       "assistant",
		"uuid":       "msg-2",
		"session_id": "test-session-5678",
		"message": map[string]any{
			"role":    "assistant",
			"content": []map[string]any{{"type": "text", "text": "more work..."}},
			"usage": map[string]int{
				"input_tokens":  7000,
				"output_tokens": 3500,
			},
		},
	})

	// Send tool request to track tools
	sendJSON(t, client, map[string]any{
		"type":       "control_request",
		"request_id": "req-002",
		"request": map[string]any{
			"subtype":     "can_use_tool",
			"tool_name":   "Write",
			"input":       map[string]any{"file_path": "/workspace/src/index.ts", "content": "hello"},
			"tool_use_id": "toolu_02DEF",
		},
	})
	readRawJSON(t, client) // tool response

	// Send result with cumulative usage
	sendJSON(t, client, map[string]any{
		"type":           "result",
		"subtype":        "success",
		"uuid":           "result-1",
		"session_id":     "test-session-5678",
		"is_error":       false,
		"result":         "Task completed",
		"duration_ms":    45000,
		"num_turns":      2,
		"total_cost_usd": 0.035,
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

	// Result usage is authoritative (cumulative totals)
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
	if metrics.DurationMs != 45000 {
		t.Errorf("expected duration_ms=45000, got %d", metrics.DurationMs)
	}
}

func TestMultipleToolsTracked(t *testing.T) {
	srv, client := setupTestServer(t, "Test task", "")

	// Complete handshake
	sendSystemInit(t, client)
	readRawJSON(t, client) // task prompt

	// Send multiple tool requests (including duplicate)
	tools := []string{"Bash", "Read", "Write", "Bash"}
	for i, tool := range tools {
		sendJSON(t, client, map[string]any{
			"type":       "control_request",
			"request_id": "req-" + tool + "-" + string(rune('0'+i)),
			"request": map[string]any{
				"subtype":     "can_use_tool",
				"tool_name":   tool,
				"input":       map[string]any{},
				"tool_use_id": "toolu_" + tool,
			},
		})
		readRawJSON(t, client)
	}

	// Bash should only appear once (deduped)
	if len(srv.metrics.ToolsUsed) != 3 {
		t.Errorf("expected 3 unique tools, got %d: %v", len(srv.metrics.ToolsUsed), srv.metrics.ToolsUsed)
	}
}

func TestInvalidInitMessage(t *testing.T) {
	srv := NewServer("test", "", 5*time.Minute, true)
	srv.state = StateInit

	_, err := srv.handleMessage(&Envelope{
		Type:    "user",
		Subtype: "",
	})

	if err == nil {
		t.Error("expected error for non-system/init message during init")
	}
}

func TestStateTransitions(t *testing.T) {
	srv := NewServer("task", "", 5*time.Minute, false)
	if srv.state != StateWaiting {
		t.Errorf("initial state should be WAITING, got %s", srv.state)
	}

	// Simulate connection → INIT
	srv.state = StateInit

	// Handle system/init → RUNNING
	responses, err := srv.handleMessage(&Envelope{
		Type:      "system",
		Subtype:   "init",
		SessionID: "sess-123",
		Model:     "claude-sonnet-4-5-20250929",
	})
	if err != nil {
		t.Fatalf("init: %v", err)
	}
	if srv.state != StateRunning {
		t.Errorf("expected RUNNING after init, got %s", srv.state)
	}
	if len(responses) != 1 {
		t.Fatalf("expected 1 response (user message), got %d", len(responses))
	}

	// Verify user message format
	var userMsg map[string]any
	if err := json.Unmarshal(responses[0], &userMsg); err != nil {
		t.Fatalf("unmarshal user message: %v", err)
	}
	if userMsg["type"] != "user" {
		t.Errorf("expected type=user, got %v", userMsg["type"])
	}
	if userMsg["session_id"] != "sess-123" {
		t.Errorf("expected session_id=sess-123, got %v", userMsg["session_id"])
	}

	// Handle result → DONE
	isError := false
	_, err = srv.handleMessage(&Envelope{
		Type:         "result",
		Subtype:      "success",
		IsError:      &isError,
		Result:       "done",
		NumTurns:     5,
		DurationMs:   30000,
		TotalCostUSD: 0.02,
		Usage:        &ResultUsage{InputTokens: 100, OutputTokens: 50},
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

func TestIgnoresInfoMessages(t *testing.T) {
	srv := NewServer("task", "", 5*time.Minute, true)
	srv.state = StateRunning

	// These should all be silently consumed
	infoTypes := []string{"keep_alive", "stream_event", "tool_progress", "tool_use_summary"}
	for _, msgType := range infoTypes {
		responses, err := srv.handleMessage(&Envelope{Type: msgType})
		if err != nil {
			t.Errorf("unexpected error for %s: %v", msgType, err)
		}
		if len(responses) != 0 {
			t.Errorf("expected no responses for %s, got %d", msgType, len(responses))
		}
	}
}
