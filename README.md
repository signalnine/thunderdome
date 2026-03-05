# Agentic Thunderdome

Two agents enter, one agent leaves.

A benchmarking framework that pits agentic coding orchestrators against standardized programming tasks and measures what matters: completion rate, token efficiency, cost, and correctness.

## Results

Composite scores across 19 tasks — the original 11-task standard suite (T1-T11) plus 8 hard benchmarks (T12-T19) spanning algorithmic, correctness, ambiguity, and reasoning challenges. Data includes 1,400+ scored trials across 39 primary orchestrator variants (1,600+ total including adapter-debugging and crash trials). All scoring is deterministic — no LLM judges, no rubric. Crash trials ($0 cost, <10s duration) are excluded from averages. Early adapter-debugging trials have been pruned — each orchestrator's data starts from its first stable full-suite run.

### Leaderboard

Composite scores ranked by Overall (weighted average of Standard and Hard suite means). Orchestrators tested only on T1-T11 are listed below the ranked entries. Gene ablation variants (testing individual features in isolation) are in a [separate table](#gene-ablation-variants). See [Contenders](#contenders) for architecture descriptions.

| Rank | Orchestrator | Standard | Hard | Overall | Trials | Avg Cost | Model |
|---:|---|---:|---:|---:|---:|---:|---|
| 1 | [**Conclave v6 (Opus)**](#contenders) | 95.2% | 87.8% | **92.1%** | 49 | $2.05 | Opus 4.6 |
| 2 | [Conclave Brainstorm](#contenders) | 93.3% | 88.8% | **91.4%** | 49 | $1.59 | Opus 4.6 |
| 3 | [Self-Review (Opus)](#contenders) | 93.7% | 87.9% | **91.3%** | 49 | $1.31 | Opus 4.6 |
| 4 | [Conclave v6 (Sonnet)](#contenders) | 92.8% | 87.0% | **90.3%** | 45 | $0.83 | Sonnet 4.6 |
| 5 | [TDD (Opus)](#contenders) | 89.6% | 89.7% | **89.6%** | 46 | $2.31 | Opus 4.6 |
| 5 | [TDD (Sonnet)](#contenders) | 94.5% | 82.3% | **89.4%** | 55 | $1.40 | Sonnet 4.6 |
| 7 | [Stacked](#contenders) | 88.8% | 87.9% | **88.4%** | 49 | $1.48 | Opus 4.6 |
| 8 | [Self-Review (Sonnet)](#contenders) | 85.3% | 89.9% | **87.3%** | 45 | $0.68 | Sonnet 4.6 |
| 9 | [Metacog](#contenders) | 89.2% | 82.5% | **86.4%** | 49 | $1.26 | Opus 4.6 |
| 10 | [Superpowers](#contenders) | 85.9% | 86.0% | **86.0%** | 49 | $1.28 | Opus 4.6 |
| 11 | [BMAD-METHOD](#contenders) | 82.6% | 87.8% | **84.8%** | 45 | $1.38 | Opus 4.6 |
| 12 | [Gemini CLI](#contenders) | 80.7% | 84.8% | **82.4%** | 37 | $0.14 | Gemini 3 Flash |
| 13 | [GSD](#contenders) | 81.2% | 83.7% | **82.2%** | 45 | $0.86 | Opus 4.6 |
| 14 | [Agent Teams](#contenders) | 84.9% | 77.4% | **81.7%** | 43 | $1.89 | Opus 4.6 |
| 15 | [Claude Code](#contenders) | 85.6% | 77.0% | **82.0%** | 51 | $1.10 | Opus 4.6 |
| 16 | [Gas Station](#contenders) | 85.8% | 75.5% | **81.5%** | 46 | $0.85 | Opus 4.6 |
| 17 | [Amplifier (Opus)](#contenders) | 86.0% | 69.4% | **79.0%** | 28 | $0.29 | Opus 4.6 |
| 18 | [Gas Town](#contenders) | 68.9% | 88.2% | **77.0%** | 49 | $3.16 | Opus 4.6 |
| — | [Amplifier (Gemini)](#contenders) | 85.6% | 39.6% | — | 20 | $0.03 | Gemini 3 Flash |
| 19 | [Aider (Cerebras)](#contenders) | 64.5% | 45.2% | **56.4%** | 38 | $0.00 | gpt-oss-120b |

### Cost Efficiency

All orchestrators with Overall scores, sorted by cost. **Bold** = Pareto-optimal (no other orchestrator scores higher at equal or lower cost).

| Orchestrator | Overall | Avg Cost | Pareto |
|---|---:|---:|:---:|
| Aider (Cerebras) | 56.4% | $0.00 | |
| **Gemini CLI** | **82.4%** | **$0.14** | **best <$0.68** |
| Amplifier (Opus) | 79.0% | $0.29 | |
| **Self-Review (Sonnet)** | **87.3%** | **$0.68** | **best <$0.83** |
| Gas Station | 81.5% | $0.85 | |
| GSD | 82.2% | $0.86 | |
| **Conclave v6 (Sonnet)** | **90.3%** | **$0.83** | **best <$1.31** |
| Claude Code | 82.0% | $1.10 | |
| Metacog | 86.4% | $1.26 | |
| Superpowers | 86.0% | $1.28 | |
| **Self-Review (Opus)** | **91.3%** | **$1.31** | **best <$1.59** |
| BMAD-METHOD | 84.9% | $1.38 | |
| TDD Sonnet | 89.6% | $1.40 | |
| Stacked | 88.4% | $1.48 | |
| **Conclave Brainstorm** | **91.4%** | **$1.59** | **best <$2.05** |
| Agent Teams | 82.5% | $1.87 | |
| **Conclave v6 (Opus)** | **92.1%** | **$2.05** | **best overall** |
| TDD Opus | 89.6% | $2.31 | |
| Gas Town | 77.0% | $3.16 | |

The biggest value jump is from Gemini CLI ($0.10, 82.2%) to SR Sonnet ($0.68, 87.3%) — **+5.1 points for $0.58 more**. From there to v6 Sonnet ($0.83, 90.3%) adds +3.0 points for $0.15 more. From v6 Sonnet to SR Opus ($1.31, 91.3%) adds +1.0 points for $0.48 — diminishing returns. The Pareto frontier has compressed with n=3 data: v6 Opus (92.1%) barely beats Brainstorm (91.4%) and SR Opus (91.3%) at higher cost. The top tier is converging.

### Gene Ablation Variants

Individual orchestrator "genes" tested in isolation — Claude Code with a single feature forced on. Scores continue to drop with more trials: the n=1 cluster at 97% dropped to ~92% at n=2, and now drops further to 89-94% at n=3. The top tier is converging — the gap between "best discipline" and "vanilla" narrowed from 12pp to 8pp. Variants tested on T12-T19 are ranked by Overall; standard-only variants listed below. See [Ablation Studies](#ablation-studies) for detailed per-gene analysis.

| Rank | Variant | Standard | Hard | Overall | Trials | Avg Cost | Model |
|---:|---|---:|---:|---:|---:|---:|---|
| 1 | **Conclave Brainstorm** | 93.3% | 88.8% | **91.4%** | 49 | $1.59 | Opus 4.6 |
| 2 | Superpowers TDD | 89.6% | 89.7% | **89.6%** | 46 | $2.31 | Opus 4.6 |
| 3 | Superpowers TDD | 94.5% | 80.6% | **89.6%** | 55 | $1.40 | Sonnet 4.6 |
| 4 | Stacked | 88.8% | 87.9% | **88.4%** | 49 | $1.48 | Opus 4.6 |
| — | Conclave Review + Keys | 94.1% | — | — | 33 | $1.77 | Multi-provider |
| — | Superpowers Brainstorm (pure) | 92.8% | — | — | 29 | $0.89 | Opus 4.6 |
| — | Superpowers Review (pure) | 92.5% | — | — | 33 | $1.95 | Opus 4.6 |
| — | Conclave Skill Review | 92.3% | — | — | 33 | $2.10 | Opus 4.6 |
| — | Verify (Sonnet) | 91.6% | — | — | 33 | $0.72 | Sonnet 4.6 |
| — | Conclave Brainstorm + Keys | 91.6% | — | — | 33 | $1.46 | Multi-provider |
| — | Superpowers Debug | 90.7% | — | — | 33 | $1.01 | Opus 4.6 |
| — | Conclave Brainstorm (Sonnet) | 90.7% | — | — | 30 | $0.62 | Sonnet 4.6 |
| — | Conclave Review + Verify | 90.2% | — | — | 33 | $2.21 | Opus 4.6 |
| — | Superpowers Plans | 89.6% | — | — | 33 | $1.06 | Opus 4.6 |
| — | Superpowers Verify | 89.2% | — | — | 33 | $0.96 | Opus 4.6 |
| — | Conclave Review | 86.5% | — | — | 30 | $1.32 | Opus 4.6 |
| — | Conclave Design | 95.7% | — | — | 9 | $2.09 | Multi-provider |
| — | Conclave (Full) | 95.2% | — | — | 12 | $0.14 | Multi-provider |
| — | Conclave Double Review | 95.2% | — | — | 9 | $1.26 | Opus 4.6 |
| — | Conclave Dbl Review + Keys | 95.0% | — | — | 9 | $1.89 | Multi-provider |
| — | Ralph Fresh | 94.7% | — | — | 4 | $1.57 | Opus 4.6 |
| — | Claude Code Worktree | 94.7% | — | — | 3 | $1.20 | Opus 4.6 |
| — | Claude Code Headless | 94.2% | — | — | 9 | $1.15 | Opus 4.6 |
| — | Amplifier + ts-dev | 86.8% | — | — | 12 | $0.74 | Opus 4.6 |

### Hard Benchmarks (T12-T19)

Per-task breakdown for the 8 harder benchmarks — algorithmic complexity (T12-T13, T16), correctness constraints (T14), ambiguous requirements (T15), and deep reasoning where naive approaches fail at scale (T17-T19). Aggregate rankings are in the [leaderboard](#leaderboard) above.

20 orchestrators (n=2+ per task unless noted, 307 total trials), sorted by hard-suite mean:

| Task | Category | SR Sonnet | TDD Opus | Brstm Opus | Gas Town | Agent Tm | SR Opus | Stacked | BMAD | v6 Opus | v6 Sonnet | Superpowers | GSD | Metacog | Gemini | Vanilla | Gas Stn | Amp Opus | TDD Sonnet | Aider Cerebras |
|------|----------|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| **T12** constraint-scheduler | algo/hard | 90.4% | 91.8% | **93.4%** | 90.5% | 88.4%¶ | 81.0% | 91.3% | 83.8% | 76.5%† | 87.8% | 73.7% | 92.6% | 75.9% | 90.1% | 60.0% | 74.4% | 76.6%‖ | 81.3% | 52.0% |
| **T13** structural-merge | algo/hard | 91.0% | 89.0% | **93.3%** | 85.5% | 89.4% | 90.1% | 90.2% | 90.0% | 93.0% | 89.9% | 91.2% | 91.6% | 75.0% | 66.6% | 59.0% | 58.5% | 56.4%‖ | 88.2% | 32.2% |
| **T14** financial-ledger | correct/hard | 100% | 100% | 100% | 100% | 100% | 100% | 100% | 100% | 100% | 100% | 100% | 100% | 100% | 100% | 100% | 100% | 100% | 100% | 100% |
| **T15** permission-maze | ambig/hard | 70.8% | 75.3% | 65.2% | 77.7% | **78.6%** | 67.0%‡ | 61.2% | 73.6% | 66.8% | 70.7% | 76.6% | 76.7% | 67.8%‡ | 63.9% | 69.6% | 62.9% | 78.3% | 64.3% | 44.5% |
| **T16** reactive-spreadsheet | algo/hard | 93.0% | 91.9% | **93.2%** | 92.3% | 89.8% | 90.2% | 88.0% | 91.2% | 91.9% | 91.2% | 90.9% | 89.5% | 88.9% | 89.9% | 91.1% | 87.8% | 91.8% | 88.7% | 28.8% |
| **T17** circuit-debugger | reason/hard | 86.0% | 86.9% | 85.3% | 84.5% | 92.2% | 86.6% | 87.3% | 83.7% | 90.3% | 73.3% | 89.7% | 70.3% | 84.8% | **93.6%** | 88.9% | 88.1% | 92.2% | 40.4%\* | 25.6% |
| **T18** beam-splitter | reason/hard | **95.3%** | 90.2% | 93.2% | 90.0% | 80.1% | 93.9% | 93.2% | 91.9% | 94.3% | 94.0% | 77.0% | 75.3% | 75.2% | 95.3% | 69.2% | 59.0% | 40.0%‖ | 20.0%\* | 39.0% |
| **T19** factory-reset | reason/hard | 93.1% | 92.3% | 87.0% | 85.4% | 86.0% | 91.0% | 91.7% | 88.2% | 89.5% | 88.9% | 89.2% | 73.7% | **92.8%** | 78.8% | 78.6% | 68.2% | 20.0%‖ | 20.0%\* | 39.2% |
| **Mean** | | **89.9%** | 89.7% | 88.8% | 88.2% | 88.1% | 88.1% | 87.9% | 87.8% | 87.8% | 87.0% | 86.0% | 84.8% | 83.7% | 82.5% | 77.0% | 74.9% | 69.4% | 62.9% | 45.2% |
| **Avg Cost** | | $0.77 | $3.19 | $1.94 | $2.55 | $3.93 | $1.43 | $1.48 | $2.01 | $1.78 | $0.80 | $1.49 | $0.12 | $1.09 | $1.57 | $1.33 | $1.06 | $0.46 | $0.53 | $0.00 |

\*TDD Sonnet crashed on 5 of 6 reasoning/hard trials ($0.00 cost, <3s duration). The non-crashing T17 trial scored 60.8%.
†v6 Opus T12 trial 1 had a validation container hang (hidden_tests=0); trial 2 scored 94.7%.
‡Self-Review and Metacog T15 trial 2 affected by OAuth expiry during the run.
¶Agent Teams T12 is n=3 (includes diagnostic trial). All other tasks n=2.
‖Amplifier Opus had bundle-prep crashes (T12 trial 2, T18 trial 1: $0, <4min) and timeouts (T13 trial 1, T19 both trials).

**Key findings from the hard suite:**

1. **SR Sonnet leads hard tasks by a hair; top 3 within 1.1 points.** Self-Review Sonnet (89.9%), TDD Opus (89.7%), and Brainstorm Opus (88.8%) form a tight top tier — all within noise of each other. The surprise: Sonnet with just a system prompt ("verify, review your diff, fix") beats every Opus orchestrator except TDD on hard tasks, at a fraction of the cost ($0.77 vs $3.19/hard trial). TDD Sonnet collapses to 62.9% — the TDD cycle amplifies Opus's reasoning but exposes Sonnet's limits.

2. **n=2 data deflated BMAD by 2.7 points.** BMAD's hard mean dropped from 90.5% (n=1) to 87.8% (n=2) — the single biggest correction from adding trials. T12 constraint-scheduler swung from 95.8% to 71.8% between trials, and T15 permission-maze from 84.9% to 62.3%. The adversarial self-review workflow is good but not the outlier it appeared to be. This is exactly why n=2 matters.

3. **Hard tasks finally differentiate orchestrators.** The T1-T11 spread among top-tier Opus variants at n=3 is 6 points (89-95%). On T12-T19 the spread is 27 points (62.9-89.9%). Hard benchmarks test what easy benchmarks can't: whether the agent can discover novel algorithmic approaches rather than implement well-known patterns.

4. **The top 10 cluster within 3 points — below that, it falls off fast.** SR Sonnet (89.9%) through v6 Sonnet (87.0%) span 2.9 points, now including Agent Teams (88.1%). Then Superpowers (86.0%), GSD (83.7%), Metacog (82.5%), and Gemini CLI (80.3%) form a mid-tier, vanilla drops to 77.0%, Gas Station to 74.9%, Amplifier to 69.4%, TDD Sonnet to 62.9%.

5. **Gemini CLI climbs to 80.3% with n=2 data — T13 was the biggest correction.** T13 structural-merge swung from 20.0% to 89.2% between trials — the largest single-trial swing in the hard suite. With n=2 averaging, Gemini's hard mean jumps from 76.1% to 80.3%, pushing it past Claude Code and Gas Station to #9 overall (82.2%). It still holds the highest scores on T17 circuit-debugger (93.6%) and T18 beam-splitter (96.5%), but rate-limit crashes prevented T16-T19 trial 2 (n=1 only). At $0.09/hard trial, it beats Claude Code ($0.77) at a fraction of the cost.

6. **Metacog (82.5%) has the highest variance.** T18 beam-splitter: one trial 58%, the other 92%. T19 factory-reset: 95% and 90%. The metacognitive reframing occasionally produces breakthrough insights but inconsistently. Metacog does hold the highest T19 score (92.8%) among Claude-based orchestrators.

7. **Permission maze (T15) is the hardest non-crashing task.** Scores range 61-79% across 18 orchestrators — the deliberately ambiguous TASK.md exposes agents that make assumptions rather than exploring edge cases. Agent Teams takes the lead (78.6%), followed by Amplifier (78.3%), Gas Town (77.7%), GSD (76.7%), and Superpowers (76.6%).

8. **Third-party tools: BMAD outperforms GSD on hard tasks.** BMAD (87.8%) and GSD (83.7%) represent different approaches — BMAD's structured adversarial workflow vs GSD's wave-based parallel execution. GSD is strong on algorithmic tasks (T12: 92.6%, T13: 91.6%) but shows high variance on reasoning tasks (T18: 92.6%/58.1%, T19: 89.0%/58.5% between trials). n=2 data confirmed GSD's mid-tier placement.

9. **Gas Station n=2 exposed massive T12 variance.** Gas Station's T12 dropped from 92.4% to 56.4% between trials — the biggest single-trial swing in the dataset. T17 went the other direction (82.2%→94.1%). Overall hard mean dropped from 75.7% to 74.9%, confirming Gas Station as the weakest full-suite Opus orchestrator on hard tasks.

### Key Findings

- **n=3 data confirms the convergence trend.** Every "stable" n=2 score dropped 3-5 more points at n=3: v6 Opus 98.0%→95.2%, TDD Sonnet 98.2%→94.5%, Brainstorm 97.4%→93.3%, Self-Review 96.8%→93.7%, Review 97.0%→92.3%, v6 Sonnet 98.1%→92.2%. The top tier has compressed from a 12-point spread (85.5-97.4%) to a 10-point spread (85.6-95.2%). Vanilla Claude Code (85.6%) barely moved — the floor is real, but the ceiling keeps dropping
- **v6 Opus leads overall at 92.1%.** The task classifier + completion gate architecture remains the most robust across both standard (95.2%) and hard (87.8%) tasks. Brainstorm (91.4%) and Self-Review Opus (91.3%) follow closely, with SR Opus achieving it at lower cost ($1.31 vs $1.59)
- **v6 Sonnet is the Pareto-optimal choice.** 90.3% Overall at $0.83/task — the best cost-adjusted score in the dataset. v6 Sonnet beats every orchestrator costing less than $1.31, and its 92.8% standard score matches discipline-gene Opus variants
- **TDD Opus and TDD Sonnet converge at 89.6% overall — through different paths.** TDD Opus: strong on hard tasks (89.7%) but weak on standard (89.6%). TDD Sonnet: strong on standard (94.5%) but weak on hard (80.6%). Their overall scores are identical but the profiles are opposite. TDD's rigid cycle helps Sonnet's consistency on implementation tasks but limits Opus's flexibility on reasoning tasks
- **Multi-agent consensus adds nothing — even with real multi-provider keys.** Three-way test: pure superpowers (no binary), conclave (Claude-only consensus), conclave + keys (Claude + Gemini + Codex). All within 2pp: no-keys 93.3% > pure 92.3% > +keys 91.6%. The structured skill text drives all the value
- **The real gap is vanilla vs any discipline — but it's narrowing.** Claude Code without review instruction scores 85.6% standard. Adding discipline jumps to 89-95% — a 4-10 point improvement. At n=1, the gap was ~12 points; at n=3, the best discipline gene leads by ~8 points. The skill infrastructure still helps but the marginal value keeps shrinking
- **Hard benchmarks (T12-T19) still differentiate.** On standard tasks, the top-to-bottom spread among Opus variants is ~10 points. On hard tasks it's 14+ points. SR Sonnet (89.9%) and TDD Opus (89.7%) lead; Brainstorm (88.8%) and Gas Town (88.2%) follow. TDD Sonnet (80.6% hard) drops to #15 — rigid TDD cycles hurt on novel reasoning tasks
- **Gene stacking has diminishing returns** — Review + Verify (90.2% at n=3) scores no better than either alone. Two discipline checkpoints don't compound
- **Gas Town collapsed on standard tasks (68.9%, n=3).** The Mayor→Polecats→Refinery pipeline scores 30% on T3 and T4 across all trials — the single-polecat strategy completes with minimal work. Gas Town is strong on hard tasks (88.2%, #4) but its standard-task weakness drops it to last place overall (77.0%)
- **T4** (bugfix) is the great equalizer — most contenders score 100%, the task is too easy
- **T2, T5, and T8 are the variance killers.** These three complex tasks (collab-server, task-queue, analytics-dashboard) account for virtually all inter-trial variance. Scores range from 54% to 95% across orchestrators. Every n→n+1 backfill drop is concentrated in these tasks
- **Third-party tools show promise on hard tasks.** [BMAD-METHOD](https://github.com/bmad-code-org/BMAD-METHOD) (87.8% hard, 82.9% standard) and [GSD](https://github.com/gsd-build/get-shit-done) (83.7% hard, 81.2% standard) both perform better on hard tasks relative to their standard-suite ranking. Both show significant inter-trial variance on standard tasks, which worsened with n=3 data

### The Gas Station Story

Gas Town is a multi-agent pipeline: a Mayor decomposes the task, parallel Polecats implement pieces in git worktrees, and a Refinery merges their work and fixes conflicts. We asked Claude Code to build the adapter.

What it delivered was a fraud — a single `claude -p` call with `gt prime` context injected, wearing Gas Town's scaffolding like a trench coat. It set up the town, created beads, initialized a polecat worktree, the whole ceremony — then ran one agent that did all the work by itself. A single agent pretending to be a workforce.

I named the impostor "Gas Station" and kept it as a control while we built the real multi-agent pipeline ourselves.

Then the benchmarks came back. Gas Station scored 85.8% standard (n=30). The single agent in a trench coat was respectably consistent. And the real multi-agent pipeline? Gas Town scores 88.2% on hard tasks (#4 overall) but cratered to 68.9% on standard tasks (n=33) — the Mayor dispatches simple tasks to a single polecat that sometimes completes with minimal work (30% on T3 and T4, every trial). The fraud outperforms the real thing on standard tasks by 17 points. On hard tasks, the multi-agent decomposition finally justifies itself. Gas Station earned its place: a permanent reminder that complexity must earn its keep on every task type, not just the hard ones.

### From Gene Ablation to Conclave v6

The ablation studies below aren't just academic — they directly shaped [Conclave's](https://github.com/signalnine/conclave) v6 architecture. Here's the story of how 1,200+ trials rewrote a multi-agent framework.

**Phase 1: Measure every gene in isolation.** We tested 8 composable features ("genes") one at a time against vanilla Claude Code (85.6%). The n=1 results looked striking: every discipline gene landed within 1.4 points of each other (96.7-98.0%). With n=2 backfill, every gene dropped 4-6 points. With n=3, the previously "stable" entries dropped another 3-5 points: Brainstorm 97.4%→93.3%, v6 Opus 98.0%→95.2%, TDD Sonnet 98.2%→94.5%, Review 97.0%→92.3%. The top and bottom are converging — the gap from vanilla to best discipline narrowed from 12pp to 8pp.

**Phase 2: Three findings that broke assumptions.**

1. **Multi-agent consensus adds nothing.** Conclave's signature feature — synthesizing perspectives from Claude, Gemini, and Codex — was tested in a 3-way comparison. All three variants converged within 2pp at n=3. More models meant more noise, not more signal.

2. **Gene stacking has diminishing returns.** Review + Verify stacked scored 90.2% at n=3 — no better than either gene alone. Two quality checkpoints don't catch more than one.

3. **A 15-line system prompt captures ~90% of the benefit.** "Implement, verify, commit, review your diff, fix issues" — no plugins, no skills, no binary — scored 93.7% (Opus). The skill infrastructure adds ~1.5pp of stability on top, but the instruction does the heavy lifting.

**Phase 3: Redesign around the data.** These findings drove three architectural changes in Conclave v6:

- **Task classifier replaces skill browsing.** Instead of 16 skills for the agent to evaluate, the entry point auto-routes: new feature → brainstorm then TDD, bug fix → TDD, everything else → verify. One skill per task, no decision paralysis. Top performers in the benchmark all used exactly one skill.

- **Completion gate embedded everywhere.** The self-review prompt worked because it baked verification into the workflow exit. v6 adds a mandatory gate to every skill: run tests, read output, commit, review diff, fix issues. No skill completes without fresh evidence.

- **Consensus demoted to opt-in.** Every `conclave consensus` call was moved from the default flow to an "Optional: Multi-Agent Consensus" section. Single-agent execution is the default. The binary still works — it just stops hurting scores by default.

**The result:** Conclave v6 on Opus 4.6 scores 95.2% standard (n=3, #1), 87.8% hard — the best overall orchestrator. v6 Sonnet scores 92.2% standard, 87.0% hard at half the cost. The framework went from complex multi-agent orchestration to structured single-agent methodology, guided entirely by benchmark evidence.

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

**Hard benchmark results (T12-T19):** Amplifier (Opus) scored **69.4% hard mean** with n=2 per task. Strong on T16 reactive-spreadsheet (91.8%) and T17 circuit-debugger (92.2%), but fragile: 4 of 16 trials crashed or timed out (bundle-prep failures on T12/T18, timeouts on T13/T19). T19 factory-reset (20.0%) was a total loss — both trials timed out. T15 permission-maze (78.3%) was surprisingly competitive (#2 across all orchestrators). At $0.46/hard trial, Amplifier is cheap but unreliable — when it works, it's mid-tier; when the bundle preparation fails, it scores 20%. Overall drops to 79.0% (#13), between Claude Code (81.4%) and Gas Town (77.2%).

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

**Setup:** Claude Code Opus with the systematic-debugging skill forcibly invoked. The skill mandates a four-phase process for each bug: (1) root cause investigation — read errors, reproduce, trace data flow; (2) pattern analysis — find working examples, compare; (3) hypothesis testing — form hypothesis, test minimally; (4) implementation — create fix, verify. One bug at a time, no batching. Run across all 11 tasks with 3 trials (33 total).

| Task | Category | Debug | Claude Code | Delta |
| --- | --- | ---: | ---: | ---: |
| **T1** time-tracker | greenfield/simple | 87.1% | 82.9% | +4.2 |
| **T2** collab-server | greenfield/complex | 79.1% | 54.1% | +25.0 |
| **T3** fts-search | features/medium | 86.7% | 100% | -13.3 |
| **T4** phantom-invoice | bugfix/medium | 93.2% | 98.3% | -5.1 |
| **T5** task-queue | marathon | 82.6% | 62.0% | +20.6 |
| **T6** monorepo-disaster | recovery | 100% | 100% | 0.0 |
| **T7** plugin-marketplace | greenfield/complex | 95.6% | 91.8% | +3.8 |
| **T8** analytics-dashboard | greenfield/complex | 77.7% | 56.4% | +21.3 |
| **T9** ssg-toolkit | features/complex | 100% | 100% | 0.0 |
| **T10** ecommerce-backend | greenfield/complex | 96.3% | 95.6% | +0.7 |
| **T11** debug-nightmare | bugfix/hard | 100% | 100% | 0.0 |
| **Mean** | | **90.7%** | **85.6%** | **+5.1** |

**Findings:**

1. **The original T11-only study was misleading.** The previous analysis (n=6 on T11 only) concluded "no measurable effect" because both variants scored ~99% on the debugging task. Across all 11 tasks at n=3, the debugging skill adds +5.1 points over vanilla — a solid mid-tier discipline gene, though less than the +7.1 seen at n=2.

2. **The debugging methodology works as general discipline.** The four-phase process (investigate → analyze → hypothesize → implement) isn't just for bugs — it imposes structure on greenfield (T2: +25.0) and marathon (T5: +20.6) tasks too. The "one fix at a time, verify after each" cadence prevents the agent from rushing. Some tasks (T3, T4) show Debug scoring below vanilla — likely noise from small sample sizes.

3. **At n=3, Debug landed at 90.7% — mid-tier.** Down from the n=2 reading of 96.7%. Debug (90.7%) vs Self-Review Opus (93.7%) — Self-Review pulled ahead with more trials. T2 (79%), T8 (78%), T5 (83%) are the usual variance killers.

4. **T8 and T2 remain the hardest.** Analytics dashboard (77.7%) and collab-server (79.1%) are the lowest scores — consistent with every other discipline gene. The debugging methodology's "one fix at a time" process may hurt on complex greenfield tasks where the challenge is architecture, not defect isolation.

5. **Cost-effective.** $1.01/task — cheaper than TDD ($1.84), Brainstorm ($1.43), and Review ($2.10). Comparable to Verify ($0.96) and Plans ($1.06).

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

> **n=3 update:** TDD Opus dropped from 98.0% (n=1) → 92.8% (n=2) → **89.5%** (n=3). Three complex tasks remain the variance killers: T2 (71%), T5 (77%), T8 (70%). T4 phantom-invoice also softened to 93%. The n=1 table above is preserved for historical context.

**Findings:**

1. **TDD Opus scored 98.0% at n=1, 92.8% at n=2, and 89.5% at n=3.** The decline continued with every backfill round. T2 collab-server (94→77→71%), T5 task-queue (93→77%), T8 analytics-dashboard (95→76→70%). T4 phantom-invoice, stable at 100% through n=2, dropped to 93% at n=3. The n=1 reading was heavily inflated by lucky first runs.

2. **Biggest gains on complex greenfield tasks — but also biggest variance.** The same tasks that showed the largest n=1 gains (T2, T5, T8) also showed the largest drops. TDD's red-green-refactor cycle helps most on complex tasks, but the improvement is inconsistent.

3. **No effect on tasks the model already aces.** T3, T9 remain at 100%. T6 softened slightly to 95% but is still near-perfect. The easy tasks are stable across all trial counts.

4. **Cost is the tradeoff.** $1.84/task mean (n=30 standard) — the most expensive standard Opus approach after Review+Verify. The red-green-refactor cycle adds turns: 135 turns on T5 vs typical 40-70.

**The revised pattern:** Forced TDD works — not because the model doesn't know how to test, but because the mandatory discipline prevents cutting corners under token pressure. The model naturally wants to implement first and test later (or not at all). Forcing test-first produces more thorough implementations. But at n=3, TDD Opus (89.5%) has converged with other discipline genes (89-90%) — the n=1 differentiation was noise.

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

> **n=3 update:** Verify dropped from 97.3% (n=1) → 92.5% (n=2) → **89.2%** (n=3). Same pattern: T2 (68%), T5 (70%), T8 (72%), T1 (81%). The n=1 table above is preserved for historical context.

**Findings:**

1. **Verification scored 97.3% at n=1, 92.5% at n=2, and 89.2% at n=3.** Same universal decline as every other gene. T2 collab-server (93→75→68%), T5 task-queue (96→77→70%), T8 analytics-dashboard (93→82→72%). T1 time-tracker also softened to 81%. Still beats vanilla (85.6%) by 3.6 points at $0.96/task.

2. **Minimal overhead.** 33-51 turns per task — barely more than vanilla Claude Code (~24). The skill is a checkpoint, not a workflow change. The agent implements freely and verifies at the end.

3. **The mechanism is simple.** The agent already *can* verify — it just doesn't always bother. The skill forces it to run `npm test`, `npm run build`, and `npm run lint` fresh and read the output before stopping. This catches issues the agent would otherwise ship.

4. **Verify Sonnet (91.6%) beats Verify Opus (89.2%).** Same pattern as TDD — Sonnet's consistency outperforms Opus's higher variance on complex tasks. Sonnet beats Opus on T2 (+13pp), T5 (+11pp), T1 (-2pp). At $0.72/task vs $0.96, Sonnet is both better and cheaper.

**Implication:** The single most cost-effective intervention is telling the agent "you may not claim completion without running verification and reading the output." This should be the default system prompt addition for any agentic coding tool.

#### Skill-Guided Code Review: Requesting Review via Skill

**Hypothesis:** The requesting-code-review skill, which guides the agent through committing, running `conclave consensus --mode=code-review`, and addressing findings, produces better outcomes than either hardcoded review instructions (Conclave Review) or no review at all (vanilla Claude Code).

**Setup:** Claude Code Opus with the requesting-code-review skill forcibly invoked. The agent implements freely, then must invoke the skill which guides it to commit, run multi-agent consensus code review (Claude + Gemini + Codex), and fix high/medium priority findings. Uses the conclave Docker image for access to the `conclave` binary. Run across all 11 tasks.

| Task | Category | Skill Review | Claude Code | Delta |
| --- | --- | ---: | ---: | ---: |
| **T1** time-tracker | greenfield/simple | 83.9% (n=3) | 82.9% (n=3) | +1.0 |
| **T2** collab-server | greenfield/complex | 79.4% (n=3) | 54.1% (n=3) | +25.3 |
| **T3** fts-search | features/medium | 100% (n=3) | 100% (n=3) | 0.0 |
| **T4** phantom-invoice | bugfix/medium | 99.4% (n=3) | 98.3% (n=3) | +1.1 |
| **T5** task-queue | marathon | 83.0% (n=3) | 62.0% (n=3) | +21.0 |
| **T6** monorepo-disaster | recovery | 100% (n=3) | 100% (n=3) | 0.0 |
| **T7** plugin-marketplace | greenfield/complex | 96.4% (n=3) | 91.8% (n=3) | +4.6 |
| **T8** analytics-dashboard | greenfield/complex | 76.9% (n=3) | 56.4% (n=3) | +20.5 |
| **T9** ssg-toolkit | features/complex | 100% (n=3) | 100% (n=3) | 0.0 |
| **T10** ecommerce-backend | greenfield/complex | 96.5% (n=3) | 95.6% (n=3) | +0.9 |
| **T11** debug-nightmare | bugfix/hard | 100% (n=3) | 100% (n=3) | 0.0 |
| **Mean** | | **92.3%** | **85.6%** | **+6.7** |

**Findings:**

1. **Skill Review dropped to 92.3% at n=3 (was 97.0% at n=2).** Same universal decline pattern. T1 (83.9%), T2 (79.4%), T5 (83.0%), T8 (76.9%) all regressed. Still beats vanilla (85.6%) by 6.7 points but is mid-tier among discipline genes.

2. **Review + Keys (94.1%) pulled ahead.** The multi-provider consensus review variant outperforms pure skill review at n=3. This is the one area where the consensus binary seems to help — but the margin is small and may be noise.

3. **Expensive for the tier.** $2.10/task mean — one of the most expensive contender among discipline genes. Self-Review Opus achieves 93.7% at $1.26 with no infrastructure at all.

4. **The review gene is robust across delivery mechanisms.** At n=3, skill-guided (92.3%), +keys (94.1%), and system-prompt self-review (93.7%) cluster within 1.8 points. The common thread: pausing to examine your work before claiming done.

**The multi-trial hierarchy (n=3):** v6 Opus (95.2%) > TDD Sonnet (94.5%) > Review+Keys (94.1%) > Self-Review Opus (93.8%) > Brainstorm (93.3%) > v6 Sonnet (92.8%) > Brainstorm Pure (92.8%) > Review Pure (92.5%) > Skill Review (92.3%) > Verify Sonnet (91.6%) > Debug (90.7%) > Review+Verify (90.2%) > Plans (89.6%) > TDD Opus (89.6%) > Verify (89.2%) > Vanilla (85.6%). Every gene dropped 3-5 points from n=2 to n=3. The "stable" entries (Brainstorm, Review, Self-Review at 97%+) were not actually stable — they regressed like everything else. The gap from vanilla to best discipline narrowed from 12pp to 10pp.

#### Brainstorming: Consensus Design Exploration

**Hypothesis:** Having multiple AI models collaboratively explore the design space before coding — asking and answering architecture questions via consensus — produces better implementations than jumping straight to code.

**Setup:** Claude Code Opus with the brainstorming skill forcibly invoked in autopilot mode. The skill's autopilot uses `conclave consensus --mode=general-prompt` to answer each design question (database choice, API style, component architecture, etc.) via three-model consensus (Claude + Gemini + Codex). The agent works through architecture, components, data flow, error handling, and testing, writes a design document, then implements. Run across all 11 tasks. One T1 trial pruned (coverage infrastructure failure — `coverage-summary.json` not generated).

| Task | Category | Brainstorm | Claude Code | Delta |
| --- | --- | ---: | ---: | ---: |
| **T1** time-tracker | greenfield/simple | 94.1% (n=3) | 82.9% (n=3) | +11.2 |
| **T2** collab-server | greenfield/complex | 82.0% (n=3) | 54.1% (n=3) | +27.9 |
| **T3** fts-search | features/medium | 100% (n=3) | 100% (n=3) | 0.0 |
| **T4** phantom-invoice | bugfix/medium | 99.4% (n=3) | 98.3% (n=3) | +1.1 |
| **T5** task-queue | marathon | 82.2% (n=3) | 62.0% (n=3) | +20.2 |
| **T6** monorepo-disaster | recovery | 100% (n=3) | 100% (n=3) | 0.0 |
| **T7** plugin-marketplace | greenfield/complex | 97.5% (n=3) | 91.8% (n=3) | +5.7 |
| **T8** analytics-dashboard | greenfield/complex | 81.1% (n=3) | 56.4% (n=3) | +24.7 |
| **T9** ssg-toolkit | features/complex | 100% (n=3) | 100% (n=3) | 0.0 |
| **T10** ecommerce-backend | greenfield/complex | 96.5% (n=3) | 95.6% (n=3) | +0.9 |
| **T11** debug-nightmare | bugfix/hard | 93.1% (n=3) | 100% (n=3) | -6.9 |
| **Mean** | | **93.3%** | **85.6%** | **+7.7** |

**Findings:**

1. **Brainstorming dropped to 93.3% at n=3 (was 97.4% at n=2).** Previously appeared stable but regressed like every other gene when more trials were added. Still in the top tier but no longer clearly #1 on standard tasks. T3 and T9 hold at 100%. T11 dropped to 93.1% on the third trial.

2. **Biggest gains on complex greenfield and marathon.** T2 collab-server (+27.9), T8 analytics-dashboard (+24.7), and T5 marathon (+20.2) benefit most from consensus-driven design exploration. The multi-model design discussion surfaces architecture choices the solo agent might miss.

3. **Good cost/performance ratio.** $1.43/task mean — cheaper than Review ($2.10) and TDD ($1.84). The autopilot consensus calls add overhead but the agent doesn't need as many implementation turns when it has a solid design to follow.

4. **T8 showed the biggest brainstorm gain at n=3.** Brainstorm (81.1%) vs vanilla (56.4%) — a +24.7 point improvement on analytics-dashboard, now the single largest delta. Design exploration matters most when the challenge IS architecture.

5. **Divergent exploration vs convergent discipline.** Brainstorming is the first "divergent" gene tested — it opens up the design space before narrowing. All previous top genes (Review, TDD, Verify) are "convergent" — they check work after implementation. Both approaches work, through different mechanisms.

**The multi-trial picture:** At n=3, every discipline gene continues to drop: Brainstorm 97.4%→93.3%, Review 97.0%→92.3%, Self-Review 96.8%→93.8%, TDD Opus 92.8%→89.6%, Verify 92.5%→89.2%, Plans 92.1%→89.6%. The "stable" entries (Brainstorm, Review, Self-Review) that held at n=2 regressed like everything else at n=3. The gap from vanilla (85.6%) to best discipline (95.2% v6 Opus) is now ~10 points. The convergence trend suggests the true steady-state gap may be even smaller.

#### Gene Stacking: Review + Verify (Diminishing Returns)

**Hypothesis:** Stacking Review with Verify should push past either alone. Review catches bugs via consensus, Verify ensures nothing ships unchecked — complementary mechanisms.

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

1. **Stacking doesn't help — it slightly hurts.** Review + Verify (90.2% at n=3) scores no better than either gene alone (Verify 89.2%, Review 92.3%). The n=1 reading of 97.2% was inflated like all other genes. Two discipline checkpoints are not additive — the stacked version is within noise of the component genes.

2. **The marathon tells the story.** T5 at n=3: Review+Verify (73.7%) ≈ Stacked (72.6%) vs Review alone (83.0%). The extra verification cycle after an already-thorough review adds turns without catching anything new, and the longer session may introduce regression.

3. **T8 converged downward.** Review+Verify (65.2%), Stacked (56.0%) — both worse than most single genes. The hardest task isn't about discipline, it's about implementation complexity.

4. **More expensive for less.** $2.21/task for Review+Verify — the most expensive standard approach at n=3, and the score (90.2%) doesn't justify it.

5. **This mirrors the Double Review finding.** The earlier ablation showed consensus adds nothing on top of self-review. Here, verification adds nothing on top of code review. **One quality checkpoint is sufficient. Adding a second doesn't compound.**

**Implication:** The ~95% standard ceiling appears to be the practical limit with current single-session approaches. v6's task-aware routing gets closest by picking the right single checkpoint per task type rather than stacking multiple checkpoints.

#### System Prompt Self-Review: No Skills, No Plugins, Just Instructions

**Hypothesis:** The ~97% top-tier scores require skill infrastructure (plugins, conclave binary, consensus protocols). A well-worded system prompt telling the agent "verify, commit, review your diff, fix issues" can't match actual skill-guided workflows.

**Setup:** Vanilla Claude Code Opus with NO plugins, NO skills, NO conclave binary — just `thunderdome/claude-code:latest` (not the conclave image). The only addition is a system prompt instructing the agent to: (1) implement, (2) run full verification (test/build/lint), (3) commit, (4) review its own diff with `git diff HEAD~1`, (5) fix any issues found, (6) repeat until clean. Run across all 11 tasks.

| Task | Category | Self-Review (Opus) | Claude Code | Delta |
| --- | --- | ---: | ---: | ---: |
| **T1** time-tracker | greenfield/simple | 95.0% (n=2) | 82.9% (n=3) | +12.1 |
| **T2** collab-server | greenfield/complex | 81.0% (n=3) | 54.1% (n=3) | +26.9 |
| **T3** fts-search | features/medium | 100% (n=3) | 100% (n=3) | 0.0 |
| **T4** phantom-invoice | bugfix/medium | 99.4% (n=3) | 98.3% (n=3) | +1.1 |
| **T5** task-queue | marathon | 85.6% (n=3) | 62.0% (n=3) | +23.6 |
| **T6** monorepo-disaster | recovery | 100% (n=3) | 100% (n=3) | 0.0 |
| **T7** plugin-marketplace | greenfield/complex | 96.5% (n=3) | 91.8% (n=3) | +4.7 |
| **T8** analytics-dashboard | greenfield/complex | 77.4% (n=3) | 56.4% (n=3) | +21.0 |
| **T9** ssg-toolkit | features/complex | 100% (n=3) | 100% (n=3) | 0.0 |
| **T10** ecommerce-backend | greenfield/complex | 96.4% (n=3) | 95.6% (n=3) | +0.8 |
| **T11** debug-nightmare | bugfix/hard | 100% (n=3) | 100% (n=3) | 0.0 |
| **Mean** | | **93.7%** | **85.6%** | **+8.1** |

**Findings:**

1. **Self-Review Opus dropped to 93.7% at n=3 — still the best free option.** Down from 96.8% at n=2, following the universal decline pattern. T2 (81%), T5 (86%), T8 (77%) are the usual variance killers. But at n=3, SR Opus is still #4 standard (behind v6 Opus 95.2%, TDD Sonnet 94.5%, Review+Keys 94.1%) and costs $1.26/task with no plugins or infrastructure.

2. **The gap that matters is vanilla vs discipline, not skill vs no-skill.** Vanilla Claude Code scores 85.6%. Adding "verify, commit, review your diff" to the system prompt jumps to 93.7% — an 8.1 point improvement for free. All the skill infrastructure fights over the remaining 1.5 points.

3. **Self-Review Sonnet collapsed to 85.5% at n=3.** This is the biggest single correction in the study — down from 97.1% at n=2. T10 ecommerce (45%), T9 ssg (77%), T3 fts (87%) all cratered on added trials. Sonnet without structured skill routing is unreliable. The finding that "Sonnet matches Opus on self-review" was an n=2 artifact. With structured skills (v6 Sonnet 92.2%, TDD Sonnet 94.5%), Sonnet is competitive; with only a system prompt, it's not.

4. **Cost is mid-tier.** $1.26/task for Opus — cheaper than Review ($2.10), TDD ($1.84), and Brainstorm ($1.43), but more than Verify ($0.96) and Plans ($1.06). The self-review loop adds turns but no external API calls.

5. **Still reframes the study.** The system prompt baseline remains the simplest high-performing approach. Its 93.7% Opus mean is competitive with all skill-based genes except v6 and TDD Sonnet. The instruction is what matters; the infrastructure is optional — but structured skills do add ~1.5 points of stability.

**Implication:** The single most impactful change to any agentic coding tool is adding "verify your work, commit, review your diff, fix issues, repeat until clean" to the system prompt. This is free, requires no infrastructure, and captures ~90% of the benefit of elaborate skill-based approaches. But the n=3 data shows structured skill routing (v6) adds genuine stability that a bare system prompt doesn't.

#### Conclave Binary Effect: Pure Superpowers vs Conclave Consensus

**Hypothesis:** The brainstorming and code review skills perform better when backed by the conclave consensus binary (multi-agent consensus via `conclave consensus`) than when the agent works through the same skill process alone. And multi-provider consensus (Claude + Gemini + Codex) outperforms Claude-only consensus.

**Setup:** Three-way comparison for both brainstorm and code review skills, each using identical skill text from obra/superpowers:

- **Pure Superpowers** — `thunderdome/superpowers:latest` image, NO conclave binary. Agent works through the skill process autonomously (brainstorm) or via Task tool subagent (review).
- **Conclave, no keys** — `thunderdome/conclave:latest` with `conclave` binary but no Gemini/OpenAI API keys. Consensus calls fall back to Claude-only.
- **Conclave + keys** — `thunderdome/conclave:latest` with `conclave` binary AND full API keys (Anthropic + OpenAI + Gemini). True multi-provider consensus.

Each variant run across all 11 tasks with 2 trials (22 trials per variant, 88 total new trials for the pure and +keys variants).

| Variant | Brainstorm | Review |
| --- | ---: | ---: |
| **Pure Superpowers** (no binary) | **92.3%** (n=29, $0.89/task) | **92.5%** (n=33, $1.95/task) |
| **Conclave + keys** (multi-provider) | 91.6% (n=33, $1.46/task) | 94.1% (n=33, $1.77/task) |
| **Conclave, no keys** (Claude-only) | 93.3% (n=33, $1.43/task) | 92.3% (n=33, $2.10/task) |

Per-task breakdown (Brainstorm):

| Task | Pure | + Keys | No Keys |
| --- | ---: | ---: | ---: |
| **T1** time-tracker | 96.7% | 75.8% | 94.1% |
| **T2** collab-server | 80.2% | 79.4% | 82.0% |
| **T3** fts-search | 86.7% | 100% | 100% |
| **T4** phantom-invoice | 93.2% | 99.4% | 99.4% |
| **T5** task-queue | 95.0% | 80.3% | 82.2% |
| **T6** monorepo-disaster | 94.5% | 100% | 100% |
| **T7** plugin-marketplace | 99.0% | 96.0% | 97.5% |
| **T8** analytics-dashboard | 79.2% | 79.3% | 81.1% |
| **T9** ssg-toolkit | 100% | 100% | 100% |
| **T10** ecommerce-backend | 96.8% | 97.5% | 96.5% |
| **T11** debug-nightmare | 100% | 100% | 93.1% |

**Findings:**

1. **All three variants converged at n=3.** With more trials, the 1.4pp spread at n=2 shrunk further. Brainstorm: No Keys (93.3%) > Pure (92.3%) > +Keys (91.6%). Review: +Keys (94.1%) > Pure (92.5%) ≈ No Keys (92.3%). The ordering shuffled between brainstorm and review — no variant consistently wins.

2. **Multi-provider consensus (Claude + Gemini + Codex) doesn't beat Claude-only consensus.** The +keys variant is best for review (94.1%) but worst for brainstorm (91.6%). Adding Gemini and Codex to the consensus panel doesn't systematically improve quality — it's noise.

3. **The skill TEXT is the value driver, not the consensus mechanism.** The brainstorming skill's structured design process (architecture, components, data flow, error handling, testing strategy) forces the agent to think before coding. Whether design questions are answered by multi-model consensus, single-model consensus, or the agent's own reasoning makes no measurable difference. All three variants land within 2pp of each other.

4. **Pure superpowers is the cheapest.** $0.89/task for brainstorm (vs $1.46 with keys), $1.95/task for review (vs $1.77 — keys is cheaper on review). No external API dependencies, no conclave binary, no consensus overhead.

**Bottom line:** Multi-agent consensus for design and review decisions is noise, not signal. The three variants are statistically indistinguishable at n=3. The conclave binary and multi-provider API keys are unnecessary.

#### Model Ablation: Sonnet 4.6 vs Opus 4.6 Across Top Approaches

**Hypothesis:** The ~97% top-tier scores require Opus 4.6 ($15/MTok input, $75/MTok output). Sonnet 4.6 (~5x cheaper) can't match it even with the same system prompts.

**Setup:** Four top-performing approaches — TDD (Superpowers), Brainstorm (Conclave), Verify (Superpowers), and Self-Review (system prompt only) — each run with identical Docker images, system prompts, and flags, but with `--model claude-sonnet-4-6` instead of `claude-opus-4-6`. Each Sonnet variant run across all 11 tasks with 2 trials (22 trials per approach, 88 total new trials). Note: Brainstorm Sonnet uses the conclave binary (Claude-only consensus, no API keys); the binary was later shown to have no effect (see Conclave Binary Effect ablation).

| Approach | Opus 4.6 | Sonnet 4.6 | Delta | Cost (Opus → Sonnet) |
| --- | ---: | ---: | ---: | ---: |
| **TDD** | 89.5% (n=30) | **94.5%** (n=44) | **+5.0** | $1.84 → $1.55 (16% cheaper) |
| **Brainstorm** | 93.3% (n=33) | 90.5% (n=30) | -2.8 | $1.43 → $0.62 (57% cheaper) |
| **Verify** | 89.2% (n=33) | 91.6% (n=33) | +2.4 | $0.96 → $0.72 (25% cheaper) |
| **Self-Review** | 93.7% (n=32) | 85.5% (n=29) | -8.2 | $1.26 → $0.62 (51% cheaper) |

Per-task breakdown for **TDD (Sonnet vs Opus at n=3)**:

| Task | Category | TDD Sonnet | TDD Opus | Delta |
| --- | --- | ---: | ---: | ---: |
| **T1** time-tracker | greenfield/simple | 95.8% | 94.5% | +1.3 |
| **T2** collab-server | greenfield/complex | 85.4% | 70.9% | +14.5 |
| **T3** fts-search | features/medium | 100% | 100% | 0.0 |
| **T4** phantom-invoice | bugfix/medium | 99.6% | 92.6% | +7.0 |
| **T5** task-queue | marathon | 88.4% | 77.4% | +11.0 |
| **T6** monorepo-disaster | recovery | 100% | 94.5% | +5.5 |
| **T7** plugin-marketplace | greenfield/complex | 96.5% | 95.0% | +1.5 |
| **T8** analytics-dashboard | greenfield/complex | 85.0% | 70.3% | +14.7 |
| **T9** ssg-toolkit | features/complex | 100% | 100% | 0.0 |
| **T10** ecommerce-backend | greenfield/complex | 94.5% | 98.3% | -3.8 |
| **T11** debug-nightmare | bugfix/hard | 93.8% | 91.8% | +2.0 |
| **Mean** | | **94.5%** | **89.5%** | **+5.0** |

**Findings:**

1. **Sonnet + TDD dominates Opus + TDD by 5.0 points at n=3.** Sonnet (94.5%) vs Opus (89.5%) with the same TDD methodology — the gap persists across trial counts. It's concentrated on complex tasks: T2 (+14.5), T8 (+14.7), T5 (+11.0). Sonnet's consistency outperforms Opus's higher variance on exactly the tasks that matter most.

2. **Sonnet beats Opus on TDD and Verify; Opus wins on Brainstorm and Self-Review.** At n=3: TDD (+5.0pp Sonnet), Verify (+2.4pp Sonnet), Brainstorm (-2.8pp Opus wins), Self-Review (-8.2pp Opus wins). The pattern is clear: structured rigid methodologies (TDD, Verify) favor Sonnet; flexible creative approaches (Brainstorm, Self-Review) favor Opus. Self-Review Sonnet's 85.5% collapse is the biggest n=3 correction — bare system prompts need Opus-level reasoning.

3. **Sonnet + TDD is the Pareto-optimal standard configuration.** 94.5% at $1.55/task — highest standard score. But v6 Opus (95.2%, $2.19) is technically higher, and v6 Sonnet (92.2%, $0.84) is much cheaper. The Pareto frontier depends on your cost tolerance.

4. **The cost story varies by approach.** Sonnet saves 16-57% depending on the approach. But the score tradeoff isn't uniform — Self-Review Sonnet saves 51% but loses 8.2pp, while TDD Sonnet saves 16% and gains 5.0pp. Choosing the right methodology matters more than choosing the model.

**Implication:** The optimal configuration depends on the task mix. For standard tasks with rigid structure, Sonnet + TDD (94.5%) dominates. For creative/greenfield tasks, Opus + Brainstorm (93.3%) is better. Self-Review's collapse on Sonnet (85.5%) proves that bare system prompts need Opus — structured skill routing is what makes Sonnet competitive.

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

> **n=3 update:** Plans dropped from 96.9% (n=1) → 92.1% (n=2) → **89.6%** (n=3). Same pattern: T2 (67%), T5 (72%), T8 (73%), T1 (90%). The n=1 table above is preserved for historical context.

**Findings:**

1. **Planning scored 96.9% at n=1, 92.1% at n=2, and 89.6% at n=3.** Same universal decline. T2 collab-server (91→59→67%), T5 task-queue (89→72%), T8 analytics-dashboard (92→71→73%). Still beats vanilla (85.6%) by 4.0 points at $1.06/task.

2. **Biggest gains on complex greenfield and marathon.** T2 collab-server (+13.3) and T1 time-tracker (+6.9) benefit most from upfront architecture thinking. But the gains shrink at n=3 as both Plans and baseline converge.

3. **Good cost profile.** $1.06/task mean — cheaper than TDD ($1.84), Review ($2.10), and Brainstorm ($1.43). Planning adds turns (17-54 per task) but fewer than TDD's red-green-refactor cycle.

4. **The plan is overhead on easy tasks.** T3, T9 remain at 100%. T6 softened to 95% but near-perfect. Writing a plan for a straightforward bugfix adds time without benefit.

**The hierarchy of discipline genes (all at n=3):** v6 Opus (95.2%) > TDD Sonnet (94.5%) > Review+Keys (94.1%) > Self-Review Opus (93.7%) > Brainstorm (93.3%) >> Review Pure (92.5%) > Skill Review (92.3%) > Debug (90.7%) > Review+Verify (90.2%) ≈ Plans (89.6%) ≈ TDD Opus (89.5%) ≈ Verify (89.2%) ≈ Stacked (88.8%). The n=1 "~97% cluster" has spread into a 6-point range (89-95%). The top tier requires either structured skill routing (v6) or model-appropriate methodology (TDD+Sonnet). The bottom tier (~89%) is all single-gene Opus approaches — their n=1 readings were inflated.

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

**Standard results** (from earlier runs, n=29 across T1-T11): 85.2% mean, $0.47 avg cost.

| Task | Headless | Agent Teams | Delta |
| --- | ---: | ---: | ---: |
| **T1** time-tracker | 94.9% (n=3) | 96.6% (n=9) | +1.7 |
| **T5** task-queue | 87.3% (n=2) | 56.4% (n=8) | -30.9 |
| **T7** plugin-marketplace | 95.1% (n=2) | 94.6% (n=3) | -0.5 |
| **T8** analytics-dashboard | 89.6% (n=2) | 89.3% (n=2) | -0.3 |

**Hard results** (n=2 per task, 17 total trials): **88.1% hard mean**, $3.93 avg cost.

| Task | Agent Teams | Claude Code | Delta |
| --- | ---: | ---: | ---: |
| **T12** constraint-scheduler | 88.4% (n=3) | 60.0% | +28.4 |
| **T13** structural-merge | 89.4% | 59.0% | +30.4 |
| **T14** financial-ledger | 100% | 100% | 0 |
| **T15** permission-maze | **78.6%** | 69.6% | +9.0 |
| **T16** reactive-spreadsheet | 89.8% | 91.1% | -1.3 |
| **T17** circuit-debugger | 92.2% | 88.9% | +3.3 |
| **T18** beam-splitter | 80.1% | 69.2% | +10.9 |
| **T19** factory-reset | 86.0% | 78.6% | +7.4 |

**Findings:**

1. **Agent Teams hurts on the marathon task.** T5 dropped from 87.3% (headless) to 56.4% (agent teams, n=8). The high trial count reveals significant variance — some trials succeed (~92%) while others catastrophically fail. The task's 12 sequential phases can't truly parallelize, and teammates stepping on each other causes failures.

2. **No effect on simpler tasks.** T1, T7, and T8 show noise-level deltas. The agent often decides not to spawn teammates on tasks that don't benefit from parallelization.

3. **Agent Teams shines on hard tasks.** 88.1% hard mean places Agent Teams tied for 5th in the hard grid (with SR Opus). The biggest gains are on T12 (+28.4) and T13 (+30.4), where parallel teammates can independently tackle separate modules. Agent Teams also leads all orchestrators on T15 permission-maze (78.6%).

4. **High cost for hard tasks.** $3.93 avg per hard trial makes Agent Teams the second-most expensive on the hard grid (after Factory Reset's $10.80 per-task average). The parallel teammates consume tokens aggressively — T17 and T19 each cost ~$8-11.

5. **Supports H5 (partially updated).** Parallelization helps on decomposable tasks (T12-T13) and hurts on sequential ones (T5). This confirms hypothesis H5 but also shows agent teams can identify which tasks benefit from parallelization.

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

Run with both Sonnet 4.6 and Opus 4.6 across all 11 tasks, 3 trials each (66 total). Uses `CONCLAVE_NON_INTERACTIVE=1` which routes brainstorming to single-agent Autopilot mode.

| Task | Category | v6 Sonnet | v6 Opus | TDD Sonnet | Self-Review | Claude Code |
| --- | --- | ---: | ---: | ---: | ---: | ---: |
| **T1** time-tracker | greenfield/simple | 98.5% | 94.3% | 95.8% | 95.0% | 82.9% |
| **T2** collab-server | greenfield/complex | 83.4% | 86.6% | 85.4% | 81.0% | 54.1% |
| **T3** fts-search | features/medium | 86.7% | 100% | 100% | 100% | 100% |
| **T4** phantom-invoice | bugfix/medium | 93.2% | 99.4% | 99.6% | 99.4% | 98.3% |
| **T5** task-queue | marathon | 94.4% | 85.1% | 88.4% | 85.6% | 62.0% |
| **T6** monorepo-disaster | recovery | 94.5% | 100% | 100% | 100% | 100% |
| **T7** plugin-marketplace | greenfield/complex | 98.1% | 96.4% | 96.5% | 96.5% | 91.8% |
| **T8** analytics-dashboard | greenfield/complex | 82.3% | 87.2% | 85.0% | 77.4% | 56.4% |
| **T9** ssg-toolkit | features/complex | 100% | 100% | 100% | 100% | 100% |
| **T10** ecommerce-backend | greenfield/complex | 97.8% | 98.0% | 94.5% | 96.4% | 95.6% |
| **T11** debug-nightmare | bugfix/hard | 91.8% | 100% | 93.8% | 100% | 100% |
| **Mean** | | **92.2%** | **95.2%** | **94.5%** | **93.7%** | **85.6%** |
| **Avg Cost** | | $0.84 | $2.19 | $1.55 | $1.26 | $0.97 |

**Findings:**

1. **v6 Opus is #1 standard at n=3.** Opus (95.2%, n=33) leads all orchestrators on standard tasks. Sonnet (92.2%, n=29) dropped more — v6 Sonnet has several soft spots at n=3: T3 (87%), T4 (93%), T6 (95%), T11 (92%) all came off their 100% n=2 readings. The task classifier helps but can't fully compensate for Sonnet's lower consistency on non-trivial tasks.

2. **Opus now beats Sonnet on v6 by 3.0pp.** At n=2, v6 Sonnet (98.1%) and Opus (98.0%) were identical. At n=3, Opus (95.2%) pulls ahead as Sonnet drops further (92.2%). The cost difference remains: Opus ($2.19) vs Sonnet ($0.84) — Sonnet is still 2.6x cheaper, so the tradeoff depends on whether you value the 3pp or the $1.35 savings.

3. **The plugin's advantage over a bare system prompt is now clearer.** v6 Opus (95.2%) vs Self-Review Opus (93.7%) — a 1.5pp gap at n=3. v6 Sonnet (92.2%) vs Self-Review Sonnet (85.5%) — a 6.7pp gap. The structured skill routing matters much more for Sonnet, where it provides scaffolding the model needs.

4. **Biggest improvement: complex greenfield tasks.** T2 (+32.5 vs vanilla), T8 (+30.8), T5 (+23.1). The brainstorming → TDD routing gives greenfield tasks both upfront design thinking and implementation discipline.

5. **The three v6 changes compound.** Individual genes at n=3 cluster between 89-94%. v6 Opus breaks above at 95.2% by combining the right gene for each task type. Task-aware routing > one-size-fits-all discipline.

6. **Consensus demotion was the right call.** The Conclave Binary Effect study showed consensus adds nothing. Making consensus opt-in removes the overhead without losing any benefit.

**Hard benchmark results (T12-T19):**

v6 was run on all 8 hard benchmarks with 2 trials each (32 additional trials). Results in the [Hard Benchmarks table](#hard-benchmarks-t12-t19) above.

- **v6 Opus (87.8%)** lands within 1.9 points of the leader (TDD Opus 89.7%) on the hard suite. Holds the highest individual scores on T17 circuit-debugger (90.3%) and T18 beam-splitter (94.3%). T12 was affected by a validation container hang (trial 1: hidden_tests=0, trial 2: 94.7%).
- **v6 Sonnet (87.0%)** is the standout cost-performance result. TDD Sonnet scored 62.9% on the same tasks — crashing on 5 of 6 reasoning/hard trials. v6 Sonnet completed all 16 trials with 100% pass rate. At $0.80/trial, v6 Sonnet is the best cost-adjusted hard benchmark orchestrator — matching Self-Review Opus (87.5%) at 56% of the cost.
- **v6 Sonnet's weakness is T17 circuit-debugger (73.3%).** This task requires discovering that simulation caps at ~25% accuracy and switching to structural analysis — a reasoning leap that Opus handles (90.3%) but Sonnet struggles with. On all other tasks, v6 Sonnet is within 5 points of v6 Opus.

**Implication:** The optimal plugin architecture is not "more consensus" or "more checkpoints" — it's intelligent routing to the right methodology for each task type, with a consistent verification gate across all paths. Conclave v6 validates this: v6 Opus (95.2%) is the #1 standard orchestrator at n=3, beating every single-gene approach. The v6 framework also lifts Sonnet from 85.5% (bare system prompt) to 92.2% (with plugin) — the largest Sonnet uplift from any intervention. On hard benchmarks, v6 remains competitive across both models.

#### Planned Ablations

| Ablation | A | B | Gene Isolated | Status |
|---|---|---|---|---|
| Parallelism | Gas Town | Gas Station | Mayor + parallel polecats + refinery | Data exists (needs more trials) |
| Gas Station scaffolding | Gas Station | Claude Code + Headless | Git worktree + branch setup (gt prime discarded) | **Done — worktree matches Gas Station** |
| Git worktree isolation | Claude Code + Worktree | Claude Code | Bare clone + worktree (no Gas Town tooling) | **Done — 90.7% T5 (n=2), matches Gas Station** |
| Consensus review only | Conclave Review | Claude Code | Multi-agent code review (no skills) | **Done — +11.3 points** |
| Full skill pipeline | Full Conclave | Conclave Review | Brainstorm/plan/implement workflow | **Done — -2.0 points vs review-only (was -19 before data cleanup)** |
| Systematic debugging | Superpowers Debug | Claude Code | Four-phase debugging methodology | **Done — +5.1 points full-suite (90.7% at n=3, was 96.7% at n=2); original T11-only study was misleading** |
| Test-driven development | Superpowers TDD | Claude Code | Forced red-green-refactor cycle | **Done — Opus 89.5% at n=3 (was 92.8% n=2, 97.4% n=1); Sonnet 94.5% (n=44). T12-T19: Opus #1 at 89.7%, Sonnet last at 62.9%** |
| Verification before completion | Superpowers Verify | Claude Code | "No claims without fresh evidence" | **Done — Opus 89.2% at n=3 (was 92.5% n=2, 97.3% n=1); Sonnet 91.6% beats Opus** |
| Skill-guided code review | Conclave Skill Review | Claude Code | requesting-code-review skill + conclave consensus | **Done — 92.3% at n=3 (was 97.0% n=2)** |
| Writing plans | Superpowers Plans | Claude Code | Mandatory plan before implementation | **Done — 89.6% at n=3 (was 92.1% n=2, 96.9% n=1)** |
| Brainstorming | Conclave Brainstorm | Claude Code | Consensus design exploration (autopilot) | **Done — 93.3% at n=3 (was 97.4% n=2). Pure 92.3%, +keys 91.6%** |
| Gene stacking: Review + Verify | Review+Verify | Review / Verify | Two discipline checkpoints stacked | **Done — 90.2% at n=3 (was 91.9% n=2, 97.2% n=1; worse than either alone)** |
| System prompt self-review | Self-Review | Claude Code | "Verify, commit, review diff, fix" — no plugins | **Done — Opus 93.7% at n=3 (was 96.8% n=2). Sonnet collapsed to 85.5%** |
| Model ablation: Sonnet vs Opus | TDD/Brainstorm/Verify/Self-Review (Sonnet) | Same (Opus) | Cheap model + same system prompts | **Done — TDD Sonnet still #1 standard (94.5%). Sonnet wins on TDD/Verify, Opus wins on Brainstorm/Self-Review** |
| Consensus design review | Conclave Design | Claude Code | Pre-implementation multi-model architecture guidance | **Done — +16.2 points** |
| Self-review discipline | Double Review (no keys) | Claude Code | "Commit, review your diff, fix" in system prompt | **Done — ~+16 points (free, largest gene)** |
| Self-review + consensus | Double Review (keys) | Claude Code | Self-review + real multi-model consensus | **Done — ~+15.5 points (consensus adds nothing over self-review)** |
| Conclave binary effect | Conclave Brainstorm/Review (no keys, +keys) | Superpowers Brainstorm/Review | Multi-agent consensus binary + multi-provider | **Done — no effect at n=3: all three variants within 2pp (91.6-93.3% brainstorm, 92.3-94.1% review)** |
| Conclave v6 plugin | Conclave v6 (Sonnet + Opus) | TDD Sonnet / Self-Review | Task classifier + completion gate + consensus opt-in | **Done — v6 Opus #1 standard at n=3 (95.2%). v6 Sonnet 92.2%. T12-T19: Opus 87.8%, Sonnet 87.0%** |
| Mandatory skills | Conclave | Claude Code | Conclave plugin (TDD, debugging, planning) | Data exists (needs more trials) |
| Skill optionality | Conclave | Superpowers | Mandatory vs optional skill invocation | Data exists (needs more trials) |
| Metacognitive reframing | Metacog | Claude Code | Pre-implementation thinking skill | **Done — T1-T11 data exists; T12-T19: 82.6% (high variance, holds T19 high at 92.8%)** |
| Agent teams | Agent Teams | Claude Code | In-process teammate coordination | **Done — hurts T5 (-30.9), shines on hard (88.1%, +11 vs vanilla)** |
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
| **[Conclave](https://github.com/signalnine/conclave) v6 (Sonnet)** | Conclave plugin + Sonnet 4.6 | Same plugin, half the cost — 92.2% standard at $0.84/task (vs Opus 95.2% at $2.19) |
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
| **Conclave Review + Verify** | Claude Code + review + verify stacked | Gene stacking study — diminishing returns (90.2% at n=3, both genes combined) |
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
| **Conclave Brainstorm (Sonnet)** | Claude Code Sonnet + brainstorming skill | Sonnet + consensus design — 90.7% at $0.62/task |
| **Ralph Fresh** | Claude Code + fresh-context Ralph loop | Multi-iteration fresh context on same workspace |
| **Claude Code Worktree** | Claude Code + git worktree | Matches Gas Station — worktree adds isolation, not quality |
| **Verify (Sonnet)** | Claude Code Sonnet + verification skill | Sonnet + verification — 91.6% at $0.72/task |
| **Claude Code Headless** | Claude Code `-p` mode without skills | Headless baseline — no interactive user, no plugins |
| **Amplifier + ts-dev** | Amplifier + TypeScript bundle | LSP code intelligence, TS expert agent |
| **Aider (Cerebras)** | Aider + Cerebras gpt-oss-120b | Open-weight 120B MoE via Cerebras inference (~3K tok/s); single-pass diff edits |

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
- [ ] Ablation studies (gene isolation) — 18 done on T1-T11: ts-dev (no effect), consensus review (+11.3), full pipeline (-2 vs review-only), systematic debugging (+5.1 at n=3), TDD (+3.9 at n=3), verification (+3.6 at n=3), writing plans (+4.0 at n=3), skill-guided review (+6.7 at n=3), brainstorming (+7.7 at n=3), review+verify stacking (90.2% at n=3, diminishing returns), design review (+16.2), self-review (+8.1, free), self-review+consensus (consensus adds nothing), worktree matches Gas Station, agent teams (hurts on T5), branch (inconclusive), Ralph fresh-context (+15.6 on T5, top-tier), no-git (unstable), Conclave v6 plugin (Opus 95.2% #1, Sonnet 92.2%). **Universal n=3 finding: every gene continued to drop from n=2, converging toward 89-95% standard.** All scores are mechanical — rubric dropped.
- [ ] Run remaining orchestrators on T12-T19 hard suite
- [ ] Publish methodology paper

## License

TBD
