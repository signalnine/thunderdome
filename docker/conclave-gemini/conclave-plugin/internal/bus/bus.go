package bus

import (
	"encoding/json"
	"fmt"
	"os"
	"strings"
	"sync/atomic"
	"time"
)

// MessageBus is the interface for inter-agent communication.
type MessageBus interface {
	Publish(topic string, msg Message) error
	Subscribe(topic string) (<-chan Envelope, error)
	Unsubscribe(topic string) error
	Close() error
}

// Message is the input to Publish, before envelope wrapping.
type Message struct {
	Type    string          `json:"type"`
	Sender  string          `json:"sender"`
	Payload json.RawMessage `json:"payload"`
}

// Envelope is the on-wire message format.
type Envelope struct {
	ID        string          `json:"id"`
	Seq       uint64          `json:"seq"`
	Timestamp time.Time       `json:"timestamp"`
	Sender    string          `json:"sender"`
	Topic     string          `json:"topic"`
	Type      string          `json:"type"`
	Payload   json.RawMessage `json:"payload"`
}

var seqCounter atomic.Uint64
var pidPrefix = fmt.Sprintf("%d", os.Getpid())

// NewEnvelope wraps a Message into an Envelope with generated ID and sequence.
func NewEnvelope(topic string, msg Message) Envelope {
	seq := seqCounter.Add(1)
	return Envelope{
		ID:        fmt.Sprintf("%s-%d", pidPrefix, seq),
		Seq:       seq,
		Timestamp: time.Now(),
		Sender:    msg.Sender,
		Topic:     topic,
		Type:      msg.Type,
		Payload:   msg.Payload,
	}
}

// TopicMatch returns true if topic matches or starts with the pattern prefix.
func TopicMatch(pattern, topic string) bool {
	if pattern == "" {
		return true
	}
	if topic == pattern {
		return true
	}
	return strings.HasPrefix(topic, pattern+".")
}
