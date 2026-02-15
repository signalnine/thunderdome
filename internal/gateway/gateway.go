package gateway

import (
	"context"
	"encoding/json"
	"fmt"
	"net"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"time"
)

type Gateway struct {
	Port         int
	UsageLogPath string
	cmd          *exec.Cmd
	logFile      *os.File
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

	os.MkdirAll(opts.LogDir, 0o755)
	usageLogPath := fmt.Sprintf("%s/proxy-usage-%d.jsonl", opts.LogDir, port)

	// Find the proxy script next to this Go source file (embedded in repo).
	proxyScript, err := findProxyScript()
	if err != nil {
		return nil, fmt.Errorf("finding proxy script: %w", err)
	}

	serverLogPath := fmt.Sprintf("%s/proxy-server-%d.log", opts.LogDir, port)
	logFile, err := os.Create(serverLogPath)
	if err != nil {
		return nil, fmt.Errorf("creating log file: %w", err)
	}

	cmd := exec.CommandContext(ctx, "python3", proxyScript,
		"--port", fmt.Sprintf("%d", port),
		"--log", usageLogPath,
	)
	cmd.Stdout = logFile
	cmd.Stderr = logFile

	if err := cmd.Start(); err != nil {
		logFile.Close()
		return nil, fmt.Errorf("starting proxy: %w", err)
	}

	if err := waitForPort(port, 15*time.Second); err != nil {
		cmd.Process.Kill()
		logFile.Close()
		return nil, fmt.Errorf("proxy did not start: %w", err)
	}

	return &Gateway{Port: port, cmd: cmd, logFile: logFile, UsageLogPath: usageLogPath}, nil
}

func findProxyScript() (string, error) {
	// Look relative to the working directory (repo root).
	candidates := []string{
		"internal/gateway/proxy.py",
	}
	for _, c := range candidates {
		if _, err := os.Stat(c); err == nil {
			abs, _ := filepath.Abs(c)
			return abs, nil
		}
	}
	return "", fmt.Errorf("proxy.py not found in %v", candidates)
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
	Provider                string  `json:"provider"`
	Model                   string  `json:"model"`
	InputTokens             int     `json:"input_tokens"`
	OutputTokens            int     `json:"output_tokens"`
	CacheCreationTokens     int     `json:"cache_creation_input_tokens"`
	CacheReadTokens         int     `json:"cache_read_input_tokens"`
	Timestamp               float64 `json:"timestamp"`
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

// EstimateCost calculates approximate USD cost from usage records using
// Anthropic's published per-token pricing (as of 2025-05).
func EstimateCost(records []UsageRecord) float64 {
	var total float64
	for _, r := range records {
		inputPrice, outputPrice, cacheWritePrice, cacheReadPrice := modelPricing(r.Model)
		total += float64(r.InputTokens) * inputPrice / 1e6
		total += float64(r.OutputTokens) * outputPrice / 1e6
		total += float64(r.CacheCreationTokens) * cacheWritePrice / 1e6
		total += float64(r.CacheReadTokens) * cacheReadPrice / 1e6
	}
	return total
}

// modelPricing returns per-million-token prices: (input, output, cacheWrite, cacheRead).
func modelPricing(model string) (float64, float64, float64, float64) {
	switch {
	case strings.Contains(model, "opus"):
		return 15.0, 75.0, 18.75, 1.50
	case strings.Contains(model, "sonnet"):
		return 3.0, 15.0, 3.75, 0.30
	case strings.Contains(model, "haiku"):
		return 0.80, 4.0, 1.0, 0.08
	default:
		// Default to Sonnet pricing
		return 3.0, 15.0, 3.75, 0.30
	}
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

// ParseEnvFile reads a .env file and returns a map of key=value pairs.
func ParseEnvFile(path string) (map[string]string, error) {
	vars, err := parseEnvFile(path)
	if err != nil {
		return nil, err
	}
	m := make(map[string]string, len(vars))
	for _, v := range vars {
		if idx := strings.IndexByte(v, '='); idx >= 0 {
			m[v[:idx]] = v[idx+1:]
		}
	}
	return m, nil
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
