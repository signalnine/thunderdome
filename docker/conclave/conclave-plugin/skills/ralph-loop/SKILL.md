---
name: ralph-loop
description: Use when running tasks autonomously with retry - iterates until success or cap hit
---

# Ralph Loop

Autonomous iteration wrapper for subagent-driven-development. Inspired by Geoffrey Huntley's Ralph Wiggum loop technique.

**Core Principle:** Fresh context per iteration + mechanical state tracking + tiered escalation = autonomous task completion without human in the loop.

## Overview

Runs each task in a loop until:
- **Success:** Tests pass AND spec compliance verified
- **Failure:** Iteration cap hit (default: 5)

Each iteration:
1. Prepends TDD discipline + completion gate preamble to the task prompt
2. Dispatches Claude Code with task spec + previous failure context
3. Runs test gate (hard - must pass)
4. Runs spec compliance gate (hard - must pass)
5. Runs code quality gate (soft - warnings only)

**TDD enforcement:** Every iteration prompt includes mandatory TDD instructions (RED-GREEN-REFACTOR) and a completion gate (full suite + diff review). This was identified as the single most effective methodology in benchmarks (+12.3pp over vanilla).

## Usage

```bash
conclave ralph-run <task-id> <task-prompt-file> [options]

# Examples
conclave ralph-run "add-auth" ./specs/auth-feature.md
conclave ralph-run "fix-bug-123" ./specs/bug-123.md -n 3 --non-interactive
```

### Arguments

| Argument | Description |
|----------|-------------|
| `task-id` | Unique identifier for this task |
| `task-prompt-file` | Path to markdown file with task spec |

### Options

| Option | Description |
|--------|-------------|
| `-n, --max-iter N` | Maximum iterations (default: 5) |
| `-d, --dir DIR` | Project directory (default: current) |
| `--non-interactive` | Don't prompt for resume, auto-fresh |
| `-h, --help` | Show help |

## Configuration

### Timeouts (via environment variables)

| Variable | Default | Description |
|----------|---------|-------------|
| `RALPH_TIMEOUT_IMPLEMENT` | 1200 (20 min) | Implementation timeout |
| `RALPH_TIMEOUT_TEST` | 600 (10 min) | Test suite timeout |
| `RALPH_TIMEOUT_SPEC` | 300 (5 min) | Spec review timeout |
| `RALPH_TIMEOUT_QUALITY` | 180 (3 min) | Quality check timeout |
| `RALPH_TIMEOUT_GLOBAL` | 3600 (60 min) | Overall loop timeout |

### Thresholds

| Variable | Default | Description |
|----------|---------|-------------|
| `RALPH_STUCK_THRESHOLD` | 3 | Same error count before aborting |

## State Files

### `.ralph_state.json`

Machine-readable state (JSON for reliable parsing):

```json
{
  "task_id": "add-auth",
  "iteration": 3,
  "max_iterations": 5,
  "last_gate": "tests",
  "exit_code": 1,
  "error_hash": "a3f2b7c1",
  "stuck_count": 2,
  "attempts": [...]
}
```

### `.ralph_context.md`

LLM-readable context with verbatim error output:

```markdown
# Ralph Loop Context: add-auth

## Status
- Iteration: 3 of 5
- Last gate failed: tests
- Stuck count: 2 (threshold: 3)

## Last Error Output (verbatim)
...
```

## Gates

### Test Gate (Hard)

Auto-detects test runner:
- `package.json` → `npm test`
- `Cargo.toml` → `cargo test`
- `pyproject.toml` or `setup.py` → `pytest`
- `go.mod` → `go test ./...`
- `test.sh` → custom script

### Spec Gate (Hard)

Invokes Claude Code to verify implementation matches spec. Looks for `SPEC_PASS` in output.

### Quality Gate (Soft)

Auto-detects linter (npm lint, clippy, ruff). Warnings logged but don't block success.

## Stuck Detection

When same error hash appears 3+ times:
1. Adds "strategy shift" directive to context
2. Explicitly tells implementer to try fundamentally different approach
3. If still stuck after strategy shift → abort

## Failure Handling

On cap hit or stuck abort:
1. Creates `wip/ralph-fail-{task-id}-{timestamp}` branch
2. Commits all state + context files
3. Pushes to origin (non-fatal if no remote)
4. Returns to working branch

**Safety:** Won't reset main/master branches.

## Concurrency

Lockfile (`.ralph.lock`) prevents concurrent runs in same worktree. Stale locks are auto-cleaned.

## Testing

```bash
./skills/ralph-loop/test-ralph-loop.sh
```

## Integration

### With subagent-driven-development

```bash
# In plan execution loop
for task in $(get_tasks_from_plan); do
    conclave ralph-run "$task" "./specs/$task.md" || {
        echo "Task $task failed, continuing..."
    }
done
```

### With executing-plans

Add to batch execution with `--non-interactive` for CI.

## See Also

- Design: `docs/plans/2026-01-21-ralph-loop-design.md`
- Multi-agent consensus: `skills/multi-agent-consensus/`
