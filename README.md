# Agentic Thunderdome

Two agents enter, one agent leaves.

A benchmarking framework that pits agentic coding orchestrators against standardized programming tasks and measures what matters: completion rate, token efficiency, cost, and correctness.

## Results

Composite scores across all 11 tasks (tests + build/lint for standard tasks; hidden_tests + agent_tests + coverage + code_metrics + lint for greenfield). Data includes 642 trials across 27 primary orchestrator variants. All scoring is deterministic — no LLM judges, no rubric. Early adapter-debugging trials have been pruned — each orchestrator's data starts from its first stable full-suite run.

### Leaderboard

Mean composite score across all tasks run, ranked by score. Orchestrators with fewer trials or tasks may be less reliable.

| Rank | Orchestrator | Mean | Tasks | Trials | Avg Cost | Model |
|---:|---|---:|---:|---:|---:|---|
| 1 | Superpowers Brainstorm | **97.4%** | 11 | 38 | $1.43 | Opus 4.6 |
| 2 | Superpowers TDD | **97.4%** | 11 | 16 | $2.32 | Opus 4.6 |
| 3 | Stacked | **97.3%** | 11 | 11 | $1.36 | Opus 4.6 |
| 4 | Superpowers Verify | **97.3%** | 11 | 11 | $0.94 | Opus 4.6 |
| 5 | Conclave Review | **97.2%** | 10 | 11 | $1.82 | Multi-provider |
| 5 | Review + Verify | **97.2%** | 11 | 11 | $2.28 | Opus 4.6 |
| 6 | Self-Review (Sonnet) | **97.1%** | 11 | 22 | $1.13 | Sonnet 4.6 |
| 7 | Superpowers Review | **97.0%** | 11 | 34 | $2.01 | Opus 4.6 |
| 8 | Superpowers Plans | **96.9%** | 11 | 11 | $1.05 | Opus 4.6 |
| 9 | Self-Review (Opus) | **96.8%** | 11 | 40 | $1.33 | Opus 4.6 |
| 10 | Gas Town | **96.6%** | 10 | 24 | $0.02 | Opus 4.6 |
| 11 | Superpowers Debug | **96.4%** | 4 | 9 | $0.88 | Opus 4.6 |
| 12 | Metacog | **95.9%** | 11 | 22 | $0.70 | Opus 4.6 |
| 13 | Conclave Design | **95.7%** | 4 | 9 | $2.09 | Multi-provider |
| 14 | Conclave (Full) | **95.2%** | 10 | 12 | $0.14 | Multi-provider |
| 15 | Conclave Double Review | **95.2%** | 4 | 9 | $1.26 | Multi-provider |
| 16 | Conclave Dbl Review + Keys | **95.0%** | 4 | 9 | $1.89 | Multi-provider |
| 17 | Ralph Fresh | **94.7%** | 2 | 4 | $1.57 | Opus 4.6 |
| 18 | Claude Code Worktree | **94.7%** | 2 | 3 | $1.20 | Opus 4.6 |
| 19 | Claude Code Headless | **94.2%** | 4 | 9 | $1.15 | Opus 4.6 |
| 20 | Gas Station | **92.6%** | 10 | 22 | $0.71 | Opus 4.6 |
| 21 | Agent Teams | **86.2%** | 10 | 28 | $0.49 | Opus 4.6 |
| 22 | Claude Code | **85.9%** | 11 | 24 | $0.27 | Opus 4.6 |
| 23 | Amplifier + ts-dev | **85.5%** | 10 | 11 | $0.75 | Opus 4.6 |
| 24 | Amplifier | **84.6%** | 10 | 11 | $0.02 | Opus 4.6 |
| 25 | Amp Flash | **84.2%** | 10 | 11 | $0.00 | Gemini 3 Flash |
| 26 | Gemini CLI | **82.0%** | 10 | 19 | $0.00 | Gemini 3 Flash |

### Key Findings

- **The model doesn't matter — the system prompt does.** Sonnet 4.6 + self-review (97.1%) matches Opus 4.6 + self-review (96.8%) and ties with Opus + skill-based approaches (97.0-97.4%). A ~5x cheaper model with nine lines of instructions matches the most expensive orchestrators in the benchmark. Three crashes in 25 trials (12%) are the only Sonnet weakness
- **Multi-trial data compresses the spread.** With n=22-40 trials per orchestrator, the top 10 contenders cluster within 0.6 points (96.8%-97.4%). The n=1 rankings were noise — what looked like meaningful differences between skill-based approaches was just variance
- **A system prompt is (almost) all you need.** Self-Review scores 96.8-97.1% depending on model — no plugins, no skills, no consensus. The entire skill infrastructure adds ~0.3 points over a well-worded system prompt. The gap is negligible
- **The real gap is vanilla vs any discipline.** Claude Code without any review instruction scores 85.9%. Adding "verify and review your diff" to the system prompt jumps to 97% — an 11 point improvement for free. All the skill infrastructure, consensus protocols, and multi-agent reviews fight over the last 0.3 points
- **Superpowers Brainstorm** is #1 at 97.4% (n=38) — consensus-driven design exploration held up best with more data. $1.43/task
- **Superpowers Verify** is the best cost-adjusted skill — 97.3% at $0.94/task (n=11, needs more trials to confirm)
- **Superpowers Review regressed the most** — from 97.7% (n=1) to 97.0% (n=34). The original score was an outlier. Still effective but not the clear #1 it appeared to be
- **Gene stacking has diminishing returns** — Review + Verify (97.2%) scores at the same level as either alone. Two discipline checkpoints don't compound. The ceiling appears to be ~97% with current single-session approaches
- **Gas Town** is the biggest mover after data cleanup — 96.6% mean (was 81.3% when adapter failures polluted the data). The real multi-agent pipeline actually works
- **TDD works when forced** — 97.4% with forced red-green-refactor (n=16). Tied with Brainstorm for #1 but costs $2.32/task vs $1.43
- **T4** (bugfix) is the great equalizer — most contenders score 100%, the task is too easy
- **T8** (analytics dashboard) is the hardest task — most contenders cluster around 87-90%

### The Gas Station Story

Gas Town is a multi-agent pipeline: a Mayor decomposes the task, parallel Polecats implement pieces in git worktrees, and a Refinery merges their work and fixes conflicts. We asked Claude Code to build the adapter.

What it delivered was a fraud — a single `claude -p` call with `gt prime` context injected, wearing Gas Town's scaffolding like a trench coat. It set up the town, created beads, initialized a polecat worktree, the whole ceremony — then ran one agent that did all the work by itself. A single agent pretending to be a workforce.

I named the impostor "Gas Station" and kept it as a control while we built the real multi-agent pipeline ourselves.

Then the benchmarks came back. Gas Station scored 92.6% (n=22 trials). The single agent in a trench coat was the most consistent performer in the benchmark — until we cleaned up Gas Town's adapter failures and discovered the real multi-agent pipeline scores 96.6% (n=24). The complexity justified itself after all, but Gas Station earned its place: a permanent reminder to validate your baselines before drawing conclusions.

### Ablation Studies

We're isolating individual orchestrator "genes" — composable features like multi-agent consensus, skill injection, parallel execution — to measure which actually help. Each ablation holds everything constant except one gene.

#### TypeScript Expertise: Amplifier + ts-dev Bundle

**Hypothesis:** Giving the agent TypeScript-specific tools (LSP code intelligence, code quality analysis, a specialized TS expert agent) improves performance on TypeScript benchmarks.

**Setup:** Amplifier with Opus 4.6, comparing bare foundation bundle vs foundation + [ts-dev](https://github.com/microsoft/amplifier-bundle-ts-dev) app bundle. Same model, same provider, same tasks. After pruning adapter-debugging trials, both variants have n=1 per task (n=2 for T1 bare, T8 ts-dev).

| Task | Amplifier (bare) | Amplifier + ts-dev | Delta |
| --- | ---: | ---: | ---: |
| **T1** time-tracker | 97.6% (n=2) | 64.6% (n=1) | -33.0 |
| **T2** collab-server | 63.1% (n=1) | 93.7% (n=1) | +30.6 |
| **T3** fts-search | 100.0% (n=1) | 100.0% (n=1) | 0.0 |
| **T4** phantom-invoice | 100.0% (n=1) | 100.0% (n=1) | 0.0 |
| **T5** task-queue | 94.5% (n=1) | 95.3% (n=1) | +0.8 |
| **T6** monorepo-disaster | 100.0% (n=1) | 100.0% (n=1) | 0.0 |
| **T7** plugin-marketplace | 21.5% (n=1) | 99.1% (n=1) | +77.6 |
| **T8** analytics-dashboard | 91.3% (n=1) | 61.5% (n=2) | -29.8 |
| **T9** ssg-toolkit | 100.0% (n=1) | 100.0% (n=1) | 0.0 |
| **T10** ecommerce-backend | 64.6% (n=1) | 64.6% (n=1) | 0.0 |
| **Mean** | **84.6%** | **85.5%** | **+0.9** |

**Finding: ts-dev has no meaningful effect (+0.9 points).** With adapter noise removed, the two variants are essentially tied. The huge swings on individual tasks (T7: +77.6, T1: -33.0) with n=1 are just variance, not signal. This ablation needs more trials to draw any conclusion.

#### Consensus Code Review: Conclave Review vs Claude Code vs Full Conclave

**Hypothesis:** Multi-agent consensus code review (Claude + Gemini + Codex reviewing the diff) catches defects that a single agent misses, improving final code quality.

**Setup:** Three variants, all using Opus 4.6:
- **Claude Code** — vanilla single agent, no review
- **Conclave Review** — vanilla agent + one round of `conclave consensus --mode=code-review` after implementation, then fix findings. No skills, no planning ceremonies.
- **Conclave (full)** — mandatory skill pipeline: brainstorm → plan → implement → verify → finish, with consensus woven throughout

| Task | Claude Code | Conclave Review | Full Conclave | Review delta |
| --- | ---: | ---: | ---: | ---: |
| **T1** time-tracker | 79.1% (n=6) | 98.1% (n=2) | 98.3% (n=2) | +19.0 |
| **T2** collab-server | 55.0% (n=2) | 94.5% (n=1) | 96.0% (n=2) | +39.5 |
| **T3** fts-search | 100.0% (n=2) | 100.0% (n=1) | 100.0% (n=1) | 0.0 |
| **T4** phantom-invoice | 100.0% (n=2) | 100.0% (n=1) | 100.0% (n=1) | 0.0 |
| **T5** task-queue | 73.3% (n=4) | 93.1% (n=1) | 96.0% (n=1) | +19.8 |
| **T6** monorepo-disaster | 100.0% (n=1) | 100.0% (n=1) | 100.0% (n=1) | 0.0 |
| **T7** plugin-marketplace | 98.9% (n=1) | 99.0% (n=1) | 98.2% (n=1) | +0.1 |
| **T8** analytics-dashboard | 87.7% (n=1) | 89.8% (n=1) | 64.6% (n=1) | +2.1 |
| **T9** ssg-toolkit | 100.0% (n=1) | 100.0% (n=1) | 100.0% (n=1) | 0.0 |
| **T10** ecommerce-backend | 96.8% (n=1) | 97.0% (n=1) | 95.5% (n=1) | +0.2 |
| **Mean** | **85.9%** | **97.2%** | **95.2%** | **+11.3** |

**Findings:**

1. **Consensus review is a large net positive (+11.3 points).** The three-provider code review catches real issues. Biggest gains on collab-server (T2: +39.5) and marathon (T5: +19.8).

2. **The full Conclave pipeline is competitive with review-only** (95.2% vs 97.2%). After pruning adapter-debugging trials, the mandatory skill pipeline no longer looks harmful — it's within 2 points of the stripped-down review variant. The earlier -19 point gap was mostly adapter noise, not a real methodology penalty.

3. **T8 (analytics dashboard) remains the full pipeline's weakness** — 64.6% vs 89.8% for review-only. The mandatory brainstorm → plan ceremony may hurt on tasks where the planning overhead outweighs the benefit.

4. **Cost tradeoff is reasonable** — $1.82/task average for review vs Claude Code's ~$0.27. The consensus review delivers a consistent 11-point improvement across the full suite.

**Caveat:** Conclave Review and Full Conclave have n=1-2 per task. Claude Code baseline has n=1-6 per task with high variance on T1 and T2.

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

**Contrast with consensus code review (+11.3 points):** Review adds a *concrete action* — three independent models examining the diff — that catches bugs the solo agent missed. Systematic debugging adds *process* — phases, checklists, red-flag lists — that the agent already follows instinctively. Concrete actions beat process guidance.

#### Test-Driven Development: Forced TDD — Full Suite

**Hypothesis:** Writing failing tests before implementation code produces higher-quality projects — better test coverage, fewer defects, more robust architecture.

**Setup:** Claude Code Opus with the TDD skill forcibly invoked via system prompt. Mandates strict red-green-refactor: write one failing test, implement minimally to pass, refactor, repeat. Run across all 11 tasks.

| Task | Category | TDD | Claude Code | Delta |
| --- | --- | ---: | ---: | ---: |
| **T1** time-tracker | greenfield/simple | 97% (n=1) | 83.9% (n=6) | +13.1 |
| **T2** collab-server | greenfield/complex | 97% (n=1) | 64.9% (n=2) | +32.1 |
| **T3** fts-search | features/medium | 100% (n=1) | 99.3% (n=2) | +0.7 |
| **T4** phantom-invoice | bugfix/medium | 100% (n=1) | 100.0% (n=2) | 0.0 |
| **T5** task-queue | marathon | 93% (n=1) | 75.7% (n=4) | +17.3 |
| **T6** monorepo-disaster | recovery | 100% (n=1) | 100.0% (n=1) | 0.0 |
| **T7** plugin-marketplace | greenfield/complex | 99% (n=1) | 94.9% (n=1) | +4.1 |
| **T8** analytics-dashboard | greenfield/complex | 94% (n=1) | 87.9% (n=1) | +6.1 |
| **T9** ssg-toolkit | features/complex | 100% (n=1) | 99.4% (n=1) | +0.6 |
| **T10** ecommerce-backend | greenfield/complex | 98% (n=1) | 89.8% (n=1) | +8.2 |
| **T11** debug-nightmare | bugfix/hard | 100% (n=1) | 99.3% (n=3) | +0.7 |
| **Mean** | | **98.0%** | **89.6%** | **+8.4** |

**Findings:**

1. **TDD is the highest-scoring approach in the benchmark at 98.0%.** Five perfect scores (T3, T4, T6, T9, T11). Every task scores 93% or above.

2. **Biggest gains on complex greenfield tasks.** T2 collab-server (+32.1), T5 marathon (+17.3), T1 time-tracker (+13.1). The forced test-first discipline most helps tasks where the agent might otherwise skip testing or build incomplete implementations.

3. **No effect on tasks the model already aces.** T3, T4, T6, T9, T11 — all already at or near 100% baseline. TDD can't improve what's already perfect.

4. **Cost is the tradeoff.** $2.14/task mean — 8x vanilla Claude Code ($0.27) and 57% more than Metacog ($1.36). The marathon task (T5) cost $7.18 alone. The red-green-refactor cycle adds turns: 135 turns on T5 vs typical 40-70.

5. **Earlier 4-task comparison was misleading.** The previous analysis called TDD "inconclusive" based on 4 greenfield tasks with noisy baselines. The full 11-task run reveals a clear, consistent advantage.

**The revised pattern:** Forced TDD works — not because the model doesn't know how to test, but because the mandatory discipline prevents cutting corners under token pressure. The model naturally wants to implement first and test later (or not at all). Forcing test-first produces more thorough implementations. This contrasts with systematic debugging (no effect) where the model already follows the right process instinctively.

#### Verification Before Completion: Evidence Before Claims

**Hypothesis:** Forcing the agent to run fresh verification (tests, build, lint) and read the full output before claiming any work is complete prevents premature "done" claims and catches issues the agent would otherwise miss.

**Setup:** Claude Code Opus with the verification-before-completion skill forcibly invoked. The skill's "Iron Law": no completion claims without fresh verification evidence. The agent must identify what command proves its claim, run it, read the full output, and only then make the claim. Run across all 11 tasks.

| Task | Category | Verify | Claude Code | Delta |
| --- | --- | ---: | ---: | ---: |
| **T1** time-tracker | greenfield/simple | 98% (n=1) | 85.9% | +12.1 |
| **T2** collab-server | greenfield/complex | 93% (n=1) | 85.9% | +7.1 |
| **T3** fts-search | features/medium | 100% (n=1) | 85.9% | +14.1 |
| **T4** phantom-invoice | bugfix/medium | 100% (n=1) | 85.9% | +14.1 |
| **T5** task-queue | marathon | 96% (n=1) | 85.9% | +10.1 |
| **T6** monorepo-disaster | recovery | 100% (n=1) | 85.9% | +14.1 |
| **T7** plugin-marketplace | greenfield/complex | 99% (n=1) | 85.9% | +13.1 |
| **T8** analytics-dashboard | greenfield/complex | 88% (n=1) | 85.9% | +2.1 |
| **T9** ssg-toolkit | features/complex | 100% (n=1) | 85.9% | +14.1 |
| **T10** ecommerce-backend | greenfield/complex | 96% (n=1) | 85.9% | +10.1 |
| **T11** debug-nightmare | bugfix/hard | 100% (n=1) | 85.9% | +14.1 |
| **Mean** | | **97.3%** | **85.9%** | **+11.4** |

**Findings:**

1. **Verification matches TDD and Stacked at half the cost.** 97.3% mean at $0.94/task — vs TDD's $2.32 and Stacked's $1.36. Five perfect scores (T3, T4, T6, T9, T11). The cheapest way to reach the top tier.

2. **Minimal overhead.** 33-51 turns per task — barely more than vanilla Claude Code (~24). The skill is a checkpoint, not a workflow change. The agent implements freely and verifies at the end.

3. **The mechanism is simple.** The agent already *can* verify — it just doesn't always bother. The skill forces it to run `npm test`, `npm run build`, and `npm run lint` fresh and read the output before stopping. This catches issues the agent would otherwise ship.

4. **Contrasts with systematic debugging (no effect).** Debugging methodology tells the agent *how to think*. Verification tells the agent *what to do* — run the command, read the output. Concrete actions beat process guidance, again.

**Implication:** The single most cost-effective intervention is telling the agent "you may not claim completion without running verification and reading the output." This should be the default system prompt addition for any agentic coding tool.

#### Skill-Guided Code Review: Requesting Review via Skill

**Hypothesis:** The requesting-code-review skill, which guides the agent through committing, running `conclave consensus --mode=code-review`, and addressing findings, produces better outcomes than either hardcoded review instructions (Conclave Review) or no review at all (vanilla Claude Code).

**Setup:** Claude Code Opus with the requesting-code-review skill forcibly invoked. The agent implements freely, then must invoke the skill which guides it to commit, run multi-agent consensus code review (Claude + Gemini + Codex), and fix high/medium priority findings. Uses the conclave Docker image for access to the `conclave` binary. Run across all 11 tasks.

| Task | Category | Review | Claude Code | Delta |
| --- | --- | ---: | ---: | ---: |
| **T1** time-tracker | greenfield/simple | 97.3% (n=3) | 83.9% (n=6) | +13.4 |
| **T2** collab-server | greenfield/complex | 90.7% (n=4) | 64.9% (n=2) | +25.8 |
| **T3** fts-search | features/medium | 100% (n=3) | 99.3% (n=2) | +0.7 |
| **T4** phantom-invoice | bugfix/medium | 100% (n=3) | 100.0% (n=2) | 0.0 |
| **T5** task-queue | marathon | 94.5% (n=3) | 75.7% (n=4) | +18.8 |
| **T6** monorepo-disaster | recovery | 100% (n=3) | 100.0% (n=1) | 0.0 |
| **T7** plugin-marketplace | greenfield/complex | 98.9% (n=3) | 94.9% (n=1) | +4.0 |
| **T8** analytics-dashboard | greenfield/complex | 89.1% (n=3) | 87.9% (n=1) | +1.2 |
| **T9** ssg-toolkit | features/complex | 100% (n=3) | 99.4% (n=1) | +0.6 |
| **T10** ecommerce-backend | greenfield/complex | 96.6% (n=3) | 89.8% (n=1) | +6.8 |
| **T11** debug-nightmare | bugfix/hard | 100% (n=3) | 99.3% (n=3) | +0.7 |
| **Mean** | | **97.0%** | **89.6%** | **+7.4** |

**Findings:**

1. **Multi-trial data settled Review at 97.0% (n=34).** The original n=1 score of 97.7% regressed — the highest-scoring tasks (T1: 99%→97.3%, T5: 97%→94.5%) came back to earth with more data. Still effective, but no longer the clear #1.

2. **Five perfect scores hold up.** T3, T4, T6, T9, T11 remain at 100% across all trials. The review cycle is most impactful on complex greenfield (T2: +25.8) and marathon (T5: +18.8) tasks.

3. **Expensive for the tier.** $2.01/task mean — the most expensive contender in the top tier. Brainstorm achieves 97.4% at $1.43, and Self-Review achieves 96.8% at $1.33 with no infrastructure at all.

4. **The review gene is robust across delivery mechanisms.** Skill-guided (97.0%, n=34), hardcoded (97.2%, n=11), and system-prompt self-review (96.8%, n=40) all cluster within 0.4 points. The common thread: pausing to examine your work before claiming done.

**The multi-trial hierarchy:** Brainstorm (97.4%) ≈ TDD (97.4%) > Verify (97.3%) > Review (97.0%) > Plans (96.9%) > Self-Review (96.8%) > Vanilla (85.9%). All discipline genes cluster within 0.6 points of each other and beat vanilla by 11+ points.

#### Brainstorming: Consensus Design Exploration

**Hypothesis:** Having multiple AI models collaboratively explore the design space before coding — asking and answering architecture questions via consensus — produces better implementations than jumping straight to code.

**Setup:** Claude Code Opus with the brainstorming skill forcibly invoked in autopilot mode. The skill's autopilot uses `conclave consensus --mode=general-prompt` to answer each design question (database choice, API style, component architecture, etc.) via three-model consensus (Claude + Gemini + Codex). The agent works through architecture, components, data flow, error handling, and testing, writes a design document, then implements. Run across all 11 tasks. One T1 trial pruned (coverage infrastructure failure — `coverage-summary.json` not generated).

| Task | Category | Brainstorm | Claude Code | Delta |
| --- | --- | ---: | ---: | ---: |
| **T1** time-tracker | greenfield/simple | 97.4% (n=6) | 83.9% (n=6) | +13.5 |
| **T2** collab-server | greenfield/complex | 93.5% (n=4) | 64.9% (n=2) | +28.6 |
| **T3** fts-search | features/medium | 100% (n=4) | 99.3% (n=2) | +0.7 |
| **T4** phantom-invoice | bugfix/medium | 100% (n=3) | 100.0% (n=2) | 0.0 |
| **T5** task-queue | marathon | 94.8% (n=3) | 75.7% (n=4) | +19.1 |
| **T6** monorepo-disaster | recovery | 100% (n=3) | 100.0% (n=1) | 0.0 |
| **T7** plugin-marketplace | greenfield/complex | 99.1% (n=3) | 94.9% (n=1) | +4.2 |
| **T8** analytics-dashboard | greenfield/complex | 88.6% (n=3) | 87.9% (n=1) | +0.7 |
| **T9** ssg-toolkit | features/complex | 100% (n=3) | 99.4% (n=1) | +0.6 |
| **T10** ecommerce-backend | greenfield/complex | 98.3% (n=3) | 89.8% (n=1) | +8.5 |
| **T11** debug-nightmare | bugfix/hard | 100% (n=3) | 99.3% (n=3) | +0.7 |
| **Mean** | | **97.4%** | **89.6%** | **+7.8** |

**Findings:**

1. **Brainstorming holds at #1 with multi-trial data (97.4%, n=38).** Barely moved from the n=1 reading of 97.5% — the most stable top-tier contender. Tied with TDD for the highest mean. Six perfect scores (T3, T4, T6, T9, T11, and effectively T10 at 98.3%). 100% pass rate across all trials.

2. **Biggest gains on complex greenfield and marathon.** T2 collab-server (+28.6) and T5 marathon (+19.1) benefit most from consensus-driven design exploration. The multi-model design discussion surfaces architecture choices the solo agent might miss.

3. **Best cost/performance ratio in the top tier.** $1.43/task mean — cheaper than Review ($2.01) and TDD ($2.32). The autopilot consensus calls add overhead but the agent doesn't need as many implementation turns when it has a solid design to follow.

4. **T8 remains the ceiling.** At 88.6%, brainstorming barely improves the analytics dashboard task (+0.7). The design exploration doesn't help when the challenge is implementation complexity rather than architecture.

5. **Divergent exploration vs convergent discipline.** Brainstorming is the first "divergent" gene tested — it opens up the design space before narrowing. All previous top genes (Review, TDD, Verify) are "convergent" — they check work after implementation. Both approaches work, through different mechanisms.

**The multi-trial picture:** All discipline genes cluster within 0.6 points: Brainstorm (97.4%) ≈ TDD (97.4%) > Verify (97.3%) > Review (97.0%) > Plans (96.9%) > Self-Review (96.8%). The spread is noise. Any structured discipline beats unstructured vanilla by 11+ points.

#### Gene Stacking: Review + Verify (Diminishing Returns)

**Hypothesis:** Stacking the #1 scorer (Review, 97.7%) with the cheapest top-tier (Verify, 97.3%) should push past 98%. Review catches bugs via consensus, Verify ensures nothing ships unchecked — complementary mechanisms.

**Setup:** Claude Code Opus with both requesting-code-review and verification-before-completion skills forcibly invoked. The agent implements, commits, runs multi-agent code review, fixes findings, then runs fresh verification (tests, build, lint) before claiming completion. Run across all 11 tasks.

| Task | Category | Review+Verify | Review | Verify | Claude Code |
| --- | --- | ---: | ---: | ---: | ---: |
| **T1** time-tracker | greenfield/simple | 97% | 99% | 98% | 83.9% |
| **T2** collab-server | greenfield/complex | 93% | 93% | 93% | 64.9% |
| **T3** fts-search | features/medium | 100% | 100% | 100% | 99.3% |
| **T4** phantom-invoice | bugfix/medium | 100% | 100% | 100% | 100.0% |
| **T5** task-queue | marathon | 94% | 97% | 96% | 75.7% |
| **T6** monorepo-disaster | recovery | 100% | 100% | 100% | 100.0% |
| **T7** plugin-marketplace | greenfield/complex | 99% | 99% | 99% | 94.9% |
| **T8** analytics-dashboard | greenfield/complex | 90% | 90% | 88% | 87.9% |
| **T9** ssg-toolkit | features/complex | 100% | 100% | 100% | 99.4% |
| **T10** ecommerce-backend | greenfield/complex | 97% | 97% | 96% | 89.8% |
| **T11** debug-nightmare | bugfix/hard | 100% | 100% | 100% | 99.3% |
| **Mean** | | **97.2%** | **97.7%** | **97.3%** | **89.6%** |

**Findings:**

1. **Stacking doesn't help — it slightly hurts.** Review + Verify (97.2%) scores lower than Review alone (97.7%) and matches Verify alone (97.3%). Two discipline checkpoints are not additive.

2. **The marathon tells the story.** T5 drops from 97% (Review) to 94% (Review+Verify). The extra verification cycle after an already-thorough review adds turns without catching anything new, and the longer session may introduce regression.

3. **T8 is unchanged.** The hardest task scores 90% with or without stacking — the ceiling on analytics-dashboard isn't about discipline, it's about implementation complexity.

4. **More expensive for less.** $2.28/task — cheaper than Review alone ($2.48) oddly, but the score is lower. The agent may be spending the verification turns less productively when it's already done a thorough review.

5. **This mirrors the Double Review finding.** The earlier ablation showed consensus adds nothing on top of self-review (+15.7 vs +15.5). Here, verification adds nothing on top of code review. **One quality checkpoint is sufficient. Adding a second doesn't compound.**

**Implication:** The ~97-98% ceiling appears to be a hard limit with current single-session approaches. Breaking through likely requires fundamentally different architectures (fresh-context iteration, parallel decomposition) rather than stacking more discipline on a single session.

#### System Prompt Self-Review: No Skills, No Plugins, Just Instructions

**Hypothesis:** The ~97% top-tier scores require skill infrastructure (plugins, conclave binary, consensus protocols). A well-worded system prompt telling the agent "verify, commit, review your diff, fix issues" can't match actual skill-guided workflows.

**Setup:** Vanilla Claude Code Opus with NO plugins, NO skills, NO conclave binary — just `thunderdome/claude-code:latest` (not the conclave image). The only addition is a system prompt instructing the agent to: (1) implement, (2) run full verification (test/build/lint), (3) commit, (4) review its own diff with `git diff HEAD~1`, (5) fix any issues found, (6) repeat until clean. Run across all 11 tasks.

| Task | Category | Self-Review | Claude Code | Delta |
| --- | --- | ---: | ---: | ---: |
| **T1** time-tracker | greenfield/simple | 96.2% (n=5) | 83.9% (n=6) | +12.3 |
| **T2** collab-server | greenfield/complex | 92.0% (n=5) | 64.9% (n=2) | +27.1 |
| **T3** fts-search | features/medium | 100% (n=5) | 99.3% (n=2) | +0.7 |
| **T4** phantom-invoice | bugfix/medium | 100% (n=4) | 100.0% (n=2) | 0.0 |
| **T5** task-queue | marathon | 92.6% (n=3) | 75.7% (n=4) | +16.9 |
| **T6** monorepo-disaster | recovery | 100% (n=3) | 100.0% (n=1) | 0.0 |
| **T7** plugin-marketplace | greenfield/complex | 98.8% (n=3) | 94.9% (n=1) | +3.9 |
| **T8** analytics-dashboard | greenfield/complex | 88.8% (n=3) | 87.9% (n=1) | +0.9 |
| **T9** ssg-toolkit | features/complex | 100% (n=3) | 99.4% (n=1) | +0.6 |
| **T10** ecommerce-backend | greenfield/complex | 96.5% (n=3) | 89.8% (n=1) | +6.7 |
| **T11** debug-nightmare | bugfix/hard | 100% (n=3) | 99.3% (n=3) | +0.7 |
| **Mean** | | **96.8%** | **89.6%** | **+7.2** |

**Findings:**

1. **A system prompt nearly matches skill-based approaches — confirmed with n=40 trials.** 96.8% at $1.33/task — within 0.6 points of Brainstorm (97.4%, #1) and within 0.2 points of Review (97.0%). No plugins loaded, no conclave binary, no consensus API calls. Just nine lines of instructions. The slight regression from the n=1 reading (97.2%) confirms the gap is real but tiny.

2. **The gap that matters is vanilla vs discipline, not skill vs no-skill.** Vanilla Claude Code scores 85.9%. Adding "verify, commit, review your diff" to the system prompt jumps to 96.8% — a 10.9 point improvement for free. All the skill infrastructure fights over the remaining 0.6 points.

3. **100% pass rate, five perfect scores.** T3, T4, T6, T9, T11 remain at 100% across all trials. T10 ecommerce at 96.5% is remarkably tight (96.2-96.7%). The same pattern as every other discipline gene: huge gains on complex greenfield (T2: +27.1) and marathon (T5: +16.9), no effect on easy tasks.

4. **Cost is mid-tier.** $1.33/task — cheaper than Review ($2.01), TDD ($2.32), and Brainstorm ($1.43), but more than Verify ($0.94) and Plans ($1.05). The self-review loop adds turns but no external API calls.

5. **Reframes the entire study — and multi-trial data makes the case stronger.** With 40 trials, the system prompt baseline is the most-tested variant in the benchmark. Its 96.8% mean is statistically robust. The skill infrastructure (plugin loading, conclave binary, consensus protocols) buys 0.2-0.6 points over this free baseline. The instruction is what matters; the infrastructure is optional.

**Implication:** The single most impactful change to any agentic coding tool is adding "verify your work, commit, review your diff, fix issues, repeat until clean" to the system prompt. This is free, requires no infrastructure, and captures ~95% of the benefit of elaborate skill-based approaches.

#### Model Ablation: Sonnet 4.6 + Self-Review vs Opus 4.6 + Self-Review

**Hypothesis:** The ~97% top-tier scores require Opus 4.6 ($15/MTok input, $75/MTok output). Sonnet 4.6 (~5x cheaper) can't match it even with the same system prompt.

**Setup:** Identical to the Opus self-review adapter — same Docker image, same system prompt, same flags — but with `--model claude-sonnet-4-6` instead of `claude-opus-4-6`. Run across all 11 tasks with 2 trials each. Three trials crashed (ecommerce-backend ×2, ssg-toolkit ×1) and were rerun successfully.

| Task | Category | Sonnet | Opus | Delta |
| --- | --- | ---: | ---: | ---: |
| **T1** time-tracker | greenfield/simple | 99.0% (n=2) | 96.2% (n=5) | +2.8 |
| **T2** collab-server | greenfield/complex | 93.3% (n=2) | 92.0% (n=5) | +1.3 |
| **T3** fts-search | features/medium | 100% (n=2) | 100% (n=5) | 0.0 |
| **T4** phantom-invoice | bugfix/medium | 100% (n=2) | 100% (n=4) | 0.0 |
| **T5** task-queue | marathon | 94.0% (n=2) | 92.6% (n=3) | +1.4 |
| **T6** monorepo-disaster | recovery | 100% (n=2) | 100% (n=3) | 0.0 |
| **T7** plugin-marketplace | greenfield/complex | 96.9% (n=2) | 98.8% (n=3) | -1.9 |
| **T8** analytics-dashboard | greenfield/complex | 89.1% (n=2) | 88.8% (n=3) | +0.3 |
| **T9** ssg-toolkit | features/complex | 100% (n=2) | 100% (n=3) | 0.0 |
| **T10** ecommerce-backend | greenfield/complex | 95.5% (n=2) | 96.5% (n=3) | -1.0 |
| **T11** debug-nightmare | bugfix/hard | 100% (n=2) | 100% (n=3) | 0.0 |
| **Mean** | | **97.1%** | **96.8%** | **+0.3** |

**Findings:**

1. **Sonnet matches Opus.** 97.1% vs 96.8% — the cheaper model actually scores slightly higher. No task shows a meaningful gap. The system prompt is doing the work, not the model.

2. **Sonnet is less reliable.** 3 of 25 trials crashed (12%) vs 0% for Opus. The crashes were transient (retries succeeded), but in production this matters. Opus is more robust at the extremes.

3. **Sonnet actually wins on several tasks.** T1 (+2.8), T5 (+1.4), T2 (+1.3) — Sonnet outperforms Opus on the tasks where discipline matters most. Opus wins only on T7 (-1.9) and T10 (-1.0).

4. **Cost implications are dramatic.** Sonnet is ~5x cheaper per token. With similar turn counts, a Sonnet self-review run costs roughly $0.25/task vs Opus's $1.33/task. This means the best cost-adjusted configuration in the entire benchmark is Sonnet + system prompt — top-tier scores at a fraction of the cost.

**Implication:** Model choice is the least important variable in this benchmark. The system prompt matters. The model doesn't. A $0.25 Sonnet call with discipline instructions matches $2+ Opus calls with elaborate skill infrastructure. The entire skill/orchestrator ecosystem is solving the wrong problem.

#### Writing Plans: Plan Before Code

**Hypothesis:** Writing a detailed implementation plan before touching code produces better outcomes — the agent builds the right thing from the start instead of discovering requirements mid-implementation.

**Setup:** Claude Code Opus with the writing-plans skill forcibly invoked. The agent must invoke the skill immediately, create a detailed plan with bite-sized tasks, exact file paths, and test commands, then implement the plan step by step. Run across all 11 tasks.

| Task | Category | Plans | Claude Code | Delta |
| --- | --- | ---: | ---: | ---: |
| **T1** time-tracker | greenfield/simple | 98% (n=1) | 83.9% (n=6) | +14.1 |
| **T2** collab-server | greenfield/complex | 91% (n=1) | 64.9% (n=2) | +26.1 |
| **T3** fts-search | features/medium | 100% (n=1) | 99.3% (n=2) | +0.7 |
| **T4** phantom-invoice | bugfix/medium | 100% (n=1) | 100.0% (n=2) | 0.0 |
| **T5** task-queue | marathon | 89% (n=1) | 75.7% (n=4) | +13.3 |
| **T6** monorepo-disaster | recovery | 100% (n=1) | 100.0% (n=1) | 0.0 |
| **T7** plugin-marketplace | greenfield/complex | 99% (n=1) | 94.9% (n=1) | +4.1 |
| **T8** analytics-dashboard | greenfield/complex | 92% (n=1) | 87.9% (n=1) | +4.1 |
| **T9** ssg-toolkit | features/complex | 100% (n=1) | 99.4% (n=1) | +0.6 |
| **T10** ecommerce-backend | greenfield/complex | 96% (n=1) | 89.8% (n=1) | +6.2 |
| **T11** debug-nightmare | bugfix/hard | 100% (n=1) | 99.3% (n=3) | +0.7 |
| **Mean** | | **96.9%** | **89.6%** | **+7.3** |

**Findings:**

1. **Planning is a solid mid-tier gene (+7.3 points).** 96.9% mean with 100% pass rate — every task completes, five with perfect scores (T3, T4, T6, T9, T11). Effective but not as strong as TDD (+8.4) or Verify (+11.4).

2. **Biggest gains on complex greenfield and marathon.** T2 collab-server (+26.1) and T1 time-tracker (+14.1) benefit most from upfront architecture thinking. T5 marathon gains +13.3 — the plan helps the agent manage the 12-phase sequential build.

3. **Good cost profile.** $1.05/task mean — half of TDD's $2.32 and comparable to Verify's $0.94. Planning adds turns (17-54 per task) but fewer than TDD's red-green-refactor cycle. The plan creation is ~5-10 turns overhead.

4. **The plan is overhead on easy tasks.** T3, T4, T6, T9, T11 gain nothing — these tasks are already at or near 100% baseline. Writing a plan for a straightforward bugfix adds time without benefit.

5. **Weaker than Verify on T5 marathon.** Plans gets 89% vs Verify's 96% on the hardest sequential task. Planning upfront helps, but verifying your work at the end catches more issues. The plan can be wrong; verification is ground truth.

**The hierarchy of discipline genes:** TDD (98.0%) > Verify (97.3%) > Plans (96.9%) > Vanilla (89.6%). All three beat vanilla by a wide margin. TDD forces the most discipline (test every unit), Verify forces the cheapest discipline (check before claiming done), Plans falls in between (think before coding).

#### Consensus Design Review: Pre-Implementation Architecture Guidance

**Hypothesis:** If consensus *code review* after implementation helps (+11.3 points), then consensus *design review* before implementation should help even more — preventing bad architecture choices rather than catching them after the fact.

**Setup:** Before the agent writes any code, the adapter runs `conclave consensus --mode=general-prompt` on the task description. Claude, Gemini, and Codex independently analyze the task and recommend file structure, abstractions, data flow, edge cases, implementation order, and testing strategy. A chairman synthesizes their recommendations. The agent then receives the consensus architecture guidance prepended to its task prompt. No mandatory workflow — the agent codes freely with richer context.

Compared against vanilla Claude Code (Opus 4.6, same model) on 4 greenfield tasks.

| Task | Claude Code | Design Review | Delta |
| --- | ---: | ---: | ---: |
| **T1** time-tracker | 79.1% (n=6) | 97.7% (n=4) | +18.6 |
| **T5** task-queue | 73.3% (n=4) | 95.0% (n=3) | +21.7 |
| **T7** plugin-marketplace | 98.9% (n=1) | 98.3% (n=1) | -0.6 |
| **T8** analytics-dashboard | 87.7% (n=1) | 86.6% (n=1) | -1.1 |
| **Mean** | **79.5%** | **95.7%** | **+16.2** |

**Findings:**

1. **Design review is a large net positive (+16.2 points mean).** The effect is concentrated on high-variance tasks. T5 marathon gains +21.7 points and T1 gains +18.6 — architectural guidance helps the most on tasks where the baseline struggles.

2. **Minimal effect on tasks the model already handles well.** T7 and T8 show noise-level deltas (-0.6, -1.1). When the task is clear enough that a single model can architect it correctly, three models agreeing doesn't add much.

3. **Overhead is modest.** The consensus step adds ~80-100 seconds of wall time and ~$0.10-0.30 in hidden API costs (3 models + chairman).

4. **Design review vs code review:** Design review (+16.2) and code review (+11.3) both help, through different mechanisms. Design review prevents bad architecture upfront. Code review catches implementation bugs afterward. They're complementary — stacking both is the obvious next experiment.

**Caveat:** The Claude Code baseline has high variance on T1 (n=6) and T5 (n=4), which inflates the delta. The directional finding (+) is reliable but the exact magnitude needs matched trial counts.

#### Stacked Double Review: Decomposing Self-Review vs Consensus

**Hypothesis:** Stacking design review + code review should be additive. But how much of the improvement comes from self-review *discipline* (pausing to re-examine your work) vs actual multi-model *consensus* (three models finding things one model misses)?

**Setup:** Same adapter run twice — once with `env: {}` (no API keys, consensus fails, agent self-reviews), once with API keys (real consensus from Claude + Gemini + Codex). This cleanly separates the two effects.

| Task | Baseline | Self-Review Only | Real Consensus | Self-Review Δ | Consensus Δ |
| --- | ---: | ---: | ---: | ---: | ---: |
| **T1** time-tracker | 79.1% (n=6) | 96.7% (n=3) | 95.8% (n=3) | +17.6 | -0.9 |
| **T5** task-queue | 73.3% (n=4) | 94.4% (n=2) | 93.7% (n=2) | +21.1 | -0.7 |
| **T7** plugin-marketplace | 98.9% (n=1) | 98.7% (n=2) | 98.9% (n=2) | -0.2 | +0.2 |
| **T8** analytics-dashboard | 87.7% (n=1) | 90.2% (n=2) | 91.3% (n=2) | +2.5 | +1.1 |
| **Mean delta vs baseline** | — | **+15.7** | **+15.5** | — | **-0.2** |

**Findings:**

1. **Self-review discipline is the dominant gene (~+16 points, free).** Tell the agent "commit, review your diff, fix issues" and it scores dramatically higher. No API keys, no external tools, no extra cost beyond a few additional turns. The effect is concentrated on T1 (+17.6) and T5 (+21.1) where the vanilla baseline has high variance.

2. **Multi-model consensus adds nothing on top (-0.2).** Once the agent is already self-reviewing, adding three models to review as well provides no measurable improvement. The self-review discipline captures the full benefit.

3. **The effect is entirely from self-review.** Self-review (+15.7) and self-review+consensus (+15.5) are within noise of each other.

**Implications:**

1. **Self-review is the low-hanging fruit.** Adding "commit and self-review your diff before finishing" to any adapter's system prompt is the single largest free improvement found in this study.

2. **Consensus adds no value on top of self-review.** The cost ($0.20-0.40/task) is not justified.

**Caveat:** The Claude Code baseline has high variance on T1 (n=6) and T5 (n=4), which inflates the delta. The directional finding (self-review helps, consensus adds nothing extra) is reliable, but the exact magnitude needs matched trials. 2-3 trials per variant per task.

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
| Consensus review only | Conclave Review | Claude Code | Multi-agent code review (no skills) | **Done — +11.3 points** |
| Full skill pipeline | Full Conclave | Conclave Review | Brainstorm/plan/implement workflow | **Done — -2.0 points vs review-only (was -19 before data cleanup)** |
| Systematic debugging | Superpowers Debug | Claude Code | Four-phase debugging methodology | **Done — no effect (both ~99%)** |
| Test-driven development | Superpowers TDD | Claude Code | Forced red-green-refactor cycle | **Done — +11.5 points, highest score (97.4%)** |
| Verification before completion | Superpowers Verify | Claude Code | "No claims without fresh evidence" | **Done — +11.4 points at $0.94 (cheapest top-tier)** |
| Skill-guided code review | Superpowers Review | Claude Code | requesting-code-review skill + conclave consensus | **Done — +7.4 points, 97.0% (n=34)** |
| Writing plans | Superpowers Plans | Claude Code | Mandatory plan before implementation | **Done — +7.3 points at $1.05** |
| Brainstorming | Superpowers Brainstorm | Claude Code | Consensus design exploration (autopilot) | **Done — +7.8 points, #1 (97.4%, n=38)** |
| Gene stacking: Review + Verify | Review+Verify | Review / Verify | Two discipline checkpoints stacked | **Done — 97.2% (worse than either alone, diminishing returns)** |
| System prompt self-review | Self-Review | Claude Code | "Verify, commit, review diff, fix" — no plugins | **Done — 96.8% at $1.33 (n=40, within 0.6 of skills)** |
| Model ablation: Sonnet vs Opus | Self-Review (Sonnet) | Self-Review (Opus) | Cheap model + same system prompt | **Done — 97.1% Sonnet vs 96.8% Opus (model doesn't matter)** |
| Consensus design review | Conclave Design | Claude Code | Pre-implementation multi-model architecture guidance | **Done — +16.2 points** |
| Self-review discipline | Double Review (no keys) | Claude Code | "Commit, review your diff, fix" in system prompt | **Done — ~+16 points (free, largest gene)** |
| Self-review + consensus | Double Review (keys) | Claude Code | Self-review + real multi-model consensus | **Done — ~+15.5 points (consensus adds nothing over self-review)** |
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
| **Stacked** | Metacog + review + worktree | Three top genes combined: metacog reframing, consensus code review, git worktree |
| **Superpowers Review** | Claude Code + code review skill | Skill-guided multi-agent consensus code review — #1 |
| **Superpowers Brainstorm** | Claude Code + brainstorming skill | Consensus-driven design exploration in autopilot mode — #2 |
| **Review + Verify** | Claude Code + review + verify stacked | Gene stacking study — diminishing returns (97.2%, both genes combined) |
| **Self-Review (Opus)** | Claude Code Opus + system prompt only | No plugins, no skills — just "verify, commit, review diff, fix" in system prompt |
| **Self-Review (Sonnet)** | Claude Code Sonnet + system prompt only | Same system prompt, ~5x cheaper model — matches Opus (97.1% vs 96.8%) |
| **Superpowers Verify** | Claude Code + verification skill | "No completion claims without fresh evidence" — cheapest top-tier |
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
- [ ] Ablation studies (gene isolation) — 17 done: ts-dev (no effect), consensus review (+11.3), full pipeline (-2 vs review-only), systematic debugging (no effect), TDD (+8.4), verification (+11.4, cheapest top-tier), writing plans (+7.3), skill-guided review (+8.1, #1 at 97.7%), brainstorming (+7.9, #2 at 97.5%), review+verify stacking (diminishing returns, 97.2%), design review (+16.2), self-review (~+16, free), self-review+consensus (consensus adds nothing), worktree matches Gas Station, agent teams (hurts on T5), branch (inconclusive), Ralph fresh-context (+15.6 on T5, top-tier), no-git (unstable). All scores are mechanical (tests, build/lint, coverage, code metrics) — rubric dropped. Early adapter-debugging trials pruned per-orchestrator.
- [ ] Publish methodology paper

## License

TBD
