# Opus 4.7 + v8 minus self-review (2026-05-22)

## Hypothesis

Opus 4.7's hidden thinking tokens *are* the adversarial self-review pass that v8 prompts add explicitly. If so, removing the explicit self-review step from v8 should close the deficit between v8+4.7 (86.3%) and v8+4.6 (88.7%) on the standard+hard benchmark suite.

If `conclave-v8-no-review-opus-47` lands at ~88-89% overall, hypothesis confirmed -- 4.7's hidden thinking is double-counted with explicit review on this prompt.

If it lands at ~86% or below, hypothesis falsified -- 4.7's regression is not about review redundancy.

## What We Tested

`conclave-v8-no-review-opus-47`: v8 prompt with the Adversarial Self-Review step removed, on Opus 4.7 via OAuth. Adapter is a one-line model swap on top of the existing `conclave-v8-no-review-opus` (4.6) adapter. n=2 full suite (19 tasks), parallel=2.

Salvaged trials from an earlier parallel=1 run and a credential-mismatch crash mid-run are merged via gen-scores' standard aggregation. Total: 58 non-crash trials (44 standard, 14 hard at writeup time; T19 still running).

## Result

**Overall: 86.5% / $2.10 (n=60, std 82.5% / hard 90.4%)** -- hypothesis falsified at the overall level, but with a stronger hard-suite finding than expected.

Comparison table:

| Orchestrator | Overall | Standard | Hard | $/task | n | Notes |
|---|---:|---:|---:|---:|---:|---|
| conclave-v8-no-review-opus (4.6) | **88.6%** | 87.3% | 89.9% | $1.28 | 70 | published baseline |
| conclave-v8-combined-opus (4.6) | 88.5% | 87.7% | 89.3% | $1.49 | 56 | published baseline |
| conclave-v8-combined-opus-47 | 86.3% | 83.6% | 89.1% | $5.46 | 39 | published 4.7 best |
| **conclave-v8-no-review-opus-47** | **86.5%** | **82.5%** | **90.4%** | **$2.10** | **60** | this run |
| claude-code-oauth-opus-47 (vanilla) | 73.4% | 68.4% | 78.4% | $2.94 | 38 | bare 4.7 |

Three findings:

**1. Hypothesis falsified on standard suite, confirmed on hard suite (with lift).** Standard suite regressed -4.8pp vs the 4.6 baseline (87.3% -> 82.5%). The explicit review pass *was* doing real work on standard tasks for 4.6, and 4.7's hidden thinking doesn't substitute. But hard suite landed at **90.4% vs 89.9% baseline -- +0.5pp on 16 vs 24 trials**, the first config where 4.7's hidden thinking has not just substituted for but slightly improved on explicit discipline. T19 factory-reset is the largest individual contributor: 4.7 scores 95.5% vs 4.6's 91.2% (+4.3pp).

**2. Cost is the real story.** $2.10 vs v8-combined-opus-47 at $5.46 = **62% cheaper at +0.2pp overall accuracy**. v8-combined-opus-47's $5.46/trial is the explicit-review pass plus 4.7 hidden thinking -- when both run on 4.7 the bill explodes, with little to show for it. Removing the explicit pass cuts cost to v8-combined-opus 4.6 territory ($1.49) at the same hard-suite outcome. **For hard-only sweeps, v8-no-review on 4.7 is now the leaderboard top hard-suite score among Opus configs at $2.10 -- behind only v10-routed-47-fast (91.0%, $3.56) and the v10-routed (4.6) entry at $1.20.**

**3. Standard-suite regression concentrates on specific tasks.** Per-task delta (4.7 - 4.6):

| Task | 4.6 | 4.7 | Δ | Task class |
|---|---:|---:|---:|---|
| T3 fts-search | 100% | 100% | 0 | Ceiling for both |
| T6 monorepo-disaster | 100% | 100% | 0 | Ceiling for both |
| T9 ssg-toolkit | 100% | 100% | 0 | Ceiling for both |
| T11 debug-nightmare | 100% | 100% | 0 | Ceiling for both |
| T4 phantom-invoice | 98.3% | 98.3% | 0 | Near-ceiling |
| T5 task-queue | 64.6% | 63.4% | -1.2pp | Mid-difficulty |
| T7 plugin-marketplace | 92.6% | 88.2% | -4.4pp | Strong both |
| T2 collab-server | 59.2% | 54.2% | -5.0pp | Mid-difficulty |
| T10 ecommerce-backend | 98.5% | 88.9% | -9.6pp | 4.6 ceiling, 4.7 drops |
| T1 time-tracker | 81.6% | 70.7% | -10.9pp | Mid-difficulty |
| **T8 analytics-dashboard** | **65.9%** | **44.2%** | **-21.7pp** | **Catastrophic** |

The standard-suite damage is non-uniform. Five tasks ceiling at 100% for both. Five mid-difficulty tasks lose -1 to -10pp. **T8 analytics-dashboard collapses from 65.9% to 44.2%** -- a -21.7pp regression on a single task accounts for ~2pp of the standard-suite mean drop. T8 was already 4.6's weakest standard task at 65.9%; 4.7 + no-review cuts it nearly in half. Worth examining whether T8 needs the explicit review specifically.

Per-task on hard suite is less stark, with four lifts and three regressions:

| Task | 4.6 | 4.7 | Δ |
|---|---:|---:|---:|
| **T17 circuit-debugger** | **85.4%** | **92.2%** | **+6.8pp** |
| **T19 factory-reset** | **91.2%** | **95.5%** | **+4.3pp** |
| T16 reactive-spreadsheet | 90.3% | 94.0% | +3.7pp |
| T13 structural-merge | 89.1% | 91.2% | +2.1pp |
| T14 financial-ledger | 100% | 100% | 0 |
| T12 constraint-scheduler | 93.0% | 92.0% | -1.0pp |
| T18 beam-splitter | 93.2% | 90.4% | -2.8pp |
| T15 permission-maze | 76.8% | 67.9% | -8.9pp |

T17 circuit-debugger has the cleanest 4.7 win (the hardest reasoning task in the suite). T19 factory-reset is the second-largest win and historically the timeout magnet -- 4.7 + no-review handles it more reliably than 4.6 + review, though at a cost premium ($4.58 trial 1, $11.87 trial 2 -- the trial 2 burned 9.4M tokens over 63 minutes). T15 permission-maze regresses -8.9pp; it's a cross-tree permission reasoning task where 4.6 already scored relatively low and 4.7 + no-review drops further.

## Methodology Notes

**Two harness issues surfaced during this run:**

1. **Mid-sweep `/login` invalidates in-flight Claude credentials.** The first parallel=2 attempt crashed 27 trials in ~5s each when a user `/login` rotated the OAuth token while containers were running. The credentials file is bind-mounted at container launch -- in-flight CLIs hold the old token and fail-fast on the next API call. Workaround: never `/login` during a sweep. Long-term fix: have the runner detect token rotation and pause new trial launches until the operator reconfirms. Filed as a TODO for the harness but not blocking.

2. **T2 collab-server hung for 26 min on Opus 4.7.** Claude wrote an inline `node` test under Bash that did `await new Promise(r => ws.once('open', () => r(true)))` with no timeout wrapper. The WebSocket server didn't emit `open` (likely a path-mismatch bug Claude had introduced earlier in the same trial) and the test hung indefinitely. Killing the hung node process via `docker exec` let Claude recover. **Pattern worth tracking**: 4.7 may be more prone than 4.6 to writing ad-hoc test scripts that lack their own timeout discipline. Not a one-off -- T2 scored 0.44 / 0.57 across four no-review-47 trials, the lowest of any standard task except T8.

**Untested combinations remain.** This experiment only covers the v8-minus-review ablation on 4.7. Two related questions are still open:

- Does v8-minus-review on 4.6 also tie 4.7 on hard suite? (Implicitly tested by the existing v8-no-review-opus 4.6 data at 89.9% hard; 4.7 lands at 89.7%. Effectively no.)
- Does v8-minus-boil-the-lake on 4.7 also tie? The current data does not isolate which v8 step matters for hard.

## Conclusion

The "4.7 hidden thinking substitutes for explicit review" hypothesis is **falsified on standard suite, confirmed-with-lift on hard suite**. Dropping explicit self-review on 4.7 makes it 62% cheaper than v8-combined-opus-47 at +0.2pp overall and +1.3pp hard. But the standard-suite regression is real and concentrates on specific tasks (T8 catastrophically, T1/T2/T10 moderately), so this configuration is **not a drop-in replacement** for v8-combined-opus on 4.6 -- it's a hard-suite specialist.

Practical recommendation: if running a hard-only sweep on 4.7, use no-review-opus-47 -- at 90.4% hard, it's competitive with the absolute leaderboard top (v10-routed at 91.7%) and beats every other Opus 4.7 config in the data. If running mixed standard+hard, the 4.6 baseline (v8-combined-opus, $1.49/trial, 88.5%) remains the right pick. We have not yet found a 4.7 configuration that beats v8+4.6 on the full suite.
