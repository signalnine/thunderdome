# Open Questions

A working list of unresolved threads from the benchmark. Each entry has a short statement, what we know, a proposed experiment, and a rough cost.

Last updated 2026-05-12.

---

## Q1: Why does Benedictine specifically lift Sonnet?

**Status:** Sharpened at n=22 standard + n=10 hard. Top-6 on the leaderboard.

**Observation.** Benedictine-sonnet lands at 87.9% / $0.83 (rank #6). Other tradition prompts on the same substrate cluster lower at the full n=22+ backfill:

| Prompt | Sonnet overall | Δ vs benedictine |
|---|---:|---:|
| benedictine-sonnet | **87.9%** | baseline |
| sufi-sonnet | 85.1% | -2.8pp |
| dao-sonnet | 82.5% | -5.4pp |
| stoic-sonnet | 82.1% | -5.8pp |
| zen-lite-sonnet | 80.9% | -7.0pp |

n=2 said the spread was noise. n=22+ says it isn't.

**Best hypothesis: Benedictine = v8 minus contract.** The four named phases (Lectio → Meditatio → Oratio → Contemplatio) map almost identically to v8's structure (Understand → Plan → TDD → Verify), but without v8's CONTRACT.md requirement that drives a long preamble. v8-combined-sonnet sits at 88.1% (just +0.2pp above benedictine), v8-no-boil-sonnet at 87.7%, v8-no-contract-sonnet at 87.0%. If the contract is dead weight, that'd explain why Benedictine ties v8 at much shorter prompt length.

**Proposed experiment.** Direct ablation: write a Sonnet adapter with v8 minus contract.md and v8 minus boil-the-lake, run at n=22 standard. If both land at ~87-88%, then Benedictine's lift is mostly the four-phase rhythmic discipline, not anything specifically Christian/monastic. If Benedictine is meaningfully above v8-minus-X, then the phase *names* (lectio/meditatio/...) are doing load-bearing work and we've found a real prompting nugget.

**Cost.** ~$20 for two adapters × 22 trials each. Already have v8-no-contract-sonnet baseline at 87.0%.

---

## Q2: Why does Dao on Sonnet bleed standard-suite scores?

**Status:** Open. Per-task split is suspicious.

**Observation.** dao-sonnet 82.5% combined breaks down as 78.3% std / 86.8% hard. Hard suite is competitive with benedictine (88.8%) but standard tanks 9pp. Same shape as dao-deepseek (std -4.8pp / hard +1.9pp vs vanilla).

**Best guess.** The "release urgency, water finds the riverbed" framing makes capable models *over-deliberate on simple tasks*. Standard suite has well-spec'd CRUD/feature work where iteration speed matters; hard suite has reasoning work where deliberation pays off. Dao's framing is shape-matched to hard, not std.

**Proposed experiment.** Test the same per-task pattern on sufi (which lands between dao and benedictine). If sufi-sonnet std also bleeds vs hard, the "calm framing hurts std on capable models" rule generalizes. If sufi doesn't bleed, then dao specifically has an over-deliberation problem we should isolate to the watercourse imagery.

**Cost.** Already have sufi-sonnet data — just slice the per-task breakdown out of the existing run. Nearly free.

---

## Q3: Can routed-trio recover with a better classifier prompt?

**Status:** Partially fixed in code, not re-run.

**Observation.** conclave-v10-routed-trio landed at 82.3% / $0.88 — disappointing vs v10-routed (89.9% / $1.20). T19 factory-reset took two zero scores because Haiku misclassified it as EASY and Sonnet timed out. Without those zeros, the trio would have been ~85-86%, which is the v8-Sonnet-cheap-tier ballpark but at the cost of routing complexity.

**Fix already applied.** Tightened the classifier prompt to recognize "find-minimum-subject-to-constraints" as HARD signals. Added explicit examples (factory-reset, beam-splitter, button-toggle). Defaulted parse failure to HARD instead of EASY (asymmetric cost: $0.50 over-spending vs full-suite timeout).

**Proposed experiment.** Re-run conclave-v10-routed-trio after the classifier fix. If it lands 85-88% at $0.85-1.00, three-way routing is viable. If it lands at the same 82% (or worse), the routing premise isn't load-bearing — easier to just run v8 Sonnet directly.

**Cost.** ~$25-30 for n=2 across 19 tasks.

---

## Q4: Is the DeepSeek native API path Pareto-optimal for the $0.30 cost tier?

**Status:** Combined leaderboard entry now visible after gen-scores alias fix.

**Observation.** claude-code-deepseek-v4-pro (alias covering OpenRouter std + native hard) sits at 78.2% / $0.31 / n=39. That's the cheapest entry on the leaderboard above 75%. v11-qwen-routed at 86.3% / $0.74 is the next step up — 8pp better but 2.4× the cost.

**Open question.** Is there a way to push DeepSeek's hard-suite score (70.9%) up without losing the cost advantage? Two candidate levers:
1. Run DeepSeek with the v8 prompt (already done in routed-trio's TRIVIAL bucket — those trials scored ~0.6-0.8 on std).
2. Run DeepSeek with the Benedictine prompt — but we already saw that the calm-framing prompts hurt DeepSeek on simple tasks. Heavy-structure on capable models = lift. Test bene-deepseek hypothesis: should it land in the same neighborhood as bene-sonnet on hard suite?

**Proposed experiment.** Build bene-deepseek-v4-pro-native, run at n=2 full suite. If hard suite climbs from 70.9% → 80%+, DeepSeek with Benedictine becomes a real cheap-tier contender (~$0.40-0.50 estimated).

**Cost.** ~$15-20.

---

## Q5: Does the calm-framing lift survive at n=22 for GLM-5.1?

**Status:** Suggested but never run.

**Observation.** zen-lite-glm51-neuralwatt at n=20 sits at 83.1% (+7.4pp over vanilla GLM-5.1 at 75.7%). Dao on the same substrate is untested. At n=2, dao and zen tied on Qwen3.6 (76.4% vs 76.1%); at n=57 they still tied. Plausible the same holds on GLM-5.1.

**Open question.** If zen-lite lifts GLM-5.1 by +7.4pp, does dao do roughly the same? If yes, "calm framing class" generalizes cleanly. If dao lifts only +2-3pp, then zen-lite specifically has something dao doesn't (likely the explicit TDD-first cadence).

**Proposed experiment.** Build dao-glm51-neuralwatt. Run at n=2 full suite. If lands within 2pp of zen-lite-glm51, the class generalizes. If lands ~3-5pp below, dive into the prompt diff.

**Cost.** ~$20-40 (GLM-5.1 is ~$1/task on Neuralwatt).

---

## Q6: Top-of-leaderboard ceiling is stuck at ~90%. What breaks 92%+?

**Status:** Long-standing. No new ceiling-breaker discovered this session.

**Observation.** v10-routed at 89.9%, v8-zen-opus at 88.7%, v8-no-review-opus at 88.6%, v8-combined-opus at 88.5%. The cluster is tight (1.4pp spread among the top 4). Hard-suite ceiling is 91.7% (v10-routed); standard ceiling is 88.1% (also v10-routed).

**What hasn't been tried.** A 4-model routed-quad (Haiku → DeepSeek/Sonnet/Opus + a reasoning-specialist on the hardest tasks). Hot candidate for the reasoning specialist: GPT-5.5 via Codex OAuth (75.0% solo but with Codex harness disciplines that don't transfer to Claude Code), or o1/o3-class model.

**Cost.** TBD — depends on routing target. Estimate $30-50.

---

## Q7: Sonnet OAuth concurrency penalty — can it be characterized?

**Status:** Observational only.

**Observation.** Running `--parallel 2` sweeps on Sonnet 4.6 via OAuth produces ~25 401-crash trials mid-sweep, even when well within Anthropic's stated rate limits. parallel=1 with fresh OAuth holds clean. The exact trigger conditions aren't documented anywhere we can see.

**Open question.** Is the threshold time-of-day dependent (cluster congestion)? Account-tier dependent (Pro vs Team)? Cumulative-call-count dependent (the longer the session, the more likely)? Some combination?

**Proposed experiment.** Stress test: drive parallel=3 on a fresh Sonnet session and log exactly when the first 401 appears. Repeat 3-5x at different times. If the trigger is cumulative-call-count, we can quantify "sustainable rate" precisely.

**Cost.** ~$5-10 per stress test. Worthwhile because every future Sonnet sweep is bottlenecked by this constraint.

---

## Q8: Does OpenRouter's Pareto Router match task-adaptive routing?

**Status:** New, not run.

**Observation.** OpenRouter shipped `openrouter/pareto-code` (May 2026) — a static price-sorted shortlist routed by `min_coding_score` tier (0-1). At each tier the router picks the cheapest model that meets the threshold, with up to two fallbacks. No per-task classification, no router fee. Confirmed working via OpenRouter's Anthropic-shape endpoint with our existing claude-code-deepseek-v4-pro adapter pattern; a "say ok" probe routed to deepseek-v4-pro at the default tier.

**Open question.** Pareto Router and our conclave-v10-routed-trio occupy the same conceptual space (route to cheaper models when you can) but with opposite mechanisms:

| | Pareto Router (theirs) | Routed-Trio (ours) |
|---|---|---|
| Routing decision | Static, per-tier price-sorted | Per-task Haiku classification |
| Routing cost | $0 router fee | ~$0.005 Haiku call/task |
| Adapts to task difficulty | No -- same model per tier | Yes -- TRIVIAL/EASY/HARD |
| Adapts to new models | Yes (curated shortlist evolves) | No (hardcoded) |

If Pareto-at-similar-cost matches Routed-Trio's quality, our per-task routing logic isn't load-bearing -- the win is just "buy cheaper when you can," which a static shortlist handles. If Routed-Trio meaningfully beats Pareto at the same cost tier, task-adaptive routing is the actual lift.

**Proposed experiment.** Build three pareto adapters at different `min_coding_score` levels:

| Adapter | min_score | Expected tier | Cost target | Compare against |
|---|---|---|---|---|
| pareto-cheap | 0.70 | DeepSeek-class | ~\$0.10-0.20/trial | DeepSeek standalone (78.2%, \$0.31) |
| pareto-mid | 0.85 | Sonnet-class | ~\$0.50-0.80/trial | v8-Sonnet (88.1%, \$0.82) |
| pareto-top | 0.95 | Opus/GPT-5.5 class | ~\$1.00-1.50/trial | v10-routed (89.9%, \$1.20) |

Wrinkle: `min_coding_score` is a plugin param passed via OpenAI's `extra_body`, which Claude Code → OpenRouter Anthropic endpoint doesn't expose. Three implementation paths:
1. Default tier (no config) -- cheapest first test, see what Pareto picks across our 19 tasks
2. Thin proxy that injects the `pareto-router` plugin into the request body before forwarding
3. Switch to OpenRouter's chat-completions endpoint + route through ccr (which can pass extra_body)

Recommend option (1) first as the cheap baseline; if interesting, then (2) for the three-tier comparison.

**Cost.** Option (1): ~$30-50 for one default-tier sweep. Option (2): ~$100-150 across three tiers.

**Tie-breaker if results match:** at the same score-per-dollar, the simpler routing wins (Pareto, no Haiku call, no maintenance). If quality differs by >2pp at the same cost, the more complex routing wins. Reserve a "stretch goal" comparison: pareto-top vs routed-trio after the Q3 classifier fix.

- ✅ ccr is the working path for OpenAI-shape upstreams (Q closed 2026-05-10, see `memory/tool_ccr_neuralwatt.md`)
- ✅ Discipline complexity must match model capability — heavy structure on under-capable model regresses (Q closed 2026-05-10, see `memory/project_prompt_capability_match_2026-05-10.md`)
- ✅ DeepSeek native API caching is real (3.5× cheaper than OpenRouter on agentic loops, see `memory/project_deepseek_v4_pro_2026-05-05.md`)
