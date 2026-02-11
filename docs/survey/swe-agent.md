# SWE-agent — Orchestrator Survey

**Tool:** SWE-agent (https://github.com/SWE-agent/SWE-agent)
**Archetype:** Academic/research single-agent framework
**Version surveyed:** v1.0+ as of February 2026 (source: NeurIPS 2024 paper, official docs, GitHub)

---

## 1. Architecture Type

**Single-agent ReAct loop with a custom Agent-Computer Interface (ACI).**

SWE-agent is a single-agent system built around a thought-action-observation loop. The agent receives a problem statement (typically a GitHub issue), then iteratively reasons about the problem, executes actions in a sandboxed environment, observes the results, and repeats until it produces a solution (a git patch). There is no multi-agent consensus, no delegation tree, and no parallel competing agents in the default configuration.

The core architectural innovation is not the agent loop itself (which follows the standard ReAct pattern) but the **Agent-Computer Interface (ACI)** -- a carefully designed set of commands and feedback formats that replace raw shell interaction. The central thesis of the SWE-agent paper is that LM agents are "a new category of end users with their own needs and abilities" and benefit from purpose-built interfaces rather than human-oriented ones like the Linux shell.

**Execution flow:**

1. **RunOrchestrator** initializes the environment (Docker container via SWE-ReX) and loads configuration.
2. **DefaultAgent** receives the problem statement and enters the step loop.
3. Each step: the agent queries the LLM with the full conversation history, the response is parsed into a thought and an action, the action is validated by the **ToolHandler**, executed in the sandboxed shell via **SWEEnv**, and the output is recorded as an observation.
4. The loop continues until the agent submits a solution, exceeds a step/cost limit, or encounters an unrecoverable error.

**Key classes in the architecture:**

- `DefaultAgent`: Primary single-agent implementation with `setup()`, `step()`, and completion lifecycle.
- `RetryAgent`: Meta-orchestrator that runs multiple `DefaultAgent` instances with varying configurations and selects the best solution. This is not multi-agent consensus -- it is independent parallel attempts with post-hoc evaluation.
- `ToolHandler`: Validates and dispatches parsed actions against the configured tool set.
- `SWEEnv`: Wraps the SWE-ReX runtime, managing the sandboxed container lifecycle.
- `History`: Maintains the full conversation state (messages and metadata) passed to the LLM.
- `Trajectory`: Records the complete action-observation trace for post-run analysis.

The RetryAgent deserves special note: it can run 5 attempts with slightly different configurations (e.g., Claude 3.7 Sonnet), then use a discriminator model (e.g., o1) to select the best patch. This is an ensemble/retry strategy, not a consensus mechanism -- the agents do not communicate or negotiate with each other.

---

## 2. Context Strategy

SWE-agent's context strategy is fundamentally different from tools like Aider. It has **no repo map, no AST-based indexing, and no PageRank graph**. Instead, the agent explores the repository dynamically through shell-like ACI commands, building understanding incrementally through its conversation history.

### Dynamic Exploration via ACI Commands

The agent discovers repository structure through purpose-built commands:

- **`find_file <filename> [dir]`**: Locates files by name, returning a succinct summary of matches.
- **`search_dir <search_term> [dir]`**: Searches for text across all files in a directory, returning only the file names with matches (not full content). This deliberate suppression of verbose output prevents context flooding.
- **`search_file <search_term> [file]`**: Searches within a single file for a term.
- **`open <file> [line_number]`**: Opens a file in the built-in viewer, displaying a window of approximately 100 lines centered on the specified line.
- **`goto <line_number>`**: Jumps to a specific line in the currently open file.
- **`scroll_up` / `scroll_down`**: Navigates through the currently open file in 100-line increments.

This means the agent must actively decide what to look at, creating a navigation-heavy interaction pattern. Each exploration step consumes a turn and adds to the conversation history.

### File Viewer Design

Rather than allowing raw `cat` access to files, SWE-agent provides a structured file viewer that:

- Displays approximately **100 lines per turn** (configurable window size).
- Shows **line numbers** alongside content, giving the agent precise positional awareness.
- Tracks the **currently open file and line position** as persistent state across turns.
- Prevents the agent from being overwhelmed by large files.

The 100-line window was an empirical design choice -- the researchers found this balances enough context for understanding with concise enough output to avoid flooding the LLM.

### History Management and Truncation

SWE-agent uses a collapse-based strategy for managing conversation history:

- **Observations older than the last 5 turns are collapsed** into single-line summaries. This is the primary context compression mechanism.
- **Error messages are pruned**: once a valid generation is received, past error messages are omitted except for the first occurrence.
- **Empty outputs** are replaced with an explicit message: "Your command ran successfully and did not produce any output." This prevents the agent from being confused by silent success.

The system pre-counts tokens via `litellm.token_counter()` before each query and raises `ContextWindowExceededError` if the context window would be exceeded.

### EnIGMA Summarizer (Extended Context Management)

The EnIGMA variant introduces an **LM-based summarizer** for handling long outputs. Rather than truncating, an LLM summarizes verbose command outputs before they are added to the conversation history. Ablation studies show the LM summarizer improves performance by 2.5% compared to no summarization, and outperforms simpler heuristic-based summarization.

### No Static Repo Map

Unlike Aider's PageRank-based repo map or tools that use embeddings for retrieval, SWE-agent has **no pre-built index of the repository**. The agent must explore from scratch on every run. This design choice prioritizes generality (works on any repo without preprocessing) at the cost of efficiency (more exploration turns needed).

---

## 3. Planning Approach

**No explicit planning phase; emergent planning through the thought-action loop.**

SWE-agent does not have a dedicated "plan-before-code" step. The agent's planning is embedded in the **thought** component of each thought-action-observation cycle. Before each action, the agent produces a natural-language thought explaining its reasoning -- what it has learned so far, what it intends to do next, and why. This is emergent, not structured.

The system template instructs the agent that it "must include a THOUGHT section before the command where [it] explain[s its] reasoning process." This thought is recorded in the trajectory but is not validated, scored, or enforced beyond format compliance.

**What this means in practice:**

- The agent may form an implicit plan in early turns (e.g., "First I'll find the relevant file, then understand the bug, then fix it"), but this plan is not stored as a separate artifact.
- There is no plan revision loop -- the agent does not compare its current actions against a previously stated plan.
- There is no plan-vs-implementation consistency checking.
- The quality of planning depends entirely on the underlying LLM's reasoning capabilities.

The **RetryAgent** configuration introduces a form of strategic variation -- running multiple attempts with different configurations -- but this is not planning in the traditional sense. It is brute-force diversity at the attempt level.

---

## 4. Edit Mechanism

**Search-and-replace via `str_replace_editor` with syntax-checking guardrails.**

SWE-agent uses a structured editing tool (the `str_replace_editor`, derived from Anthropic's tool design) rather than whole-file replacement or unified diffs. The tool supports five operations:

| Command | Purpose |
|---------|---------|
| **`view`** | Display file contents (with `cat -n` style line numbers) or directory structure (2 levels deep). Supports `view_range` for partial viewing. |
| **`create`** | Create a new file (path must not already exist). |
| **`str_replace`** | Replace an exact string match (`old_str`) with a new string (`new_str`). The `old_str` must match exactly one or more consecutive lines, including whitespace and indentation. |
| **`insert`** | Insert content after a specified line number. |
| **`undo_edit`** | Revert the most recent edit to a file. |

### Linting Guardrails

The most architecturally significant aspect of SWE-agent's editing is its **mandatory syntax checking**:

- A linter runs on every `edit` / `str_replace` command before the edit is committed.
- If the resulting code is not syntactically valid, **the edit is rejected** and the agent receives an error message explaining why.
- The agent must fix the edit and resubmit.

This is a hard guardrail, not advisory. The ablation study in the paper shows that **removing linting causes a 3 percentage point drop** in SWE-bench performance. This is one of the most impactful individual ACI design decisions.

### Exact Matching Requirements

The `str_replace` command requires the `old_str` to match **exactly** -- character-for-character, including whitespace and indentation. If the string is not unique in the file, the replacement fails. A `--range` option was later added to restrict matching to a specific line range, addressing the uniqueness constraint in large files.

This is notably different from Aider's approach, which uses **fuzzy matching** of SEARCH blocks to tolerate minor LLM output imprecision. SWE-agent's exact matching is stricter but avoids ambiguity about which code is being changed.

### Tool Bundles

SWE-agent organizes editing capabilities into modular **tool bundles** -- directories containing a `config.yaml`, executable scripts, and installation scripts. The default configuration includes:

- `tools/edit_anthropic`: The `str_replace_editor` tool described above.
- `tools/registry`: Core navigation and search commands.
- `tools/review_on_submit_m`: Review step triggered on solution submission.

Tool bundles are swappable via YAML configuration, allowing researchers to test different editing interfaces.

---

## 5. Self-Correction

SWE-agent's self-correction is primarily driven by **environment feedback loops** rather than explicit self-review.

### Syntax Error Prevention

The linting guardrail (Section 4) prevents syntactically invalid edits from being applied. This is proactive error prevention, not reactive correction -- the agent cannot introduce syntax errors into the codebase.

### Test Execution

The agent has full shell access and can run test suites as part of its action loop. Unlike Aider's `--auto-test` flag which automatically runs tests after every edit, SWE-agent leaves test execution to the agent's discretion. The agent must decide when to run tests and interpret the results. This means:

- The agent can run tests at any point during its trajectory.
- Test output becomes an observation that informs subsequent actions.
- If tests fail, the agent observes the failure output and can attempt fixes.
- There is no automatic retry loop -- the agent must explicitly choose to re-edit and re-test.

### Format Error Recovery

If the agent produces a malformed response (wrong action format, invalid command syntax), a two-turn recovery mechanism activates:

1. An error message is shown asking the model to correct its response.
2. The agent gets a second chance to produce a valid response.
3. If both attempts fail, the episode terminates.
4. Once a valid response is received, past format error messages are pruned from history (except the first), preventing error messages from consuming context.

### Re-query on Errors

The `max_requeries` parameter (default 3) controls how many times the model is re-queried after errors including formatting errors, blocked actions, or bash syntax errors.

### RetryAgent as Macro-Level Self-Correction

The RetryAgent provides a form of "outer loop" self-correction: if one attempt fails to solve the problem, the system can make additional independent attempts with different configurations. A discriminator model then evaluates all solutions and selects the best one. This is expensive (approximately 5x cost) but effective -- the pass@3 metric shows significant improvement over pass@1.

### No Explicit Self-Review

SWE-agent does **not** have the LLM review its own patch for quality, design coherence, or correctness before submitting. The `review_on_submit_m` tool bundle provides a review step at submission time, but this is a single checkpoint, not an iterative review loop.

---

## 6. Gene List

### Genes Present

| Gene | Strength | Notes |
|------|----------|-------|
| **iterative-refinement** | Strong | Core architecture. The thought-action-observation loop naturally supports iterative exploration, editing, testing, and fixing across many turns. |
| **tool-use** | Strong | The entire ACI is a purpose-built tool interface. The agent uses structured commands rather than raw shell. Navigation, search, editing, and execution all happen through defined tools. |
| **ralph-loop** | Weak (via RetryAgent) | RetryAgent runs multiple independent attempts, effectively providing fresh-context restarts. But this is not a deliberate "ralph loop" -- it is retry with diversity, not context rotation. |
| **fresh-context** | Weak (via RetryAgent) | Each retry attempt starts with a clean context. But within a single attempt, context accumulates without refresh. |
| **self-review** | Weak | The `review_on_submit_m` tool bundle triggers a review at submission time. This is a single checkpoint, not an ongoing review process. |

### Genes Absent

| Gene | Notes |
|------|-------|
| **multi-agent-consensus** | No consensus mechanism. Single agent per attempt. RetryAgent runs independent attempts without inter-agent communication. |
| **cross-provider-consensus** | RetryAgent can use different models for attempts vs. discrimination, but attempts do not produce competing solutions that are debated -- they are independently evaluated. |
| **plan-before-code** | No separate planning phase. Planning is embedded in thought sections of the ReAct loop. |
| **repo-mapping** | No static repository index, no AST parsing, no PageRank. The agent explores dynamically via ACI commands. |
| **auto-pilot-brainstorm** | No brainstorming phase. The agent proceeds directly to exploration and implementation. |
| **multi-agent-review** | No second agent reviews the solution (except the discriminator in RetryAgent, which selects among solutions rather than reviewing one). |
| **test-first** | Does not generate tests before implementation. Can run existing tests but does not create new ones as a strategy. |
| **prose-linting** | No natural-language quality checks. |

### New Genes Discovered

| Gene | Description |
|------|-------------|
| **agent-computer-interface** | Purpose-built command interface designed specifically for LLM interaction rather than human use. Includes constrained action spaces, guardrails (linting), concise feedback formats, and suppression of verbose output. This is the central innovation of SWE-agent and represents a distinct design philosophy: instead of improving the agent, improve the interface the agent uses. |
| **observation-collapse** | Automatic compression of older observations in the conversation history. Observations older than 5 turns are collapsed to single-line summaries, keeping the context window focused on recent interactions while preserving a minimal record of earlier steps. |
| **syntax-guardrail** | Hard prevention of syntactically invalid edits via mandatory linting before edit application. Unlike advisory linting (where the error is reported but the edit proceeds), this blocks the edit entirely, preventing the agent from ever introducing syntax errors. Ablation shows 3pp impact on performance. |
| **discriminator-selection** | Post-hoc evaluation of multiple independent solution attempts by a separate (potentially stronger) model. The discriminator does not participate in solving -- it only judges solutions. This separates the "generation" and "evaluation" concerns into different models. |
| **environment-as-feedback** | Rather than having the agent self-assess, SWE-agent relies on environment signals (test results, linter output, command errors) as the primary feedback mechanism. The agent corrects based on concrete external signals rather than internal self-review. |

---

## 7. Benchmark-Relevant Traits

### Traits That Affect Task Design

1. **Fully autonomous by design.** Unlike Aider, SWE-agent is built for headless operation from the start. It takes a problem statement and runs autonomously until completion. There is no human-in-the-loop expectation during a run. This makes it naturally suitable for automated benchmarking without adapter complexity.

2. **Dynamic file discovery means variable exploration overhead.** Since SWE-agent has no repo map, it must spend turns exploring the repository structure before it can begin editing. Task complexity is amplified by repository size -- a large repo requires more exploration turns. Benchmark tasks should account for this: a task that is "easy" for a tool with a repo map may require significantly more turns for SWE-agent.

3. **Shell access enables arbitrary computation.** The agent can run any shell command, install packages, execute scripts, and interact with the full Linux environment inside the Docker container. This means SWE-agent can potentially handle tasks that require build systems, package installation, or complex test setups -- but it also means the agent may go down unproductive rabbit holes.

4. **The ACI constrains but does not eliminate raw shell.** While the ACI provides structured commands, the agent retains access to standard bash. It can `cat`, `grep`, `find`, `pip install`, etc. The ACI commands are preferred but not mandatory. Benchmark measurement should track which commands the agent actually uses.

5. **RetryAgent multiplies cost significantly.** If benchmarking with RetryAgent (5 attempts + discriminator), expect approximately 5-6x the cost of a single attempt. Benchmark configurations must specify whether single-attempt or multi-attempt mode is used, as results are not comparable.

### Traits That Affect Measurement

1. **Trajectory files enable deep analysis.** Every run produces a detailed JSON trajectory containing all thoughts, actions, observations, timestamps, token counts, and costs. This is the most detailed execution trace of any tool in the survey, enabling fine-grained measurement of: turns to solution, exploration vs. editing ratio, backtracking frequency, cost breakdown, and reasoning quality.

2. **Turn count is high compared to tools with repo maps.** SWE-agent's exploration-heavy approach means it typically uses more turns than tools that start with repository awareness. Turn count comparisons must account for this architectural difference -- more turns does not necessarily mean worse reasoning.

3. **Cost tracking is built in.** Per-instance and total cost limits are enforced by the system (`per_instance_cost_limit`, `total_cost_limit`). The framework tracks input/output tokens and API costs via litellm's cost calculator. This enables direct cost-efficiency comparisons.

4. **Context window exhaustion is a real risk on long tasks.** The observation collapse strategy (Section 2) helps, but on marathon tasks with many turns, context can fill up. The `ContextWindowExceededError` terminates the run rather than degrading gracefully. Models with larger context windows (128k+) are strongly preferred.

5. **Linting guardrails suppress a class of failures.** Because SWE-agent prevents syntax errors at the edit level, it will have a lower rate of "trivially broken" solutions compared to tools without such guardrails. This makes its success rate on compilation/syntax metrics artificially higher -- the interesting comparison is on semantic correctness.

6. **Parallel execution via num_workers.** Batch mode supports `--num_workers` for parallel instance processing. This affects wall-clock time measurement but not per-instance metrics.

### Scripting for Headless Benchmark Use

```bash
# Single issue, single attempt
sweagent run \
  --agent.model.name claude-3-7-sonnet-20250219 \
  --agent.model.per_instance_cost_limit 2.00 \
  --problem_statement.type text \
  --problem_statement.text "Fix the bug described in TASK.md" \
  --problem_statement.repo_path /path/to/repo \
  --config config/default.yaml

# Batch mode on SWE-bench Lite
sweagent run-batch \
  --config config/default.yaml \
  --agent.model.name claude-3-7-sonnet-20250219 \
  --instances.type swe_bench \
  --instances.subset lite \
  --instances.split dev \
  --instances.slice :10 \
  --num_workers 3

# Multi-attempt with discriminator (competitive mode)
sweagent run-batch \
  --config config/competitive.yaml \
  --agent.model.per_instance_cost_limit 5.00 \
  --instances.type file \
  --instances.path tasks.yaml \
  --num_workers 2

# Inspect results
sweagent quick-stats trajectories/
sweagent inspect trajectories/<instance_id>.traj
```

```python
# Programmatic batch execution (via CLI subprocess)
import subprocess
import json

result = subprocess.run([
    "sweagent", "run",
    "--agent.model.name", "claude-3-7-sonnet-20250219",
    "--agent.model.per_instance_cost_limit", "2.00",
    "--problem_statement.type", "text",
    "--problem_statement.text", task_description,
    "--problem_statement.repo_path", repo_path,
    "--config", "config/default.yaml",
], capture_output=True, text=True)

# Parse trajectory for metrics
with open(f"trajectories/{instance_id}.traj") as f:
    trajectory = json.load(f)
    total_cost = trajectory["info"]["model_stats"]["instance_cost"]
    num_steps = len(trajectory["trajectory"])
    patch = trajectory["info"].get("submission")
```

---

## Summary

SWE-agent's key architectural contributions and implications for benchmarking are:

1. **The Agent-Computer Interface (ACI) is the central innovation.** SWE-agent demonstrates that designing the interface between the LLM and the environment matters as much as the agent logic itself. The ablation study shows a 10.7pp improvement over a baseline agent using only the raw Linux shell. Within the ACI, the linting guardrail (3pp), structured file viewer (enabling focused 100-line windows), and concise search output formats each contribute measurably. This suggests that our benchmarks should separately evaluate the quality of tool interfaces, not just agent reasoning.

2. **Exploration-heavy architecture trades tokens for generality.** Unlike Aider (which pre-indexes the repo) or tools with embeddings-based retrieval, SWE-agent explores from scratch on every run. This makes it universally applicable to any repository without setup, but means it consumes significantly more turns and tokens on the exploration phase. For our benchmark, this creates a natural contrast: SWE-agent will likely perform worse on token efficiency but better on novel/unfamiliar codebases where pre-built indices might be stale or missing.

3. **The RetryAgent/discriminator pattern is a lightweight alternative to consensus.** Rather than having agents debate or negotiate (multi-agent consensus), SWE-agent runs independent attempts and lets a judge pick the winner. This is cheaper to implement, easier to parallelize, and avoids the coordination overhead of true consensus -- but it does not benefit from the collaborative error-catching that consensus enables. Comparing RetryAgent (independent + judge) against true consensus approaches (H1, H2) is a high-value experiment.

4. **Trajectory-level instrumentation is best-in-class.** SWE-agent's detailed JSON trajectories, built-in cost tracking, and structured action logging make it the most measurement-friendly tool in the survey. Every thought, action, and observation is recorded with timestamps and token counts. This makes it an ideal candidate for detailed ablation studies within our benchmarking framework, and the trajectory format could serve as a reference standard for instrumenting other tools.
