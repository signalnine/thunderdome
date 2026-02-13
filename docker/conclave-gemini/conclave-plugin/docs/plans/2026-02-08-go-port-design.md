# Conclave Go Port - Design Document

Port all bash scripts and JavaScript libraries to a single Go binary (`conclave`) with Cobra subcommands. Skills (SKILL.md) stay as markdown. The binary replaces consensus-synthesis.sh, auto-review.sh, parallel-runner.sh, ralph-runner.sh, supporting libs, session-start hook, and skill discovery.

## Motivation

- **Single binary distribution** - eliminate bash/jq/curl dependencies
- **Performance & concurrency** - goroutines/channels for parallel API calls and worktree management
- **Maintainability** - type safety, testability, structure over 1,200-line bash scripts

## Command Tree

```
conclave
├── consensus            # replaces consensus-synthesis.sh
│   ├── --mode=code-review|general-prompt
│   ├── --base-sha, --head-sha, --description
│   ├── --prompt, --context
│   ├── --stage1-timeout, --stage2-timeout
│   └── --dry-run
├── auto-review          # replaces auto-review.sh
│   ├── <description>    (positional)
│   ├── --base, --head, --plan-file
│   └── --dry-run
├── parallel-run         # replaces parallel-runner.sh
│   ├── <plan-file>      (positional)
│   ├── --max-concurrent, --worktree-dir
│   ├── --base-branch, --non-interactive
│   └── --dry-run
├── ralph-run            # replaces ralph-runner.sh
│   ├── <task-file>      (positional)
│   ├── --max-iterations, --worktree
│   └── timeout flags per gate
├── hook                 # replaces session-start.sh + run-hook.cmd
│   └── session-start
├── skills               # replaces lib/skills-core.js
│   ├── list
│   └── resolve <name>
└── version
```

All flags accept env var equivalents via Viper (e.g., `--stage1-timeout` / `CONSENSUS_STAGE1_TIMEOUT`).

## Package Layout

```
cmd/
  conclave/
    main.go                    # entry point, root cobra command
internal/
  consensus/
    consensus.go               # two-stage orchestration
    consensus_test.go
    agents.go                  # Claude, Gemini, Codex API clients
    agents_test.go
    chairman.go                # stage 2 synthesis
    chairman_test.go
  autoreview/
    autoreview.go              # git SHA auto-detection, wraps consensus
    autoreview_test.go
  parallel/
    runner.go                  # wave-based parallel execution
    runner_test.go
    scheduler.go               # topological sort, dependency resolution
    scheduler_test.go
    merge.go                   # worktree merge + conflict detection
    merge_test.go
  ralph/
    runner.go                  # retry state machine
    runner_test.go
    state.go                   # JSON state persistence
    state_test.go
    stuck.go                   # MD5-based stuck detection
  plan/
    parser.go                  # markdown plan -> task list
    parser_test.go
  skills/
    discovery.go               # find SKILL.md, parse frontmatter
    discovery_test.go
    resolve.go                 # namespace resolution with shadowing
    resolve_test.go
  hook/
    sessionstart.go            # JSON context injection
    sessionstart_test.go
  git/
    git.go                     # thin wrapper around git CLI (os/exec)
    git_test.go
  config/
    config.go                  # env var loading, ~/.env sourcing
    config_test.go
go.mod
go.sum
Makefile
```

All packages under `internal/` - unexported. CLI commands in `cmd/` are the only public interface.

The `git/` package is the sole place that shells out to `git`. All other packages call it, never `exec.Command("git", ...)` directly.

## Consensus Engine

### Agent Interface

```go
type Agent interface {
    Name() string
    Run(ctx context.Context, prompt string) (string, error)
    Available() bool
}
```

Three implementations: `ClaudeAgent`, `GeminiAgent`, `CodexAgent`.

### API Details

| Provider | Endpoint | Auth | Response Path |
|----------|----------|------|---------------|
| Claude | `POST /v1/messages` | `x-api-key` header | `.content[0].text` |
| Gemini | `POST /v1beta/models/{model}:generateContent` | `?key=` query param | `.candidates[0].content.parts[0].text` |
| Codex | `POST /v1/responses` (codex models) or `/v1/chat/completions` | `Bearer` header | `.output[0].content[0].text` or `.choices[0].message.content` |

### Two-Stage Execution

**Stage 1:** Launch all available agents as goroutines with shared `context.WithTimeout`. Collect results via `sync.WaitGroup`. Context cancellation kills all agents if timeout fires.

**Stage 2:** Chairman agent (Claude, with fallback to Gemini, then Codex) synthesizes all Stage 1 results into consensus output.

**Graceful degradation:** Minimum 1 of 3 agents must succeed. Chairman prompt adjusts based on how many responded.

**Output:** Full synthesis written to temp file (`/tmp/consensus-*.md`) and summary to stdout.

## Parallel Runner

Wave-based execution model:

```
Wave 1: [Task 1, Task 2, Task 3]  <- no dependencies, run in parallel
         | merge all back
Wave 2: [Task 4, Task 5]          <- depended on wave 1
         | merge all back
Wave 3: [Task 6]                  <- depends on wave 2
```

Per task within a wave:
1. `git worktree add .worktrees/task-N -b task/N <base-branch>`
2. Launch ralph-run in worktree (or direct `claude -p`)
3. Wait for all tasks in wave
4. Serial merge: `git merge task/N` for each, conflict detection
5. On merge conflict: re-run conflicting task in fresh worktree on merged base (up to `PARALLEL_MAX_CONFLICT_RERUNS`)

Concurrency capped by `--max-concurrent` (default 3).

## Ralph Loop

Retry state machine with three sequential gates per iteration:

```
Iteration N (max 5):
  Gate 1: Implementation  -> claude -p (timeout: 1200s)
  Gate 2: Tests           -> run test command (timeout: 600s)
  Gate 3: Spec compliance -> claude -p (timeout: 600s)

  All pass? -> done
  Any fail? -> MD5 hash error output
    Same hash 3x -> stuck -> shift strategy
    Same hash 5x -> abort -> create wip/ralph-fail-* branch
    Otherwise    -> iterate with fresh context
```

State persisted to `.ralph_state.json`:

```go
type RalphState struct {
    TaskID        string    `json:"task_id"`
    Iteration     int       `json:"iteration"`
    MaxIterations int       `json:"max_iterations"`
    ErrorHashes   []string  `json:"error_hashes"`
    StuckCount    int       `json:"stuck_count"`
    GateResults   []Gate    `json:"gate_results"`
    StartedAt     time.Time `json:"started_at"`
}
```

Each iteration spawns `claude -p` via `exec.CommandContext` - context timeout kills it cleanly.

## Plan Parser

Line-by-line state machine. Recognizes `## Task N: Title` headers and `Depends on: Task X, Task Y` markers.

```go
type Task struct {
    ID           int
    Title        string
    Description  string
    FilePaths    []string
    DependsOn    []int
    Verification string
}

func ParsePlan(reader io.Reader) ([]Task, error)
```

## Skills Discovery

```go
type Skill struct {
    Name        string
    Description string
    Path        string
    Source      string // "conclave", "personal", "project"
}

func Discover(dirs ...string) []Skill
func Resolve(name string, dirs ...string) *Skill
```

Search order: project-local > personal (`~/.claude/skills/`) > conclave plugin skills. The `conclave:` prefix forces conclave-only resolution.

## Session Start Hook

`conclave hook session-start`:
1. Check for legacy `~/.config/conclave/skills/` directory, emit warning if exists
2. Read `using-conclave/SKILL.md` from plugin root (resolved relative to binary location)
3. Output JSON: `{"hookSpecificOutput": {"hookEventName": "SessionStart", "additionalContext": "..."}}`

## Testing Strategy

Three layers, 80%+ coverage target.

**Unit tests:** Table-driven tests in every package. API clients tested against `httptest.NewServer` mocks. No real API calls. `Agent` interface enables `MockAgent` injection.

**Integration tests:** Build binary, run as subprocess with env vars pointing at mock HTTP servers. Requires `*_BASE_URL` env vars (`ANTHROPIC_BASE_URL`, etc.) for test-only endpoint override.

**Git operation tests:** Real git repos in `t.TempDir()`. Real filesystem, no mocks. Tests the `internal/git/` wrapper against actual git behavior.

Existing bash tests (`tests/claude-code/`, `tests/skill-triggering/`) remain unchanged - they test skill behavior in Claude Code sessions.

```makefile
test:           go test ./... -race -cover
test-integration: go test ./... -race -run Integration
lint:           golangci-lint run ./...
```

## Git Operations

Shell out to `git` CLI via `os/exec`. No `go-git` library. Users already have git installed. The `internal/git/` package wraps all git commands:

- `WorktreeAdd(path, branch, base string) error`
- `WorktreeRemove(path string) error`
- `Merge(branch string) error`
- `MergeBase(a, b string) (string, error)`
- `Diff(base, head string) (string, error)`
- `BranchCreate(name, base string) error`

## Build & Release

```makefile
VERSION := $(shell git describe --tags --always --dirty)

build:
    go build -ldflags "-X main.version=$(VERSION)" -o conclave ./cmd/conclave

install:
    go install ./cmd/conclave
```

Static binary. Cross-compile for darwin/linux (amd64, arm64).

## Dependencies

| Library | Purpose |
|---------|---------|
| `github.com/spf13/cobra` | CLI framework |
| `github.com/spf13/viper` | Config/env var binding |
| `gopkg.in/yaml.v3` | YAML frontmatter parsing |
| stdlib only | HTTP, JSON, concurrency, filesystem, exec |

## Migration

**Plugin changes:**
- `hooks/hooks.json`: command path updated to `conclave hook session-start`
- All SKILL.md files: script references updated (e.g., `consensus-synthesis.sh` -> `conclave consensus`)

**Deleted after port:**
- All `.sh` files replaced by Go subcommands
- `lib/skills-core.js`
- `hooks/session-start.sh`, `hooks/run-hook.cmd`
- `.codex/conclave-codex` (Node.js script)

**Kept unchanged:**
- All SKILL.md files (updated references only)
- `commands/*.md`
- `agents/code-reviewer.md`
- `.claude-plugin/plugin.json`
- Test suites in `tests/`

**Incremental approach:** Port one subcommand at a time. Both bash and Go coexist during transition. Start with `conclave consensus`, validate against existing bash tests, then proceed to others.
