package gateway_test

import (
	"fmt"
	"net"
	"os"
	"path/filepath"
	"reflect"
	"strings"
	"testing"

	"github.com/signalnine/thunderdome/internal/gateway"
)

func TestStartOptsHasNoDeadFields(t *testing.T) {
	v := reflect.TypeOf(gateway.StartOpts{})
	for i := 0; i < v.NumField(); i++ {
		switch v.Field(i).Name {
		case "BudgetUSD", "SecretsEnvFile":
			t.Errorf("StartOpts still has dead field %s", v.Field(i).Name)
		}
	}
}

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
	records, malformed, err := gateway.ParseUsageLogs(logPath)
	if err != nil {
		t.Fatalf("ParseUsageLogs: %v", err)
	}
	if len(records) != 2 {
		t.Fatalf("expected 2 records, got %d", len(records))
	}
	if malformed != 1 {
		t.Errorf("malformed: got %d, want 1", malformed)
	}
	inTok, outTok := gateway.TotalUsage(records)
	if inTok != 5200 {
		t.Errorf("input tokens: got %d, want 5200", inTok)
	}
	if outTok != 2300 {
		t.Errorf("output tokens: got %d, want 2300", outTok)
	}
}

// Regression for td-16w: ParseUsageLogs must surface the count of malformed
// JSON lines so a proxy version mismatch or persistent corruption can't
// silently zero out token totals.
func TestParseUsageLogsReportsMalformedCount(t *testing.T) {
	dir := t.TempDir()
	logContent := `{"model":"claude-opus-4-6","provider":"anthropic","input_tokens":100,"output_tokens":50}
garbage line one
{"model":"codex-max","provider":"openai","input_tokens":10,"output_tokens":5}
also garbage
{"this":"is":"not":"valid"}
`
	logPath := filepath.Join(dir, "proxy-log.jsonl")
	os.WriteFile(logPath, []byte(logContent), 0o644)
	records, malformed, err := gateway.ParseUsageLogs(logPath)
	if err != nil {
		t.Fatalf("ParseUsageLogs: %v", err)
	}
	if len(records) != 2 {
		t.Errorf("records: got %d, want 2", len(records))
	}
	if malformed != 3 {
		t.Errorf("malformed: got %d, want 3", malformed)
	}
}

// Regression for td-16w: A final line lacking a trailing newline is
// considered a possibly-truncated write from a still-running proxy and
// must NOT be counted as malformed.
func TestParseUsageLogsAllowsTruncatedFinalLine(t *testing.T) {
	dir := t.TempDir()
	// Note: no trailing newline; the final JSON object is cut off mid-write.
	logContent := `{"model":"claude-opus-4-6","provider":"anthropic","input_tokens":100,"output_tokens":50}
{"model":"codex-max","provider":"open`
	logPath := filepath.Join(dir, "proxy-log.jsonl")
	os.WriteFile(logPath, []byte(logContent), 0o644)
	records, malformed, err := gateway.ParseUsageLogs(logPath)
	if err != nil {
		t.Fatalf("ParseUsageLogs: %v", err)
	}
	if len(records) != 1 {
		t.Errorf("records: got %d, want 1", len(records))
	}
	if malformed != 0 {
		t.Errorf("malformed: got %d, want 0 (truncated final line is OK)", malformed)
	}
}

// Regression for td-16w: blank lines must not be counted as malformed.
func TestParseUsageLogsIgnoresBlankLines(t *testing.T) {
	dir := t.TempDir()
	logContent := `{"model":"claude-opus-4-6","provider":"anthropic","input_tokens":100,"output_tokens":50}

{"model":"codex-max","provider":"openai","input_tokens":10,"output_tokens":5}

`
	logPath := filepath.Join(dir, "proxy-log.jsonl")
	os.WriteFile(logPath, []byte(logContent), 0o644)
	records, malformed, err := gateway.ParseUsageLogs(logPath)
	if err != nil {
		t.Fatalf("ParseUsageLogs: %v", err)
	}
	if len(records) != 2 {
		t.Errorf("records: got %d, want 2", len(records))
	}
	if malformed != 0 {
		t.Errorf("malformed: got %d, want 0", malformed)
	}
}

// TestEstimateCostUsesPricingYaml is a regression test for td-0eb.
// EstimateCost must source per-token pricing from pricing.yaml so the gateway
// path and the reporter path can't drift. Loading is exercised here via the
// test override; the production path resolves pricing.yaml the same way
// findProxyScript resolves proxy.py.
func TestEstimateCostUsesPricingYaml(t *testing.T) {
	dir := t.TempDir()
	pricingYaml := `anthropic:
  claude-opus-4-6: { input: 0.015, output: 0.075, cache_write: 0.01875, cache_read: 0.0015 }
  claude-sonnet-4-5: { input: 0.003, output: 0.015, cache_write: 0.00375, cache_read: 0.0003 }
`
	path := filepath.Join(dir, "pricing.yaml")
	if err := os.WriteFile(path, []byte(pricingYaml), 0o644); err != nil {
		t.Fatalf("write: %v", err)
	}
	if err := gateway.LoadPricing(path); err != nil {
		t.Fatalf("LoadPricing: %v", err)
	}
	t.Cleanup(func() { gateway.LoadPricing("") })

	records := []gateway.UsageRecord{
		{
			Provider:            "anthropic",
			Model:               "claude-opus-4-6",
			InputTokens:         1000,
			OutputTokens:        500,
			CacheCreationTokens: 2000,
			CacheReadTokens:     10000,
		},
	}
	got := gateway.EstimateCost(records)
	// 1000*0.015/1000 + 500*0.075/1000 + 2000*0.01875/1000 + 10000*0.0015/1000
	want := 0.015 + 0.0375 + 0.0375 + 0.015
	if got < want-0.0001 || got > want+0.0001 {
		t.Errorf("EstimateCost = %f, want %f", got, want)
	}

	// Now rewrite pricing.yaml with double the rates and reload -- EstimateCost
	// must reflect the new prices, proving the value comes from the file
	// rather than a hardcoded table.
	pricingYaml2 := `anthropic:
  claude-opus-4-6: { input: 0.030, output: 0.150, cache_write: 0.0375, cache_read: 0.003 }
`
	if err := os.WriteFile(path, []byte(pricingYaml2), 0o644); err != nil {
		t.Fatalf("rewrite: %v", err)
	}
	if err := gateway.LoadPricing(path); err != nil {
		t.Fatalf("LoadPricing reload: %v", err)
	}
	got2 := gateway.EstimateCost(records)
	if got2 < 2*want-0.0001 || got2 > 2*want+0.0001 {
		t.Errorf("after reload EstimateCost = %f, want %f", got2, 2*want)
	}
}

// TestFindProxyScriptResolvesFromBinary is a regression test for td-zsw.
// The gateway must locate proxy.py based on the binary's own filesystem
// location, not the caller's cwd. This lets `thunderdome run` work from any
// directory, including when the binary is on $PATH.
func TestFindProxyScriptResolvesFromBinary(t *testing.T) {
	dir := t.TempDir()
	scriptDir := filepath.Join(dir, "internal", "gateway")
	if err := os.MkdirAll(scriptDir, 0o755); err != nil {
		t.Fatalf("mkdir: %v", err)
	}
	scriptPath := filepath.Join(scriptDir, "proxy.py")
	if err := os.WriteFile(scriptPath, []byte("#!/usr/bin/env python3\n"), 0o644); err != nil {
		t.Fatalf("write proxy.py: %v", err)
	}

	// Pretend the binary lives in <dir>/bin/thunderdome -- proxy.py should
	// still be found by walking up to the repo root, or by the explicit
	// override.
	gateway.SetProxyScriptSearchDirsForTest([]string{dir})
	t.Cleanup(func() { gateway.SetProxyScriptSearchDirsForTest(nil) })

	// Force cwd to a directory that does NOT contain proxy.py so we know the
	// resolution didn't come from cwd.
	cwd := t.TempDir()
	prev, _ := os.Getwd()
	if err := os.Chdir(cwd); err != nil {
		t.Fatalf("chdir: %v", err)
	}
	t.Cleanup(func() { os.Chdir(prev) })

	got, err := gateway.FindProxyScriptForTest()
	if err != nil {
		t.Fatalf("FindProxyScript: %v", err)
	}
	wantAbs, _ := filepath.Abs(scriptPath)
	if got != wantAbs {
		t.Errorf("FindProxyScript = %q, want %q", got, wantAbs)
	}
}

// Regression for agentic-thunderdome-tzu: a shared gateway log must be
// sliceable by timestamp into a per-trial proxy-log.jsonl so enrichCosts
// (which reads <trialDir>/proxy-log.jsonl) sees only records from this
// trial's wall-clock window, not the entire shared log.
func TestSliceUsageLogFiltersByTimestamp(t *testing.T) {
	dir := t.TempDir()
	srcPath := filepath.Join(dir, "proxy-usage-12345.jsonl")
	dstPath := filepath.Join(dir, "trial", "proxy-log.jsonl")
	if err := os.MkdirAll(filepath.Dir(dstPath), 0o755); err != nil {
		t.Fatal(err)
	}

	// Three trials' worth of records on the same shared gateway log.
	// Trial 1: ts in [100, 110]. Trial 2 (target): ts in [200, 210].
	// Trial 3: ts in [300, 310].
	src := `{"model":"claude-opus-4-6","provider":"anthropic","input_tokens":1,"output_tokens":1,"timestamp":105}
{"model":"claude-opus-4-6","provider":"anthropic","input_tokens":2,"output_tokens":2,"timestamp":205}
{"model":"claude-opus-4-6","provider":"anthropic","input_tokens":3,"output_tokens":3,"timestamp":208}
{"model":"claude-opus-4-6","provider":"anthropic","input_tokens":4,"output_tokens":4,"timestamp":305}
`
	if err := os.WriteFile(srcPath, []byte(src), 0o644); err != nil {
		t.Fatal(err)
	}

	written, err := gateway.SliceUsageLog(srcPath, dstPath, 200, 210)
	if err != nil {
		t.Fatalf("SliceUsageLog: %v", err)
	}
	if written != 2 {
		t.Errorf("written: got %d, want 2", written)
	}

	records, malformed, err := gateway.ParseUsageLogs(dstPath)
	if err != nil {
		t.Fatalf("ParseUsageLogs: %v", err)
	}
	if malformed != 0 {
		t.Errorf("malformed: got %d, want 0", malformed)
	}
	if len(records) != 2 {
		t.Fatalf("records: got %d, want 2", len(records))
	}
	// Records 2 and 3 (timestamps 205, 208) should be present; record 1 (105)
	// and record 4 (305) must be excluded.
	for _, r := range records {
		if r.Timestamp < 200 || r.Timestamp > 210 {
			t.Errorf("record outside window: ts=%v", r.Timestamp)
		}
	}
}

// SliceUsageLog must create an empty destination when the source log does
// not exist yet (the proxy may not have written anything for a trial that
// bypassed it). Callers depend on the destination existing so the
// downstream proxy-log.jsonl read doesn't trigger an ENOENT path.
func TestSliceUsageLogMissingSource(t *testing.T) {
	dir := t.TempDir()
	dstPath := filepath.Join(dir, "proxy-log.jsonl")
	written, err := gateway.SliceUsageLog(filepath.Join(dir, "nope.jsonl"), dstPath, 0, 1)
	if err != nil {
		t.Fatalf("SliceUsageLog: %v", err)
	}
	if written != 0 {
		t.Errorf("written: got %d, want 0", written)
	}
	if _, err := os.Stat(dstPath); err != nil {
		t.Errorf("expected empty dst file to exist: %v", err)
	}
}

// Records lacking a timestamp (Timestamp == 0) are written unconditionally
// so older proxy versions and test fixtures without timestamps still produce
// some output. This keeps the existing report.enrichCosts test fixtures
// (which set no timestamp) working.
func TestSliceUsageLogPreservesUndatedRecords(t *testing.T) {
	dir := t.TempDir()
	srcPath := filepath.Join(dir, "src.jsonl")
	dstPath := filepath.Join(dir, "dst.jsonl")

	src := `{"model":"claude-opus-4-6","provider":"anthropic","input_tokens":1,"output_tokens":1}
{"model":"claude-opus-4-6","provider":"anthropic","input_tokens":2,"output_tokens":2,"timestamp":50}
`
	if err := os.WriteFile(srcPath, []byte(src), 0o644); err != nil {
		t.Fatal(err)
	}
	written, err := gateway.SliceUsageLog(srcPath, dstPath, 100, 200)
	if err != nil {
		t.Fatalf("SliceUsageLog: %v", err)
	}
	// Undated record passes; the ts=50 record is outside [100,200] and is dropped.
	if written != 1 {
		t.Errorf("written: got %d, want 1 (undated record only)", written)
	}
}

// TestTotalTokensIncludesCacheTokens is a regression test for td-6yl.
// The gateway path must report the same TotalTokens as the adapter-metrics
// fallback for equivalent usage. Both must include cache creation and read
// tokens (which under Anthropic prompt caching commonly dominate the total).
func TestTotalTokensIncludesCacheTokens(t *testing.T) {
	records := []gateway.UsageRecord{
		{
			Model:               "claude-opus-4-6",
			InputTokens:         100,
			OutputTokens:        200,
			CacheCreationTokens: 1000,
			CacheReadTokens:     5000,
		},
		{
			Model:               "claude-sonnet-4-5",
			InputTokens:         50,
			OutputTokens:        25,
			CacheCreationTokens: 0,
			CacheReadTokens:     400,
		},
	}
	got := gateway.TotalTokens(records)
	want := 100 + 200 + 1000 + 5000 + 50 + 25 + 0 + 400
	if got != want {
		t.Errorf("TotalTokens = %d, want %d", got, want)
	}
}

// TestGatewayStopSignalsTerminateBeforeKill is a source-check test that
// guards against regressions of the graceful-shutdown sequence in Stop().
// Stop must send SIGTERM (and wait) before falling back to Process.Kill()
// so proxy.py's signal handler has a chance to flush the usage log.
func TestGatewayStopSignalsTerminateBeforeKill(t *testing.T) {
	src, err := os.ReadFile("gateway.go")
	if err != nil {
		t.Fatal(err)
	}
	text := string(src)
	sigTermIdx := strings.Index(text, "syscall.SIGTERM")
	killIdx := strings.Index(text, "Process.Kill")
	if sigTermIdx < 0 {
		t.Errorf("Stop should send SIGTERM before SIGKILL")
	}
	if sigTermIdx > killIdx && killIdx > 0 {
		t.Errorf("SIGTERM should precede Process.Kill")
	}
}
