package gateway

import (
	"context"
	"encoding/json"
	"fmt"
	"net"
	"os"
	"os/exec"
	"strings"
	"time"
)

type Gateway struct {
	Port    int
	cmd     *exec.Cmd
	logFile *os.File
}

type StartOpts struct {
	SecretsEnvFile string
	LogDir         string
	BudgetUSD      float64
}

func FindFreePort() (int, error) {
	ln, err := net.Listen("tcp", ":0")
	if err != nil {
		return 0, fmt.Errorf("finding free port: %w", err)
	}
	port := ln.Addr().(*net.TCPAddr).Port
	ln.Close()
	return port, nil
}

func (g *Gateway) URL() string {
	return fmt.Sprintf("http://localhost:%d", g.Port)
}

func Start(ctx context.Context, opts *StartOpts) (*Gateway, error) {
	port, err := FindFreePort()
	if err != nil {
		return nil, err
	}

	logPath := fmt.Sprintf("%s/litellm-%d.log", opts.LogDir, port)
	os.MkdirAll(opts.LogDir, 0o755)
	logFile, err := os.Create(logPath)
	if err != nil {
		return nil, fmt.Errorf("creating log file: %w", err)
	}

	cmd := exec.CommandContext(ctx, "litellm", "--port", fmt.Sprintf("%d", port))
	cmd.Stdout = logFile
	cmd.Stderr = logFile

	cmd.Env = os.Environ()
	if opts.SecretsEnvFile != "" {
		envVars, err := parseEnvFile(opts.SecretsEnvFile)
		if err != nil {
			logFile.Close()
			return nil, fmt.Errorf("reading secrets env file: %w", err)
		}
		cmd.Env = append(cmd.Env, envVars...)
	}

	if err := cmd.Start(); err != nil {
		logFile.Close()
		return nil, fmt.Errorf("starting litellm: %w", err)
	}

	if err := waitForPort(port, 30*time.Second); err != nil {
		cmd.Process.Kill()
		logFile.Close()
		return nil, fmt.Errorf("litellm did not start: %w", err)
	}

	return &Gateway{Port: port, cmd: cmd, logFile: logFile}, nil
}

func (g *Gateway) Stop() error {
	if g.cmd != nil && g.cmd.Process != nil {
		g.cmd.Process.Kill()
		g.cmd.Wait()
	}
	if g.logFile != nil {
		g.logFile.Close()
	}
	return nil
}

type UsageRecord struct {
	Provider     string `json:"provider"`
	Model        string `json:"model"`
	InputTokens  int    `json:"input_tokens"`
	OutputTokens int    `json:"output_tokens"`
}

func ParseUsageLogs(logPath string) ([]UsageRecord, error) {
	data, err := os.ReadFile(logPath)
	if err != nil {
		return nil, fmt.Errorf("reading gateway log: %w", err)
	}
	var records []UsageRecord
	for _, line := range splitLines(data) {
		if len(line) == 0 {
			continue
		}
		var rec UsageRecord
		if err := json.Unmarshal(line, &rec); err != nil {
			continue
		}
		if rec.Model != "" {
			records = append(records, rec)
		}
	}
	return records, nil
}

func TotalUsage(records []UsageRecord) (inputTokens, outputTokens int) {
	for _, r := range records {
		inputTokens += r.InputTokens
		outputTokens += r.OutputTokens
	}
	return
}

func waitForPort(port int, timeout time.Duration) error {
	deadline := time.Now().Add(timeout)
	for time.Now().Before(deadline) {
		conn, err := net.DialTimeout("tcp", fmt.Sprintf("localhost:%d", port), time.Second)
		if err == nil {
			conn.Close()
			return nil
		}
		time.Sleep(500 * time.Millisecond)
	}
	return fmt.Errorf("port %d not ready after %s", port, timeout)
}

func parseEnvFile(path string) ([]string, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		return nil, err
	}
	var envVars []string
	for _, line := range splitLines(data) {
		s := strings.TrimSpace(string(line))
		if s == "" || s[0] == '#' {
			continue
		}
		s = strings.TrimPrefix(s, "export ")
		eqIdx := strings.IndexByte(s, '=')
		if eqIdx < 0 {
			continue
		}
		key := s[:eqIdx]
		val := s[eqIdx+1:]
		val = stripQuotes(val)
		envVars = append(envVars, key+"="+val)
	}
	return envVars, nil
}

func stripQuotes(s string) string {
	if len(s) >= 2 {
		if (s[0] == '\'' && s[len(s)-1] == '\'') || (s[0] == '"' && s[len(s)-1] == '"') {
			return s[1 : len(s)-1]
		}
	}
	return s
}

func splitLines(data []byte) [][]byte {
	var lines [][]byte
	start := 0
	for i, b := range data {
		if b == '\n' {
			lines = append(lines, data[start:i])
			start = i + 1
		}
	}
	if start < len(data) {
		lines = append(lines, data[start:])
	}
	return lines
}
