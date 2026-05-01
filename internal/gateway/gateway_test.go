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
