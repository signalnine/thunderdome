# Thunderdome v6.3 Marathon Exemption Experiment Log

> **Hypothesis:** Adding marathon task classification to the TDD skill improves scores on marathon tasks (bench-task-queue, bench-time-tracker) without hurting greenfield TDD tasks (bench-beam-splitter).
>
> **Based on:** Behavioral analysis of 676 trials showing TDD hurts on marathon tasks (-3.8pp on bench-task-queue) due to thrashing (5+ fix cycles). See `2026-03-24-behavioral-analysis-findings.md`.
>
> **Experiment:** A/B test `conclave-v63-marathon-opus` (with marathon exemption + iteration guidance) vs `conclave-v6-opus` (baseline without marathon exemption) on 3 tasks x 2 trials each.

---

## Iteration 1 — 2026-03-25T06:03 (Initial Launch)

### Setup
- Created adapter `conclave-v63-marathon-opus` based on `conclave-v6-opus`
- Updated TDD SKILL.md in Docker build context with marathon task classification + iteration guidance
- Rebuilt `thunderdome/conclave:latest` Docker image
- Launched 12 trials: 2 orchestrators x 3 tasks x 2 trials each
- All trials use OAuth authentication

### Changes in v63 TDD skill vs v6:
1. **Task Classification section** — classifies tasks as Standard (strict TDD) or Marathon (iterative verification)
2. **Iteration Guidance section** — "target 3 test runs, 1-2 fix cycles"
3. **Completion Gate section** — full verification suite + diff review before claiming done

### Results (as of ~06:30, partial)

| Task | v63-marathon | v6-opus (baseline) | Delta | Notes |
|------|-------------|-------------------|-------|-------|
| bench-beam-splitter | 91.5% (93.6, 89.3) | 92.5% (96.0, 88.9) | **-1.0pp** | Control — within noise |
| bench-time-tracker | 83.8% (83.5, 84.0) | 89.0% (89.0, 89.0) | **-5.2pp** | Unexpected regression |
| bench-task-queue | *pending* | *pending* | — | Primary target (marathon) |

### Early Observations
- **beam-splitter (control):** Essentially a wash. Marathon exemption doesn't hurt greenfield TDD. Good.
- **time-tracker (surprising):** v63 scores 5.2pp worse. Time-tracker is a simple greenfield task (15min limit), NOT a marathon task. The marathon exemption shouldn't change behavior here. Possible explanations:
  - The added Completion Gate / Iteration Guidance sections are consuming context or changing agent behavior on non-marathon tasks
  - The extra skill text (~500 words added) is diluting the core TDD message
  - Random variance (only 2 trials each)
- **task-queue:** Still running (60min time limit). This is the real test.

---

## Iteration 2 — 2026-03-25T07:15 (Task-Queue Results)

### New Results

Task-queue trials complete for v63-marathon (2 trials) and v6-opus (1 of 2 trials). v6-opus trial 2 still running.

### Final Results Table

| Task | v63-marathon (new) | v6-opus (baseline) | Delta | Verdict |
|------|-------------------|-------------------|-------|---------|
| bench-beam-splitter | 91.5% (93.6, 89.3) | 92.5% (96.0, 88.9) | **-1.0pp** | Neutral (within noise) |
| bench-time-tracker | 83.8% (83.5, 84.0) | 89.0% (89.0, 89.0) | **-5.2pp** | Regression |
| bench-task-queue | 62.0% (61.1, 62.8) | 63.6% (1 trial) | **-1.6pp** | Neutral/slight regression |

### Key Finding: Marathon Exemption Did NOT Help

The primary hypothesis — that routing marathon tasks away from strict TDD would improve scores on bench-task-queue — is **not confirmed**. v63-marathon scored 62.0% vs v6-opus 63.6%, essentially flat with a slight regression.

### Analysis

**Why didn't the marathon exemption help?**

Three possible explanations:

1. **The agent may not be classifying the task correctly.** The marathon exemption relies on the agent recognizing the task as "marathon" and switching to iterative verification. If the agent still uses strict TDD (or no TDD at all), the skill text change has no behavioral effect. Need to check NDJSON traces.

2. **The additional skill text may be hurting.** The v63 TDD skill is ~500 words longer (Task Classification, Iteration Guidance, Completion Gate). On time-tracker (-5.2pp), this extra text may be diluting the core TDD message or causing the agent to spend time classifying instead of coding. This would explain why time-tracker regressed even though it's not a marathon task.

3. **TDD compliance was already low on task-queue.** From the 676-trial analysis: only 4 trials had TDD compliance on bench-task-queue. If agents rarely do TDD on this task regardless of skill text, then exempting marathon tasks from TDD has no practical effect — you're exempting them from something they weren't doing anyway.

### Hypotheses to Test

- **H1:** v63 agents are NOT actually classifying task-queue as marathon (check NDJSON traces for classification behavior)
- **H2:** The extra skill text is causing regression on non-marathon tasks (isolate: test iteration guidance alone vs task classification alone)
- **H3:** The regression on time-tracker is due to the Completion Gate section consuming time on a 15-min task

### Next Steps
- [ ] Analyze NDJSON traces from v63 task-queue trials — did the agent classify as marathon? Did it use iterative verification?
- [ ] Analyze NDJSON traces from v63 time-tracker trials — what behavioral difference caused the -5.2pp?
- [ ] Compare behavioral profiles (test runs, fix cycles, TDD compliance) between v63 and v6 across all tasks
- [ ] Wait for v6-opus task-queue trial 2
- [ ] Consider running a "skill text only" variant that adds ONLY iteration guidance (no task classification, no completion gate) to isolate the effect

---

## Iteration 3 — 2026-03-25T07:17 (Trace Analysis)

### New Results

v6-opus beam-splitter T1 came in: 96.0%. v6-opus task-queue T2 still running.

Updated averages:
| Task | v63-marathon | v6-opus | Delta |
|------|-------------|---------|-------|
| beam-splitter | 91.5% | **92.5%** (96.0, 88.9) | -1.0pp |
| time-tracker | 83.8% | **89.0%** (89.0, 89.0) | -5.2pp |
| task-queue | 62.0% | 63.6% (1 trial) | -1.6pp |

### Behavioral Signal Comparison (Trial 1 of each)

| Signal | v63 task-queue | v6 task-queue | v63 time-track | v6 time-track | v63 beam-split | v6 beam-split |
|--------|---------------|---------------|----------------|---------------|----------------|---------------|
| test_runs | 5 | 2 | 3 | 4 | 5 | 10 |
| fix_cycles | 3 | 2 | 3 | 2 | 3 | 6 |
| TDD | No | No | No | Yes | No | No |
| commits | 2 | 2 | 2 | 0 | 2 | 2 |
| diff_review | Yes | No | Yes | Yes | Yes | No |
| build | Yes | Yes | Yes | Yes | Yes | Yes |
| lint | Yes | Yes | Yes | Yes | Yes | Yes |
| skills invoked | TDD, plans, SDD, VBC | brainstorm, plans, SDD | TDD | brainstorm, TDD, VBC | TDD | TDD, VBC |
| marathon_mentioned | Yes | No | Yes | Yes | Yes | Yes |
| task_classified | Yes | No | No | No | Yes | Yes |
| iterative_verif | Yes | No | Yes | Yes | Yes | Yes |

### Key Findings

**H1 CONFIRMED: v63 IS classifying task-queue as marathon.**
The v63 agent explicitly says: "This is clearly a **marathon task** — 12 distinct phases/sub-features. Per the TDD skill, I'll use the **Iterative Verification** pattern." It then uses iterative verification. This is the desired behavior.

**SURPRISE: v6 also mentions marathon/iterative verification on some tasks.**
The v6-opus time-tracker agent says "This is a marathon task" and uses iterative verification — even though v6 doesn't have the Task Classification section! This means the agent is picking up on the "marathon" concept from somewhere else (possibly the using-conclave skill or general training). This dilutes the experiment — v6 is partially already doing what v63 was supposed to add.

**The REAL behavioral difference is in skill routing, not TDD approach:**

- **v6 task-queue:** brainstorming → writing-plans → subagent-driven-development (heavy ceremony)
- **v63 task-queue:** TDD (classified as marathon) → writing-plans → subagent-driven-development (still heavy)

Both ended up with plans + subagent-driven-development. The v63 agent added TDD skill invocation on top, which the v6 agent skipped. Neither agent did actual strict TDD on task-queue (TDD=false for both).

**Time-tracker regression explained:**
- v63: Classified as marathon (wrong!), skipped TDD RED phase, wrote implementation + tests together → 83.8%
- v6: Correctly recognized as greenfield, used TDD (test-first), had actual RED-GREEN cycle → 89.0%

The marathon exemption is **misclassifying time-tracker as marathon** because it has "multiple features" (start/stop, persistence, filtering, summary). The classification heuristic ("3+ sub-features") is too aggressive — it catches tasks that are really just one cohesive feature with multiple aspects.

### Revised Hypothesis

**The marathon exemption text is causing the agent to over-classify as marathon, skipping TDD on tasks where TDD helps.** The -5.2pp on time-tracker is because the agent saw "multiple features" and chose iterative verification over test-first development. On task-queue (a genuine marathon task), the agent was already not doing TDD, so the exemption had no practical effect.

### Implications

1. **The marathon classification heuristic needs to be much more specific.** "3+ sub-features" is too broad. It should be something like "12+ phases", "explicitly sequential multi-day workflow", or tied to specific task structure (like a phases/ directory).

2. **Adding skill text can backfire.** The 500 extra words (Task Classification, Iteration Guidance, Completion Gate) changed behavior on non-target tasks. The time-tracker regression is a direct consequence.

3. **The v6 baseline already partially implements marathon awareness** through the agent's training or the existing using-conclave skill text. The marginal value of explicit classification is lower than expected.

### Next Steps
- [ ] Wait for v6-opus task-queue T2 to complete the dataset
- [ ] Consider reverting the marathon exemption from the TDD skill — the cost (time-tracker regression) exceeds the benefit (no improvement on task-queue)
- [ ] If keeping marathon exemption: tighten the classification criteria significantly (e.g., "10+ sequential phases" not "3+ sub-features")
- [ ] Run a variant with ONLY iteration guidance (no task classification) to isolate the value of "target 3 test runs, 1-2 fix cycles"

---

## Iteration 4 — 2026-03-25T07:45 (Complete Dataset)

### v6-opus task-queue T2 arrived: 64.2%

### Final Results (all 12 trials complete)

| Task | v63-marathon (new) | v6-opus (baseline) | Delta | N |
|------|-------------------|-------------------|-------|---|
| bench-beam-splitter | 91.5% (93.6, 89.3) | 92.5% (96.0, 88.9) | **-1.0pp** | 4 |
| bench-time-tracker | 83.8% (83.5, 84.0) | 89.0% (89.0, 89.0) | **-5.2pp** | 4 |
| bench-task-queue | 62.0% (61.1, 62.8) | 63.9% (63.6, 64.2) | **-1.9pp** | 4 |
| **Weighted avg** | **79.1%** | **81.8%** | **-2.7pp** | **12** |

### Verdict

**The marathon exemption is a net negative across all three tasks.** It didn't help on the target task (task-queue: -1.9pp), and it hurt on non-target tasks (time-tracker: -5.2pp). The beam-splitter control is within noise (-1.0pp).

### Cost comparison

| Orchestrator | Avg cost/trial | Avg duration |
|---|---|---|
| v63-marathon | $1.72 | 407s |
| v6-opus | $1.84 | 421s |

Costs are similar. v63 is marginally cheaper/faster but scores worse.

### Root causes (from Iteration 3 trace analysis)

1. **Over-classification:** The agent classifies time-tracker as "marathon" (wrong), skipping test-first TDD where it helps
2. **No practical effect on true marathon tasks:** Task-queue agents don't do TDD regardless of skill text
3. **Extra skill text dilutes core message:** 500 additional words change behavior even on non-target tasks

### Decision

**Recommend reverting the marathon exemption from the TDD skill.** The experiment clearly shows it's a net negative. The iteration guidance and completion gate sections may still have value but should be tested independently.

### Open questions for future experiments
1. Does iteration guidance alone ("target 3 test runs") help without task classification?
2. Does the completion gate section alone improve scores?
3. Can we improve task-queue scores through a completely different approach (e.g., better planning, not TDD changes)?

---

---

## Iteration 5 — 2026-03-25T08:17 (Deep Dive: Iteration Guidance Effect)

### Analysis: Does "target 3 test runs" actually help?

Examined test run sequences in beam-splitter traces to assess iteration guidance impact:

| Trial | Test runs | Fix cycles | Hidden tests | Code metrics | Score |
|-------|-----------|------------|-------------|-------------|-------|
| v6 beam-split T1 | **10** (7 consecutive vitest reruns) | 6 | 1.0 | **0.9** | **96.0%** |
| v63 beam-split T1 | **5** (iteration guidance working) | 3 | 1.0 | 0.7 | 93.6% |

**Finding:** Iteration guidance successfully reduced thrashing (10→5 test runs) but **didn't improve scores**. The v6 agent's 7 consecutive test reruns were fixing real issues — each cycle improved code quality (code_metrics 0.9 vs 0.7). The "stop after 3" heuristic may terminate productive iteration prematurely.

### Nuance from 676-trial analysis vs live experiment

The original 676-trial data showed 3 test runs as optimal (89.9%) with 5+ runs declining (81.7%). But that was an *aggregate* correlation — agents running 5+ tests were often *stuck* (same error repeating). The v6 beam-splitter agent ran 10 tests but wasn't stuck — it was making genuine progress each cycle.

**Key insight:** The optimal number of test runs depends on whether runs are productive (fixing new issues) or unproductive (same error repeating). A fixed cap ("stop after 3") can't distinguish between these cases. The ralph-loop's "same error 3x = stuck" heuristic is actually better calibrated.

### Implications for iteration guidance text

The current iteration guidance says:
> **Target 3 test runs.** More than 5 test runs on the same feature means you're stuck.

This should probably be revised to:
> **If the same test keeps failing with the same error after 3 attempts, step back and rethink.** But if each run reveals new issues, keep iterating — progress is progress.

This aligns with the ralph-loop stuck detection pattern (MD5-based same-error detection) rather than a raw count threshold.

### Updated open questions
1. ~~Does iteration guidance alone help?~~ → Probably not with a fixed count. Error-pattern-based stuck detection is better.
2. Does the completion gate section alone improve scores? → Still untested.
3. Can we improve task-queue through better planning/approach rather than TDD changes? → Most promising avenue.
4. **NEW:** Would a "stuck detection" prompt (like ralph-loop's "same error 3x = rethink") outperform a fixed iteration cap?

---

## Iteration 6 — 2026-03-25T09:17 (Tool Sequence Analysis)

### Correcting the test run count methodology

Earlier analysis overcounted test runs (regex matched `cat vitest.config.ts` as a test). Recounted using `^(npm test|npx vitest run)` prefix matching:

| Trial | Test runs | Edits | Edit:Test ratio |
|-------|-----------|-------|-----------------|
| v6 beam-split T1 (96.0%) | 8 | 7 | 0.88 |
| v63 beam-split T1 (93.6%) | 5 | 5 | 1.00 |
| v6 time-track T1 (89.0%) | 4 | 3 | 0.75 |
| v63 time-track T1 (83.5%) | 3 | 5 | 1.67 |
| v6 task-queue T1 (63.6%) | 2 | 26 | 13.0 |
| v63 task-queue T1 (62.0%) | 5 | 9 | 1.80 |

### Key finding: v6 beam-splitter test runs were ALL productive

Full tool sequence analysis of v6 beam-splitter T1 shows every test rerun (steps 12-27) had a Read→Edit→Test cycle between them. The 6 consecutive `vitest run` calls weren't thrashing — each fixed a different issue. This is **healthy red-green iteration**, not stuck looping.

The tool sequence: `Edit(impl)→Edit(test)→TEST→Edit(impl)→TEST→Edit(test)→TEST→Edit(impl)→TEST→Edit(impl)→TEST→Edit(test)→TEST→TEST(full)→BUILD→LINT→VBC`

### Corrected interpretation

Iteration 5 concluded that "the extra thrashing on v6 led to better code quality." This is misleading — it wasn't thrashing, it was productive iteration. The v6 agent's 8 test runs each found and fixed a new issue, leading to code_metrics 0.9 vs v63's 0.7.

**The iteration guidance ("stop after 3 test runs") actively prevented productive iteration on beam-splitter.** The v63 agent stopped too early, leaving code quality issues unfixed.

### Edit-to-test ratio as a diagnostic

| Pattern | Edit:Test ratio | Meaning |
|---------|----------------|---------|
| ~1.0 | Healthy TDD cycle (edit → test → edit → test) |
| <0.5 | Possible stuck (testing without making changes) |
| >5.0 | Big-bang development (many edits, few tests) |

v6 task-queue had ratio 13.0 (26 edits, 2 tests) — classic big-bang. v63 task-queue had 1.8 — more incremental but still not TDD.

### Summary of what we've learned from this experiment

1. **Marathon task classification hurts more than it helps** (-2.7pp net). The heuristic is too aggressive, misclassifying simple greenfield tasks as marathon.
2. **Fixed iteration caps are harmful.** "Target 3 test runs" stopped productive iteration early. Error-pattern-based stuck detection (ralph-loop's approach) is better.
3. **Adding 500 words of skill text has measurable cost.** Even when the new text is correct guidance, it changes agent behavior on non-target tasks.
4. **TDD compliance on marathon tasks is already low** (~4/50 trials). Exempting agents from TDD they weren't doing has no effect.
5. **The v6 baseline already has partial marathon awareness** from model training. Explicit classification adds marginal value.

---

## Experiment Complete

**Total cost:** ~$21 across 12 trials
**Duration:** ~2 hours wall clock
**Outcome:** Marathon exemption hypothesis rejected — net -2.7pp across tasks
**Bonus findings:**
- Fixed iteration caps harm productive iteration; stuck detection should be error-pattern-based
- Edit:test ratio is a useful diagnostic (1.0=healthy TDD, <0.5=stuck, >5.0=big-bang)
- Adding skill text has measurable cost even when guidance is correct
