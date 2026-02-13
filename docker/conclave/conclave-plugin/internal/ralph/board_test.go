package ralph

import (
	"encoding/json"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/signalnine/conclave/internal/bus"
)

func TestReadBoardEmpty(t *testing.T) {
	dir := t.TempDir()
	entries, err := ReadBoard(dir, 20)
	if err != nil {
		t.Fatal(err)
	}
	if len(entries) != 0 {
		t.Errorf("got %d entries from empty dir, want 0", len(entries))
	}
}

func TestReadBoardMessages(t *testing.T) {
	dir := t.TempDir()
	writeBoardFile(t, dir, "board.jsonl", []bus.Envelope{
		{Type: "board.discovery", Sender: "task-1", Payload: json.RawMessage(`{"text":"found API"}`)},
		{Type: "board.warning", Sender: "task-2", Payload: json.RawMessage(`{"text":"broken dep"}`)},
		{Type: "board.discovery", Sender: "task-3", Payload: json.RawMessage(`{"text":"uses REST"}`)},
	})

	entries, err := ReadBoard(dir, 20)
	if err != nil {
		t.Fatal(err)
	}
	if len(entries) != 3 {
		t.Fatalf("got %d entries, want 3", len(entries))
	}
}

func TestReadBoardCap(t *testing.T) {
	dir := t.TempDir()
	var envs []bus.Envelope
	for i := 0; i < 30; i++ {
		envs = append(envs, bus.Envelope{
			Type:    "board.discovery",
			Sender:  "task-1",
			Payload: json.RawMessage(`{"text":"item"}`),
		})
	}
	writeBoardFile(t, dir, "board.jsonl", envs)

	entries, err := ReadBoard(dir, 10)
	if err != nil {
		t.Fatal(err)
	}
	if len(entries) != 10 {
		t.Errorf("got %d entries, want 10 (capped)", len(entries))
	}
}

func TestReadBoardWarningsAlwaysIncluded(t *testing.T) {
	dir := t.TempDir()
	var envs []bus.Envelope
	// 20 discoveries then 5 warnings
	for i := 0; i < 20; i++ {
		envs = append(envs, bus.Envelope{Type: "board.discovery", Sender: "s", Payload: json.RawMessage(`{"text":"d"}`)})
	}
	for i := 0; i < 5; i++ {
		envs = append(envs, bus.Envelope{Type: "board.warning", Sender: "s", Payload: json.RawMessage(`{"text":"w"}`)})
	}
	writeBoardFile(t, dir, "board.jsonl", envs)

	entries, err := ReadBoard(dir, 10)
	if err != nil {
		t.Fatal(err)
	}

	warnings := 0
	for _, e := range entries {
		if e.Type == "board.warning" {
			warnings++
		}
	}
	if warnings != 5 {
		t.Errorf("got %d warnings, want 5 (all warnings always included)", warnings)
	}
}

func TestFormatBoardContext(t *testing.T) {
	entries := []bus.Envelope{
		{Type: "board.discovery", Sender: "task-1", Payload: json.RawMessage(`{"text":"API uses pagination"}`)},
		{Type: "board.warning", Sender: "task-2", Payload: json.RawMessage(`{"text":"package X is broken"}`)},
	}

	md := FormatBoardContext(entries)
	if md == "" {
		t.Error("expected non-empty markdown")
	}
}

func TestReadBoardNonexistentDir(t *testing.T) {
	entries, err := ReadBoard("/nonexistent/path", 20)
	if err != nil {
		t.Fatal("should not error on nonexistent dir")
	}
	if len(entries) != 0 {
		t.Errorf("got %d entries, want 0", len(entries))
	}
}

func writeBoardFile(t *testing.T, dir, name string, envs []bus.Envelope) {
	t.Helper()
	f, err := os.Create(filepath.Join(dir, name))
	if err != nil {
		t.Fatal(err)
	}
	defer f.Close()
	enc := json.NewEncoder(f)
	for _, e := range envs {
		enc.Encode(e)
	}
}

func TestExtractBusMarkers(t *testing.T) {
	output := `Some normal output
<!-- BUS:discovery -->The API uses cursor-based pagination<!-- /BUS -->
More output here
<!-- BUS:warning -->Package X v2 has breaking changes<!-- /BUS -->
<!-- BUS:intent -->Modifying internal/auth/handler.go<!-- /BUS -->
Final output`

	markers := ExtractBusMarkers(output)
	if len(markers) != 3 {
		t.Fatalf("got %d markers, want 3", len(markers))
	}

	if markers[0].Type != "board.discovery" || markers[0].Text != "The API uses cursor-based pagination" {
		t.Errorf("marker 0 = %+v", markers[0])
	}
	if markers[1].Type != "board.warning" || markers[1].Text != "Package X v2 has breaking changes" {
		t.Errorf("marker 1 = %+v", markers[1])
	}
	if markers[2].Type != "board.intent" || markers[2].Text != "Modifying internal/auth/handler.go" {
		t.Errorf("marker 2 = %+v", markers[2])
	}
}

func TestExtractBusMarkersNone(t *testing.T) {
	markers := ExtractBusMarkers("Normal output with no markers")
	if len(markers) != 0 {
		t.Errorf("got %d markers, want 0", len(markers))
	}
}

func TestExtractBusMarkersMultiline(t *testing.T) {
	output := "<!-- BUS:discovery -->This spans\nmultiple lines<!-- /BUS -->"
	markers := ExtractBusMarkers(output)
	if len(markers) != 1 {
		t.Fatalf("got %d markers, want 1", len(markers))
	}
	if !strings.Contains(markers[0].Text, "multiple lines") {
		t.Errorf("should capture multiline content: %q", markers[0].Text)
	}
}

func TestPublishMarkers(t *testing.T) {
	dir := t.TempDir()
	b, _ := bus.NewFileBus(dir, 50*time.Millisecond, 200*time.Millisecond)
	defer b.Close()

	markers := []BusMarker{
		{Type: "board.discovery", Text: "found something"},
		{Type: "board.warning", Text: "watch out"},
	}

	err := PublishMarkers(b, "parallel.wave-0.board", "task-1", markers)
	if err != nil {
		t.Fatal(err)
	}

	// Verify messages in file
	data, _ := os.ReadFile(filepath.Join(dir, "parallel.wave-0.board.jsonl"))
	lines := strings.Split(strings.TrimSpace(string(data)), "\n")
	if len(lines) != 2 {
		t.Fatalf("got %d lines, want 2", len(lines))
	}
}
