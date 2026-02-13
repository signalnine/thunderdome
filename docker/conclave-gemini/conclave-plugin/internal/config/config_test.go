package config

import (
	"os"
	"path/filepath"
	"testing"
)

func TestLoadAPIKeys(t *testing.T) {
	tests := []struct {
		name     string
		envVars  map[string]string
		wantKeys int
	}{
		{"no keys", nil, 0},
		{"anthropic only", map[string]string{"ANTHROPIC_API_KEY": "sk-test"}, 1},
		{"all three", map[string]string{
			"ANTHROPIC_API_KEY": "sk-test",
			"GEMINI_API_KEY":    "gm-test",
			"OPENAI_API_KEY":    "op-test",
		}, 3},
		{"gemini fallback to google", map[string]string{
			"GOOGLE_API_KEY": "gk-test",
		}, 1},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			// Point HOME to empty temp dir so loadDotEnv() is a no-op
			t.Setenv("HOME", t.TempDir())
			for _, k := range []string{"ANTHROPIC_API_KEY", "GEMINI_API_KEY", "GOOGLE_API_KEY", "OPENAI_API_KEY"} {
				t.Setenv(k, "")
			}
			for k, v := range tt.envVars {
				t.Setenv(k, v)
			}
			cfg := Load()
			got := 0
			if cfg.AnthropicAPIKey != "" {
				got++
			}
			if cfg.GeminiAPIKey != "" {
				got++
			}
			if cfg.OpenAIAPIKey != "" {
				got++
			}
			if got != tt.wantKeys {
				t.Errorf("got %d keys, want %d", got, tt.wantKeys)
			}
		})
	}
}

func TestLoadDotEnv(t *testing.T) {
	dir := t.TempDir()
	envFile := filepath.Join(dir, ".env")
	os.WriteFile(envFile, []byte("ANTHROPIC_API_KEY=from-dotenv\n"), 0644)

	t.Setenv("ANTHROPIC_API_KEY", "")
	t.Setenv("HOME", dir)

	cfg := Load()
	if cfg.AnthropicAPIKey != "from-dotenv" {
		t.Errorf("got %q, want 'from-dotenv'", cfg.AnthropicAPIKey)
	}
}

func TestLoadDotEnvExportPrefix(t *testing.T) {
	dir := t.TempDir()
	envFile := filepath.Join(dir, ".env")
	os.WriteFile(envFile, []byte("export ANTHROPIC_API_KEY=from-dotenv-export\nexport GEMINI_API_KEY=\"quoted-value\"\n"), 0644)

	t.Setenv("ANTHROPIC_API_KEY", "")
	t.Setenv("GEMINI_API_KEY", "")
	t.Setenv("GOOGLE_API_KEY", "")
	t.Setenv("HOME", dir)

	cfg := Load()
	if cfg.AnthropicAPIKey != "from-dotenv-export" {
		t.Errorf("AnthropicAPIKey got %q, want 'from-dotenv-export'", cfg.AnthropicAPIKey)
	}
	if cfg.GeminiAPIKey != "quoted-value" {
		t.Errorf("GeminiAPIKey got %q, want 'quoted-value'", cfg.GeminiAPIKey)
	}
}

func TestLoadDotEnvLocalOverridesHome(t *testing.T) {
	// Set up ~/.env with one value
	homeDir := t.TempDir()
	os.WriteFile(filepath.Join(homeDir, ".env"), []byte("ANTHROPIC_API_KEY=from-home\nGEMINI_API_KEY=home-only\n"), 0644)

	// Set up ./.env with an override for one key
	localDir := t.TempDir()
	os.WriteFile(filepath.Join(localDir, ".env"), []byte("ANTHROPIC_API_KEY=from-local\n"), 0644)

	t.Setenv("ANTHROPIC_API_KEY", "")
	t.Setenv("GEMINI_API_KEY", "")
	t.Setenv("GOOGLE_API_KEY", "")
	t.Setenv("HOME", homeDir)

	// Change to the local dir so ./.env is found
	origDir, _ := os.Getwd()
	os.Chdir(localDir)
	defer os.Chdir(origDir)

	cfg := Load()
	if cfg.AnthropicAPIKey != "from-local" {
		t.Errorf("AnthropicAPIKey got %q, want 'from-local' (local .env should win)", cfg.AnthropicAPIKey)
	}
	if cfg.GeminiAPIKey != "home-only" {
		t.Errorf("GeminiAPIKey got %q, want 'home-only' (should fall through from ~/.env)", cfg.GeminiAPIKey)
	}
}

func TestDefaults(t *testing.T) {
	// Clear env vars that might interfere
	for _, k := range []string{"ANTHROPIC_MODEL", "GEMINI_MODEL", "OPENAI_MODEL", "CONSENSUS_STAGE1_TIMEOUT"} {
		t.Setenv(k, "")
	}
	cfg := Load()
	if cfg.AnthropicModel != "claude-opus-4-5-20251101" {
		t.Errorf("AnthropicModel = %q", cfg.AnthropicModel)
	}
	if cfg.GeminiModel != "gemini-3-pro-preview" {
		t.Errorf("GeminiModel = %q", cfg.GeminiModel)
	}
	if cfg.OpenAIModel != "gpt-5.1-codex-max" {
		t.Errorf("OpenAIModel = %q", cfg.OpenAIModel)
	}
	if cfg.Stage1Timeout != 60 {
		t.Errorf("Stage1Timeout = %d", cfg.Stage1Timeout)
	}
}
