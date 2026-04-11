# Conclave v7: Adaptive Task Routing

## Problem

Conclave Review (#1 overall at 87.8%, 139 trials) applies a uniform strategy — vanilla coding + one consensus code review — to every task. This works brilliantly on deterministic tasks (98-100%) but leaves 20-30pp on the table for state-heavy tasks:

| Task Type | Conclave Review | Best Competitor | Gap | Best Strategy |
|-----------|----------------|-----------------|-----|---------------|
| Deterministic (T3,T4,T6,T9,T11,T14) | 98-100% | — | — | Consensus review (current) |
| State-heavy (T5,T8) | 62-67% | Double-Review: 78-84% | -17pp | Two review passes |
| Simple greenfield (T1) | 82.4% | Sonnet gstack: 92.0% | -10pp | Unknown — review still helps |
| Complex greenfield (T2,T7,T10) | 75-87% | Plans Opus: varies | -5pp | Plans-first + review |
| Ambiguous (T15) | 69.8% | Plans+gstack: 76.9% | -7pp | Plans-first |
| Reasoning/hard (T12-T19 ex T15) | 84-95% | Sonnet Plans: 89.0% | -1pp | Plans-first (marginal) |

## Validation Results

### H1: Double-Review Helps State Tasks — CONFIRMED (n=3)

| Task | Conclave Review (n=18+) | Double-Review (n=3) | Trials | Delta |
|------|------------------------|---------------------|--------|-------|
| T5 (task-queue) | 66.8% | 84.2% | 94.1, 94.7, 63.9 | **+17.4pp** |
| T8 (analytics-dashboard) | 62.5% | 77.6% | 88.0, 92.3, 52.6 | **+15.1pp** |

The n=2 data (94.4% / 90.2%) was optimistic — the third trial for each task scored much lower (63.9% / 52.6%), showing high variance. But the mean improvement is still large (+15-17pp). Also validated with `conclave-double-review-keys-opus` (n=4 T5: 79.8%, n=2 T8: 91.3%).

**Verdict: Ship it.** Effect size is large (+15-17pp) even accounting for variance. The 2/3 "good" trials (90%+) suggest the intervention works when the double-review actually catches constraint issues; the 1/3 "bad" trials likely represent cases where the initial implementation was too broken for review to save.

### H2: Skip-Review Helps Simple Tasks — DISCONFIRMED

| Task | Vanilla Claude Code (n=7) | Conclave Review (n=18+) | Delta |
|------|--------------------------|------------------------|-------|
| T1 (time-tracker) | 77.7% | 82.4% | **-5pp** |

Vanilla scores *worse* on T1, not better. The hypothesis that review overhead hurts simple tasks is wrong — the code review catches real bugs even on straightforward greenfield work.

**Verdict: Drop the skip-review fast path.** Keep review on all tasks.

### H3: Plans-First Helps Hard Tasks — MARGINAL

| Orchestrator | Hard Mean | n | Notable Wins | Notable Losses |
|-------------|-----------|---|---|---|
| Conclave Review | 88.2% | 52 | T12 (94.5%), T17 (84.7%) | T15 (69.8%) |
| Sonnet Plans | 89.0% | 24 | T13 (96.7%), T18 (94.1%) | T17 (74.7%) |
| Plans Opus | 88.3% | 24 | T16 (92.2%), T14 (100%) | T18 (81.1%) |
| Plans+gstack | 88.3% | 23 | T19 (94.7%), T15 (76.9%) | T16 (67.0%*) |

*T16 outlier: one trial scored 20%, dragging the mean.

Plans-first is +0.8pp over Review on hard tasks — within statistical noise at these sample sizes. The per-task profile is different (plans wins T13/T15/T16, review wins T12/T17) but the aggregate effect is negligible.

**Verdict: Optional.** Not worth the routing complexity for +0.8pp. Could revisit if plans-first is combined with double-review.

## Revised Design (Post-Validation)

### Core Change: Two-Path Router

The original 5-way router is overfit. Validation shows only ONE intervention has a clear, large effect: double-review on state-heavy tasks. Simplify to a 2-path router:

```
1. STATE-HEAVY GREENFIELD
   Signal: greenfield + complex state management, async, real-time, constraint propagation
   Keywords: "concurrent", "real-time", "state", "queue", "dashboard", "WebSocket",
             "scheduler", "constraint", "propagation"
   Strategy: Implement → review #1 → fix → review #2 (focus: constraint violations)
   Evidence: +15-17pp on T5 and T8 (validated n=3 means: 84%/78% vs 67%/63%)

2. EVERYTHING ELSE (DEFAULT)
   Strategy: Current Conclave Review behavior (implement → single review)
   Evidence: Already #1 overall at 87.8%
```

This is a much smaller, safer change than the original 5-way router. It targets the single highest-impact gap (state-heavy tasks at 62-67%) with a validated intervention.

### Implementation

#### 1. Modify `using-conclave/SKILL.md` — Add State-Heavy Detection

Add to the existing task classification section:

```markdown
## State-Heavy Task Detection

After classifying the task type (above), check if it also involves complex state management.

**Compound signals (any ONE is sufficient):**
- Concurrent/async operations with ordering constraints
- Real-time updates where one operation's side effects affect others
- Constraint propagation (changing one value must update dependents)
- State machine with multiple transitions that must maintain invariants

**Supporting keywords (need 2+ alongside a compound signal):**
queues, dashboards, WebSockets, state machines, schedulers, concurrent, real-time

**When in doubt, classify as state-heavy.** The cost of a false positive is ~$0.40
for an extra review pass. The cost of a false negative is -15pp on a hard task.

**Decision point:** The agent reading this skill makes the classification at task start,
before invoking the first skill. Log the decision: "State-heavy: yes/no — [reason]".

If state-heavy: after implementation and first code review, run a SECOND
code review (see requesting-code-review skill, "Second-Pass Review").
```

#### 2. Add Second-Pass Review to `requesting-code-review/SKILL.md`

```markdown
## Second-Pass Review (State-Heavy Tasks Only)

After addressing first-review findings, run a second review with this focus prompt.

**Important:** This review must be independent. Assume the first review's findings
may NOT have been fully addressed. Do not rubber-stamp — verify from scratch.

"Review this implementation with fresh eyes, specifically for:
1. State consistency: Can any operation leave the system in an invalid state?
2. Constraint propagation: When one value changes, are all dependent values updated?
3. Race conditions: Can concurrent operations produce inconsistent results?
4. Edge cases: What happens at boundaries (empty, full, overflow, underflow)?
5. Performance invariants: Are state update paths O(n) or better? Any hidden O(n²)?
Assume nothing from prior reviews. Ignore code style and naming — focus only on correctness.
Verify each property by tracing through the code, not by checking review comments."
```

#### 3. Bump Version

`.claude-plugin/plugin.json` → version 6.2.0 (additive change, not breaking)

### What Does NOT Change

- The completion gate (mandatory on every path)
- The consensus binary and review infrastructure
- Existing skills (TDD, brainstorming, debugging, etc.)
- The hook injection mechanism
- The Go binary commands
- Review behavior on non-state-heavy tasks

### Files Modified

1. `skills/using-conclave/SKILL.md` — Add state-heavy detection block
2. `skills/requesting-code-review/SKILL.md` — Add second-pass review section
3. `.claude-plugin/plugin.json` — Bump version to 7.0.0

## Expected Impact (Revised)

| Metric | v6 Review | v7 Adaptive | Delta |
|--------|-----------|-------------|-------|
| Overall | 87.8% | ~88.9% | +1.1pp |
| Standard | 87.4% | ~88.9% | +1.5pp |
| Hard | 88.2% | ~88.2% | ~0pp |
| Cost/task | $1.86 | ~$1.94 | +$0.08 |
| T5 (task-queue) | 66.8% | ~84% | +17pp |
| T8 (analytics) | 62.5% | ~78% | +15pp |

Cost *increases* slightly (~$0.08/task amortized) because double-review adds ~$0.40 per state-heavy task (2 out of 19 tasks). But the +15-17pp improvement on those tasks is worth it.

No cost savings from skipping review (H2 disconfirmed). No hard task improvement from plans-first routing (H3 marginal).

## Risk Mitigation

- **Router misclassification (false positive)**: If the router incorrectly classifies a non-state-heavy task as state-heavy, the agent runs an extra review pass. Worst case: ~$0.40 wasted, no quality degradation (extra review is additive).
- **Router misclassification (false negative)**: If it misses a state-heavy task, behavior is identical to current v6. No regression.
- **Double-review cost**: Second review adds ~$0.40/task, but only on 2 tasks (T5, T8), so amortized cost is ~$0.04/task across the suite.
- **Variance in double-review**: n=3 shows high variance (2/3 trials score 88-95%, 1/3 scores 52-64%). **Decision: accept the variance.** The ~1/3 failure rate likely represents implementations too broken for review to save — the same trials would also fail under single review. The expected value (+15-17pp) is large enough that even with 1/3 failures, the intervention is net positive. We do NOT add an abort heuristic at this time; the added complexity isn't justified when the failure case is equivalent to the current baseline behavior.
- **Confirmation bias in second review**: The second-pass review prompt explicitly instructs the reviewer to treat the implementation as unreviewed and verify properties from scratch rather than checking whether first-review findings were addressed. This guards against the second pass rubber-stamping the first.

## Monitoring & Rollback

**Post-deployment measurement:**
- Track whether the second review fires: the completion gate should log "State-heavy: double-review completed" to stderr when the second pass runs
- Measure T5/T8 scores on the next 10 runs of these tasks in Thunderdome to confirm the intervention holds
- Track overall suite score to confirm no regression on non-state-heavy tasks

**Rollback criteria:**
- If overall score drops more than 2pp in the first 20 trials post-v7, revert state-heavy detection to v6 (single review for all tasks)
- If T5/T8 scores show no improvement over baseline (below +10pp delta) after 6+ trials, re-evaluate the router heuristic

## Future Work (Not in v7)

- **Plans-first for specific hard tasks**: H3 shows plans-first wins on T13/T15/T16 but loses on T12/T17. A more targeted per-task router might help, but the complexity isn't justified by the marginal aggregate gain.
- **T1 improvement**: Review doesn't hurt T1, but we're still 10pp below Sonnet gstack (92.0%). The gap may be model-level (gstack uses a different Sonnet configuration) rather than methodology.
- **T15 (permission-maze)**: The hardest task for everyone. Plans+gstack shows 76.9% vs Review's 69.8%, but the sample is small and the mechanism unclear.
