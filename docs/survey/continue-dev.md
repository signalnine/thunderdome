# Continue.dev — Orchestrator Survey

**Archetype:** IDE extension + CLI agentic (multi-surface)
**Vendor:** Continue (continuedev)
**Source:** Open-source (github.com/continuedev/continue)
**Research date:** 2026-02-11
**Method:** GitHub source code analysis, docs (docs.continue.dev), blog posts, CLI architecture inspection

---

## 1. Architecture Type

**Single-agent tool-calling loop with subagent spawning, operating across three surfaces: IDE extension (VS Code / JetBrains), TUI (terminal), and headless CLI for cloud/async agents.**

The core agent loop follows the standard pattern:

```
while (response contains tool_calls):
    execute tool calls (with permission checks)
    feed results back into conversation
    auto-compact if approaching context limit
    repeat
```

The loop is implemented in `extensions/cli/src/stream/streamChatResponse.ts`. On each iteration it:
1. Refreshes chat history from the ChatHistoryService
2. Recomputes available tools (tools can change mid-conversation based on mode switches)
3. Checks for pre-API compaction needs
4. Sends to LLM, streams response
5. Handles tool calls via `handleToolCalls.ts`
6. Checks post-tool context validation
7. Auto-compacts at 80% threshold if needed
8. Auto-continues after compaction (sends a "continue" message to avoid losing flow)

The loop terminates when the model produces a response with no tool calls.

**Three operating modes within the agent:**
- **Agent mode** — full tool access, read+write
- **Plan mode** — read-only tools only; the system message explicitly instructs the model not to circumvent restrictions. Used for investigation before committing to changes.
- **Chat mode** — pure conversation, no tools

Mode can be switched mid-session, and tools are recomputed each iteration to reflect the current mode.

**Subagents:** The CLI supports a `Subagent` tool that spawns child agent sessions. Subagents are configured in `config.yaml` with the `subagent` role and each gets its own system message, model, and fresh chat history. The parent agent invokes them by name with a prompt. Subagent results (the last assistant message) are returned to the parent. All tools are auto-allowed for subagents (no permission prompts). This is a depth-1 delegation pattern — no evidence of subagents spawning their own subagents.

**Headless mode:** The `-p` flag runs the agent non-interactively, suitable for CI/CD, scripts, Docker, and cloud-triggered automation. Headless mode supports JSON output (`--format json`), silent mode (`--silent`), and TTY-less environments. This is the foundation for "cloud agents" that run asynchronously and create PRs.

**Cloud agents (`cn serve`):** A server mode where the agent runs with an `--id` flag, reports status via API (`PLANNING`, `WORKING`, `DONE`, `BLOCKED`, `FAILED`), can upload artifacts, and reports failures. This enables the "Continuous AI" vision — agents triggered by external events (CI, webhooks, scheduled tasks).

## 2. Context Strategy

**Hybrid: on-demand tool-based search + optional RAG with embeddings + repo map + auto-compaction via summarization.**

Continue uses a multi-layered context strategy, significantly more varied than tools-only approaches:

**Tool-based search (runtime):**
- `read_file` / `read_file_range` — read files with optional line ranges
- `grep_search` — ripgrep-backed content search
- `file_glob_search` — glob pattern file discovery
- `ls` — directory listing
- `view_repo_map` — tree-sitter-based repository map (experimental)
- `view_subdirectory` — directory structure exploration
- `codebase` — semantic codebase search via embeddings (experimental)
- `search_web` — web search (signed-in users only)

**Context providers (pre-loaded, user-triggered via `@` mentions):**
A rich ecosystem of 30+ context providers including: `@codebase` (RAG), `@repo-map`, `@file`, `@folder`, `@code`, `@docs`, `@terminal`, `@diff`, `@git-commit`, `@problems`, `@open-files`, `@clipboard`, `@url`, `@web`, `@database`, `@postgres`, `@jira`, `@github-issues`, `@gitlab-mr`, `@discord`, `@google`, `@greptile`, plus custom HTTP and MCP context providers.

**Codebase indexing (background):**
Four index types are maintained:
1. **Full-text search (FTS)** — SQLite-based full-text index
2. **Embeddings / vector search** — LanceDB-backed vector index using configurable embedding models
3. **Code snippets** — tree-sitter-based code structure index (function/class signatures)
4. **Chunking** — document chunking for embedding pipeline

Indexing runs in the background with batch processing (200 files per batch), pause/resume support, and branch-aware tagging.

**Retrieval pipeline:**
The `@codebase` context provider uses a multi-signal retrieval pipeline (`RerankerRetrievalPipeline`):
1. Full-text search results
2. Embedding similarity results
3. Recently edited files
4. Repo map-based file suggestions (LLM-guided)
5. Optional: tool-based retrieval (experimental)

Results are deduplicated, filtered by directory if scoped, and optionally reranked. The pipeline targets filling half the context window, up to 25 snippets.

**Repo map:** Tree-sitter tag queries for 16 languages extract function/class signatures. The repo map is capped at 50% of model context length. Signatures are batched from a `CodeSnippetsIndex`. This is similar to Aider's repo-map approach.

**Compaction:** Auto-compaction triggers when input tokens approach `contextLimit - maxTokens - buffer` (buffer is min of 15k tokens or 20% of available space). The compaction prompt asks the model to summarize the conversation, preserving "key context, decisions made, and current state" and specifically "what the current stream of work was at the very end." After compaction, the system auto-sends a "continue" message to resume work without user intervention.

**System message context:** The CLI automatically injects:
- Directory structure snapshot (up to 500 files, respecting `.gitignore`/`.continueignore`)
- Git status snapshot
- Contents of `AGENTS.md`, `AGENT.md`, `CLAUDE.md`, or `CODEX.md` (first found)
- Rules from `config.yaml`
- Rules from `--rule` flags (can reference Hub-hosted rules)

## 3. Planning Approach

**Explicit plan mode with status tracking; no mandatory upfront planning.**

**Plan mode:** A dedicated permission mode where only read-only tools are available. The system message explicitly instructs: "You are operating in _Plan Mode_... You only have access to read-only tools and should not attempt to circumvent them to write / delete / create files." Plan mode is toggled by the user, not automatically engaged.

**Checklist tool:** The `writeChecklist` tool creates/updates markdown task checklists (`- [ ]` / `- [x]` format) visible to the user. This provides lightweight plan tracking during execution.

**Status tool (cloud agents):** Reports task status (`PLANNING`, `WORKING`, `DONE`, `BLOCKED`, `FAILED`) to an external API. The default status is `PLANNING` before the agent sets a different one, suggesting an expected planning-first workflow.

**Skills as procedural plans:** Skills (markdown files with structured instructions) provide pre-written plans for specific tasks. The agent reads a skill via the `read_skill` tool and follows its instructions. This is effectively a form of externalized planning.

No evidence of automatic plan-then-execute patterns like some tools (e.g., Devin). Planning is user-driven or embedded in skills/rules.

## 4. Edit Mechanism

**Dual-strategy: search-and-replace for CLI/standard models, lazy-apply diff for IDE extension. Model-dependent tool selection.**

**Search-and-replace (primary for CLI and non-recommended models):**
Three tools in order of capability:
1. `single_find_and_replace` — exact string match with `old_string`/`new_string`/`replace_all`. Validates uniqueness. Requires prior `read_file`.
2. `multi_edit` — array of sequential find-and-replace operations on a single file. Atomic (all or nothing). Reserved for "recommended agent models" only.
3. `edit_existing_file` — the model outputs the changes with `// ... existing code ...` placeholders for unchanged sections. A secondary LLM pass (the "lazy apply" system) fills in the unchanged regions.

The tool selection logic in `core/tools/index.ts` is model-dependent:
```typescript
if (isRecommendedAgentModel(modelName)) {
    tools.push(multiEditTool);
} else {
    tools.push(editFileTool);
    tools.push(singleFindAndReplaceTool);
}
```

**Lazy apply (IDE extension edit mode):**
For the `edit_existing_file` tool, the system uses a two-pass approach:
1. The model generates code with `// ... existing code ...` (or equivalent) markers
2. A secondary LLM call (`streamLazyApply`) fills in the gaps by applying the new code to the original, generating a streaming diff

This uses model-specific prompts (currently only Claude Sonnet has a dedicated prompt). The output is streamed as diff lines for inline display in the editor.

**Streaming diff:** `streamDiffLines.ts` converts model output into a line-by-line diff stream, handling code block filtering, whitespace normalization, and language-appropriate comment stripping.

**Write tool (CLI):** A separate `writeFile` tool exists for creating new files.

**Critical constraint:** All edit tools include `NO_PARALLEL_TOOL_CALLING_INSTRUCTION` — they cannot be called in parallel with any other tools, preventing race conditions on file writes.

## 5. Self-Correction

**Tool error feedback loop. No explicit self-review or test-running patterns.**

**Error feedback:** The architecture feeds tool execution errors back into the model's context automatically. From the docs: "data returned from a tool call is automatically fed back into the model as a context item," including caught errors. This enables the model to adapt its approach on failure.

**Edit validation:** The search-and-replace tools validate edits before applying:
- Filepath validation and resolution
- Uniqueness check for `old_string` (fails if not unique without `replace_all`)
- Content mismatch detection (fails if file has changed since last read)
- Multi-edit atomicity (all edits must succeed or none apply)

**File-read requirement:** Both CLI and IDE edit tools enforce that the agent must `read_file` before editing. The CLI tracks read files in a `readFilesSet` and rejects edits on unread files. This prevents blind edits.

**Report failure (cloud agents):** The `reportFailure` tool allows the agent to explicitly signal unrecoverable errors, which triggers a status update and marks the agent session as complete.

**Context overflow recovery:** Post-tool-call validation checks if the context window has been exceeded. If so, compaction is triggered before the next LLM call, preventing hard failures.

**No explicit test-running pattern:** Unlike Claude Code (which has a documented test-loop gene), Continue does not have a built-in "run tests and fix" cycle. The agent can run terminal commands (including test suites) via `run_terminal_command`, but there is no system-level orchestration that automatically runs tests after edits. Test execution depends entirely on model initiative or skill instructions.

## 6. Gene List

### Genes present:

| Gene | Evidence |
|------|----------|
| **tool-use** | Core architecture — 20+ built-in tools, MCP integration, tool policies |
| **repo-mapping** | Tree-sitter-based repo map with 16 language support via `view_repo_map` tool and `@repo-map` context provider |
| **iterative-refinement** | Agent loop continues until model stops calling tools; error feedback enables retry |
| **plan-before-code** | Weak/optional — Plan mode exists but is user-toggled, not automatic. Status tool defaults to PLANNING. |
| **fresh-context** | Subagents get fresh context windows; compaction with auto-continuation resets context mid-task |
| **self-review** | Absent as explicit pattern — no built-in "review my own output" step. `cn check` provides external agent-based review. |

### Genes absent:

| Gene | Status |
|------|--------|
| **multi-agent-consensus** | Not present. Subagents are delegated tasks, not parallel consensus voters. |
| **cross-provider-consensus** | Not present. Multi-model support exists but for role assignment (chat, embed, autocomplete, subagent), not consensus. |
| **ralph-loop** | Not present. No automatic fresh-context restart pattern. Compaction + auto-continue is the closest analog. |
| **auto-pilot-brainstorm** | Not present. |
| **multi-agent-review** | Partially present via `cn check` — multiple independent agents review code changes in parallel, but this is a separate workflow, not integrated into the edit loop. |
| **test-first** | Not present as system pattern. |
| **prose-linting** | Not present. |

### NEW genes not in the standard list:

| Gene | Description |
|------|-------------|
| **skill-injection** | Pre-authored markdown instructions (skills) that the agent reads on-demand to learn task-specific procedures. Skills include step-by-step instructions, file references, and constraints. Found in both IDE (`SKILL.md` files) and CLI (`skills/` directory). |
| **rule-injection** | Declarative rules (from `config.yaml`, `--rule` flags, Hub-hosted rules, and `AGENTS.md`/`CLAUDE.md` files) injected into system messages. Rules encode team standards, security requirements, and coding conventions. |
| **mode-switching** | The agent can switch between Agent/Plan/Chat modes mid-session, with tools dynamically recomputed. This is distinct from plan-before-code — it is a user-driven capability toggle. |
| **multi-surface-agent** | The same agent core runs across IDE, TUI, and headless environments with different capabilities in each. Cloud agents add status reporting, artifact upload, and failure reporting tools. |
| **background-agent** | Async agent execution triggered by external events (CI, webhooks, schedules) via `cn serve`. The agent runs unattended, reports status, creates PRs, and uploads artifacts for later human review. |
| **parallel-agent-review** | `cn check` runs multiple independent agent instances in parallel (separate git worktrees), each reviewing code changes from a different perspective (security, style, docs). Results are aggregated. |
| **compaction-with-continuation** | After auto-compaction, the system automatically injects a "continue" message to resume work, preventing the agent from stopping mid-task due to context pressure. |
| **model-adaptive-tooling** | Tool selection varies by model capability — "recommended agent models" get `multi_edit`, others get `single_find_and_replace` + `edit_existing_file`. |
| **checklist-tracking** | The `writeChecklist` tool creates visible task checklists that serve as lightweight plans and progress indicators. |

## 7. Benchmark-Relevant Traits

### Task design implications:

1. **Multi-surface variability:** The same task can yield different results depending on surface (IDE vs CLI vs headless). Benchmarks should specify which surface is being tested. The CLI headless mode is the most automation-friendly for benchmarking.

2. **Configuration-heavy:** Agent behavior is heavily influenced by `config.yaml` (model selection, rules, tools, MCP servers, skills). Benchmarks must standardize configuration or treat it as a variable.

3. **No automatic test loop:** Unlike Claude Code, Continue does not have a built-in pattern for running tests after edits. Tasks that require test-driven development will depend on model initiative or explicit skill instructions. This is a measurable differentiator.

4. **RAG availability affects performance:** The optional embeddings/FTS indexes can significantly change codebase search quality. Benchmarks should test with and without indexing enabled (`disableIndexing` flag exists).

5. **Model-dependent behavior:** Tool selection, lazy-apply support, and agent capability all vary by model. The same task with different models will exercise different code paths.

### Measurement considerations:

6. **Token counting is built-in:** The system tracks `promptTokens`, `completionTokens`, `cachedTokens`, `cacheWriteTokens`, and total cost per session. Session usage is tracked via `SessionManager`.

7. **Compaction events as a signal:** The number of compaction events indicates context pressure. Tasks that trigger more compactions may indicate less efficient context usage or longer task chains.

8. **Permission system affects autonomy:** In headless mode, all tools can be auto-allowed. In interactive mode, the permission system introduces human-in-the-loop friction. Benchmarks should use headless mode with `allow` policies for fair comparison.

9. **Status reporting (cloud agents):** The `PLANNING`/`WORKING`/`DONE`/`BLOCKED`/`FAILED` status transitions provide structured progress signals that could be used for benchmark instrumentation.

10. **Subagent delegation as a strategy:** Tasks complex enough to trigger subagent delegation will test the orchestration overhead. The depth-1 limit means no recursive delegation.

11. **Parallel check agents:** `cn check` provides a unique benchmark angle — multiple agents reviewing the same code simultaneously. This could be compared against single-agent self-review patterns.

### Distinctive strengths to probe:

- **Retrieval-augmented context** — Tasks where finding the right code matters more than editing it should favor Continue's RAG pipeline over tools-only approaches.
- **Skill-driven tasks** — Tasks with pre-authored skills should show whether procedural instruction-following outperforms free-form problem solving.
- **Long-running tasks** — The compaction-with-continuation pattern should handle marathon tasks better than naive context management, but may lose nuanced early context.
- **Multi-file coordination** — The `multi_edit` tool and atomic edit validation should help with complex refactoring tasks.
