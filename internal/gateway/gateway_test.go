package gateway_test

import (
	"fmt"
	"net"
	"os"
	"path/filepath"
	"testing"

	"github.com/signalnine/thunderdome/internal/gateway"
)

func TestFindFreePort(t *testing.T) {
	port, err := gateway.FindFreePort()
	if err != nil {
		t.Fatalf("FindFreePort: %v", err)
	}
	if port < 1024 || port > 65535 {
		t.Errorf("port out of range: %d", port)
	}
	ln, err := net.Listen("tcp", fmt.Sprintf(":%d", port))
	if err != nil {
		t.Errorf("port %d not free: %v", port, err)
	} else {
		ln.Close()
	}
}

func TestGatewayURL(t *testing.T) {
	gw := &gateway.Gateway{Port: 8080}
	if gw.URL() != "http://localhost:8080" {
		t.Errorf("got %q, want %q", gw.URL(), "http://localhost:8080")
	}
}

func TestParseUsageLogs(t *testing.T) {
	dir := t.TempDir()
	logContent := `{"model":"claude-opus-4-6","provider":"anthropic","input_tokens":4200,"output_tokens":1800}
{"model":"codex-max","provider":"openai","input_tokens":1000,"output_tokens":500}
some non-json startup noise
`
	logPath := filepath.Join(dir, "proxy-log.jsonl")
	os.WriteFile(logPath, []byte(logContent), 0o644)
	records, err := gateway.ParseUsageLogs(logPath)
	if err != nil {
		t.Fatalf("ParseUsageLogs: %v", err)
	}
	if len(records) != 2 {
		t.Fatalf("expected 2 records, got %d", len(records))
	}
	inTok, outTok := gateway.TotalUsage(records)
	if inTok != 5200 {
		t.Errorf("input tokens: got %d, want 5200", inTok)
	}
	if outTok != 2300 {
		t.Errorf("output tokens: got %d, want 2300", outTok)
	}
}
