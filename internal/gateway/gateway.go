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
	"sync"
	"syscall"
	"time"

	"github.com/signalnine/thunderdome/internal/pricing"
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
		// Graceful: SIGTERM first so any partially-started proxy can flush;
		// fall back to SIGKILL if it doesn't exit promptly.
		_ = cmd.Process.Signal(syscall.SIGTERM)
		done := make(chan error, 1)
		go func() { done <- cmd.Wait() }()
		select {
		case <-done:
		case <-time.After(2 * time.Second):
			_ = cmd.Process.Kill()
			<-done
		}
		logFile.Close()
		return nil, fmt.Errorf("proxy did not start: %w", err)
	}

	return &Gateway{Port: port, cmd: cmd, logFile: logFile, UsageLogPath: usageLogPath}, nil
}

// proxyScriptSearchDirsOverride lets tests inject extra search roots.
var proxyScriptSearchDirsOverride []string

// SetProxyScriptSearchDirsForTest lets tests inject the search roots used by
// findProxyScript. Pass nil to clear.
func SetProxyScriptSearchDirsForTest(dirs []string) {
	proxyScriptSearchDirsOverride = dirs
}

// FindProxyScriptForTest exposes findProxyScript to tests in other packages.
func FindProxyScriptForTest() (string, error) {
	return findProxyScript()
}

func findProxyScript() (string, error) {
	const rel = "internal/gateway/proxy.py"

	var roots []string
	roots = append(roots, proxyScriptSearchDirsOverride...)

	// 1. Walk up from the binary's directory looking for the repo layout.
	if exe, err := os.Executable(); err == nil {
		if resolved, err := filepath.EvalSymlinks(exe); err == nil {
			exe = resolved
		}
		roots = append(roots, exe) // walkUp will Dir() this
	}

	// 2. Fall back to cwd (preserves the original behavior when running
	// the binary from the repo root during local dev).
	if cwd, err := os.Getwd(); err == nil {
		roots = append(roots, cwd)
	}

	tried := make([]string, 0, len(roots))
	for _, root := range roots {
		// Allow either a directory or a file -- if it's a file, start at its
		// parent. Walk up until we hit the filesystem root.
		dir := root
		if info, err := os.Stat(dir); err == nil && !info.IsDir() {
			dir = filepath.Dir(dir)
		}
		for {
			candidate := filepath.Join(dir, rel)
			tried = append(tried, candidate)
			if _, err := os.Stat(candidate); err == nil {
				abs, _ := filepath.Abs(candidate)
				return abs, nil
			}
			parent := filepath.Dir(dir)
			if parent == dir {
				break
			}
			dir = parent
		}
	}
	return "", fmt.Errorf("proxy.py not found (searched %v)", tried)
}

func (g *Gateway) Stop() error {
	if g.cmd == nil || g.cmd.Process == nil {
		if g.logFile != nil {
			g.logFile.Close()
		}
		return nil
	}
	// Graceful: SIGTERM, wait up to 5s for proxy.py's signal handler to
	// flush its usage log, then escalate to SIGKILL.
	_ = g.cmd.Process.Signal(syscall.SIGTERM)
	done := make(chan error, 1)
	go func() { done <- g.cmd.Wait() }()
	select {
	case <-done:
	case <-time.After(5 * time.Second):
		_ = g.cmd.Process.Kill()
		<-done
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

// ParseUsageLogs reads a proxy usage JSONL log. It returns parsed records,
// the count of malformed JSON lines that were skipped, and any read error.
// A final line lacking a trailing newline is treated as a possibly-truncated
// write from a still-running proxy and is NOT counted as malformed; every
// other unmarshal failure is. Callers can use the count to distinguish a
// transient truncation from persistent proxy/version corruption.
func ParseUsageLogs(logPath string) ([]UsageRecord, int, error) {
	data, err := os.ReadFile(logPath)
	if err != nil {
		return nil, 0, fmt.Errorf("reading gateway log: %w", err)
	}
	lines := splitLines(data)
	lastUnterminated := len(data) > 0 && data[len(data)-1] != '\n'
	var records []UsageRecord
	var malformed int
	for i, line := range lines {
		if len(line) == 0 {
			continue
		}
		var rec UsageRecord
		if err := json.Unmarshal(line, &rec); err != nil {
			if i == len(lines)-1 && lastUnterminated {
				continue
			}
			malformed++
			continue
		}
		if rec.Model != "" {
			records = append(records, rec)
		}
	}
	return records, malformed, nil
}

// SliceUsageLog reads srcPath as a JSONL usage log and writes lines whose
// records have start <= timestamp <= end into dstPath. Lines that don't
// parse are skipped (matches ParseUsageLogs semantics). A record with
// Timestamp == 0 is treated as undated and written unconditionally so that
// older proxy versions or test fixtures without timestamps still produce
// some output. Returns the number of records written. If srcPath does not
// exist or is empty, dstPath is created as an empty file and (0, nil) is
// returned. Used by RunTrial to carve a shared gateway log into per-trial
// slices that enrichCosts can read.
func SliceUsageLog(srcPath, dstPath string, start, end float64) (int, error) {
	data, err := os.ReadFile(srcPath)
	if err != nil {
		if os.IsNotExist(err) {
			return 0, os.WriteFile(dstPath, nil, 0o644)
		}
		return 0, fmt.Errorf("reading source usage log: %w", err)
	}

	lines := splitLines(data)
	lastUnterminated := len(data) > 0 && data[len(data)-1] != '\n'

	var out []byte
	var written int
	for i, line := range lines {
		if len(line) == 0 {
			continue
		}
		var rec UsageRecord
		if err := json.Unmarshal(line, &rec); err != nil {
			if i == len(lines)-1 && lastUnterminated {
				continue
			}
			continue
		}
		if rec.Model == "" {
			continue
		}
		if rec.Timestamp != 0 && (rec.Timestamp < start || rec.Timestamp > end) {
			continue
		}
		out = append(out, line...)
		out = append(out, '\n')
		written++
	}

	if err := os.WriteFile(dstPath, out, 0o644); err != nil {
		return 0, fmt.Errorf("writing trial usage log: %w", err)
	}
	return written, nil
}

func TotalUsage(records []UsageRecord) (inputTokens, outputTokens int) {
	for _, r := range records {
		inputTokens += r.InputTokens
		outputTokens += r.OutputTokens
	}
	return
}

// TotalTokens sums all four token types (input, output, cache creation, cache
// read) across records. This matches the adapter-metrics fallback definition
// in trial.go so MeanTokens is comparable across trials regardless of which
// usage source captured the data. With Anthropic prompt caching, cache reads
// commonly dominate the sum -- omitting them understates real token volume by
// 10-100x.
func TotalTokens(records []UsageRecord) int {
	var total int
	for _, r := range records {
		total += r.InputTokens + r.OutputTokens + r.CacheCreationTokens + r.CacheReadTokens
	}
	return total
}

var (
	pricingMu     sync.RWMutex
	pricingTable  *pricing.Table
	pricingLoaded bool
)

// LoadPricing loads pricing data from the given pricing.yaml. Pass an empty
// path to clear the cached table (used by tests). Subsequent calls to
// EstimateCost will use this table. Calling EstimateCost without a prior
// LoadPricing causes one lazy lookup attempt; if pricing.yaml can't be found
// EstimateCost returns 0.
func LoadPricing(path string) error {
	pricingMu.Lock()
	defer pricingMu.Unlock()
	if path == "" {
		pricingTable = nil
		pricingLoaded = false
		return nil
	}
	t, err := pricing.Load(path)
	if err != nil {
		return err
	}
	pricingTable = t
	pricingLoaded = true
	return nil
}

func getPricingTable() *pricing.Table {
	pricingMu.RLock()
	if pricingLoaded {
		t := pricingTable
		pricingMu.RUnlock()
		return t
	}
	pricingMu.RUnlock()

	pricingMu.Lock()
	defer pricingMu.Unlock()
	if pricingLoaded {
		return pricingTable
	}
	pricingLoaded = true
	if path, err := findPricingFile(); err == nil {
		if t, err := pricing.Load(path); err == nil {
			pricingTable = t
		}
	}
	return pricingTable
}

// FindPricingFile is the exported form of findPricingFile so callers outside
// this package (cmd/run, cmd/report) can locate pricing.yaml without
// duplicating the search heuristic.
func FindPricingFile() (string, error) {
	return findPricingFile()
}

func findPricingFile() (string, error) {
	const rel = "pricing.yaml"
	var roots []string
	if exe, err := os.Executable(); err == nil {
		if resolved, err := filepath.EvalSymlinks(exe); err == nil {
			exe = resolved
		}
		roots = append(roots, filepath.Dir(exe))
	}
	if cwd, err := os.Getwd(); err == nil {
		roots = append(roots, cwd)
	}
	for _, root := range roots {
		dir := root
		for {
			candidate := filepath.Join(dir, rel)
			if _, err := os.Stat(candidate); err == nil {
				return candidate, nil
			}
			parent := filepath.Dir(dir)
			if parent == dir {
				break
			}
			dir = parent
		}
	}
	return "", fmt.Errorf("pricing.yaml not found")
}

// EstimateCost calculates approximate USD cost from usage records using
// per-token prices loaded from pricing.yaml (the canonical source). Returns
// 0 if pricing.yaml can't be found or a record's provider/model isn't listed.
func EstimateCost(records []UsageRecord) float64 {
	t := getPricingTable()
	if t == nil {
		return 0
	}
	var total float64
	for _, r := range records {
		total += t.Cost(r.Provider, r.Model, r.InputTokens, r.OutputTokens, r.CacheCreationTokens, r.CacheReadTokens)
	}
	return total
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
