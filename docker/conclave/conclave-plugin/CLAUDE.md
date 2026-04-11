# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Is

Conclave is a Claude Code plugin that provides structured development methodologies through composable "skills" — TDD, design brainstorming, verification, and code review. Skills activate automatically based on task type and guide the agent through disciplined workflows that improve code quality by 10-12 points over unguided development. Optionally includes multi-agent consensus for higher-stakes decisions (requires API keys for Gemini and/or Codex in addition to Claude). Forked from [obra/superpowers](https://github.com/obra/superpowers).

## Running Tests

```bash
# Go unit tests (all packages including proxy, consensus, plan, etc.)
go test ./... -race

# Multi-agent consensus tests (33 tests, runs fast, no API keys needed for most)
./skills/multi-agent-consensus/test-consensus-synthesis.sh

# Auto-review wrapper tests (13 tests)
./skills/multi-agent-consensus/test-auto-review.sh

# Ralph loop tests
./skills/ralph-loop/test-ralph-loop.sh

# Multi-review tests
./skills/requesting-code-review/test-multi-review.sh

# Subagent-driven-development unit tests (run all)
./skills/subagent-driven-development/test-all.sh

# Individual SDD tests
./skills/subagent-driven-development/test-parse-plan.sh
./skills/subagent-driven-development/test-scheduler.sh
./skills/subagent-driven-development/test-merge.sh
./skills/subagent-driven-development/test-parallel-runner.sh

# OpenCode plugin tests
./tests/opencode/run-tests.sh

# Integration tests (require `claude` CLI, take 10-30 min, run from repo root)
./tests/claude-code/test-subagent-driven-development-integration.sh

# Skill triggering tests (require `claude` CLI)
./tests/skill-triggering/run-all.sh
./tests/explicit-skill-requests/run-all.sh
```

Integration tests must be run from the conclave plugin directory (not temp dirs). They require `claude` CLI and `"conclave@conclave-dev": true` in `~/.claude/settings.json`.

## Architecture

### Plugin Structure

This is a Claude Code plugin. The plugin system entry point is `.claude-plugin/plugin.json` (v4.5.0). The plugin hooks into Claude Code via:

- **`hooks/hooks.json`** - Declares a `SessionStart` hook that fires on startup/resume/clear/compact
- **`hooks/session-start.sh`** - Injects the `using-conclave` skill content into the session context so skills activate automatically
- **`hooks/run-hook.cmd`** - Cross-platform polyglot wrapper (bash/cmd)

### Skills (`skills/`)

Each skill lives in its own directory with a `SKILL.md` file containing YAML frontmatter (`name`, `description`) and the skill content. Skills are invoked via the `Skill` tool with the `conclave:` namespace prefix (e.g., `conclave:brainstorming`).

Skills are **not standalone scripts** - they are prompts/instructions that Claude follows. The `description` field in frontmatter is trigger-only ("Use when X") and must never contain process details (the "Description Trap" - Claude follows the short description instead of the full flowchart).

### Commands (`commands/`)

Three slash commands (`/brainstorm`, `/write-plan`, `/execute-plan`) that redirect to their corresponding skills. All have `disable-model-invocation: true` so only users can invoke them.

### Agents (`agents/`)

Contains `code-reviewer.md` - a specialized agent definition used by the `superpowers:code-reviewer` Task agent for structured code review against plans.

### Multi-Agent Consensus (`skills/multi-agent-consensus/`)

The core consensus engine:
- **`consensus-synthesis.sh`** - Two-stage bash script: Stage 1 runs Claude/Gemini/Codex in parallel via direct API calls (curl + jq), Stage 2 has a chairman agent synthesize findings. Requires `ANTHROPIC_API_KEY`, `GEMINI_API_KEY`, `OPENAI_API_KEY` (at least 1 of 3). Sources `~/.env` automatically.
- **`auto-review.sh`** - Convenience wrapper that auto-detects git SHAs for code review mode
- Two modes: `--mode=code-review` (reviews git diffs) and `--mode=general-prompt` (analyzes questions)

### Parallel Execution (`skills/subagent-driven-development/`)

The parallel task runner system:
- **`parallel-runner.sh`** - Orchestrator that creates git worktrees for parallel task execution
- **`lib/parse-plan.sh`** - Parses markdown implementation plans into tasks with dependency info
- **`lib/scheduler.sh`** - Topological sort scheduler respecting task dependencies
- **`lib/merge.sh`** - Merges completed worktree branches back with conflict detection
- **`lib/helpers.sh`** - Shared utilities

### Ralph Loop (`skills/ralph-loop/`)

Autonomous iteration wrapper for tasks. Runs `claude -p` in fresh context per retry (max 5 attempts). Includes stuck detection, failure branching (`wip/ralph-fail-*`), and per-gate timeouts. State tracked in `.ralph_state.json` and `.ralph_context.md`.

### Message Bus (`internal/bus/`)

Inter-agent communication system with two transport implementations behind a unified `MessageBus` interface:
- **`ChannelBus`** (`channel.go`) — In-process pub/sub via buffered Go channels (cap 64) with non-blocking send. Used for consensus debate (Stage 1.5) where all agents are goroutines.
- **`FileBus`** (`file.go`) — Cross-process pub/sub via JSON Lines files with `syscall.Flock` for atomic appends. Adaptive polling (100ms→1s backoff). Used for parallel ralph-run bulletin boards.
- **`bus.go`** — Core types (`Message`, `Envelope`, `MessageBus` interface), process-prefixed ID generation (`{pid}-{counter}`), prefix-based topic matching.

Consensus Stage 1.5 debate: opt-in via `--debate` flag. After Stage 1, agents see each other's thesis summaries and produce rebuttals. Chairman receives both original analyses and rebuttals.

Ralph bulletin board: wave-scoped boards where tasks post `<!-- BUS:type -->content<!-- /BUS -->` markers (discovery/warning/intent). Board entries injected into `.ralph_context.md` at iteration start (capped at 20, warnings always included). Orchestrator summarizes wave boards for next wave as `board.context`.

### Prose Linter (`internal/lint/`)

SKILL.md validator (`conclave lint`) checking frontmatter (required fields, schema), description rules ("Use when" prefix, length limits), skill naming (lowercase-hyphenated), word count, cross-reference validation (with fenced code block awareness), duplicate name detection, and `docs/plans/` filename format. Human-readable and `--json` output. Exit 1 on errors, 0 on clean/warnings-only.

### Token-Counting Proxy (`internal/proxy/`)

Transparent HTTP reverse proxy (`conclave proxy`) that sits between Claude Code and `api.anthropic.com`, counting input/output tokens from every API response. Uses `httputil.ReverseProxy` with a `ModifyResponse` hook for non-streaming JSON and an `io.Pipe`-based SSE scanner for streaming responses. Atomic counters for thread-safe accumulation. Prints per-request log lines to stderr and a formatted summary on SIGINT/SIGTERM shutdown.

Usage:
```bash
# Terminal 1: start proxy
conclave proxy --port 8199
# Terminal 2: point Claude Code at the proxy
ANTHROPIC_BASE_URL=http://localhost:8199 claude
# Ctrl+C the proxy when done to see token summary
```

### Shared Library (`lib/`)

`skills-core.js` - ES module used by Codex and OpenCode integrations. Handles skill discovery (`findSkillsInDir`), resolution with shadowing (`resolveSkillPath`), frontmatter parsing, and update checking. Personal skills override conclave skills by name.

### Platform Integrations

- **Claude Code**: Native plugin via `.claude-plugin/`, hooks, skills, commands, agents
- **Codex**: `.codex/conclave-codex` unified Node.js script + bootstrap markdown
- **OpenCode**: `.opencode/plugin/conclave.js` native JS plugin

## Model Recommendations

Benchmark data (796 trials) shows that with Conclave's structured methodology, **Sonnet 4.6 matches or beats Opus 4.6** at half the cost:

- TDD: Sonnet 98.2% vs Opus 97.4%
- Self-Review: Sonnet 97.1% vs Opus 96.8%

Sonnet 4.6 is the recommended default model for Conclave-guided work.

## Key Conventions

- All shell scripts use `set -euo pipefail` and bash
- Skills use DOT/GraphViz flowcharts as executable specifications (prose is supporting content)
- Design docs go to `docs/plans/YYYY-MM-DD-<topic>-design.md`, implementation plans to `docs/plans/YYYY-MM-DD-<topic>-implementation.md`
- Skill cross-references use markers: `**REQUIRED BACKGROUND:**`, `**REQUIRED SUB-SKILL:**`, `**Complementary skills:**`
- Consensus timeouts configurable via `CONSENSUS_STAGE1_TIMEOUT` / `CONSENSUS_STAGE2_TIMEOUT` env vars (default: 60s each)
