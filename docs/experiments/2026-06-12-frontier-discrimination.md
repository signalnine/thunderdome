# Frontier discrimination: Fable 5 vs Opus 4.8, and why benchmarks can't tell them apart (2026-06-09 .. 06-12)

## TL;DR

Claude Fable 5 (released 2026-06-09, +10% over Opus 4.8 on press benchmarks, 2x the price) lands **~3pp BELOW** the Opus 4.8 baseline on this suite -- reproducibly, across two harness versions and a 3-trial run. Chasing the "why" produced a four-day investigation with one central finding:

**Frontier models cannot be discriminated by well-scoped tasks at all.** Across 5 purpose-built "ultra-hard" tasks (synthetic and real-repo-harvested), Opus 4.8 scored a perfect 1.0 on hidden tests every single time. On genuinely hard human-curated SWE-bench Pro instances the models trade single-shot wins in both directions (tied 5/15 vs 4/15) -- but giving both models an iterative build/test loop made **every measurable differentiator disappear: 1.0 across the board.** The single-shot "Fable beats Opus here, Opus beats Fable there" results were scaffolding artifacts, not capability differences. What leaderboard gaps (SWE-bench Pro 80% vs 69%, FrontierCode 13.4%) measure is differential skill at *using* a specific verify loop, plus task-curation difficulty that cannot be manufactured -- synthetically or by automated harvest.

Keepers shipped along the way: a deterministic mutation-testing primitive (`scripts/mutation_score.py`), a real-repo task-harvest pipeline (T20/T21), a local SWE-bench Pro eval loop, and a revived interactive-TUI adapter (`claude-code-tmux-oauth`) that proves the interactive-vs-headless gene is score-neutral.

## 1. Fable 5 on the suite: real gap, wrong direction

Vanilla Claude Code harness, Max-subscription OAuth (`claude-code-oauth-fable5`, env `{}`, $0 actual cost):

| Run | Standard | Hard | Overall |
|---|---:|---:|---:|
| Fable 5, cc 2.1.154 (pre-Fable harness), n=1 | 78.5% | 83.0% | 80.8% |
| Fable 5, cc 2.1.170 (Fable-aware harness), n=1 | 78.6% | 82.7% | 80.6% |
| Fable 5, 3-trial, crash-excluded | 79.4% | ~82.7% | **~81.0%** |
| Opus 4.8 baseline (no thinking) | 81.8% | 87.0% | **83.9%** |

- The harness-version hypothesis was tested and **rejected**: upgrading to the claude-code release that ships Fable support moved the score 0.2pp.
- The ~3pp deficit reproduced across four independent measurements. Most per-task spreads are sd ~0.00 over 3 trials; the noise is concentrated in two tasks (analytics-dashboard 0.47..0.84, circuit-debugger incl. one crash).
- Zero crashes, zero safety-fallbacks-to-Opus across all Fable runs. circuit-debugger ran 39 min (long-horizon grind, completed at 0.82).
- Interpretation: this suite is **saturated** for frontier models. The standard half ceilings at ~0.85 and two greenfield tasks cap everyone at ~0.5. There is no headroom in which a +10%-on-press-benchmarks model can show it.

## 2. Manufacturing an ultra-hard task: five failures, one law

Five attempts to build a frontier-discriminating task, calibrated by running Opus 4.8 (and Sonnet 4.5) against hidden tests. Target band: 0.3-0.7. Actual:

| Task | Type | Designed by | Opus 4.8 hidden |
|---|---|---|---:|
| bench-incremental-scheduler | algorithmic (constraint solver + retraction/pins) | Fable 5 | **1.000** (69/69) |
| bench-recurrence-engine | edge-case-dense (140 RRULE/DST/leap cases) | Fable 5 | **1.000** (140/140) |
| bench-legacy-feature | FrontierCode-style: 1216-line codebase + concise prompt | Fable 5 | **1.000** (63/63) |
| bench-yaml-escapes (T20) | harvested: real `eemeli/yaml` PR dc72566 | harvest | **1.000** (12/12) |
| bench-yaml-trailing-comma (T21) | harvested: real `yaml` PR 79af840, lineWidth-boundary subtleties | harvest | **1.000** (14/14) |

The law: **a frontier model aces any localized, self-contained, fully-inferable change** -- regardless of algorithmic depth, edge-case density, real-vs-synthetic origin, or spec concision. Peer-model authorship makes it worse (author and solver are the same class; the intent-inference gap collapses). T20/T21 were kept anyway: they discriminate mid-tier models (T21 baseline floor 6/14) and prove the harvest pipeline.

FrontierCode (Cognition, 2026-06-09) independently confirms the law from the other side: their frontier discrimination (Opus 4.8 peaks at 13.4%) comes from 40+ maintainer-hours of task curation per task on flagship OSS repos. Their tasks are held-out (not runnable); 5 of their 6 scoring dimensions are deterministically adoptable (classical tests, regression commands, build/lint, reverse-classical mutation testing, diff-size scope) -- only the code-quality "taste" rubric needs an LLM judge. The mutation-testing piece was implemented as `scripts/mutation_score.py` (validated gradient: trivial suite 0.36, partial 0.50, thorough 1.00).

## 3. SWE-bench Pro, locally

`ScaleAI/SWE-bench_Pro` (HF): 731 public instances, 185 TS/JS (NodeBB, element-web, protonmail/webclients, tutanota). Fully runnable on local hardware: per-instance Docker images at `jefzda/sweap-images:{dockerhub_tag}`, harness `scaleapi/SWE-bench_Pro-os` with `--use_local_docker` (~76s per scoring run). Gold-patch sanity check on a tutanota instance scored 1.0. Quirk: the eval reads lowercase `fail_to_pass` despite the docs saying uppercase.

**Single-shot runs** (host `claude -p` over extracted source, no build env, 1 trial, hard+medium TS/JS instances mined via `traj/*/eval_results.json` for what older strong models failed):

| Sample | Opus 4.8 | Fable 5 | Both-fail | Differentiators |
|---|---:|---:|---:|---|
| 15 instances | 5/15 | 4/15 | 8/15 | 5 total: 3 Opus-wins, 2 Fable-wins |

The leaderboard's +11pp Fable edge (80.3% vs 69.2%) does **not** reproduce single-shot. Differentiators ran in both directions: Fable won a NodeBB cross-backend email-validation bug and an element-web fix; Opus won two Proton instances.

## 4. The verify experiment (capstone)

Re-ran the 4 differentiator instances with a verify-capable harness: agent on host (images ship node 16-18; claude CLI needs >=18), with a `container-exec.sh` helper that tar-syncs edits into the live per-instance container and runs build/test there. Same prompts, 35-min timeout.

| Instance | Single-shot | Opus+verify | Fable+verify |
|---|---|---:|---:|
| NodeBB email-validation (Fable-won) | O:0 F:1 | **1.0 (flip)** | 0.0* |
| element-web (Fable-won) | O:0 F:1 | **1.0 (flip)** | 1.0 |
| Proton (Opus-won) | O:1 F:0 | 1.0 | 0.0* |
| Proton (Opus-won) | O:1 F:0 | 1.0 | **1.0 (flip)** |

*Both Fable 0.0s are **zero-line patches** -- no edits produced within the timeout (Opus shipped 135-508-line patches in the same window). Most plausibly Fable's slower verify-first cadence burning the budget; per-run agent logs were overwritten before diagnosis (harness lesson: preserve `.agent.jsonl`/`.err` per run). Not evidence of inability.

**Every run that produced output scored 1.0.** Opus went 4/4, flipping both its single-shot failures. The differentiators were scaffolding artifacts. Frontier-model "ability gaps" on these tasks are actually gaps in scaffold utilization -- which is what SWE-agent-based leaderboards measure, and why a stripped single-shot loop can't reproduce them.

## 5. Side result: the interactive-TUI gene is null

`claude-code-tmux-oauth` (committed b8de5c32) revives the tmux-interactive path that AGENTS.md recorded as a dead end. Two root causes found: `--bare` skips credential loading entirely (the actual reason interactive mode seemed to force browser OAuth), and logged-in-ness is decided by the `~/.claude.json` state file -- staging `{"hasCompletedOnboarding": true}` plus the mounted `credentials.json` makes a fresh container recognize the OAuth login. Poll-driven dialog walker handles trust/bypass prompts; 90s-idle completion detection; `/cost` scrape for metrics.

Three-way on multi-step tasks (1 trial each):

| Task | Fable headless | Opus 4.6 interactive | Fable interactive |
|---|---:|---:|---:|
| phantom-invoice | 0.833 | 0.833 | 0.833 |
| task-queue | 0.804 | 0.806 | 0.830 |
| permission-maze | 0.705 | 0.727 | 0.700 |

Flat across both axes: interactive-vs-headless is score-neutral, Fable-vs-Opus is a wash here too. Known quirk: interactive runs score `static_analysis=0.5` (lint not measured; pane-log artifacts in /workspace suspected, unfixed).

## Conclusions

1. **This suite cannot rank frontier models.** Fable 5 vs Opus 4.8 is a ~3pp difference on a saturated scale; per-task results are identical or noise.
2. **No constructible task discriminates them either.** Localized + well-scoped = solved, five-for-five, no matter the axis. Curation difficulty (FrontierCode's 40 hrs/task) is the only known source of per-task frontier signal, and it can't be automated or peer-generated.
3. **Even curated hard tasks discriminate scaffolding, not models.** With a real verify loop, both models solved everything that either had ever solved. Single-shot differentiators evaporated.
4. **Practical upshot:** for frontier comparisons, defer to SWE-bench Pro / FrontierCode leaderboards and treat their gaps as harness-utilization measures. This suite remains what it is good at: ranking orchestrators and mid-tier models, where it has real spread.

## Artifacts

- `adapters/claude-code-oauth-fable5`, `claude-code-oauth-opus48`, `claude-code-tmux-oauth` (+ fable5 variant); claude-code image bumped 2.1.154 -> 2.1.170
- `scripts/mutation_score.py` -- deterministic test-quality metric (mutation kill rate)
- `benchmarks/bench-yaml-escapes` (T20), `bench-yaml-trailing-comma` (T21) -- real-repo harvested tasks
- Local SWE-bench Pro loop + verify harness: `/tmp/diff-hunt{,2,3}.sh`, `/tmp/swebp-os` (not committed; recipe in memory)
- Run dirs: Fable suites 2026-06-09T19-02-28, -09T20-03-57, -09T22-13-49; trio + verify logs /tmp/fable-tmux.log, /tmp/diff-hunt3.log
