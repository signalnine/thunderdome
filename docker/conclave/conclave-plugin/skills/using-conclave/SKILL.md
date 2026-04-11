---
name: using-conclave
description: Use when starting any conversation - establishes how to find and use skills, requiring Skill tool invocation before ANY response including clarifying questions
---

## How to Access Skills

**In Claude Code:** Use the `Skill` tool with the `conclave:` namespace prefix. When you invoke a skill, its content is loaded and presented to you — follow it directly. Never use the Read tool on skill files.

**In other environments:** Check your platform's documentation for how skills are loaded.

## Automatic Skill Selection

When you receive a task, classify it and invoke the matching skill:

| Task Type | Skill to Invoke | Example |
|-----------|----------------|---------|
| Build something new | brainstorming → test-driven-development | "Add user auth", "Create API" |
| Fix a bug | test-driven-development | "Fix login error", "Debug crash" |
| Modify existing behavior | test-driven-development | "Change validation rules" |
| Execute existing plan | executing-plans | "Implement the plan in docs/" |
| Research / explore | (none — just do it) | "How does X work?" |

**Rules:**
1. Pick the FIRST matching row — don't deliberate
2. Invoke ONE skill at a time (skills chain to the next when needed)
3. After implementation, the Completion Gate applies (see below)

## State-Heavy Task Detection

After classifying the task type (above), check if it also involves complex state management.

**Compound signals (any ONE is sufficient):**
- Concurrent/async operations with ordering constraints
- Real-time updates where one operation's side effects affect others
- Constraint propagation (changing one value must update dependents)
- State machine with multiple transitions that must maintain invariants

**Supporting keywords (need 2+ alongside a compound signal):**
queues, dashboards, WebSockets, state machines, schedulers, concurrent, real-time

**When in doubt, classify as state-heavy.** The cost of a false positive is ~$0.40
for an extra review pass. The cost of a false negative is -15pp on a hard task.

**Decision point:** The agent reading this skill makes the classification at task start,
before invoking the first skill. Log the decision: "State-heavy: yes/no — [reason]".

If state-heavy: after implementation and first code review, run a SECOND
code review (see requesting-code-review skill, "Second-Pass Review").

## Completion Gate

**After ALL implementation work** — before claiming done, moving to next task, or committing:

1. Run the full verification suite fresh (test + build + lint)
2. Read COMPLETE output. Count failures.
3. If ANY failure: fix and re-run. Do NOT proceed.
4. Commit: `git add -A && git commit -m '<description>'`
5. Review your diff: `git diff HEAD~1`
6. Look for: missing edge cases, incomplete implementations, dead code, debug artifacts
7. If issues found: fix, re-verify, re-commit
8. Only stop when verification passes AND diff review is clean

Evidence before claims, always. "Should pass" is not evidence.

## Red Flags

These thoughts mean STOP — you're rationalizing:

| Thought | Reality |
|---------|---------|
| "This is just a simple question" | Questions are tasks. Check the table above. |
| "I need more context first" | Skill check comes BEFORE clarifying questions. |
| "Let me explore the codebase first" | Skills tell you HOW to explore. Check first. |
| "This doesn't need a formal skill" | If a skill exists, use it. |
| "I remember this skill" | Skills evolve. Read current version. |
| "The skill is overkill" | Simple things become complex. Use it. |
| "I'll just do this one thing first" | Check BEFORE doing anything. |

## Skill Types

**Rigid** (TDD, debugging): Follow exactly. Don't adapt away discipline.

**Flexible** (patterns): Adapt principles to context.

The skill itself tells you which.

## User Instructions

Instructions say WHAT, not HOW. "Add X" or "Fix Y" doesn't mean skip workflows.
