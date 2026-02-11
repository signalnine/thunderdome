# OpenHands — Orchestrator Survey

**Tool:** OpenHands (https://openhands.dev / https://github.com/All-Hands-AI/OpenHands)
**Archetype:** Multi-agent platform with sandboxed execution
**Version surveyed:** Latest as of February 2026 (source: docs, GitHub, ICLR 2025 paper, SDK paper arxiv:2511.03690)

---

## 1. Architecture Type

**Multi-agent platform with event-stream coordination, hierarchical delegation, and sandboxed execution.**

OpenHands (formerly OpenDevin) is a platform for building and running AI software agents. Unlike single-agent CLI tools, OpenHands provides a full agent runtime with Docker-based sandboxing, an event-stream communication backbone, and support for multi-agent delegation. The architecture has undergone a major refactoring from V0 (monolithic, sandbox-centric) to V1 (modular SDK with four packages).

### Core Components

1. **AgentController** -- The central orchestrator. It initializes the agent, manages `ConversationState`, and drives the main step loop. At each step, the controller pushes state to the agent, receives an action, routes the action to the event stream, and collects the resulting observation.

2. **EventStream** -- The communication backbone. All interactions (user messages, agent actions, sandbox observations, system events) flow through the event stream as typed, immutable events. Any component can publish events or subscribe to events published by others. The event stream is the single source of truth for conversation history.

3. **Runtime (Sandbox)** -- A Docker container spun up per session. The runtime receives actions from the AgentController over a RESTful API and executes them in an isolated environment. It manages bash shells, Jupyter/IPython kernels, browser instances, and file operations. The host system is never directly exposed to agent-generated code.

4. **Agent** -- A pluggable component that consumes state (the event history) and produces an action. The default agent is CodeActAgent, but OpenHands supports multiple agent types including BrowsingAgent and custom micro-agents.

### V1 SDK Architecture (Four Packages)

The 2025 V1 refactoring splits the monolith into four independently testable packages:

| Package | Responsibility |
|---------|---------------|
| `openhands.sdk` | Core abstractions: Agent, Conversation, LLM, Tool, MCP interfaces. Stays lightweight for diverse integrations. |
| `openhands.tools` | Concrete tool implementations built on SDK abstractions. Isolated so slow tool tests do not block core changes. |
| `openhands.workspace` | Execution environments (Docker, hosted APIs). Optional sandboxing without bloating the core. |
| `openhands.agent_server` | REST/WebSocket API server for remote execution. Usable with or without containers. |

The SDK defines an **event-sourced state model with deterministic replay**: immutable events are appended to a log, conversation state is the only mutable entity, and any session can be recovered by loading base state and replaying subsequent events.

### Agent Types

- **CodeActAgent** -- The primary generalist agent based on the CodeAct framework (ICLR 2025). Consolidates all agent actions into a unified code action space: bash commands, Python execution, file editing, and browser control via function calls. Version 2.1 switched to Anthropic-style function calling for precision.
- **BrowsingAgent** -- Specialist for web navigation and web-based task execution. CodeActAgent can delegate web tasks to BrowsingAgent via `AgentDelegateAction`.
- **Micro-agents** -- Community-contributed specialized agents that inherit from a generalist agent but add domain-specific prompts and tool configurations.
- **Custom agents** -- The SDK allows registering custom agent factories with specialized system messages and tool sets.

---

## 2. Context Strategy

OpenHands takes a fundamentally different approach to context than tools like Aider. Instead of a static repo map, it maintains a **chronological event stream** and applies **condensation** when it grows too large.

### Event Stream as Context

The agent's context is the full event stream: every action the agent took, every observation returned by the sandbox, every user message, and every system event. This means the LLM sees a rich, structured history of what was attempted and what happened, but the history grows linearly with each step.

### Context Condensation (LLMSummarizingCondenser)

When the event stream exceeds a configurable threshold (`max_size`), OpenHands triggers condensation:

1. **Recent events are preserved intact** -- the most recent messages remain unmodified for immediate context.
2. **First events are pinned** -- the `keep_first` parameter preserves initial system prompts and opening messages (typically 2 events).
3. **Middle events are summarized** -- an LLM generates a concise summary encoding the user's goals, progress made, technical details (critical files, failing tests), and remaining work.
4. **The summary replaces the dropped events** -- via a `CondensationAction` event inserted into the stream.

This produces **linear cost scaling** over time instead of the quadratic scaling seen with unbounded context. OpenHands reports up to 2x reduction in per-turn API costs with condensation enabled.

### Condenser Types

| Condenser | Behavior |
|-----------|----------|
| `LLMSummarizingCondenser` | Default. Uses an LLM to generate summaries when history exceeds `max_size`. Configurable `keep_first` and model selection. |
| `RecentEventsCondenser` | Drops old events, keeps only the N most recent. Simple but lossy. |
| `ObservationMaskingCondenser` | Selectively masks verbose observation payloads (e.g., large command outputs) while preserving action structure. |
| `BrowserOutputCondenser` | Specialized for reducing costs during web browsing sessions where browser state descriptions are verbose. |
| `NoOpCondenser` | Returns history as-is. Useful for short tasks or debugging. |

Custom condensers can extend `RollingCondenser` (for rolling-window strategies) or `CondenserBase` (for arbitrary strategies). Condensation pipelines can chain multiple condensers.

### No Static Repo Map

Unlike Aider's PageRank-based repository map, OpenHands does not build a static index of the codebase. The agent discovers the repository structure dynamically by executing commands (`find`, `ls`, `grep`, `cat`) in the sandbox. This is more flexible (works with any project structure) but consumes more tokens for initial exploration.

---

## 3. Planning Approach

**Implicit planning via chain-of-thought; no dedicated plan artifact.**

CodeActAgent does not produce an explicit plan document before beginning work. Instead, planning emerges through the LLM's chain-of-thought reasoning at each step. The agent processes observations, reasons about what to do next, and emits an action. This is iterative planning, not upfront planning.

### Think Tool

CodeActAgent includes a `think` tool that allows the agent to reason without producing a visible action. This enables multi-step reasoning within a single turn, but the output is not persisted as a structured plan that can be referenced later.

### Planning Initiatives (In Progress)

OpenHands has explored but not yet fully shipped a dedicated planning mechanism:

- A **TODO.md planning tool** has been proposed (GitHub issue #9970) that would maintain a persistent task list updated as the agent progresses.
- An **Ask/Plan mode** (GitHub issue #557) has been discussed that would let users switch between planning and execution modes.
- Current long-horizon prompts exist but have known limitations -- the agent tends to update the entire task list at once rather than step by step.

### Implications

The lack of explicit planning means OpenHands relies heavily on the LLM's inherent reasoning ability. Strong models (Claude Sonnet 4.5, GPT-5) produce effective implicit plans. Weaker models may struggle with task decomposition on complex tasks. This contrasts with tools that enforce plan-before-code as a structural constraint.

---

## 4. Edit Mechanism

**Multi-modal: str_replace_editor (primary), bash commands, IPython, and direct file writes.**

OpenHands provides several mechanisms for modifying files, with the choice depending on the action type:

### str_replace_editor (Primary)

The main file editing tool, originally implemented via IPython in the sandbox but later refactored to run directly in the runtime server. It implements `str_replace`-style editing: the agent specifies a file, a search string, and a replacement string. This is similar to Anthropic's Claude Code edit mechanism.

The tool supports:
- **view**: Read file contents or specific line ranges.
- **create**: Create a new file with specified contents.
- **str_replace**: Replace a specific string occurrence in a file.
- **insert**: Insert text at a specific line number.

The str_replace approach avoids the need for the LLM to produce entire file contents or complex diff formats, reducing errors on partial edits.

### Bash-Based Editing

The agent can also modify files using standard Unix tools (`sed`, `awk`, `echo >>`, etc.) via the bash tool. This is less structured but sometimes preferred by the LLM for simple appends or substitutions.

### IPython Code Execution

For data science and scripting tasks, the agent can write and execute Python code in a persistent Jupyter kernel via `IPythonRunCellAction`. The kernel maintains state across cells, enabling iterative development with immediate feedback.

### FileEditAction / FileWriteAction

Lower-level action types that write file contents directly. `FileEditAction` produces a git-patch-style observation, enabling diff visibility. The system supports detection of multiple patch formats (unified diff, git diff, context diff, ed scripts).

### Draft Editor

OpenHands supports a `draft_editor` configuration that specifies a separate, cheaper LLM for preliminary code drafting, with the primary model refining the output.

---

## 5. Self-Correction

**Strong self-correction through execution feedback loops, loop detection, and inference-time scaling.**

### Execution-Based Feedback Loop

The core self-correction mechanism is inherent to the CodeAct architecture: the agent writes code, executes it in the sandbox, observes the output (including errors), and adjusts. This is a tight perception-action loop:

1. Agent emits a `CmdRunAction` (e.g., `pytest tests/`).
2. Sandbox executes the command and returns `CmdOutputObservation` with stdout/stderr.
3. Agent reads the output, identifies failures, and emits corrective actions.

Because execution happens in a real environment (not simulated), feedback is high-fidelity: actual error messages, stack traces, test results, and exit codes.

### Agent Stuck-in-Loop Detection

OpenHands implements `AgentStuckInLoopError` detection: if the agent repeats the same action pattern multiple times (e.g., three identical empty commands while waiting for a long-running process), the controller flags it and enters an error state. Recovery is possible by receiving new user input, rather than hard-terminating the session.

### Max Iteration Limits

A configurable `max_iterations` parameter caps the total number of agent steps per session, preventing runaway loops. When reached, the agent terminates with a `RuntimeError`.

### Retry Mechanism

An `exclude_exceptions` retry decorator handles transient failures (API timeouts, container issues) while blacklisting non-retriable exceptions. This prevents unnecessary retries on deterministic failures.

### Inference-Time Scaling with Critic Model

OpenHands achieved SOTA on SWE-Bench Verified through a sophisticated inference-time scaling approach:

1. For each problem, run the agent **multiple times** (N trajectories) with temperature 1.0.
2. Each trajectory produces a candidate code patch.
3. A **trained critic model** (fine-tuned Qwen 2.5 Coder 32B) evaluates each trajectory and predicts solution quality.
4. The best-scoring trajectory is selected.

The critic was trained using temporal difference (TD) learning: the final reward (1 for passing tests, 0 for failing) is propagated backward through each trajectory with discount factor 0.99. Performance scales log-linearly from 60.6% (1 attempt) to 66.4% (5 attempts) on SWE-Bench Verified.

### No Explicit Self-Review Step

The agent does not perform a separate "review my own work" step before declaring completion. Self-correction is implicit through the execution feedback loop, not through an explicit review phase.

---

## 6. Gene List

### Genes Present

| Gene | Strength | Notes |
|------|----------|-------|
| **tool-use** | Strong | Core architectural feature. CodeActAgent uses function calling to invoke bash, IPython, file editor, and browser tools. Tools are typed (Action/Execution/Observation pattern) with Pydantic validation. MCP tool integration is first-class. |
| **iterative-refinement** | Strong | Inherent to the execution loop. Agent runs code, observes output, corrects errors, re-runs. The sandbox provides real execution feedback, not simulated. |
| **ralph-loop** | Moderate | Context condensation provides a form of fresh-context restart by summarizing old events and freeing up context window. Not a full "throw away and restart" pattern, but achieves similar effect on token budget. |
| **fresh-context** | Moderate | Condensation replaces stale context with summaries, keeping the working context relatively fresh. However, summarization is lossy and may drop important details. |
| **multi-agent-consensus** | Moderate | Inference-time scaling with critic model runs N parallel attempts and selects the best. This is a form of multi-trajectory consensus, though the agents do not communicate during execution. |
| **plan-before-code** | Weak | No explicit planning step. The `think` tool enables reasoning, but there is no enforced plan-then-execute structure. Planning improvements are in development. |
| **auto-pilot-brainstorm** | Weak | The agent autonomously explores the codebase and reasons about approaches, but there is no dedicated brainstorming phase separate from execution. |
| **self-review** | Weak | No explicit self-review step. Self-correction is implicit through execution feedback and error observation. |

### Genes Absent

| Gene | Notes |
|------|-------|
| **cross-provider-consensus** | Multiple LLM backends are supported, but there is no mechanism for running the same task on different providers simultaneously and comparing outputs. The critic model uses a single fine-tuned model, not cross-provider comparison. |
| **multi-agent-review** | Sub-agents do not review each other's work. Delegation is task-partitioned (each agent works independently), not review-oriented. |
| **test-first** | The agent does not generate tests before implementation as a structural constraint. It may write tests as part of its solution, but this is LLM-driven behavior, not enforced by the architecture. |
| **prose-linting** | No natural-language quality checks on documentation, commit messages, or comments. |
| **repo-mapping** | No static repository map or index. Codebase understanding is built dynamically through sandbox exploration (ls, find, grep, cat). |

### New Genes Discovered

| Gene | Description |
|------|-------------|
| **sandboxed-execution** | All agent actions execute inside Docker containers with security boundaries. This provides high-fidelity feedback (real compilation errors, real test results) at the cost of container setup overhead. The sandbox also prevents the agent from corrupting the host system, enabling truly autonomous operation. |
| **event-stream-architecture** | All communication flows through a typed, chronological event stream. Actions and observations are first-class events, enabling deterministic replay, session recovery, and clean separation between agent logic and execution. This is fundamentally different from the prompt-stuffing approach of single-agent tools. |
| **context-condensation** | LLM-based summarization of old events when context grows too large. Preserves goals, progress, and technical details while discarding redundant history. Achieves linear cost scaling instead of quadratic. This is a more sophisticated context management strategy than simple truncation or sliding window. |
| **inference-time-scaling** | Running N parallel agent trajectories and using a trained critic model to select the best one. This is a compute-for-quality tradeoff that achieves SOTA results but multiplies cost by N. The critic model itself is a learned component (TD-trained on agent trajectories), not a heuristic. |
| **agent-delegation** | Hierarchical task decomposition via `AgentDelegateAction` and `DelegateTool`. A parent agent spawns sub-agents, assigns independent subtasks, and consolidates results. Sub-agents run in parallel threads with configurable concurrency limits (`max_children`). Each sub-agent has its own conversation context but shares the workspace. |
| **workspace-abstraction** | Same agent code can run locally (in-process, against local filesystem) or remotely (serialized config, delegated to agent server over HTTP/WebSocket). This "local-first, deploy-anywhere" pattern enables rapid prototyping and production deployment without code changes. |

---

## 7. Benchmark-Relevant Traits

### Traits That Affect Task Design

1. **Full sandbox autonomy.** Unlike tools that require human approval, OpenHands in headless mode runs with `always-approve` semantics. The agent can execute arbitrary bash commands, install packages, run tests, and modify any file without confirmation. Tasks can be designed assuming full autonomy without needing a human-approval shim.

2. **Dynamic codebase discovery.** OpenHands has no pre-built repo map. The agent must spend initial turns exploring the codebase (`find`, `grep`, `cat`). Tasks should account for this exploration overhead in turn count and token measurements. Alternatively, the system prompt can include initial orientation instructions.

3. **Container startup latency.** Each session spins up a Docker container, which adds startup time (typically 10-30 seconds depending on the base image). For benchmarks measuring wall-clock time, this overhead must be accounted for. Custom Docker images with pre-installed dependencies can reduce this.

4. **Multi-agent delegation is available but optional.** The agent delegation system allows parallel sub-agent execution, but CodeActAgent does not use it by default. Benchmarks testing multi-agent behavior must explicitly configure delegation, or test a custom agent that uses `DelegateTool`.

5. **Arbitrary execution environment.** OpenHands supports custom Docker images, meaning the sandbox can include any OS, language runtime, or toolchain. Tasks can specify complex environments (specific Python versions, database servers, etc.) by providing a Docker image, which is a significant advantage over tools limited to the host environment.

### Traits That Affect Measurement

1. **Token cost is dominated by event stream size.** Because the full event history (or its condensed summary) is sent to the LLM at each step, token usage correlates with session length. Condensation reduces this, but the initial turns (before condensation triggers) accumulate rapidly. Token measurement should track both raw event count and post-condensation context size.

2. **Exploration overhead inflates token counts.** The lack of a repo map means OpenHands spends tokens on file discovery that tools like Aider do not. When comparing token efficiency, this structural difference should be acknowledged -- OpenHands trades upfront indexing for runtime flexibility.

3. **Inference-time scaling multiplies cost linearly.** Using the critic model approach (N trajectories per problem) multiplies both token cost and wall-clock time by N. Benchmarks should report both single-trajectory and best-of-N results to separate agent capability from compute budget.

4. **Condensation quality affects long-task performance.** For marathon tasks, the quality of context condensation directly affects whether the agent can maintain coherence across many phases. Poor summaries lose critical details; good summaries preserve them. This is a testable dimension.

5. **SWE-Bench performance is well-documented.** OpenHands publishes extensive SWE-Bench results across multiple model configurations. On SWE-Bench Verified: Claude Sonnet 4.5 achieves 72.8%, GPT-5 (reasoning=high) achieves 68.8%. On SWE-Bench Live (harder, no data leakage): 19.25% with Claude 3.7 Sonnet. These provide strong baselines for comparing our benchmark results.

6. **The OpenHands Index provides multi-dimensional benchmarks.** Their continuously updated leaderboard evaluates issue resolution, greenfield development, frontend development, software testing, and information gathering. This multi-dimensional approach aligns well with our benchmark categories.

### Scripting for Headless Benchmark Use

```bash
# Single-task headless execution
openhands --headless \
  -t "Fix the bug described in TASK.md and ensure all tests pass" \
  --model claude-sonnet-4.5

# Task from file with JSON output for programmatic parsing
openhands --headless \
  --json \
  -f task.txt \
  --model claude-sonnet-4.5 \
  > output.jsonl

# Python SDK for programmatic control (V1 SDK)
from openhands.sdk import Agent, Conversation
from openhands.sdk.llm import LLM

llm = LLM(model="claude-sonnet-4.5", api_key="...")
agent = Agent(llm=llm)

conversation = Conversation.local(
    agent=agent,
    workspace_dir="/path/to/repo",
)

result = conversation.run(
    "Fix the bug described in TASK.md and ensure all tests pass"
)
print(result.state)  # ConversationState with full event history

# Using the evaluation harness for SWE-Bench-style evaluation
# (from OpenHands/evaluation/benchmarks/)
python evaluation/benchmarks/swe_bench/run_infer.py \
  --model claude-sonnet-4.5 \
  --dataset swe-bench-verified \
  --max-iterations 30 \
  --output-dir results/
```

---

## Summary

OpenHands is architecturally the most ambitious platform in this survey. Its key characteristics and implications for benchmarking:

1. **Event-stream architecture provides unprecedented observability.** Every action, observation, and internal event is typed, serialized, and replayable. This makes OpenHands exceptionally well-suited for benchmarking -- we can capture the full agent trajectory, replay sessions deterministically, and measure granular metrics (per-step latency, per-action token cost, error recovery patterns) that are opaque in simpler tools.

2. **Sandboxed execution enables true autonomy but adds overhead.** The Docker-based sandbox means the agent gets real execution feedback (actual test results, real compilation errors), which is higher fidelity than tools that merely suggest commands. However, container setup and the lack of a pre-built repo map add startup cost. For short tasks, this overhead is proportionally significant; for complex tasks, it pays for itself through more accurate self-correction.

3. **Context condensation is the key differentiator for marathon tasks.** OpenHands is the only tool in the survey with a built-in, configurable strategy for managing growing context. The LLMSummarizingCondenser directly addresses hypothesis H3 (fresh context vs. stale context). Benchmarks should test condensation quality by measuring whether the agent maintains coherence across long, multi-phase tasks.

4. **Inference-time scaling with a critic model represents a distinct compute-quality tradeoff.** The ability to run N parallel trajectories and select the best one via a trained critic model is architecturally unique. This directly tests whether "trying harder" (spending more compute) produces better results, which is relevant to hypothesis H1 (consensus mechanisms) and has clear implications for cost-effectiveness measurement. Benchmarks should report both single-shot and best-of-N results.
