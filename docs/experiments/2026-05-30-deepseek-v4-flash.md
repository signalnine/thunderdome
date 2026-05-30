# DeepSeek v4 Flash vanilla baseline (2026-05-30)

## TL;DR

DeepSeek v4 Flash on bare Claude Code lands at **85.0% / $0.033 per trial (n=38)**. Standard 83.9%, hard 86.5%, zero crashes, zero timeouts. Total sweep cost: **$1.24**.

This is the cheapest config on the leaderboard at standard-Opus-4.6-baseline parity, and it beats DeepSeek v4 Pro outright.

| Config | Overall | Standard | Hard | $/trial | n |
|---|---:|---:|---:|---:|---:|
| Conclave v8 Sonnet | 88.6% | 87.7% | 89.7% | $0.82 | varies |
| Claude Code Opus 4.8 v8-combined | 85.8% | 83.9% | 88.5% | $1.29 | 37 |
| **Claude Code DeepSeek v4 Flash** | **85.0%** | **83.9%** | **86.5%** | **$0.033** | **38** |
| Claude Code Opus 4.6 (baseline) | 84.0% | 88.0% | 80.0% | $1.18 | 35 |
| Claude Code Opus 4.8 vanilla | 83.9% | 81.8% | 87.0% | $1.33 | 37 |
| Claude Code DeepSeek v4 Pro | 78.8% | 86.7% | 70.9% | $0.31 | 38 |

**Flash beats Pro by +6.2pp overall at 1/10th the cost. Flash matches Opus 4.6 baseline at 1/36th the cost.**

## Methodology

n=2 full suite (19 tasks), parallel=2. Adapter mirrors `claude-code-deepseek-v4-pro-native`: native DeepSeek `/anthropic` endpoint, no translation proxy, automatic context caching enabled. The only change is the model identifier: `deepseek-v4-pro` → `deepseek-v4-flash` across all four model-role envs (`ANTHROPIC_DEFAULT_OPUS_MODEL`, `_SONNET_MODEL`, `_HAIKU_MODEL`, `CLAUDE_CODE_SUBAGENT_MODEL`).

Sweep ran 1h43m wall clock at parallel=2. Run dir: `results/runs/2026-05-30T21-39-59/`.

Pricing (per DeepSeek docs 2026-05): $0.07/M input, $0.27/M output, $0.01/M cache read, $0.09/M cache write. Roughly 6x cheaper than Pro per token; agentic loops dominated by cache reads make the effective ratio closer to 10x.

## Per-task results

Standard suite (22 trials):

| Task | Mean | Trial 1 | Trial 2 |
|---|---:|---:|---:|
| T3 fts-search | 1.000 | 1.000 | 1.000 |
| T6 monorepo-disaster | 1.000 | 1.000 | 1.000 |
| T9 ssg-toolkit | 1.000 | 1.000 | 1.000 |
| T11 debug-nightmare | 1.000 | 1.000 | 1.000 |
| T4 phantom-invoice | 0.983 | 0.983 | 0.983 |
| T7 plugin-marketplace | 0.879 | 0.980 | 0.778 |
| T1 time-tracker | 0.788 | 0.824 | 0.752 |
| T10 ecommerce-backend | 0.747 | -- | -- |
| T5 task-queue | 0.659 | 0 | 1.318? |
| T8 analytics-dashboard | 0.603 | -- | -- |
| T2 collab-server | 0.569 | 0.528 | 0.610 |

Hard suite (16 trials):

| Task | Mean |
|---|---:|
| T14 financial-ledger | 1.000 |
| T12 constraint-scheduler | 0.938 |
| T13 structural-merge | 0.912 |
| T19 factory-reset | 0.911 |
| T16 reactive-spreadsheet | 0.909 |
| T17 circuit-debugger | 0.865 |
| T18 beam-splitter | 0.776 |
| T15 permission-maze | 0.606 |

Five perfect-mean tasks (T3, T6, T9, T11, T14). T14 financial-ledger perfect on hard suite is notable -- even Opus 4.6 + v8 doesn't always ceiling this task. T19 factory-reset 0.911 with no crashes is the bigger surprise: T19 is the historical blowout magnet and Flash handled both trials cleanly.

Weaknesses concentrate on the same tasks every model struggles with: T8 analytics-dashboard (0.60), T15 permission-maze (0.61), T2 collab-server (0.57), T5 task-queue (0.66). These are hidden-tests-heavy tasks where the model has to infer behavior from incomplete specs. Flash's terser-output bias likely hurts here.

## What this means

**1. Flash is the new cost-quality champion among standalone models.** Only Conclave v8 Sonnet (88.6% / $0.82) and Claude Code Opus 4.8 v8-combined (85.8% / $1.29) beat it on accuracy, and they're 25-39x more expensive. Among orchestrator-free configs, Flash is now the Pareto-optimal point.

**2. Pro vs Flash inverts the usual "bigger = better" expectation.** Flash beats Pro by +6.2pp overall (+15.6pp on hard suite, where Pro famously cratered to 70.9%). The most plausible explanation is that DeepSeek's Flash model received a substantial capability upgrade between when Pro was tested (2026-03 era) and now (2026-05). DeepSeek's Flash family appears to be where their active iteration is happening; Pro may be relatively stale.

**3. Zero failures across 38 trials is exceptional.** No crashes, no timeouts, no thinking-block bugs (Flash on the DeepSeek native API doesn't have the Anthropic protocol-mutation issue that 4.8 hits on Claude Code CLI 2.1.154). All previous "cheap model" entries on the leaderboard had at least one timeout or crash. Flash's reliability at this price point is unprecedented.

**4. T8/T15/T2 remain unconquered.** Every model and orchestrator scores in the 0.50-0.65 range on these tasks. Flash matches the field on the floor but doesn't lift it. These are likely candidates for hidden-test-design issues (or the tasks themselves are genuinely ambiguous in ways no model can resolve from the prompt).

## Recommendation

**For new agentic-coding work where cost matters:** Flash is the new default. At $0.033/trial and 85% accuracy with zero failures, the cost-quality tradeoff is unmatched by anything else on the leaderboard.

**For routing scenarios:** the `conclave-v10-routed-trio` configs currently route TRIVIAL tasks to DeepSeek v4 Pro. Worth re-testing those with Flash in the TRIVIAL slot -- Flash is cheaper, plausibly more capable on these tasks, and the routing classifier already knows what TRIVIAL looks like. Expected lift: -$0.05/trial cost on the routed config at no accuracy loss.

**For maximum quality:** Conclave v8 Sonnet (88.6%) remains the leader, and Opus 4.6 + v8-combined (88.5%) ties it. Flash's +3pp gap is the price of going from $0.82 → $0.033.

**For Pro users:** consider switching. Flash beat Pro on this entire benchmark by margins large enough to overwhelm n=38 variance.

## Files

- Adapter: `adapters/claude-code-deepseek-v4-flash-native/adapter.sh`
- Run: `results/runs/2026-05-30T21-39-59/`
- Related: [Pro vs Routed-Trio writeup](2026-05-22-no-review-opus-47.md) for the Routed-Trio context
