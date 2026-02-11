# Aider — Orchestrator Survey

**Tool:** Aider (https://aider.chat / https://github.com/paul-gauthier/aider)
**Archetype:** CLI turn-based
**Version surveyed:** Latest as of February 2026 (source: public docs, blog posts, GitHub source)

---

## 1. Architecture Type

**Single-agent loop with optional two-model delegation.**

Aider is fundamentally a single-agent REPL. The user types a request, the LLM responds with code edits, edits are applied, and the loop repeats. There is no multi-agent orchestration, no delegation tree, and no persistent background agents.

The one exception is **architect mode**, which introduces a sequential two-model pipeline:

1. An "architect" model receives the user request and produces a natural-language plan describing changes.
2. An "editor" model receives the architect's output and translates it into concrete file edits.

This is not multi-agent in the consensus or delegation sense -- it is a two-stage pipeline within a single turn. The architect never reviews the editor's output, and there is no negotiation loop between them.

**Modes of operation:**
- **Code mode** (default): LLM directly produces file edits.
- **Ask mode**: LLM answers questions without editing files.
- **Architect mode**: Two-model pipeline (plan then edit).
- **Help mode**: Answers questions about Aider itself.
- **Context mode**: Identifies which files are relevant to a request (used internally).

---

## 2. Context Strategy

Aider's context management is one of its most architecturally distinctive features.

### Repo Map (PageRank-based)

Aider builds a **repository map** using tree-sitter to parse all source files into ASTs, extracting symbol definitions (functions, classes, variables) and references. It then constructs a **graph** where:

- **Nodes** are source files.
- **Edges** connect files that reference each other's symbols, weighted by reference frequency (sqrt-normalized to prevent high-frequency terms from dominating).
- **Multipliers** boost edge weights for: symbols explicitly mentioned in the conversation (10x), camelCase/kebab-case identifiers >= 8 chars (10x). Underscore-prefixed names are reduced (0.1x).
- Files currently in the chat get a **50x personalization boost**.

The graph is then ranked using **NetworkX PageRank**. The top-ranked identifiers (with their function signatures and surrounding context lines) are included in the prompt, subject to a configurable token budget (default 1,024 tokens, adjustable via `--map-tokens`).

A **binary search** fits the output within the token budget -- iteratively testing tag counts and accepting results where token count is within 15% of target.

The map is cached and refreshed according to a configurable policy (`auto`, `always`, `files`, `manual`). When no files are explicitly added to the chat, the map expands to use more of the budget, providing broader context.

### Explicit File Management

Users manually add/remove files from the chat using `/add` and `/drop` commands. Added files are included in full (their complete contents go into the prompt). Read-only files (`/read-only`) provide reference context without edit permission.

### No Automatic Context Compression

Aider does **not** summarize, truncate, or rotate context automatically. When the context window fills up, it reports API errors and relies on the user to manually `/drop` files, `/clear` chat history, or reduce scope. This is a deliberate design choice -- the user retains full control over what is in context.

### Prompt Caching

For Anthropic and DeepSeek models, Aider organizes the prompt to exploit provider-level prompt caching: system prompt, read-only files, repo map, and editable files are structured as cacheable prefixes. A `--cache-keepalive-pings` option prevents cache expiration.

### Infinite Output (Prefill Continuation)

For models supporting prefill (Claude, DeepSeek, Mistral), when the LLM hits its output token limit mid-response, Aider initiates a new API call with the partial response prefilled, seamlessly continuing generation across multiple calls.

---

## 3. Planning Approach

**Minimal planning in default mode; explicit planning in architect mode.**

- In **code mode**, the LLM receives the user request and produces edits directly. There is no separate planning step. The user can optionally use `/ask` to discuss an approach before switching to `/code`, but this is manual, not automatic.
- In **architect mode**, the architect model produces a natural-language plan describing the solution approach. This plan is then passed to the editor model for implementation. This is the closest Aider comes to automatic plan-before-code.
- Aider's documentation recommends users "discuss a plan first" using `/ask` for complex tasks, but the tool does not enforce or automate this.

There is no persistent plan document, no plan revision loop, and no plan-vs-implementation consistency checking.

---

## 4. Edit Mechanism

Aider has invested heavily in edit format research and supports **six primary edit formats**, each suited to different LLM capabilities:

| Format | Mechanism | Use Case |
|--------|-----------|----------|
| **whole** | LLM returns complete updated file contents | Simple; works with weaker models |
| **diff** | SEARCH/REPLACE blocks with git-merge-conflict-style markers | Default for most models; efficient for small changes |
| **diff-fenced** | Same as diff but file path inside the fence | Adapted for Gemini models |
| **udiff** | Simplified unified diff (no line numbers) | Reduced "lazy coding" in GPT-4 Turbo |
| **editor-diff** / **editor-whole** | Streamlined variants for the editor model in architect mode | Less prompt overhead for the second-stage model |
| **patch** | Structured patch format | Alternative structured format |

Key architectural insights:
- Aider found that **plain-text edit formats consistently outperform JSON/structured output** for code. Models score measurably worse when asked to return code wrapped in JSON tool calls due to escaping complexity.
- The unified diff format was created specifically to combat GPT-4 Turbo's "lazy coding" tendency (replacing code with `// ... rest of implementation`), improving benchmark scores from 20% to 61%.
- Edit format selection is **per-model** -- Aider's model settings YAML maps each model to its best-performing edit format.
- Aider applies edits using fuzzy matching of the SEARCH blocks, not exact string matching, to tolerate minor LLM output imprecision.

---

## 5. Self-Correction

Aider has a structured auto-fix loop:

### Lint-Fix Loop
- By default, Aider **automatically lints every file it edits** after each LLM turn.
- Built-in linters exist for most popular languages; users can specify custom lint commands via `--lint-cmd`.
- If the linter reports errors, the errors are fed back to the LLM for correction.
- This repeats until clean or a retry limit is reached.

### Test-Fix Loop
- When configured with `--test-cmd` and `--auto-test`, Aider runs the test suite after each edit.
- If tests fail (non-zero exit code), the failure output is sent back to the LLM, which attempts a fix.
- This creates an iterative correction loop: edit -> test -> fix -> retest.

### No Self-Review
- Aider does **not** have the LLM review its own output for quality, design coherence, or correctness before committing.
- The architect model does not review the editor model's implementation.
- There is no "second opinion" or consensus mechanism.

### Git-Based Undo
- Every edit is auto-committed with a descriptive message.
- The `/undo` command reverts the last AI-generated commit, providing easy rollback.
- Pre-existing uncommitted changes are auto-committed first to keep AI edits separate.

---

## 6. Gene List

### Genes Present

| Gene | Strength | Notes |
|------|----------|-------|
| **repo-mapping** | Strong | Core differentiator. PageRank-based tree-sitter graph ranking, not simple file listing. |
| **iterative-refinement** | Moderate | Lint-fix and test-fix loops iterate until clean. Not open-ended multi-turn refinement. |
| **tool-use** | Weak | Can scrape web pages (`/web`), process images, run shell commands via `/run`. But the LLM cannot autonomously invoke tools -- it only suggests shell commands for the user to execute. |
| **plan-before-code** | Weak (opt-in) | Architect mode separates planning from editing. Not present in default code mode. |

### Genes Absent

| Gene | Notes |
|------|-------|
| **multi-agent-consensus** | No consensus mechanism. Single LLM (or sequential two-LLM pipeline). |
| **cross-provider-consensus** | Architect and editor can be different providers, but they do not produce competing solutions -- they are sequential, not parallel. |
| **ralph-loop** | No fresh-context rotation. Context accumulates within a session. Manual `/clear` is the only reset. |
| **fresh-context** | No automatic context refresh or rotation strategy. |
| **auto-pilot-brainstorm** | No autonomous brainstorming phase. |
| **self-review** | No LLM self-review step. |
| **multi-agent-review** | No review by a second agent. |
| **test-first** | Does not generate tests before implementation. Runs pre-existing tests. |
| **prose-linting** | No natural-language quality checks on commit messages, docs, etc. |

### New Genes Discovered

| Gene | Description |
|------|-------------|
| **edit-format-adaptation** | Dynamically selects the edit format (whole, diff, udiff, etc.) based on which model is being used. Different models have different strengths at structured output; Aider matches format to model capability. This is a form of prompt engineering that adapts the communication protocol to the LLM's tendencies. |
| **semantic-repo-indexing** | Goes beyond simple file listing or keyword search. Uses tree-sitter AST parsing + PageRank graph ranking to identify the most structurally important symbols in the codebase and include them in context. This is distinct from generic RAG. |
| **auto-commit-with-undo** | Every AI edit is automatically committed to git with a descriptive message. Combined with `/undo`, this creates a safe experimentation loop where any change can be instantly reverted. The separation of human commits from AI commits in git history is architecturally significant. |
| **infinite-output-continuation** | Transparently chains multiple LLM API calls via prefill to overcome output token limits. The LLM can produce arbitrarily long edits without the user noticing boundaries. |
| **watch-mode** | File system watcher detects `AI` comments in source files (placed by the user in their IDE) and triggers LLM action. Enables IDE-agnostic "inline AI prompting" without Aider being the active editor. |

---

## 7. Benchmark-Relevant Traits

### Traits That Affect Task Design

1. **Human-in-the-loop by default.** Aider expects the user to add/drop files, approve architect suggestions, and manage context. For benchmarking, it must be run in scripted/headless mode using `--message`, `--yes`, and potentially `--auto-test`. The `--yes` flag auto-approves confirmations. The Python API (`Coder.create()` + `coder.run()`) enables programmatic control but is officially unsupported.

2. **No autonomous file discovery.** Unlike tools that explore the filesystem, Aider relies on the repo map for awareness and explicit `/add` for editing. In a benchmark, either all relevant files must be pre-added, or the orchestrator adapter must handle the file management loop. The context coder mode can auto-identify files, but it requires an extra LLM call.

3. **Edit format affects success rate measurably.** The choice of edit format (whole vs. diff vs. udiff) changes benchmark outcomes by 10-40+ percentage points depending on the model. Any benchmark comparing Aider against other tools must specify which edit format and model combination is used, or results will not be reproducible.

4. **No built-in shell autonomy.** The LLM suggests shell commands but cannot execute them autonomously. For benchmarks requiring shell interaction (install dependencies, run builds), the harness must intercept and execute suggested commands, or use `/run` command piping.

### Traits That Affect Measurement

1. **Token efficiency is a core strength.** The repo map's PageRank ranking means Aider sends a very compact context representation. Token usage per task should be significantly lower than tools that include full file contents. This is directly measurable and should be tracked.

2. **Lint/test feedback loop inflates turn count.** The auto-lint and auto-test loops generate additional LLM calls that are invisible to the user but consume tokens and time. Turn count measurement must distinguish between "user turns" and "internal correction turns."

3. **Git commit granularity enables diff analysis.** Every edit is a separate commit, making it straightforward to measure: number of edit attempts, diff size per attempt, whether the final solution is minimal, and whether earlier attempts introduced regressions.

4. **No context endurance strategy.** For the marathon task (Task 5: 12-phase task queue), Aider will accumulate all 12 phases of conversation in context without summarization or rotation. It will likely hit context limits on smaller-window models. This directly tests H3 (fresh context vs. stale context).

5. **Architect mode is a distinct configuration.** Benchmarks should test Aider in both code mode and architect mode, as they are architecturally different approaches with different cost/quality tradeoffs.

6. **Auto-commit enables rollback measurement.** The git-based undo system means we can measure how often Aider's edits need to be reverted and re-attempted, providing a natural "rework rate" metric.

### Scripting for Headless Benchmark Use

```bash
# Single-message headless execution
aider --message "implement the feature described in TASK.md" \
      --yes \
      --auto-test \
      --test-cmd "npm test" \
      --auto-commits \
      --model claude-3.5-sonnet \
      src/*.ts

# Python API (unsupported but functional)
from aider.coders import Coder
from aider.models import Model

model = Model("claude-3.5-sonnet")
coder = Coder.create(
    main_model=model,
    fnames=["src/index.ts", "src/utils.ts"],
    auto_test=True,
    test_cmd="npm test",
)
coder.run("implement the feature described in TASK.md")
```

---

## Summary

Aider is the most architecturally transparent tool in the survey. Its key innovations are:

1. **PageRank-based repo mapping** -- a genuinely novel approach to context selection that uses graph theory rather than keyword search or embeddings.
2. **Edit format research** -- extensive empirical work showing that the format in which you ask an LLM to produce code edits matters as much as the model itself.
3. **Minimal abstraction** -- Aider does not hide complexity behind multi-agent orchestration. It is a well-instrumented single-agent loop with clear extension points (architect mode, lint/test loops).

Its weaknesses for our benchmarks are the lack of autonomous operation (human-in-the-loop context management), no context compression for long tasks, and no self-review or consensus mechanisms. It serves as an excellent **baseline single-agent tool** against which multi-agent consensus approaches can be compared.
