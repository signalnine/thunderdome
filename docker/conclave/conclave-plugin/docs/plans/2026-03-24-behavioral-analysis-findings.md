# Behavioral Analysis Findings

> **Source:** 676 traced trials (of 5,517 total) across 18 orchestrators with NDJSON output.
> **Tool:** `conclave analyze --results-dir <path> --correlate`
> **Date:** 2026-03-24

## Executive Summary

We built a behavior analyzer that extracts 10 signals from Claude Code NDJSON traces and correlates them with task scores. The key findings:

1. **TDD compliance is real but task-dependent.** Within the same orchestrator, TDD adds +3-8pp consistently. But on marathon/state-heavy tasks, TDD *hurts* (-3.8pp on bench-task-queue).

2. **Three test runs is optimal.** Scores peak at 3 test runs (89.9%) and decline with more — agents running 5+ tests are likely thrashing.

3. **1-2 fix cycles is the sweet spot.** Zero cycles = no iteration (82.5%). 1-2 cycles = healthy red-green (88.3%). 3+ cycles = stuck (78.8%).

4. **Completion gate behaviors predict success within conclave.** Diff review (39.7% vs 34.0%) and final verification (25.4% vs 17.0%) are more common in high-scoring conclave trials.

5. **Running tests matters more than running build.** "Tests only" agents score 93.9% vs "Build only" at 68.8%.

---

## 1. Aggregate Correlations (676 trials)

| Signal | r | Mean(ON) | Mean(OFF) | Delta | N(ON) |
|--------|---|----------|-----------|-------|-------|
| tdd_compliance | +0.111 | 88.1% | 83.2% | +4.9pp | 150 |
| commit_count | -0.101 | 84.3% | — | — | 676 |
| build_check | -0.073 | 83.9% | 88.3% | -4.4pp | 609 |
| lint_check | -0.062 | 83.9% | 87.4% | -3.5pp | 598 |
| fix_cycles | -0.039 | 85.7% | 82.5% | +3.1pp | 380 |
| verification_before_commit | -0.037 | 82.8% | 84.6% | -1.8pp | 108 |
| test_run_count | -0.017 | 86.3% | 80.3% | +6.0pp | 452 |
| test_first_ratio | -0.016 | 84.3% | — | — | 676 |
| final_verification | +0.012 | 85.3% | 84.3% | +1.1pp | 30 |
| diff_review | +0.001 | 84.4% | 84.3% | +0.1pp | 59 |

**Caution:** Aggregate correlations mix orchestrators with very different baselines. Per-orchestrator and per-task breakdowns are more informative.

---

## 2. Per-Orchestrator Behavioral Compliance

Orchestrators with >=10 traced trials, sorted by score:

| Orchestrator | N | Score | TDD% | VBC% | FV% | DR% | BLD% | LNT% |
|---|---|---|---|---|---|---|---|---|
| conclave-design-opus | 32 | 89.0% | 6.2 | 0.0 | 0.0 | 0.0 | 93.8 | 93.8 |
| conclave-review-opus | 55 | 87.9% | 40.0 | 87.3 | 30.9 | 47.3 | 94.5 | 92.7 |
| bmad-oauth-opus | 38 | 87.1% | 26.3 | 0.0 | 0.0 | 0.0 | 94.7 | 94.7 |
| sonnet-gstack | 74 | 86.4% | 23.0 | 0.0 | 0.0 | 0.0 | 93.2 | 91.9 |
| gstack | 57 | 86.1% | 24.6 | 0.0 | 0.0 | 0.0 | 96.5 | 94.7 |
| sonnet-plans | 68 | 85.9% | 22.1 | 2.9 | 0.0 | 0.0 | 89.7 | 91.2 |
| ralph-fresh-opus | 57 | 85.9% | 10.5 | 0.0 | 0.0 | 0.0 | 70.2 | 70.2 |
| sonnet-plans-gstack | 57 | 85.4% | 21.1 | 7.0 | 0.0 | 0.0 | 93.0 | 91.2 |
| claude-code-branch-opus | 38 | 85.4% | 26.3 | 0.0 | 0.0 | 0.0 | 94.7 | 89.5 |
| ralph-fresh-sonnet | 20 | 84.8% | 15.0 | 0.0 | 0.0 | 0.0 | 65.0 | 60.0 |
| conclave-v6-sonnet | 27 | 82.7% | 48.1 | 77.8 | 14.8 | 77.8 | 88.9 | 88.9 |
| conclave-v62-review-opus | 17 | 73.5% | 0.0 | 82.4 | 17.6 | 5.9 | 94.1 | 94.1 |
| conclave-v62-design-review-opus | 11 | 60.3% | 0.0 | 81.8 | 36.4 | 27.3 | 100.0 | 90.9 |

**Key observation:** conclave-review-opus has the highest behavioral compliance (87.3% VBC, 47.3% DR, 30.9% FV) AND the highest score among conclave variants. But the v6.2 variants have even higher VBC% (82.4%) yet score much lower — suggesting compliance alone isn't sufficient; the v6.2 skill text changes hurt more than the compliance helped.

---

## 3. Per-Orchestrator Correlations (Strong Signals)

**conclave-review-opus** (55 traced, 87.9% mean):
| Signal | r | Delta |
|--------|---|-------|
| diff_review | +0.358 | +10.2pp |
| final_verification | +0.352 | +10.8pp |
| verification_before_commit | +0.265 | +11.3pp |
| tdd_compliance | +0.231 | +6.7pp |

**bench-beam-splitter** (31 traced, 86.1% mean):
| Signal | r | Delta |
|--------|---|-------|
| tdd_compliance | +0.660 | +21.6pp |
| fix_cycles | +0.383 | +10.7pp |
| test_run_count | +0.377 | +9.1pp |

**bench-task-queue** (50 traced, 59.9% mean):
| Signal | r | Delta |
|--------|---|-------|
| lint_check | +0.780 | +37.6pp |
| build_check | +0.711 | +41.5pp |
| tdd_compliance | **-0.091** | **-3.8pp** |

---

## 4. TDD Effect Controlled by Orchestrator

Within individual orchestrators (controlling for methodology differences):

| Orchestrator | TDD Score | No-TDD Score | Delta | N(TDD) |
|---|---|---|---|---|
| bmad-oauth-opus | 92.8% | 85.1% | **+7.7pp** | 10 |
| conclave-review-opus | 91.9% | 85.2% | **+6.7pp** | 22 |
| ralph-fresh-opus | 90.0% | 85.4% | +4.6pp | 6 |
| sonnet-plans | 88.5% | 85.2% | +3.3pp | 15 |
| gstack | 86.6% | 86.0% | +0.6pp | 14 |

TDD's within-orchestrator effect is robust (+3-8pp) but smaller than the cross-orchestrator effect (+12pp in the Thunderdome leaderboard). This makes sense — the leaderboard compares TDD-focused orchestrators vs vanilla, capturing both the methodology and the skill text.

---

## 5. TDD Effect by Task

| Task | TDD Score | No-TDD Score | Delta | N(TDD) |
|---|---|---|---|---|
| bench-beam-splitter | 92.3% | 70.8% | **+21.6pp** | 22 |
| bench-ecommerce-backend | 95.7% | 86.6% | +9.0pp | 28 |
| bench-factory-reset | 86.7% | 81.4% | +5.4pp | 19 |
| bench-analytics-dashboard | 62.1% | 57.2% | +4.9pp | 2 |
| bench-constraint-scheduler | 92.0% | 87.3% | +4.8pp | 8 |
| bench-reactive-spreadsheet | 89.7% | 87.0% | +2.7pp | 9 |
| bench-collab-server | 59.8% | 57.2% | +2.5pp | 1 |
| bench-structural-merge | 89.0% | 88.1% | +0.9pp | 7 |
| bench-circuit-debugger | 82.7% | 82.3% | +0.4pp | 23 |
| bench-plugin-marketplace | 90.5% | 91.4% | -1.0pp | 23 |
| bench-task-queue | 56.3% | 60.2% | **-3.8pp** | 4 |
| bench-time-tracker | 74.4% | 79.0% | **-4.6pp** | 4 |

**Pattern:** TDD helps most on greenfield tasks with complex logic (beam-splitter, ecommerce). TDD hurts on marathon tasks (task-queue) and simple tasks with tight time constraints (time-tracker). This suggests the task classifier should route marathon tasks to a different methodology.

---

## 6. Optimal Iteration Counts

### Test Runs
| Count | N | Score |
|-------|---|-------|
| 0 | 62 | 69.7% |
| 1 | 162 | 84.3% |
| 2 | 166 | 86.7% |
| **3** | **117** | **89.9%** |
| 4 | 52 | 87.9% |
| 5 | 37 | 81.7% |
| 6+ | 80 | 81.6% |

### Fix Cycles (test → edit → test)
| Count | N | Score |
|-------|---|-------|
| 0 | 296 | 82.5% |
| **1-2** | **272** | **88.3%** |
| 3-5 | 77 | 78.8% |
| 6+ | 31 | 80.2% |

**Implication for skill text:** Skills should encourage exactly 1-2 fix cycles and approximately 3 test runs. More isn't better — it signals the agent is stuck. The ralph-loop stuck detection threshold of 3 consecutive same-errors is well-calibrated.

---

## 7. No-Discipline Breakdown

Among trials with no TDD compliance and no verification-before-commit:

| Behavior | N | Score |
|----------|---|-------|
| Tests only (no build) | 53 | **93.9%** |
| Build + Tests | 348 | 84.8% |
| Build only (no tests) | 43 | 68.8% |
| Nothing | 7 | 39.9% |

**Surprise:** "Tests only" agents outscore "Build + Tests" by 9pp. This could mean: (a) agents that skip build are faster and have more time for quality work, or (b) tasks where build is unnecessary (pure test-driven) are inherently easier. Needs further investigation with task-level controls.

---

## 8. High vs Low Scoring Trials (Conclave Variants)

Within conclave variants only, comparing trials scoring >=95% vs <70%:

| Behavior | High (n=63) | Low (n=53) |
|----------|-------------|------------|
| TDD compliance | 12.7% | 7.5% |
| Verify before commit | 63.5% | 62.3% |
| Final verification | **25.4%** | 17.0% |
| Diff review | **39.7%** | 34.0% |
| Avg fix cycles | 1.5 | 1.9 |
| Avg test runs | 3.5 | 3.6 |

The differences are modest, suggesting that within conclave (where all agents get skill guidance), the variance comes more from task difficulty than behavioral compliance. The completion gate behaviors (final verification, diff review) show the clearest separation.

---

## Implications for Skill Text Iteration

### What to reinforce
1. **TDD on greenfield/complex tasks** — +21.6pp on beam-splitter, +9pp on ecommerce
2. **Completion gate** (final verification + diff review) — strongest per-orchestrator signals
3. **Target 3 test runs, 1-2 fix cycles** — explicit guidance on "enough is enough"

### What to change
1. **Marathon task routing** — TDD hurts on task-queue (-3.8pp). Route marathon tasks to "verify frequently, iterate fast" instead of strict red-green-refactor
2. **Stop encouraging excessive testing** — 5+ test runs correlates with decline. Add "if tests pass on the third run, move on"
3. **Build check is noise** — negative aggregate correlation. Don't emphasize it in skills

### What to test with micro-benchmarks
1. Task classifier routing: does routing marathon tasks away from TDD improve scores?
2. Iteration caps: does "stop after 3 test runs" guidance change behavior?
3. Completion gate wording: does stronger/weaker gate text change final-verification rates?
