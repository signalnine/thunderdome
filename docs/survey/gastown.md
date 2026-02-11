# Gas Town — Orchestrator Survey

**Tool:** Gas Town (https://github.com/steveyegge/gastown)
**Archetype:** Multi-agent workspace orchestrator
**Version surveyed:** Latest as of February 2026 (source: GitHub, blog posts, docs)

---

## 1. Architecture Type

**Hierarchical multi-agent system with role-based delegation and git-backed persistence.**

Gas Town is fundamentally different from every other tool in this survey. It is not a coding agent -- it is a **workspace manager that coordinates colonies of coding agents**. The human interacts with a single AI coordinator ("the Mayor"), who decomposes work, dispatches it to ephemeral and persistent worker agents, and manages the results. Gas Town itself never writes a line of code. The underlying coding agents (Claude Code, Codex, Cursor, Gemini, Auggie, Amp) do the actual implementation.

The architecture has **five layers**:

1. **The Mayor** -- AI coordinator and single human interface. Receives feature requests, decomposes them into work items (beads), creates convoys (work bundles), and dispatches tasks. The Mayor never writes code directly.
2. **Town** -- The workspace directory containing all projects and their associated infrastructure.
3. **Rigs** -- Project containers wrapping individual git repositories and their associated agents. Each rig is a self-contained project with its own set of workers.
4. **Hooks** -- Git worktree-based persistent storage that survives agent crashes. This is the core durability primitive -- each agent has a "hook" (a pinned bead) where work assignments are placed. The Gas Town Universal Propulsion Principle (GUPP) states: "When an agent finds work on their hook, they execute immediately."
5. **Crew Members** -- Human developer workspaces for persistent, long-term collaboration with specific agents.

**Agent roles form a hierarchy:**

| Role | Persistence | Function |
|------|-------------|----------|
| **Mayor** | Persistent | Coordinator, planner, human interface. Never codes. |
| **Polecats** | Ephemeral | Worker agents that spawn, execute a single isolated task in a git worktree, submit results, and disappear. |
| **Witness** | Per-rig | Supervisor that patrols active Polecats, nudges stalled workers, and escalates to the Mayor after 3 failed nudges. |
| **Refinery** | Persistent | Merge queue manager. Evaluates completed work, resolves git conflicts, and can "re-imagine" implementations that fail to merge cleanly. Functions as an automated release engineer. |
| **Deacon** | Persistent | System-level supervisor for triage and routing. |
| **Boot the Dog** | Ephemeral per tick | Daemon watchdog spawned fresh on each daemon tick. Observes system state, archives stale messages, decides on corrective actions. |
| **Crew** | Persistent | Human-managed, named agents for ongoing collaboration on specific projects. |

This is the most complex agent hierarchy in the survey. The key insight is that Gas Town treats coding agents as **disposable compute units** -- sessions are cheap, identity is persistent (stored as beads in git), and any agent can be killed and respawned without losing work state.

---

## 2. Context Strategy

Gas Town's approach to context is radical: **it assumes context is disposable and designs around that constraint.**

### Ephemeral Sessions, Persistent State

Instead of trying to keep a single session alive with a growing context window, Gas Town freely kills sessions and starts fresh ones. Work state is externalized into the beads system (git-backed JSON), so no information lives solely in an agent's context window. When a new session starts, it "seances" -- discovers and resumes the identity and work of the previous session through git-persisted metadata.

### gt prime -- Context Recovery

The `gt prime` command runs at session start (via SessionStart hook) and injects context without persisting it to disk. It outputs: session metadata, role-specific context, handoff content from the previous session, attachment status, and the previous session's checkpoint. This allows a freshly spawned agent to pick up exactly where the previous one left off.

### No Repo Mapping

Gas Town does not build a repository map or AST index. It delegates that responsibility entirely to the underlying coding agent (Claude Code, Cursor, etc.). The orchestrator concerns itself with **work coordination**, not code comprehension.

### Hook-Based Message Injection

Inter-agent communication happens through a mail system where messages are injected into hooks. The `gt mail check --inject` command pulls messages into an agent's context. This is a pull-based communication model -- agents check for messages rather than having them pushed into their context window.

### Implications for Context Endurance

Because Gas Town externalizes all state to git and freely restarts sessions, it has a natural **fresh-context strategy** that is architecturally enforced rather than opt-in. Stale context is not a problem because sessions are routinely killed. Boot the Dog archives stale handoff messages older than one hour. This is the strongest fresh-context implementation in the survey.

---

## 3. Planning Approach

**Mandatory plan-before-code via the Mayor.**

The Mayor is architecturally prohibited from writing code. Its sole function is to receive feature requests from the human, analyze them, decompose them into discrete work items (beads), group them into convoys, and dispatch them to appropriate agents. This enforces a planning phase by construction -- there is no code path where implementation happens without the Mayor first creating a plan.

The planning workflow (MEOW -- Mayor-Enhanced Orchestration Workflow):

1. **Tell the Mayor** -- Describe what you want in natural language.
2. **Mayor analyzes** -- Breaks the request down into atomic, trackable tasks.
3. **Convoy creation** -- Mayor creates a convoy (work bundle) containing beads (work items).
4. **Agent spawning** -- Mayor spawns appropriate agents (Polecats for one-off tasks, Crew for persistent work).
5. **Work distribution** -- Beads are "slung" to agents via hooks using `gt sling`.
6. **Progress monitoring** -- Track through convoy status (`gt convoy list`).
7. **Completion** -- Mayor summarizes results.

Unlike architect mode in Aider or plan mode in Claude Code, where the LLM may skip or abbreviate the planning step, Gas Town's architecture **makes planning unavoidable**. The Mayor cannot execute code, so it must delegate. Delegation requires specifying what to do. This is the strongest plan-before-code implementation in the survey, though the quality of the plans depends on the underlying LLM powering the Mayor.

---

## 4. Edit Mechanism

**Gas Town does not edit files.** It delegates all code editing to the underlying coding agent runtime.

When a Polecat is spawned with a task, it operates in its own git worktree using whatever coding agent the rig is configured for (Claude Code by default, but also Codex, Cursor, Gemini, Auggie, or Amp). The edit mechanism -- diff format, whole-file replacement, tool-use patterns -- is entirely determined by the runtime, not by Gas Town.

Gas Town's contribution to the edit pipeline is **isolation and merge management**:

- **Worktree isolation**: Each Polecat works in its own git worktree. No file locking is needed. Agents cannot interfere with each other's edits.
- **Branch management**: Polecat branches are visible to the Refinery immediately since they share refs.
- **Merge queue**: The Refinery evaluates completed work, resolves conflicts, and merges into main. If a merge fails, the Refinery can "re-imagine" the implementation -- essentially asking a fresh agent to redo the work with knowledge of what conflicted.

This separation of concerns is architecturally significant: Gas Town treats the coding agent as a black box and focuses on the coordination layer above it.

---

## 5. Self-Correction

Gas Town has multiple self-correction mechanisms, but they operate at the **orchestration level** rather than the code level.

### Witness Nudging

The Witness agent patrols active Polecats on a heartbeat schedule. If a Polecat appears stalled (no progress, no commits, unresponsive), the Witness nudges it -- injecting a prompt to get it back on track. After 3 failed nudges, the Witness escalates to the Mayor, who can kill the stalled agent and respawn a fresh one.

### Refinery Re-Imagination

When the Refinery encounters a merge conflict or a failing build from a Polecat's submission, it does not simply reject the work. It can "re-imagine" the implementation -- spawning a new agent with context about what went wrong and asking it to produce a compatible solution. This is a form of iterative refinement at the orchestration level.

### Crash Recovery via GUPP

The Gas Town Universal Propulsion Principle ensures that crashed agents resume work automatically. When an agent restarts and finds work on its hook, it executes immediately. Combined with `gt prime` for context recovery, this means crashes are self-healing at the workflow level.

### No Code-Level Self-Review

Gas Town itself does not perform code review, linting, or test execution. These responsibilities fall to the underlying coding agent and to the human reviewer. The Refinery evaluates mergeability (conflict resolution, build status) but does not perform semantic code review. The human remains the final quality gate.

### Session Handoff

When an agent's context fills up or a session degrades, Gas Town performs a handoff: the current session's state is checkpointed to git, the session is killed, and a fresh session is spawned that primes itself with the checkpoint. This is automatic self-correction for context degradation.

---

## 6. Gene List

### Genes Present

| Gene | Strength | Notes |
|------|----------|-------|
| **multi-agent-consensus** | Moderate | Multiple Polecats can work on related tasks in a convoy, and the Refinery reconciles their output. However, this is not true consensus (competing solutions to the same problem) -- it is parallel decomposition with merge-time reconciliation. |
| **fresh-context** | Strong | Core architectural principle. Sessions are disposable. Agents are routinely killed and respawned with fresh context via `gt prime` and the seance mechanism. GUPP ensures work survives restarts. This is the strongest fresh-context implementation in the survey. |
| **plan-before-code** | Strong | Architecturally enforced. The Mayor cannot write code; it must plan and delegate. MEOW workflow mandates decomposition before execution. |
| **iterative-refinement** | Moderate | Refinery re-imagination loop retries failed merges. Witness nudging unsticks stalled agents. But refinement happens at the orchestration level, not within individual coding sessions. |
| **tool-use** | Strong | Full `gt` CLI available to agents: `gt sling`, `gt convoy`, `gt mail`, `gt prime`, `bd` (beads CLI). Agents can create sub-tasks, communicate with each other, and manage their own work queues. |
| **multi-agent-review** | Weak | The Refinery evaluates merge compatibility but does not perform semantic code review. The Witness monitors progress but not code quality. No structured review-before-merge pipeline exists. |

### Genes Absent

| Gene | Notes |
|------|-------|
| **cross-provider-consensus** | Agents can use different runtimes (Claude Code, Codex, Cursor), but they work on different tasks, not competing solutions to the same task. No cross-provider voting or reconciliation. |
| **ralph-loop** | No explicit Ralph loop pattern (repeated fresh-context attempts at the same task). Closest analogue is Refinery re-imagination, but that is conflict-driven, not quality-driven. |
| **repo-mapping** | Gas Town has no code indexing. Delegates entirely to the underlying runtime. |
| **self-review** | No LLM self-review of generated code. Quality assurance is left to the human and to external test suites. |
| **test-first** | No built-in TDD workflow. The Mayor does not instruct agents to write tests before implementation unless the human explicitly requests it. |
| **prose-linting** | No natural-language quality checks. |
| **auto-pilot-brainstorm** | The Mayor plans and decomposes, but there is no autonomous brainstorming or exploration phase. The human provides the feature specification. |

### New Genes Discovered

| Gene | Description |
|------|-------------|
| **agent-disposability** | Sessions are treated as cheap, disposable compute. Identity and work state are externalized to git. Any agent can be killed and respawned without data loss. This inverts the traditional approach of keeping a session alive as long as possible. Gas Town's entire architecture is built on the assumption that sessions will die. |
| **orchestration-level-coordination** | The orchestrator never writes code -- it operates purely at the coordination layer. Work decomposition, dispatch, progress monitoring, conflict resolution, and re-dispatch are all orchestrator concerns. Code generation is a black-box capability provided by pluggable runtimes. This is a clean separation of concerns not seen in other tools. |
| **git-worktree-isolation** | Each parallel agent works in its own git worktree, eliminating file-level conflicts during execution. Conflicts are deferred to merge time and handled by a specialized agent (Refinery). This is the only tool in the survey that uses git worktrees as an isolation primitive. |
| **propulsion-principle** | The GUPP pattern: agents check their hooks on startup and execute immediately without confirmation. This eliminates the "stalled restart" failure mode and creates a self-healing workflow. Work is never lost because it is always on a hook, and hooks are always checked. |
| **supervisor-hierarchy** | Multi-level supervision: Witness monitors Polecats, Deacon handles triage, Boot the Dog monitors system health. Each level has escalation paths. This is the only tool with structured supervisory agents. |
| **seance-identity** | Agent identity persists across sessions via git-backed beads. A new session "seances" the identity of a previous one, resuming its role, work history, and context. Sessions are disposable; identities are not. |
| **merge-queue-as-agent** | The Refinery is an autonomous agent managing the merge queue, not a passive CI/CD pipeline. It can make decisions (resolve conflicts, re-imagine implementations, reject work) rather than simply reporting pass/fail. |

---

## 7. Benchmark-Relevant Traits

### Traits That Affect Task Design

1. **Gas Town is not a coding agent.** It is an orchestrator that wraps coding agents. Benchmarking Gas Town means benchmarking the entire system: Mayor + Polecats + Refinery + the underlying runtime (Claude Code, Codex, etc.). A fair comparison against single-agent tools like Aider must account for the fact that Gas Town has an entire coordination layer that single agents lack.

2. **Task decomposition is the Mayor's responsibility.** The benchmark harness provides a task description to the Mayor. The Mayor decides how to break it down. For simple tasks, this decomposition overhead may hurt performance (slower startup, more tokens spent on planning). For complex tasks, it may help (better parallelization, cleaner architecture). Task design should include both simple and complex tasks to test this tradeoff.

3. **Parallel execution changes the time dimension.** Gas Town can spawn multiple Polecats working simultaneously on different subtasks. Wall-clock time may be dramatically lower than sequential tools, but total token consumption may be higher. Benchmarks must measure both wall-clock time and total cost.

4. **Prerequisites are heavy.** Gas Town requires Go 1.23+, Git 2.25+, beads (bd) 0.44.0+, sqlite3, and tmux 3.0+, plus at least one underlying coding agent (Claude Code, Codex, etc.). The benchmark Docker container must include all of these.

5. **No single-task mode.** Gas Town is designed for multi-task orchestration. Using it for a single isolated task (e.g., "fix this bug") invokes the full Mayor/Polecat/Refinery pipeline, which is architecturally overkill. Simple benchmarks will measure the overhead of this coordination layer more than the quality of code generation.

### Traits That Affect Measurement

1. **Token accounting is complex.** Every agent session consumes tokens independently: the Mayor for planning, each Polecat for implementation, the Witness for supervision, the Refinery for merge resolution. Total token cost is the sum across all agents, which is fundamentally different from single-agent tools. The $100-200/hr API cost cited by Yegge reflects this multiplicative effect.

2. **Turn count is multidimensional.** In a single-agent tool, "turns" is straightforward. In Gas Town, there are Mayor turns (planning), Polecat turns (implementation), Witness turns (monitoring), and Refinery turns (merging). These happen in parallel across different sessions. A flat turn count is not meaningful; the benchmark must track turns per agent role.

3. **Git history provides rich instrumentation.** Because every Polecat works in its own branch and the Refinery manages merges, the git history is a detailed record of: how many agents were spawned, how many attempts each subtask required, which merges conflicted, which were re-imagined. This is far richer than the single-branch commit history of most tools.

4. **Context endurance is a non-problem by design.** Gas Town's fresh-context architecture means it should excel at marathon tasks (H3). Sessions are killed and restarted routinely. Context never goes stale because context windows are never pushed to their limits. This is the most direct test of H3 in the survey.

5. **Error recovery is architecturally strong.** GUPP, crash recovery via hooks, Witness nudging, and Refinery re-imagination provide multiple layers of error recovery. Benchmarks that test error recovery and broken-state escape should be a strong suit for Gas Town.

6. **Code quality depends on the underlying runtime.** Gas Town adds coordination quality (decomposition, parallelism, merge management) but delegates code quality entirely to the runtime. Measuring Gas Town's code quality is really measuring Claude Code's (or Codex's, etc.) code quality plus any benefit or harm from the decomposition.

### Scripting for Headless Benchmark Use

Gas Town is designed for interactive use via tmux sessions and is not straightforward to run headlessly. Key challenges and approaches:

```bash
# Install Gas Town and prerequisites
brew install gastown        # or: go install github.com/steveyegge/gastown@latest
brew install beads          # bd CLI for bead management

# Initialize a workspace
gt install ~/benchmark-town
gt rig add ~/benchmark-town/myproject --repo /path/to/task/repo

# The Mayor is an interactive tmux session -- headless use requires
# scripting the Mayor's session or using gt CLI commands directly.

# Direct CLI approach (bypass Mayor, script the pipeline):
# 1. Create a bead for the task
bd create --title "Implement feature X" --body "$(cat TASK.md)" --rig myproject

# 2. Sling the bead to a Polecat
gt sling <bead-id> myproject

# 3. Monitor convoy status
gt convoy list
gt convoy show <convoy-id>

# 4. Wait for Refinery to merge
# (requires gt daemon running for Witness/Refinery automation)
gt daemon start

# For fully automated benchmarking, the harness must:
# - Start the gt daemon (for Witness, Refinery, Boot)
# - Create beads programmatically via bd CLI
# - Sling beads to rigs
# - Poll convoy/bead status until completion
# - Collect git history, bead metadata, and session logs for analysis
```

The primary challenge is that Gas Town assumes a human is present to interact with the Mayor. For benchmarking, the harness must either: (a) script the Mayor's tmux session using tmux send-keys, (b) bypass the Mayor and use `gt sling` directly, or (c) use Claude Code's headless mode as the Mayor runtime and pipe task descriptions programmatically. Option (b) loses the Mayor's decomposition intelligence but is the most reliable for automation.

---

## Summary

Gas Town is the most architecturally ambitious tool in the survey, and also the most unconventional. Its key innovations are:

1. **Agent disposability as a design principle** -- Rather than fighting context window limits, Gas Town assumes sessions will die and externalizes all state to git. This is the strongest fresh-context implementation surveyed and directly tests H3 (fresh context vs. stale context loops).

2. **Orchestration-level separation of concerns** -- Gas Town never writes code. It manages work decomposition, dispatch, supervision, and merge resolution as a layer above pluggable coding runtimes. This is the only tool that cleanly separates "what to do" from "how to code it."

3. **Hierarchical supervision** -- Multiple specialized agent roles (Witness, Refinery, Deacon, Boot) provide structured oversight, escalation, and self-healing. No other tool has this level of supervisory architecture.

4. **Git as the coordination bus** -- Beads, hooks, worktrees, and branches are all git primitives. Git is not just version control; it is the communication, persistence, and isolation layer for the entire multi-agent system.

Its weaknesses for our benchmarks are significant: massive operational complexity ($100-200/hr, heavy prerequisites), no headless/scripting mode, no built-in code review or testing pipeline, and coordination overhead that may penalize simple tasks. It is also self-described as rough and early-stage, "vibecoded in 17 days."

Gas Town is the strongest candidate for testing H3 (fresh context vs. stale context) due to its architectural commitment to session disposability. It is also the best test of whether multi-agent coordination overhead pays for itself on complex tasks (a dimension not captured by the existing hypotheses but worth adding). For simple tasks, it will likely underperform single-agent tools due to Mayor/Polecat/Refinery overhead. For complex, multi-file, multi-concern tasks, the parallelism and decomposition may provide substantial advantages.
