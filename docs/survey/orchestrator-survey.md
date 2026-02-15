# Orchestrator Survey — Unified Analysis

**Scope:** 10 agentic coding tools spanning major architectural archetypes.
**Research date:** 2026-02-11
**Method:** Public documentation, published papers, blog posts, open-source code analysis.

---

## 1. Gene Matrix

Legend: **●** Strong | **◐** Moderate/Partial | **○** Weak/Opt-in | **—** Absent

| Gene | Aider | Claude Code | Claude Squad | SWE-agent | OpenHands | Superpowers | Gas Town | Amplifier | **Conclave** |
|------|-------|-------------|-------------|-----------|-----------|-------------|----------|-----------|------------|
| **multi-agent-consensus** | — | ○ (teams) | — | — | ◐ (scaling) | — | ◐ (convoy+merge) | — | **●** (council) |
| **cross-provider-consensus** | — | — | — | — | — | — | — | — | **●** (Claude×Gemini×Codex) |
| **ralph-loop** | — | — | — | ○ (Retry) | ◐ (condense) | ◐ (subagent) | — | — | **●** (first-class) |
| **fresh-context** | — | ● (subagents) | ● (per-session) | ○ (Retry) | ◐ (condense) | ● (subagents) | ● (disposable) | ◐ (sub-sessions) | **●** (ralph+worktree) |
| **plan-before-code** | ○ (architect) | ○ (plan mode) | — | — | ○ (think) | ● (mandatory) | ● (Mayor) | ◐ (zen-architect) | **●** (mandatory+consensus) |
| **repo-mapping** | ● (PageRank) | — | — | — | — | — | — | ○ (explorer) | — |
| **iterative-refinement** | ◐ (lint/test) | ● (agent loop) | ◐ (via agent) | ● (ReAct) | ● (exec loop) | ● (TDD+review) | ◐ (Refinery) | ◐ (delegation) | **●** (ralph+TDD+review) |
| **tool-use** | ○ (limited) | ● (rich) | ● (via agent) | ● (ACI) | ● (func call) | ● (from CC) | ● (gt CLI) | ● (modular) | **●** (inherited+CLI) |
| **auto-pilot-brainstorm** | — | ◐ (headless) | — | — | ○ | ◐ (skill) | — | ○ (explorer) | **●** (consensus autopilot) |
| **self-review** | — | ◐ (test/lint) | — | ○ (submit) | ○ (exec fb) | ● (verify) | — | — | **●** (verify+consensus) |
| **multi-agent-review** | — | ○ (config) | — | — | — | ● (two-stage) | ○ (Refinery) | — | **●** (3-stage+consensus) |
| **test-first** | — | — | — | — | — | ● (TDD) | — | — | **●** (mandatory TDD) |
| **prose-linting** | — | — | — | — | — | — | — | — | **◐** (SKILL.md + plan filenames) |

### Key Observations from the Matrix

1. **Only Conclave implements cross-provider consensus.** Every other tool either uses a single provider or uses multiple providers for sequential/role-based purposes (architect vs. editor), never for competing-then-reconciling solutions. Conclave is the sole test subject for H1.

2. **Planning enforcement is rare.** Only Superpowers and Conclave make planning mandatory (Conclave adds consensus gates at each planning transition). Most tools offer planning as an opt-in mode. This directly informs H2 — the control group (most tools) has no planning discipline.

3. **Self-correction is universal but shallow — with two exceptions.** Most tools rely on "run tests, feed errors back" as the sole quality signal. Superpowers has structured multi-agent review; Conclave extends this to six layers (TDD → ralph-loop test gate → spec gate → quality gate → two-stage subagent review → cross-provider consensus review).

4. **Context strategies diverge sharply.** Aider pre-indexes (PageRank repo map), Claude Code searches on-demand, OpenHands condenses, SWE-agent explores via ACI, Gas Town treats sessions as disposable, Claude Squad inherits from its underlying agent. This creates measurable differences in token efficiency and marathon task performance (H3).

5. **Three tools enforce plan-before-code structurally.** Superpowers via mandatory skill pipeline, Gas Town via architectural separation (Mayor cannot code), Conclave via mandatory pipeline plus consensus gates at each transition. All should outperform on tasks where planning prevents rework (H2), but at different cost profiles.

6. **prose-linting is nearly a universal gap.** Conclave has a SKILL.md and plan-filename linter (`conclave lint`) but it's scoped to skill authoring artifacts, not general documentation or commit messages. No tool checks general prose quality. This could be a benchmark dimension worth testing.

---

## 2. New Genes Discovered

Genes not in the original list, discovered across the survey:

| Gene | Found In | Description |
|------|----------|-------------|
| **agent-computer-interface** | SWE-agent | Purpose-built command interface for LLM interaction (not human UX). Structured commands, guardrails, concise feedback. |
| **context-condensation** | OpenHands | LLM-based summarization of old context when window fills. Preserves key details while freeing space. Linear vs. quadratic cost scaling. |
| **context-compaction** | Claude Code | Selective compression at ~92-98% utilization. Preserves key info, drops verbose tool outputs. Similar to condensation but triggered differently. |
| **discriminator-selection** | SWE-agent, OpenHands | Post-hoc evaluation of N independent attempts by a separate judge model. Separates generation from evaluation. |
| **edit-format-adaptation** | Aider | Dynamically selects edit format (whole/diff/udiff) based on which model is used. Matches communication protocol to LLM tendencies. |
| **semantic-repo-indexing** | Aider | Tree-sitter AST parsing + PageRank graph ranking of codebase symbols. Distinct from generic RAG. |
| **sandboxed-execution** | OpenHands, SWE-agent | Docker-isolated execution providing high-fidelity feedback (real errors, real tests) at cost of container overhead. |
| **event-stream-architecture** | OpenHands | Typed, chronological event stream as single source of truth. Enables deterministic replay and session recovery. |
| **syntax-guardrail** | SWE-agent | Hard prevention of syntactically invalid edits. Linter blocks edit application (not advisory). 3pp performance impact in ablation. |
| **mandatory-skill-enforcement** | Superpowers | Skills are non-optional — 1% applicability probability triggers mandatory invocation. Backed by anti-rationalization patterns. |
| **two-stage-review** | Superpowers | Sequential spec-compliance then code-quality review by separate agents. Ordering prevents quality review from masking spec violations. |
| **plan-persistence** | Superpowers | Plans stored as markdown on disk, surviving context compaction and enabling cross-session continuity. |
| **tmux-session-orchestration** | Claude Squad | Each agent runs in an isolated tmux session. TUI provides unified management. Lightweight alternative to container-per-agent. |
| **auto-commit-with-undo** | Aider | Every AI edit auto-committed to git. `/undo` reverts last AI commit. Separates human from AI commits. |
| **inference-time-scaling** | OpenHands | N parallel trajectories + trained critic model (TD-learned) selects best. Compute-for-quality tradeoff. |
| **skill-injection** | Superpowers | On-demand loading of domain-specific instruction packages that modify agent behavior. Progressive disclosure. |
| **observation-collapse** | SWE-agent | Observations older than N turns collapsed to single-line summaries. Keeps context focused on recent work. |
| **agent-disposability** | Gas Town | Sessions are cheap, disposable compute. Identity and state externalized to git. Any agent can be killed/respawned without data loss. |
| **orchestration-level-coordination** | Gas Town | Orchestrator never writes code — operates purely at coordination layer. Code generation is a black-box from pluggable runtimes. |
| **git-worktree-isolation** | Gas Town, Superpowers | Each parallel agent works in its own git worktree. Conflicts deferred to merge time. Filesystem-level isolation. |
| **propulsion-principle** | Gas Town | Agents check hooks on startup and execute immediately. Eliminates "stalled restart" failure mode. Self-healing workflow. |
| **supervisor-hierarchy** | Gas Town | Multi-level supervision: Witness monitors workers, Deacon handles triage, Boot monitors system health. Structured escalation. |
| **seance-identity** | Gas Town | Agent identity persists across sessions via git-backed beads. New sessions resume previous role/history. Sessions disposable; identities not. |
| **merge-queue-as-agent** | Gas Town | Autonomous agent managing merge queue (Refinery). Can resolve conflicts, re-imagine implementations, reject work. Not passive CI/CD. |
| **micro-kernel-composability** | Amplifier | Entire agent architecture decomposable into swappable modules. Any component replaceable independently. Enables A/B testing of individual choices. |
| **context-sink-delegation** | Amplifier | Heavy documentation loads only when specialist agent spawns, keeping parent sessions lean. Trades latency for context preservation. |
| **bundle-composition** | Amplifier | Composable YAML/Markdown config packages with inheritance, overlay merging, and cycle detection. Reproducible, version-controlled agent configs. |
| **metacognitive-recipes** | Amplifier | Code-orchestrated multi-stage workflows where each stage uses optimized AI configs. "Code for structure, AI for intelligence." |
| **description-driven-routing** | Amplifier | Agent delegation driven by meta.description field. LLM sees only description to decide routing. Prompt-engineered dispatch, no hardcoded rules. |
| **cross-provider-council** | Conclave | Three providers (Claude/Gemini/Codex) independently analyze the same artifact, then a chairman synthesizes into tiered consensus. Diversity from different architectures, not temperature variation. |
| **consensus-autopilot** | Conclave | Fully autonomous design exploration where the multi-provider council debates questions without human input. Human watches and can interrupt/override. |
| **tiered-gate-validation** | Conclave | Sequential gates (test → spec → quality) with different enforcement levels (hard/hard/soft). Separates correctness, completeness, and polish into distinct concerns. |
| **stuck-detection-with-strategy-shift** | Conclave | Same error hash 3+ times triggers "strategy shift" directive forcing a fundamentally different approach. Prevents repeated broken-fix loops. |
| **failure-branching** | Conclave | Exceeded iteration cap → work committed to `wip/ralph-fail-*` branch, not discarded. Preserves partial progress for human review. |
| **token-counting-proxy** | Conclave | Transparent HTTP reverse proxy between agent and API counting input/output tokens per request. SSE scanning for streaming. Enables precise cost measurement. |
| **checkpoint-recovery** | Conclave | Every workflow phase persists progress (brainstorm checkpoints, plan files, ralph-loop state JSON). Survives crashes, compaction, and session rotation. |
| **parallel-wave-execution** | Conclave | Dependency-respecting topological-sort waves, parallel within each wave (separate worktrees), squash-merge in plan order between waves. More structured than Gas Town's convoy. |

---

## 3. Per-Tool Notes

Only findings that are surprising or cannot be captured in the matrix.

### Aider

- **Edit format matters more than model choice.** Aider's research shows changing the edit format (whole vs. diff vs. udiff) can swing benchmark scores by 10-40+ percentage points for the same model. This is a confounding variable for any cross-tool benchmark.
- **PageRank repo map is genuinely novel.** No other tool uses graph-theoretic ranking for context selection. The 50x personalization boost for chat-active files is a clever design that biases toward relevance.
- **Infinite output continuation** is architecturally invisible — the user doesn't know when one API call ends and another begins. This means Aider can produce arbitrarily long edits, which matters for whole-file rewrites on large files.

### Claude Code

- **Agent teams are a distinct architectural mode**, not just "more subagents." Teammates have peer-to-peer messaging and shared task lists with file locking. This is closer to a distributed system than a parent-child delegation tree.
- **No repo map is a deliberate choice**, not a gap. Anthropic chose on-demand search over pre-built indexes because it avoids stale index problems and works identically on fresh codebases.
- **Context compaction is lossy in ways that matter.** Early-conversation instructions can be lost during compaction. For marathon tasks, this means instructions from phase 1 may not survive to phase 12.

### Claude Squad

- **Meta-orchestrator, not an agent itself.** Claude Squad manages multiple instances of existing agents (Claude Code, Aider, Codex, Gemini) in parallel tmux sessions with git worktree isolation. The intelligence comes from the underlying agent; Claude Squad provides the orchestration layer.
- **`--autoyes` mode enables hands-off operation.** Experimental auto-accept of all agent prompts, allowing fully background execution. Combined with session creation via prompt (`N` key), this enables batch task processing.
- **Architecturally similar to Gas Town** in its use of git worktrees for isolation and parallel agent execution, but lighter-weight — no supervisor hierarchy, no Mayor/Witness/Refinery stack, no propulsion hooks. Claude Squad is "just tmux + worktrees + a TUI."
- **No headless/programmatic API.** The tool is purely TUI-based, which creates challenges for Docker-based benchmarking. Sessions can be driven via tmux scripting but there is no `-p` pipe mode or structured output format.
- **Session lifecycle is manual.** Unlike Gas Town's automatic propulsion and restart, Claude Squad sessions must be explicitly created, resumed, and deleted by the user. The `checkout` command (commit + pause) and `resume` provide manual session control.

### SWE-agent

- **The ACI is the innovation, not the agent.** The SWE-agent paper's central claim is about interface design, not agent architecture. The 10.7pp improvement over raw Linux shell comes from better tool UX for LLMs.
- **100-line file viewer is empirically tuned.** The window size was tested at various sizes; 100 lines balances enough context for understanding with concise enough output to avoid flooding.
- **RetryAgent + discriminator** is structurally similar to OpenHands' inference-time scaling but uses a heuristic or LLM judge rather than a TD-trained critic. Comparing these two approaches could inform H1.

### OpenHands

- **Inference-time scaling with TD-learned critic** is architecturally unique. The critic is trained on (trajectory, outcome) pairs with temporal difference learning (discount=0.99). This is ML-in-the-loop, not just LLM-in-the-loop.
- **V1 SDK refactoring into 4 packages** (sdk, tools, workspace, agent_server) makes OpenHands the most modular platform. Components can be used independently or composed.
- **SWE-Bench Verified: 72.8% with Claude Sonnet 4.5** — the highest published score by any open-source tool. This is the ceiling of what single-agent + inference-time-scaling can achieve.

### Superpowers (Original)

- **Anti-rationalization patterns** are tested using Cialdini persuasion scenarios (time pressure, sunk cost, authority). This is the most rigorous approach to preventing LLM behavioral drift of any tool surveyed.
- **Skills are pressure-tested via TDD against subagent scenarios before deployment.** Skills are themselves software artifacts with tests — meta-quality-assurance.
- **The primary divergence point for the fork** is the absence of cross-provider consensus. The original uses only Claude; the fork adds Codex and Gemini routing via MCP tools.

### Gas Town

- **The Mayor never writes code.** This is architecturally enforced, not just a prompt instruction. The coordinator is structurally separated from implementation, making Gas Town the purest plan-then-delegate tool surveyed.
- **$100-200/hr in API costs** makes Gas Town the most expensive tool to benchmark. Each Polecat is a separate agent session. A convoy of 5 tasks spawns 5+ parallel sessions plus Mayor + Witness + Refinery overhead. Token accounting must aggregate across all sessions.
- **"Entirely vibecoded" in 17 days** (~189k lines of Go). The codebase itself is an artifact of the agentic coding workflow it orchestrates. Self-described as rough — "You probably don't want to use it yet."
- **Strongest fresh-context implementation.** Sessions are routinely killed and respawned. GUPP (propulsion principle) ensures work survives. This makes Gas Town the most direct test of H3 — it should excel at marathon tasks where other tools' context degrades.
- **Multi-runtime support** (Claude Code, Codex, Cursor, Gemini, Auggie, Amp) means Gas Town could theoretically provide cross-provider comparison at the task level, though agents work on different tasks, not competing solutions.

### Amplifier

- **Micro-kernel architecture (~2,600 lines core)** is the most modular platform surveyed. Providers, tools, orchestrators, context managers, and hooks are all swappable modules. This makes Amplifier uniquely suited for ablation studies — swap one component while holding others constant.
- **Bundle composition with inheritance and overlay merging** means agent configurations are reproducible and version-controlled. This is critical for benchmark reproducibility.
- **Early-stage project** with explicit "may change significantly" warning. The roadmap mentions moving away from Claude Code dependency toward "Agentic Loop Independence." Results may not reproduce across versions.
- **14 specialist agents** in the default foundation bundle (zen-architect, bug-hunter, explorer, web-research, etc.) with description-driven routing. The LLM decides which specialist to invoke based on descriptions — non-deterministic but flexible.
- **Metacognitive recipes** (Analyze -> Plan -> Implement -> Evaluate) are a novel middle ground between fully autonomous agents and manual pipelines, but require code-level setup to use.

### Conclave

- **The only cross-provider consensus tool in the survey.** Claude × Gemini × Codex independently analyze, then a chairman synthesizes. This is structurally different from OpenHands' inference-time scaling (same model, multiple trajectories) or SWE-agent's RetryAgent (independent attempts, post-hoc judge). Conclave's diversity comes from genuinely different model architectures.
- **Six-layer self-correction stack** is the deepest surveyed: (1) TDD red-green, (2) ralph-loop test gate, (3) spec compliance gate, (4) quality gate, (5) two-stage subagent review, (6) cross-provider consensus. The hypothesis is that each layer catches bugs the previous layers miss.
- **Ralph loop with stuck detection** prevents the common failure mode where an LLM repeatedly attempts the same broken fix. After 3 identical error hashes, a "strategy shift" directive forces a fundamentally different approach. This is a novel error-recovery mechanism.
- **Consensus Autopilot** enables fully autonomous design exploration — the council debates design questions without human input. No other tool combines autonomous brainstorming with cross-provider perspectives.
- **Token-counting proxy** (`conclave proxy`) provides precise cost measurement by intercepting API traffic. This is purpose-built for the benchmarking use case.
- **Platform-agnostic** — runs on Claude Code, Codex, and OpenCode. The same skill framework tested across different host platforms could isolate the skill layer's contribution.

---

## 4. Observations for Benchmark Design

### Cross-Cutting Patterns

**Pattern 1: The exploration-indexing spectrum.** Tools fall on a spectrum from pre-built indexes (Aider's PageRank map) through on-demand search (Claude Code's Grep/Glob) to dynamic exploration (SWE-agent's ACI commands). Token efficiency on feature and bugfix tasks should correlate with position on this spectrum. Greenfield tasks neutralize this advantage.

**Pattern 2: Self-correction depth varies from zero to six layers.** Aider has lint-fix + test-fix. SWE-agent has syntax guardrails + environment feedback. Claude Code has test/build/lint loops. Claude Squad inherits its underlying agent's self-correction. OpenHands adds execution feedback + stuck-loop detection + inference-time scaling. Superpowers adds mandatory TDD + two-stage review + verification-before-completion. Conclave extends to six layers (TDD + ralph-loop tiered gates + two-stage subagent review + cross-provider consensus). Deeper self-correction should correlate with higher completion rates but higher token costs. Testing this tradeoff is the core of H4.

**Pattern 3: Planning investment is front-loaded.** Superpowers spends significant tokens before any code is written. Other tools jump to implementation immediately. The question is whether planning overhead pays for itself — tasks where planning prevents design reversals (Task 2: Collab Server, Task 5: Task Queue) should favor Superpowers over jump-to-code tools.

**Pattern 4: Context management determines marathon viability.** For Task 5 (12-phase task queue), tools with no context management (Aider) will likely fail on smaller-window models. Tools with condensation (OpenHands, Claude Code) will degrade gracefully. Superpowers' fresh-subagent-per-task, Gas Town's disposable-session, Claude Squad's per-instance worktrees, and Conclave's fresh-context ralph-loop + worktree approaches all sidestep the problem entirely. This is the primary testbed for H3.

**Pattern 5: Orchestration overhead vs. task complexity tradeoff.** Gas Town and Amplifier add coordination layers that are expensive for simple tasks but potentially valuable for complex ones. Gas Town's Mayor/Polecat/Refinery pipeline is overkill for a 25-test CLI tool but potentially transformative for a 12-phase task queue. Benchmark results must be analyzed per-complexity-tier, not aggregated.

### Implications for Task Design

1. **Task 1 (CLI Time Tracker, greenfield/simple):** The great equalizer — every tool can attempt this. Measure whether planning overhead (Superpowers) or repo mapping (Aider) adds value on a task this simple.

2. **Task 2 (Collab Server, greenfield/complex):** Tests whether multi-agent review catches OT/CRDT convergence bugs that single-agent tools miss. Superpowers' two-stage review should shine. Claude Squad's parallel instances could divide the work but may struggle with cross-component integration.

3. **Task 3 (FTS Search, features/medium):** Tests codebase understanding — tools with repo mapping (Aider) should find existing code faster. SWE-agent's dynamic exploration adds overhead. The existing-test-regression trap tests self-correction depth.

4. **Task 4 (Phantom Invoice Bug, bugfix/medium):** The 20-line diff constraint tests precision. Claude Code's Edit tool naturally produces minimal diffs. SWE-agent's exact-match `str_replace` enforces precision. Red herrings test whether tools explore before fixing (plan-before-code) or jump to the first suspicious code.

5. **Task 5 (Task Queue, marathon):** The definitive H3 test. Prediction: Gas Town (disposable sessions) >= Superpowers (fresh subagents) > OpenHands (condensation) > Claude Code (compaction) > SWE-agent (observation collapse) > Aider (no management). Gas Town's architecture is purpose-built for this scenario. Claude Squad's per-session fresh context could also perform well if tasks are properly decomposed.

6. **Task 6 (Monorepo Disaster, recovery):** Tests diagnostic breadth — six interacting problems. Tools with stronger exploration (SWE-agent, OpenHands) may be better at finding all six issues. Tools with planning (Superpowers) may be better at coordinating fixes. The merge-conflict-markers trap tests whether tools read before editing.

### Implications for Measurement

1. **Token counting must be multi-model aware.** Claude Code uses Haiku for Explore subagents. OpenHands uses a critic model. Aider's architect mode uses two different models. Report tokens per model tier, not just total.

2. **Turn count definitions must be consistent.** Define: (a) user-visible turns (top-level interactions), (b) tool invocations (all tools across all agents), (c) LLM API calls (including subagent, review, and critic calls). Report all three.

3. **Configuration is a confounding variable.** Aider's edit format, SWE-agent's tool bundles, and OpenHands' condenser selection all significantly affect results. Document exact configuration per trial.

4. **Planning artifacts are measurable.** Superpowers produces plan files. Claude Code's TodoWrite produces JSON task lists. These can be evaluated for quality independently of implementation.

5. **Self-correction cost should be isolated.** Measure tokens spent on: (a) initial implementation, (b) lint/test/build feedback loops, (c) review cycles, (d) re-attempts. This decomposition reveals where each tool spends its error-correction budget.

---

## 5. Archetype Summary

| Archetype | Tool | Core Strength | Core Weakness | Best Task Fit |
|-----------|------|---------------|---------------|---------------|
| CLI turn-based | Aider | Token-efficient context (PageRank), edit format research | No autonomous operation, no context endurance | Short tasks with known file scope |
| CLI agentic | Claude Code | Rich tool use, flexible autonomy, subagent delegation | No repo index, lossy compaction | Medium tasks requiring exploration |
| Multi-instance orchestrator | Claude Squad | Parallel agent instances via tmux + git worktrees, lightweight | No planning, no review, depends entirely on underlying agent | Decomposable tasks benefiting from parallelization |
| Academic/research | SWE-agent | Best instrumentation (trajectories), syntax guardrails, ACI design research | No planning, exploration-heavy, no context management | Bugfix tasks (built for SWE-bench) |
| Multi-agent platform | OpenHands | Sandboxed execution, context condensation, inference-time scaling | Container overhead, no repo map | Complex tasks needing real execution feedback |
| Skill-injection | Superpowers | Mandatory planning + TDD + review, strongest quality gates | High front-loaded cost, Claude-only | Complex tasks where architecture quality matters |
| Multi-agent workspace | Gas Town | Strongest fresh-context (disposable sessions), parallel execution, supervisor hierarchy | Very expensive ($100-200/hr), rough maturity, heavy prerequisites | Complex tasks benefiting from parallelization |
| Micro-kernel platform | Amplifier | Most modular (swappable everything), ideal for ablation studies, bundle composition | Early stage, no built-in consensus, no auto test loop | Research platform for testing architectural variations |
| Cross-provider consensus | Conclave | Only cross-provider consensus (Claude×Gemini×Codex), deepest self-correction (6 layers), mandatory planning + TDD | Highest token cost (planning + ralph-loop + consensus at 7 checkpoints) | Complex tasks where quality gates and error diversity matter (H1, H4) |

---

## 6. Hypothesis Mapping

| Hypothesis | Most Relevant Tools | Key Comparison |
|-----------|-------------------|----------------|
| **H1:** Cross-provider consensus outperforms same-model consensus on defect catch rate | Conclave vs. Superpowers Original vs. OpenHands (inference-time scaling) | Does cross-provider diversity catch more bugs than N-of-same-model? |
| **H2:** Multi-agent consensus reduces design reversals vs. solo agents | Superpowers (mandatory planning + review) vs. Gas Town (Mayor-planned) vs. Claude Code (optional planning) vs. SWE-agent (no planning) | Does enforced planning + review prevent rework? |
| **H3:** Fresh context Ralph loops outperform stale-context loops on marathon tasks | Gas Town (disposable sessions) vs. Superpowers (fresh subagents) vs. Claude Squad (per-session worktrees) vs. OpenHands (condensation) vs. Claude Code (compaction) vs. Aider (none) | Which context strategy preserves coherence across 12 phases? |
| **H4:** Consensus overhead pays for itself in reduced rework | Superpowers (two-stage review, ~2x) vs. Gas Town (Refinery merge, ~5-10x) vs. Claude Code (no review, ~1x) vs. SWE-agent (RetryAgent, ~5x) | Do review/coordination tokens save more rework tokens than they cost? |
