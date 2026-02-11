# GPT-Engineer — Orchestrator Survey

**Tool:** GPT-Engineer (https://github.com/AntonOsika/gpt-engineer)
**Archetype:** Scaffold / plan-then-generate
**Version surveyed:** v0.3.1 (last release June 2024; source: GitHub, readthedocs, DeepWiki analysis)

---

## 1. Architecture Type

**Plan-then-generate pipeline with pluggable step functions.**

GPT-Engineer is a CLI-driven code generation platform originally conceived around the idea of "one prompt generates a codebase." The user provides a natural-language prompt describing the desired software, and the system orchestrates a multi-step pipeline that transforms that prompt into a complete, executable project.

The central orchestrator is the **CliAgent**, which implements the `BaseAgent` interface with two primary methods:

1. **`init()`** -- generates a new codebase from a prompt.
2. **`improve()`** -- modifies an existing codebase based on improvement instructions.

Within `init()`, the system chains together pluggable step functions. The default generation pipeline is:

```
prompt --> gen_code() --> gen_entrypoint() --> execute_entrypoint() --> files on disk
```

Alternative pipelines can be substituted by swapping step functions:

- **Standard mode** (default): `gen_code()` -- full generation with roadmap, philosophy, and file-format preprompts composing the system message.
- **Lite mode** (`--lite`): `lite_gen()` -- simplified generation with minimal system prompting, fewer API calls, and reduced context overhead.
- **Clarify mode** (`--clarify`): `clarified_gen()` -- interactive questioning phase before implementation, where the LLM asks the user disambiguating questions, then proceeds with informed generation.
- **Self-heal mode** (`--self-heal`): `self_heal()` -- replaces the execution step; when generated code fails, the system automatically feeds error output back to the LLM and retries.

This is a single-agent architecture. There is no multi-agent delegation, no consensus mechanism, and no parallel execution. Each step is a synchronous function that takes an AI interface and a set of databases (DiskMemory) as arguments and returns a list of messages.

**Key architectural distinction from other tools:** GPT-Engineer generates an *entire* codebase in a single pass rather than making incremental edits to existing files. This is fundamentally different from tools like Aider (which applies targeted edits within a conversation loop) or Cursor (which provides real-time inline suggestions). GPT-Engineer's improve mode was added later to handle the existing-codebase case, but the tool's DNA is whole-project generation.

---

## 2. Context Strategy

GPT-Engineer's context management is straightforward compared to tools that maintain sophisticated repo maps or embedding-based retrieval.

### Prompt-Centric Context

In generation mode, the primary context is the user's prompt file (a plaintext file named `prompt` placed in the project directory). This prompt, combined with the preprompts system messages, forms the entire context sent to the LLM. There is no repo map, no AST parsing, and no symbol graph -- the LLM receives the prompt and must generate everything from scratch.

Optional context enrichment includes:
- **Image inputs**: The `--image_directory` flag enables vision-capable models to process UX mockups or architecture diagrams alongside the text prompt.
- **Custom preprompts**: Users can override the default system prompts via `--use-custom-preprompts`, effectively injecting persistent context about coding standards, frameworks, or project conventions.

### Improve Mode: File Selection as Context Control

In improve mode (`-i`), context management becomes more critical because the LLM needs to see existing code. GPT-Engineer uses a **TOML-based file selector**:

1. The system generates a `file_selection.toml` listing all files in the project.
2. The file opens in the user's default editor.
3. The user uncomments the files they want to include by removing `#` prefixes.
4. Selected files are loaded into a `FilesDict` structure and formatted for LLM consumption via the `to_chat()` method.

The `--skip-file-selection` (`-s`) flag bypasses this manual step, which is important for headless/benchmark use. Linting can also be toggled within the TOML configuration.

### No Automatic Context Compression or Ranking

GPT-Engineer does not summarize, truncate, rank, or rotate context. There is no equivalent of Aider's PageRank-based repo map. The entire content of selected files is sent to the LLM, subject only to the model's context window limit. For large projects, this means improve mode can quickly exhaust available context, and the user must manually constrain file selection.

### Token Tracking

The `TokenUsageLog` class tracks per-step token consumption (prompt tokens, completion tokens, total) and provides cumulative cost estimation for OpenAI models. This is a logging/observability feature rather than an active context management strategy -- it does not influence which context is sent.

### DiskMemory Persistence

All conversation history, generated files, and logs are persisted to the `.gpteng/` directory within the project via the `DiskMemory` class. This enables:
- Resuming interrupted generation runs.
- Inspecting per-step conversation logs in `.gpteng/memory/`.
- Archiving old logs for debugging.

However, this is filesystem-level persistence, not semantic memory. There is no cross-project learning, no embedding store, and no retrieval-augmented generation from previous sessions.

---

## 3. Planning Approach

**Explicit plan-before-code in standard mode; optional interactive clarification.**

GPT-Engineer's planning approach is embedded in its preprompts system, which structures the LLM's behavior through composable system message templates:

### Roadmap Preprompt

The `roadmap` preprompt instructs the LLM to first think through the high-level architecture before writing any code. This is not a separate planning step in the pipeline -- it is prompt engineering that encourages the LLM to reason about structure within its single generation pass.

### Generate Preprompt

The `generate` preprompt contains explicit planning instructions:
- "First lay out the names of the core classes, functions, and methods that will be necessary, as well as a quick comment on their purpose."
- "Then start with the 'entrypoint' file, then go to the ones that are imported by that file, and so on."
- Code must be "fully functional" with "no placeholders."

This creates a structured generation order: the LLM is instructed to plan the architecture (classes, functions, interfaces) before writing implementation code, and to follow a dependency-driven file ordering.

### Clarify Mode

Clarify mode (`--clarify`) adds a genuine interactive planning phase. Before any code generation:
1. The LLM reads the user's prompt.
2. It generates clarifying questions about ambiguous requirements.
3. The user answers.
4. The clarified understanding informs subsequent generation.

This is the closest GPT-Engineer comes to a formal requirements-gathering step. However, it is opt-in and adds latency (additional LLM round-trips).

### No Persistent Plan Document

Unlike tools that produce a plan document that can be reviewed, edited, and used as a reference during implementation, GPT-Engineer's "planning" exists only within the LLM's chain-of-thought during a single generation call. There is no plan revision loop, no plan-vs-implementation consistency checking, and no plan persistence across sessions.

---

## 4. Edit Mechanism

GPT-Engineer uses two fundamentally different edit mechanisms depending on mode:

### Generation Mode: Whole-File Output

In generation mode, the LLM produces complete file contents wrapped in markdown code blocks. The `chat_to_files_dict()` function parses the LLM output by:
1. Identifying markdown code blocks (triple-backtick fenced blocks).
2. Extracting filenames from locations near each code block (the line immediately before or within the fence metadata).
3. Constructing a `FilesDict` (dictionary with file paths as keys, file contents as values).

The parsing is intentionally flexible -- it searches for filenames "in logical spots" near code blocks rather than requiring a rigid output format. A test suite (`tests/test_chat_parser.py`) validates parsing against many formatting variations.

The `file_format` preprompt instructs the LLM on the expected output structure, ensuring files are properly delimited and named.

### Improve Mode: Unified Diff

In improve mode, the LLM produces changes in a unified diff format rather than rewriting entire files. The diff pipeline involves:

1. **`parse_diffs()`**: Extracts diff objects from LLM output, identifying file-level changes and line-specific modifications represented as `Hunk` objects (containing line numbers, ranges, original content, and modified content).
2. **`validate_and_correct()`**: Validates that diff hunks align with the original source code lines, automatically correcting misaligned hunks where possible.
3. **`apply_diffs()`**: Applies validated diffs to the original files incrementally.

If diff application fails due to formatting errors, the system retries with error feedback up to `MAX_EDIT_REFINEMENT_STEPS` iterations, creating a mini correction loop within improve mode.

### Entrypoint Generation

A distinctive GPT-Engineer feature is the separate `gen_entrypoint()` step, which generates a `run.sh` bash script that handles dependency installation and launches the application. This is generated by a second LLM call after the main code generation, using the `entrypoint` preprompt. The entrypoint script may install packages (`pip install`, `npm install`) and run components in parallel if needed.

### Git Integration

GPT-Engineer integrates with git for version tracking: in improve mode, it stages uncommitted changes before applying modifications, enabling rollback if the LLM's changes are unsatisfactory. This is a safety mechanism rather than a primary edit strategy.

---

## 5. Self-Correction

GPT-Engineer's self-correction capabilities are limited compared to tools with integrated lint-fix or test-fix loops.

### Self-Heal Mode

The most explicit self-correction mechanism is `--self-heal` mode, which creates an execute-diagnose-fix cycle:

1. Generated code is executed via `execute_entrypoint()`.
2. If execution produces errors (non-zero exit code, stack traces), the error output is captured.
3. The error messages are fed back to the LLM along with the original code.
4. The LLM generates corrected code.
5. The cycle repeats until execution succeeds or a retry limit is reached.

This is a genuine iterative correction loop, but it is **opt-in** (requires the `--self-heal` flag) and only triggers on runtime errors, not on logical correctness, code quality, or test failures.

### Diff Validation Loop

In improve mode, when diff application fails because the LLM produced malformed or misaligned diffs, the system retries by feeding the validation errors back to the LLM. This is a formatting correction loop rather than a semantic correctness loop, bounded by `MAX_EDIT_REFINEMENT_STEPS`.

### No Integrated Lint or Test Loop

Unlike Aider (which automatically lints every edited file and optionally runs tests after each edit), GPT-Engineer does not have built-in linting or test execution as part of its standard pipeline. The improve mode TOML file has a linting toggle, but this is a configuration option rather than an automatic feedback loop.

### No Self-Review

The LLM does not review its own output for quality, design coherence, or adherence to the original prompt before the code is written to disk. There is no second-pass review step, no separate review agent, and no quality gate between generation and output.

### Execution as Validation

The default pipeline includes `execute_entrypoint()` as its final step, which runs the generated code and displays output. This serves as a basic smoke test -- if the code crashes on first run, the user sees the error. But without self-heal mode, the system does not automatically attempt to fix the crash.

---

## 6. Gene List

### Genes Present

| Gene | Strength | Notes |
|------|----------|-------|
| **plan-before-code** | Moderate | The `roadmap` and `generate` preprompts explicitly instruct the LLM to lay out architecture before writing implementation. Clarify mode adds interactive requirements gathering. However, there is no persistent plan document or plan revision loop. |
| **iterative-refinement** | Weak | Self-heal mode creates an execute-fix cycle, and diff validation retries malformed edits. But these are opt-in and narrow in scope (runtime errors and diff formatting only). Not a general-purpose refinement loop. |
| **tool-use** | Weak | The generated `run.sh` entrypoint is executed via `DiskExecutionEnv`, and improve mode integrates with git. But the LLM cannot autonomously invoke shell commands, browse files, or use external tools during generation. |

### Genes Absent

| Gene | Notes |
|------|-------|
| **multi-agent-consensus** | Single-agent architecture throughout. No parallel generation, no voting, no consensus. |
| **cross-provider-consensus** | Supports multiple LLM providers (OpenAI, Anthropic, Azure, open-source) but uses only one at a time. No cross-provider comparison or voting. |
| **ralph-loop** | No fresh-context rotation. Each generation pass is a single LLM call. Improve mode accumulates context but does not rotate or refresh it. |
| **fresh-context** | No context refresh strategy. Conversation history persists in DiskMemory but is not summarized or rotated. |
| **repo-mapping** | No AST-based repo map, no symbol graph, no PageRank ranking. File selection in improve mode is manual (TOML-based), not automated. |
| **auto-pilot-brainstorm** | No autonomous brainstorming phase. Clarify mode is interactive (requires human answers), not autonomous. |
| **self-review** | No LLM self-review step before outputting code. |
| **multi-agent-review** | No review by a second agent or model. |
| **test-first** | Does not generate tests before implementation as a default behavior. The philosophy preprompt recommends pytest for Python but does not enforce test-first development. |
| **prose-linting** | No natural-language quality checks on generated documentation, comments, or commit messages. |

### New Genes Discovered

| Gene | Description |
|------|-------------|
| **preprompt-identity** | The preprompts system (`roadmap`, `generate`, `improve`, `philosophy`, `file_format`) acts as a composable identity layer that shapes LLM behavior without code changes. Users can override these templates to create custom "personalities" or enforce project-specific conventions. This is a form of prompt-level configuration that is more structured than simple system prompts -- it decomposes the system message into role-specific concerns. |
| **whole-project-scaffolding** | Unlike edit-based tools that modify existing files, GPT-Engineer's default mode generates an entire project from scratch in a single pass: source code, dependency files (`requirements.txt`, `package.json`), entrypoint scripts, and directory structure. This is architecturally distinct from iterative editing and represents a "scaffold" pattern where the LLM acts as a project bootstrapper. |
| **entrypoint-generation** | A separate LLM call dedicated to producing a `run.sh` script that installs dependencies and launches the application. This decouples "what the code does" from "how to run it" and ensures generated projects are immediately executable. The entrypoint step uses its own preprompt and can handle parallel process launching. |
| **execution-as-validation** | The default pipeline executes generated code as a final step, using runtime success/failure as a basic validation signal. In self-heal mode, this becomes a feedback loop. This gene represents the philosophy that "the best test of code is running it." |
| **toml-file-selection** | In improve mode, context scope is controlled through a TOML file opened in the user's editor, where files are included/excluded by commenting/uncommenting lines. This is a manual but explicit context-scoping mechanism that gives the user precise control over what the LLM sees, at the cost of requiring human interaction for every improve cycle. |

---

## 7. Benchmark-Relevant Traits

### Traits That Affect Task Design

1. **Generation mode is project-bootstrapping, not incremental editing.** GPT-Engineer's default mode assumes it is creating a project from nothing. For benchmark tasks that provide an existing codebase and require modifications (features, bugfix categories), improve mode (`-i`) must be used instead. These are architecturally different pipelines with different strengths -- generation mode is suited for greenfield tasks, improve mode for feature/bugfix tasks. Benchmarks should test both.

2. **Improve mode requires explicit file selection.** In a benchmark harness, the `--skip-file-selection` flag is essential to avoid the interactive TOML editor popup. Without it, the tool blocks waiting for human input. Alternatively, the harness must pre-populate `file_selection.toml` or pipe file selections programmatically.

3. **No autonomous file discovery.** GPT-Engineer does not explore the filesystem to find relevant files. In generation mode, this is irrelevant (it creates files from scratch). In improve mode, the user must specify which files to include. For benchmark tasks where the relevant files are not obvious, the tool is at a disadvantage compared to tools with repo mapping or file search capabilities.

4. **Clarify mode adds human-in-the-loop requirement.** Clarify mode expects interactive answers to the LLM's questions. For headless benchmarking, this mode must be disabled (it is off by default). This means benchmarks test the tool without its requirements-gathering capability, which may undercount its potential quality on ambiguous tasks.

5. **Self-heal is opt-in.** Self-heal mode must be explicitly enabled via `--self-heal`. Benchmarks should test both with and without self-heal to measure the value of the execute-fix loop. Without it, GPT-Engineer is a pure one-shot generator with no error recovery.

6. **Single-pass generation may struggle with complex tasks.** The architecture assumes the LLM can hold the entire project design in a single context window and produce all files in one pass. For complex multi-file projects, this places heavy demands on model capability and context window size. Tasks that require iterative refinement across multiple files may expose this limitation.

### Traits That Affect Measurement

1. **Token usage pattern is distinctive.** Generation mode consumes tokens in large, discrete bursts (one call for code, one for entrypoint) rather than many small incremental calls. This creates a different cost profile from edit-based tools. Token measurement must account for the fact that GPT-Engineer may use fewer API calls but more tokens per call.

2. **Turn count is inherently low.** In generation mode without self-heal, the pipeline makes exactly two LLM calls (code generation + entrypoint). With self-heal, additional calls occur only on runtime errors. This means turn count is not a useful efficiency metric for GPT-Engineer in generation mode -- the interesting metric is whether the single pass produced correct output.

3. **No intermediate commits for diff analysis.** Unlike Aider (which auto-commits every edit), GPT-Engineer writes all files at once. There is no git history of incremental attempts within a single generation run. Measurement of "number of edit attempts" or "progressive convergence" is not possible without self-heal mode, which does persist intermediate states.

4. **Execution output is available for analysis.** The `execute_entrypoint()` step produces captured output that can be compared against expected results. This provides a natural pass/fail signal for benchmark scoring.

5. **Cost tracking is built-in.** The `TokenUsageLog` provides per-step token counts and cost estimates, making it straightforward to measure API cost per benchmark task without external instrumentation.

6. **Context endurance is not tested meaningfully.** GPT-Engineer does not maintain long-running conversations -- each generation is a fresh context. For marathon tasks (e.g., 12-phase task queues), GPT-Engineer would need to run improve mode repeatedly, with each phase as a separate improve call. This tests a fundamentally different workflow than tools that maintain persistent conversation context, and the benchmark harness must be designed accordingly.

7. **Model sensitivity is high.** GPT-Engineer's quality depends entirely on the underlying model's ability to generate a coherent multi-file project in one pass. The default model is GPT-4o, but the tool supports Anthropic Claude, Azure OpenAI, and open-source models. Benchmark results will vary significantly across models, and the model must be controlled as a variable.

### Scripting for Headless Benchmark Use

```bash
# Greenfield generation (new project from prompt)
gpte /path/to/project \
     --model gpt-4o \
     --no_execution \
     --lite  # or omit for standard mode

# Greenfield with self-heal (auto-fix runtime errors)
gpte /path/to/project \
     --model gpt-4o \
     --self-heal

# Improve existing codebase (headless, skip file selection UI)
gpte /path/to/project \
     --model gpt-4o \
     --improve \
     --skip-file-selection

# With custom preprompts for benchmark-specific identity
gpte /path/to/project \
     --model gpt-4o \
     --use-custom-preprompts

# Using Anthropic model
ANTHROPIC_API_KEY=... gpte /path/to/project \
     --model claude-3-5-sonnet-20241022
```

**Benchmark integration notes:**

- The `bench` binary (installed with gpt-engineer) provides a built-in interface for evaluating custom agent implementations against APPS and MBPP datasets. The `gpte-bench-template` repository provides a template for implementing benchmark agents.
- For custom benchmark tasks, the harness should: (a) create a project directory with a `prompt` file, (b) for improve mode, pre-populate the codebase and optionally a `file_selection.toml`, (c) invoke `gpte` via subprocess, (d) inspect generated files and optionally run test suites against them.
- The Python internals (CliAgent, AI class) could theoretically be imported and driven programmatically, but this is not an officially supported interface.
- Each benchmark run should capture: the `.gpteng/memory/` directory (conversation logs), token usage from `TokenUsageLog`, execution output, and the final generated files.

---

## Summary

GPT-Engineer is the purest "scaffold generator" in the survey. Its defining architectural trait is **whole-project generation from a single prompt** -- the LLM receives a description of desired software and produces an entire codebase (source files, dependency manifests, and a runnable entrypoint) in one pass. This is fundamentally different from the iterative edit-based approach of tools like Aider or Cursor.

Key characteristics for benchmarking:

1. **Preprompts as composable identity** -- the system decomposes LLM instructions into role-specific templates (roadmap, generate, philosophy, file format) that can be customized per-project. This is a structured prompt engineering approach that is more modular than monolithic system prompts.

2. **Two distinct modes with different architectures** -- generation mode (whole-project scaffolding) and improve mode (diff-based editing) are architecturally different pipelines. Benchmarks must test both, as they have fundamentally different strengths: generation mode excels at greenfield tasks, improve mode handles existing codebases.

3. **Minimal self-correction** -- without `--self-heal`, GPT-Engineer is a pure one-shot generator. Self-heal adds a runtime-error feedback loop but does not approach the lint-fix/test-fix automation of tools like Aider. There is no self-review or quality gating.

4. **No context sophistication** -- no repo map, no symbol graph, no embedding retrieval. Context management is manual (file selection TOML) or absent (generation mode relies entirely on the prompt). This makes GPT-Engineer a clean test of "what can an LLM produce from a prompt alone?" without the confounding effects of sophisticated context engineering.

5. **Commercial evolution** -- the open-source GPT-Engineer CLI is the precursor to Lovable (formerly gptengineer.app), which grew to $50M+ ARR as a managed web-based code generation service. The open-source CLI remains at v0.3.1 (June 2024) and is less actively developed than the commercial product. This affects long-term viability for benchmarking but does not diminish its value as a representative of the scaffold/generator archetype.

GPT-Engineer serves as an excellent **baseline for the generation archetype** -- it tests the hypothesis that a well-prompted single LLM call can produce a complete, working project. Comparing its greenfield performance against multi-turn, multi-agent approaches directly tests whether iterative refinement and consensus justify their additional cost and complexity.
