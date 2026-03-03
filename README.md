# Agentic Thunderdome

Two agents enter, one agent leaves.

A benchmarking framework that pits agentic coding orchestrators against standardized programming tasks and measures what matters: completion rate, token efficiency, cost, and correctness.

## Results

Composite scores across 19 tasks — the original 11-task standard suite (T1-T11) plus 8 hard benchmarks (T12-T19) spanning algorithmic, correctness, ambiguity, and reasoning challenges. Data includes 774 scored trials across 38 primary orchestrator variants. All scoring is deterministic — no LLM judges, no rubric. Early adapter-debugging trials have been pruned — each orchestrator's data starts from its first stable full-suite run.

### Leaderboard

Composite scores ranked by Overall (weighted average of Standard and Hard suite means). Orchestrators tested only on T1-T11 are listed below the ranked entries. Gene ablation variants (testing individual features in isolation) are in a [separate table](#gene-ablation-variants). See [Contenders](#contenders) for architecture descriptions.

| Rank | Orchestrator | Standard | Hard | Overall | Trials | Avg Cost | Model |
|---:|---|---:|---:|---:|---:|---:|---|
| 1 | [**Conclave v6 (Opus)**](#contenders) | 98.0% | 87.8% | **93.7%** | 38 | $2.02 | Opus 4.6 |
| 2 | [Conclave v6 (Sonnet)](#contenders) | 98.1% | 87.0% | **93.4%** | 38 | $0.98 | Sonnet 4.6 |
| 3 | [Self-Review (Opus)](#contenders) | 96.8% | 88.1% | **93.1%** | 39 | $1.31 | Opus 4.6 |
| 4 | [Metacog](#contenders) | 95.3% | 82.5% | **89.9%** | 28 | $1.45 | Opus 4.6 |
| 5 | [Self-Review (Sonnet)](#contenders) | 89.3% | 89.9% | **89.6%** | 38 | $0.80 | Sonnet 4.6 |
| 6 | [BMAD-METHOD](#contenders) | 86.0% | 87.8% | **86.7%** | 28 | $1.65 | Opus 4.6 |
| 7 | [Superpowers](#contenders) | 86.4% | 86.0% | **86.2%** | 29 | $1.31 | Opus 4.6 |
| 8 | [GSD](#contenders) | 82.5% | 83.7% | **83.0%** | 28 | $1.04 | Opus 4.6 |
| 9 | [Gemini CLI](#contenders) | 83.6% | 80.3% | **82.2%** | 32 | $0.10 | Gemini 3 Flash |
| 10 | [Gas Station](#contenders) | 86.6% | 74.9% | **81.7%** | 30 | $1.00 | Opus 4.6 |
| 11 | [Claude Code](#contenders) | 84.8% | 76.7% | **81.4%** | 51 | $0.77 | Opus 4.6 |
| 12 | [Gas Town](#contenders) | 69.2% | 88.2% | **77.2%** | 63 | $1.99 | Opus 4.6 |
| — | [Amplifier (Opus)](#contenders) | 86.0% | — | — | 12 | $0.07 | Opus 4.6 |
| — | [Amplifier (Gemini)](#contenders) | 85.6% | 39.6% | — | 20 | $0.03 | Gemini 3 Flash |
| — | [Agent Teams](#contenders) | 85.2% | — | — | 29 | $0.47 | Opus 4.6 |

### Cost Efficiency

All orchestrators with Overall scores, sorted by cost. **Bold** = Pareto-optimal (no other orchestrator scores higher at equal or lower cost).

| Orchestrator | Overall | Avg Cost | Pareto |
|---|---:|---:|:---:|
| **Gemini CLI** | **82.2%** | **$0.10** | **best <$0.77** |
| **Claude Code** | **81.4%** | **$0.77** | |
| **Self-Review (Sonnet)** | **89.6%** | **$0.80** | **best <$0.98** |
| TDD Sonnet | 83.3% | $0.85 | |
| **Conclave v6 (Sonnet)** | **93.4%** | **$0.98** | **best <$1.58** |
| Gas Station | 81.7% | $1.00 | |
| GSD | 83.0% | $1.04 | |
| Superpowers | 86.2% | $1.31 | |
| Self-Review (Opus) | 93.1% | $1.31 | |
| Stacked | 93.3% | $1.43 | |
| Metacog | 89.9% | $1.45 | |
| **Conclave Brainstorm** | **93.8%** | **$1.58** | **best <$2.76** |
| BMAD-METHOD | 86.7% | $1.65 | |
| Gas Town | 77.2% | $1.99 | |
| Conclave v6 (Opus) | 93.7% | $2.02 | |
| **TDD Opus** | **94.2%** | **$2.76** | **best overall** |

The biggest value jump is from Gemini CLI ($0.10, 82.2%) to SR Sonnet ($0.80, 89.6%) — **+7.4 points for $0.70 more**. From there to v6 Sonnet ($0.98, 93.4%) adds +3.8 points for $0.18 more. After that, diminishing returns: the next 0.8 points (to TDD Opus 94.2%) costs $1.78 more. Gemini CLI at $0.10 is the cheapest orchestrator and scores 82.2% — beating vanilla Claude Code ($0.77) at a fraction of the cost. Claude Code loses its Pareto-optimal status: Gemini CLI scores higher at lower cost.

### Gene Ablation Variants

Individual orchestrator "genes" tested in isolation — Claude Code with a single feature forced on. All discipline genes cluster within 0.6 points (96.7-97.4%) on Standard and beat vanilla by 11+ points. Variants tested on T12-T19 are ranked by Overall; standard-only variants listed below. See [Ablation Studies](#ablation-studies) for detailed per-gene analysis.

| Rank | Variant | Standard | Hard | Overall | Trials | Avg Cost | Model |
|---:|---|---:|---:|---:|---:|---:|---|
| 1 | **Superpowers TDD** | 97.4% | 89.7% | **94.2%** | 32 | $2.76 | Opus 4.6 |
| 2 | Conclave Brainstorm | 97.4% | 88.8% | **93.8%** | 54 | $1.58 | Opus 4.6 |
| 3 | Stacked | 97.3% | 87.9% | **93.3%** | 27 | $1.43 | Opus 4.6 |
| 4 | Superpowers TDD | 98.2% | 62.9% | **83.3%** | 38 | $0.85 | Sonnet 4.6 |
| — | Superpowers Verify | 97.3% | — | — | 11 | $0.94 | Opus 4.6 |
| — | Conclave Review + Verify | 97.2% | — | — | 11 | $2.28 | Opus 4.6 |
| — | Conclave Review | 97.2% | — | — | 11 | $1.82 | Opus 4.6 |
| — | Superpowers Brainstorm | 97.1% | — | — | 22 | $1.12 | Opus 4.6 |
| — | Conclave Skill Review | 97.0% | — | — | 34 | $2.01 | Opus 4.6 |
| — | Superpowers Review | 97.0% | — | — | 22 | $1.83 | Opus 4.6 |
| — | Conclave Review + Keys | 96.9% | — | — | 22 | $1.71 | Multi-provider |
| — | Superpowers Plans | 96.9% | — | — | 11 | $1.05 | Opus 4.6 |
| — | Superpowers Debug | 96.7% | — | — | 22 | $1.14 | Opus 4.6 |
| — | Conclave Design | 95.7% | — | — | 9 | $2.09 | Multi-provider |
| — | Conclave Brainstorm + Keys | 95.7% | — | — | 22 | $1.43 | Multi-provider |
| — | Conclave (Full) | 95.2% | — | — | 12 | $0.14 | Multi-provider |
| — | Conclave Double Review | 95.2% | — | — | 9 | $1.26 | Opus 4.6 |
| — | Conclave Dbl Review + Keys | 95.0% | — | — | 9 | $1.89 | Multi-provider |
| — | Conclave Brainstorm (Sonnet) | 94.7% | — | — | 22 | $0.74 | Sonnet 4.6 |
| — | Ralph Fresh | 94.7% | — | — | 4 | $1.57 | Opus 4.6 |
| — | Claude Code Worktree | 94.7% | — | — | 3 | $1.20 | Opus 4.6 |
| — | Verify (Sonnet) | 94.3% | — | — | 22 | $0.74 | Sonnet 4.6 |
| — | Claude Code Headless | 94.2% | — | — | 9 | $1.15 | Opus 4.6 |
| — | Amplifier + ts-dev | 86.8% | — | — | 12 | $0.74 | Opus 4.6 |

### Hard Benchmarks (T12-T19)

Per-task breakdown for the 8 harder benchmarks — algorithmic complexity (T12-T13, T16), correctness constraints (T14), ambiguous requirements (T15), and deep reasoning where naive approaches fail at scale (T17-T19). Aggregate rankings are in the [leaderboard](#leaderboard) above.

16 orchestrators (n=2 per task unless noted, 239 total trials), sorted by hard-suite mean:

| Task | Category | SR Sonnet | TDD Opus | Brstm Opus | Gas Town | SR Opus | Stacked | BMAD | v6 Opus | v6 Sonnet | Superpowers | GSD | Metacog | Gemini | Vanilla | Gas Stn | TDD Sonnet |
|------|----------|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| **T12** constraint-scheduler | algo/hard | 90.4% | 91.8% | **93.4%** | 90.5% | 81.0% | 91.3% | 83.8% | 76.5%† | 87.8% | 73.7% | 92.6% | 75.9% | 89.2% | 60.0% | 74.4% | 81.3% |
| **T13** structural-merge | algo/hard | 91.0% | 89.0% | **93.3%** | 85.5% | 90.1% | 90.2% | 90.0% | 93.0% | 89.9% | 91.2% | 91.6% | 75.0% | 54.6% | 59.0% | 58.5% | 88.2% |
| **T14** financial-ledger | correct/hard | 100% | 100% | 100% | 100% | 100% | 100% | 100% | 100% | 100% | 100% | 100% | 100% | 100% | 100% | 100% | 100% |
| **T15** permission-maze | ambig/hard | 70.8% | 75.3% | 65.2% | **77.7%** | 67.0%‡ | 61.2% | 73.6% | 66.8% | 70.7% | 76.6% | 76.7% | 67.8%‡ | 60.9% | 69.6% | 62.9% | 64.3% |
| **T16** reactive-spreadsheet | algo/hard | 93.0% | 91.9% | **93.2%** | 92.3% | 90.2% | 88.0% | 91.2% | 91.9% | 91.2% | 90.9% | 89.5% | 88.9% | 88.7%§ | 91.1% | 87.8% | 88.7% |
| **T17** circuit-debugger | reason/hard | 86.0% | 86.9% | 85.3% | 84.5% | 86.6% | 87.3% | 83.7% | 90.3% | 73.3% | 89.7% | 70.3% | 84.8% | **93.6%**§ | 88.9% | 88.1% | 40.4%\* |
| **T18** beam-splitter | reason/hard | 95.1% | 90.2% | 93.2% | 90.0% | 93.9% | 93.2% | 91.9% | 94.3% | 94.0% | 77.0% | 75.3% | 75.2% | **96.5%**§ | 69.2% | 59.0% | 20.0%\* |
| **T19** factory-reset | reason/hard | 93.1% | 92.3% | 87.0% | 85.4% | 91.0% | 91.7% | 88.2% | 89.5% | 88.9% | 89.2% | 73.7% | **92.8%** | 58.5%§ | 78.6% | 68.2% | 20.0%\* |
| **Mean** | | **89.9%** | 89.7% | 88.8% | 88.2% | 88.1% | 87.9% | 87.8% | 87.8% | 87.0% | 86.0% | 83.7% | 82.5% | 80.3% | 77.0% | 74.9% | 62.9% |
| **Avg Cost** | | $0.77 | $3.19 | $1.94 | $2.55 | $1.43 | $1.48 | $2.01 | $1.78 | $0.80 | $1.49 | $1.09 | $1.57 | $0.09 | $1.33 | $1.06 | $0.53 |

\*TDD Sonnet crashed on 5 of 6 reasoning/hard trials ($0.00 cost, <3s duration). The non-crashing T17 trial scored 60.8%.
†v6 Opus T12 trial 1 had a validation container hang (hidden_tests=0); trial 2 scored 94.7%.
‡Self-Review and Metacog T15 trial 2 affected by OAuth expiry during the run.
§Gemini CLI T16-T19 are n=1 (rate-limit crashes on trial 2). T12-T15 are n=2.

**Key findings from the hard suite:**

1. **SR Sonnet leads hard tasks by a hair; top 3 within 1.1 points.** Self-Review Sonnet (89.9%), TDD Opus (89.7%), and Brainstorm Opus (88.8%) form a tight top tier — all within noise of each other. The surprise: Sonnet with just a system prompt ("verify, review your diff, fix") beats every Opus orchestrator except TDD on hard tasks, at a fraction of the cost ($0.77 vs $3.19/hard trial). TDD Sonnet collapses to 62.9% — the TDD cycle amplifies Opus's reasoning but exposes Sonnet's limits.

2. **n=2 data deflated BMAD by 2.7 points.** BMAD's hard mean dropped from 90.5% (n=1) to 87.8% (n=2) — the single biggest correction from adding trials. T12 constraint-scheduler swung from 95.8% to 71.8% between trials, and T15 permission-maze from 84.9% to 62.3%. The adversarial self-review workflow is good but not the outlier it appeared to be. This is exactly why n=2 matters.

3. **Hard tasks finally differentiate orchestrators.** The T1-T11 spread among top-tier Opus variants is 0.6 points (96.8-97.4%). On T12-T19 the spread is 27 points (62.9-89.9%). These benchmarks test what easy benchmarks can't: whether the agent can discover novel algorithmic approaches rather than implement well-known patterns.

4. **The top 9 cluster within 3 points — below that, it falls off fast.** SR Sonnet (89.9%) through v6 Sonnet (87.0%) span 2.9 points. Then Superpowers (86.0%), GSD (83.7%), Metacog (82.5%), and Gemini CLI (80.3%) form a mid-tier, vanilla drops to 77.0%, Gas Station to 74.9%, TDD Sonnet to 62.9%.

5. **Gemini CLI climbs to 80.3% with n=2 data — T13 was the biggest correction.** T13 structural-merge swung from 20.0% to 89.2% between trials — the largest single-trial swing in the hard suite. With n=2 averaging, Gemini's hard mean jumps from 76.1% to 80.3%, pushing it past Claude Code and Gas Station to #9 overall (82.2%). It still holds the highest scores on T17 circuit-debugger (93.6%) and T18 beam-splitter (96.5%), but rate-limit crashes prevented T16-T19 trial 2 (n=1 only). At $0.09/hard trial, it beats Claude Code ($0.77) at a fraction of the cost.

6. **Metacog (82.5%) has the highest variance.** T18 beam-splitter: one trial 58%, the other 92%. T19 factory-reset: 95% and 90%. The metacognitive reframing occasionally produces breakthrough insights but inconsistently. Metacog does hold the highest T19 score (92.8%) among Claude-based orchestrators.

7. **Permission maze (T15) is the hardest non-crashing task.** Scores range 61-78% across 16 orchestrators — the deliberately ambiguous TASK.md exposes agents that make assumptions rather than exploring edge cases. Gas Town takes the lead (77.7%), followed by GSD (76.7%) and Superpowers (76.6%).

8. **Third-party tools: BMAD outperforms GSD on hard tasks.** BMAD (87.8%) and GSD (83.7%) represent different approaches — BMAD's structured adversarial workflow vs GSD's wave-based parallel execution. GSD is strong on algorithmic tasks (T12: 92.6%, T13: 91.6%) but shows high variance on reasoning tasks (T18: 92.6%/58.1%, T19: 89.0%/58.5% between trials). n=2 data confirmed GSD's mid-tier placement.

9. **Gas Station n=2 exposed massive T12 variance.** Gas Station's T12 dropped from 92.4% to 56.4% between trials — the biggest single-trial swing in the dataset. T17 went the other direction (82.2%→94.1%). Overall hard mean dropped from 75.7% to 74.9%, confirming Gas Station as the weakest full-suite Opus orchestrator on hard tasks.

### Key Findings

- **SR Sonnet edges TDD Opus on hard tasks (89.9% vs 89.7%) at a fraction of the cost ($0.77 vs $3.19/trial).** BMAD dropped from 90.5% (n=1) to 87.8% (n=2) — the biggest correction from adding trials. The top 3 hard-task performers (SR Sonnet, TDD Opus, Brainstorm Opus) cluster within 1.1 points. TDD Sonnet scores 62.9% — **TDD's value is model-dependent**
- **Conclave v6 ties for #1 on easy tasks and matches top tier on hard ones.** The redesigned Conclave plugin (98.1% T1-T11, n=22) matches TDD Sonnet on standard tasks. On hard benchmarks (T12-T19), v6 Opus scores 87.8% and v6 Sonnet 87.0% — both in the top 8 cluster. v6 Sonnet's 87.0% is especially notable vs TDD Sonnet's 62.9%: flexible task routing helps where rigid TDD hurts
- **The methodology matters more than the model — on standard tasks.** Four approaches tested with both Opus and Sonnet on T1-T11: TDD (Sonnet +0.8pp), Brainstorm (Sonnet -0.9pp), Verify (Sonnet -3.0pp), Self-Review (Sonnet -7.5pp). The more structured the methodology, the smaller the Opus-Sonnet gap. But T12-T19 hard benchmarks reveal this is incomplete: TDD Opus (89.7%) dominates TDD Sonnet (62.9%) when problems require novel algorithmic approaches
- **Multi-agent consensus adds nothing — even with real multi-provider keys.** Three-way test: pure superpowers (no binary), conclave (Claude-only consensus), conclave + keys (Claude + Gemini + Codex). Pure wins: Brainstorm 97.1% > +keys 95.7% > no-keys 95.6%. Adding the consensus binary and multi-provider API keys actually hurts slightly — the structured skill text drives all the value
- **A system prompt is (almost) all you need — on hard tasks.** Self-Review Sonnet leads the hard suite (89.9%) with no plugins, skills, or consensus — just "verify, commit, review your diff, fix." But its standard-suite score (89.3%) is significantly weaker, dragging its Overall to 89.6% (#6). Structured methodologies still matter for standard tasks
- **The real gap is vanilla vs any discipline.** Claude Code without any review instruction scores 84.8% standard. Adding "verify and review your diff" to the system prompt jumps to 97% — a 12 point improvement for free. All the skill infrastructure, consensus protocols, and multi-agent reviews fight over the last 1.2 points
- **Hard benchmarks (T12-T19) break the T1-T11 consensus.** On easy tasks, all discipline genes cluster within 0.6 points. On hard tasks, the spread explodes to 27 points across 16 orchestrators. The top 9 (SR Sonnet 89.9% through v6 Sonnet 87.0%) cluster within 2.9 points; then GSD (83.7%), Metacog (82.5%), vanilla (77.0%), Gemini CLI (76.1%), Gas Station (74.9%), and TDD Sonnet (62.9%) fall off. The T1-T11 leaderboard was measuring methodology compliance, not problem-solving capability
- **Multi-trial data compresses the spread.** With n=22-40 trials per orchestrator, the Opus top tier clusters within 0.6 points (96.8%-97.4%) on T1-T11. The n=1 rankings were noise — what looked like meaningful differences between skill-based approaches was just variance
- **Superpowers Verify** is the best cost-adjusted Opus skill — 97.3% at $0.94/task (n=11, needs more trials to confirm)
- **Conclave Skill Review regressed the most** — from 97.7% (n=1) to 97.0% (n=34). The original score was an outlier. Still effective but not the clear #1 it appeared to be
- **Gene stacking has diminishing returns** — Review + Verify (97.2%) scores at the same level as either alone. Two discipline checkpoints don't compound. The ceiling appears to be ~97-98% with current single-session approaches
- **Gas Town collapsed on standard tasks (69.2%, n=2).** The Mayor→Polecats→Refinery pipeline scores 30% on T3 and T4 in both trials — the single-polecat strategy completes with minimal work. T5 showed high variance (32.7%→63.0%), but the n=2 mean barely changed (68.2%→69.2%). Gas Town is strong on hard tasks (88.2%, #4) but its standard-task weakness drops it to last place overall (77.2%)
- **Gemini CLI climbs to #9 (82.2% overall).** n=2 hard data corrected T13 from 20.0% to 54.6% (biggest single-trial swing), pushing the hard mean from 76.1% to 80.3%. Gemini CLI now beats Claude Code and Gas Station. At $0.10/task it's the cheapest orchestrator by 8x, with best-in-class scores on T17 (93.6%) and T18 (96.5%). Rate-limit crashes prevented T16-T19 trial 2
- **T4** (bugfix) is the great equalizer — most contenders score 100%, the task is too easy
- **T8** (analytics dashboard) is the hardest task in the standard suite — most contenders cluster around 87-90%. In the hard suite, T15 (permission maze, 61-85%) and the reasoning tasks (T17-T19) are significantly harder
- **Third-party tools show promise on hard tasks.** [BMAD-METHOD](https://github.com/bmad-code-org/BMAD-METHOD) (87.8% hard, 86.0% standard) and [GSD](https://github.com/gsd-build/get-shit-done) (83.7% hard, 82.5% standard) both perform better on hard tasks relative to their standard-suite ranking. Both show significant inter-trial variance: BMAD T12 swung 95.8%→71.8%, GSD T18 swung 92.6%→58.1%. Gas Station (74.9% hard) had the dataset's biggest single-task swing: T12 at 92.4% vs 56.4%

### The Gas Station Story

Gas Town is a multi-agent pipeline: a Mayor decomposes the task, parallel Polecats implement pieces in git worktrees, and a Refinery merges their work and fixes conflicts. We asked Claude Code to build the adapter.

What it delivered was a fraud — a single `claude -p` call with `gt prime` context injected, wearing Gas Town's scaffolding like a trench coat. It set up the town, created beads, initialized a polecat worktree, the whole ceremony — then ran one agent that did all the work by itself. A single agent pretending to be a workforce.

I named the impostor "Gas Station" and kept it as a control while we built the real multi-agent pipeline ourselves.

Then the benchmarks came back. Gas Station scored 86.6% standard (n=11). The single agent in a trench coat was respectably consistent. And the real multi-agent pipeline? Gas Town scores 88.2% on hard tasks (#4 overall) but cratered to 69.2% on standard tasks (n=22) — the Mayor dispatches simple tasks to a single polecat that sometimes completes with minimal work (30% on T3 and T4, both trials). The fraud outperforms the real thing on standard tasks by 17 points. On hard tasks, the multi-agent decomposition finally justifies itself. Gas Station earned its place: a permanent reminder that complexity must earn its keep on every task type, not just the hard ones.

### Ablation Studies

We're isolating individual orchestrator "genes" — composable features like multi-agent consensus, skill injection, parallel execution — to measure which actually help. Each ablation holds everything constant except one gene.

#### TypeScript Expertise: Amplifier + ts-dev Bundle

**Hypothesis:** Giving the agent TypeScript-specific tools (LSP code intelligence, code quality analysis, a specialized TS expert agent) improves performance on TypeScript benchmarks.

**Setup:** Amplifier with Opus 4.6, comparing bare foundation bundle vs foundation + [ts-dev](https://github.com/microsoft/amplifier-bundle-ts-dev) app bundle. Same model, same provider, same tasks. After pruning adapter-debugging trials, both variants have n=1 per task (n=2 for T1 bare, T8 ts-dev).

| Task | Amplifier (Opus) | Amplifier + ts-dev | Delta |
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
| **T11** debug-nightmare | 100.0% (n=1) | 100.0% (n=1) | 0.0 |
| **Mean** | **86.0%** | **86.8%** | **+0.8** |

**Finding: ts-dev has no meaningful effect (+0.8 points).** With adapter noise removed, the two variants are essentially tied. The huge swings on individual tasks (T7: +77.6, T1: -33.0) with n=1 are just variance, not signal. This ablation needs more trials to draw any conclusion.

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

**Hypothesis:** A structured four-phase debugging methodology (root cause investigation → pattern analysis → hypothesis testing → implementation) improves defect resolution across all task types, not just debugging tasks.

**Setup:** Claude Code Opus with the systematic-debugging skill forcibly invoked. The skill mandates a four-phase process for each bug: (1) root cause investigation — read errors, reproduce, trace data flow; (2) pattern analysis — find working examples, compare; (3) hypothesis testing — form hypothesis, test minimally; (4) implementation — create fix, verify. One bug at a time, no batching. Run across all 11 tasks with 2 trials (22 total).

| Task | Category | Debug | Claude Code | Delta |
| --- | --- | ---: | ---: | ---: |
| **T1** time-tracker | greenfield/simple | 96.8% | 83.9% | +12.9 |
| **T2** collab-server | greenfield/complex | 89.4% | 64.9% | +24.5 |
| **T3** fts-search | features/medium | 100% | 99.3% | +0.7 |
| **T4** phantom-invoice | bugfix/medium | 100% | 100% | 0.0 |
| **T5** task-queue | marathon | 92.6% | 75.7% | +16.9 |
| **T6** monorepo-disaster | recovery | 100% | 100% | 0.0 |
| **T7** plugin-marketplace | greenfield/complex | 98.3% | 94.9% | +3.4 |
| **T8** analytics-dashboard | greenfield/complex | 89.9% | 87.9% | +2.0 |
| **T9** ssg-toolkit | features/complex | 100% | 99.4% | +0.6 |
| **T10** ecommerce-backend | greenfield/complex | 96.2% | 89.8% | +6.4 |
| **T11** debug-nightmare | bugfix/hard | 100% | 99.3% | +0.7 |
| **Mean** | | **96.7%** | **89.6%** | **+7.1** |

**Findings:**

1. **The original T11-only study was misleading.** The previous analysis (n=6 on T11 only) concluded "no measurable effect" because both variants scored ~99% on the debugging task. Across all 11 tasks, the debugging skill adds +7.1 points over vanilla — a solid mid-tier discipline gene.

2. **The debugging methodology works as general discipline.** The four-phase process (investigate → analyze → hypothesize → implement) isn't just for bugs — it imposes structure on greenfield (T2: +24.5) and marathon (T5: +16.9) tasks too. The "one fix at a time, verify after each" cadence prevents the agent from rushing.

3. **Weaker than TDD but comparable to Self-Review.** Debug (96.7%) vs TDD (97.4%) vs Self-Review (96.8%). The debugging skill provides similar discipline to self-review but through a different mechanism — investigation phases vs commit-and-review cycles.

4. **T8 and T2 remain the hardest.** Analytics dashboard (89.9%) and collab-server (89.4%) are the lowest scores — consistent with every other discipline gene. The debugging methodology's "one bug at a time" process may hurt on complex greenfield tasks where the challenge is architecture, not defect isolation.

5. **Cost-effective.** $1.14/task — cheaper than TDD ($2.32), Brainstorm ($1.43), and Review ($2.01). Comparable to Self-Review ($1.33) and Plans ($1.05).

**Revised conclusion:** Systematic debugging is a legitimate discipline gene, not "no effect" as previously reported. The T11-only study was a methodological error — testing a debugging skill only on debugging tasks proved nothing because the model already debugs well. The skill's value is as general-purpose implementation discipline, not debugging-specific guidance.

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

**The revised pattern:** Forced TDD works — not because the model doesn't know how to test, but because the mandatory discipline prevents cutting corners under token pressure. The model naturally wants to implement first and test later (or not at all). Forcing test-first produces more thorough implementations.

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

4. **Contrasts with systematic debugging (96.7%).** Debugging methodology tells the agent *how to think* — phases, checklists. Verification tells the agent *what to do* — run the command, read the output. Both work as general discipline (+7.1 and +11.4 respectively), but concrete actions edge out process guidance.

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

#### Conclave Binary Effect: Pure Superpowers vs Conclave Consensus

**Hypothesis:** The brainstorming and code review skills perform better when backed by the conclave consensus binary (multi-agent consensus via `conclave consensus`) than when the agent works through the same skill process alone. And multi-provider consensus (Claude + Gemini + Codex) outperforms Claude-only consensus.

**Setup:** Three-way comparison for both brainstorm and code review skills, each using identical skill text from obra/superpowers:

- **Pure Superpowers** — `thunderdome/superpowers:latest` image, NO conclave binary. Agent works through the skill process autonomously (brainstorm) or via Task tool subagent (review).
- **Conclave, no keys** — `thunderdome/conclave:latest` with `conclave` binary but no Gemini/OpenAI API keys. Consensus calls fall back to Claude-only.
- **Conclave + keys** — `thunderdome/conclave:latest` with `conclave` binary AND full API keys (Anthropic + OpenAI + Gemini). True multi-provider consensus.

Each variant run across all 11 tasks with 2 trials (22 trials per variant, 88 total new trials for the pure and +keys variants).

| Variant | Brainstorm | Review |
| --- | ---: | ---: |
| **Pure Superpowers** (no binary) | **97.1%** (n=22, $1.12/task) | **97.0%** (n=22, $1.83/task) |
| **Conclave + keys** (multi-provider) | 95.7% (n=22, $1.43/task) | 96.9% (n=22, $1.71/task) |
| **Conclave, no keys** (Claude-only) | 95.6% (n=40, $1.35/task) | 96.0% (n=35, $2.04/task) |

Per-task breakdown (Brainstorm):

| Task | Pure | + Keys | No Keys |
| --- | ---: | ---: | ---: |
| **T1** time-tracker | 96.7% | 84.0% | 92.9% |
| **T2** collab-server | 91.0% | 92.2% | 86.5% |
| **T3** fts-search | 100% | 100% | 100% |
| **T4** phantom-invoice | 100% | 100% | 100% |
| **T5** task-queue | 95.0% | 92.7% | 94.8% |
| **T6** monorepo-disaster | 100% | 100% | 100% |
| **T7** plugin-marketplace | 99.0% | 98.4% | 99.1% |
| **T8** analytics-dashboard | 89.5% | 87.8% | 88.5% |
| **T9** ssg-toolkit | 100% | 100% | 100% |
| **T10** ecommerce-backend | 96.8% | 97.2% | 98.3% |
| **T11** debug-nightmare | 100% | 100% | 100% |

**Findings:**

1. **Multi-agent consensus adds nothing — and may introduce instability.** The pure superpowers variant (no binary, no consensus) matches or exceeds both conclave variants. Brainstorm + keys scored 1.4 points LOWER than pure, driven by a T1 outlier (0.692 on time-tracker trial-1 — the worst score in the entire brainstorm dataset). Multi-provider consensus introduces external model variability that can hurt.

2. **Multi-provider consensus (Claude + Gemini + Codex) doesn't beat Claude-only consensus.** With keys: 95.7% brainstorm, 96.9% review. Without keys: 95.6% brainstorm, 96.0% review. Adding Gemini and Codex to the consensus panel doesn't systematically improve quality — the external models add cost and latency without benefit.

3. **The skill TEXT is the value driver, not the consensus mechanism.** The brainstorming skill's structured design process (architecture, components, data flow, error handling, testing strategy) forces the agent to think before coding. Whether design questions are answered by multi-model consensus, single-model consensus, or the agent's own reasoning makes no measurable difference.

4. **Pure superpowers is the cheapest and best.** $1.12/task for brainstorm (vs $1.43 with keys), $1.83/task for review (vs $1.71 — keys was cheaper here due to fewer review iterations, but lower score). No external API dependencies, no conclave binary, no consensus overhead.

**Bottom line:** Multi-agent consensus for design and review decisions is pure overhead. A single agent working through the same structured skill process achieves the best results at the lowest cost. The conclave binary and multi-provider API keys are unnecessary.

#### Model Ablation: Sonnet 4.6 vs Opus 4.6 Across Top Approaches

**Hypothesis:** The ~97% top-tier scores require Opus 4.6 ($15/MTok input, $75/MTok output). Sonnet 4.6 (~5x cheaper) can't match it even with the same system prompts.

**Setup:** Four top-performing approaches — TDD (Superpowers), Brainstorm (Conclave), Verify (Superpowers), and Self-Review (system prompt only) — each run with identical Docker images, system prompts, and flags, but with `--model claude-sonnet-4-6` instead of `claude-opus-4-6`. Each Sonnet variant run across all 11 tasks with 2 trials (22 trials per approach, 88 total new trials). Note: Brainstorm Sonnet uses the conclave binary (Claude-only consensus, no API keys); the binary was later shown to have no effect (see Conclave Binary Effect ablation).

| Approach | Opus 4.6 | Sonnet 4.6 | Delta | Cost (Opus → Sonnet) |
| --- | ---: | ---: | ---: | ---: |
| **TDD** | 97.4% (n=16) | **98.2%** (n=22) | **+0.8** | $2.32 → $1.08 (53% cheaper) |
| **Brainstorm** | 97.4% (n=38) | 94.7% (n=22) | -2.7 | $1.43 → $0.74 (48% cheaper) |
| **Verify** | 97.3% (n=11) | 94.3% (n=22) | -3.0 | $0.94 → $0.74 (21% cheaper) |
| **Self-Review** | 96.8% (n=40) | 97.1% (n=22) | +0.3 | $1.33 → $1.13 (15% cheaper) |

Per-task breakdown for **TDD (Sonnet)** — the new #1:

| Task | Category | TDD Sonnet | TDD Opus | Delta |
| --- | --- | ---: | ---: | ---: |
| **T1** time-tracker | greenfield/simple | 98.1% | 96.2% | +1.9 |
| **T2** collab-server | greenfield/complex | 94.2% | 94.1% | +0.1 |
| **T3** fts-search | features/medium | 100% | 100% | 0.0 |
| **T4** phantom-invoice | bugfix/medium | 100% | 100% | 0.0 |
| **T5** task-queue | marathon | 96.2% | 95.8% | +0.4 |
| **T6** monorepo-disaster | recovery | 100% | 100% | 0.0 |
| **T7** plugin-marketplace | greenfield/complex | 98.2% | 98.8% | -0.6 |
| **T8** analytics-dashboard | greenfield/complex | 96.1% | 95.2% | +0.9 |
| **T9** ssg-toolkit | features/complex | 100% | 100% | 0.0 |
| **T10** ecommerce-backend | greenfield/complex | 97.9% | 97.1% | +0.8 |
| **T11** debug-nightmare | bugfix/hard | 100% | 100% | 0.0 |
| **Mean** | | **98.2%** | **97.4%** | **+0.8** |

**Findings:**

1. **TDD is the great equalizer.** Sonnet + TDD (98.2%) beats every orchestrator in the benchmark including Opus + TDD (97.4%). The rigid Red-Green-Refactor cycle provides enough scaffolding that the cheaper model actually produces better results. The methodology matters more than the model.

2. **Structure determines the Opus-Sonnet gap.** The more structured the approach, the smaller the gap: TDD (+0.8pp for Sonnet) > Self-Review (+0.3pp) > Brainstorm (-2.7pp) > Verify (-3.0pp). TDD's step-by-step cycle eliminates the need for Opus-level reasoning; open-ended approaches like Verify leave more room for model capability to show.

3. **Sonnet + TDD is the Pareto-optimal configuration.** 98.2% at $1.08/task — highest score AND lower cost than most Opus variants. The next-best configurations (Opus Brainstorm at 97.4%/$1.43, Opus TDD at 97.4%/$2.32) are both worse and more expensive.

4. **The cost story is uniformly positive.** Every Sonnet variant is cheaper than its Opus counterpart (15-53% savings). Even the weaker Sonnet variants (Brainstorm 94.7%, Verify 94.3%) are competitive with mid-tier Opus orchestrators at a fraction of the cost.

**Implication:** The optimal agentic coding configuration is not "better model + better prompt" — it's "structured methodology + cheaper model." Sonnet 4.6 + TDD discipline beats Opus 4.6 + anything. Investment should go into methodology (test-driven workflows, structured cycles) rather than model upgrades or multi-agent infrastructure.

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

#### Conclave v6: Task Classifier + Completion Gate + Consensus Opt-In

**Hypothesis:** The previous Conclave experiments tested individual genes in isolation (brainstorming, review, TDD, etc.) via forced skill invocation. A well-designed plugin should combine these genes intelligently — routing tasks to the right methodology based on task type, enforcing a completion gate across all skills, and making multi-agent consensus opt-in rather than mandatory.

**Setup:** Conclave v6 redesigns the plugin architecture around three changes:
1. **Task classifier** — the `using-conclave` meta-skill auto-routes: build new → brainstorming → TDD; fix bug → TDD; modify behavior → TDD; execute plan → executing-plans. The agent picks the first matching row rather than deliberating.
2. **Completion gate** — every skill includes a standardized exit gate: run full verification suite, read output, fix failures, commit, review diff, fix issues. Baked into all skills.
3. **Consensus opt-in** — all skills that previously called `conclave consensus` by default now use single-agent execution. Consensus is available but not the default path.

Run with both Sonnet 4.6 and Opus 4.6 across all 11 tasks, 2 trials each (44 total). Uses `CONCLAVE_NON_INTERACTIVE=1` which routes brainstorming to single-agent Autopilot mode.

| Task | Category | v6 Sonnet | v6 Opus | TDD Sonnet | Self-Review | Claude Code |
| --- | --- | ---: | ---: | ---: | ---: | ---: |
| **T1** time-tracker | greenfield/simple | 98.5% | 97.4% | 98.1% | 96.2% | 83.9% |
| **T2** collab-server | greenfield/complex | 95.9% | 95.3% | 94.2% | 92.0% | 64.9% |
| **T3** fts-search | features/medium | 100% | 100% | 100% | 100% | 99.3% |
| **T4** phantom-invoice | bugfix/medium | 100% | 100% | 100% | 100% | 100% |
| **T5** task-queue | marathon | 94.4% | 95.6% | 96.2% | 92.6% | 75.7% |
| **T6** monorepo-disaster | recovery | 100% | 100% | 100% | 100% | 100% |
| **T7** plugin-marketplace | greenfield/complex | 98.1% | 98.7% | 98.2% | 98.8% | 94.9% |
| **T8** analytics-dashboard | greenfield/complex | 94.2% | 93.6% | 96.1% | 88.8% | 87.9% |
| **T9** ssg-toolkit | features/complex | 100% | 100% | 100% | 100% | 99.4% |
| **T10** ecommerce-backend | greenfield/complex | 97.8% | 98.0% | 97.9% | 96.5% | 89.8% |
| **T11** debug-nightmare | bugfix/hard | 100% | 100% | 100% | 100% | 99.3% |
| **Mean** | | **98.1%** | **98.0%** | **98.2%** | **96.8%** | **89.6%** |
| **Avg Cost** | | $1.11 | $2.20 | $1.08 | $1.13 | $0.27 |

**Findings:**

1. **Conclave v6 ties for #1 on both models.** Sonnet (98.1%, n=22) and Opus (98.0%, n=22) both land in the top tier alongside TDD Sonnet (98.2%). Five perfect scores each (T3, T4, T6, T9, T11), 100% pass rate on both. The task classifier successfully routes each task to an effective methodology regardless of model.

2. **Sonnet matches Opus at half the cost — again.** v6 Sonnet (98.1%, $1.11) vs v6 Opus (98.0%, $2.20). The 0.1pp difference is noise; the 2x cost difference is real. This replicates the TDD finding: structured methodology eliminates the model capability gap.

3. **The plugin adds 1.3 points over a bare system prompt.** Conclave v6 Sonnet (98.1%) vs Self-Review Sonnet (96.8%) — the structured skill routing and completion gate provide a small but consistent advantage over "verify and review your diff" alone.

4. **Biggest improvement: greenfield tasks.** T1 (+14.6 vs vanilla), T2 (+31.0), T8 (+6.3), T10 (+7.9). The brainstorming → TDD routing gives greenfield tasks both upfront design thinking and implementation discipline.

5. **The three v6 changes compound.** Previous studies showed individual genes cluster within 0.6 points (96.8-97.4%). Conclave v6 breaks above that range by combining the right gene for each task type rather than applying one gene uniformly. Task-aware routing > one-size-fits-all discipline.

6. **Consensus demotion was the right call.** The Conclave Binary Effect study showed consensus adds nothing (pure 97.1% > +keys 95.7%). Making consensus opt-in removes the overhead without losing any benefit.

**Hard benchmark results (T12-T19):**

v6 was run on all 8 hard benchmarks with 2 trials each (32 additional trials). Results in the [Hard Benchmarks table](#hard-benchmarks-t12-t19) above.

- **v6 Opus (87.8%)** lands within 1.9 points of the leader (TDD Opus 89.7%) on the hard suite. Holds the highest individual scores on T17 circuit-debugger (90.3%) and T18 beam-splitter (94.3%). T12 was affected by a validation container hang (trial 1: hidden_tests=0, trial 2: 94.7%).
- **v6 Sonnet (87.0%)** is the standout cost-performance result. TDD Sonnet scored 62.9% on the same tasks — crashing on 5 of 6 reasoning/hard trials. v6 Sonnet completed all 16 trials with 100% pass rate. At $0.80/trial, v6 Sonnet is the best cost-adjusted hard benchmark orchestrator — matching Self-Review Opus (87.5%) at 56% of the cost.
- **v6 Sonnet's weakness is T17 circuit-debugger (73.3%).** This task requires discovering that simulation caps at ~25% accuracy and switching to structural analysis — a reasoning leap that Opus handles (90.3%) but Sonnet struggles with. On all other tasks, v6 Sonnet is within 5 points of v6 Opus.

**Implication:** The optimal plugin architecture is not "more consensus" or "more checkpoints" — it's intelligent routing to the right methodology for each task type, with a consistent verification gate across all paths. Conclave v6 validates this on both Sonnet and Opus across both easy and hard tasks: a well-designed classifier + completion gate matches the best individual gene while being more general-purpose. On hard benchmarks, v6 Sonnet at $0.80 is the clear cost-performance winner — matching Opus-tier results at 45% of the cost.

#### Planned Ablations

| Ablation | A | B | Gene Isolated | Status |
|---|---|---|---|---|
| Parallelism | Gas Town | Gas Station | Mayor + parallel polecats + refinery | Data exists (needs more trials) |
| Gas Station scaffolding | Gas Station | Claude Code + Headless | Git worktree + branch setup (gt prime discarded) | **Done — worktree matches Gas Station** |
| Git worktree isolation | Claude Code + Worktree | Claude Code | Bare clone + worktree (no Gas Town tooling) | **Done — 90.7% T5 (n=2), matches Gas Station** |
| Consensus review only | Conclave Review | Claude Code | Multi-agent code review (no skills) | **Done — +11.3 points** |
| Full skill pipeline | Full Conclave | Conclave Review | Brainstorm/plan/implement workflow | **Done — -2.0 points vs review-only (was -19 before data cleanup)** |
| Systematic debugging | Superpowers Debug | Claude Code | Four-phase debugging methodology | **Done — +7.1 points full-suite (96.7%, n=22); original T11-only study was misleading** |
| Test-driven development | Superpowers TDD | Claude Code | Forced red-green-refactor cycle | **Done — +11.5 points T1-T11 (97.4%); T12-T19: Opus #1 at 89.7%, Sonnet last at 62.9%** |
| Verification before completion | Superpowers Verify | Claude Code | "No claims without fresh evidence" | **Done — +11.4 points at $0.94 (cheapest top-tier)** |
| Skill-guided code review | Conclave Skill Review | Claude Code | requesting-code-review skill + conclave consensus | **Done — +7.4 points, 97.0% (n=34)** |
| Writing plans | Superpowers Plans | Claude Code | Mandatory plan before implementation | **Done — +7.3 points at $1.05** |
| Brainstorming | Conclave Brainstorm | Claude Code | Consensus design exploration (autopilot) | **Done — +7.8 points, #2 (97.4%, n=38)** |
| Gene stacking: Review + Verify | Review+Verify | Review / Verify | Two discipline checkpoints stacked | **Done — 97.2% (worse than either alone, diminishing returns)** |
| System prompt self-review | Self-Review | Claude Code | "Verify, commit, review diff, fix" — no plugins | **Done — 96.8% at $1.33 (n=40, within 0.6 of skills)** |
| Model ablation: Sonnet vs Opus | TDD/Brainstorm/Verify/Self-Review (Sonnet) | Same (Opus) | Cheap model + same system prompts | **Done — TDD Sonnet #1 overall (98.2%), structure closes the gap** |
| Consensus design review | Conclave Design | Claude Code | Pre-implementation multi-model architecture guidance | **Done — +16.2 points** |
| Self-review discipline | Double Review (no keys) | Claude Code | "Commit, review your diff, fix" in system prompt | **Done — ~+16 points (free, largest gene)** |
| Self-review + consensus | Double Review (keys) | Claude Code | Self-review + real multi-model consensus | **Done — ~+15.5 points (consensus adds nothing over self-review)** |
| Conclave binary effect | Conclave Brainstorm/Review (no keys, +keys) | Superpowers Brainstorm/Review | Multi-agent consensus binary + multi-provider | **Done — no effect, 3-way comparison (pure 97.1% > +keys 95.7% > no-keys 95.6%)** |
| Conclave v6 plugin | Conclave v6 (Sonnet + Opus) | TDD Sonnet / Self-Review | Task classifier + completion gate + consensus opt-in | **Done — T1-T11: Sonnet 98.1%, Opus 98.0%, both tie #1. T12-T19: Opus 87.8%, Sonnet 87.0%, top 7 cluster; v6 Sonnet best cost-perf at $0.80** |
| Mandatory skills | Conclave | Claude Code | Conclave plugin (TDD, debugging, planning) | Data exists (needs more trials) |
| Skill optionality | Conclave | Superpowers | Mandatory vs optional skill invocation | Data exists (needs more trials) |
| Metacognitive reframing | Metacog | Claude Code | Pre-implementation thinking skill | **Done — T1-T11 data exists; T12-T19: 82.6% (high variance, holds T19 high at 92.8%)** |
| Agent teams | Agent Teams | Claude Code | In-process teammate coordination | **Done — hurts on T5 (-30.9), noise elsewhere** |
| Branch from detached HEAD | Claude Code + Branch | Claude Code | `git checkout -b main` before agent | **Done — inconclusive (82.2%, high variance)** |
| Fresh-context Ralph loop | Ralph Fresh | Claude Code | Multi-iteration fresh context on same workspace | **Done — +15.6 on T5, now top-tier (91.3%)** |
| No-git workspace | Claude Code + No Git | Claude Code | Remove .git directory entirely | **Done — unstable (50% failure rate, n=4)** |
| Structured recipes | Amplifier + recipes | Amplifier (Opus) | Multi-step orchestration behaviors | Not started |
| Agent delegation | Amplifier + delegate | Amplifier (Opus) | Sub-session spawning | Not started |

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
| **[Conclave](https://github.com/signalnine/conclave) v6 (Opus)** | Conclave plugin + Opus 4.6 | Task classifier routes to right methodology; completion gate; consensus opt-in |
| **[Conclave](https://github.com/signalnine/conclave) v6 (Sonnet)** | Conclave plugin + Sonnet 4.6 | Same plugin, half the cost — Sonnet matches Opus (98.1% vs 98.0%) |
| **Self-Review (Opus)** | Claude Code Opus + system prompt only | No plugins, no skills — just "verify, commit, review diff, fix" in system prompt |
| **[Metacog](https://github.com/signalnine/metacog)** | Claude Code + metacognitive skill | Perspective-shifting plugin; methodology guidance |
| **Self-Review (Sonnet)** | Claude Code Sonnet + system prompt only | Same system prompt, ~5x cheaper model — matches Opus on hard tasks |
| **[BMAD-METHOD](https://github.com/bmad-code-org/BMAD-METHOD)** | Third-party structured workflow | Adversarial self-review with role-based phases |
| **[Superpowers](https://github.com/obra/superpowers)** | Skill-injection platform | Mandatory planning + TDD + two-stage review; no conclave binary |
| **[GSD](https://github.com/gsd-build/get-shit-done)** | Third-party wave-based execution | Parallel wave execution with dependency tracking |
| **Gemini CLI** | Google's agentic CLI | Gemini 3 models via Google One OAuth; headless `-p` mode |
| **Gas Station** | Single-agent + context injection | Gas Town's prompt engineering without multi-agent overhead |
| **Claude Code** | CLI agentic (single agent) | Rich tool use, subagent delegation, flexible autonomy |
| **[Gas Town](https://github.com/steveyegge/gastown)** | Multi-agent pipeline | Mayor (planner) -> parallel Polecats (workers) -> Refinery (merge) |
| **[Amplifier](https://github.com/microsoft/amplifier) (Opus)** | Micro-kernel platform | Swappable providers; minimal overhead; Opus 4.6 |
| **[Amplifier](https://github.com/microsoft/amplifier) (Gemini)** | Amplifier + Gemini Flash | Amplifier orchestration with Gemini 3 Flash via API |
| **Agent Teams** | Claude Code interactive + teams | Experimental agent teams feature; tmux harness for idle detection |
| **Superpowers TDD** | Claude Code + TDD skill | Rigid red-green-refactor cycle; Opus #1 overall, Sonnet crashes on hard tasks |
| **Conclave Brainstorm** | Claude Code + conclave consensus binary | Consensus-driven design exploration via conclave binary (Claude-only consensus) |
| **Stacked** | Metacog + review + worktree | Three top genes combined: metacog reframing, consensus code review, git worktree |
| **Superpowers Verify** | Claude Code + verification skill | "No completion claims without fresh evidence" — cheapest top-tier Opus |
| **Conclave Review + Verify** | Claude Code + review + verify stacked | Gene stacking study — diminishing returns (97.2%, both genes combined) |
| **Conclave Review** | Claude Code + consensus review | Code review only — no skills, no planning |
| **Superpowers Brainstorm** | Claude Code + obra/superpowers skills only | Same brainstorming skill, no conclave binary — agent answers design questions autonomously |
| **Conclave Skill Review** | Claude Code + conclave consensus binary | Skill-guided consensus code review via conclave binary (Claude-only consensus) |
| **Superpowers Review** | Claude Code + obra/superpowers skills only | Same code review skill, no conclave binary — agent dispatches code-reviewer subagent |
| **Conclave Review + Keys** | Claude Code + conclave binary + multi-provider | Multi-provider consensus code review — true multi-model panel |
| **Superpowers Plans** | Claude Code + writing-plans skill | "Think before coding" — structured plan document before implementation |
| **Superpowers Debug** | Claude Code + systematic-debugging skill | Four-phase debugging methodology applied as general discipline |
| **Conclave Design** | Claude Code + consensus design | Pre-implementation architecture review |
| **Conclave Brainstorm + Keys** | Claude Code + conclave binary + multi-provider | Multi-provider consensus (Claude + Gemini + Codex) for design questions |
| **Conclave (Full)** | Cross-provider consensus | Claude x Gemini x Codex consensus; mandatory skill pipeline |
| **Conclave Double Review** | Claude Code + two review rounds | Double consensus code review — no improvement over single |
| **Conclave Dbl Review + Keys** | Conclave Double Review + multi-provider | Double review with multi-provider keys |
| **Conclave Brainstorm (Sonnet)** | Claude Code Sonnet + brainstorming skill | Sonnet + consensus design — 94.7% at $0.74/task |
| **Ralph Fresh** | Claude Code + fresh-context Ralph loop | Multi-iteration fresh context on same workspace |
| **Claude Code Worktree** | Claude Code + git worktree | Matches Gas Station — worktree adds isolation, not quality |
| **Verify (Sonnet)** | Claude Code Sonnet + verification skill | Sonnet + verification — 94.3% at $0.74/task |
| **Claude Code Headless** | Claude Code `-p` mode without skills | Headless baseline — no interactive user, no plugins |
| **Amplifier + ts-dev** | Amplifier + TypeScript bundle | LSP code intelligence, TS expert agent |

See [`docs/survey/orchestrator-survey.md`](docs/survey/orchestrator-survey.md) for the full gene matrix and per-tool analysis.

## Benchmark Suite

Nineteen tasks span eight categories:

**Standard Suite (T1-T11)** — the original 11 tasks covering greenfield, features, bugfix, marathon, and recovery:

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

**Hard Suite (T12-T19)** — 8 tasks designed to differentiate where the standard suite couldn't. Naive or brute-force approaches fail at scale; agents must discover efficient algorithms:

| # | Task | Category | Key Challenge | Timeout | Hidden Tests |
|---|------|----------|---------------|---------|------|
| 12 | Constraint Scheduler | algorithmic/hard | Backtracking + constraint propagation | 45m | 38 |
| 13 | Structural Merge | algorithmic/hard | 3-way tree merge with conflict detection | 45m | 22 |
| 14 | Financial Ledger | correctness/hard | Double-entry accounting invariants | 30m | 35 |
| 15 | Permission Maze | ambiguity/hard | Deliberately vague spec; agents must infer rules | 45m | 52 |
| 16 | Reactive Spreadsheet | algorithmic/hard | Topological sort + cycle detection + propagation | 45m | 77 |
| 17 | Circuit Debugger | reasoning/hard | Structural analysis beats simulation at scale | 45m | 20 |
| 18 | Beam Splitter | reasoning/hard | Counter propagation vs path enumeration (2^K paths) | 45m | 23 |
| 19 | Factory Reset | reasoning/hard | GF(2) linear algebra (toggle = XOR = Gaussian elimination) | 45m | 20 |

All tasks use TypeScript/Node.js with Vitest. Orchestrators cannot cheat by modifying tests. Validation runs `npm run build && npm run lint && npm test`.

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
├── benchmarks/                 # 19 standalone task repos (each with v1/v1-solution tags)
├── docker/                     # Dockerfiles for orchestrator images
├── docs/
│   ├── survey/                 # Orchestrator architecture survey
│   └── plans/                  # Design documents
├── thunderdome.yaml            # Default configuration
└── project.md                  # Full project specification
```

## Status

- [x] Orchestrator survey (10 tools documented)
- [x] Benchmark task design (19 tasks specified — 11 standard + 8 hard)
- [x] Build benchmark task repos (19 repos, v1/v1-solution/v1-validation tags)
- [x] Harness implementation (run, list, report, validate commands)
- [x] Write orchestrator adapters (10 orchestrators, 20+ adapter variants)
- [x] Run baseline comparisons (single-trial full suite for 10 orchestrators)
- [ ] Multi-trial runs for statistical significance
- [x] Hard benchmark suite (T12-T19) — 8 tasks designed to differentiate where T1-T11 couldn't. 160-trial run across 10 orchestrators. TDD Opus (89.7%) takes #1 — the TDD methodology that crashes Sonnet (62.9%) works best with Opus. Top 7 orchestrators cluster within 2.7 points (87.0-89.7%); Metacog (82.6%), vanilla (76.7%), and TDD Sonnet (62.9%) fall off
- [ ] Ablation studies (gene isolation) — 18 done on T1-T11: ts-dev (no effect), consensus review (+11.3), full pipeline (-2 vs review-only), systematic debugging (+7.1 full-suite, original T11-only was misleading), TDD (+8.4), verification (+11.4, cheapest top-tier), writing plans (+7.3), skill-guided review (+8.1, #1 at 97.7%), brainstorming (+7.9, #2 at 97.5%), review+verify stacking (diminishing returns, 97.2%), design review (+16.2), self-review (~+16, free), self-review+consensus (consensus adds nothing), worktree matches Gas Station, agent teams (hurts on T5), branch (inconclusive), Ralph fresh-context (+15.6 on T5, top-tier), no-git (unstable), Conclave v6 plugin (Sonnet 98.1%, Opus 98.0%, both tie #1). All scores are mechanical (tests, build/lint, coverage, code metrics) — rubric dropped. Early adapter-debugging trials pruned per-orchestrator.
- [ ] Run remaining orchestrators on T12-T19 hard suite
- [ ] Publish methodology paper

## License

TBD
