package main

import (
	"context"
	"encoding/json"
	"flag"
	"fmt"
	"log"
	"net"
	"net/http"
	"os"
	"time"

	"nhooyr.io/websocket"
)

// State represents the server's protocol state.
type State int

const (
	StateWaiting State = iota // Listening, no connection yet
	StateInit                 // Connected, awaiting system/init from CLI
	StateRunning              // Task prompt sent, Claude Code is working
	StateDone                 // Result received, ready to exit
)

func (s State) String() string {
	switch s {
	case StateWaiting:
		return "WAITING"
	case StateInit:
		return "INIT"
	case StateRunning:
		return "RUNNING"
	case StateDone:
		return "DONE"
	default:
		return fmt.Sprintf("UNKNOWN(%d)", int(s))
	}
}

// --- Protocol message types (NDJSON over WebSocket) ---
// These match the Claude Code SDK WebSocket protocol.

// Envelope is the top-level message read from the wire.
// Different message types use different subsets of fields.
type Envelope struct {
	Type    string `json:"type"`
	Subtype string `json:"subtype,omitempty"`

	// system/init fields (CLI → Server)
	SessionID        string   `json:"session_id,omitempty"`
	UUID             string   `json:"uuid,omitempty"`
	Cwd              string   `json:"cwd,omitempty"`
	Tools            []string `json:"tools,omitempty"`
	Model            string   `json:"model,omitempty"`
	PermissionMode   string   `json:"permissionMode,omitempty"`
	ClaudeCodeVersion string  `json:"claude_code_version,omitempty"`

	// control_request fields (CLI → Server)
	RequestID string          `json:"request_id,omitempty"`
	Request   json.RawMessage `json:"request,omitempty"`

	// control_response fields (Server → CLI)
	Response json.RawMessage `json:"response,omitempty"`

	// user message fields (Server → CLI)
	Message         json.RawMessage `json:"message,omitempty"`
	ParentToolUseID *string         `json:"parent_tool_use_id"` // null for top-level
	// SessionID is shared with init

	// assistant message fields (CLI → Server)
	// Message, UUID, SessionID shared

	// result fields (CLI → Server)
	IsError     *bool           `json:"is_error,omitempty"`
	Result      string          `json:"result,omitempty"`
	Errors      []string        `json:"errors,omitempty"`
	DurationMs  int             `json:"duration_ms,omitempty"`
	NumTurns    int             `json:"num_turns,omitempty"`
	TotalCostUSD float64        `json:"total_cost_usd,omitempty"`
	Usage       *ResultUsage    `json:"usage,omitempty"`
}

// ControlRequestBody is the nested "request" inside a control_request envelope.
type ControlRequestBody struct {
	Subtype   string          `json:"subtype"`
	ToolName  string          `json:"tool_name,omitempty"`
	Input     json.RawMessage `json:"input,omitempty"`
	ToolUseID string          `json:"tool_use_id,omitempty"`
}

// AssistantMessage is the nested "message" inside an assistant envelope.
type AssistantMessage struct {
	ID      string          `json:"id,omitempty"`
	Type    string          `json:"type,omitempty"`
	Role    string          `json:"role"`
	Model   string          `json:"model,omitempty"`
	Content json.RawMessage `json:"content,omitempty"`
	Usage   *AssistantUsage `json:"usage,omitempty"`
}

type AssistantUsage struct {
	InputTokens              int `json:"input_tokens"`
	OutputTokens             int `json:"output_tokens"`
	CacheReadInputTokens     int `json:"cache_read_input_tokens,omitempty"`
	CacheCreationInputTokens int `json:"cache_creation_input_tokens,omitempty"`
}

type ResultUsage struct {
	InputTokens              int `json:"input_tokens"`
	OutputTokens             int `json:"output_tokens"`
	CacheReadInputTokens     int `json:"cache_read_input_tokens,omitempty"`
	CacheCreationInputTokens int `json:"cache_creation_input_tokens,omitempty"`
}

type Metrics struct {
	InputTokens         int      `json:"input_tokens"`
	OutputTokens        int      `json:"output_tokens"`
	CacheReadTokens     int      `json:"cache_read_tokens,omitempty"`
	CacheCreationTokens int      `json:"cache_creation_tokens,omitempty"`
	Turns               int      `json:"turns"`
	ToolsUsed           []string `json:"tools_used"`
	DurationMs          int      `json:"duration_ms,omitempty"`
	TotalCostUSD        float64  `json:"total_cost_usd,omitempty"`
}

type Server struct {
	state       State
	sessionID   string
	taskPrompt  string
	metricsFile string
	idleTimeout time.Duration
	debug       bool
	metrics     Metrics
	toolsSeen   map[string]bool
}

func NewServer(taskPrompt, metricsFile string, idleTimeout time.Duration, debug bool) *Server {
	return &Server{
		state:       StateWaiting,
		taskPrompt:  taskPrompt,
		metricsFile: metricsFile,
		idleTimeout: idleTimeout,
		debug:       debug,
		toolsSeen:   make(map[string]bool),
	}
}

func (s *Server) logf(format string, args ...any) {
	if s.debug {
		log.Printf(format, args...)
	}
}

func (s *Server) HandleConnection(ctx context.Context, conn *websocket.Conn) error {
	s.state = StateInit
	s.logf("[STATE] → %s", s.state)

	readTimeout := s.idleTimeout

	for s.state != StateDone {
		readCtx, cancel := context.WithTimeout(ctx, readTimeout)
		_, data, err := conn.Read(readCtx)
		cancel()
		if err != nil {
			return fmt.Errorf("read in state %s: %w", s.state, err)
		}

		var env Envelope
		if err := json.Unmarshal(data, &env); err != nil {
			s.logf("[RECV] malformed JSON: %s", string(data))
			continue
		}

		s.logf("[RECV] type=%s subtype=%s state=%s", env.Type, env.Subtype, s.state)

		responses, err := s.handleMessage(&env)
		if err != nil {
			return fmt.Errorf("handle message in state %s: %w", s.state, err)
		}

		for _, resp := range responses {
			respData, err := json.Marshal(resp)
			if err != nil {
				return fmt.Errorf("marshal response: %w", err)
			}
			s.logf("[SEND] %s", string(respData))
			if err := conn.Write(ctx, websocket.MessageText, respData); err != nil {
				return fmt.Errorf("write response: %w", err)
			}
		}
	}

	return s.writeMetrics()
}

func (s *Server) handleMessage(env *Envelope) ([]json.RawMessage, error) {
	switch s.state {
	case StateInit:
		return s.handleInit(env)
	case StateRunning:
		return s.handleRunning(env)
	default:
		return nil, fmt.Errorf("unexpected message in state %s", s.state)
	}
}

// handleInit handles the system/init message from the CLI and sends the task prompt.
func (s *Server) handleInit(env *Envelope) ([]json.RawMessage, error) {
	if env.Type != "system" || env.Subtype != "init" {
		return nil, fmt.Errorf("expected system/init, got type=%s subtype=%s", env.Type, env.Subtype)
	}

	s.sessionID = env.SessionID
	s.logf("[INIT] session=%s model=%s version=%s tools=%v",
		env.SessionID, env.Model, env.ClaudeCodeVersion, env.Tools)

	// Send the task prompt as a user message
	userMsg := map[string]any{
		"type": "user",
		"message": map[string]any{
			"role":    "user",
			"content": s.taskPrompt,
		},
		"parent_tool_use_id": nil,
		"session_id":         s.sessionID,
	}
	data, err := json.Marshal(userMsg)
	if err != nil {
		return nil, fmt.Errorf("marshal user message: %w", err)
	}

	s.state = StateRunning
	s.logf("[STATE] → %s", s.state)
	return []json.RawMessage{data}, nil
}

// handleRunning processes messages while Claude Code is working.
func (s *Server) handleRunning(env *Envelope) ([]json.RawMessage, error) {
	switch env.Type {
	case "control_request":
		return s.handleControlRequest(env)
	case "assistant":
		return s.handleAssistant(env)
	case "result":
		return s.handleResult(env)
	case "keep_alive", "stream_event", "tool_progress", "tool_use_summary", "system", "auth_status":
		// Silently consume informational messages
		return nil, nil
	default:
		s.logf("[WARN] unknown message type: %s", env.Type)
		return nil, nil
	}
}

// handleControlRequest processes tool permission requests.
func (s *Server) handleControlRequest(env *Envelope) ([]json.RawMessage, error) {
	var reqBody ControlRequestBody
	if err := json.Unmarshal(env.Request, &reqBody); err != nil {
		return nil, fmt.Errorf("unmarshal control request body: %w", err)
	}

	switch reqBody.Subtype {
	case "can_use_tool":
		if reqBody.ToolName != "" && !s.toolsSeen[reqBody.ToolName] {
			s.toolsSeen[reqBody.ToolName] = true
			s.metrics.ToolsUsed = append(s.metrics.ToolsUsed, reqBody.ToolName)
		}

		// Auto-approve all tools with the original input
		resp := map[string]any{
			"type": "control_response",
			"response": map[string]any{
				"subtype":    "success",
				"request_id": env.RequestID,
				"response": map[string]any{
					"behavior":     "allow",
					"updatedInput": json.RawMessage(reqBody.Input),
				},
			},
		}
		data, err := json.Marshal(resp)
		if err != nil {
			return nil, fmt.Errorf("marshal control response: %w", err)
		}
		return []json.RawMessage{data}, nil

	default:
		s.logf("[WARN] unknown control_request subtype: %s", reqBody.Subtype)
		return nil, nil
	}
}

// handleAssistant processes assistant response messages and extracts usage.
func (s *Server) handleAssistant(env *Envelope) ([]json.RawMessage, error) {
	s.metrics.Turns++

	if env.Message != nil {
		var msg AssistantMessage
		if err := json.Unmarshal(env.Message, &msg); err == nil && msg.Usage != nil {
			s.metrics.InputTokens += msg.Usage.InputTokens
			s.metrics.OutputTokens += msg.Usage.OutputTokens
			s.metrics.CacheReadTokens += msg.Usage.CacheReadInputTokens
			s.metrics.CacheCreationTokens += msg.Usage.CacheCreationInputTokens
		}
	}

	return nil, nil
}

// handleResult processes the final result message.
func (s *Server) handleResult(env *Envelope) ([]json.RawMessage, error) {
	// Extract usage from result (cumulative totals)
	if env.Usage != nil {
		// Result usage is cumulative — use it as the authoritative total
		s.metrics.InputTokens = env.Usage.InputTokens
		s.metrics.OutputTokens = env.Usage.OutputTokens
		s.metrics.CacheReadTokens = env.Usage.CacheReadInputTokens
		s.metrics.CacheCreationTokens = env.Usage.CacheCreationInputTokens
	}

	if env.NumTurns > 0 {
		s.metrics.Turns = env.NumTurns
	}
	s.metrics.DurationMs = env.DurationMs
	s.metrics.TotalCostUSD = env.TotalCostUSD

	isError := env.IsError != nil && *env.IsError
	if isError {
		s.logf("[RESULT] error subtype=%s errors=%v", env.Subtype, env.Errors)
	} else {
		s.logf("[RESULT] success, cost=$%.4f, turns=%d", env.TotalCostUSD, env.NumTurns)
	}

	s.state = StateDone
	s.logf("[STATE] → %s", s.state)
	return nil, nil
}

func (s *Server) writeMetrics() error {
	if s.metricsFile == "" {
		return nil
	}
	data, err := json.MarshalIndent(s.metrics, "", "  ")
	if err != nil {
		return fmt.Errorf("marshal metrics: %w", err)
	}
	if err := os.WriteFile(s.metricsFile, data, 0o644); err != nil {
		return fmt.Errorf("write metrics: %w", err)
	}
	s.logf("[METRICS] written to %s", s.metricsFile)
	return nil
}

func main() {
	port := flag.Int("port", 9876, "WebSocket server port")
	taskFile := flag.String("task-file", "", "Path to task description file")
	metricsFile := flag.String("metrics-file", "", "Path to write metrics JSON")
	idleTimeout := flag.Int("idle-timeout", 10, "Minutes of silence before assuming stuck")
	debug := flag.Bool("debug", false, "Enable debug logging")
	flag.Parse()

	if *taskFile == "" {
		log.Fatal("--task-file is required")
	}

	taskData, err := os.ReadFile(*taskFile)
	if err != nil {
		log.Fatalf("reading task file: %v", err)
	}

	srv := NewServer(string(taskData), *metricsFile, time.Duration(*idleTimeout)*time.Minute, *debug)

	listener, err := net.Listen("tcp", fmt.Sprintf("localhost:%d", *port))
	if err != nil {
		log.Fatalf("listen: %v", err)
	}
	log.Printf("ws-server listening on localhost:%d", *port)

	connCh := make(chan *websocket.Conn, 1)
	errCh := make(chan error, 1)

	httpServer := &http.Server{
		Handler: http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			conn, err := websocket.Accept(w, r, &websocket.AcceptOptions{
				InsecureSkipVerify: true,
			})
			if err != nil {
				log.Printf("accept error: %v", err)
				return
			}
			select {
			case connCh <- conn:
			default:
				conn.Close(websocket.StatusPolicyViolation, "only one connection allowed")
			}
		}),
	}

	go func() {
		if err := httpServer.Serve(listener); err != nil && err != http.ErrServerClosed {
			errCh <- err
		}
	}()
	defer httpServer.Close()

	// Wait for single connection or server error
	var conn *websocket.Conn
	select {
	case conn = <-connCh:
	case err := <-errCh:
		log.Fatalf("http server failed: %v", err)
	}

	ctx := context.Background()
	if err := srv.HandleConnection(ctx, conn); err != nil {
		log.Printf("connection error: %v", err)
		conn.Close(websocket.StatusInternalError, err.Error())
		os.Exit(1)
	}

	conn.Close(websocket.StatusNormalClosure, "done")
	httpServer.Close()
}
