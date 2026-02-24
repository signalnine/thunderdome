# Agentic Thunderdome

Two agents enter, one agent leaves.

A benchmarking framework that pits agentic coding orchestrators against standardized programming tasks and measures what matters: completion rate, token efficiency, cost, and code quality.

## Results

Composite scores across all 10 tasks (tests + build/lint for standard tasks; hidden_tests + agent_tests + coverage + code_metrics + lint for greenfield). Data includes 467 trials across 39 orchestrator variants. Scoring is purely deterministic — no LLM judges.

### Leaderboard

Mean composite score across all tasks run, ranked by score. Orchestrators with fewer trials or tasks may be less reliable.

| Rank | Orchestrator | Mean | Tasks | Trials | Avg Cost | Model |
|---:|---|---:|---:|---:|---:|---|
| 1 | Metacog | **95.0%** | 10 | 11 | $0.04 | Opus 4.6 |
| 2 | Conclave Review | **94.9%** | 10 | 11 | $1.82 | Opus 4.6 |
| 3 | Gas Station | **93.6%** | 10 | 22 | $0.71 | Opus 4.6 |
| 4 | Conclave Design | **93.1%** | 4 | 9 | $2.09 | Opus 4.6 |
| 5 | Conclave Double Review + Keys | **93.3%** | 4 | 9 | $1.89 | Opus 4.6 |
| 6 | Agent Teams | **91.8%** | 10 | 28 | $0.49 | Opus 4.6 |
| 7 | Claude Code Headless | **92.1%** | 4 | 9 | $1.15 | Opus 4.6 |
| 8 | Ralph Fresh | **91.0%** | 2 | 4 | $1.57 | Opus 4.6 |
| 9 | Claude Code | **89.6%** | 10 | 24 | $0.27 | Opus 4.6 |
| 10 | Gemini CLI | **81.3%** | 10 | 19 | $0.00 | Gemini 3 Flash |
| 11 | Amp Flash | **81.8%** | 10 | 12 | $0.00 | Gemini 3 Flash |
| 12 | Gas Town | **81.3%** | 10 | 41 | $0.01 | Opus 4.6 |
| 13 | Amplifier | **66.8%** | 10 | 42 | $0.01 | Opus 4.6 |
| 14 | Conclave | **76.0%** | 10 | 32 | $0.05 | Multi-provider |

**Data quality note:** Some orchestrators (Amplifier, Gas Town, Conclave) have many trials from early experimental runs when adapters were still being debugged. Their means are dragged down by adapter failures, not model capability. Gas Station, Metacog, and Conclave Review have cleaner data (fewer experimental trials). The ablation studies below use controlled comparisons and are more reliable than the overall means.

### Key Findings

- **Metacog** leads on score (95.0%) using Claude Code with a metacognitive perspective-shifting skill — but only 11 trials, mostly n=1 per task
- **Conclave Review** is the value play — 94.9% mean at $1.82/task. Adding three-provider code review after implementation adds ~5 points vs vanilla Claude Code
- **Gas Station** is the most reliable — 93.6% mean across 22 trials with the lowest variance of any top contender. Single-agent + context injection in a git worktree
- **Self-review discipline is free and effective** — telling the agent "commit, review your diff, fix issues" adds ~7 points at zero cost. This is the largest gene effect found (see Double Review ablation)
- **Process skills hurt or have no effect** — TDD, systematic debugging, and mandatory planning ceremonies all fail to improve scores. The model already follows good practices by default
- **T4** (bugfix) is the great equalizer — most contenders score 100%, the task is too easy
- **T8** (analytics dashboard) is the hardest task — most contenders cluster around 70-90%

### The Gas Station Story

Gas Town is a multi-agent pipeline: a Mayor decomposes the task, parallel Polecats implement pieces in git worktrees, and a Refinery merges their work and fixes conflicts. We asked Claude Code to build the adapter.

What it delivered was a fraud — a single `claude -p` call with `gt prime` context injected, wearing Gas Town's scaffolding like a trench coat. It set up the town, created beads, initialized a polecat worktree, the whole ceremony — then ran one agent that did all the work by itself. A single agent pretending to be a workforce.

I named the impostor "Gas Station" and kept it as a control while we built the real multi-agent pipeline ourselves.

Then the benchmarks came back. Gas Station scored 93.6% (n=22 trials). The single agent in a trench coat is the most consistent performer in the entire benchmark suite — 90% mean on the marathon task (T5) across 6 trials with low variance (87.7%-92.2%). Gas Station is still in the benchmark suite as a permanent reminder that complexity needs to justify itself.

### Ablation Studies

We're isolating individual orchestrator "genes" — composable features like multi-agent consensus, skill injection, parallel execution — to measure which actually help. Each ablation holds everything constant except one gene.

#### TypeScript Expertise: Amplifier + ts-dev Bundle

**Hypothesis:** Giving the agent TypeScript-specific tools (LSP code intelligence, code quality analysis, a specialized TS expert agent) improves performance on TypeScript benchmarks.

**Setup:** Amplifier with Opus 4.6, comparing bare foundation bundle vs foundation + [ts-dev](https://github.com/microsoft/amplifier-bundle-ts-dev) app bundle. Same model, same provider, same tasks.

| Task | Amplifier (bare) | Amplifier + ts-dev | Delta |
| --- | ---: | ---: | ---: |
| **T1** time-tracker | 70.3% (n=13) | 83.3% (n=2) | +13.0 |
| **T2** collab-server | 39.6% (n=3) | 78.5% (n=2) | +38.9 |
| **T3** fts-search | 89.4% (n=3) | 98.6% (n=2) | +9.2 |
| **T4** phantom-invoice | 90.0% (n=3) | 85.0% (n=2) | -5.0 |
| **T5** task-queue | 44.4% (n=3) | 52.9% (n=2) | +8.5 |
| **T6** monorepo-disaster | 80.0% (n=3) | 85.0% (n=2) | +5.0 |
| **T7** plugin-marketplace | 42.6% (n=5) | 95.0% (n=1) | +52.4 |
| **T8** analytics-dashboard | 78.4% (n=3) | 67.6% (n=2) | -10.8 |
| **T9** ssg-toolkit | 73.1% (n=3) | 99.4% (n=1) | +26.3 |
| **T10** ecommerce-backend | 64.5% (n=3) | 68.2% (n=1) | +3.7 |
| **Mean** | **67.2%** | **81.4%** | **+14.1** |

**Caveat: This comparison is unreliable.** The bare Amplifier mean is dragged down by many early experimental trials when the adapter was being debugged (n=3-13 per task). The ts-dev variant has cleaner data (n=1-2). The apparent +14 point advantage of ts-dev is largely an artifact of baseline pollution, not a real effect of the TypeScript bundle. The original controlled comparison (single trials for both) showed ts-dev as a net negative (-4.6 points). This ablation needs re-running with matched trial counts to draw any conclusion.

#### Consensus Code Review: Conclave Review vs Claude Code vs Full Conclave

**Hypothesis:** Multi-agent consensus code review (Claude + Gemini + Codex reviewing the diff) catches defects that a single agent misses, improving final code quality.

**Setup:** Three variants, all using Opus 4.6:
- **Claude Code** — vanilla single agent, no review
- **Conclave Review** — vanilla agent + one round of `conclave consensus --mode=code-review` after implementation, then fix findings. No skills, no planning ceremonies.
- **Conclave (full)** — mandatory skill pipeline: brainstorm → plan → implement → verify → finish, with consensus woven throughout

| Task | Claude Code | Conclave Review | Full Conclave | Review delta |
| --- | ---: | ---: | ---: | ---: |
| **T1** time-tracker | 83.9% (n=6) | 94.8% (n=2) | 70.4% (n=5) | +10.9 |
| **T2** collab-server | 64.9% (n=2) | 92.9% (n=1) | 65.5% (n=4) | +28.0 |
| **T3** fts-search | 99.3% (n=2) | 96.4% (n=1) | 99.1% (n=3) | -2.9 |
| **T4** phantom-invoice | 100.0% (n=2) | 100.0% (n=1) | 100.0% (n=5) | 0.0 |
| **T5** task-queue | 75.7% (n=4) | 90.3% (n=1) | 49.2% (n=3) | +14.6 |
| **T6** monorepo-disaster | 100.0% (n=1) | 100.0% (n=1) | 98.6% (n=4) | 0.0 |
| **T7** plugin-marketplace | 94.9% (n=1) | 95.0% (n=1) | 64.5% (n=2) | +0.1 |
| **T8** analytics-dashboard | 87.9% (n=1) | 90.1% (n=1) | 56.1% (n=2) | +2.2 |
| **T9** ssg-toolkit | 99.4% (n=1) | 99.1% (n=1) | 99.4% (n=2) | -0.3 |
| **T10** ecommerce-backend | 89.8% (n=1) | 90.0% (n=1) | 57.0% (n=2) | +0.2 |
| **Mean** | **89.6%** | **94.9%** | **76.0%** | **+5.3** |

**Findings:**

1. **Consensus review is a net positive (+5.3 points).** The three-provider code review catches real issues. Biggest gains on collab-server (T2: +28.0) and marathon (T5: +14.6).

2. **Stripping Conclave to just the review beats the full pipeline by 19 points** (94.9% vs 76.0%). The mandatory brainstorm → plan → implement workflow burns context and constrains the agent's natural problem-solving. The review gene is valuable; the methodology gene is not.

3. **Cost tradeoff is reasonable** — $1.82/task average vs Claude Code's ~$0.27. The consensus review adds cost but delivers a consistent 5-point improvement across the full suite.

**Caveat:** Conclave Review has n=1-2 per task. Claude Code baseline includes some failed trials (e.g., T2 has one 37% trial dragging down the mean). Full Conclave's low mean partly reflects early experimental trials with adapter issues.

#### Systematic Debugging: Superpowers Debug Skill vs Claude Code

**Hypothesis:** A structured four-phase debugging methodology (root cause investigation → pattern analysis → hypothesis testing → implementation) improves defect resolution on hard debugging tasks.

**Setup:** We built T11 (Debug Nightmare), a new hard debugging benchmark with 6 cascading bugs in an event-driven order processing system. The bugs feature multi-level indirection (symptom in Module A, root cause in Module C), cascading failures (fixing Bug 1 unmasks Bug 3), and red herrings.

Variants tested, all using Opus 4.6 on T11:
- **Claude Code** — vanilla single agent, no methodology (n=3)
- **Superpowers Debug** — systematic-debugging skill, various configurations (n=6)

| Variant | Mean | Trials | Mean Cost |
| --- | ---: | ---: | ---: |
| **Claude Code** | **99.3%** | 3 | $0.84 |
| **Superpowers Debug** | **99.1%** | 6 | $1.06 |

**Findings:**

1. **Systematic debugging has no measurable effect.** Both variants cluster at ~99% — both fix all 6 bugs in every trial. The debugging skill adds process overhead without changing outcomes.

2. **When opt-in, the agent never invokes it.** Across opt-in trials, the Skill tool appeared in tools_used zero times. The agent prefers to debug directly rather than consult a methodology.

3. **The model already debugs systematically.** It reads errors, traces data flow, and fixes root causes without needing a skill to tell it to.

**Contrast with consensus code review (+5.3 points):** Review adds a *concrete action* — three independent models examining the diff — that catches bugs the solo agent missed. Systematic debugging adds *process* — phases, checklists, red-flag lists — that the agent already follows instinctively. Concrete actions beat process guidance.

#### Test-Driven Development: Forced TDD vs Claude Code on Greenfield Tasks

**Hypothesis:** Writing failing tests before implementation code produces higher-quality greenfield projects — better test coverage, fewer defects, more robust architecture.

**Setup:** Claude Code Opus with the TDD skill forcibly invoked. System prompt mandates strict red-green-refactor: write one failing test, implement minimally to pass, refactor, repeat. Compared against vanilla Claude Code on 4 greenfield tasks.

| Task | Claude Code | TDD (forced) | Delta |
| --- | ---: | ---: | ---: |
| **T2** collab-server | 64.9% (n=2) | 93.0% (n=1) | +28.1 |
| **T5** task-queue | 75.7% (n=4) | 88.7% (n=1) | +13.0 |
| **T7** plugin-marketplace | 94.9% (n=1) | 94.4% (n=1) | -0.5 |
| **T8** analytics-dashboard | 87.9% (n=1) | 94.9% (n=1) | +7.0 |
| **Mean** | **80.9%** | **92.8%** | **+11.9** |

**Caveat: This comparison is unreliable.** The Claude Code baseline has mixed trial counts (n=1-4) including some failed trials, while TDD has clean n=1 data. The apparent +11.9 advantage is partly an artifact of baseline pollution. The truth likely lies somewhere in between — TDD neither dramatically helps nor hurts, but the data is too noisy to draw conclusions.

**What is clear:** TDD achieved 1.000 on hidden tests for all 4 tasks — the agent's own tests were thorough enough that the hidden validation suite passed automatically. This is the one unambiguous win for TDD methodology. But the cost is high (~$2.98/task vs ~$1.00 for vanilla) and the score impact is uncertain.

**The emerging pattern:** Rigid process skills (TDD, systematic debugging) have uncertain or no effect — the model already follows good practices by default. What works is review: self-review discipline (~+7 points, free) and real multi-model consensus (~+2 points on top). See "Decomposing Self-Review vs Consensus" below.

#### Consensus Design Review: Pre-Implementation Architecture Guidance

**Hypothesis:** If consensus *code review* after implementation helps (+5.3 points), then consensus *design review* before implementation should help even more — preventing bad architecture choices rather than catching them after the fact.

**Setup:** Before the agent writes any code, the adapter runs `conclave consensus --mode=general-prompt` on the task description. Claude, Gemini, and Codex independently analyze the task and recommend file structure, abstractions, data flow, edge cases, implementation order, and testing strategy. A chairman synthesizes their recommendations. The agent then receives the consensus architecture guidance prepended to its task prompt. No mandatory workflow — the agent codes freely with richer context.

Compared against vanilla Claude Code (Opus 4.6, same model) on 4 greenfield tasks.

| Task | Claude Code | Design Review | Delta |
| --- | ---: | ---: | ---: |
| **T1** time-tracker | 83.9% (n=6) | 97.0% (n=4) | +13.1 |
| **T5** task-queue | 75.7% (n=4) | 92.7% (n=3) | +17.0 |
| **T7** plugin-marketplace | 94.9% (n=1) | 94.5% (n=1) | -0.4 |
| **T8** analytics-dashboard | 87.9% (n=1) | 88.1% (n=1) | +0.2 |
| **Mean** | **85.6%** | **93.1%** | **+7.5** |

**Findings:**

1. **Design review is a net positive (+7.5 points mean).** The effect is strongest on tasks with higher variance. T5 marathon gains +17 points — architectural guidance helps the most on complex, multi-phase tasks.

2. **Minimal effect on tasks the model already handles well.** T7 and T8 show noise-level deltas (-0.4, +0.2). When the task is clear enough that a single model can architect it correctly, three models agreeing doesn't add much.

3. **Overhead is modest.** The consensus step adds ~80-100 seconds of wall time and ~$0.10-0.30 in hidden API costs (3 models + chairman).

4. **Design review vs code review:** Design review (+7.5) and code review (+5.3) both help, through different mechanisms. Design review prevents bad architecture upfront. Code review catches implementation bugs afterward. They're complementary — stacking both is the obvious next experiment.

**Caveat:** The Claude Code baseline includes some failed trials that drag down its mean. The design review effect size is likely overstated — the directional finding (+) is reliable but the exact magnitude needs matched trial counts.

#### Stacked Double Review: Decomposing Self-Review vs Consensus

**Hypothesis:** Stacking design review + code review should be additive. But how much of the improvement comes from self-review *discipline* (pausing to re-examine your work) vs actual multi-model *consensus* (three models finding things one model misses)?

**Setup:** Same adapter run twice — once with `env: {}` (no API keys, consensus fails, agent self-reviews), once with API keys (real consensus from Claude + Gemini + Codex). This cleanly separates the two effects.

| Task | Baseline | Self-Review Only | Real Consensus | Self-Review Δ | Consensus Δ |
| --- | ---: | ---: | ---: | ---: | ---: |
| **T1** time-tracker | 83.9% (n=6) | 95.2% (n=3) | 95.0% (n=3) | +11.3 | -0.2 |
| **T5** task-queue | 75.7% (n=4) | 91.1% (n=2) | 92.1% (n=2) | +15.4 | +1.0 |
| **T7** plugin-marketplace | 94.9% (n=1) | 94.8% (n=2) | 94.9% (n=2) | -0.1 | +0.1 |
| **T8** analytics-dashboard | 87.9% (n=1) | 89.8% (n=2) | 91.1% (n=2) | +1.9 | +1.3 |
| **Mean delta vs baseline** | — | **+7.1** | **+7.7** | — | **+0.5** |

**Findings:**

1. **Self-review discipline is the dominant gene (~+7 points, free).** Tell the agent "commit, review your diff, fix issues" and it scores significantly higher. No API keys, no external tools, no extra cost beyond a few additional turns. This is the single most impactful intervention found in the entire study.

2. **Multi-model consensus adds little on top (+0.5).** Once the agent is already self-reviewing, adding three models to review as well provides marginal improvement. The effect is concentrated on complex tasks (T5: +1.0, T8: +1.3) and absent on others.

3. **The combined effect (~+7.7 points) is the largest improvement found.** Self-review accounts for ~92% of it.

**Implications:**

1. **Self-review is the low-hanging fruit.** Adding "commit and self-review your diff before finishing" to any adapter's system prompt yields ~+7 points at zero marginal cost. Every contender should do this.

2. **Consensus adds minimal value on top of self-review.** The +0.5 above self-review is within noise for most tasks. The cost ($0.20-0.40/task) may not be justified for the incremental gain.

**Caveat:** The Claude Code baseline includes some failed trials dragging down its mean, which inflates the delta. The directional finding (self-review helps, consensus adds little extra) is reliable, but the exact magnitude needs matched trials. 2-3 trials per variant per task.

#### Agent Teams: Parallel Teammates on Marathon Tasks

**Hypothesis:** Claude Code's experimental agent teams feature — spawning parallel teammate subagents to work on subtasks — improves performance on complex and marathon tasks.

**Setup:** Claude Code Opus 4.6 in interactive mode (tmux harness with idle detection), `--agent-teams` enabled. Token costs estimated from session JSONL files using Opus per-token rates. Compared against Claude Code in headless `-p` mode.

| Task | Headless | Agent Teams | Delta |
| --- | ---: | ---: | ---: |
| **T1** time-tracker | 94.9% (n=3) | 96.6% (n=9) | +1.7 |
| **T5** task-queue | 87.3% (n=2) | 56.4% (n=8) | -30.9 |
| **T7** plugin-marketplace | 95.1% (n=2) | 94.6% (n=3) | -0.5 |
| **T8** analytics-dashboard | 89.6% (n=2) | 89.3% (n=2) | -0.3 |

**Findings:**

1. **Agent Teams hurts on the marathon task.** T5 dropped from 87.3% (headless) to 56.4% (agent teams, n=8). The high trial count reveals significant variance — some trials succeed (~92%) while others catastrophically fail. The task's 12 sequential phases can't truly parallelize, and teammates stepping on each other causes failures.

2. **No effect on simpler tasks.** T1, T7, and T8 show noise-level deltas. The agent often decides not to spawn teammates on tasks that don't benefit from parallelization.

3. **Supports H5.** The Task Queue Marathon is inherently sequential. Spawning parallel workers on a sequential workload adds coordination overhead without enabling real parallelism. This aligns with hypothesis H5: naive parallelization on non-decomposable tasks eliminates the advantage.

**Caveat:** Agent Teams scores estimated from session JSONL token counts. The T5 mean (56.4%) may be dragged down by configuration issues in some trials ($0.00 cost suggests some ran without proper billing/tracking).

#### Branch Ablation: Real Git Branch vs Detached HEAD

**Hypothesis:** Gas Station's `git checkout -b main` (creating a real branch from detached HEAD) explains part of its T5 advantage.

**Setup:** Vanilla Claude Code Opus 4.6 with one addition: `git checkout -b main` before running the agent. Everything else identical to vanilla.

| Variant | Trial 1 | Trial 2 | Mean |
| --- | ---: | ---: | ---: |
| **Vanilla Claude Code** | — | — | 75.7% (n=4) |
| **Claude Code + Branch** | 90.6% | 73.8% | 82.2% (n=2) |

**Finding:** Creating a real branch shows mixed results (+6.5 points mean, but high variance: 90.6% vs 73.8%). The branch effect is ambiguous — one trial matches Gas Station, the other is mediocre. Not enough data to conclude.

#### Worktree Ablation: Git Worktree vs Vanilla

**Hypothesis:** Gas Station's advantage comes from working in a git worktree created from a bare clone, not from any Gas Town tooling.

**Setup:** Vanilla Claude Code Opus 4.6 with bare clone + worktree plumbing only. No Gas Town tooling (no beads, no `gt prime`, no env vars), no system prompt changes, no `--disallowed-tools`. Just:
1. `git checkout -b main` (prerequisite for bare clone)
2. `git clone --bare /workspace /tmp/workspace-bare.git`
3. `git worktree add -b work /tmp/worktree/bench main`
4. Run Claude in the worktree
5. Copy files back to /workspace

| Variant | Trial 1 | Trial 2 | Mean |
| --- | ---: | ---: | ---: |
| **Vanilla Claude Code** | — | — | 75.7% (n=4) |
| **Gas Station** (6 trials) | — | — | 90.0% |
| **Claude Code + Worktree** | 89.5% | 91.9% | **90.7%** (n=2) |

**Finding: The worktree matches Gas Station.** The worktree ablation (90.7%) matches Gas Station (90.0%) within noise, confirming that Gas Town's ceremony — beads database, `gt prime` context, polecat env vars — contributes nothing. The advantage comes from the workspace setup.

**Why the worktree helps:** In a git worktree, `.git` is a single file (pointer to the bare repo) rather than a directory containing `HEAD`, `config`, `description`, `index`, `packed-refs`, etc. The agent's Explore subagent doesn't encounter these files when building its project summary, resulting in a cleaner mental model. See the No-Git Ablation below for more on this mechanism.

**Caveat:** Only 2 trials. Both are strong (89.5%, 91.9%), consistent with Gas Station's range (87.7%-92.2%), but more data is needed.

#### The Gas Station Mystery: Investigated — Workspace Setup Matters

**The investigation:** Gas Station scored 90.0% on T5 (marathon, n=6) vs vanilla Claude Code's 75.7% (n=4) — a ~14 point gap. We systematically isolated variables through ablations.

**Gas Station T5 confirmation (6 trials):**

| Gas Station T5 | Trial 1 | Trial 2 | Trial 3 | Trial 4 | Trial 5 | Trial 6 | Mean |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| **Score** | 87.7% | 90.6% | 90.4% | 92.2% | 90.8% | 88.6% | **90.0%** |

Gas Station is remarkably consistent — 87.7% to 92.2% across 6 trials. Vanilla Claude Code varies wildly: 31.0% to 93.4% across 4 trials.

**Headless ablation:**

| Task | Vanilla Claude Code | Headless | Gas Station |
| --- | ---: | ---: | ---: |
| **T1** time-tracker | 83.9% (n=6) | 94.9% (n=3) | 94.5% (n=4) |
| **T5** task-queue | 75.7% (n=4) | 87.3% (n=2) | 90.0% (n=6) |
| **T7** plugin-marketplace | 94.9% (n=1) | 95.1% (n=2) | 94.6% (n=3) |
| **T8** analytics-dashboard | 87.9% (n=1) | 89.6% (n=2) | 78.0% (n=3) |

Headless mode actually helps on T5 (87.3% vs 75.7%). The `--disallowed-tools` flag prevents the agent from wasting turns on AskUserQuestion and EnterPlanMode, which may help on long-running tasks.

**Decomposition summary:**

| Factor | T5 Result | Verdict |
| --- | ---: | --- |
| `git checkout -b main` alone | 82.2% (n=2) | Inconclusive (high variance) |
| `--disallowed-tools` + headless prompt | 87.3% (n=2) | Helps (~+12 points) |
| **Bare clone + git worktree** | **90.7% (n=2)** | **Matches Gas Station** |
| **Remove .git entirely** | **66.7% (n=4)** | **Unstable — 50% failure rate** |

**Revised finding:** The worktree matches Gas Station (90.7% vs 90.0%), but the mechanism is more nuanced than originally reported. The original hypothesis that "removing `.git` reproduces the same improvement" does NOT hold — the no-git ablation has a 50% catastrophic failure rate (see below). The worktree's advantage may come from replacing the `.git` directory with a clean file pointer, but with only 2 trials the evidence is thin.

#### No-Git Ablation: Unstable — Not the Silver Bullet Originally Reported

**Hypothesis:** The worktree advantage comes from eliminating `.git` directory noise in the agent's file exploration.

**Setup:** Vanilla Claude Code Opus 4.6 with workspace files copied (via `tar`) to a clean directory with NO `.git` directory at all.

| Variant | Trial 1 | Trial 2 | Trial 3 | Trial 4 | Mean |
| --- | ---: | ---: | ---: | ---: | ---: |
| **Claude Code + No Git** | 92.9% | 48.0% | 91.0% | 34.9% | **66.7%** |

**The original analysis (now corrected) reported 90.5% from 2 trials (the two that succeeded).** Two additional trials catastrophically failed (hidden_tests=0.0, coverage=0.0), revealing that removing `.git` introduces a severe instability. When it works, it's excellent (91-93%). When it fails, the agent produces nothing useful (35-48%).

**The `.git` noise mechanism is still real** — confirmed via transcript analysis showing the Explore subagent includes `.git/` internals (~2,100 tokens of noise). But removing `.git` entirely may break assumptions in the agent's toolchain (git operations fail, subagents may behave differently without a repo context).

**Why the worktree works but no-git doesn't:** A git worktree preserves full git functionality (commits, diffs, status) while replacing the `.git` directory with a single file. No-git removes git entirely, which the agent sometimes can't handle.

**Implication:** Use git worktrees, not no-git directories, for benchmarking. The worktree provides the clean workspace benefits without breaking the agent's git workflow. But with only 2 worktree trials, this needs more data.

**Caveat:** n=2-4 per variant. The 50% failure rate for no-git could be coincidence with 4 trials — it needs 10+ trials to establish a reliable failure rate.

#### Fresh-Context Ralph Loops (H3)

**Hypothesis (H3):** Fresh-context Ralph loops outperform stale-context loops on marathon tasks.

**Setup:** Ralph loop adapter runs Claude Code Opus 4.6 in a loop. Each iteration gets fresh context (new `claude -p` invocation) but works in the same persistent workspace. After iteration 1, subsequent iterations receive the original task prompt plus current `npm test` output showing which tests fail. Minimum 2 iterations, maximum 4. The agent's conversation history resets between iterations, but all code changes survive.

Compared against vanilla Claude Code (stale context — one long session where context accumulates) on T5 marathon.

| Variant | Trial 1 | Trial 2 | Trial 3 | Mean | Mean Cost |
| --- | ---: | ---: | ---: | ---: | ---: |
| **Vanilla Claude Code** | — | — | — | 75.7% (n=4) | $0.69 |
| **Ralph Fresh** | 90.5% | 93.2% | 90.0% | **91.3%** | $1.90 |

Greenfield breakdown (Ralph Fresh):

| Trial | Hidden Tests | Coverage | Cost |
| --- | ---: | ---: | ---: |
| **Trial 1** | 1.000 | 0.890 | $1.28 |
| **Trial 2** | 1.000 | 0.941 | $1.68 |
| **Trial 3** | 1.000 | 0.915 | $2.73 |

**Findings:**

1. **Fresh context is now the top-performing T5 intervention at 91.3%.** All 3 trials cluster tightly (90.0%-93.2%), making this the most consistent high-scoring variant alongside Gas Station and the worktree ablation.

2. **Perfect hidden test scores.** All 3 trials achieved 1.000 on hidden tests — all 108 validation tests passing. The fresh-context second iteration re-reads the codebase without accumulated context pollution and effectively identifies and fixes remaining issues.

3. **H3 is supported.** Fresh context (+15.6 points over baseline, $1.90) provides a large, consistent improvement on the marathon task. The mechanism: resetting the conversation clears accumulated noise and lets the agent re-approach remaining problems with a clean mental model.

4. **Comparable to worktree but through a different mechanism.** Ralph Fresh (91.3%) and worktree (90.7%) achieve similar scores. Worktree prevents `.git` noise from entering context. Ralph Fresh resets accumulated noise between iterations. Both work; Ralph Fresh costs more ($1.90 vs $1.61) but is more robust (3/3 successes vs 2/2).

**Caveat:** 3 trials for Ralph Fresh, 4 for vanilla (including 1 failed trial at 31%).

#### Planned Ablations

| Ablation | A | B | Gene Isolated | Status |
|---|---|---|---|---|
| Parallelism | Gas Town | Gas Station | Mayor + parallel polecats + refinery | Data exists (needs more trials) |
| Gas Station scaffolding | Gas Station | Claude Code + Headless | Git worktree + branch setup (gt prime discarded) | **Done — worktree matches Gas Station** |
| Git worktree isolation | Claude Code + Worktree | Claude Code | Bare clone + worktree (no Gas Town tooling) | **Done — 90.7% T5 (n=2), matches Gas Station** |
| Consensus review only | Conclave Review | Claude Code | Multi-agent code review (no skills) | **Done — +5.3 points** |
| Full skill pipeline | Full Conclave | Conclave Review | Brainstorm/plan/implement workflow | **Done — -18.9 points** |
| Systematic debugging | Superpowers Debug | Claude Code | Four-phase debugging methodology | **Done — no effect (both ~99%)** |
| Test-driven development | Superpowers TDD | Claude Code | Forced red-green-refactor cycle | **Done — inconclusive (baseline noisy)** |
| Consensus design review | Conclave Design | Claude Code | Pre-implementation multi-model architecture guidance | **Done — +7.5 points** |
| Self-review discipline | Double Review (no keys) | Claude Code | "Commit, review your diff, fix" in system prompt | **Done — ~+7 points (free, largest gene)** |
| Self-review + consensus | Double Review (keys) | Claude Code | Self-review + real multi-model consensus | **Done — ~+7.7 points (consensus adds little over self-review)** |
| Mandatory skills | Conclave | Claude Code | Conclave plugin (TDD, debugging, planning) | Data exists (needs more trials) |
| Skill optionality | Conclave | Superpowers | Mandatory vs optional skill invocation | Data exists (needs more trials) |
| Metacognitive reframing | Metacog | Claude Code | Pre-implementation thinking skill | Data exists (needs more trials) |
| Agent teams | Agent Teams | Claude Code | In-process teammate coordination | **Done — hurts on T5 (-30.9), noise elsewhere** |
| Branch from detached HEAD | Claude Code + Branch | Claude Code | `git checkout -b main` before agent | **Done — inconclusive (82.2%, high variance)** |
| Fresh-context Ralph loop | Ralph Fresh | Claude Code | Multi-iteration fresh context on same workspace | **Done — +15.6 on T5, now top-tier (91.3%)** |
| No-git workspace | Claude Code + No Git | Claude Code | Remove .git directory entirely | **Done — unstable (50% failure rate, n=4)** |
| Structured recipes | Amplifier + recipes | Amplifier | Multi-step orchestration behaviors | Not started |
| Agent delegation | Amplifier + delegate | Amplifier | Sub-session spawning | Not started |

## Why This Exists

Every AI coding tool claims superiority. None publish reproducible head-to-head comparisons. Thunderdome fills that gap by running orchestrators against identical tasks in isolated Docker containers, scoring their output with automated tests and static analysis.

The framework tests five hypotheses:

- **H1:** Cross-provider consensus (Codex Max x Opus x Gemini 3 Pro) catches more defects than same-model consensus
- **H2:** Multi-agent consensus reduces mid-implementation design reversals
- **H3:** Fresh-context Ralph loops outperform stale-context loops on marathon tasks
- **H4:** Consensus overhead pays for itself in reduced rework
- **H5:** Dependency-aware parallel execution achieves sub-linear wall-clock time on decomposable tasks; naive parallelization produces merge conflicts that eliminate the advantage

## Contenders

| Orchestrator | Architecture | Key Differentiator |
|---|---|---|
| **Agent Teams** | Claude Code interactive + teams | Experimental agent teams feature; tmux harness for idle detection |
| **Amplifier** | Micro-kernel platform | Swappable providers; minimal overhead; Sonnet 4.5 |
| **Amplifier + ts-dev** | Amplifier + TypeScript bundle | LSP code intelligence, TS expert agent (ablation study) |
| **Conclave Review** | Claude Code + consensus review | Code review only — no skills, no planning (ablation study) |
| **Conclave Design** | Claude Code + consensus design | Pre-implementation architecture review (ablation study) |
| **Gas Town** | Multi-agent pipeline | Mayor (planner) -> parallel Polecats (workers) -> Refinery (merge) |
| **Gas Station** | Single-agent + context injection | Gas Town's prompt engineering without multi-agent overhead |
| **Gemini CLI** | Google's agentic CLI | Gemini 3 models; free via Google One OAuth; headless `-p` mode |
| **Amp Flash** | Amplifier + Gemini Flash | Amplifier orchestration with Gemini 3 Flash via API |
| **Claude Code** | CLI agentic (single agent) | Rich tool use, subagent delegation, flexible autonomy |
| **Metacog** | Claude Code + metacognitive skill | Perspective-shifting plugin; methodology guidance |
| **Superpowers** (Original) | Skill-injection platform | Mandatory planning + TDD + two-stage review |
| **Conclave** (Superpowers fork) | Cross-provider consensus | Claude x Gemini x Codex consensus; 6-layer self-correction |
| **Aider** | CLI turn-based | One-shot Sonnet; PageRank repo map; token-efficient |

See [`docs/survey/orchestrator-survey.md`](docs/survey/orchestrator-survey.md) for the full gene matrix and per-tool analysis.

## Benchmark Suite

Eleven tasks span six categories and the full parallelism spectrum:

| # | Task | Category | Parallelism | Timeout | Tests |
|---|------|----------|-------------|---------|-------|
| 1 | CLI Time Tracker | greenfield/simple | None | 15m | 25 |
| 2 | Collab Server | greenfield/complex | Mixed | 45m | 45 |
| 3 | FTS Search | features/medium | Sequential | 30m | 35 |
| 4 | Phantom Invoice Bug | bugfix/medium | Sequential | 20m | 41 |
| 5 | Task Queue Marathon | marathon | Sequential | 60m | 90 |
| 6 | Monorepo Disaster | recovery | Mixed | 30m | 49 |
| 7 | Plugin Marketplace | greenfield/complex | Pure parallel | 45m | 55 |
| 8 | Analytics Dashboard | greenfield/complex | Deceptive parallel | 45m | 50 |
| 9 | SSG Toolkit | features/complex | DAG parallel | 45m | 75 |
| 10 | E-Commerce Backend | greenfield/complex | Pure parallel (max) | 45m | 70 |
| 11 | Debug Nightmare | bugfix/hard | Sequential | 30m | 49 |

```
None        Sequential     Mixed          Deceptive      DAG-Parallel     Pure Parallel
|              |              |               |               |                |
T1           T3,T5         T2,T6           T8              T9             T7,T10
```

All 584 tests across 11 repos use TypeScript/Node.js with Vitest. Orchestrators cannot cheat by modifying tests. Validation runs `npm run build && npm run lint && npm test`.

Each task includes at least one trap that punishes naive or template-driven approaches. See [`docs/plans/2026-02-11-survey-and-tasks-design.md`](docs/plans/2026-02-11-survey-and-tasks-design.md) for full task specifications.

## How It Works

```
thunderdome run
  |
  ├─ Clone task repo at pinned tag
  ├─ Launch orchestrator in Docker container
  │    ├─ Mount adapter script, task description, workspace
  │    ├─ Orchestrator reads TASK.md, writes code to /workspace
  │    └─ Container exits on completion, timeout, or crash
  ├─ Capture git diff of workspace changes
  ├─ Run validation pipeline
  │    ├─ Tests (npm test in validation image)
  │    ├─ Build + lint (npm run build && npm run lint)
  │    └─ Greenfield extras: hidden tests, coverage, code metrics
  └─ Write results (meta.json, diff.patch, scores)
```

Each orchestrator plugs in through a shell adapter script mounted at `/adapter.sh`. The adapter translates between Thunderdome's interface (environment variables `TASK_DIR`, `TASK_DESCRIPTION`, `PROXY_URL`) and the orchestrator's native invocation. Adapters also parse their orchestrator's output to write `.thunderdome-metrics.json` with token usage and cost data.

## Usage

### Prerequisites

- Go 1.24+
- Docker

### Build

```sh
go build -o thunderdome .
```

### Run

```sh
# Run all orchestrators against all tasks
./thunderdome run

# Filter to one orchestrator or task
./thunderdome run --orchestrator conclave-oauth-opus
./thunderdome run --task T5

# Run with parallel containers
./thunderdome run --parallel 4 --trials 3

```

### Results

Each trial produces:

```
results/runs/<run-id>/trials/<orchestrator>/<task>/trial-1/
├── meta.json      # Duration, exit reason, scores, token usage, cost
├── diff.patch     # Git diff of all workspace changes
├── task.md        # Task prompt given to the orchestrator
└── workspace/     # Full workspace after orchestrator ran
    └── .thunderdome-metrics.json  # Token/cost metrics from adapter
```

The composite score blends test pass rate and static analysis. Greenfield tasks additionally include hidden tests, code coverage, and code metrics.

## Writing an Adapter

An adapter script bridges Thunderdome and an orchestrator. It receives these environment variables:

| Variable | Value |
|---|---|
| `TASK_DIR` | `/workspace` -- the task repo, mounted read-write |
| `TASK_DESCRIPTION` | `/task.md` -- the task prompt |
| `PROXY_URL` | API gateway URL (if gateway is enabled) |

The script must:

1. Read the task description
2. Invoke the orchestrator, pointing it at the workspace
3. Write `/workspace/.thunderdome-metrics.json` with token/cost data
4. Exit 0 on success, non-zero on error

Example (Aider adapter with cost tracking):

```sh
#!/bin/bash
set -e
cd "$TASK_DIR"

aider --yes-always --no-auto-commits \
  --message-file "$TASK_DESCRIPTION" \
  --model anthropic/claude-sonnet-4-5 \
  | tee /workspace/.aider-stdout.log

# Parse cost from stdout and write metrics
python3 -c "
import re, json
last_cost = 0.0
with open('/workspace/.aider-stdout.log') as f:
    for line in f:
        m = re.search(r'Cost:.*\\\$([\\d.]+) session', line)
        if m: last_cost = float(m.group(1))
json.dump({'total_cost_usd': last_cost},
          open('/workspace/.thunderdome-metrics.json','w'))
"
```

## Scoring

| Axis | Method | Weight |
|---|---|---|
| **Tests** | Fraction of pre-written tests that pass | Task-specific |
| **Static analysis** | Build + lint pass/fail (binary) | Task-specific |
| **Hidden tests** | Tests on `v1-validation` tag, not visible to orchestrator | Greenfield only |
| **Coverage** | Statement coverage of agent-written tests | Greenfield only |
| **Code metrics** | Lines of code, complexity, duplication | Greenfield only |

The composite score is a weighted sum. Each task defines its own weights, so bugfix tasks weight tests higher; greenfield tasks include the full six-axis scoring.

## Project Structure

```
.
├── main.go                     # Entry point
├── cmd/                        # CLI commands (run, list, report)
├── internal/
│   ├── config/                 # YAML config parsing and validation
│   ├── docker/                 # Container lifecycle management
│   ├── gateway/                # API proxy (proxy.py), usage tracking
│   ├── gitops/                 # Clone, checkout, diff capture
│   ├── report/                 # Table, Markdown, JSON report generation
│   ├── result/                 # Trial metadata types and storage
│   ├── runner/                 # Trial execution, validation pipeline, pool
│   └── validation/             # Tests, lint, hidden tests, coverage, code metrics
├── adapters/                   # Shell adapter scripts per orchestrator
├── benchmarks/                 # 11 standalone task repos (each with v1/v1-solution tags)
├── docker/                     # Dockerfiles for orchestrator images
├── docs/
│   ├── survey/                 # Orchestrator architecture survey
│   └── plans/                  # Design documents
├── thunderdome.yaml            # Default configuration
└── project.md                  # Full project specification
```

## Status

- [x] Orchestrator survey (10 tools documented)
- [x] Benchmark task design (11 tasks specified)
- [x] Build benchmark task repos (11 repos, 584 tests, v1/v1-solution tags)
- [x] Harness implementation (run, list, report, validate commands)
- [x] Write orchestrator adapters (10 orchestrators, 20+ adapter variants)
- [x] Run baseline comparisons (single-trial full suite for 10 orchestrators)
- [ ] Multi-trial runs for statistical significance
- [ ] Ablation studies (gene isolation) — 13 done: ts-dev (inconclusive), consensus review (+5.3), systematic debugging (no effect), TDD (inconclusive), design review (+7.5), self-review (~+7, free), self-review+consensus (~+7.7), worktree matches Gas Station, agent teams (hurts on T5), branch (inconclusive), worktree (+15 on T5), Ralph fresh-context (+15.6 on T5, top-tier), no-git (unstable)
- [ ] Publish methodology paper

## License

TBD
