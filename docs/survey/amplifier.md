# Amplifier — Orchestrator Survey

**Tool:** Amplifier (https://github.com/microsoft/amplifier)
**Archetype:** Modular multi-agent kernel with delegated sub-sessions
**Version surveyed:** Latest as of February 2026 (source: public docs, GitHub repos, official docs site)

---

## 1. Architecture Type

**Micro-kernel with swappable orchestrators and delegated specialist agents.**

Amplifier follows a Linux kernel-inspired design. The core (`amplifier-core`) is an ultra-thin kernel of approximately 2,600 lines of Python that provides module protocols, session lifecycle management, an event system, and hook dispatch. Everything else -- providers, tools, orchestrators, context managers, agents, hooks -- lives outside the kernel as swappable modules with stable contracts.

The kernel's design principle is "mechanism, not policy." It provides the infrastructure for loading modules, coordinating sessions, emitting events, and managing context, but never dictates which modules to load, which LLM to use, or how to orchestrate. The litmus test the project uses: "Could two teams want different behavior? If yes, it belongs in a module, not the kernel."

The system comprises several separate repositories:

- **amplifier-core**: The kernel itself. Module protocols (Python structural typing via `Protocol`), session lifecycle, coordinator injection.
- **amplifier-foundation**: Bundle composition library. Loads, merges, and validates YAML/Markdown bundle configurations.
- **amplifier-profiles** (formerly amplifier-foundation content): Reusable agent definitions, behaviors, context files, and provider configs.
- **amplifier-app-cli**: Reference CLI implementation built on core and foundation.
- **amplifier-collection-toolkit**: Utilities for building multi-stage "recipe" tools.

**Session lifecycle** follows a three-phase pattern: `initialize()` -> `execute()` -> `cleanup()`. A session is an execution context containing mounted modules and conversation state, compiled from a "Mount Plan" -- a configuration dictionary specifying which modules to load and their settings.

**Orchestrator flexibility** is a first-class design goal. The orchestrator module is swappable: sequential planners, parallel planners, chain-of-thought voters, basic loops, and streaming loops can all be substituted without changing the core. Available orchestrator configurations include `loop-basic`, `loop-streaming`, and event-based variants.

This is fundamentally different from tools like Aider (single-agent loop) or Claude Code (single-agent with tool use). Amplifier is a platform for composing arbitrary agent topologies, not a fixed agent architecture.

---

## 2. Context Strategy

Amplifier's context management operates at two levels: within a session and across sessions.

### Within-Session Context Management

The kernel defines a `ContextManager` protocol with three methods: `add_message()`, `get_messages()`, and `compact()`. The default implementations include "simple" (in-memory) and "persistent" (survives across invocations) context managers. When the context window fills, Amplifier automatically compacts by preserving system instructions, recent conversation turns, and tool call pairs while compressing older messages. This is automatic, not user-managed.

### Agents as Context Sinks

This is Amplifier's most architecturally distinctive context pattern. Rather than loading all documentation and knowledge into the parent session (which would bloat the context window), heavy documentation is co-located with specialist agent definitions. When an agent is spawned, its full documentation loads into the sub-session. The parent session carries only thin "awareness pointers" (approximately 30 lines) that signal to the LLM which domains exist and which agents to delegate to.

This creates a deliberately asymmetric architecture:
- **Parent sessions stay lean**: Only thin pointers to agent capabilities.
- **Sub-sessions burn context doing focused work**: Heavy docs load on demand.
- **Token efficiency**: Documentation materializes only when the relevant specialist is invoked.

### Session Persistence

Sessions are automatically saved project-scoped and can be resumed with full context via `amplifier continue` or `amplifier session resume <id>`. This enables multi-session workflows where knowledge accumulates across interactions.

### Bundle-Level Context Composition

Context files are included in bundles via two mechanisms:
- **`context.include`**: YAML-level file path resolution for programmatic composition.
- **`@mentions`**: Text substitution in Markdown bodies (`@namespace:context/file.md`) for narrative documentation.

A `ContentDeduplicator` prevents the same content from being loaded multiple times when multiple bundles or agents reference the same documentation.

### No Repo Mapping

Unlike Aider's PageRank-based repository map, Amplifier does not appear to build an automatic structural index of the codebase. Context selection is driven by agent delegation (the right agent loads the right docs) and explicit file operations via tools, not by AST-level analysis of the repository.

---

## 3. Planning Approach

**Implicit planning via agent delegation and configurable orchestrators.**

Amplifier does not have a single hardcoded planning step. Instead, planning behavior emerges from the combination of:

1. **Specialist agent delegation**: The `zen-architect` agent is specifically designed for system design and architecture planning. When the LLM determines a task requires architectural thinking, it delegates to zen-architect, which runs in its own sub-session with architecture-specific documentation and instructions. This is an organic plan-before-code pattern, but it is LLM-initiated rather than structurally enforced.

2. **Swappable orchestrators**: Because orchestrators are modules, a "planning orchestrator" that enforces plan-then-implement sequencing could be mounted without changing any other component. The architecture explicitly supports sequential planners, parallel planners, and chain-of-thought voters as orchestrator types.

3. **Multi-stage recipe tools**: The `amplifier-collection-toolkit` demonstrates a "metacognitive recipe" pattern where code (not the LLM) orchestrates multiple AI sessions across specialized stages: "Analyze (precise) -> Simulate (empathetic) -> Diagnose (critical) -> Plan [HUMAN APPROVAL] -> Implement (creative) -> Evaluate." Each stage uses optimized configurations rather than a single model compromise. This represents explicit, code-driven planning with human approval gates.

4. **Outlines directory**: The repository includes an `outlines/` directory suggesting template-driven planning structures, though details are limited in public documentation.

There is no evidence of a persistent plan document, plan revision loop, or plan-vs-implementation consistency checking as a built-in kernel feature. Planning is delegable, not mandatory.

---

## 4. Edit Mechanism

**Standard file-system tools with module-level flexibility.**

Amplifier's edit mechanism is tool-based. The default foundation bundle provides a `tool-filesystem` module that exposes `read_file`, `write_file`, and `edit_file` operations. A `tool-bash` module provides shell command execution. These are invoked by the LLM through the standard tool-use protocol.

Key differences from other tools:

- **No specialized edit formats**: Unlike Aider's six edit formats (whole, diff, udiff, etc.), Amplifier relies on standard tool-call-based file operations. The LLM reads files, decides on changes, and writes/edits them through tool invocations. There is no SEARCH/REPLACE block format or unified diff protocol.

- **Tool-call, not plain-text**: Where Aider found that plain-text edit formats outperform JSON/structured output for code edits, Amplifier uses the standard structured tool-call interface. This is a deliberate tradeoff: structured tool calls are more reliable for tool dispatch and orchestration, even if they may sacrifice some editing precision.

- **Agent-scoped tool access**: Different agents can have different tool sets. An inline agent definition can specify exactly which tools it has access to, meaning a "read-only explorer" agent can be restricted from write operations while a "modular-builder" agent gets full filesystem access.

- **No edit-format-per-model adaptation**: Because editing goes through tool calls rather than text formats, there is no per-model edit format selection. The same tool interface works across all providers.

The absence of specialized edit format research is notable. Aider's empirical work showed that edit format choice affects benchmark success rates by 10-40+ percentage points. Amplifier sidesteps this by using the provider's native tool-call mechanism, which may limit performance on models where structured output quality is lower.

---

## 5. Self-Correction

**Delegated self-correction through agent specialization and hook-based observability.**

Amplifier's self-correction capabilities are architecturally distributed rather than built into a single loop:

### Bug-Hunter Agent

A dedicated `bug-hunter` agent specializes in systematic debugging. When the LLM detects errors or test failures, it can delegate to bug-hunter, which runs in its own sub-session with debugging-specific documentation and tools. This is more powerful than a simple retry loop because the debugging agent carries specialized knowledge, but it requires the orchestrating LLM to recognize when delegation is appropriate.

### Hook System

The kernel's hook protocol (`__call__(event, data) -> HookResult`) provides interception points for observability and control. Hooks can implement logging, redaction, approval gates, and scheduling. An approval hook can require human confirmation before certain operations proceed, providing a manual self-correction checkpoint. Hook results can modify execution flow, enabling automated correction patterns.

### No Built-In Lint/Test Loop

Unlike Aider's automatic lint-fix and test-fix loops, Amplifier does not appear to have a built-in mechanism that automatically runs linters or tests after each edit and feeds failures back to the LLM. The `tool-bash` module can execute test commands, but automated test-then-fix cycling would need to be implemented as an orchestrator module or behavior rather than being a default feature.

### No Self-Review Protocol

There is no documented mechanism for the LLM to review its own output before committing changes. The multi-agent architecture could support this (a "reviewer" agent could inspect changes produced by a "builder" agent), but this is not a built-in pattern in the default foundation bundle.

### Human Approval Gates

The collection toolkit pattern includes explicit `[HUMAN APPROVAL]` stages in multi-stage workflows, providing external correction checkpoints. This is more explicit than implicit self-correction but requires human presence.

---

## 6. Gene List

### Genes Present

| Gene | Strength | Notes |
|------|----------|-------|
| **tool-use** | Strong | First-class tool protocol with filesystem, bash, web, search, and task delegation modules. LLM autonomously invokes tools through structured calls. Tools are extensible and agent-scoped. |
| **plan-before-code** | Moderate | zen-architect agent provides organic planning when delegated to. Multi-stage recipes enforce explicit planning stages. Not structurally mandatory in default mode. |
| **iterative-refinement** | Moderate | Agent delegation enables multi-turn refinement (build, then debug via bug-hunter). Orchestrator loop repeats until task completion. No automatic lint/test feedback loop. |
| **fresh-context** | Moderate | Agent sub-sessions inherently provide fresh context -- each specialist starts with its own clean context plus relevant documentation. Parent session context does not bleed into sub-sessions except through explicit handoff. |
| **auto-pilot-brainstorm** | Weak | The explorer agent performs "breadth-first exploration" of code, docs, and files. Web-research agent can investigate external resources. Neither is a structured brainstorming phase. |
| **repo-mapping** | Weak | The explorer agent can analyze codebases and produce citation-ready summaries, but there is no automatic structural index like Aider's PageRank-based repo map. File discovery is tool-driven, not graph-driven. |

### Genes Absent

| Gene | Notes |
|------|-------|
| **multi-agent-consensus** | No mechanism for multiple agents to produce competing solutions and vote or merge. Agents are specialists with non-overlapping domains, not parallel competitors. |
| **cross-provider-consensus** | Multi-provider support exists (Anthropic, OpenAI, Azure, Gemini, Ollama), but agents do not run the same task across multiple providers and compare results. |
| **ralph-loop** | No fresh-context rotation strategy with periodic session reset and knowledge distillation. Session persistence is accumulative, not cyclical. |
| **self-review** | No built-in mechanism for an agent to review its own output before committing. |
| **multi-agent-review** | No automatic pattern where one agent reviews another's output, despite the architecture supporting it. |
| **test-first** | No built-in test generation before implementation. The tool-bash module can run tests, but test-first workflow is not a default behavior. |
| **prose-linting** | No natural-language quality checks on documentation, commit messages, or comments. |

### New Genes Discovered

| Gene | Description |
|------|-------------|
| **micro-kernel-composability** | The entire agent architecture is decomposable into swappable modules (providers, tools, orchestrators, context managers, hooks). Any component can be replaced without affecting others. This enables A/B testing of individual architectural choices -- swap one orchestrator for another while holding everything else constant. No other surveyed tool offers this level of compositional flexibility. |
| **context-sink-delegation** | Heavy documentation loads only when the relevant specialist agent is spawned, keeping parent sessions lean. This is a deliberate token-efficiency strategy that trades latency (agent spawn time) for context window preservation. Distinct from simple RAG or repo mapping. |
| **bundle-composition** | Configuration is composable YAML/Markdown packages that merge via "later overrides earlier" semantics. Profiles support multi-level inheritance with cycle detection. Behaviors are reusable capability add-ons. This enables reproducible, version-controlled agent configurations -- critical for benchmarking. |
| **agent-as-bundle** | Agents and bundles use identical file formats (only frontmatter key differs: `meta:` vs `bundle:`). Both are loaded via `load_bundle()`. This means agents are not a special system -- they are simply bundles with different metadata semantics. The unification simplifies the architecture but may limit agent-specific optimizations. |
| **metacognitive-recipes** | Code-orchestrated multi-stage workflows where each stage uses optimized AI configurations. "Code for structure, AI for intelligence" -- the code defines the workflow skeleton, and AI fills each stage. This is a novel middle ground between fully autonomous agents and fully manual pipelines. |
| **description-driven-routing** | Agent delegation is driven entirely by the `meta.description` field. The LLM sees only the description to decide which agent to invoke. This is a form of prompt-engineered routing that avoids hardcoded dispatch rules but depends on description quality. |

---

## 7. Benchmark-Relevant Traits

### Traits That Affect Task Design

1. **Agent delegation is LLM-initiated, not deterministic.** When the parent LLM encounters a task, it decides whether to delegate to a specialist agent based on the agent's description. This means the same task may follow different execution paths depending on the LLM's delegation decisions. Benchmarks must account for non-deterministic routing: the zen-architect agent may or may not be invoked for a planning-heavy task.

2. **No automatic file discovery mechanism.** Like Aider, Amplifier does not automatically index or discover relevant files. The LLM must use filesystem tools (read_file, list directory) to explore the codebase. For benchmarks, either the prompt must guide the LLM to the relevant files, or the benchmark must measure the LLM's ability to find them via tool use.

3. **Provider-dependent behavior.** Amplifier recommends Anthropic Claude as the primary provider but supports OpenAI, Azure, Gemini, and Ollama. Because agent delegation depends on the LLM's ability to interpret agent descriptions and make routing decisions, different providers will exhibit different delegation patterns. Benchmarks must fix the provider to ensure reproducibility.

4. **Bundle configuration defines capability surface.** The set of agents, tools, and behaviors available depends on which bundle is mounted. The default foundation bundle includes 14 agents and standard tools, but custom bundles can add or remove capabilities. Benchmarks must specify the exact bundle configuration used.

5. **Multi-stage recipes require code-level setup.** The metacognitive recipe pattern (Analyze -> Plan -> Implement -> Evaluate) is not a default interactive mode -- it requires authoring a recipe tool with explicit stages and approval gates. Benchmarking this pattern requires building a custom recipe, which is a higher integration effort than running a CLI command.

### Traits That Affect Measurement

1. **Sub-session spawning inflates total token usage.** Each delegated agent runs in its own sub-session with its own context (including heavy documentation). Total token consumption across a task includes the parent session plus all sub-sessions. This must be measured holistically, not just at the parent level. The token cost of context-sink delegation may be higher than a single-agent approach for simple tasks but lower for complex tasks where only relevant documentation is loaded.

2. **Orchestrator choice changes execution characteristics.** Because orchestrators are swappable, benchmarks comparing Amplifier against other tools must specify which orchestrator is used. A basic sequential orchestrator will behave very differently from a parallel planner or chain-of-thought voter. Each produces different turn counts, token usage, and latency profiles.

3. **Session persistence enables multi-run measurement.** Amplifier's session resume capability means benchmarks can test multi-session workflows where knowledge from one session carries into the next. This is relevant for marathon tasks (context endurance testing) and recovery tasks (can the agent resume from a broken state?).

4. **No git auto-commit.** Unlike Aider, Amplifier does not automatically commit each edit to git. Measuring edit granularity and rework rate requires instrumenting the file system or git operations externally. The hook system could be used to add auto-commit behavior via a custom hook module.

5. **Early-stage project with evolving APIs.** The project explicitly states it is in "early development and may change significantly." The roadmap mentions moving away from Claude Code dependency toward "Agentic Loop Independence." Benchmark results may not be reproducible across Amplifier versions without version pinning.

6. **Context compaction obscures turn history.** When context is compacted (older messages compressed to fit the window), the full conversation history is lost from the model's perspective. Measuring effective context usage requires tracking compaction events, which may need hook instrumentation.

### Scripting for Headless Benchmark Use

```bash
# Single-shot headless execution
amplifier run "implement the feature described in TASK.md" \
    -p anthropic \
    -m claude-sonnet-4-5

# Piped input for automation
cat TASK.md | amplifier run

# Resume a session with follow-up
amplifier continue "now run the tests and fix any failures"

# Specify a custom bundle for reproducible configuration
amplifier bundle use my-benchmark-bundle
amplifier run "implement the feature described in TASK.md"

# List available tools to verify configuration
amplifier tool list --output json

# Direct tool invocation for testing
amplifier tool invoke read_file path=src/index.ts
```

**Key scripting considerations:**
- The `amplifier run` command with a direct prompt provides non-interactive single-shot execution suitable for benchmark harnesses.
- Stdin piping enables passing task descriptions programmatically.
- No equivalent to Aider's `--yes` flag is documented; approval behavior depends on the mounted hook configuration.
- No documented Python API for programmatic control (unlike Aider's `Coder.create()` pattern), though the modular architecture suggests direct session creation via `amplifier-core` is possible.
- Session IDs are auto-generated and returned, enabling automated session tracking across benchmark runs.
- The three-scope configuration system (local/project/global) means benchmark runs should use project-level settings to ensure isolation.

---

## Summary

Amplifier is architecturally the most ambitious tool in this survey. Where Aider is a well-instrumented single-agent loop and Claude Code is a single-agent with rich tool use, Amplifier is a **platform for composing arbitrary agent architectures**. Its micro-kernel design with swappable orchestrators, the context-sink delegation pattern, and bundle-based composition are genuinely novel contributions.

Its key innovations are:

1. **Micro-kernel composability** -- the separation of mechanism (kernel) from policy (modules) means any architectural component can be swapped for benchmarking. This makes Amplifier uniquely suitable for ablation studies: swap one orchestrator, one context manager, or one agent set while holding everything else constant.

2. **Context-sink delegation** -- heavy documentation loads only when the relevant specialist is spawned, creating a natural token-efficiency strategy that scales with task complexity.

3. **Bundle-as-configuration** -- reproducible, version-controlled, composable agent configurations that can be shared, inherited, and merged. This is directly useful for benchmark reproducibility.

Its weaknesses for benchmarking are significant:

1. **Early-stage maturity** -- the project is in active early development with evolving APIs. Benchmark results may not be stable across versions.

2. **No built-in self-correction loops** -- unlike Aider's lint-fix and test-fix cycles, Amplifier has no automatic feedback loop that runs tests and feeds failures back to the LLM. Self-correction must be orchestrated through agent delegation or custom orchestrator modules.

3. **LLM-dependent routing** -- agent delegation depends on the LLM correctly interpreting agent descriptions, introducing non-determinism into execution paths.

4. **Missing consensus mechanisms** -- despite the multi-agent architecture, there is no built-in pattern for parallel competing solutions or cross-agent review, which are the genes most relevant to our research hypotheses (H1, H2).

5. **Limited edit format optimization** -- by relying on standard tool calls for file editing, Amplifier foregoes the per-model edit format tuning that Aider has shown produces measurable benchmark improvements.

Amplifier is best understood as **infrastructure for building orchestrators** rather than a finished orchestrator itself. For our benchmarks, it represents both a contender (using its default foundation bundle) and a platform (on which custom orchestration patterns like multi-agent consensus could be implemented). Its modular design makes it a natural testbed for our gene ablation studies, though its early maturity level introduces reproducibility risks.
