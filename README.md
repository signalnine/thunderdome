# Agentic Thunderdome

Two agents enter, one agent leaves.

A benchmarking framework that pits agentic coding orchestrators against standardized programming tasks and measures what matters: completion rate, token efficiency, cost, and correctness.

## Results

Composite scores across 19 tasks — the original 11-task standard suite (T1-T11) plus 8 hard benchmarks (T12-T19) spanning algorithmic, correctness, ambiguity, and reasoning challenges. Data includes 890 scored trials across 53 orchestrator variants (947 total including crash trials). All scoring is deterministic — no LLM judges, no rubric. Crash trials ($0 cost, <10s duration) are excluded from averages.

Most orchestrators have n=1 per task due to data loss during infrastructure migration. Scores reflect current corrected scoring pipeline (test parser fix + diff-capture fix).

### Leaderboard

Composite scores ranked by Overall (weighted average of Standard and Hard suite means). Gene ablation variants (testing individual features in isolation) are in a [separate table](#gene-ablation-variants). See [Contenders](#contenders) for architecture descriptions.

| Rank | Orchestrator | Standard | Hard | Overall | Trials | Avg Cost | Model |
|---:|---|---:|---:|---:|---:|---:|---|
| 1 | [**Conclave Review**](#contenders) | 91.8% | 84.5% | **88.7%** | 32 | $1.58 | Opus 4.6 |
| 2 | [Plans (Opus)](#contenders) | 86.8% | 90.7% | **88.5%** | 19 | $1.29 | Opus 4.6 |
| 3 | [Conclave v6 (Sonnet)](#contenders) | 87.4% | 88.9% | **88.0%** | 19 | $1.06 | Sonnet 4.6 |
| 4 | [Stacked](#contenders) | 86.3% | 87.6% | **86.9%** | 19 | $1.50 | Opus 4.6 |
| 5 | [GSD](#contenders) | 85.7% | 88.1% | **86.7%** | 19 | $1.06 | Opus 4.6 |
| 6 | [BMAD-METHOD](#contenders) | 85.3% | 88.1% | **86.5%** | 19 | $1.93 | Opus 4.6 |
| 7 | [Agent Teams](#contenders) | 85.7% | 87.0% | **86.3%** | 36 | $0.95 | Opus 4.6 |
| 8 | [Metacog](#contenders) | 88.3% | 81.1% | **85.3%** | 49 | $0.92 | Opus 4.6 |
| 9 | [Gas Station](#contenders) | 87.8% | 81.3% | **85.0%** | 49 | $0.85 | Opus 4.6 |
| 10 | [Conclave v6 (Opus)](#contenders) | 85.8% | 83.4% | **84.8%** | 57 | $1.98 | Opus 4.6 |
| 11 | [TDD (Opus)](#contenders) | 92.0% | 70.4% | **82.9%** | 24 | $2.35 | Opus 4.6 |
| 12 | [Crush GLM-5](#contenders) | 86.5% | 78.0% | **82.9%** | 19 | $0.76 | GLM-5 |
| 13 | [Self-Review (Opus)](#contenders) | 86.1% | 77.8% | **82.6%** | 19 | $1.23 | Opus 4.6 |
| 14 | [Brainstorm (Opus)](#contenders) | 87.9% | 75.0% | **82.5%** | 19 | $1.72 | Opus 4.6 |
| 15 | [Claude Code](#contenders) | 85.8% | 76.9% | **82.1%** | 32 | $0.61 | Opus 4.6 |
| 16 | [Verify (Opus)](#contenders) | 86.0% | 75.7% | **81.7%** | 19 | $0.94 | Opus 4.6 |
| 17 | [Gemini CLI](#contenders) | 79.7% | 80.2% | **79.9%** | 32 | $0.05 | Gemini 2.5 Flash |
| 18 | [Debug (Opus)](#contenders) | 84.6% | 70.0% | **78.4%** | 28 | $1.16 | Opus 4.6 |
| 19 | [Review + Verify](#contenders) | 83.5% | 71.2% | **78.3%** | 20 | $1.81 | Opus 4.6 |
| 20 | [Conclave (full)](#contenders) | 68.3% | 91.8% | **78.2%** | 20 | $1.00 | Opus 4.6 |
| 21 | [Superpowers](#contenders) | 66.4% | 88.8% | **75.9%** | 19 | $0.63 | Opus 4.6 |
| 22 | [Review (pure)](#contenders) | 78.7% | 69.2% | **74.7%** | 21 | $1.75 | Opus 4.6 |
| 23 | [Cerebras CLI](#contenders) | 79.2% | 66.0% | **73.7%** | 15 | $0.00 | gpt-oss-120b |
| 24 | [Cerebras CLI Ralph](#contenders) | 69.9% | 74.9% | **72.0%** | 25 | $0.00 | gpt-oss-120b |
| 25 | [Amplifier (Gemini 2.5 Flash)](#contenders) | 78.7% | 52.7% | **67.8%** | 26 | $0.01 | Gemini 2.5 Flash |
| 26 | [Gemini CLI Flash Lite Ralph](#contenders) | 56.6% | 71.2% | **62.7%** | 19 | $0.11 | Gemini 2.0 FL |
| 27 | [Gemini CLI Flash Lite](#contenders) | 64.9% | 54.5% | **60.5%** | 20 | $0.31 | Gemini 2.0 FL |
| 28 | [Amplifier (Gemini Flash)](#contenders) | 71.0% | 39.6% | **57.8%** | 20 | $0.01 | Gemini 2.0 Flash |

### Cost Efficiency

All orchestrators with Overall scores, sorted by cost. **Bold** = Pareto-optimal (no other orchestrator scores higher at equal or lower cost).

| Orchestrator | Overall | Avg Cost | Pareto |
|---|---:|---:|:---:|
| Cerebras CLI | 73.7% | $0.00 | |
| Cerebras CLI Ralph | 72.0% | $0.00 | |
| Amplifier (Gemini 2.5 Flash) | 67.8% | $0.01 | |
| Amplifier (Gemini Flash) | 57.8% | $0.01 | |
| **Gemini CLI** | **79.9%** | **$0.05** | **best <$0.61** |
| Gemini CLI Flash Lite Ralph | 62.7% | $0.11 | |
| Gemini CLI Flash Lite | 60.5% | $0.31 | |
| **Claude Code** | **82.1%** | **$0.61** | **best <$0.76** |
| Superpowers | 75.9% | $0.63 | |
| **Crush GLM-5** | **82.9%** | **$0.76** | **best <$0.85** |
| **Gas Station** | **85.0%** | **$0.85** | **best <$0.92** |
| **Metacog** | **85.3%** | **$0.92** | **best <$1.06** |
| Verify (Opus) | 81.7% | $0.94 | |
| Agent Teams | 86.3% | $0.95 | |
| Conclave (full) | 78.2% | $1.00 | |
| GSD | 86.7% | $1.06 | |
| **Conclave v6 (Sonnet)** | **88.0%** | **$1.06** | **best <$1.29** |
| Debug (Opus) | 78.4% | $1.16 | |
| Self-Review (Opus) | 82.6% | $1.23 | |
| **Plans (Opus)** | **88.5%** | **$1.29** | **best <$1.58** |
| Stacked | 86.9% | $1.50 | |
| **Conclave Review** | **88.7%** | **$1.58** | **best overall** |
| Brainstorm (Opus) | 82.5% | $1.72 | |
| Review (pure) | 74.7% | $1.75 | |
| Review + Verify | 78.3% | $1.81 | |
| BMAD-METHOD | 86.5% | $1.93 | |
| Conclave v6 (Opus) | 84.8% | $1.98 | |
| TDD (Opus) | 82.9% | $2.35 | |

The Pareto frontier: Gemini CLI ($0.05, 79.9%) → Claude Code ($0.61, 82.1%) → Crush GLM-5 ($0.76, 82.9%) → Gas Station ($0.85, 85.0%) → Metacog ($0.92, 85.3%) → v6 Sonnet ($1.06, 88.0%) → Plans ($1.29, 88.5%) → Conclave Review ($1.58, 88.7%). Crush GLM-5 offers 82.9% at $0.76/task with GLM-5 pricing ($1/1M input, $3.20/1M output). v6 Sonnet remains the paid sweet spot: 88.0% at $1.06/task — Opus-tier quality at Sonnet pricing.

### Gene Ablation Variants

Individual orchestrator "genes" tested in isolation — Claude Code with a single feature forced on. Ranked by Standard mean. Many now have hard-task data (marked with +). See [Ablation Studies](#ablation-studies) for detailed per-gene analysis.

| Rank | Variant | Standard | Hard | Overall | Trials | Avg Cost | Model |
|---:|---|---:|---:|---:|---:|---:|---|
| 1 | TDD (Opus) | 92.0% | 70.4% | **82.9%** | 24 | $2.35 | Opus 4.6 |
| 2 | Conclave Review | 91.8% | 84.5% | **88.7%** | 32 | $1.58 | Opus 4.6 |
| 3 | Brainstorm (Opus) | 87.9% | 75.0% | **82.5%** | 19 | $1.72 | Opus 4.6 |
| 4 | Plans (Opus) | 86.8% | 90.7% | **88.5%** | 19 | $1.29 | Opus 4.6 |
| 5 | Conclave v6 (Opus) | 85.8% | 83.4% | **84.8%** | 57 | $1.98 | Opus 4.6 |
| 6 | Conclave v6 (Sonnet) | 87.4% | 88.9% | **88.0%** | 19 | $1.06 | Sonnet 4.6 |
| 7 | Self-Review (Opus) | 86.1% | 77.8% | **82.6%** | 19 | $1.23 | Opus 4.6 |
| 8 | Verify (Opus) | 86.0% | 75.7% | **81.7%** | 19 | $0.94 | Opus 4.6 |
| 9 | Metacog | 88.3% | 81.1% | **85.3%** | 49 | $0.92 | Opus 4.6 |
| 10 | Claude Code (Opus) | 85.8% | 76.9% | **82.1%** | 32 | $0.61 | Opus 4.6 |
| 11 | Debug (Opus) | 84.6% | 70.0% | **78.4%** | 28 | $1.16 | Opus 4.6 |
| 12 | Review + Verify | 83.5% | 71.2% | **78.3%** | 20 | $1.81 | Opus 4.6 |
| 13 | Review (pure) | 78.7% | 69.2% | **74.7%** | 21 | $1.75 | Opus 4.6 |
| — | Conclave Review + Keys | 94.9% | — | — | 9 | $1.89 | Multi-provider |
| — | Conclave Double Review | 95.0% | — | — | 9 | $1.26 | Opus 4.6 |
| — | Conclave Design | 94.4% | — | — | 9 | $2.09 | Opus 4.6 |

### Hard Benchmarks (T12-T19)

Per-task breakdown for the 8 harder benchmarks — algorithmic complexity (T12-T13, T16), correctness constraints (T14), ambiguous requirements (T15), and deep reasoning where naive approaches fail at scale (T17-T19). Aggregate rankings are in the [leaderboard](#leaderboard) above.

27 orchestrators with hard-task data (n=1 per task unless noted), sorted by hard-suite mean. All gene ablation variants now have complete 8/8 hard task coverage.

| Orchestrator | Hard | T12 | T13 | T14 | T15 | T16 | T17 | T18 | T19 | n |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| Conclave (full) | **91.8%** | 97.7% | 95.6% | 100% | 79.3% | 94.3% | 85.3% | 90.0% | 92.2% | 8 |
| Plans (Opus) | **90.7%** | 95.1% | 92.2% | 100% | 77.7% | 90.4% | 91.4% | 89.2% | 89.6% | 8 |
| Conclave v6 (Sonnet) | **88.9%** | 87.1% | 95.1% | 100% | 76.1% | 91.9% | 81.4% | 88.7% | 91.0% | 8 |
| Superpowers | **88.8%** | 93.0% | 92.6% | 100% | 75.4% | 88.7% | 85.2% | 89.1% | 86.7% | 8 |
| BMAD-METHOD | **88.1%** | 90.7% | 94.0% | 100% | 62.2% | 93.4% | 84.2% | 90.9% | 89.5% | 8 |
| GSD | **88.1%** | 95.7% | 88.1% | 100% | 64.8% | 91.8% | 82.3% | 92.3% | 89.9% | 8 |
| Stacked | **87.6%** | 90.8% | 85.7% | 100% | 62.9% | 90.4% | 86.4% | 95.1% | 89.6% | 8 |
| Agent Teams | **87.0%** | 90.0% | 96.2% | 100% | 78.3% | 92.0% | 79.6% | 91.5% | 68.7% | 8 |
| Conclave Review | **84.5%** | 96.2% | 92.7% | 93.0% | 67.7% | 88.7% | 85.4% | 58.4% | 94.1% | 10 |
| Conclave v6 (Opus) | **83.4%** | 62.2% | 94.5% | 96.5% | 72.9% | 68.6% | 88.0% | 93.3% | 91.1% | 24 |
| Gas Station | **81.3%** | 89.7% | 56.7% | 100% | 69.7% | 86.7% | 80.9% | 75.8% | 90.9% | 16 |
| Metacog | **81.1%** | 90.0% | 58.5% | 100% | 61.1% | 91.4% | 83.2% | 76.9% | 87.8% | 16 |
| Gemini CLI | **80.2%** | 89.2% | 54.6% | 100% | 60.8% | 88.7% | 93.6% | 96.5% | 58.5% | 12 |
| Self-Review (Opus) | **77.8%** | 73.8% | 91.5% | 100% | 60.5% | 60.1% | 58.1% | 95.2% | 82.8% | 8 |
| Crush GLM-5 | **78.0%** | 58.5% | 88.3% | 100% | 69.9% | 90.3% | 62.9% | 60.0% | 94.4% | 8 |
| Claude Code | **76.9%** | 62.1% | 58.5% | 100% | 61.2% | 90.8% | 93.7% | 60.0% | 88.7% | 8 |
| Verify (Opus) | **75.7%** | 58.5% | 56.7% | 100% | 60.1% | 91.8% | 83.0% | 97.1% | 58.5% | 8 |
| Brainstorm (Opus) | **75.0%** | 58.0% | 95.3% | 100% | 58.5% | 93.6% | 81.4% | 20.0% | 93.0% | 8 |
| Cerebras CLI Ralph | **74.9%** | 81.1% | 40.6% | 100% | 80.5% | 82.3% | 34.2% | 95.1% | 85.7% | 8 |
| Review + Verify | **71.2%** | 61.5% | 92.5% | 84.2% | 78.2% | 20.0% | 52.8% | 93.1% | 87.4% | 9 |
| Gemini CLI Flash Lite Ralph | **71.2%** | 93.0% | 52.4% | 100% | 55.0% | 26.2% | 65.8% | 89.9% | 87.4% | 8 |
| TDD (Opus) | **70.4%** | 77.7% | 58.5% | 84.2% | 72.1% | 88.7% | 70.8% | 20.0% | 91.5% | 8 |
| Debug (Opus) | **70.0%** | 88.9% | 87.4% | 100% | 62.1% | 86.1% | 58.1% | 20.0% | 56.9% | 8 |
| Review (pure) | **69.2%** | 77.1% | 56.0% | 84.2% | 78.3% | 20.0% | 86.9% | 60.0% | 90.8% | 10 |
| Cerebras CLI | **66.0%** | — | 24.6% | 100% | 66.2% | 89.4% | 31.2% | — | 84.9% | 6 |
| Gemini CLI Flash Lite | **54.5%** | 66.2% | 30.3% | 100% | 64.6% | 36.2% | 21.5% | 66.2% | 50.8% | 8 |
| Amplifier (Gemini 2.5 Flash) | **52.7%** | 89.2% | 87.9% | 100% | 63.2% | 21.5% | 20.0% | 20.0% | 20.0% | 16 |
| Amplifier (Gemini Flash) | **39.6%** | 58.5% | 20.0% | 100% | 58.5% | 20.0% | 20.0% | 20.0% | 20.0% | 8 |

**Key findings from the hard suite:**

1. **Conclave Review leads overall at 88.7% — the strongest standard-task gene (91.8%) also performs well on hard tasks (84.5%).** Multi-agent consensus code review provides consistent quality improvement across both task types. With complete hard coverage, it overtook Plans for the #1 overall spot.

2. **Plans (Opus) is the hard-task champion among single genes (90.7%).** The writing-plans skill's structured upfront design outperforms every other single-gene variant on hard tasks. On standard tasks it's mid-tier (86.8%), but on hard tasks where architectural choices matter most, planning first pays off dramatically.

3. **Conclave (full) leads the hard grid at 91.8% but craters on standard tasks (68.3%).** The full mandatory skill pipeline — brainstorm → plan → implement → verify — produces excellent hard-task results but its overhead hurts on simple tasks. This is the most extreme standard/hard split in the leaderboard.

4. **Hard tasks differentiate orchestrators far more than standard tasks.** The standard-task spread among top-tier Opus variants is ~7 points (86-92%). On hard tasks, the spread is 52 points (39-92%). Hard benchmarks test whether the agent can discover novel algorithmic approaches rather than implement well-known patterns.

5. **T14 (financial-ledger) is universally solved.** Every orchestrator with full hard coverage scores 100%. This task is too easy and should be replaced.

6. **T15 (permission-maze) remains the hardest non-crashing task.** Scores range 58-80% — the deliberately ambiguous TASK.md exposes agents that make assumptions rather than exploring edge cases. Cerebras CLI Ralph surprisingly leads (80.5%), followed by Conclave full (79.3%) and Agent Teams (78.3%).

7. **Gemini CLI holds the highest individual task scores.** T17 circuit-debugger (93.6%) and T18 beam-splitter (96.5%) — Gemini excels at reasoning tasks where structural analysis beats brute-force simulation. At $0.05/task, it's by far the cheapest competitive option.

8. **Conclave v6 Sonnet matches Opus-tier quality at half the cost.** v6 Sonnet (88.9% hard, 87.4% standard, 88.0% overall) outperforms v6 Opus (83.4% hard, 85.8% standard, 84.8% overall at n=57) at $1.06/task vs $1.98. The task classifier + completion gate architecture benefits Sonnet more than Opus — structured routing compensates for Sonnet's lower baseline capability.

9. **Complete hard coverage resolved several rank surprises.** With 8/8 tasks filled in, TDD Opus jumped from 60.1% to 70.4% hard, Conclave Review from 72.1% to 84.5%, Brainstorm from 66.4% to 75.0%, and v6 from 71.1% to 78.8%. Incomplete data was systematically biased toward easier tasks.

### Key Findings

- **Conclave Review leads overall at 88.7%.** The consensus code review gene is the strongest single intervention, excelling on both standard (91.8%) and hard (84.5%) tasks
- **v6 Sonnet is the cost-efficiency champion.** 88.0% overall at $1.06/task — #3 on the leaderboard, outperforming its Opus counterpart (84.8%, $1.98 at n=57). The task classifier + completion gate architecture compensates for Sonnet's lower baseline, making structured routing more valuable on cheaper models
- **Plans is the hard-task champion (90.7%).** Plan-before-code produces the best hard-task scores of any single-gene variant, making it #2 overall (88.5%)
- **Hard tasks are the true differentiator.** On standard tasks the spread is ~7 points (85-92%). On hard tasks it's 52 points (39-92%). Hard benchmarks test what easy benchmarks can't: whether the agent discovers novel algorithmic approaches rather than implements well-known patterns
- **Standard task scores cluster tightly.** Claude Code vanilla (85.8%) is within 7 points of the best discipline gene (TDD at 92.0%). Most of the discipline gap is on hard tasks, not standard
- **Multi-agent consensus adds nothing — even with real multi-provider keys.** Three-way test: pure superpowers (no binary), conclave (Claude-only consensus), conclave + keys (Claude + Gemini + Codex). The structured skill text drives all the value
- **Gene stacking has diminishing returns** — Review + Verify (78.3% overall) scores worse than either alone. Two discipline checkpoints don't compound
- **TDD excels on standard but collapses on hard.** TDD (92.0% standard, 70.4% hard) shows the most extreme standard/hard divergence among discipline genes — its structured red-green-refactor cycle helps on known problem types but doesn't transfer to novel challenges
- **T14** (financial-ledger) is the new great equalizer — every orchestrator scores 100%, the task is too easy
- **T2, T5, and T8 are the variance killers.** These three complex tasks (collab-server, task-queue, analytics-dashboard) account for virtually all inter-trial variance. Scores range from 15% to 78% across orchestrators
- **Third-party tools show promise on hard tasks.** [BMAD-METHOD](https://github.com/bmad-code-org/BMAD-METHOD) (88.1% hard) and [GSD](https://github.com/gsd-build/get-shit-done) (88.1% hard) both outperform most discipline genes on hard tasks. Both have competitive standard scores (85.3%, 85.7%)

### The Gas Station Story

Gas Town is a multi-agent pipeline: a Mayor decomposes the task, parallel Polecats implement pieces in git worktrees, and a Refinery merges their work and fixes conflicts. We asked Claude Code to build the adapter.

What it delivered was a fraud — a single `claude -p` call with `gt prime` context injected, wearing Gas Town's scaffolding like a trench coat. It set up the town, created beads, initialized a polecat worktree, the whole ceremony — then ran one agent that did all the work by itself. A single agent pretending to be a workforce.

I named the impostor "Gas Station" and kept it as a control while we built the real multi-agent pipeline ourselves.

Then the benchmarks came back. Gas Station scored 87.8% standard (n=33). The single agent in a trench coat was respectably consistent. And the real multi-agent pipeline? Gas Town scores 88.6% on hard tasks (#4 overall) but cratered to 66.7% on standard tasks (n=34) — the Mayor dispatches simple tasks to a single polecat that sometimes completes with minimal work (30% on T3 and T4, every trial). The fraud outperforms the real thing on standard tasks by 21 points. On hard tasks, the multi-agent decomposition finally justifies itself. Gas Station earned its place: a permanent reminder that complexity must earn its keep on every task type, not just the hard ones.

### From Gene Ablation to Conclave v6

The ablation studies below aren't just academic — they directly shaped [Conclave's](https://github.com/signalnine/conclave) v6 architecture. Here's the story of how 1,200+ trials rewrote a multi-agent framework.

**Phase 1: Measure every gene in isolation.** We tested 8 composable features ("genes") one at a time against vanilla Claude Code (84.6%). Every discipline gene improves on vanilla, but the spread is narrow — the top genes land at 86-89%, the bottom at 80-85%. The gap from vanilla to best discipline is ~5 points.

**Phase 2: Three findings that broke assumptions.**

1. **Multi-agent consensus adds nothing.** Conclave's signature feature — synthesizing perspectives from Claude, Gemini, and Codex — was tested in a 3-way comparison. All three variants converged within 2pp at n=3. More models meant more noise, not more signal.

2. **Gene stacking has diminishing returns.** Review + Verify stacked scored 86.7% — no better than either gene alone. Two quality checkpoints don't catch more than one.

3. **A 15-line system prompt captures most of the benefit.** "Implement, verify, commit, review your diff, fix issues" — no plugins, no skills, no binary — scored 87.0% (Opus). The gap from vanilla (84.6%) to best discipline (89.5%) is only 5 points, and the bare system prompt captures half of it.

**Phase 3: Redesign around the data.** These findings drove three architectural changes in Conclave v6:

- **Task classifier replaces skill browsing.** Instead of 16 skills for the agent to evaluate, the entry point auto-routes: new feature → brainstorm then TDD, bug fix → TDD, everything else → verify. One skill per task, no decision paralysis. Top performers in the benchmark all used exactly one skill.

- **Completion gate embedded everywhere.** The self-review prompt worked because it baked verification into the workflow exit. v6 adds a mandatory gate to every skill: run tests, read output, commit, review diff, fix issues. No skill completes without fresh evidence.

- **Consensus demoted to opt-in.** Every `conclave consensus` call was moved from the default flow to an "Optional: Multi-Agent Consensus" section. Single-agent execution is the default. The binary still works — it just stops hurting scores by default.

**The result:** Conclave v6 on Opus 4.6 scores 85.8% standard, 83.4% hard (84.8% overall, n=57). On Sonnet 4.6, v6 scores 87.4% standard, 88.9% hard (88.0% overall, n=19) at $1.06/task — outperforming the Opus variant at half the cost. The task classifier + completion gate architecture benefits Sonnet more than Opus: structured routing compensates for Sonnet's lower baseline capability, making v6 the optimal cost-performance configuration. The framework went from complex multi-agent orchestration to structured single-agent methodology, guided entirely by benchmark evidence.

### Ablation Studies

We're isolating individual orchestrator "genes" — composable features like multi-agent consensus, skill injection, parallel execution — to measure which actually help. Each ablation holds everything constant except one gene.

**Note:** Per-task tables in some studies below are from early n=1 runs and are preserved for historical context. The corrected aggregate scores are in the [Gene Ablation Variants](#gene-ablation-variants) table above.

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

3. **Debug scores 80.6% on standard tasks.** Below vanilla Claude Code (84.6%) — the debugging methodology's overhead may hurt more than it helps on non-debugging tasks.

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

> **Multi-trial update:** TDD Opus scored 98.0% at n=1 but settled to **86.5%** with more trials and scoring fixes. The n=1 table above is preserved for historical context.

**Findings:**

1. **TDD Opus scores 86.5% on standard tasks.** The n=1 reading of 98.0% dropped progressively with more trials. Complex tasks (T2, T5, T8) account for most of the variance.

2. **Biggest gains on complex greenfield tasks — but also biggest variance.** The same tasks that showed the largest n=1 gains (T2, T5, T8) also showed the largest drops. TDD's red-green-refactor cycle helps most on complex tasks, but the improvement is inconsistent.

3. **No effect on tasks the model already aces.** T3, T9 remain at 100%. T6 softened slightly to 95% but is still near-perfect. The easy tasks are stable across all trial counts.

4. **Cost is the tradeoff.** $1.84/task mean (n=30 standard) — the most expensive standard Opus approach after Review+Verify. The red-green-refactor cycle adds turns: 135 turns on T5 vs typical 40-70.

**The revised pattern:** Forced TDD works — not because the model doesn't know how to test, but because the mandatory discipline prevents cutting corners under token pressure. The model naturally wants to implement first and test later (or not at all). Forcing test-first produces more thorough implementations. TDD Opus (86.5%) is mid-tier among discipline genes. TDD Opus shines on hard tasks (89.8%, #1) where the methodology's structured approach helps discover algorithmic solutions.

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

> **Multi-trial update:** Verify scored 97.3% at n=1 but settled to **83.7%** with more trials and scoring fixes. The n=1 table above is preserved for historical context.

**Findings:**

1. **Verification scores 83.7% on standard tasks.** At $0.96/task, it's one of the cheapest discipline genes. The margin over vanilla (84.6%) is slim on standard tasks, but the verification habit prevents premature completion claims.

2. **Minimal overhead.** 33-51 turns per task — barely more than vanilla Claude Code (~24). The skill is a checkpoint, not a workflow change. The agent implements freely and verifies at the end.

3. **The mechanism is simple.** The agent already *can* verify — it just doesn't always bother. The skill forces it to run `npm test`, `npm run build`, and `npm run lint` fresh and read the output before stopping. This catches issues the agent would otherwise ship.

4. **Verify Sonnet (81.5%) and Verify Opus (83.7%) are within noise.** At $0.72/task vs $0.96, Sonnet remains cheaper.

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

1. **Skill Review scores 79.7% on standard tasks.** Below vanilla Claude Code (84.6%) — the skill's overhead may not be justified on standard tasks. The skill-guided review process adds turns and cost without a commensurate quality improvement.

2. **Conclave Review (88.6%) is the best review variant.** Review + Keys (88.3%) is within noise. The consensus binary provides no advantage.

3. **Expensive for the tier.** $2.33/task mean — the most expensive discipline gene. Self-Review Opus achieves 87.0% at $1.43 with no infrastructure at all.

4. **The review gene is robust across delivery mechanisms.** Conclave Review (88.6%), Review+Keys (88.3%), and Self-Review Opus (87.0%) all cluster. The common thread: pausing to examine your work before claiming done.

**The standard hierarchy:** TDD Opus (92.0%) > Conclave Review (91.8%) > Metacog (88.3%) > Brainstorm (87.9%) > v6 Sonnet (87.4%) > Plans (86.8%) > SR Opus (86.1%) > Verify (86.0%) > Claude Code (85.8%) > v6 Opus (85.8%) > Debug (84.6%) > Review+Verify (83.5%) > Review Pure (78.7%). The gap from vanilla to best discipline is ~6 points. **The overall hierarchy** (with hard tasks): Conclave Review (88.7%) > Plans (88.5%) > v6 Sonnet (88.0%) > Metacog (85.3%) > v6 Opus (84.8%) > TDD (82.9%) > SR Opus (82.6%) > Brainstorm (82.5%) > Claude Code (82.1%) > Verify (81.7%) > Debug (78.4%) > Review+Verify (78.3%) > Review Pure (74.7%).

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

1. **Brainstorming scores 81.0% standard, 88.2% hard.** Below vanilla (84.6%) on standard tasks, but strong on hard tasks where the design exploration pays off. The consensus-driven design discussion surfaces architecture choices the solo agent might miss.

2. **Biggest gains on complex greenfield and marathon.** T2 collab-server (+27.9), T8 analytics-dashboard (+24.7), and T5 marathon (+20.2) benefit most from consensus-driven design exploration. The multi-model design discussion surfaces architecture choices the solo agent might miss.

3. **Good cost/performance ratio.** $1.43/task mean — cheaper than Review ($2.10) and TDD ($1.84). The autopilot consensus calls add overhead but the agent doesn't need as many implementation turns when it has a solid design to follow.

4. **T8 showed the biggest brainstorm gain at n=3.** Brainstorm (81.1%) vs vanilla (56.4%) — a +24.7 point improvement on analytics-dashboard, now the single largest delta. Design exploration matters most when the challenge IS architecture.

5. **Divergent exploration vs convergent discipline.** Brainstorming is the first "divergent" gene tested — it opens up the design space before narrowing. All previous top genes (Review, TDD, Verify) are "convergent" — they check work after implementation. Both approaches work, through different mechanisms.

**The big picture:** The gap from vanilla (84.6%) to best discipline (89.5% v6 Opus) is ~5 points. Discipline genes range from 80-89% on standard tasks. Hard tasks show wider differentiation — see the [Hard Benchmarks](#hard-benchmarks-t12-t19) table.

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

1. **Stacking doesn't help — it slightly hurts.** Review + Verify (86.7%) scores no better than Review alone (88.6%). Two discipline checkpoints are not additive.

2. **More expensive for less.** $2.17/task for Review+Verify — among the most expensive standard approaches, and the score doesn't justify it vs Review alone.

3. **This mirrors the Double Review finding.** The earlier ablation showed consensus adds nothing on top of self-review. Here, verification adds nothing on top of code review. **One quality checkpoint is sufficient. Adding a second doesn't compound.**

**Implication:** The ~89% standard ceiling appears to be the practical limit with current single-session approaches. v6's task-aware routing gets closest by picking the right single checkpoint per task type rather than stacking multiple checkpoints.

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

1. **Self-Review Opus scores 87.0% — a strong free option.** No plugins, no skills, no infrastructure — just a system prompt. At $1.43/task, it's cost-effective.

2. **The gap that matters is vanilla vs discipline, not skill vs no-skill.** Vanilla Claude Code scores 84.6%. Adding "verify, commit, review your diff" jumps to 87.0% — a 2.4 point improvement for free. The gap from vanilla to best discipline (v6 Opus 89.5%) is only ~5pp, and the bare system prompt captures half of it.

3. **Cost is mid-tier.** $1.43/task for Opus — cheaper than Review ($1.77), TDD ($2.53), but more than Plans ($1.06) and Verify ($0.96). The self-review loop adds turns but no external API calls.

4. **Still reframes the study.** The system prompt baseline remains the simplest high-performing approach. The instruction is what matters; the infrastructure is optional — but structured skill routing (v6 at 89.5%) adds genuine stability.

**Implication:** Adding "verify your work, commit, review your diff, fix issues, repeat until clean" to the system prompt is the single simplest high-impact change to any agentic coding tool.

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

1. **All three variants converged.** Brainstorm: No Keys > Pure > +Keys. Review: +Keys > Pure ≈ No Keys. The ordering shuffled between brainstorm and review — no variant consistently wins. See the [Gene Ablation Variants](#gene-ablation-variants) table for aggregate standard means.

2. **Multi-provider consensus (Claude + Gemini + Codex) doesn't beat Claude-only consensus.** The +keys variant is best for review (94.1%) but worst for brainstorm (91.6%). Adding Gemini and Codex to the consensus panel doesn't systematically improve quality — it's noise.

3. **The skill TEXT is the value driver, not the consensus mechanism.** The brainstorming skill's structured design process (architecture, components, data flow, error handling, testing strategy) forces the agent to think before coding. Whether design questions are answered by multi-model consensus, single-model consensus, or the agent's own reasoning makes no measurable difference. All three variants land within 2pp of each other.

4. **Pure superpowers is the cheapest.** $0.89/task for brainstorm (vs $1.46 with keys), $1.95/task for review (vs $1.77 — keys is cheaper on review). No external API dependencies, no conclave binary, no consensus overhead.

**Bottom line:** Multi-agent consensus for design and review decisions is noise, not signal. The three variants are statistically indistinguishable at n=3. The conclave binary and multi-provider API keys are unnecessary.

#### Model Ablation: Sonnet 4.6 vs Opus 4.6 Across Top Approaches

**Hypothesis:** The ~97% top-tier scores require Opus 4.6 ($15/MTok input, $75/MTok output). Sonnet 4.6 (~5x cheaper) can't match it even with the same system prompts.

**Setup:** Four top-performing approaches — TDD (Superpowers), Brainstorm (Conclave), Verify (Superpowers), and Self-Review (system prompt only) — each run with identical Docker images, system prompts, and flags, but with `--model claude-sonnet-4-6` instead of `claude-opus-4-6`. Each Sonnet variant run across all 11 tasks with 2 trials (22 trials per approach, 88 total new trials). Note: Brainstorm Sonnet uses the conclave binary (Claude-only consensus, no API keys); the binary was later shown to have no effect (see Conclave Binary Effect ablation).

| Approach | Opus 4.6 | Sonnet 4.6 | Delta | Cost (Opus → Sonnet) |
| --- | ---: | ---: | ---: | ---: |
| **TDD** | 86.5% | **81.2%** | **-5.3** | $2.53 → $1.48 |
| **Brainstorm** | 81.0% | 76.5% | -4.5 | $1.59 → $0.74 |
| **Verify** | 83.7% | 81.5% | -2.2 | $0.96 → $0.72 |
| **Self-Review** | 87.0%\* | — | — | $1.43 → — |

Per-task breakdown for **TDD (Sonnet vs Opus)** from early runs:

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

1. **Opus leads Sonnet on most approaches.** TDD Opus (86.5%) vs TDD Sonnet (81.2%), Brainstorm Opus (81.0%) vs Brainstorm Sonnet (76.5%), Verify Opus (83.7%) vs Verify Sonnet (81.5%). The per-task table above is from early runs; see the [Gene Ablation Variants](#gene-ablation-variants) table for current aggregates.

2. **The cost story still favors Sonnet.** Sonnet saves 40-55% per task across approaches. Whether the 2-5pp Opus advantage justifies the price difference depends on the use case.

3. **On hard tasks, the picture differs dramatically.** TDD Sonnet collapses (62.9%, crashes on reasoning tasks) while v6 Sonnet thrives (88.9% hard, zero crashes). Structured skill routing matters more for Sonnet than for Opus. v6 Sonnet (88.0% overall, $1.06) outperforms v6 Opus (85.7%, $1.95) — the task classifier + completion gate architecture benefits Sonnet more than Opus.

**Implication:** The right architecture can make Sonnet outperform Opus. v6 Sonnet (88.0%, $1.06) beats v6 Opus (85.7%, $1.95) and ranks #3 overall — Opus-tier quality at Sonnet pricing. Structured routing compensates for model capability gaps.

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

> **Multi-trial update:** Plans scored 96.9% at n=1 but settled to **84.7%** with more trials and scoring fixes. The n=1 table above is preserved for historical context.

**Findings:**

1. **Planning scores 84.7% — essentially at vanilla (84.6%).** The planning overhead doesn't pay off on standard tasks. At $1.06/task, the upfront plan adds turns without improving outcomes.

2. **Biggest gains on complex greenfield and marathon.** T2 collab-server (+13.3) and T1 time-tracker (+6.9) benefit most from upfront architecture thinking. But the gains shrink at n=3 as both Plans and baseline converge.

3. **Good cost profile.** $1.06/task mean — cheaper than TDD ($1.84), Review ($2.10), and Brainstorm ($1.43). Planning adds turns (17-54 per task) but fewer than TDD's red-green-refactor cycle.

4. **The plan is overhead on easy tasks.** T3, T9 remain at 100%. T6 softened to 95% but near-perfect. Writing a plan for a straightforward bugfix adds time without benefit.

**The hierarchy of discipline genes (standard):** TDD Opus (92.0%) > Conclave Review (91.8%) > Brainstorm (87.9%) > Plans (86.8%) > v6 (86.6%) > SR Opus (86.1%) > Verify (86.0%) > Claude Code (85.8%) > Debug (84.6%) > Review+Verify (83.5%) > Review Pure (78.7%). The gap from vanilla to best discipline is ~6pp.

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

> **Note:** The per-task table above is from early n=3 runs. Current aggregate standard means: v6 Opus 89.5%, TDD Sonnet 81.2%, Self-Review Opus 87.0%, Claude Code 84.6%.

**Findings:**

1. **v6 Opus leads standard at 89.5%.** Still #1 overall at 88.4% (89.5% standard, 87.0% hard). The task classifier + completion gate architecture is the most robust across both suites.

2. **The plugin's advantage over a bare system prompt is real.** v6 Opus (89.5%) vs Self-Review Opus (87.0%) — a 2.5pp gap. The structured skill routing provides genuine stability over a bare system prompt.

3. **Biggest improvement: complex greenfield tasks.** The brainstorming → TDD routing gives greenfield tasks both upfront design thinking and implementation discipline.

4. **The three v6 changes compound.** Individual genes land at 80-89%. v6 Opus breaks above at 89.5% by combining the right gene for each task type. Task-aware routing > one-size-fits-all discipline.

5. **Consensus demotion was the right call.** The Conclave Binary Effect study showed consensus adds nothing. Making consensus opt-in removes the overhead without losing any benefit.

**Hard benchmark results (T12-T19):**

v6 was run on all 8 hard benchmarks with 2 trials each (32 additional trials). Results in the [Hard Benchmarks table](#hard-benchmarks-t12-t19) above.

- **v6 Opus (87.0%)** lands within 2.7 points of the leader (SR Sonnet 89.9%) on the hard suite. Holds the highest individual scores on T17 circuit-debugger (90.3%) and T18 beam-splitter (94.3%). T12 was affected by a validation container hang (trial 1: hidden_tests=0, trial 2: 94.7%).
- **v6 Sonnet (87.0%)** is the standout cost-performance result. TDD Sonnet scored 62.9% on the same tasks — crashing on 5 of 6 reasoning/hard trials. v6 Sonnet completed all 16 trials with 100% pass rate. At $0.80/trial, v6 Sonnet is the best cost-adjusted hard benchmark orchestrator.
- **v6 Sonnet's weakness is T17 circuit-debugger (73.3%).** This task requires discovering that simulation caps at ~25% accuracy and switching to structural analysis — a reasoning leap that Opus handles (90.3%) but Sonnet struggles with. On all other tasks, v6 Sonnet is within 5 points of v6 Opus.

**Implication:** The optimal plugin architecture is not "more consensus" or "more checkpoints" — it's intelligent routing to the right methodology for each task type, with a consistent verification gate across all paths. v6 Opus leads all orchestrators overall at 88.4%. On hard benchmarks, both v6 Opus (87.0%) and v6 Sonnet (87.0%) are competitive.

#### Planned Ablations

| Ablation | A | B | Gene Isolated | Status |
|---|---|---|---|---|
| Parallelism | Gas Town | Gas Station | Mayor + parallel polecats + refinery | Data exists (needs more trials) |
| Gas Station scaffolding | Gas Station | Claude Code + Headless | Git worktree + branch setup (gt prime discarded) | **Done — worktree matches Gas Station** |
| Git worktree isolation | Claude Code + Worktree | Claude Code | Bare clone + worktree (no Gas Town tooling) | **Done — 90.7% T5 (n=2), matches Gas Station** |
| Consensus review only | Conclave Review | Claude Code | Multi-agent code review (no skills) | **Done — +11.3 points** |
| Full skill pipeline | Full Conclave | Conclave Review | Brainstorm/plan/implement workflow | **Done — -2.0 points vs review-only (was -19 before data cleanup)** |
| Systematic debugging | Superpowers Debug | Claude Code | Four-phase debugging methodology | **Done — 80.6% standard** |
| Test-driven development | Superpowers TDD | Claude Code | Forced red-green-refactor cycle | **Done — Opus 86.5% standard, 89.8% hard (#1). Sonnet 81.2% standard, 80.5% hard** |
| Verification before completion | Superpowers Verify | Claude Code | "No claims without fresh evidence" | **Done — Opus 83.7%, Sonnet 81.5%** |
| Skill-guided code review | Conclave Skill Review | Claude Code | requesting-code-review skill + conclave consensus | **Done — 79.7% standard** |
| Writing plans | Superpowers Plans | Claude Code | Mandatory plan before implementation | **Done — 84.7% standard** |
| Brainstorming | Conclave Brainstorm | Claude Code | Consensus design exploration (autopilot) | **Done — 81.0% standard, 88.2% hard** |
| Gene stacking: Review + Verify | Review+Verify | Review / Verify | Two discipline checkpoints stacked | **Done — 86.7% (worse than Review alone at 88.6%)** |
| System prompt self-review | Self-Review | Claude Code | "Verify, commit, review diff, fix" — no plugins | **Done — Opus 87.0%, 89.0% hard** |
| Model ablation: Sonnet vs Opus | TDD/Brainstorm/Verify/Self-Review (Sonnet) | Same (Opus) | Cheap model + same system prompts | **Done — Opus leads Sonnet on standard; Sonnet 40-55% cheaper** |
| Consensus design review | Conclave Design | Claude Code | Pre-implementation multi-model architecture guidance | **Done — +16.2 points** |
| Self-review discipline | Double Review (no keys) | Claude Code | "Commit, review your diff, fix" in system prompt | **Done — ~+16 points (free, largest gene)** |
| Self-review + consensus | Double Review (keys) | Claude Code | Self-review + real multi-model consensus | **Done — consensus adds nothing over self-review** |
| Conclave binary effect | Conclave Brainstorm/Review (no keys, +keys) | Superpowers Brainstorm/Review | Multi-agent consensus binary + multi-provider | **Done — no effect: all variants within noise** |
| Conclave v6 plugin | Conclave v6 (Sonnet + Opus) | TDD Sonnet / Self-Review | Task classifier + completion gate + consensus opt-in | **Done — v6 Opus #1 overall (88.4%). Hard: Opus 87.0%, Sonnet 87.0%** |
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
| **[Conclave](https://github.com/signalnine/conclave) v6 (Sonnet)** | Conclave plugin + Sonnet 4.6 | Same plugin, lower cost — 87.0% hard at $0.80/trial |
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
| **Superpowers TDD** | Claude Code + TDD skill | Rigid red-green-refactor cycle; Opus 89.8% hard (#1), Sonnet crashes on hard tasks |
| **Conclave Brainstorm** | Claude Code + conclave consensus binary | Consensus-driven design exploration via conclave binary (Claude-only consensus) |
| **Stacked** | Metacog + review + worktree | Three top genes combined: metacog reframing, consensus code review, git worktree |
| **Superpowers Verify** | Claude Code + verification skill | "No completion claims without fresh evidence" — cheapest top-tier Opus |
| **Conclave Review + Verify** | Claude Code + review + verify stacked | Gene stacking study — diminishing returns (86.7%, both genes combined) |
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
| **Conclave Brainstorm (Sonnet)** | Claude Code Sonnet + brainstorming skill | Sonnet + consensus design — 76.5% standard at $0.74/task |
| **Ralph Fresh** | Claude Code + fresh-context Ralph loop | Multi-iteration fresh context on same workspace |
| **Claude Code Worktree** | Claude Code + git worktree | Matches Gas Station — worktree adds isolation, not quality |
| **Verify (Sonnet)** | Claude Code Sonnet + verification skill | Sonnet + verification — 81.5% standard at $0.72/task |
| **Claude Code Headless** | Claude Code `-p` mode without skills | Headless baseline — no interactive user, no plugins |
| **Amplifier + ts-dev** | Amplifier + TypeScript bundle | LSP code intelligence, TS expert agent |
| **Cerebras CLI** | cerebras-cli (OpenCode fork) + gpt-oss-120b | Full agentic tool use (read/write/bash/glob) via Cerebras inference; direct API routing bypasses OpenCode proxy |
| **[Crush](https://github.com/charm-bracelet/crush) GLM-5** | Crush CLI + Zhipu GLM-5 | Open-source CLI with Zhipu's GLM-5 model; 82.9% overall at $0.76/task (GLM-5 pricing: $1/1M input, $3.20/1M output) |
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
