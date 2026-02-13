package ralph

import (
	"bufio"
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"regexp"
	"strings"

	"github.com/signalnine/conclave/internal/bus"
)

// ReadBoard reads all messages from board JSONL files in a directory.
// Returns at most maxMessages entries, but always includes all warnings.
func ReadBoard(dir string, maxMessages int) ([]bus.Envelope, error) {
	entries, err := os.ReadDir(dir)
	if err != nil {
		if os.IsNotExist(err) {
			return nil, nil
		}
		return nil, err
	}

	var all []bus.Envelope
	for _, entry := range entries {
		if entry.IsDir() || !strings.HasSuffix(entry.Name(), ".jsonl") {
			continue
		}
		f, err := os.Open(filepath.Join(dir, entry.Name()))
		if err != nil {
			continue
		}
		scanner := bufio.NewScanner(f)
		for scanner.Scan() {
			var env bus.Envelope
			if err := json.Unmarshal(scanner.Bytes(), &env); err != nil {
				continue
			}
			all = append(all, env)
		}
		f.Close()
	}

	if len(all) == 0 {
		return nil, nil
	}

	// Separate warnings (always included) from others
	var warnings, others []bus.Envelope
	for _, e := range all {
		if e.Type == "board.warning" {
			warnings = append(warnings, e)
		} else {
			others = append(others, e)
		}
	}

	// Cap non-warning messages, keeping most recent
	remaining := maxMessages - len(warnings)
	if remaining < 0 {
		remaining = 0
	}
	if len(others) > remaining {
		others = others[len(others)-remaining:]
	}

	result := append(warnings, others...)
	return result, nil
}

// FormatBoardContext formats board entries as markdown for injection into .ralph_context.md.
func FormatBoardContext(entries []bus.Envelope) string {
	if len(entries) == 0 {
		return ""
	}

	var b strings.Builder
	b.WriteString("## Peer Task Findings (from bulletin board)\n\n")

	for _, e := range entries {
		var payload struct {
			Text string `json:"text"`
		}
		json.Unmarshal(e.Payload, &payload)

		prefix := "INFO"
		switch e.Type {
		case "board.discovery":
			prefix = "DISCOVERY"
		case "board.warning":
			prefix = "WARNING"
		case "board.intent":
			prefix = "INTENT"
		case "board.context":
			prefix = "CONTEXT"
		}
		b.WriteString(fmt.Sprintf("- **[%s]** (%s): %s\n", prefix, e.Sender, payload.Text))
	}
	return b.String()
}

// BusMarker represents a structured marker extracted from LLM output.
type BusMarker struct {
	Type string // "board.discovery", "board.warning", "board.intent"
	Text string
}

var busMarkerRe = regexp.MustCompile(`(?s)<!-- BUS:(discovery|warning|intent) -->(.*?)<!-- /BUS -->`)

// ExtractBusMarkers extracts structured BUS markers from LLM output.
func ExtractBusMarkers(output string) []BusMarker {
	matches := busMarkerRe.FindAllStringSubmatch(output, -1)
	var markers []BusMarker
	for _, m := range matches {
		markers = append(markers, BusMarker{
			Type: "board." + m[1],
			Text: strings.TrimSpace(m[2]),
		})
	}
	return markers
}

// PublishMarkers publishes extracted markers to the message bus.
func PublishMarkers(b bus.MessageBus, topic, sender string, markers []BusMarker) error {
	for _, m := range markers {
		payload, _ := json.Marshal(struct {
			Text string `json:"text"`
		}{Text: m.Text})
		err := b.Publish(topic, bus.Message{
			Type:    m.Type,
			Sender:  sender,
			Payload: json.RawMessage(payload),
		})
		if err != nil {
			return err
		}
	}
	return nil
}
