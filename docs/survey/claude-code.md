# Claude Code — Orchestrator Survey

**Archetype:** CLI agentic
**Vendor:** Anthropic
**Source:** Open-source (github.com/anthropics/claude-code)
**Research date:** 2026-02-11
**Method:** Public docs (code.claude.com), blog posts, GitHub issues, reverse-engineered system prompts

---

## 1. Architecture Type

**Single-agent loop with optional subagent spawning and experimental multi-agent teams.**

The core is a single-threaded master loop (internally codenamed "nO") following the pattern:

```
while (response contains tool_call):
    execute tool
    feed result back into conversation
    repeat
```

The loop terminates when the model produces a text response without tool invocations. One flat message history is maintained — no threaded conversations. This design explicitly prioritizes debuggability over multi-agent complexity.

A real-time steering queue ("h2A") allows user interjections mid-loop without restarting the agent, making it a truly interactive streaming agent rather than a batch processor.

**Subagents:** The `Task` / `dispatch_agent` tool spawns child agents with their own isolated context windows. Subagents cannot spawn their own subagents (depth=1 limit). Built-in subagents include:
- **Explore** — fast read-only agent (runs on Haiku) for codebase search
- **Plan** — research agent for plan mode context gathering
- **General-purpose** — full-tool agent for complex delegation

**Agent Teams (experimental):** Multiple independent Claude Code sessions coordinated by a lead agent. Teammates have their own context windows, communicate via a mailbox system, and share a task list with file-locking for concurrent claim. This is distinct from subagents — teammates can message each other directly rather than only reporting to a parent. Currently gated behind `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS`.

## 2. Context Strategy

**On-demand search with automatic compaction. No pre-built index, no embeddings, no RAG.**

Claude Code does not build a repo map, vector index, or embedding database. Instead, it discovers codebase structure at runtime using:
- **Glob** — file pattern matching
- **Grep** (ripgrep-backed) — regex content search
- **Read** — read files (~2000 lines default, with offset/limit)
- **LS** — directory listing
- **Bash** — arbitrary shell commands (e.g., `git log`, `find`, language-specific tools)

Anthropic's stated design principle: "choose regex over embeddings for search, Markdown files over databases for memory."

**Context compaction:** The "Compressor wU2" system auto-triggers at ~92-98% context utilization (sources vary; the threshold may have changed across versions). It summarizes the conversation, drops older tool outputs first, then summarizes if needed. User requests and key code snippets are preserved; detailed early-conversation instructions may be lost.

Manual compaction via `/compact` can be invoked at any time, optionally with a focus directive (e.g., `/compact focus on the API changes`).

**Persistent memory:** `CLAUDE.md` files (project root, nested directories, user-level) are loaded at session start and injected into every request. These serve as the primary cross-session memory mechanism. An "auto memory" feature can also persist learnings automatically.

**Subagent context isolation:** Each subagent gets a fresh context window. Only the summary/result returns to the parent, preventing context bloat from verbose operations (test output, large searches).

## 3. Planning Approach

**Hybrid: optional upfront plan mode + in-loop TODO tracking.**

**Plan mode (user-toggled):** Activated via `Shift+Tab` twice. In this mode, all write tools (Edit, Write, Bash with side effects) are blocked. Claude can only read, search, and analyze. It produces a plan with affected files and trade-offs. The user reviews and approves before Claude exits plan mode and begins implementation.

**TodoWrite (in-loop planning):** For multi-step tasks (3+ actions), Claude creates structured JSON task lists with fields: `id`, `content`, `activeForm`, `status` (pending/in_progress/completed), `priority` (high/medium/low). The system injects current TODO state after each tool use to prevent model drift during long conversations. Only one task may be `in_progress` at a time.

**Agent teams planning:** The lead agent can require plan approval from teammates before they implement — the teammate works in read-only mode until the lead approves the plan.

**No mandatory upfront planning.** For simple tasks, Claude jumps straight to implementation. For complex tasks, the model decides whether to plan based on context. The user can force planning via plan mode or prompt instructions.

## 4. Edit Mechanism

**Search-and-replace (primary) with whole-file fallback.**

Two editing tools:

| Tool | Mechanism | When used |
|------|-----------|-----------|
| **Edit** | Exact string match replacement (`old_string` -> `new_string`). Fails if `old_string` is not unique. Has `replace_all` flag for bulk renames. | Primary — surgical, minimal diffs |
| **MultiEdit** | Multiple find-and-replace operations on a single file, applied atomically. All-or-nothing. | Multiple related edits in one file |
| **Write** | Whole-file overwrite. Requires reading the file first if it exists. | New file creation, or complete rewrites |

The system prompt instructs Claude to prefer Edit over Write for existing files. The diffs-first approach "naturally promotes test-driven development — Claude can run tests, see failures, and iterate on fixes, all while keeping changes transparent and contained."

**Not AST-aware.** Edits operate on raw text, not syntax trees. The exact-string-match requirement forces Claude to read the file first and match indentation precisely.

## 5. Self-Correction

**Yes — test-driven verification loop is the primary self-correction mechanism.**

The three-phase agentic loop is: gather context -> take action -> verify results. These phases blend and repeat. Verification typically means:

1. **Run tests** — Claude runs the test suite after making changes, reads failures, and iterates
2. **Run build/lint** — TypeScript compilation errors and lint warnings feed back into the loop
3. **Re-read edited files** — Claude can re-read files to verify edits applied correctly
4. **Command output inspection** — any shell command output (error messages, stack traces) feeds back as context

There is no formal "self-review" step where a separate model or prompt reviews the output. However:
- The agent naturally reviews its own changes through the test/build/lint cycle
- Subagents can be configured as dedicated code reviewers (built-in or custom)
- Agent teams can be set up with adversarial review (teammates challenging each other's work)

**Retry behavior:** The loop inherently retries — if tests fail, Claude reads the errors and attempts a fix. There is no explicit retry limit in the core loop; it continues as long as the model produces tool calls. The `maxTurns` setting on subagents can impose a limit.

## 6. Gene List

### Genes Present

| Gene | Strength | Notes |
|------|----------|-------|
| **tool-use** | Strong | Core architecture. Rich tool set: file ops, search, shell, web fetch, code intelligence plugins. |
| **iterative-refinement** | Strong | The agentic loop is fundamentally iterative — edit, test, fix, repeat. |
| **self-review** | Moderate | Via test/build/lint feedback loop. No dedicated self-review prompt, but the verify phase serves this function. |
| **plan-before-code** | Optional | Plan mode available but not default. TodoWrite provides lightweight in-loop planning. |
| **repo-mapping** | Weak/Absent | No pre-built repo map or index. Uses on-demand search (Grep/Glob) instead. Community plugins (PROJECT_INDEX, claude-context) can add this. |
| **fresh-context** | Present | Subagents get fresh context windows. Agent teams give each teammate independent context. Compaction provides a form of context refresh. |
| **multi-agent-review** | Optional | Achievable via custom subagents or agent teams configured as reviewers. Not default behavior. |
| **multi-agent-consensus** | Experimental | Agent teams can investigate competing hypotheses and debate. Not the default single-agent mode. |
| **cross-provider-consensus** | Absent | Claude Code only uses Claude models (Sonnet, Opus, Haiku). No cross-provider support. |
| **ralph-loop** | Absent | No built-in subagent execution loop pattern. Could be approximated by chaining subagents from the main conversation. |
| **auto-pilot-brainstorm** | Present | Headless mode (`claude -p`) and `bypassPermissions` enable fully autonomous operation without human gates. |
| **test-first** | Not default | Claude can be instructed to write tests first, and it naturally runs tests for verification, but TDD is not the default behavior. |
| **prose-linting** | Absent | No built-in documentation quality rules. Could be added via CLAUDE.md instructions or skills. |

### New Genes Discovered

| Gene | Description |
|------|-------------|
| **context-compaction** | Automatic summarization when context window fills (~92-98%), preserving key information while dropping verbose tool outputs. Distinct from fresh-context (which discards everything) — this is selective compression. |
| **persistent-project-memory** | CLAUDE.md files persist instructions and conventions across sessions without consuming runtime context until loaded. A static, human-authored knowledge base rather than dynamic RAG. |
| **human-in-loop-steering** | Real-time interjection queue allowing course correction mid-loop without restart. The user is part of the loop, not just at approval gates. |
| **permission-gated-execution** | Graduated permission system (default -> auto-accept edits -> plan mode -> delegate mode -> bypass). Affects benchmark design because different permission modes change the agent's autonomy profile. |
| **subagent-delegation** | Spawning child agents with isolated context, restricted tool access, and configurable models. Depth-limited (no recursive spawning). Key for context management on large tasks. |
| **skill-injection** | On-demand loading of domain-specific instruction packages. Progressive disclosure: skill descriptions visible at startup, full content loaded only when invoked. |
| **checkpoint-rewind** | File snapshots before every edit, enabling rollback to any prior state. Safety net that changes error recovery dynamics. |

## 7. Benchmark-Relevant Traits

### Task Design Implications

- **No repo map means cold-start search overhead.** On large codebases (features/complex, bugfix tasks), Claude must spend tokens discovering file locations. This is measurable and distinguishes it from tools with pre-built indexes (e.g., Aider's repo-map).

- **Edit mechanism matters for diff-size constraints.** Task 4 (Phantom Invoice Bug) enforces a 20-line diff limit. Claude's Edit tool naturally produces minimal diffs, which is an advantage over whole-file rewrite tools.

- **Compaction affects marathon tasks.** Task 5 (12-phase Task Queue) is explicitly designed to test H3 (context endurance). Claude's compaction system will trigger during this task, and measuring what information survives compaction is directly relevant.

- **Permission modes affect automation.** For benchmark harness integration, use headless mode (`claude -p`) with `--allowedTools` to pre-approve operations. The `--dangerously-skip-permissions` flag or `bypassPermissions` mode removes all gates for fully autonomous runs.

- **Subagent spawning is non-deterministic.** Claude decides when to delegate to subagents. The Explore subagent (running on Haiku) may handle initial codebase discovery, meaning the search quality varies by which model does the searching. This introduces variance across runs.

### Measurement Considerations

- **Token counting:** Claude Code uses multiple models in a single session (Haiku for Explore subagent, Sonnet/Opus for main loop). Token costs must account for all models used. The SDK/headless mode returns session IDs and can stream JSON with token usage.

- **Turn counting:** Each tool call is one "turn" in the loop. The loop can chain dozens of actions. The TodoWrite tool provides a machine-readable planning trace that could be parsed to understand the agent's task decomposition.

- **Context window utilization:** The `/context` command or `CLAUDE_AUTOCOMPACT_PCT_OVERRIDE` env var can control compaction threshold. For marathon benchmarks, logging compaction events reveals when and what information is lost.

- **Non-determinism:** Same prompt, same codebase can produce different tool sequences. Multiple trials are essential. The session system enables exact replay investigation but not deterministic replay.

- **Agent teams token cost:** Agent teams use significantly more tokens than single-session work. Each teammate is a separate Claude instance. For cost comparison benchmarks, single-session mode should be the default, with agent teams as a separate "gene" to test.

### Headless/SDK Integration

Claude Code can be run programmatically:
- CLI: `claude -p "task description" --output-format stream-json --allowedTools Edit,Write,Bash,Read,Grep,Glob`
- Python SDK: `claude-agent-sdk-python`
- TypeScript SDK: `@anthropic-ai/claude-code`
- Output: streamed JSON with tool calls, results, and final output
- Session management: session IDs for resume/fork

This makes harness integration straightforward. The JSON streaming output provides fine-grained trace data for metrics collection.

---

## Sources

- [Claude Code overview — official docs](https://code.claude.com/docs/en/overview)
- [How Claude Code works — official docs](https://code.claude.com/docs/en/how-claude-code-works)
- [Create custom subagents — official docs](https://code.claude.com/docs/en/sub-agents)
- [Orchestrate teams of Claude Code sessions — official docs](https://code.claude.com/docs/en/agent-teams)
- [Claude Code: Behind-the-scenes of the master agent loop — PromptLayer](https://blog.promptlayer.com/claude-code-behind-the-scenes-of-the-master-agent-loop/)
- [Claude Code Agent Architecture: Single-Threaded Master Loop — ZenML](https://www.zenml.io/llmops-database/claude-code-agent-architecture-single-threaded-master-loop-for-autonomous-coding)
- [Claude Agent Skills: A First Principles Deep Dive — Lee Han Chung](https://leehanchung.github.io/blogs/2025/10/26/claude-skills-deep-dive/)
- [Claude Code system prompts and tool descriptions — GitHub Gist](https://gist.github.com/wong2/e0f34aac66caf890a332f7b6f9e2ba8f)
- [TodoWrite tool description — Piebald-AI](https://github.com/Piebald-AI/claude-code-system-prompts/blob/main/system-prompts/tool-description-todowrite.md)
- [anthropics/claude-code — GitHub](https://github.com/anthropics/claude-code)
- [Run Claude Code programmatically — official docs](https://code.claude.com/docs/en/headless)
