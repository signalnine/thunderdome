# Ralph Loop for Subagent-Driven Development

## Overview

A composable autonomous iteration wrapper that runs each task until success criteria are met or iteration cap is hit. Inspired by Geoffrey Huntley's Ralph Wiggum loop technique.

**Core Principle:** Fresh context per iteration + mechanical state tracking + tiered escalation = autonomous task completion without human in the loop.

## Success Criteria

| Gate | Type | Description |
|------|------|-------------|
| Tests pass | Hard | All tests must pass |
| Spec compliance | Hard | Independent reviewer confirms spec met |
| Code quality | Soft | Warnings logged, doesn't block |
| Iteration cap | Hard | Max 5 attempts (configurable) |

**Dropped from autonomous loop:** Multi-agent consensus review (too slow/flaky for iteration loop; run once at end instead).

## Architecture

```
skills/
  ralph-loop/
    SKILL.md              # Wrapper skill instructions
    ralph-runner.sh       # Bash loop enforcer
  subagent-driven-development/
    SKILL.md              # Unchanged
    implementer-prompt.md # Updated: reads state, embeds spec
    spec-reviewer-prompt.md
    code-quality-reviewer-prompt.md
```

**Wrapper layers on top** - does not replace or fork existing skill.

## Core Loop

```bash
#!/usr/bin/env bash
TASK_ID="$1"
MAX_ITER="${2:-5}"
STATE_FILE=".ralph_state.md"
LOCK_FILE=".ralph.lock"

# Prevent concurrent runs
if [ -f "$LOCK_FILE" ] && kill -0 "$(cat $LOCK_FILE)" 2>/dev/null; then
    echo "ERROR: Another Ralph loop active (PID $(cat $LOCK_FILE))"
    exit 1
fi
echo $$ > "$LOCK_FILE"
trap "rm -f $LOCK_FILE" EXIT

for i in $(seq 1 $MAX_ITER); do
    echo "Ralph Loop: Iteration $i/$MAX_ITER for $TASK_ID"

    # Invoke with timeout
    if timeout 20m claude --task "$TASK_ID" --state "$STATE_FILE"; then
        echo "SUCCESS: $TASK_ID completed in $i iterations"
        rm -f "$STATE_FILE"
        exit 0
    fi

    # Check for stuck loop
    if grep -q "stuck_count: [3-9]" "$STATE_FILE" 2>/dev/null; then
        echo "STUCK: Escalating to strategy shift"
        inject_strategy_shift "$STATE_FILE"
    fi
done

# Cap hit - branch and skip
echo "CAP HIT: $TASK_ID failed after $MAX_ITER attempts"
branch_failed_work "$TASK_ID"
exit 1
```

## Timeout Configuration

```
Global Limits:
  Soft: 45 minutes (checkpoint + warning)
  Hard: 60 minutes (terminate loop)

Per-Gate Limits:
  Implement: 12min soft / 20min hard
  Test: 5min soft / 10min hard
  Spec Review: 3min soft / 5min hard
  Quality Check: 2min soft / 3min hard
```

- Per-gate timeout = failed attempt (1 of 5), loop continues
- Global timeout = entire loop terminates
- `--timeout-multiplier` flag for known-complex tasks

## State File Format

**File:** `.ralph_state.md` (markdown with YAML frontmatter)

```markdown
---
task_id: auth-feature
iteration: 3
max_iterations: 5
last_gate: spec-review
exit_code: 1
error_hash: a3f2b7c1
timestamp: 2026-01-21T10:30:00Z
stuck_count: 0
strategy_shifts: 0
files_modified:
  - src/auth.ts
  - tests/auth.test.ts
---

## Spec Reviewer Output (verbatim)
```
Missing: password reset flow (spec line 24)
Extra: added --json flag (not requested)
```

## Test Output (verbatim)
```
FAIL src/auth.test.ts
  ✕ should reject expired token
    Expected: 401, Received: 200
```

## Attempt History
| # | Gate | Error Hash | Strategy Shift |
|---|------|------------|----------------|
| 1 | tests | a3f2b7c1 | no |
| 2 | tests | a3f2b7c1 | no |
| 3 | spec | c4d5e6f7 | yes |
```

**Rules:**
- System writes file, never LLM
- Verbatim output (no summaries) - prevents hallucination
- Truncate at 100 lines with `[... N lines truncated ...]`
- Rolling window of last 3 attempts
- Error hash enables stuck detection

## Stuck Detection and Escalation

**3-tier escalation when same error hash appears 3x:**

### Tier 1: Strategy Shift (attempts 4-5)
- Inject into prompt: "You're stuck. Previous approach failed 3x with same error. Try fundamentally different approach."
- Include actual error trace
- Explicitly forbid the failed pattern
- Cap at 2 strategy shift attempts

### Tier 2: Context Expansion (conditional)
- Only if error suggests info gap (ImportError, NameError, FileNotFound)
- Provide additional file context
- Otherwise skip to Tier 3

### Tier 3: Hard Stop
- Abort loop, mark task `failed`
- Create failure branch with diagnostics
- Log full error history
- Continue to next task

## Iteration Flow

```
┌─────────────────────────────────────────────────────────────┐
│ 1. READ STATE                                                │
│    - Load .ralph_state.md (if exists)                       │
│    - Read relevant source files                              │
│    - Check iteration count, stuck status                    │
└─────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────┐
│ 2. IMPLEMENT                                                 │
│    - Dispatch implementer subagent                          │
│    - Prompt includes: task spec, previous failures          │
│    - If stuck: includes strategy shift directive            │
│    - Implementer writes code, commits                       │
└─────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────┐
│ 3. TEST GATE (hard) [timeout: 10min]                        │
│    - Run test suite                                          │
│    - FAIL → capture output, update state, continue loop     │
│    - PASS → proceed to spec review                          │
└─────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────┐
│ 4. SPEC GATE (hard) [timeout: 5min]                         │
│    - Dispatch spec reviewer (fresh context)                 │
│    - FAIL → capture issues, update state, continue loop     │
│    - PASS → proceed to quality check                        │
└─────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────┐
│ 5. QUALITY CHECK (soft) [timeout: 3min]                     │
│    - Dispatch code quality reviewer                         │
│    - Log warnings to output (don't block)                   │
│    - Always proceed to success                              │
└─────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────┐
│ 6. SUCCESS                                                   │
│    - Clean up .ralph_state.md                               │
│    - Mark task complete in TodoWrite                        │
│    - Exit 0                                                  │
└─────────────────────────────────────────────────────────────┘
```

## Cleanup Behavior

| Scenario | State File | Branches |
|----------|-----------|----------|
| **Success** | Delete | None created |
| **Cap hit** | Preserve | Create `wip/ralph-fail-{task-id}-{timestamp}` |
| **Interrupt** | Preserve (as-is) | Don't create (incomplete) |
| **Rerun** | Prompt: resume or fresh? | Archive old branches |

**Concurrency:** Disallowed in same worktree via `.ralph.lock` file.

**Failure branch content:**
```bash
git checkout -b "wip/ralph-fail-${TASK_ID}-$(date +%Y%m%d-%H%M%S)"
git add -A
git commit -m "Ralph Loop failed: ${TASK_ID}

Iterations: ${ITER}/${MAX_ITER}
Last gate: ${LAST_GATE}
Error hash: ${ERROR_HASH}

See .ralph_state.md for full history"
git push -u origin HEAD
git checkout "${WORKING_BRANCH}"
git reset --hard HEAD~${COMMITS_TO_UNDO}
```

## Failure Report

Generated at end of plan execution:

```markdown
# Ralph Loop Execution Summary

## Completed: 4/6 tasks

## Failed Tasks (require human attention):

### Task 3: Add authentication
- Attempts: 5/5
- Last gate: spec-compliance
- Branch: wip/ralph-fail-auth-20260121-103045
- Error: Missing password reset flow
- Stuck: No
- Quality warnings: 2

### Task 5: Rate limiting
- Attempts: 5/5
- Last gate: tests
- Branch: wip/ralph-fail-ratelimit-20260121-104532
- Error: Race condition in token bucket
- Stuck: Yes (same error 3x, strategy shift failed)
- Quality warnings: 0
```

## Updated Implementer Prompt

```markdown
# Task Implementation

## Your Task
{TASK_SPEC}

## Success Criteria (you must satisfy ALL)
- [ ] {CRITERION_1}
- [ ] {CRITERION_2}
- [ ] {CRITERION_3}

## Previous Attempts
{Contents of .ralph_state.md, or "First attempt" if none}

{IF STUCK}
## IMPORTANT: Strategy Shift Required
You have failed 3x with the same error. Your previous approach does not work.
You MUST try a fundamentally different approach. Do NOT:
- {FORBIDDEN_PATTERN_FROM_ERROR}

Consider completely different solutions.
{/IF STUCK}

## Process
1. Read relevant source files
2. If previous attempts exist, understand what failed and why
3. Write tests FIRST (TDD)
4. Implement the feature/fix
5. Run tests, ensure passing
6. Self-review against success criteria
7. Commit with descriptive message

## Exit Signals
- Tests pass AND spec criteria met → exit 0
- Tests fail OR spec criteria not met → exit 1
```

## Integration with Existing Skill

**What changes:**
- New `skills/ralph-loop/` directory with wrapper
- `implementer-prompt.md` updated to read state file
- Spec embedded in implementer prompt (not just separate review)

**What stays same:**
- `subagent-driven-development/SKILL.md` unchanged
- Spec reviewer still runs independently (fresh context)
- Code quality reviewer still runs
- TodoWrite for progress tracking

**Usage:**
```bash
# Run single task with Ralph Loop
./skills/ralph-loop/ralph-runner.sh "task-auth" 5

# Integrate with plan execution
for task in $(get_tasks_from_plan); do
    ./skills/ralph-loop/ralph-runner.sh "$task" 5 || mark_failed "$task"
done
generate_failure_report
```

## Key Design Decisions

| Decision | Choice | Reasoning |
|----------|--------|-----------|
| Success criteria | Tests + Spec (hard), Quality (soft) | Consensus: quality shouldn't cause infinite loops |
| Loop mechanism | Hybrid bash + skill | Bash enforces cap, skill owns logic |
| Previous work visibility | State file with verbatim output | No LLM summaries (hallucination risk) |
| Spec review | Embed in prompt + independent reviewer | Reduces iterations, verifies independently |
| Failure handling | Branch and skip | Don't block entire plan for one task |
| Timeouts | Per-gate + global | Different phases have different profiles |
| Stuck response | 3-tier escalation | Strategy shift → context expand → abort |
| State format | Markdown + YAML frontmatter | LLM-readable body, machine-parseable header |
| Concurrency | Disallowed (lockfile) | Git lock contention is real |

## Testing Strategy

**Unit tests:**
- Success on first try
- Success after retry
- Cap hit creates branch
- Stuck detection triggers escalation
- Timeout enforcement
- Lockfile prevents concurrent runs

**Integration test:**
- Create trivial failing task
- Run ralph-runner.sh
- Verify iterations, state updates, success

**Smoke test checklist:**
- [ ] Fresh context each iteration
- [ ] State file captures real error output
- [ ] Spec reviewer runs independently
- [ ] Quality warnings logged but don't block
- [ ] Failed branch contains diagnostics
- [ ] Rerun detects existing state
- [ ] Concurrent run blocked
