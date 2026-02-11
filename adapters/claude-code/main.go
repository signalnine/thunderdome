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
	StateWaiting      State = iota // Listening, no connection yet
	StateInitializing              // Connected, awaiting initialize handshake
	StateRunning                   // Task prompt sent, Claude Code is working
	StateDone                      // Result received, ready to exit
)

func (s State) String() string {
	switch s {
	case StateWaiting:
		return "WAITING"
	case StateInitializing:
		return "INITIALIZING"
	case StateRunning:
		return "RUNNING"
	case StateDone:
		return "DONE"
	default:
		return fmt.Sprintf("UNKNOWN(%d)", int(s))
	}
}

// Protocol message types (NDJSON over WebSocket).

type Message struct {
	Type    string          `json:"type"`
	Subtype string          `json:"subtype,omitempty"`
	Content json.RawMessage `json:"content,omitempty"`

	// Fields for control_request/response
	SupportedAPIVersions []string        `json:"supportedApiVersions,omitempty"`
	APIVersion           string          `json:"apiVersion,omitempty"`
	PermissionMode       string          `json:"permissionMode,omitempty"`
	ToolName             string          `json:"toolName,omitempty"`
	Input                json.RawMessage `json:"input,omitempty"`
	Allowed              *bool           `json:"allowed,omitempty"`

	// Fields for result
	Result string `json:"result,omitempty"`
	Usage  *Usage `json:"usage,omitempty"`

	// Fields for user message
	UserType string `json:"userType,omitempty"`
}

type Usage struct {
	InputTokens          int `json:"input_tokens"`
	OutputTokens         int `json:"output_tokens"`
	CacheReadTokens      int `json:"cache_read_input_tokens,omitempty"`
	CacheCreationTokens  int `json:"cache_creation_input_tokens,omitempty"`
}

type Metrics struct {
	InputTokens         int      `json:"input_tokens"`
	OutputTokens        int      `json:"output_tokens"`
	CacheReadTokens     int      `json:"cache_read_tokens,omitempty"`
	CacheCreationTokens int      `json:"cache_creation_tokens,omitempty"`
	Turns               int      `json:"turns"`
	ToolsUsed           []string `json:"tools_used"`
}

type Server struct {
	state       State
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
	s.state = StateInitializing
	s.logf("[STATE] → %s", s.state)

	readTimeout := s.idleTimeout

	for s.state != StateDone {
		readCtx, cancel := context.WithTimeout(ctx, readTimeout)
		_, data, err := conn.Read(readCtx)
		cancel()
		if err != nil {
			return fmt.Errorf("read in state %s: %w", s.state, err)
		}

		var msg Message
		if err := json.Unmarshal(data, &msg); err != nil {
			s.logf("[RECV] malformed JSON: %s", string(data))
			continue
		}

		s.logf("[RECV] type=%s subtype=%s state=%s", msg.Type, msg.Subtype, s.state)

		response, err := s.handleMessage(&msg)
		if err != nil {
			return fmt.Errorf("handle message in state %s: %w", s.state, err)
		}

		for _, resp := range response {
			respData, err := json.Marshal(resp)
			if err != nil {
				return fmt.Errorf("marshal response: %w", err)
			}
			s.logf("[SEND] type=%s subtype=%s", resp.Type, resp.Subtype)
			if err := conn.Write(ctx, websocket.MessageText, respData); err != nil {
				return fmt.Errorf("write response: %w", err)
			}
		}
	}

	return s.writeMetrics()
}

func (s *Server) handleMessage(msg *Message) ([]Message, error) {
	switch s.state {
	case StateInitializing:
		return s.handleInitializing(msg)
	case StateRunning:
		return s.handleRunning(msg)
	default:
		return nil, fmt.Errorf("unexpected message in state %s", s.state)
	}
}

func (s *Server) handleInitializing(msg *Message) ([]Message, error) {
	if msg.Type != "control_request" || msg.Subtype != "initialize" {
		return nil, fmt.Errorf("expected initialize, got type=%s subtype=%s", msg.Type, msg.Subtype)
	}

	// Respond with initialize + send task prompt
	responses := []Message{
		{
			Type:           "control_response",
			Subtype:        "initialize",
			APIVersion:     "1",
			PermissionMode: "default",
		},
		{
			Type:    "user",
			Content: mustMarshal([]map[string]string{{"type": "text", "text": s.taskPrompt}}),
		},
	}

	s.state = StateRunning
	s.logf("[STATE] → %s", s.state)
	return responses, nil
}

func (s *Server) handleRunning(msg *Message) ([]Message, error) {
	switch msg.Type {
	case "control_request":
		return s.handleControlRequest(msg)
	case "assistant":
		s.metrics.Turns++
		return nil, nil
	case "result":
		return s.handleResult(msg)
	default:
		// Ignore unknown message types
		s.logf("[WARN] unknown message type: %s", msg.Type)
		return nil, nil
	}
}

func (s *Server) handleControlRequest(msg *Message) ([]Message, error) {
	switch msg.Subtype {
	case "can_use_tool":
		if msg.ToolName != "" && !s.toolsSeen[msg.ToolName] {
			s.toolsSeen[msg.ToolName] = true
			s.metrics.ToolsUsed = append(s.metrics.ToolsUsed, msg.ToolName)
		}
		allowed := true
		return []Message{{
			Type:    "control_response",
			Subtype: "can_use_tool",
			Allowed: &allowed,
		}}, nil
	default:
		s.logf("[WARN] unknown control_request subtype: %s", msg.Subtype)
		return nil, nil
	}
}

func (s *Server) handleResult(msg *Message) ([]Message, error) {
	if msg.Usage != nil {
		s.metrics.InputTokens += msg.Usage.InputTokens
		s.metrics.OutputTokens += msg.Usage.OutputTokens
		s.metrics.CacheReadTokens += msg.Usage.CacheReadTokens
		s.metrics.CacheCreationTokens += msg.Usage.CacheCreationTokens
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

func mustMarshal(v any) json.RawMessage {
	data, err := json.Marshal(v)
	if err != nil {
		panic(err)
	}
	return data
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
			// InsecureSkipVerify disables origin checking — safe because this
			// server only accepts connections from localhost inside a container.
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
