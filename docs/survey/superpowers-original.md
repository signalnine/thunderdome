# Superpowers (Original) — Orchestrator Survey

**Tool:** Superpowers ([github.com/obra/superpowers](https://github.com/obra/superpowers))
**Archetype:** Skill-injected agentic framework (plugin layer on top of Claude Code)
**Vendor/Author:** Jesse Vincent (obra)
**Source:** Open-source, MIT license
**Version surveyed:** Latest as of February 2026 (~49.8k GitHub stars, 270 commits, 16 contributors)
**Research date:** 2026-02-11
**Method:** GitHub README, blog posts (blog.fsck.com), third-party write-ups, DeepWiki analysis, skills.sh documentation

---

## 1. Architecture Type

**Skill-injection framework layered on a single-agent loop, with subagent dispatch for execution.**

Superpowers is not a standalone orchestrator. It is a Claude Code plugin that restructures the underlying Claude Code agentic loop by injecting mandatory workflow skills into the system prompt. The core agent loop remains Claude Code's single-threaded tool-call loop, but Superpowers constrains and directs it through a library of composable skills (SKILL.md files) that enforce structured development practices.

The bootstrap mechanism works as follows:

1. A session-start hook (`hooks/session-start.sh`) fires when Claude Code starts.
2. The hook injects the meta-skill `using-superpowers` into the agent's context.
3. This meta-skill establishes "THE RULE": if there is even a 1% probability a skill applies to the current task, the agent must invoke it before proceeding.
4. Skills are discoverable at runtime via a `find-skills` command that searches by description.

The system uses a dual-repository design: plugin code lives in `obra/superpowers`, while skills content is automatically cloned to `~/.config/superpowers/skills/` from `obra/superpowers-skills` on first use and kept up to date via fast-forward merges on subsequent sessions.

Skills resolve through a three-tier priority hierarchy:
1. **Project skills** — `.claude/skills/` in the working directory
2. **Personal skills** — `~/.config/superpowers/skills/` (user-customized, shadow defaults)
3. **Superpowers skills** — built into the plugin at `skills/`

The architecture does not introduce a new agent loop. It modifies Claude Code's existing loop behavior through prompt injection, making it a "behavioral overlay" rather than a replacement orchestrator. This means Superpowers inherits all of Claude Code's core capabilities (tool use, subagent spawning, context compaction) while adding mandatory workflow enforcement on top.

Language distribution of the codebase: Shell (76.1%), JavaScript (12.4%), Python (5.7%), TypeScript (4.3%).

## 2. Context Strategy

**Skill-based progressive disclosure with subagent context isolation and optional memory system.**

Superpowers manages context through several mechanisms:

**Skill progressive disclosure:** Skill descriptions are loaded at session start (lightweight metadata), but full skill content is loaded only when invoked. This prevents context bloat from the ~40+ available skills.

**Subagent context isolation:** When using subagent-driven development, the controller agent curates exactly what information each subagent receives. Subagents never directly access plan files — the controller extracts and provides full task text directly, ensuring each subagent gets a "fresh context per task (no confusion)" without carryover from previous tasks.

**Plan files as external memory:** Instead of holding entire implementation plans in the conversation context, Superpowers persists plans as markdown files on disk. Work is split into 2-5 minute chunks, and progress is written to markdown files. This means plans survive across sessions and context compaction events without consuming active context window space.

**Memory system (partially implemented as of October 2025):** A memory system duplicates Claude transcripts outside the `.claude` directory (bypassing Anthropic's one-month deletion policy), indexes them in SQLite with vector embeddings, and generates summaries using Claude Haiku. A command-line search tool allows subagents to query relevant past conversations. As of the survey date, the author described this as not fully wired up yet.

**Failed skill searches logged:** When `find-skills` fails to locate a relevant skill, the query is logged to `search-log.jsonl`, creating a feedback loop for identifying skill gaps.

Superpowers does not build a repo map, vector index, or embedding database for codebase understanding. It relies on Claude Code's native on-demand search tools (Grep, Glob, Read) for code discovery, supplemented by the git worktree isolation that creates clean working environments.

## 3. Planning Approach

**Mandatory multi-phase planning pipeline: brainstorm, write plan, execute plan.**

Superpowers enforces structured planning through three primary commands that form a pipeline:

**Phase 1 — Brainstorming (`/superpowers:brainstorm`):** Activates before any code is written. Uses Socratic questioning to refine rough ideas: asks specific questions about requirements and edge cases, explores alternatives, and presents the resulting design in digestible sections for human validation. Saves the approved design document to disk for reference.

**Phase 2 — Plan Writing (`/superpowers:write-plan`):** Activates after design approval. Decomposes the approved design into bite-sized implementation tasks (2-5 minutes each), each with:
- Explicit file paths (not vague outlines)
- Complete code solutions
- Verification commands for each phase
- Success criteria and rollback procedures

Plans include multi-phase breakdowns with specific file identification. The author describes output detailed enough that "an enthusiastic junior engineer" could follow it.

**Phase 3 — Plan Execution (`/superpowers:execute-plan`):** Runs the plan in batches with human checkpoints between batches. Two execution models are available:
- **Sequential (subagent-driven):** Fresh subagent dispatched per task with two-stage review before proceeding
- **Parallel session:** Execution launches in a separate Claude session; original session remains available for discussion

**Anti-skip enforcement:** The system blocks common rationalizations for skipping planning ("just a simple question," "need more context first," "I know this concept"). THE RULE requires skill invocation whenever applicable, making planning non-optional for qualifying tasks.

## 4. Edit Mechanism

**Inherits Claude Code's search-and-replace editing. No custom edit tooling.**

Superpowers does not introduce its own edit mechanism. All file modifications use Claude Code's native tools:

- **Edit** — exact string match replacement (primary)
- **MultiEdit** — multiple find-and-replace operations applied atomically
- **Write** — whole-file overwrite (for new files or complete rewrites)

The key behavioral difference from vanilla Claude Code is that Superpowers enforces TDD discipline around edits: the RED-GREEN-REFACTOR cycle means edits follow a strict pattern of (1) write a failing test, (2) write minimal code to pass, (3) refactor while keeping tests green. If the agent writes implementation code before tests, the TDD skill instructs it to delete that code and start over with tests first.

## 5. Self-Correction

**Multi-layered: TDD verification, two-stage code review, systematic debugging skill, and verification-before-completion.**

Superpowers implements several self-correction mechanisms:

**TDD as continuous verification:** The RED-GREEN-REFACTOR cycle serves as the primary self-correction loop. Tests are written first, implementation is validated against them, and refactoring preserves test passage. This catches implementation errors immediately.

**Two-stage subagent review:** After each subagent completes a task:
1. **Spec compliance review** — does the implementation match the plan requirements?
2. **Code quality review** — does the code meet quality standards?

Both reviews require re-review if issues are found. The implementer fixes identified issues, and reviewers re-check until approval. Critical red flags: never skip reviews, never proceed with unfixed issues, never start code quality review before spec compliance passes.

**Self-review before formal review:** The implementer subagent performs a self-review and git commit before formal review stages begin.

**Systematic debugging skill:** When bugs are encountered, a 4-phase root cause analysis activates: reproduce consistently, instrument code, analyze root causes, validate with tests, then implement solutions. This prevents "random fixes" — the shotgun debugging pattern that wastes context.

**Verification-before-completion:** A dedicated skill requires the agent to confirm fixes with evidence before declaring task success. Prevents premature completion claims.

**Anti-rationalization enforcement:** The meta-skill system explicitly blocks cognitive shortcuts that would bypass quality gates (e.g., "I already know the answer" bypassing skill discovery).

## 6. Gene List

### Genes Present

| Gene | Strength | Notes |
|------|----------|-------|
| **plan-before-code** | Strong (mandatory) | Three-phase pipeline (brainstorm, plan, execute) enforced by skill system. Cannot be bypassed without violating THE RULE. |
| **test-first** | Strong (mandatory) | RED-GREEN-REFACTOR enforced. Code written before tests is deleted. Strongest TDD enforcement of any surveyed tool. |
| **self-review** | Strong | Implementer self-reviews before formal review. Verification-before-completion skill adds a final check. |
| **multi-agent-review** | Strong | Two-stage review (spec compliance then code quality) by separate reviewer subagents after each task. |
| **tool-use** | Strong (inherited) | Inherits Claude Code's full tool set: file ops, search, shell, web fetch. |
| **iterative-refinement** | Strong | Subagent loop iterates until both reviewers approve. TDD cycle is inherently iterative. Explicit iterative-refinement skill treats improvement as multi-pass. |
| **fresh-context** | Strong | Each dispatched subagent gets a fresh context window. Controller curates task context; no carryover between tasks. |
| **auto-pilot-brainstorm** | Moderate | Brainstorming skill automates the design exploration process, but still requires human validation at design approval gates. The "go" command can launch autonomous subagent-driven execution for hours. |
| **repo-mapping** | Weak/Absent | No pre-built repo map or index. Relies on Claude Code's on-demand Grep/Glob/Read tools. Git worktree isolation creates clean working environments but does not map existing code structure. |
| **ralph-loop** | Moderate | Subagent-driven development dispatches fresh subagents per task in sequence, creating an execution loop pattern. Not explicitly called a "Ralph loop" but structurally similar: iterate tasks with fresh context per iteration. |
| **prose-linting** | Absent | No built-in documentation quality rules or style enforcement. Could be added as a custom skill. |

### Genes Absent

| Gene | Notes |
|------|-------|
| **multi-agent-consensus** | No consensus mechanism. Subagents execute tasks individually; reviewers check quality but do not debate or vote on implementation approaches. Design decisions are not subjected to multi-model deliberation. |
| **cross-provider-consensus** | Entirely absent. Superpowers operates exclusively within the Claude ecosystem. All subagents are Claude instances. This is the primary divergence point for Conclave (the Superpowers fork), which adds Codex and Gemini routing. |
| **prose-linting** | No documentation quality enforcement. Skills focus on code quality, not prose. |

### New Genes Discovered

| Gene | Description |
|------|-------------|
| **mandatory-skill-enforcement** | THE RULE: skills are not optional. If a skill might apply (even 1% probability), it must be invoked. Backed by anti-rationalization patterns that block common excuses for skipping. This is qualitatively different from "optional best practices" — it is a behavioral constraint injected into the system prompt. |
| **anti-rationalization** | Explicit blocking of cognitive shortcuts the LLM might use to bypass workflow. Skills include lists of prohibited rationalizations (e.g., "just a simple question," "I know this concept") with rebuttals. Tested against subagents using Cialdini persuasion scenarios (time pressure, sunk cost). |
| **skill-composability** | Skills can be authored, tested, and added by both humans and Claude itself. A meta-skill teaches Claude how to create new skills. Skills are tested via TDD against subagent scenarios before deployment, creating a self-improving system. |
| **git-worktree-isolation** | Automatic creation of git worktrees for development branches. Provides filesystem-level isolation for parallel work, clean test baselines, and structured merge/PR/discard workflows at completion. |
| **plan-persistence** | Implementation plans stored as markdown files on disk rather than in conversation context. Survives context compaction, enables cross-session continuity, and allows parallel session execution where a separate Claude session loads and executes the plan. |
| **pressure-tested-skills** | Skills are validated by running subagents through adversarial scenarios designed using Cialdini's persuasion principles (authority, time pressure, sunk cost, social proof). A skill passes only if the agent follows it under pressure. |
| **two-stage-review** | Sequential spec-compliance then code-quality review, each by a separate reviewer agent. More structured than generic "code review" — the ordering prevents quality review from masking spec violations. |

## 7. Benchmark-Relevant Traits

### Traits That Affect Task Design

- **Mandatory planning overhead:** Superpowers will spend significant tokens on brainstorming and plan-writing before any implementation begins. Benchmark tasks should account for this front-loaded cost. Simple tasks (greenfield/simple, bugfix/simple) may be disproportionately penalized by planning overhead compared to tools that jump straight to implementation.

- **TDD enforcement changes edit patterns:** Tasks with existing test suites may see different behavior than tasks requiring new tests. The mandatory test-first approach means Superpowers will generate failing tests before any implementation code, which changes the diff shape and turn count profile.

- **Subagent dispatch is non-deterministic in timing:** The controller decides when and how to dispatch subagents. For reproducibility, multiple trials are necessary to average out dispatch strategy variance.

- **Planning quality is measurable:** The brainstorm and plan-writing phases produce artifacts (design documents, plan files) that can be evaluated independently of implementation quality. This enables measuring "architecture quality" as a distinct dimension.

- **Git worktree isolation affects starting state:** Superpowers creates worktrees automatically, which means the benchmark harness must either (a) provide a git repository as starting state, or (b) account for the worktree setup overhead and potential failure if no git repo exists.

### Traits That Affect Measurement

- **Token cost is distributed across subagents:** Each dispatched subagent is a separate Claude instance with its own context. Total token cost includes the controller, all implementer subagents, and all reviewer subagents. Measurement must aggregate across all sessions.

- **Turn count is multi-dimensional:** A "turn" in Superpowers is ambiguous — is it a tool call in the controller? A complete subagent run? A review cycle? The benchmark should define turn granularity consistently across tools. Recommended: count total tool invocations across all agents (controller + subagents).

- **Review overhead is measurable and isolatable:** The two-stage review after each task is a distinct cost that can be measured. This enables testing H4 (consensus overhead pays for itself in reduced rework) by comparing rework rates with and without review stages.

- **Skill discovery tokens:** The agent spends tokens discovering and loading skills at session start and when encountering new task types. This is a fixed overhead that amortizes over longer sessions but is proportionally significant for short tasks.

- **Plan files enable progress tracking:** Since plans are persisted as markdown with task status, the benchmark harness can read plan files to track progress without parsing conversation logs.

### Scripting for Headless Benchmark Use

Superpowers operates as a Claude Code plugin, so headless execution uses Claude Code's programmatic interfaces:

```bash
# CLI invocation with Superpowers plugin loaded
claude -p "task description" \
  --output-format stream-json \
  --allowedTools Edit,Write,Bash,Read,Grep,Glob \
  --dangerously-skip-permissions
```

Key considerations for benchmark harness integration:

- **Plugin must be installed before headless runs.** Install via Claude Code plugin marketplace: `/plugin install superpowers@superpowers-marketplace`. Verify with `/plugins` command.
- **Skills auto-clone on first session.** The first run will clone `obra/superpowers-skills` to `~/.config/superpowers/skills/`. Subsequent runs do fast-forward updates. Pre-clone for reproducibility.
- **Personal skills override defaults.** For benchmark consistency, clear or standardize `~/.config/superpowers/skills/` across runs to prevent per-user skill variations.
- **Subagent dispatch is implicit.** Superpowers decides when to dispatch subagents based on task complexity. There is no flag to force or prevent subagent use, which introduces variance.
- **Plan files provide machine-readable progress.** Parse plan markdown files post-run for task completion tracking.
- **`sp next` CLI command** advances the workflow from the terminal, useful for scripting multi-phase interactions.
- **Superpowers Lab** includes experimental automation skills that create detached tmux sessions and send keystrokes programmatically, which could be leveraged for more advanced benchmark automation.

---

## Summary

Superpowers (Original) is a skill-injection framework that transforms Claude Code from a general-purpose coding agent into a disciplined software development process. Its core innovation is mandatory workflow enforcement: planning before code, tests before implementation, review before merge. It achieves this through prompt-injected skills backed by anti-rationalization patterns that prevent the LLM from taking shortcuts.

The original Superpowers operates exclusively within the Claude ecosystem — all subagents are Claude instances, with no cross-provider model routing. This is the primary divergence point for Conclave (the Superpowers fork), which adds multi-model collaboration checkpoints routing tasks to Codex (backend) and Gemini (frontend) via MCP tools, with optional cross-validation.

For benchmarking, Superpowers presents a distinctive profile: high front-loaded cost (mandatory brainstorming and planning), structured execution (subagent dispatch with fresh context per task), and built-in quality gates (two-stage review). This makes it likely to excel on complex tasks where planning and architecture quality matter, but potentially disadvantaged on simple tasks where the planning overhead exceeds the implementation effort. The mandatory TDD enforcement means code quality metrics should be strong, but token efficiency will be lower than tools that skip planning and review phases.

Key genes unique or unusually strong in Superpowers: mandatory-skill-enforcement, anti-rationalization, pressure-tested-skills, two-stage-review, plan-persistence, and git-worktree-isolation. Key genes absent: multi-agent-consensus, cross-provider-consensus, and prose-linting.

---

## Sources

- [obra/superpowers — GitHub](https://github.com/obra/superpowers)
- [Superpowers: How I'm using coding agents in October 2025 — Jesse Vincent](https://blog.fsck.com/2025/10/09/superpowers/)
- [Superpowers for OpenCode — Jesse Vincent](https://blog.fsck.com/2025/11/24/Superpowers-for-OpenCode/)
- [Superpowers explained: the popular Claude plugin that enforces TDD, subagents, and planning — Dev Genius](https://blog.devgenius.io/superpowers-explained-the-claude-plugin-that-enforces-tdd-subagents-and-planning-c7fe698c3b82)
- [Superpowers to turn Claude Code into a real senior developer — betazeta.dev](https://betazeta.dev/blog/claude-code-superpowers/)
- [How I force Claude Code to plan before coding with Superpowers — Trevor Lasn](https://www.trevorlasn.com/blog/superpowers-claude-code-skills)
- [obra/superpowers — DeepWiki](https://deepwiki.com/obra/superpowers)
- [Subagent-driven development skill — skills.sh](https://skills.sh/obra/superpowers/subagent-driven-development)
- [BryanHoo/superpowers-ccg — GitHub (fork with cross-provider routing)](https://github.com/BryanHoo/superpowers-ccg)
- [Superpowers — Anthropic Claude Plugins](https://claude.com/plugins/superpowers)
- [obra/superpowers-lab — GitHub (experimental skills)](https://github.com/obra/superpowers-lab)
