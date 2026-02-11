# Conclave — Orchestrator Survey

**Tool:** Conclave (https://github.com/signalnine/conclave)
**Archetype:** Cross-provider consensus framework (skill-injection + multi-agent consensus)
**Vendor/Author:** Gabe (signalnine)
**Source:** Open-source, MIT license (forked from obra/superpowers)
**Version surveyed:** Latest as of February 2026
**Research date:** 2026-02-11
**Method:** Direct source code inspection, README, CLAUDE.md, skill files

---

## 1. Architecture Type

**Skill-injection framework with cross-provider multi-agent consensus, layered on Claude Code (also supports Codex and OpenCode).**

Conclave is a fork of Superpowers (Original) that adds one architecturally transformative capability: **cross-provider consensus using Claude, Gemini, and Codex as independent reviewers**. The underlying skill-injection framework is inherited from Superpowers — mandatory workflow skills, THE RULE enforcement, anti-rationalization patterns — but every major workflow checkpoint now triggers a multi-provider council review.

The core agent loop remains Claude Code's single-threaded tool-call loop (or Codex/OpenCode equivalent). Conclave modifies behavior through:

1. **Session-start hook** — injects the `using-conclave` skill into every session, establishing mandatory skill activation.
2. **16 composable skills** — each with a `SKILL.md` containing YAML frontmatter and DOT/GraphViz flowcharts as executable specifications.
3. **Multi-agent consensus engine** — a two-stage bash pipeline (`consensus-synthesis.sh`) that runs Claude/Gemini/Codex in parallel via direct API calls (curl + jq), then synthesizes findings through a chairman agent.
4. **Ralph loop runner** — autonomous iteration wrapper that runs `claude -p` in fresh context per retry (max 5 attempts), with stuck detection, failure branching, and tiered gate validation.
5. **Parallel task runner** — creates git worktrees for concurrent task execution with topological-sort scheduling respecting task dependencies, then squash-merges completed tasks with conflict detection.

**Platform support:** Unlike Superpowers (Claude-only), Conclave runs on three platforms:
- **Claude Code** — native plugin via `.claude-plugin/`, hooks, skills, commands, agents
- **Codex** — unified Node.js script + bootstrap markdown
- **OpenCode** — native JS plugin

**Key architectural divergence from Superpowers Original:** The original operates exclusively within the Claude ecosystem. Conclave adds cross-provider consensus at 7 workflow checkpoints, making it the only tool in the survey that structurally combines work from different LLM providers to catch errors.

---

## 2. Context Strategy

**Inherited skill-based progressive disclosure + fresh-context subagents + ralph-loop fresh context per iteration + plan persistence on disk.**

Conclave's context strategy combines mechanisms from Superpowers Original with fresh-context innovations:

### Progressive Skill Disclosure

Skill descriptions are loaded at session start (lightweight metadata), but full skill content loads only when invoked. This prevents the ~16 skills from consuming context.

### Fresh Context Per Ralph Loop Iteration

The ralph loop is the primary context management innovation. Each iteration runs `claude -p` as a completely fresh invocation — no conversation history carries over. State is tracked externally:

- **`.ralph_state.json`** — machine-readable JSON with iteration count, last gate failed, error hash, stuck count, and attempt history.
- **`.ralph_context.md`** — LLM-readable markdown with status, last error output verbatim, and strategy shift directives.

This means the implementation agent for each retry gets: (1) the task spec, (2) structured failure context from previous attempts, (3) nothing else. No stale conversation, no accumulated tool outputs, no context pollution.

### Fresh Context Per Parallel Task

The parallel runner (`parallel-runner.sh`) creates a separate git worktree per task. Each task runs through its own ralph-loop instance, meaning each task gets both filesystem isolation (worktree) and context isolation (fresh `claude -p` per retry).

### Plan Files as External Memory

Implementation plans are stored as markdown files in `docs/plans/`. The controller agent reads the plan, parses tasks and dependencies, and dispatches work — but the plan file itself is the source of truth, not the conversation context. Plans survive context compaction and session restarts.

### Consensus Reports as Checkpoints

Multi-agent consensus outputs are saved to `/tmp/consensus-XXXXXX.md` with full Stage 1 analyses from all providers. These serve as external memory for review decisions.

### No Repo Map

Like Superpowers Original, Conclave does not build a repo map or codebase index. It relies on the underlying platform's search tools (Claude Code's Grep/Glob/Read, Codex's tools, etc.) for code discovery.

---

## 3. Planning Approach

**Mandatory multi-phase pipeline with cross-provider consensus at every gate: brainstorm → write plan → execute plan.**

Conclave inherits Superpowers' mandatory planning pipeline and enhances each phase with consensus:

### Phase 1 — Brainstorming

Activates before any code is written. Two modes:

1. **Interactive** — Socratic questioning, one question at a time, user answers.
2. **Consensus Autopilot** — the council of Claude/Gemini/Codex debates each design decision while the user watches. The user can interrupt anytime to override.

Brainstorming includes session recovery via checkpoint files (`.brainstorm-checkpoint-*.json`), enabling resume after interruption. Design documents are saved to `docs/plans/`.

**Consensus gate:** Design validation by the full council before proceeding to planning.

### Phase 2 — Writing Plans

Decomposes approved design into bite-sized tasks (2-5 minutes each). Each task includes:
- Exact file paths (create/modify/test)
- Complete code
- Dependency declarations (for topological sorting)
- Verification steps

Plans assume "the engineer has zero context for the codebase and questionable taste" — they are self-contained.

**Consensus gate:** Architecture/risk/scope validation by the council.

### Phase 3 — Execution

Two execution models:

1. **Subagent-driven development** (autonomous) — parses plan into dependency DAG, computes parallel waves, creates worktrees per task, launches `conclave ralph-run` in parallel, polls for completion, squash-merges in plan order, handles conflicts by re-running from merged state.
2. **Executing-plans** (checkpointed) — batch execution with human review between batches.

**Consensus gate:** Per-task review during execution, final review before merge.

### Anti-Skip Enforcement

Inherited from Superpowers: THE RULE requires skill invocation whenever applicable (even 1% probability). Anti-rationalization patterns block common excuses for skipping planning.

---

## 4. Edit Mechanism

**Inherited from underlying platform. No custom edit tooling.**

Conclave does not introduce its own edit mechanism. All file modifications use the host platform's native tools:

- **Claude Code:** Edit (exact string match replacement), MultiEdit (atomic multi-edit), Write (whole file)
- **Codex:** native file editing tools
- **OpenCode:** native file editing tools

The behavioral difference from vanilla platform use is that edits follow the TDD discipline: RED-GREEN-REFACTOR cycle means (1) write failing test, (2) write minimal code to pass, (3) refactor while keeping tests green. Code written before tests is deleted.

---

## 5. Self-Correction

**Multi-layered: ralph-loop autonomous iteration + cross-provider consensus review + TDD verification + stuck detection + verification-before-completion.**

Conclave has the deepest self-correction stack of any tool surveyed, combining inherited Superpowers mechanisms with new consensus and ralph-loop capabilities:

### Ralph Loop (Fresh-Context Retry)

The primary self-correction mechanism. Each task runs through up to 5 iterations with tiered gates:

1. **Test gate** (hard) — auto-detects test runner (npm/cargo/pytest/go test), must pass.
2. **Spec compliance gate** (hard) — Claude verifies implementation matches task spec.
3. **Code quality gate** (soft) — auto-detects linter, warnings logged but don't block.

If a gate fails, the next iteration gets the verbatim error output plus structured context. **Stuck detection:** if the same error hash appears 3+ times, a "strategy shift" directive is injected, explicitly telling the implementer to try a fundamentally different approach. If still stuck → abort, create failure branch (`wip/ralph-fail-{task-id}-{timestamp}`).

Configurable timeouts per gate: implementation (20 min), test (10 min), spec review (5 min), quality check (3 min), global (60 min).

### Cross-Provider Consensus Review

After ralph-loop succeeds on a task, the work is reviewed by the multi-agent council:

- **Stage 1 (60s timeout per agent):** Claude, Gemini, and Codex independently analyze the changes in parallel via direct API calls.
- **Stage 2 (60s timeout):** Chairman agent (Claude → Gemini → Codex fallback) synthesizes findings.
- **Output:** Three-tier report — High Priority (multiple reviewers agree), Medium Priority (single reviewer, significant issue), Consider (suggestions).
- **Graceful degradation:** works with as few as 1 of 3 providers available.

This is the only tool in the survey where self-correction involves perspectives from different model providers, not just the same model re-evaluating its own work.

### Two-Stage Subagent Review (Inherited)

Before consensus, each task goes through:
1. **Spec compliance review** — does implementation match the plan?
2. **Code quality review** — does code meet quality standards?

### Verification Before Completion

A dedicated skill enforces evidence-based completion claims. The "Iron Law": no completion claims without fresh verification evidence. Includes rationalization prevention ("should work now" → RUN the verification) and an enhanced gate function that adds multi-agent consensus review for significant work.

### Systematic Debugging

When bugs are encountered, a 4-phase root cause analysis activates. Root cause hypotheses are validated by the consensus council before fixes are implemented.

---

## 6. Gene List

### Genes Present

| Gene | Strength | Notes |
|------|----------|-------|
| **multi-agent-consensus** | Strong | Core differentiator. Two-stage consensus (parallel independent analysis → chairman synthesis) at 7 workflow checkpoints. Groups findings by agreement level. |
| **cross-provider-consensus** | Strong | The only tool in the survey with structural cross-provider consensus. Claude × Gemini × Codex provide genuinely diverse perspectives (different training data → different blind spots). |
| **ralph-loop** | Strong | First-class implementation with fresh context per iteration, stuck detection, failure branching, tiered gates, configurable timeouts. Named feature, not an afterthought. |
| **fresh-context** | Strong | Multi-level: fresh `claude -p` per ralph-loop iteration, fresh worktree per parallel task, fresh subagent per dispatched task. Strongest fresh-context implementation alongside Gas Town. |
| **plan-before-code** | Strong (mandatory) | Three-phase pipeline (brainstorm → plan → execute) enforced by THE RULE. Consensus gates at each transition. Cannot be bypassed without violating skill enforcement. |
| **test-first** | Strong (mandatory) | RED-GREEN-REFACTOR enforced. Code written before tests is deleted. Ralph-loop test gate is hard (must pass). |
| **self-review** | Strong | Verification-before-completion skill with "Iron Law" (no claims without evidence). Enhanced gate adds consensus review for significant work. |
| **multi-agent-review** | Strong | Three layers: (1) two-stage subagent review (spec + quality), (2) cross-provider consensus review, (3) final consensus before merge. |
| **iterative-refinement** | Strong | Ralph-loop iterates up to 5 times per task with fresh context. Stuck detection forces strategy shifts. TDD cycle is inherently iterative. |
| **tool-use** | Strong (inherited) | Full platform tool set. Plus `conclave consensus`, `conclave ralph-run`, `conclave auto-review` CLI tools. Token-counting proxy (`conclave proxy`). |
| **auto-pilot-brainstorm** | Strong | Consensus Autopilot mode: council debates design decisions autonomously, user watches and can interrupt/override. No other tool has fully autonomous multi-provider brainstorming. |
| **repo-mapping** | Absent | No pre-built repo map or index. Relies on host platform's on-demand search tools. |
| **prose-linting** | Moderate | `conclave lint` validates SKILL.md files (frontmatter schema, description rules, naming, word count, cross-reference resolution, duplicate detection) and plan filenames (`YYYY-MM-DD-<topic>-{design,implementation}.md`). Scoped to skill authoring artifacts, not general documentation. |

### Genes Absent

| Gene | Notes |
|------|-------|
| **repo-mapping** | No codebase index. Delegates to host platform. |

### New Genes Discovered

| Gene | Description |
|------|-------------|
| **cross-provider-council** | Three providers (Claude/Gemini/Codex) independently analyze the same artifact, then a chairman synthesizes findings into a tiered consensus report. This is structurally different from discriminator-selection (which picks a winner) or multi-agent-consensus (which typically uses same-provider instances). The diversity comes from genuinely different training data and architectures, not just temperature variation. |
| **consensus-autopilot** | Fully autonomous design exploration where the multi-provider council answers brainstorming questions without human input. The human watches the debate and can interrupt/override but doesn't need to participate. No other tool combines autonomous brainstorming with cross-provider consensus. |
| **tiered-gate-validation** | Ralph-loop applies three sequential gates (test → spec → quality) with different enforcement levels (hard/hard/soft). This is more structured than a simple pass/fail test loop — it separates correctness (tests), completeness (spec compliance), and polish (code quality) into distinct concerns. |
| **stuck-detection-with-strategy-shift** | When the same error hash appears 3+ times across ralph-loop iterations, the system injects a "strategy shift" directive forcing a fundamentally different approach. This prevents the common failure mode where an LLM repeatedly attempts the same broken fix. |
| **failure-branching** | When a task exceeds its iteration cap or gets stuck, work is committed to a `wip/ralph-fail-*` branch rather than discarded. This preserves partial progress for human review and enables the plan to continue with remaining tasks. |
| **token-counting-proxy** | A transparent HTTP reverse proxy (`conclave proxy`) between the agent and the API that counts input/output tokens from every request. Uses SSE scanning for streaming responses. Enables precise cost measurement without modifying the agent or the API client. |
| **checkpoint-recovery** | Brainstorming sessions save progress to checkpoint files, enabling resume after interruption. Plans persist on disk. Ralph-loop state persists in JSON. This means every workflow phase can survive crashes, context compaction, or deliberate session rotation. |
| **parallel-wave-execution** | Tasks are grouped into dependency-respecting waves (topological sort), executed in parallel within each wave (separate worktrees), then squash-merged in plan order before the next wave begins. Conflicts trigger re-runs from merged state. This is a more structured parallel execution model than Gas Town's convoy system. |

---

## 7. Benchmark-Relevant Traits

### Traits That Affect Task Design

1. **Cross-provider consensus requires API keys for all three providers.** Benchmarks must configure `ANTHROPIC_API_KEY`, `GEMINI_API_KEY`, and `OPENAI_API_KEY`. The system degrades gracefully (works with 1 of 3), but the consensus value comes from provider diversity. Testing with fewer providers should be measured as a separate configuration.

2. **Mandatory planning overhead is significant.** Brainstorming + plan-writing + consensus gates consume substantial tokens before any implementation begins. Simple tasks (greenfield/simple, bugfix/simple) pay this overhead disproportionately. Complex tasks should benefit from it. The benchmark must separate planning cost from implementation cost.

3. **Ralph loop is the primary execution engine.** Each task runs through `conclave ralph-run` with up to 5 iterations. This means even straightforward tasks may consume 2-3x the tokens of a single-shot approach (iteration overhead + gate validation). But error recovery is dramatically better.

4. **Parallel execution needs multi-worktree support.** The parallel runner creates git worktrees. The benchmark Docker container must support git worktree operations and have enough disk space for multiple concurrent checkouts.

5. **Platform agnostic (mostly).** Conclave runs on Claude Code, Codex, and OpenCode. Benchmarks could test the same skill framework across different host platforms, isolating the host platform's contribution from the skill framework's contribution.

### Traits That Affect Measurement

1. **Token accounting spans multiple providers.** A single task's token cost includes: host platform tokens (Claude Code/Codex/OpenCode), consensus Stage 1 tokens (Claude + Gemini + Codex API calls), consensus Stage 2 tokens (chairman synthesis), ralph-loop iteration tokens, and review tokens. The `conclave proxy` tool can capture host-platform tokens precisely; consensus tokens must be aggregated from API response headers.

2. **Turn count is multi-dimensional.** Turns include: controller turns (plan parsing, dispatch), ralph-loop implementation turns (per iteration), gate validation turns, consensus Stage 1 calls (3 providers × N checkpoints), consensus Stage 2 calls (N checkpoints), and review turns. Report by category.

3. **Consensus latency adds wall-clock time.** Each consensus checkpoint takes ~60-120 seconds (Stage 1 parallel + Stage 2 serial). With 7 consensus-enhanced skills and multiple task reviews, wall-clock time is significantly longer than token-equivalent single-agent approaches. Benchmarks must measure both wall-clock time and total token cost.

4. **Ralph-loop iteration count is a quality signal.** Tasks that succeed on iteration 1 vs. iteration 3 vs. failure at cap reveal the difficulty profile. Stuck detection triggers reveal when the LLM is fundamentally unable to solve a problem (vs. needing refinement).

5. **Consensus agreement level predicts issue severity.** High-priority issues (all reviewers agree) vs. medium (single reviewer) provides a measurable signal of review quality. Cross-run analysis of consensus reports reveals whether multi-provider review catches issues that single-provider review misses — this directly tests H1.

6. **Planning artifacts enable quality measurement independent of implementation.** Brainstorm design docs, implementation plans, and consensus reports are all saved to disk. These can be evaluated for architecture quality, plan completeness, and review thoroughness as separate metrics from code quality.

### Scripting for Headless Benchmark Use

Conclave operates as a plugin on Claude Code (or as scripts on Codex/OpenCode):

```bash
# Claude Code with Conclave plugin loaded
claude -p "Read TASK.md and implement the described feature" \
  --output-format stream-json \
  --allowedTools Edit,Write,Bash,Read,Grep,Glob,Skill,Task \
  --dangerously-skip-permissions

# Direct consensus invocation (outside agent loop)
./skills/multi-agent-consensus/consensus-synthesis.sh \
  --mode=code-review \
  --base-sha="$BASE" --head-sha="$HEAD" \
  --plan-file="$PLAN" --description="$DESC"

# Direct ralph-loop invocation
conclave ralph-run "task-id" ./specs/task.md -n 5 --non-interactive

# Token counting via proxy
conclave proxy --port 8199 &
ANTHROPIC_BASE_URL=http://localhost:8199 claude -p "..."
# Ctrl+C proxy for token summary
```

**Benchmark harness integration notes:**
- Plugin must be installed (`/plugin install conclave@honest-gabes-marketplace`) before headless runs.
- Skills auto-activate via session-start hook — no manual skill invocation needed.
- For reproducibility, fix consensus timeouts via `CONSENSUS_STAGE1_TIMEOUT` and `CONSENSUS_STAGE2_TIMEOUT`.
- Ralph-loop timeouts configurable via `RALPH_TIMEOUT_*` env vars.
- The parallel runner's worktree creation requires a git repo as starting state.
- All consensus reports, ralph-loop state, and plan files persist to disk for post-run analysis.

---

## Summary

Conclave is the Superpowers fork that fills the survey's most conspicuous gap: **cross-provider consensus**. While every other tool in the survey either uses a single LLM provider or uses multiple providers for sequential/role purposes, Conclave is the only tool that structurally combines independent perspectives from Claude, Gemini, and Codex to catch errors.

Key architectural characteristics:

1. **Cross-provider consensus at every checkpoint.** Seven skills are enhanced with multi-provider review: brainstorming (design validation), plan-writing (architecture validation), execution (per-task review), debugging (root cause validation), and verification (final check). The two-stage synthesis (parallel independent analysis → chairman synthesis with tiered priority grouping) is the most structured consensus mechanism in the survey.

2. **Ralph loop provides the strongest iterative self-correction.** Fresh context per iteration (no stale conversation), tiered gate validation (test → spec → quality), stuck detection with strategy shifts, and failure branching. Combined with cross-provider review after success, this creates a six-layer self-correction stack: (1) TDD red-green, (2) ralph-loop test gate, (3) ralph-loop spec gate, (4) ralph-loop quality gate, (5) two-stage subagent review, (6) cross-provider consensus review.

3. **The primary test subject for H1 and H4.** Conclave is purpose-built to test whether cross-provider consensus outperforms single-provider approaches (H1) and whether consensus overhead pays for itself in reduced rework (H4). The consensus reports provide granular data on what each provider caught that others missed.

4. **Platform-agnostic skill framework.** Running on Claude Code, Codex, and OpenCode means the same workflow skills can be tested across host platforms, isolating the contribution of the skill framework itself from the underlying agent's capabilities.

The primary cost is token overhead: mandatory planning + ralph-loop iterations + consensus at 7 checkpoints means Conclave will likely be the most expensive tool per task. The hypothesis is that this cost is more than offset by reduced rework, fewer design reversals, and higher first-time correctness rates — and the benchmark is designed to test exactly that.
