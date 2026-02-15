# Claude Squad — Orchestrator Survey

**Archetype:** Multi-instance orchestrator / Terminal agent manager
**Vendor:** smtg-ai
**Source:** Open-source (github.com/smtg-ai/claude-squad), AGPL-3.0
**Research date:** 2026-02-14
**Method:** GitHub README analysis, CLI documentation, architecture inspection

---

## 1. Architecture Type

**Terminal TUI that manages multiple AI agent instances in parallel tmux sessions with git worktree isolation.**

Claude Squad is a meta-orchestrator — it does not implement agent intelligence itself but manages multiple instances of existing agents (Claude Code, Aider, Codex, Gemini) running in parallel. Each agent operates in its own tmux session with its own git worktree, preventing cross-contamination between concurrent tasks.

The core architecture uses three technologies:
1. **tmux** — each agent instance runs in an isolated terminal session
2. **git worktrees** — each session gets its own branch and working directory
3. **TUI** — a unified terminal interface for managing all sessions

The workflow:
```
User creates session with prompt
  → cs spawns tmux session
  → git worktree created on new branch
  → Agent (claude, aider, etc.) launched inside tmux
  → Agent works autonomously (with --autoyes)
  → User can attach/detach, review diffs, push results
```

There is no coordination between sessions — each agent works independently on its assigned task. There is no consensus mechanism, no supervisor hierarchy, and no merge resolution. Claude Squad provides parallelism without orchestration intelligence.

**Key distinction from Gas Town:** Gas Town has a Mayor (planning coordinator), Witness (supervisor), and Refinery (merge agent). Claude Squad has none of these — it is a session manager, not an intelligent orchestrator. The user is the implicit coordinator.

**Key distinction from Conclave:** Conclave's parallel execution (subagent-driven-development) uses dependency-aware wave execution with squash-merge in plan order. Claude Squad has no dependency awareness — all sessions are independent.

## 2. Context Strategy

**Inherited from underlying agent. No additional context management.**

Claude Squad adds no context strategy of its own. Each agent instance maintains its own context window according to the agent's built-in behavior (e.g., Claude Code's compaction, Aider's repo map). The worktree isolation ensures agents don't see each other's in-progress work.

The git worktree approach provides natural fresh-context properties — each session starts with a clean context window focused on its specific task and branch.

## 3. Planning Approach

**None. No planning enforcement or coordination.**

Claude Squad does not enforce or even suggest a planning phase. Users create sessions with ad-hoc prompts. There is no decomposition step, no dependency analysis, and no plan document.

The implicit assumption is that the user has already decomposed work into independent tasks before creating sessions. If tasks have dependencies, the user must manually coordinate (e.g., merge one branch before starting the dependent task).

## 4. Edit Mechanism

**Inherited from underlying agent.**

Claude Squad does not participate in edits. The underlying agent (Claude Code, Aider, etc.) handles all code modifications within its tmux session and git worktree.

The `checkout` command commits pending changes and pauses the session. The `push` command commits and pushes to a remote branch. These are session lifecycle operations, not edit mechanisms.

## 5. Self-Correction

**Inherited from underlying agent. No additional review or correction layer.**

Claude Squad provides a diff view (toggled with Tab) that lets the user review changes before pushing, but this is a human review step, not automated self-correction.

There is no automated testing, no multi-agent review, and no quality gates. The quality of output depends entirely on the underlying agent's capabilities.

## 6. Gene List

### Genes Present

| Gene | Strength | Notes |
|------|----------|-------|
| **fresh-context** | Strong | Each tmux session gets a completely fresh context window. No stale context accumulation across sessions. |
| **tool-use** | Strong (inherited) | Whatever tools the underlying agent provides. Claude Code sessions get full tool access. |
| **iterative-refinement** | Moderate (inherited) | Through the underlying agent's loop. Claude Squad adds no refinement of its own. |
| **git-worktree-isolation** | Strong | Each session works in its own worktree on its own branch. Filesystem-level isolation. |

### Genes Absent

| Gene | Notes |
|------|-------|
| **multi-agent-consensus** | Sessions are independent. No voting, no agreement, no synthesis. |
| **cross-provider-consensus** | Can run different providers in different sessions, but they don't interact. |
| **ralph-loop** | No fresh-context restart pattern. Sessions run until the agent decides it's done. |
| **plan-before-code** | No planning enforcement whatsoever. |
| **repo-mapping** | Depends on underlying agent. |
| **auto-pilot-brainstorm** | No autonomous design exploration. |
| **self-review** | No self-review beyond what the underlying agent does. |
| **multi-agent-review** | Sessions don't review each other's work. |
| **test-first** | No TDD enforcement. |
| **prose-linting** | Not present. |

### New Genes Discovered

| Gene | Description |
|------|-------------|
| **tmux-session-orchestration** | Each agent runs in an isolated tmux session managed by a central TUI. Sessions can be created, attached, detached, paused (checkout), resumed, and deleted. This is lighter-weight than container-per-agent (Gas Town, OpenHands) but provides less isolation. |
| **auto-accept** | The `--autoyes` flag enables experimental automatic acceptance of all agent prompts, enabling fully autonomous background execution without human intervention. This converts interactive agents into batch processors. |

## 7. Benchmark-Relevant Traits

### Traits That Affect Task Design

1. **No headless/programmatic API.** Claude Squad is purely TUI-based. Benchmarking requires tmux scripting to create sessions and extract results. There is no `-p` pipe mode, no JSON output, and no structured metrics.

2. **Parallelism is user-decomposed.** Claude Squad benefits only from tasks that can be manually split into independent sub-tasks. For a single benchmark task, it runs a single agent instance — identical to running the underlying agent directly.

3. **No merge coordination.** If multiple sessions modify overlapping files, merging is the user's problem. This limits its effectiveness on tasks where parallel work touches shared code.

4. **`--autoyes` is experimental.** The auto-accept mode may have rough edges that affect benchmark reliability.

### Traits That Affect Measurement

5. **Token counting must aggregate across sessions.** Each tmux session has its own token usage. Total cost is the sum across all sessions plus any merge resolution overhead.

6. **Wall-clock time is the key metric.** Claude Squad's value proposition is wall-clock speedup through parallelism. The benchmark should measure both total token cost and wall-clock time to evaluate the parallelism tradeoff.

7. **No built-in metrics output.** Unlike Claude Code's `--output-format stream-json`, Claude Squad has no structured output. The adapter must extract metrics from each tmux session's underlying agent output.

### Scripting for Headless Benchmark Use

```bash
# Install
curl -fsSL https://raw.githubusercontent.com/smtg-ai/claude-squad/main/install.sh | bash

# Run with autoyes (single task — equivalent to bare Claude Code)
cs --autoyes

# Run with alternative agent
cs --autoyes -p "aider --model anthropic/claude-opus-4-6"
```

**Benchmark integration notes:**

- For single-task benchmarks, Claude Squad adds no value over running the underlying agent directly. Its advantage appears only when tasks can be decomposed into parallel sub-tasks.
- The adapter will need to: (a) start cs in the background, (b) create a session with the task prompt via tmux scripting, (c) wait for the agent to finish, (d) extract results from the worktree and agent output.
- Prerequisites: tmux, gh (GitHub CLI). Both must be available in the Docker image.

---

## Summary

Claude Squad is the lightest-weight multi-instance orchestrator in the survey. It provides tmux + git worktrees as a parallelism layer on top of existing agents, with no planning, no coordination, no review, and no consensus. The user is the orchestrator; Claude Squad is the session manager.

Its benchmark value is as a test of whether "just run N agents in parallel on independent tasks" is a competitive strategy against more sophisticated orchestration. On decomposable tasks (T7, T10), parallel Claude Code instances via Claude Squad could match or beat single-agent tools on wall-clock time while using similar total tokens. On sequential tasks (T3, T5) or tasks requiring coordination (T2, T6), it offers no advantage over its underlying agent.

Claude Squad vs. Gas Town is the purest test of "lightweight parallelism vs. supervised parallelism" — same fundamental approach (parallel agents on worktrees), but Gas Town adds Mayor planning, Witness supervision, and Refinery merge resolution at significantly higher cost.
