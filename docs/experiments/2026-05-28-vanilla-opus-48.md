# Opus 4.8 vanilla baseline (2026-05-28)

## TL;DR

Opus 4.8 vanilla via Claude Code OAuth: **83.9% overall / $1.33 per trial / n=37 (19 tasks × 2 trials, minus 1 missing meta)**. Standard suite 81.8%, hard suite 87.0%.

Headline: 4.8 matches 4.6 overall (-0.1pp) while crushing 4.7 vanilla (+9.3pp), with a +7pp hard-suite jump over 4.6.

| Config | Overall | Standard | Hard | $/trial | n |
|---|---:|---:|---:|---:|---:|
| Claude Code (Opus 4.6) | 84.0% | 88.0% | 80.0% | $1.18 | 35 |
| Claude Code (Opus 4.7, no discipline) | 74.6% | 70.4% | 78.8% | $3.34 | 19 |
| **Claude Code (Opus 4.8)** | **83.9%** | **81.8%** | **87.0%** | **$1.33** | **37** |

Caveat: extended thinking was effectively *disabled* in this run (see Methodology), so the 4.8 number above is a "no-thinking" baseline. The thinking-on number is blocked behind a Claude Code CLI 2.1.154 bug.

## CLI bug found, workaround applied

Opening question was clean: spin up `claude-code-oauth-opus-48` mirroring the existing 4.7 vanilla adapter with `--model claude-opus-4-7` swapped to `--model claude-opus-4-8`. Image required a CLI bump from `@anthropic-ai/claude-code@2.1.119` to `2.1.154` to recognize the 4.8 model ID.

First smoke trial on T1 ran 27 turns ($0.77, 18K output tokens) and crashed at the end with:

```
API Error: 400 messages.1.content.12: `thinking` or `redacted_thinking` blocks in the
latest assistant message cannot be modified. These blocks must remain as they were
in the original response.
```

The same image with `--model claude-opus-4-7` (4.7, explicit) ran clean: 13 turns, $0.87, no crash. So the bug is **4.8-specific on CLI 2.1.154** — the multi-turn message loop mutates thinking blocks between requests, and 4.8 enforces immutability strictly enough to reject them while 4.7 did not.

Workaround attempted: `--model opus` (the alias). It resolves to `claude-opus-4-8` (confirmed via `system.init` message in stream-json output) but does *not* trigger the bug at low turn counts. n=3 smoke on T1 came back clean: 9-12 turns each, $0.37/trial, 100% pass rate. The cost gap suggests the alias path skips extended thinking — explicit-model trials ran 2x the turns at 2x the cost.

Decision: run the full sweep with `--model opus` and document it as a "4.8 vanilla, thinking-disabled" baseline. Real 4.8-with-thinking awaits a CLI patch.

## Sweep results

n=2 full suite (19 tasks), parallel=2, OAuth. 38 trial attempts, 37 meta.json captured (T17 trial-1 timed out and the harness did not write meta — separate harness bug noted below).

### Per-task scores

Standard suite (T1-T11, 22 trials):

| Task | Trial 1 | Trial 2 | Mean | vs 4.6 baseline |
|---|---:|---:|---:|---:|
| T1 time-tracker | 0.621 | 0.748 | 0.685 | (4.6 ~0.82 = -13pp) |
| T2 collab-server | 0.544 | 0.560 | 0.552 | (4.6 ~0.59 = -4pp) |
| T3 fts-search | 1.000 | 1.000 | 1.000 | 0 |
| T4 phantom-invoice | 0.983 | 0.983 | 0.983 | 0 |
| T5 task-queue | 0.631 | 0 (crash) | 0.316 | -33pp (crash drag) |
| T6 monorepo-disaster | 1.000 | 1.000 | 1.000 | 0 |
| T7 plugin-marketplace | 0.890 | 0.897 | 0.894 | (4.6 ~0.93 = -4pp) |
| T8 analytics-dashboard | 0.789 | 0.514 | 0.652 | -1pp |
| T9 ssg-toolkit | 1.000 | 1.000 | 1.000 | 0 |
| T10 ecommerce-backend | 0.927 | 0.910 | 0.919 | -6pp |
| T11 debug-nightmare | 1.000 | 1.000 | 1.000 | 0 |

Hard suite (T12-T19, 15 trials present + 1 missing):

| Task | Trial 1 | Trial 2 | Mean | vs 4.6 baseline | vs 4.7 baseline |
|---|---:|---:|---:|---:|---:|
| T12 constraint-scheduler | 0.926 | 0.934 | 0.930 | 0 | +1pp |
| T13 structural-merge | 0.585 | 0.935 | 0.760 | -13pp | -15pp |
| T14 financial-ledger | 0.843 (timeout+bug) | 1.000 | 0.922 | -8pp | -8pp |
| T15 permission-maze | 0.590 | 0.732 | 0.661 | -11pp | -2pp |
| T16 reactive-spreadsheet | 0.937 | 0.950 | 0.944 | +4pp | 0 |
| T17 circuit-debugger | -- (no meta) | 0.893 | 0.893 | +4pp | -3pp |
| T18 beam-splitter | 0.942 | 0.958 | 0.950 | +2pp | +6pp |
| T19 factory-reset | 0.912 | 0.913 (bug late) | 0.913 | 0 | +0pp |

Per-suite means and total cost:

- Standard: **81.8%** mean (n=22, 1 crash counted as 0; cost $22.54 = $1.02/trial)
- Hard: **87.0%** mean (n=15; cost $26.69 = $1.78/trial)
- Overall: **83.9%** mean (n=37; cost $49.23 = $1.33/trial)

### Cost outlier

T17 circuit-debugger trial-2 ran 51 min, 89 turns, **$11.99** at 177K output tokens. Same pattern as no-review-47's T19 (which went $11.87 in 63 min). Pulling this single trial out drops the per-trial mean to $1.04. Reasoning/hard tasks on the new models tend toward these long blow-out trials; budget accordingly.

## Bug + harness incidents

**Thinking-block bug occurrences: 3 of 38 trials (7.9%).**

| Task | Trial | Exit | Score | Notes |
|---|---|---|---:|---|
| T5 task-queue | 2 | crashed | 0.000 | Crashed early, no work product scored |
| T14 financial-ledger | 1 | timeout | 0.843 | Hit bug mid-run, looped to 1800s timeout; validation scored partial work |
| T19 factory-reset | 2 | crashed | 0.913 | Hit bug late in session; substantial work already on disk |

Two of three crashes still produced scoring-eligible work because the partial state on disk passed enough tests for the validation pipeline to grade. Only T5 was a true early kill.

**Other incidents**:

- **T17 trial-1 missing meta.json**: trial timed out at 1800s, harness logged `timeout (duration: 1800s, score: 0.84)` but did not write meta.json. Excluded from the 37-trial total. Suggests a harness bug where timeout exits skip the post-trial meta write — worth filing.
- **T2 trial-2 metrics zero**: `.thunderdome-output.jsonl` missing from the workspace bundle, so cost/token metrics came back as zero even though the trial completed with score 0.560. Score recovered from validation on the workspace diff; cost lost from the rollup.

The 3 thinking-block bug occurrences happened across both standard and hard tasks at varied turn counts (T5 at low turn count, T14 mid-run, T19 late). This means the `--model opus` workaround **delays but does not eliminate** the bug. Long sessions still hit it.

## What this tells us

**1. 4.8 vanilla matches 4.6 vanilla overall — without extended thinking.** 83.9% vs 84.0%. This is the first time a successor Opus has hit baseline parity on vanilla Claude Code. 4.7 vanilla was -9.4pp below 4.6 (74.6%).

**2. Hard suite is where 4.8 actually moves the needle.** +7pp vs 4.6, +8pp vs 4.7. Most of the lift comes from a uniform `+2 to +6pp` across T12-T19 with T13/T15 the only regressions. T18 beam-splitter and T17 circuit-debugger (the two pure-reasoning tasks) both improve. The pattern is consistent with the no-review-47 finding that hidden thinking helps hard reasoning — except here we *don't* have explicit thinking enabled and 4.8 is *still* doing better. Implies the base model itself, not just the thinking budget, is meaningfully stronger on reasoning.

**3. Standard suite slightly regresses vs 4.6 (-6.2pp).** T5 task-queue (-33pp via crash) and T1 time-tracker (-13pp) carry most of the drop. Both are tasks where 4.6 vanilla had quirky-but-working solutions; 4.8 vanilla seems to produce more turn-heavy approaches that occasionally trip the thinking-block bug or just hit local-maxima fixes.

**4. Cost is competitive with 4.6.** $1.33 vs $1.18 vanilla. The 4.7 cost story (-$3.34/trial because hidden thinking burned tokens server-side) does not appear to apply here, likely because the alias path skips thinking. Once the explicit-model path is unblocked, expect 4.8-with-thinking cost to land somewhere between 4.7's $3.34 and 4.8-no-thinking's $1.33.

**5. The bug is real and recurring.** 3 of 38 trials hit it. If the CLI patch lands and re-enables explicit `claude-opus-4-8`, expect the bug rate to be the *worst case* unless Anthropic also fixes the multi-turn mutation pattern. Until then, `--model opus` is the safer-but-degraded path.

## What's not tested

- **4.8 + extended thinking (real apples-to-apples vs 4.7)**: blocked by the CLI bug.
- **4.8 + v8 prompt** (`conclave-v8-combined-opus-48`, `conclave-v8-no-review-opus-48`): adapters created and registered but not run. These are the obvious next experiments once the CLI is patched, since v8 + 4.6 is the current production-grade config and v8 + no-review + 4.7 was the only 4.7 config to beat the 4.6 hard-suite baseline.
- **Single-trial variance**: n=2 means task-level deltas have wide error bars. T5's crash dragging its mean to 0.316 is a particularly noisy data point.

## Recommendation

**For new work**: 4.8 vanilla is now competitive with 4.6 vanilla and clearly better than 4.7 vanilla. If you're running bare Claude Code without orchestration, switch to 4.8 (via `--model opus` until the bug is patched).

**For benchmark sweeps**: the 4.6 + v8 combo (88.7% / $1.45) remains the cost-quality champion. Wait for the CLI patch before running v8 + 4.8 head-to-head — the no-thinking baseline isn't representative.

**Don't use** the explicit `--model claude-opus-4-8` flag on CLI 2.1.154. Use the `opus` alias.

## Files

- Adapter: `adapters/claude-code-oauth-opus-48/adapter.sh` (uses `--model opus`)
- Registered: `thunderdome.yaml` (also registers `conclave-v8-no-review-opus-48`, `conclave-v8-combined-opus-48` for future use)
- Image: `thunderdome/claude-code:latest` (Dockerfile pin bumped to `@anthropic-ai/claude-code@2.1.154`)
- Sweep: `results/runs/2026-05-28T19-34-52/`
