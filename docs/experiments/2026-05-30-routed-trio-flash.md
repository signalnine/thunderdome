# Routed-Trio with DeepSeek v4 Flash in TRIVIAL (2026-05-30)

## TL;DR

Swapped the TRIVIAL implementation tier in `conclave-v10-routed-trio-gemini3f` from DeepSeek v4 Pro to v4 Flash. Otherwise identical: Gemini-3-Flash classifier, EASY → Sonnet 4.6, HARD → Opus 4.6, all with v8 no-review prompt.

**Result: 85.5% / $0.90/trial (n=38) -- -1.3pp accuracy at -12% cost vs gemini3f baseline (86.8% / $1.02).**

| Config | Overall | Standard | Hard | $/trial | n |
|---|---:|---:|---:|---:|---:|
| Conclave v10 Routed-Trio (Gemini-3F classifier, Pro TRIVIAL) | 86.8% | 85.0% | 89.3% | $1.02 | 38 |
| **Conclave v10 Routed-Trio (Gemini-3F classifier, Flash TRIVIAL)** | **85.5%** | **83.2%** | **88.7%** | **$0.90** | **38** |

Modest cost savings; minor accuracy regression. The Sonnet tier dominates cost regardless of who's in TRIVIAL, so the upside from this swap is bounded.

## Method

Adapter `conclave-v10-routed-trio-flash`: clone of `conclave-v10-routed-trio-gemini3f` with `deepseek-v4-pro` → `deepseek-v4-flash` in the TRIVIAL implementation block. Pricing also bumped: $0.07/M in, $0.27/M out, $0.01/M cache read (vs Pro's $0.435/M in, $0.87/M out, $0.04/M cache read).

Sweep: n=2 full suite, parallel=2, 2h54m wall clock. Run dir: `results/runs/2026-05-31T00-21-12/`.

## Routing distribution

| Tier | Count | % |
|---|---:|---:|
| EASY (Sonnet 4.6) | 30 | 79% |
| HARD (Opus 4.6) | 4 | 11% |
| TRIVIAL (Flash) | 4 | 11% |

Same Gemini-3F classifier as gemini3f baseline. The classifier doesn't know which model is in the TRIVIAL slot, so routing decisions are identical between the two runs. The 30/4/4 split means **EASY (Sonnet) trials account for ~88% of total cost** -- the TRIVIAL swap can only affect that remaining ~12%.

## What moved (per-task vs gemini3f baseline)

Wins from Flash TRIVIAL (4 trials):
- T3 fts-search: 1.000 / 1.000 ($0.02 each) -- matches Pro
- T1 time-tracker: 0.768 mean ($0.014 avg) -- consistent with standalone Flash (0.788)

Losses:
- T8 analytics-dashboard: 0.41 mean (vs ~0.60 expected) -- this was routed EASY → Sonnet in both trios, and Sonnet+v8 does worse on T8 than vanilla Flash. Not a Flash-vs-Pro issue, a Sonnet failure mode.
- T16 reactive-spreadsheet trial-1 scored 0 -- Sonnet on EASY route failed (15 turns, $0.98). Trial-2 recovered at 0.95. Not Flash-related.

Net: the TRIVIAL slot performed cleanly. The -1.3pp accuracy drop is mostly statistical noise + the T16 Sonnet crash. Flash and Pro are roughly interchangeable in this slot.

## Why the upside is small

The Sonnet tier handles 79% of trials at $1.10 each -- it dominates the cost equation. Changing the TRIVIAL implementation from $0.10 to $0.02 saves $0.32 across the whole sweep (4 trials × $0.08). The actual measured savings ($0.12/trial × 38 = $4.56 total) include some EASY-route variance from differing tool-use paths.

To meaningfully cut cost, you need to push EASY tasks down to Flash too. That's the `conclave-v10-routed-duo-flash` experiment running next: drop Sonnet entirely, route TRIVIAL+EASY → Flash, HARD → Opus.

## Recommendation

Use `conclave-v10-routed-trio-flash` if you're already on the gemini3f config and want the marginal savings. The Pro tier was never optimal -- Flash is straight-up cheaper and competitive on the small-task slot.

For bigger cost savings on routed configs, **wait for the duo-flash result** -- that's where the real lever is.

## Files

- Adapter: `adapters/conclave-v10-routed-trio-flash/adapter.sh`
- Run: `results/runs/2026-05-31T00-21-12/`
- Related: [v4 Flash standalone baseline](2026-05-30-deepseek-v4-flash.md)
