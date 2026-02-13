package bus

import (
	"fmt"
	"os"
	"sync"
)

const channelBufferSize = 64

type subscriber struct {
	pattern string
	ch      chan Envelope
}

// ChannelBus implements MessageBus using Go channels for in-process communication.
type ChannelBus struct {
	mu          sync.RWMutex
	subscribers []subscriber
	closed      bool
}

// NewChannelBus creates a new in-process message bus.
func NewChannelBus() *ChannelBus {
	return &ChannelBus{}
}

func (b *ChannelBus) Publish(topic string, msg Message) error {
	env := NewEnvelope(topic, msg)

	b.mu.RLock()
	defer b.mu.RUnlock()

	if b.closed {
		return fmt.Errorf("bus is closed")
	}

	for _, sub := range b.subscribers {
		if TopicMatch(sub.pattern, topic) {
			select {
			case sub.ch <- env:
			default:
				fmt.Fprintf(os.Stderr, "[bus] dropped message for %q (buffer full)\n", sub.pattern)
			}
		}
	}
	return nil
}

func (b *ChannelBus) Subscribe(topic string) (<-chan Envelope, error) {
	b.mu.Lock()
	defer b.mu.Unlock()

	if b.closed {
		return nil, fmt.Errorf("bus is closed")
	}

	ch := make(chan Envelope, channelBufferSize)
	b.subscribers = append(b.subscribers, subscriber{pattern: topic, ch: ch})
	return ch, nil
}

func (b *ChannelBus) Unsubscribe(topic string) error {
	b.mu.Lock()
	defer b.mu.Unlock()

	filtered := b.subscribers[:0]
	for _, sub := range b.subscribers {
		if sub.pattern == topic {
			close(sub.ch)
		} else {
			filtered = append(filtered, sub)
		}
	}
	b.subscribers = filtered
	return nil
}

func (b *ChannelBus) Close() error {
	b.mu.Lock()
	defer b.mu.Unlock()

	if b.closed {
		return nil
	}
	b.closed = true
	for _, sub := range b.subscribers {
		close(sub.ch)
	}
	b.subscribers = nil
	return nil
}
