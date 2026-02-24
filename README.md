# Agentic Thunderdome

Two agents enter, one agent leaves.

A benchmarking framework that pits agentic coding orchestrators against standardized programming tasks and measures what matters: completion rate, token efficiency, cost, and code quality.

## Results

Full suite results across all 10 tasks (single trial each). Scores are composite (tests + build/lint + rubric + greenfield extras where applicable).

### Score Matrix

| Task | Agent Teams | Amplifier | Gas Town | Gas Station | Gemini CLI | Claude Code | Metacog | Amp Flash | Superpowers | Conclave | Aider* |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| **T1** time-tracker | 95.4% | 96.2% | 92.9% | 93.2% | 94.0% | 92.7% | 87.0% | 69.3% | 94.0% | 79.1% | 93.6% |
| **T2** collab-server | 88.4% | 96.2% | 87.9% | 87.2% | 85.2% | 86.9% | 85.0% | 79.7% | 84.2% | 82.2% | 92.9% |
| **T3** fts-search | 94.7% | 93.2% | 93.2% | 93.2% | 96.2% | 90.6% | 92.0% | 94.0% | 93.2% | 92.5% | 93.2% |
| **T4** phantom-invoice | 100.0% | 100.0% | 98.5% | 100.0% | 100.0% | 92.5% | 100.0% | 100.0% | 100.0% | 100.0% | 100.0% |
| **T5** task-queue | 89.3% | 94.0% | 88.4% | 86.8% | 92.7% | 57.8% | 61.0% | 75.1% | 73.0% | 73.8% | 20.0% |
| **T6** monorepo-disaster | 97.7% | 95.5% | 97.0% | 96.2% | 97.0% | 98.5% | 94.0% | 94.0% | 94.0% | 73.0% | — |
| **T7** plugin-marketplace | 94.8% | 95.2% | 94.8% | 92.6% | 92.0% | 91.4% | 91.0% | 85.4% | 70.7% | 70.0% | — |
| **T8** analytics-dashboard | 84.2% | 69.1% | 85.3% | 85.3% | 70.6% | 82.8% | 78.0% | 56.0% | 70.0% | 59.5% | — |
| **T9** ssg-toolkit | 96.2% | 96.2% | 96.2% | 94.0% | 96.2% | 83.5% | 75.0% | 96.6% | 70.7% | 84.2% | — |
| **T10** ecommerce-backend | 91.8% | 94.5% | 93.7% | 93.9% | 91.0% | 90.1% | 91.0% | 63.0% | 70.7% | 82.2% | — |
| **Mean** | **93.3%** | **93.0%** | **92.8%** | **92.3%** | **91.5%** | **86.7%** | **85.4%** | **81.3%** | **82.1%** | **79.7%** | **79.9%** |

### Cost and Speed Summary

All costs are equivalent API token costs (what the tokens would cost at published per-token rates). All contenders run on subscriptions (Claude Max, Google One) with no actual per-token billing.

| Orchestrator | Mean Score | Total Time | Token Cost | Model | Notes |
|---|---:|---:|---:|---|---|
| **Agent Teams** | 93.3% | ~87m | ~$20 est | Opus 4.6 | Interactive mode (tmux harness); cost estimated |
| **Amplifier** | 93.0% | 1h28m | ~$6.73 | Sonnet 4.5 | Best cost/score ratio among Claude contenders |
| **Gas Town** | 92.8% | 1h28m | $31.62 | Opus 4.6 | Multi-agent pipeline (Mayor/Polecats/Refinery) |
| **Gas Station** | 92.3% | 49m | $11.09 | Opus 4.6 | Single-agent + context injection |
| **Gemini CLI** | 91.5% | ~54m | **$0.45** | Gemini 3 Flash | 20x cheaper than cheapest Claude contender |
| **Claude Code** | 86.7% | 42m | $9.79 | Opus 4.6 | Vanilla `-p` mode, no orchestration |
| **Metacog** | 85.4% | ~46m | $10.42 | Opus 4.6 | Metacognitive skill injection |
| **Superpowers** | 82.1% | 27m | $7.60 | Opus 4.6 | Fastest full-suite; drops on complex tasks |
| **Amp Flash** | 81.3% | 1h42m | **~$0.07** | Gemini 3 Flash | Amplifier + Flash; cheapest but slowest |
| **Conclave** | 79.7% | 1h21m | $19.21 | Multi-provider | Cross-provider consensus (Claude/Gemini/Codex) |
| **Aider** | 79.9% | 4m | ~$0.22 | Sonnet 4.5 | One-shot, no iteration; only 5 tasks |

\*Aider uses Sonnet (one-shot, no iteration). `~` = estimated. Agent Teams cost estimated from Opus pricing.

### Key Findings

- **Agent Teams** leads on score (93.3%) using Claude Code's interactive mode with experimental agent teams enabled and a tmux harness for idle detection
- **Amplifier** is the best value — #2 on score (93.0%) at the lowest cost of any Claude-based contender (~$6.73) using Sonnet 4.5
- **Gemini CLI** is the cost story — 91.5% mean score at $0.45 equivalent token cost (20x cheaper than Amplifier). Uses Gemini 3 Flash with aggressive caching
- **Amplifier + Flash** (81.3%) vs **Gemini CLI** (91.5%) — same Flash model, 10 points apart. Amplifier's orchestration overhead hurts more than it helps on a fast, cheap model
- **Gas Station** (single-agent) nearly matches Gas Town quality (92.3% vs 92.8%) in half the time at 3x less cost
- **Claude Code** struggles on marathon tasks (T5: 57.8%) but excels at recovery (T6: 98.5%)
- **T4** (bugfix) is the great equalizer — 6 contenders score 100%, the task is too easy
- **T8** (analytics dashboard) is the hardest task — most contenders cluster around 70-85% (Conclave Review hit 90%)

### The Gas Station Story

Gas Town is a multi-agent pipeline: a Mayor decomposes the task, parallel Polecats implement pieces in git worktrees, and a Refinery merges their work and fixes conflicts. We asked Claude Code to build the adapter.

What it delivered was a fraud — a single `claude -p` call with `gt prime` context injected, wearing Gas Town's scaffolding like a trench coat. It set up the town, created beads, initialized a polecat worktree, the whole ceremony — then ran one agent that did all the work by itself. A single agent pretending to be a workforce.

I named the impostor "Gas Station" and kept it as a control while we built the real multi-agent pipeline ourselves.

Then the benchmarks came back. Gas Station scored 92.3%. The full Gas Town pipeline — Mayor planning, parallel Polecats, Refinery merge, post-merge fixup, 632 lines of orchestration — scored 92.8%. Half a percentage point better for 3x the cost and twice the wall-clock time.

The single agent in a trench coat is within margin of error of the actual workforce — 92.3% vs 92.8% — at a third of the cost ($11 vs $32) and half the wall-clock time. Gas Station is still in the benchmark suite as a permanent reminder that complexity needs to justify itself.

### The Gemini CLI Surprise

We added Gemini CLI almost as an afterthought — Google's answer to Claude Code, running on a $20/month Google One subscription. It scored 91.5%, beating vanilla Claude Code (86.7%) and landing just 1.5 points behind Gas Station. Perfect score on the bugfix task (T4), 97% on monorepo recovery (T6), and 92.7% on the marathon (T5) — a task where Claude Code scored 57.8%.

At equivalent API token rates, the entire 10-task suite costs $0.45 in Gemini 3 Flash tokens — that's 20x cheaper than Amplifier ($6.73 in Sonnet tokens) and 70x cheaper than Gas Town ($31.62 in Opus tokens). Gemini CLI uses aggressive prompt caching (3.3M cached tokens on T5 alone) and a cheap model (Flash, not Pro) to achieve this.

The catch: Google One's rate limits (~60 RPM) mean you can only run one or two tasks concurrently. But for individual developer use, Gemini CLI delivers 91.5% of the best score at a fraction of the token cost.

### Ablation Studies

We're isolating individual orchestrator "genes" — composable features like multi-agent consensus, skill injection, parallel execution — to measure which actually help. Each ablation holds everything constant except one gene.

#### TypeScript Expertise: Amplifier + ts-dev Bundle

**Hypothesis:** Giving the agent TypeScript-specific tools (LSP code intelligence, code quality analysis, a specialized TS expert agent) improves performance on TypeScript benchmarks.

**Setup:** Amplifier with Opus 4.6, comparing bare foundation bundle vs foundation + [ts-dev](https://github.com/microsoft/amplifier-bundle-ts-dev) app bundle. Same model, same provider, same tasks.

| Task | Amplifier (bare) | Amplifier + ts-dev | Delta |
| --- | ---: | ---: | ---: |
| **T1** time-tracker | 96.2% | 93.3% | -2.9 |
| **T2** collab-server | 96.2% | 86.3% | -9.9 |
| **T3** fts-search | 93.2% | 94.0% | +0.8 |
| **T4** phantom-invoice | 100.0% | 100.0% | 0.0 |
| **T5** task-queue | 94.0% | 90.8% | -3.2 |
| **T6** monorepo-disaster | 95.5% | 92.5% | -3.0 |
| **T7** plugin-marketplace | 95.2% | 92.4% | -2.8 |
| **T8** analytics-dashboard | 69.1% | 69.1% | 0.0 |
| **T9** ssg-toolkit | 96.2% | 93.0% | -3.2 |
| **T10** ecommerce-backend | 94.5% | 73.0% | -21.5 |
| **Mean** | **93.0%** | **88.4%** | **-4.6** |

**Finding:** The ts-dev bundle is a net negative (-4.6 points average). The extra system prompt context and tools burn tokens without providing useful signal — the base model already knows TypeScript well enough. T10 was the worst regression (-21.5 points). Only T3 showed a marginal improvement.

**Caveat:** Single-trial data. The bare Amplifier scores above are best-of-N from earlier multi-trial runs, while ts-dev scores are single trials. A fair comparison needs matched trial counts.

#### Consensus Code Review: Conclave Review vs Claude Code vs Full Conclave

**Hypothesis:** Multi-agent consensus code review (Claude + Gemini + Codex reviewing the diff) catches defects that a single agent misses, improving final code quality.

**Setup:** Three variants, all using Opus 4.6:
- **Claude Code** — vanilla single agent, no review
- **Conclave Review** — vanilla agent + one round of `conclave consensus --mode=code-review` after implementation, then fix findings. No skills, no planning ceremonies.
- **Conclave (full)** — mandatory skill pipeline: brainstorm → plan → implement → verify → finish, with consensus woven throughout

| Task | Claude Code | Conclave Review | Full Conclave | Review delta |
| --- | ---: | ---: | ---: | ---: |
| **T1** time-tracker | 92.7% | 91.9% | 79.1% | -0.8 |
| **T2** collab-server | 86.9% | 91.2% | 82.2% | +4.3 |
| **T3** fts-search | 90.6% | 93.2% | 92.5% | +2.6 |
| **T4** phantom-invoice | 92.5% | 100.0% | 100.0% | +7.5 |
| **T5** task-queue | 57.8% | 72.0% | 73.8% | +14.2 |
| **T6** monorepo-disaster | 98.5% | 98.5% | 73.0% | 0.0 |
| **T7** plugin-marketplace | 91.4% | 94.0% | 70.0% | +2.6 |
| **T8** analytics-dashboard | 82.8% | 90.0% | 59.5% | +7.2 |
| **T9** ssg-toolkit | 83.5% | 93.6% | 84.2% | +10.1 |
| **T10** ecommerce-backend | 90.1% | 91.9% | 82.2% | +1.8 |
| **Mean** | **86.7%** | **91.6%** | **79.7%** | **+5.0** |

**Findings:**

1. **Consensus review is a net positive (+5.0 points).** The three-provider code review catches real issues. Biggest gains on marathon (T5: +14.2), complex features (T9: +10.1), and the hardest greenfield task (T8: +7.2).

2. **Stripping Conclave to just the review beats the full pipeline by 12 points** (91.6% vs 79.7%). The mandatory brainstorm → plan → implement workflow burns context and constrains the agent's natural problem-solving. The review gene is valuable; the methodology gene is not.

3. **New best on T8** — Conclave Review scored 90.0% on Analytics Dashboard, the hardest task. Previous best was Agent Teams at 84.2%.

4. **Cost tradeoff is reasonable** — $1.89/task average vs Claude Code's ~$0.98. The consensus review adds ~$0.90 per task for a 5-point improvement.

**Caveat:** Single-trial data for Conclave Review. Claude Code and full Conclave scores are best-of-N from earlier runs.

#### Systematic Debugging: Superpowers Debug Skill vs Claude Code

**Hypothesis:** A structured four-phase debugging methodology (root cause investigation → pattern analysis → hypothesis testing → implementation) improves defect resolution on hard debugging tasks.

**Setup:** We built T11 (Debug Nightmare), a new hard debugging benchmark with 6 cascading bugs in an event-driven order processing system. The bugs feature multi-level indirection (symptom in Module A, root cause in Module C), cascading failures (fixing Bug 1 unmasks Bug 3), and red herrings. T4 and T6 were too easy — both agents scored 0.96+ on every trial.

Three variants tested, all using Opus 4.6 on T11:
- **Claude Code** — vanilla single agent, no methodology
- **Superpowers Debug (opt-in)** — systematic-debugging skill available but invocation left to the agent's discretion
- **Superpowers Debug (forced)** — system prompt mandates invoking the skill before every fix

| Variant | Trial 1 | Trial 2 | Trial 3 | Mean | Mean Cost |
| --- | ---: | ---: | ---: | ---: | ---: |
| **Claude Code** | 70.7% | 73.0% | 70.0% | **71.2%** | $0.84 |
| **Debug skill (opt-in)** | 73.0% | 70.0% | 71.0% | **71.3%** | $0.70 |
| **Debug skill (forced)** | 71.0% | 72.0% | 72.0% | **71.7%** | $1.34 |

**Findings:**

1. **Systematic debugging has no measurable effect.** All three variants cluster at 71-72% across 9 trials. The skill adds 0.1-0.5 points — well within noise.

2. **When opt-in, the agent never invokes it.** Across 6 opt-in trials (T4, T6, T11), the Skill tool appeared in tools_used zero times. The agent prefers to debug directly rather than consult a methodology.

3. **When forced, it burns tokens for nothing.** Forcing skill invocation costs 60% more ($1.34 vs $0.84) and takes 48% longer (297s vs 201s) with no score improvement. The four-phase ceremony adds process overhead without changing outcomes.

4. **The model already debugs systematically.** Both variants fix all 6 bugs in every trial. The difference is only in rubric quality scores. The model reads errors, traces data flow, and fixes root causes without needing a skill to tell it to.

**Contrast with consensus code review (+5.0 points):** Review adds a *concrete action* — three independent models examining the diff — that catches bugs the solo agent missed. Systematic debugging adds *process* — phases, checklists, red-flag lists — that the agent already follows instinctively. Concrete actions beat process guidance.

#### Test-Driven Development: Forced TDD vs Claude Code on Greenfield Tasks

**Hypothesis:** Writing failing tests before implementation code produces higher-quality greenfield projects — better test coverage, fewer defects, more robust architecture.

**Setup:** Claude Code Opus with the TDD skill forcibly invoked. System prompt mandates strict red-green-refactor: write one failing test, implement minimally to pass, refactor, repeat. Compared against vanilla Claude Code on 4 greenfield tasks.

| Task | Claude Code | TDD (forced) | Delta | TDD Cost |
| --- | ---: | ---: | ---: | ---: |
| **T2** collab-server | 86.9% | 72.6% | -14.3 | $1.90 |
| **T5** task-queue | 57.8% | 63.1% | +5.3 | $5.90 |
| **T7** plugin-marketplace | 91.4% | 90.0% | -1.4 | $1.36 |
| **T8** analytics-dashboard | 82.8% | 80.6% | -2.2 | $2.75 |
| **Mean** | **79.7%** | **76.6%** | **-3.2** | **$2.98** |

Greenfield breakdown (TDD):

| Task | Hidden Tests | Agent Tests | Coverage | Code Metrics | Rubric |
| --- | ---: | ---: | ---: | ---: | ---: |
| **T2** collab-server | 1.000 | 1.000 | 0.896 | 1.000 | 0.275 |
| **T5** task-queue | 1.000 | 1.000 | 0.929 | 0.600 | 0.100 |
| **T7** plugin-marketplace | 1.000 | 1.000 | 0.939 | 1.000 | 0.750 |
| **T8** analytics-dashboard | 1.000 | 1.000 | 0.906 | 1.000 | 0.500 |

**Findings:**

1. **TDD is a net negative (-3.2 points average).** The red-green-refactor ceremony burns tokens without improving outcomes. T2 was the worst hit (-14.3 points) — the agent spent so many turns on the TDD cycle that it likely exhausted context before completing the implementation.

2. **TDD helped on the marathon (+5.3 on T5).** The one task where Claude Code struggles most (57.8%) saw a meaningful improvement. Hypothesis: the forced incremental approach prevented the agent from attempting too much at once, which is exactly what kills marathon performance.

3. **Perfect hidden test scores across the board.** TDD achieved 1.000 on hidden tests for all 4 tasks — the agent's own tests were thorough enough that the hidden validation suite passed automatically. This is the one clear win for TDD methodology.

4. **But the cost is brutal.** Average $2.98/task vs ~$1.00 for vanilla. The TDD ceremony roughly triples token consumption. The 128-turn T5 run cost $5.90.

5. **Rubric scores are low.** Despite perfect test coverage, the rubric judge scored TDD implementations lower (0.100-0.750) — likely because the incremental build-up produces less cohesive architecture than writing the full solution directly.

**The emerging pattern:** Rigid process skills (TDD, systematic debugging) hurt or have no effect — the model already follows good practices by default. What works is review: self-review discipline (+4.7 points, free) and real multi-model consensus (+2.2 points on top, ~$0.30/task). Combined, they yield +7.0 points — the largest improvement found. See "Decomposing Self-Review vs Consensus" below.

#### Consensus Design Review: Pre-Implementation Architecture Guidance

**Hypothesis:** If consensus *code review* after implementation helps (+5.0 points), then consensus *design review* before implementation should help even more — preventing bad architecture choices rather than catching them after the fact.

**Setup:** Before the agent writes any code, the adapter runs `conclave consensus --mode=general-prompt` on the task description. Claude, Gemini, and Codex independently analyze the task and recommend file structure, abstractions, data flow, edge cases, implementation order, and testing strategy. A chairman synthesizes their recommendations. The agent then receives the consensus architecture guidance prepended to its task prompt. No mandatory workflow — the agent codes freely with richer context.

Compared against vanilla Claude Code (Opus 4.6, same model) on 4 greenfield tasks.

| Task | Claude Code | Design Review | Delta | Trials |
| --- | ---: | ---: | ---: | ---: |
| **T1** time-tracker | 91.0% (n=2) | 94.4% (n=3) | +3.4 | 5 |
| **T5** task-queue | 70.0% (n=2) | 79.7% (n=3) | +9.7 | 5 |
| **T7** plugin-marketplace | 91.4% (n=1) | 91.0% (n=1) | -0.4 | 2 |
| **T8** analytics-dashboard | 82.8% (n=1) | 83.0% (n=1) | +0.2 | 2 |
| **Weighted mean** | | | **+3.8** | |

**Findings:**

1. **Design review is a net positive (+3.8 points weighted mean).** The effect is consistent across tasks, with the largest gain on T5 marathon (+9.7 points) where architectural guidance helps the most.

2. **Biggest impact on the hardest task.** T5 (marathon, 12 phases) went from 70.0% to 79.7%. The consensus recommendations gave the agent a better mental model of the full system before it started, reducing mid-implementation architectural pivots.

3. **Minimal effect on tasks the model already handles well.** T7 and T8 show noise-level deltas (-0.4, +0.2). When the task is clear enough that a single model can architect it correctly, three models agreeing doesn't add much.

4. **Overhead is modest.** The consensus step adds ~80-100 seconds of wall time and ~$0.10-0.30 in hidden API costs (3 models + chairman). The agent itself costs slightly more due to the larger prompt (~$0.56 vs $0.36 on T1). Total overhead is less than the consensus code review adds.

5. **Design review vs code review:** Design review (+3.8) and code review (+5.0) both help, through different mechanisms. Design review prevents bad architecture upfront. Code review catches implementation bugs afterward. They're complementary — stacking both is the obvious next experiment.

#### Stacked Double Review: Decomposing Self-Review vs Consensus

**Hypothesis:** Stacking design review + code review should be additive. But how much of the improvement comes from self-review *discipline* (pausing to re-examine your work) vs actual multi-model *consensus* (three models finding things one model misses)?

**Setup:** Same adapter run twice — once with `env: {}` (no API keys, consensus fails, agent self-reviews), once with API keys (real consensus from Claude + Gemini + Codex). This cleanly separates the two effects.

| Task | Baseline | Self-Review Only | Real Consensus | Self-Review Δ | Consensus Δ |
| --- | ---: | ---: | ---: | ---: | ---: |
| **T1** time-tracker | 91.0% (n=2) | 92.4% (n=2) | 91.6% (n=2) | +1.4 | -0.8 |
| **T5** task-queue | 70.0% (n=2) | 80.4% (n=2) | 84.1% (n=2) | +10.4 | +3.7 |
| **T7** plugin-marketplace | 91.4% (n=1) | 92.6% (n=2) | 94.9% (n=2) | +1.2 | +2.3 |
| **T8** analytics-dashboard | 82.8% (n=1) | 88.8% (n=2) | 92.4% (n=2) | +6.0 | +3.6 |
| **Mean delta vs baseline** | — | **+4.7** | **+7.0** | — | **+2.2** |

**Decomposition:**

The +7.0 total improvement breaks down into two independent genes:

1. **Self-review discipline: +4.7 points (free).** Tell the agent "commit, review your diff, fix issues" and it scores nearly 5 points higher. No API keys, no external tools, no extra cost beyond a few additional turns. This is the bigger contributor — 68% of the total effect.

2. **Multi-model consensus: +2.2 points ($0.20-0.40/task).** Three models independently reviewing the task and code do find things the solo agent misses. The effect is consistent on complex tasks (T5: +3.7, T7: +2.3, T8: +3.6) but absent on simple ones (T1: -0.8). This is the smaller contributor — 32% of the total effect.

**Correcting the original conclave-review-opus finding:** The +5.0 from "consensus code review" in the full suite was a mix of both genes. That adapter used `env: {}`, so the consensus command failed and the agent self-reviewed. The +5.0 was mostly self-review discipline. With real consensus, the effect would be larger (~+7.0).

**New highs:** Real consensus + self-review hit 0.949 on T7 and 0.924 on T8 (Analytics Dashboard) — the hardest task in the suite. T8's best single trial was 0.950, the highest score any variant has achieved on that task.

**Implications:**

1. **Self-review is the low-hanging fruit.** Adding "commit and self-review your diff before finishing" to any adapter's system prompt yields +4.7 points at zero marginal cost. Every contender should do this.

2. **Consensus adds real but modest value.** +2.2 points on top of self-review, primarily on complex tasks. Whether the extra API cost ($0.20-0.40/task) is worth it depends on the task complexity.

3. **The combined effect (+7.0) is the largest improvement found.** Larger than any single gene tested: ts-dev (-4.6), TDD (-3.2), systematic debugging (0), self-review (+4.7), consensus alone (+2.2).

**Caveat:** 2 trials per variant per task. The T5 results have the highest variance (self-review: 0.730-0.880, consensus: 0.790-0.890). More trials needed for confidence intervals.

#### Agent Teams: Parallel Teammates on Marathon Tasks

**Hypothesis:** Claude Code's experimental agent teams feature — spawning parallel teammate subagents to work on subtasks — improves performance on complex and marathon tasks.

**Setup:** Claude Code Opus 4.6 in interactive mode (tmux harness with idle detection), `--agent-teams` enabled. Token costs estimated from session JSONL files using Opus per-token rates. Compared against vanilla Claude Code (headless `-p` mode).

| Task | Claude Code | Agent Teams | Delta | AT Mode |
| --- | ---: | ---: | ---: | --- |
| **T1** time-tracker | 92.3% | 92.0% | -0.3 | Solo TUI |
| **T5** task-queue | 62.1% | 69.3% | +7.2 | 4 teammates |
| **T7** plugin-marketplace | 91.4% | 89.0% | -2.4 | Solo TUI |
| **T8** analytics-dashboard | 82.8% | 82.1% | -0.7 | Solo TUI |

**Findings:**

1. **Agent Teams only spawns teammates on the marathon task.** T5 produced 5 session JSONL files (1 coordinator + 4 teammate subagents) with `Task` tool in tools_used. T1, T7, and T8 each produced a single session — the agent decided the tasks didn't need parallelization and ran solo in TUI mode.

2. **Teammates are 3x slower and 5x more expensive for +7 points.** T5 with teammates: 1472s, $8.01, 2.6M tokens. Vanilla: 455s, $1.61. The coordinator spawns workers but the task's 12 sequential phases can't truly parallelize — workers likely step on each other or serialize naturally.

3. **Solo TUI mode matches headless `-p` mode.** On the three solo tasks, Agent Teams scores (92.0, 89.0, 82.1) are within noise of vanilla Claude Code (92.3, 91.4, 82.8). Interactive mode with idle detection doesn't help or hurt.

4. **Supports H5.** The Task Queue Marathon is inherently sequential (12 ordered phases). Spawning parallel workers on a sequential workload adds coordination overhead without enabling real parallelism. This aligns with hypothesis H5: naive parallelization on non-decomposable tasks eliminates the advantage.

**Caveat:** Single trial per task. Agent Teams cost estimation uses session JSONL token counts at published Opus rates ($15/$75 per million input/output tokens).

#### Branch Ablation: Real Git Branch vs Detached HEAD

**Hypothesis:** Gas Station's `git checkout -b main` (creating a real branch from detached HEAD) explains part of its +18.9 point T5 advantage.

**Setup:** Vanilla Claude Code Opus 4.6 with one addition: `git checkout -b main` before running the agent. Everything else identical to vanilla.

| Variant | Trial 1 | Trial 2 | Mean |
| --- | ---: | ---: | ---: |
| **Vanilla Claude Code** | — | — | 62.1% |
| **Claude Code + Branch** | 64.0% | 45.0% | 54.5% |

**Finding:** Creating a real branch is a net negative (-7.6 points). The branch hypothesis is ruled out — it's not the active ingredient in Gas Station.

#### Worktree Ablation: The Gas Station Mystery Solved

**Hypothesis:** Gas Station's advantage comes from working in a git worktree created from a bare clone, not from any Gas Town tooling.

**Setup:** Vanilla Claude Code Opus 4.6 with bare clone + worktree plumbing only. No Gas Town tooling (no beads, no `gt prime`, no env vars), no system prompt changes, no `--disallowed-tools`. Just:
1. `git checkout -b main` (prerequisite for bare clone)
2. `git clone --bare /workspace /tmp/workspace-bare.git`
3. `git worktree add -b work /tmp/worktree/bench main`
4. Run Claude in the worktree
5. Copy files back to /workspace

| Variant | Trial 1 | Trial 2 | Mean |
| --- | ---: | ---: | ---: |
| **Vanilla Claude Code** | — | — | 70.2% |
| **Gas Station** (5 trials) | — | — | 88.9% |
| **Claude Code + Worktree** | 89.2% | 89.9% | **89.5%** |

**Finding: The worktree is the active ingredient.** The worktree ablation (89.5%) matches Gas Station (88.9%) within noise, confirming that the +18.9 point T5 advantage comes entirely from working in a git worktree from a bare clone. All Gas Town ceremony — beads database, `gt prime` context, polecat env vars, headless system prompt — contributes nothing.

**Ruled out (no effect):**
- `git checkout -b main` alone: -7.6 points (hurts)
- `--disallowed-tools` + headless prompt: no effect
- Gas Town env vars (GT_RIG, GT_ROLE, etc.): not needed
- `.beads/` directory: not needed
- `gt prime` execution: not needed

**Why the worktree helps is now explained — see the No-Git Ablation below.** The mechanism is `.git` directory noise polluting the agent's file exploration. Removing `.git` entirely (without any worktree) reproduces the same improvement.

This is the largest single improvement found (+19.3 points). Unlike other improvements, this one is free — zero token cost, ~2 seconds of setup time.

#### The Gas Station Mystery: Solved — Git Worktree Is the Active Ingredient

**The investigation:** Gas Station scored 88.9% on T5 (marathon) vs vanilla Claude Code's 70.0% — a +18.9 point gap. We systematically isolated every variable through a series of ablations.

**Initial hypothesis (wrong):** Gas Station's advantage comes from its `--disallowed-tools` flag and "you're headless" system prompt.

**Headless ablation:** Three variants, all Opus 4.6 on 4 greenfield tasks:

| Task | Vanilla (n=2) | Headless (n=2) | Gas Station (n=2) |
| --- | ---: | ---: | ---: |
| **T1** time-tracker | 91.0% | 92.0%* | 93.9% |
| **T5** task-queue | 70.0% | 59.6% | **89.9%** |
| **T7** plugin-marketplace | 91.4% | 90.9% | 91.6% |
| **T8** analytics-dashboard | 82.8% | 83.0% | 70.4% |

\*T1 headless trial 2 excluded (rubric judge rate-limited → 0 rubric score)

Headless hints explain nothing. T5 headless is *worse* than vanilla (59.6% vs 70.0%).

**Gas Station T5 confirmation (5 trials):**

| Gas Station T5 | Trial 1 | Trial 2 | Trial 3 | Trial 4 | Trial 5 | Mean |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| **Score** | 89.0% | 90.8% | 91.0% | 83.0% | 90.7% | **88.9%** |

**Decomposition — isolating the worktree gene:**

Gas Station does 6 things before running the agent. We tested each:

| Factor | Ablation | T5 Result | Verdict |
| --- | --- | ---: | --- |
| `git checkout -b main` | Branch ablation | 54.5% (n=2) | Hurts (-7.6) |
| `--disallowed-tools` + headless prompt | Headless ablation | 59.6% (n=2) | Hurts (-10.4) |
| Gas Town env vars, beads, gt prime | (included in Gas Station, excluded in worktree ablation) | — | No effect |
| **Bare clone + git worktree + file copy** | **Worktree ablation** | **89.5% (n=2)** | **+19.3 points** |

The worktree ablation (89.5%) matches Gas Station (88.9%) within noise, using nothing but vanilla Claude Code + `git clone --bare` + `git worktree add` + running the agent in the worktree + copying files back. All Gas Town ceremony — beads database, `gt prime` context, polecat env vars — contributes nothing.

**Why a worktree helps — mechanism confirmed:** See the No-Git Ablation section below. The `.git` directory pollutes the agent's exploration with noise files (`.git/HEAD`, `.git/config`, `.git/description`, `.git/index`, `.git/packed-refs`) that consume ~2,100 tokens of context and persist through all 48-88 turns of the marathon. The worktree replaces this directory with a single `.git` file (a pointer to the bare repo), eliminating the noise. Removing `.git` entirely (no worktree needed) reproduces the same +20 point improvement.

**Cost:** Zero. The worktree setup adds ~2 seconds and no token cost. This is the only free +19 point improvement found in the entire study.

#### No-Git Ablation: The Mechanism Confirmed

**Hypothesis:** The worktree advantage comes from eliminating `.git` directory noise in the agent's file exploration, not from anything specific to git worktree semantics.

**Setup:** Vanilla Claude Code Opus 4.6 with workspace files copied (via `tar`) to a clean directory with NO `.git` directory at all. No bare clone, no worktree, no branch — just the project files in a fresh `/tmp/clean-workspace/`.

| Variant | Trial 1 | Trial 2 | Mean | Mean Cost |
| --- | ---: | ---: | ---: | ---: |
| **Vanilla Claude Code** | — | — | 70.2% | ~$2.50 |
| **Gas Station** (5 trials) | — | — | 88.9% | ~$2.40 |
| **Claude Code + Worktree** | 89.2% | 89.9% | 89.5% | $1.61 |
| **Claude Code + No Git** | 90.4% | 90.6% | **90.5%** | **$1.20** |

Greenfield breakdown (No-Git):

| Trial | Hidden Tests | Agent Tests | Coverage | Code Metrics | Rubric |
| --- | ---: | ---: | ---: | ---: | ---: |
| **Trial 1** | 1.000 | 1.000 | 0.898 | 0.900 | 0.813 |
| **Trial 2** | 1.000 | 1.000 | 0.915 | 0.800 | 0.838 |

**Finding: Removing `.git` reproduces the full worktree advantage — and then some.** The no-git ablation (90.5%) matches or exceeds the worktree (89.5%) and Gas Station (88.9%), confirming that the `.git` directory is the sole cause of the ~20 point performance gap on marathon tasks.

**The mechanism in detail:**

1. **Noise injection:** When the agent explores the workspace with `find` or `ls`, a `.git` directory exposes internal files (`.git/HEAD`, `.git/config`, `.git/description`, `.git/index`, `.git/packed-refs`) — 5+ extra entries mixed in with project files.

2. **Context pollution:** The agent's Explore subagent builds a comprehensive project summary that includes `.git/` in the directory tree. This summary (~1,671 tokens) becomes the agent's foundational mental model of the project and persists in the prompt cache through all subsequent turns.

3. **Cumulative cost:** Across a 48-88 turn marathon, ~2,100 tokens of `.git` noise (19-22% of all tool result tokens) sit in the context window without ever being used. The agent never reads, references, or reasons about these files.

4. **Architectural degradation:** The effect is not just token waste — it degrades code quality. Vanilla agents produce flat data structures, monolithic files, and scattered tests (rubric ~0.24). No-git agents produce proper abstractions, dedicated modules, and consolidated tests (rubric ~0.83). The agent makes fundamentally better architectural decisions when its initial project understanding isn't cluttered with infrastructure noise.

**Cost savings:** No-git is also the cheapest variant at $1.20/trial — 52% cheaper than vanilla ($2.50) and 50% cheaper than Gas Station ($2.40). Fewer turns (25-48 vs 74-87) suggest the agent works more efficiently without the noise.

**Implication for all benchmarks:** Any benchmark framework that clones a git repository and runs an AI agent in it may be inadvertently degrading performance. The fix is trivial: copy the workspace files to a directory without `.git`, or use a git worktree.

#### Fresh-Context Ralph Loops (H3)

**Hypothesis (H3):** Fresh-context Ralph loops outperform stale-context loops on marathon tasks.

**Setup:** Ralph loop adapter runs Claude Code Opus 4.6 in a loop. Each iteration gets fresh context (new `claude -p` invocation) but works in the same persistent workspace. After iteration 1, subsequent iterations receive the original task prompt plus current `npm test` output showing which tests fail. Minimum 2 iterations, maximum 4. The agent's conversation history resets between iterations, but all code changes survive.

Compared against vanilla Claude Code (stale context — one long session where context accumulates) on T5 marathon.

| Variant | Trial 1 | Trial 2 | Mean | Mean Cost | Iterations |
| --- | ---: | ---: | ---: | ---: | ---: |
| **Vanilla Claude Code** | — | — | 62.1% | $1.61 | 1 (internal) |
| **Ralph Fresh** | 86.5% | 63.8% | **75.1%** | $2.21 | 2 each |

Greenfield breakdown (Ralph Fresh):

| Trial | Hidden Tests | Agent Tests | Coverage | Code Metrics | Rubric |
| --- | ---: | ---: | ---: | ---: | ---: |
| **Trial 1** | 1.000 | 1.000 | 0.941 | 0.900 | 0.675 |
| **Trial 2** | 1.000 | 1.000 | 0.915 | 0.700 | 0.100 |

**Findings:**

1. **Fresh context helps, but with high variance.** Ralph Fresh averages +13 points over vanilla (75.1% vs 62.1%), but individual trials range from 63.8% to 86.5%. Both trials completed in exactly 2 iterations — the agent's first pass built the bulk, the fresh-context second pass fixed remaining issues.

2. **Perfect hidden test scores.** Both trials achieved 1.000 on hidden tests — all 108 validation tests passing. This is rare for vanilla Claude Code on T5. The fresh-context second iteration re-reads the codebase without accumulated context pollution and can effectively identify and fix remaining issues.

3. **The rubric is the variance driver.** Trial 1 scored 0.675 on rubric, trial 2 scored 0.100. Both had similar test/coverage scores. The LLM rubric judge is the main source of score variance between trials.

4. **H3 is partially supported but overshadowed by the no-git effect.** Fresh context (+13 points, $2.21) provides a meaningful improvement, but removing `.git` directory noise (+20 points, $1.20) achieves more at half the cost with a single iteration. The mechanism is now understood: `.git` directory contents pollute the agent's file exploration and degrade architectural decisions (see No-Git Ablation). Fresh context may help by resetting accumulated noise, but preventing the noise in the first place is cheaper and more effective.

5. **Cost is 37% higher.** Ralph Fresh uses $2.21 vs $1.61 for vanilla, reflecting the overhead of two separate `claude -p` sessions (double the cache creation tokens). The improvement per dollar is worse than the worktree ablation.

**Caveat:** 2 trials per variant. The high variance (86.5% vs 63.8%) suggests more trials are needed for confidence intervals. The stale-context baseline is pooled from earlier runs (n=4).

#### Planned Ablations

| Ablation | A | B | Gene Isolated | Status |
|---|---|---|---|---|
| Parallelism | Gas Town | Gas Station | Mayor + parallel polecats + refinery | Data exists (needs more trials) |
| Gas Station scaffolding | Gas Station | Claude Code + Headless | Git worktree + branch setup (gt prime discarded) | **Done — +18.9 on T5 (mystery)** |
| Git worktree isolation | Claude Code + Worktree | Claude Code | Bare clone + worktree (no Gas Town tooling) | **Done — +19.3 on T5 (confirms worktree is the active ingredient)** |
| Consensus review only | Conclave Review | Claude Code | Multi-agent code review (no skills) | **Done — +5.0 points** |
| Full skill pipeline | Full Conclave | Conclave Review | Brainstorm/plan/implement workflow | **Done — -11.9 points** |
| Systematic debugging | Superpowers Debug | Claude Code | Four-phase debugging methodology | **Done — +0.5 points (noise)** |
| Test-driven development | Superpowers TDD | Claude Code | Forced red-green-refactor cycle | **Done — -3.2 points** |
| Consensus design review | Conclave Design | Claude Code | Pre-implementation multi-model architecture guidance | **Done — +3.8 points** |
| Self-review discipline | Double Review (no keys) | Claude Code | "Commit, review your diff, fix" in system prompt | **Done — +4.7 points (free)** |
| Self-review + consensus | Double Review (keys) | Claude Code | Self-review + real multi-model consensus | **Done — +7.0 points (best result)** |
| Mandatory skills | Conclave | Claude Code | Conclave plugin (TDD, debugging, planning) | Data exists (needs more trials) |
| Skill optionality | Conclave | Superpowers | Mandatory vs optional skill invocation | Data exists (needs more trials) |
| Metacognitive reframing | Metacog | Claude Code | Pre-implementation thinking skill | Data exists (needs more trials) |
| Agent teams | Agent Teams | Claude Code | In-process teammate coordination | **Done — +7.2 on T5 (only task with teammates), solo elsewhere** |
| Branch from detached HEAD | Claude Code + Branch | Claude Code | `git checkout -b main` before agent | **Done — -7.6 on T5 (ruled out as Gas Station factor)** |
| Fresh-context Ralph loop | Ralph Fresh | Claude Code | Multi-iteration fresh context on same workspace | **Done — +13.0 on T5 (H3 partially supported)** |
| No-git workspace | Claude Code + No Git | Claude Code | Remove .git directory entirely | **Done — +20.3 on T5 (confirms .git noise is the mechanism)** |
| Structured recipes | Amplifier + recipes | Amplifier | Multi-step orchestration behaviors | Not started |
| Agent delegation | Amplifier + delegate | Amplifier | Sub-session spawning | Not started |

## Why This Exists

Every AI coding tool claims superiority. None publish reproducible head-to-head comparisons. Thunderdome fills that gap by running orchestrators against identical tasks in isolated Docker containers, scoring their output with automated tests, static analysis, and LLM-judged rubrics.

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
  │    ├─ LLM rubric judge (scored against task-specific criteria)
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

# Validate a previous run's workspace
./thunderdome validate ./results/runs/<run-id>/trials/<orch>/<task>/trial-1
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

The composite score blends test pass rate, static analysis, and rubric scores. Greenfield tasks additionally include hidden tests, code coverage, and code metrics.

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
| **Rubric** | LLM judge scores the diff against task-specific criteria | Task-specific |
| **Hidden tests** | Tests on `v1-validation` tag, not visible to orchestrator | Greenfield only |
| **Coverage** | Statement coverage of agent-written tests | Greenfield only |
| **Code metrics** | Lines of code, complexity, duplication | Greenfield only |

The composite score is a weighted sum. Each task defines its own weights, so bugfix tasks weight tests higher; greenfield tasks include the full six-axis scoring.

## Project Structure

```
.
├── main.go                     # Entry point
├── cmd/                        # CLI commands (run, list, report, validate)
├── internal/
│   ├── config/                 # YAML config parsing and validation
│   ├── docker/                 # Container lifecycle management
│   ├── gateway/                # API proxy (proxy.py), usage tracking
│   ├── gitops/                 # Clone, checkout, diff capture
│   ├── report/                 # Table, Markdown, JSON report generation
│   ├── result/                 # Trial metadata types and storage
│   ├── runner/                 # Trial execution, validation pipeline, pool
│   └── validation/             # Tests, lint, rubric, hidden tests, coverage, code metrics
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
- [ ] Ablation studies (gene isolation) — 13 done: ts-dev (-4.6), consensus review (+5.0), systematic debugging (no effect), TDD (-3.2), design review (+3.8), self-review (+4.7), self-review+consensus (+7.0), Gas Station mystery solved (worktree = +19.3), agent teams (+7.2 on T5 only), branch ablation (-7.6), worktree isolation (+19.3), Ralph fresh-context (+13.0 on T5), **no-git mechanism confirmed (+20.3 on T5)**
- [ ] Publish methodology paper

## License

TBD
