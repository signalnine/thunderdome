package bus

import (
	"bufio"
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"syscall"
	"time"
)

type fileSubscriber struct {
	pattern string
	ch      chan Envelope
	offsets map[string]int64 // per-file byte offsets (keyed by filename)
	stop    chan struct{}
}

// FileBus implements MessageBus using JSON Lines files with flock for cross-process communication.
// Note: syscall.Flock is Unix-only. Windows is not supported.
type FileBus struct {
	dir     string
	pollMin time.Duration
	pollMax time.Duration
	mu      sync.Mutex
	subscribers []*fileSubscriber
	closed  bool
}

// NewFileBus creates a cross-process message bus backed by files in dir.
func NewFileBus(dir string, pollMin, pollMax time.Duration) (*FileBus, error) {
	if err := os.MkdirAll(dir, 0755); err != nil {
		return nil, fmt.Errorf("create bus dir: %w", err)
	}
	return &FileBus{
		dir:     dir,
		pollMin: pollMin,
		pollMax: pollMax,
	}, nil
}

func (b *FileBus) topicFile(topic string) string {
	return filepath.Join(b.dir, topic+".jsonl")
}

func (b *FileBus) Publish(topic string, msg Message) error {
	env := NewEnvelope(topic, msg)
	data, err := json.Marshal(env)
	if err != nil {
		return fmt.Errorf("marshal envelope: %w", err)
	}
	line := append(data, '\n')

	path := b.topicFile(topic)
	f, err := os.OpenFile(path, os.O_CREATE|os.O_WRONLY|os.O_APPEND, 0644)
	if err != nil {
		return fmt.Errorf("open topic file: %w", err)
	}
	defer f.Close()

	// Acquire exclusive lock
	if err := syscall.Flock(int(f.Fd()), syscall.LOCK_EX); err != nil {
		return fmt.Errorf("flock: %w", err)
	}
	defer syscall.Flock(int(f.Fd()), syscall.LOCK_UN)

	if _, err := f.Write(line); err != nil {
		return fmt.Errorf("write: %w", err)
	}
	return nil
}

func (b *FileBus) Subscribe(topic string) (<-chan Envelope, error) {
	b.mu.Lock()
	defer b.mu.Unlock()

	if b.closed {
		return nil, fmt.Errorf("bus is closed")
	}

	sub := &fileSubscriber{
		pattern: topic,
		ch:      make(chan Envelope, channelBufferSize),
		offsets: make(map[string]int64),
		stop:    make(chan struct{}),
	}
	b.subscribers = append(b.subscribers, sub)

	go b.pollLoop(sub)
	return sub.ch, nil
}

func (b *FileBus) pollLoop(sub *fileSubscriber) {
	defer close(sub.ch)

	interval := b.pollMin
	idleCount := 0

	for {
		select {
		case <-sub.stop:
			return
		case <-time.After(interval):
		}

		found := b.pollFiles(sub)
		if found > 0 {
			interval = b.pollMin
			idleCount = 0
		} else {
			idleCount++
			if idleCount >= 5 && interval < b.pollMax {
				interval = min(interval*2, b.pollMax)
			}
		}
	}
}

func (b *FileBus) pollFiles(sub *fileSubscriber) int {
	found := 0

	entries, err := os.ReadDir(b.dir)
	if err != nil {
		return 0
	}

	for _, entry := range entries {
		if entry.IsDir() || !strings.HasSuffix(entry.Name(), ".jsonl") {
			continue
		}

		name := entry.Name()
		path := filepath.Join(b.dir, name)
		info, err := entry.Info()
		if err != nil {
			continue
		}
		fileOffset := sub.offsets[name]
		if info.Size() <= fileOffset {
			continue
		}

		f, err := os.Open(path)
		if err != nil {
			continue
		}

		if fileOffset > 0 {
			f.Seek(fileOffset, 0)
		}

		// Track bytes consumed manually since bufio.Scanner reads ahead
		// and the file descriptor position won't reflect actual line boundaries.
		bytesConsumed := fileOffset
		scanner := bufio.NewScanner(f)
		for scanner.Scan() {
			lineBytes := scanner.Bytes()
			// +1 for the newline delimiter stripped by Scanner
			bytesConsumed += int64(len(lineBytes)) + 1

			var env Envelope
			if err := json.Unmarshal(lineBytes, &env); err != nil {
				continue
			}
			if TopicMatch(sub.pattern, env.Topic) {
				select {
				case sub.ch <- env:
					found++
				default:
					// Drop on full buffer
				}
			}
		}

		sub.offsets[name] = bytesConsumed
		f.Close()
	}

	return found
}

func (b *FileBus) Unsubscribe(topic string) error {
	b.mu.Lock()
	defer b.mu.Unlock()

	filtered := b.subscribers[:0]
	for _, sub := range b.subscribers {
		if sub.pattern == topic {
			close(sub.stop)
		} else {
			filtered = append(filtered, sub)
		}
	}
	b.subscribers = filtered
	return nil
}

func (b *FileBus) Close() error {
	b.mu.Lock()
	defer b.mu.Unlock()

	if b.closed {
		return nil
	}
	b.closed = true
	for _, sub := range b.subscribers {
		close(sub.stop)
	}
	b.subscribers = nil
	return nil
}
