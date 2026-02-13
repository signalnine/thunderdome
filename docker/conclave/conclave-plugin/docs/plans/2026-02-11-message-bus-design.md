# Message Bus for Inter-Agent Coordination — Design

> **For Claude:** REQUIRED SUB-SKILL: Use conclave:executing-plans to implement this plan task-by-task.

**Goal:** Add a message bus to Conclave enabling inter-agent coordination for two use cases: real-time debate during consensus review, and shared discovery during parallel task execution.

**Architecture:** Unified `MessageBus` interface with two transport implementations (ChannelBus for in-process, FileBus for cross-process), serving consensus debate and parallel bulletin board patterns.

**Tech Stack:** Go stdlib only (`encoding/json`, `sync`, `os`, `time`, `syscall` for flock)

---

## 1. Message Bus Core (`internal/bus/`)

### Interface

```go
type MessageBus interface {
    Publish(topic string, msg Message) error
    Subscribe(topic string) (<-chan Envelope, error)
    Unsubscribe(topic string) error
    Close() error
}

type Message struct {
    Type    string          // "debate.finding", "debate.rebuttal", "board.discovery", etc.
    Sender  string          // "claude", "gemini", "task-3"
    Payload json.RawMessage // Pre-marshaled JSON payload
}

type Envelope struct {
    ID        string          `json:"id"`
    Seq       uint64          `json:"seq"`
    Timestamp time.Time       `json:"timestamp"`
    Sender    string          `json:"sender"`
    Topic     string          `json:"topic"`
    Type      string          `json:"type"`
    Payload   json.RawMessage `json:"payload"`
}
```

### ID Generation

Envelope IDs use process-prefixed sequences: `{pid}-{monotonic_counter}`. The PID prefix guarantees cross-process uniqueness without coordination. The monotonic counter (per-process `atomic.Uint64`) provides per-sender ordering. UUIDs are unnecessary given the short-lived nature of bus sessions.

### ChannelBus (in-process)

For consensus debate where all agents are goroutines in the same process:

- Topic-keyed map of subscriber channels
- `Publish` fans out to all subscribers on that topic
- **Buffered channels** (capacity 64) with non-blocking send: if a subscriber's channel is full, the message is dropped and a warning is logged. This prevents a slow consumer from blocking all publishers.
- Thread-safe via `sync.RWMutex` on the subscription map
- `Close()` closes all subscriber channels; subscribers detect closure via channel close signal
- `Unsubscribe()` removes subscriber from topic and closes its channel

### FileBus (cross-process)

For parallel ralph-run instances in separate git worktrees:

- Each topic maps to a JSON Lines file in a shared directory (e.g., `.conclave/bus/{topic}.jsonl`)
- `Publish` acquires an exclusive `flock` on the topic file, appends one Envelope as a JSON line, then releases the lock. This ensures atomic concurrent appends from multiple processes.
- `Subscribe` polls the file tracking last-read byte offset. Polling uses adaptive intervals: starts at 100ms, backs off to 1s when idle (no new data for 5 consecutive polls), resets to 100ms on new data.
- Per-sender sequence numbers allow consumers to detect gaps

### Topic Matching

All topic matching uses **prefix matching** consistently across both implementations. `Subscribe("parallel.wave-0")` receives messages for `parallel.wave-0`, `parallel.wave-0.board`, etc. No glob syntax — prefix-only keeps the contract simple and identical between ChannelBus and FileBus.

### Bus Directory Lifecycle

Created by the orchestrator (parallel-run or consensus command) at session start. Cleaned up on completion or SIGINT. On startup, stale bus directories are detected by checking for a PID file (`.conclave/bus/.pid`); if the PID is dead, the directory is removed before creating a fresh one.

## 2. Consensus Debate (Stage 1.5)

### Flow

```
Stage 1:   Independent analysis (existing — parallel goroutines)
              |
Stage 1.5: Debate round (NEW — opt-in via --debate)
              |
Stage 2:   Chairman synthesis (existing — now receives 6 inputs)
```

### Stage 1.5 Mechanics

After all Stage 1 results are collected, each agent's output is condensed to a 2-3 sentence thesis summary. These summaries are broadcast to all agents via ChannelBus on topic `consensus.{session}.debate`. Each agent receives a rebuttal prompt:

```
Three agents analyzed this problem independently. Their positions:

- Claude: "{thesis summary}"
- Gemini: "{thesis summary}"
- Codex: "{thesis summary}"

Identify specific points of disagreement, factual errors, or missing
considerations in the other agents' analyses. Be concise and direct.
```

Rebuttals run in parallel (same WaitGroup pattern as Stage 1). Each agent publishes its rebuttal back to the debate topic.

### Chairman Expanded Input

The Stage 2 prompt includes both original analyses and rebuttals, clearly labeled. The chairman prompt is updated to weigh points where agents changed their position after seeing others' work — convergence after debate is a stronger signal than initial agreement.

### Configuration

- `--debate` flag on `conclave consensus` and `conclave auto-review`
- `CONSENSUS_DEBATE_ROUNDS` env var (default 1, max 2)
- `CONSENSUS_DEBATE_TIMEOUT` env var (default 60s, same as Stage 1)

### Cost

One additional API call per agent per debate round. A single-round debate roughly doubles the token cost of consensus but produces significantly higher-quality synthesis.

## 3. Parallel Bulletin Board

### Board Per Wave

When parallel-run launches a wave, it creates a bus directory at `.conclave/bus/wave-{N}/` with a single board file `board.jsonl`. All ralph-run instances in that wave share this file via FileBus.

### Message Types

| Type | Purpose | Example |
|------|---------|---------|
| `board.discovery` | Factual findings that help other tasks | "The API uses pagination, not cursor-based fetching" |
| `board.warning` | Pitfalls encountered | "Don't import package X, it has a breaking change in v2" |
| `board.intent` | Advisory resource claims to reduce merge conflicts | "I'm modifying `internal/auth/handler.go`" |
| `board.context` | Injected by orchestrator with prior wave summaries | Summary of wave 0 discoveries for wave 1 |

### How Ralph-Run Reads the Board

At the start of each iteration (not continuously), ralph-run checks the board file and appends relevant entries to `.ralph_context.md` — the context file already fed to each `claude -p` invocation. The LLM sees peer discoveries naturally as part of its task context without prompt engineering changes. **Cap: maximum 20 board messages injected per iteration** to prevent context window pollution. Most recent messages take priority; `board.warning` messages always included regardless of cap.

### How Ralph-Run Writes to the Board

After each successful gate (implement/test/spec), ralph-run scans the iteration output for publishable findings. The LLM is prompted to emit structured markers in its output:

```
<!-- BUS:discovery -->The API uses cursor-based pagination<!-- /BUS -->
<!-- BUS:warning -->Package X v2 has breaking changes in the auth module<!-- /BUS -->
<!-- BUS:intent -->Modifying internal/auth/handler.go<!-- /BUS -->
```

Ralph-run extracts content between `<!-- BUS:type -->` and `<!-- /BUS -->` tags. This is reliable (exact string matching, no heuristics) and invisible to the LLM's normal output rendering.

### Orchestrator Between Waves

After a wave completes, parallel-run reads the wave's board, takes the most recent 10 discoveries and all warnings, and injects them as `board.context` into the next wave's board. This gives later waves accumulated project knowledge without unbounded context growth.

### Cleanup

Bus directories are removed during parallel-run's cleanup phase alongside worktree removal.

## 4. Package Structure

| File | Purpose |
|------|---------|
| `internal/bus/bus.go` | MessageBus interface, Envelope, Message types, ID generation |
| `internal/bus/channel.go` | ChannelBus implementation (in-process) |
| `internal/bus/file.go` | FileBus implementation (cross-process, flock) |
| `internal/bus/bus_test.go` | Unit tests for both implementations |
| `internal/bus/bus_integration_test.go` | Cross-process concurrency stress tests |

## 5. CLI Changes

| Command | Change |
|---------|--------|
| `conclave consensus` | Add `--debate` flag; wire ChannelBus for Stage 1.5 |
| `conclave auto-review` | Pass `--debate` through to consensus |
| `conclave parallel-run` | Create/cleanup bus dirs; inject board context between waves |
| `conclave ralph-run` | Read board at iteration-start; write findings after gates |

## 6. Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `CONSENSUS_DEBATE_ROUNDS` | 1 | Number of debate rounds (max 2) |
| `CONSENSUS_DEBATE_TIMEOUT` | 60s | Timeout per debate round |
| `BUS_POLL_INTERVAL` | 100ms | FileBus initial polling interval |
| `BUS_POLL_MAX_INTERVAL` | 1s | FileBus max polling interval (adaptive backoff) |
| `BUS_DIR` | `.conclave/bus` | Bus directory path |
| `BUS_MAX_BOARD_INJECT` | 20 | Max board messages injected per ralph-run iteration |

## 7. Testing Strategy

- **Unit tests:** ChannelBus publish/subscribe, fan-out, backpressure drop, close behavior. FileBus write/read, flock contention, adaptive polling, offset tracking.
- **Concurrency tests:** 50 goroutines publishing simultaneously to ChannelBus. Multiple processes appending to same FileBus topic file with flock.
- **Integration tests (`//go:build integration`):** Full consensus with `--debate` flag against real APIs. Parallel-run with bus-enabled ralph-run instances sharing a board.
- **Race detector:** All tests run with `-race`.
