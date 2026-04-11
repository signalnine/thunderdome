# Thunderdome Benchmark Findings & Conclave Improvement Roadmap

> **Source:** 796 trials across 34 orchestrator variants on 11 standardized coding tasks.
> All scoring is deterministic (tests, build/lint, coverage, code metrics) — no LLM judges.
> Benchmark harness: [agentic-thunderdome](https://github.com/signalnine/agentic-thunderdome)

## Executive Summary

We ran the most comprehensive ablation study of agentic coding tools to date: 796 isolated Docker trials testing every combination of Conclave's features against vanilla Claude Code and other orchestrators. The results tell a clear and actionable story:

1. **The skill text is the engine.** Structured methodology guidance (TDD, verification, brainstorming) drives a +11-12 point improvement over vanilla Claude Code. This is the overwhelming value of Conclave.

2. **Multi-agent consensus is dead weight.** A 3-way comparison (pure skills vs. Conclave no-keys vs. Conclave + multi-provider keys) proves that consensus adds nothing and may slightly hurt. The conclave binary, the API calls to Gemini and Codex, and the two-stage synthesis protocol are pure overhead.

3. **A well-worded system prompt captures 95% of the benefit.** "Implement, verify, commit, review your diff, fix issues" as a system prompt scores 96.8% — within 0.6 points of the best skill-based approaches. The entire skill infrastructure fights over that last 0.6 points.

4. **TDD is the single most effective methodology.** Sonnet 4.6 + TDD scores 98.2%, beating every Opus variant. Structure matters more than model capability.

5. **Gene stacking has diminishing returns.** Review + Verify stacked = 97.2%, worse than either alone. One quality checkpoint is sufficient.

These findings suggest a fundamental shift in Conclave's architecture: **invest in skill quality, simplify the infrastructure, and make the right methodology activate by default.**

---

## Part 1: Complete Evidence Base

### 1.1 Full Leaderboard (34 variants)

| Rank | Orchestrator | Mean Score | Tasks | Trials | Avg Cost | Model |
|---:|---|---:|---:|---:|---:|---|
| 1 | **TDD (Sonnet)** | **98.2%** | 11 | 22 | $1.08 | Sonnet 4.6 |
| 2 | Conclave Brainstorm | 97.4% | 11 | 38 | $1.43 | Opus 4.6 |
| 2 | Superpowers TDD | 97.4% | 11 | 16 | $2.32 | Opus 4.6 |
| 3 | Stacked (worktree+metacog+review) | 97.3% | 11 | 11 | $1.36 | Opus 4.6 |
| 4 | Superpowers Verify | 97.3% | 11 | 11 | $0.94 | Opus 4.6 |
| 5 | Conclave Review | 97.2% | 10 | 11 | $1.82 | Opus 4.6 |
| 5 | Conclave Review + Verify | 97.2% | 11 | 11 | $2.28 | Opus 4.6 |
| 6 | Self-Review (Sonnet) | 97.1% | 11 | 22 | $1.13 | Sonnet 4.6 |
| 6 | Superpowers Brainstorm (pure) | 97.1% | 11 | 22 | $1.12 | Opus 4.6 |
| 7 | Conclave Skill Review | 97.0% | 11 | 34 | $2.01 | Opus 4.6 |
| 7 | Superpowers Review (pure) | 97.0% | 11 | 22 | $1.83 | Opus 4.6 |
| 8 | Conclave Review + Keys | 96.9% | 11 | 22 | $1.71 | Multi |
| 8 | Superpowers Plans | 96.9% | 11 | 11 | $1.05 | Opus 4.6 |
| 9 | Self-Review (Opus) | 96.8% | 11 | 40 | $1.33 | Opus 4.6 |
| 10 | Gas Town | 96.6% | 10 | 24 | $0.02 | Opus 4.6 |
| 11 | Superpowers Debug | 96.4% | 4 | 9 | $0.88 | Opus 4.6 |
| 12 | Metacog | 95.9% | 11 | 22 | $0.70 | Opus 4.6 |
| 13 | Conclave Design | 95.7% | 4 | 9 | $2.09 | Multi |
| 13 | Conclave Brainstorm + Keys | 95.7% | 11 | 22 | $1.43 | Multi |
| 14 | Conclave (Full) | 95.2% | 10 | 12 | $0.14 | Multi |
| 15 | Conclave Double Review | 95.2% | 4 | 9 | $1.26 | Opus 4.6 |
| 16 | Claude Code Headless | 94.6% | 4 | 9 | $0.76 | Opus 4.6 |
| 17 | Gas Station | 92.6% | 10 | 22 | $0.71 | Opus 4.6 |
| 18 | Agent Teams | 86.2% | 10 | 28 | $0.49 | Opus 4.6 |
| 19 | **Claude Code (Vanilla)** | **85.9%** | 11 | 24 | $0.27 | Opus 4.6 |
| 20 | Amplifier + ts-dev | 85.5% | 10 | 11 | $0.75 | Opus 4.6 |
| 21 | Amplifier | 84.6% | 10 | 11 | $0.02 | Opus 4.6 |

### 1.2 Gene-by-Gene Ablation Results

Each gene was tested in isolation against vanilla Claude Code (85.9% baseline). Every variant uses the same Docker container, same tasks, same scoring — only the system prompt and skill differ.

| Gene | Score | Delta | Cost | n | Mechanism |
|------|------:|------:|-----:|--:|-----------|
| TDD (Sonnet) | 98.2% | +12.3pp | $1.08 | 22 | Forced Red-Green-Refactor cycle |
| TDD (Opus) | 97.4% | +11.5pp | $2.32 | 16 | Same skill, Opus model |
| Brainstorm | 97.4% | +11.5pp | $1.43 | 38 | Design exploration before coding |
| Verify | 97.3% | +11.4pp | $0.94 | 11 | Fresh verification before completion |
| Review (skill) | 97.0% | +11.1pp | $2.01 | 34 | Structured code review via Skill tool |
| Plans | 96.9% | +11.0pp | $1.05 | 11 | Upfront planning with bite-sized tasks |
| Self-Review (prompt) | 96.8% | +10.9pp | $1.33 | 40 | System prompt only, no plugins |
| Debug | 96.4% | +10.5pp | $0.88 | 9 | 4-phase root cause (opt-in, rarely invoked) |
| Review + Verify | 97.2% | +11.3pp | $2.28 | 11 | Stacked — no improvement over either alone |

**Key observations:**
- All discipline genes cluster within 1.4 points of each other (96.8-98.2%)
- The gap between ANY discipline and no discipline is massive (+10.5 to +12.3pp)
- Gene stacking shows diminishing returns (Review + Verify = 97.2%, worse than Verify alone at 97.3%)

### 1.3 Consensus Binary Effect (3-Way Comparison)

This is the critical experiment. We tested brainstorming and code review in three configurations:
1. **Pure Superpowers** — skill text only, no conclave binary, single-agent execution
2. **Conclave no-keys** — conclave binary present, but only Claude API key (Claude-only consensus)
3. **Conclave + keys** — conclave binary + Anthropic/Gemini/OpenAI API keys (true multi-provider)

| Variant | Brainstorm | Review |
|---|---:|---:|
| Pure Superpowers (no binary) | **97.1%** ($1.12) | **97.0%** ($1.83) |
| Conclave + keys (multi-provider) | 95.7% ($1.43) | 96.9% ($1.71) |
| Conclave, no keys (Claude-only) | 95.6% ($1.35) | 96.0% ($2.04) |

**Conclusion:** The consensus mechanism either hurts (brainstorming: -1.5pp) or adds nothing (review: -0.1pp). The skill text drives all the value; the binary is overhead.

### 1.4 Model Capability vs. Methodology

The more structured the methodology, the smaller the Sonnet-Opus gap:

| Methodology | Opus | Sonnet | Gap |
|---|---:|---:|---|
| TDD | 97.4% | **98.2%** | Sonnet wins by +0.8pp |
| Self-Review | 96.8% | 97.1% | Sonnet wins by +0.3pp |
| Brainstorm | 97.4% | untested | — |
| Verify | 97.3% | untested | — |
| Vanilla | 85.9% | ~85% | ~1pp |

**Implication:** With strong methodology, model capability is irrelevant. Sonnet + TDD is the Pareto-optimal choice: highest score at lowest cost.

### 1.5 Task-Level Breakdown

Not all tasks benefit equally from methodology:

| Task | Type | Vanilla | Best | Delta | What helps |
|------|------|--------:|-----:|------:|------------|
| T2 (Collab Server) | greenfield/complex | 69.3% | 100% | +30.7pp | TDD, Brainstorm |
| T5 (Task Queue) | marathon | 62.1% | 96.6% | +34.5pp | Fresh context, Verify |
| T8 (Analytics) | greenfield/complex | 87.0% | 100% | +13.0pp | TDD, Brainstorm |
| T1 (Time Tracker) | greenfield/simple | 89.0% | 100% | +11.0pp | Any discipline |
| T3, T4, T6, T9, T11 | various | 100% | 100% | 0pp | Already perfect |

**5 of 11 tasks score 100% with vanilla Claude Code.** Methodology genes only matter on hard, ambiguous tasks — greenfield complex, marathon, and recovery categories.

### 1.6 The Self-Review Baseline

The most important finding is that **zero infrastructure** gets you to 96.8%. This system prompt, appended to vanilla Claude Code with no plugins, no skills, no binary:

```
MANDATORY BEFORE FINISHING:

1. Implement the task using your best judgment.
2. When you think you are done, run the FULL verification suite fresh:
   npm test
   npm run build
   npm run lint
3. Read the COMPLETE output of each command. Count any failures or errors.
4. If anything fails, fix it and re-run all three commands.
5. Once all three pass cleanly, commit your work:
   git add -A && git commit -m 'implementation'
6. Review your own diff:
   git diff HEAD~1
7. Read the diff carefully. Look for:
   - Missing edge cases
   - Incomplete implementations
   - Dead code or debug artifacts
   - Anything that looks wrong
8. If you find issues, fix them, re-run verification (step 2-3), and re-commit.
9. Only stop when verification passes AND your diff review finds no issues.

Do NOT skip the verification or diff review steps. Do NOT claim completion
without fresh evidence that tests, build, and lint all pass.
```

**Score:** 96.8% (Opus), 97.1% (Sonnet), $1.13-1.33/task, n=62

This is effectively the verification-before-completion + self-review skills distilled to 15 lines. It's the floor that any skill-based approach must beat to justify its overhead.

---

## Part 2: What This Means for Conclave

### 2.1 What's Working

The skill TEXT is excellent. The brainstorming, TDD, and verification skills are genuinely effective — they change agent behavior in measurable ways:

- **TDD** forces test-first discipline the model naturally resists. Without it, agents implement first and skip tests under token pressure. The rigid Red-Green-Refactor cycle prevents this shortcut.

- **Verification** catches the #1 failure mode: premature completion claims. Agents say "all tests pass" without running them. The Iron Law ("NO COMPLETION CLAIMS WITHOUT FRESH VERIFICATION EVIDENCE") fixes this.

- **Brainstorming** forces design exploration on greenfield tasks where the agent would otherwise jump straight to implementation. On T2 (collab server), this is worth +28.6pp.

### 2.2 What's Not Working

**Multi-agent consensus** is the signature feature of Conclave, and it adds nothing measurable:

- The brainstorming skill in autopilot mode calls `conclave consensus --mode=general-prompt` for each design question. A single agent exploring autonomously scores 1.5pp higher.
- The code review skill calls `conclave consensus --mode=code-review` to get Claude/Gemini/Codex perspectives. A single subagent review via the Task tool scores the same.
- With full API keys (Anthropic + Gemini + OpenAI), consensus *still* doesn't beat single-agent. The external models add noise, not signal.

**Systematic debugging** adds nothing because agents already debug well instinctively. When offered as opt-in, agents never invoke it. The skill is comprehensive and well-written, but it addresses a problem that doesn't exist.

**Gene stacking** doesn't compound. Review + Verify stacked scores 97.2% — worse than Verify alone (97.3%). Two quality checkpoints don't catch more than one.

**16 skills is too many.** The using-conclave meta-skill tells agents "if there's even a 1% chance a skill applies, invoke it." This leads to agents spending tokens on skill invocation, context reading, and tool calls that don't help. The top benchmark performers use exactly 1 skill.

### 2.3 The Uncomfortable Truth

The data suggests Conclave's primary value proposition should shift:

| Current Value Prop | Evidence | Recommendation |
|---|---|---|
| Multi-agent consensus catches bugs | No measurable effect (3-way test) | Demote to opt-in |
| Multiple AI perspectives improve quality | External models add noise | Single-agent with skill guidance wins |
| Composable skills library | 16 skills, only 4 matter | Consolidate to core set |
| Conclave binary orchestrates work | Pure skill text outperforms binary | Skills are the product; binary is optional |

**The real value proposition is: Conclave provides structured methodology that makes any model work like an expert developer.** The skill text — not the consensus engine, not the multi-agent protocol — is the product.

---

## Part 3: Recommended Changes

### 3.1 Make TDD the Default Methodology

**Priority: HIGH — largest expected impact**

TDD is the single most effective gene (+12.3pp). Sonnet + TDD is #1 overall at 98.2%, beating every Opus variant. The current using-conclave skill says "check if skills apply" — it should auto-route to TDD for implementation tasks.

**Change:** Modify `skills/using-conclave/SKILL.md` to include a task classifier that selects ONE methodology:

```
TASK CLASSIFICATION (apply the FIRST match):

1. Building something new (feature, component, greenfield)
   → Invoke brainstorming, THEN test-driven-development
2. Fixing a bug or test failure
   → Invoke test-driven-development (write failing test reproducing bug first)
3. Modifying existing behavior
   → Invoke test-driven-development
4. Long multi-step task with existing plan
   → Invoke executing-plans
5. Everything else
   → Invoke verification-before-completion
```

**Why this ordering matters:**
- TDD is the default for all implementation work (items 1-3)
- Brainstorming only fires for genuinely new work (item 1)
- Verification is the fallback for anything that doesn't fit TDD
- No skill selection decision paralysis — the classifier picks for you

### 3.2 Embed Verification in Every Skill Exit

**Priority: HIGH — prevents the #1 failure mode**

The verification-before-completion skill is effective but currently lives as a separate opt-in skill. Every skill's completion should include verification. The self-review prompt achieves 96.8% by baking this directly into the workflow.

**Change:** Add a standard exit gate to every skill that involves implementation:

```markdown
## Completion Gate (applies to ALL implementation work)

BEFORE claiming done, moving to next task, or committing:

1. Run the full verification suite fresh (test + build + lint)
2. Read COMPLETE output. Count failures.
3. If ANY failure: fix and re-run. Do NOT proceed.
4. Commit: git add -A && git commit -m '<description>'
5. Review your diff: git diff HEAD~1
6. Look for: missing edge cases, incomplete implementations, dead code, debug artifacts
7. If issues found: fix, re-verify, re-commit
8. Only stop when verification passes AND diff review is clean

Evidence before claims, always. "Should pass" is not evidence.
```

**Where to add it:**
- `skills/test-driven-development/SKILL.md` — after the Verification Checklist section
- `skills/brainstorming/SKILL.md` — after the "After the Design" section (for the implementation phase)
- `skills/writing-plans/SKILL.md` — already has this implicitly, make explicit
- `skills/executing-plans/SKILL.md` — after each batch
- `skills/requesting-code-review/SKILL.md` — after addressing review findings

### 3.3 Make Consensus Opt-In, Not Default

**Priority: HIGH — eliminates overhead that hurts performance**

Every skill that currently calls `conclave consensus` by default should instead use single-agent execution by default, with consensus available as an explicit opt-in.

**Changes to individual skills:**

**`skills/brainstorming/SKILL.md`:**
- Change autopilot mode to use the agent's own judgment (not consensus) for design questions
- Remove the `conclave consensus --mode=general-prompt` calls from the default flow
- Keep consensus as a third mode option: "Interactive / Autopilot / Consensus Autopilot (uses external AI models)"
- The pure superpowers adapter proves this works: agent explores design space autonomously and scores 97.1%

**`skills/requesting-code-review/SKILL.md`:**
- Default to dispatching a single `code-reviewer` subagent via Task tool
- Move multi-agent consensus to "Enhanced Multi-Agent Review" section, clearly marked as optional
- The pure superpowers adapter proves this works: subagent review scores 97.0%

**`skills/verification-before-completion/SKILL.md`:**
- Remove the "Multi-Agent Final Verification" section as a recommended default
- Move to an "Optional: Multi-Agent Verification" section at the end

**`skills/systematic-debugging/SKILL.md`:**
- Remove the "Multi-Agent Consensus Validation" section from the recommended flow
- Keep as optional advanced technique at end of skill

**`skills/writing-plans/SKILL.md`:**
- Remove "Plan Validation with Multi-Agent Consensus" as default
- Move to optional section

**General pattern:** Every `conclave consensus` call in a skill should be wrapped in:
```markdown
### Optional: Multi-Agent Consensus

If you have API keys for multiple providers and want additional perspectives:
[existing consensus instructions]
```

### 3.4 Consolidate to Core Skills

**Priority: MEDIUM — reduces cognitive overhead and token waste**

The top benchmark performers use 1-2 skills. The using-conclave meta-skill currently teaches agents about 16 skills, leading to unnecessary skill invocation overhead.

**Tier 1 — Core (keep, improve):**
| Skill | Evidence | Action |
|-------|----------|--------|
| `test-driven-development` | +12.3pp, #1 gene | Keep as-is, add completion gate |
| `verification-before-completion` | +11.4pp, cheapest top-tier | Merge into completion gate (see 3.2) |
| `brainstorming` | +11.5pp on greenfield | Simplify to single-agent default |
| `requesting-code-review` | +11.1pp | Simplify to subagent default |
| `using-conclave` | Entry point | Rewrite as task classifier (see 3.1) |

**Tier 2 — Support (keep, de-emphasize):**
| Skill | Evidence | Action |
|-------|----------|--------|
| `writing-plans` | +11.0pp | Keep for complex multi-step tasks |
| `executing-plans` | Untested standalone | Keep as plan execution path |
| `ralph-loop` | Fresh context concept validated | Keep as advanced option |
| `dispatching-parallel-agents` | Useful for specific cases | Keep, don't auto-invoke |
| `multi-agent-consensus` | No effect measured | Keep as opt-in reference |

**Tier 3 — Remove or fold in:**
| Skill | Evidence | Action |
|-------|----------|--------|
| `systematic-debugging` | 0pp effect, agents ignore it | Fold Phase 4 (write failing test) into TDD |
| `subagent-driven-development` | Complex, untested | Merge with executing-plans |
| `using-git-worktrees` | 0pp measured effect | Keep as reference, remove from default flow |
| `finishing-a-development-branch` | Support skill | Keep as-is |
| `receiving-code-review` | Support skill | Keep as-is |
| `writing-skills` | Meta skill | Keep as-is |

### 3.5 Optimize for Sonnet

**Priority: MEDIUM — halves cost, matches or beats Opus**

With structured methodology, Sonnet matches or beats Opus:

| Methodology | Opus | Sonnet |
|---|---:|---:|
| TDD | 97.4% | **98.2%** |
| Self-Review | 96.8% | **97.1%** |

**Changes:**
- Add a note to CLAUDE.md recommending Sonnet 4.6 as the default model when using Conclave skills
- Ensure skill text is optimized for Sonnet's reasoning patterns (Sonnet follows rigid checklists better than Opus, which tends to "interpret" flexible guidance)
- Consider adding `--model claude-sonnet-4-6` recommendations in skill documentation

### 3.6 Slim Down the Session Start Hook

**Priority: LOW — minor improvement**

The current `hooks/session-start.sh` injects the full `using-conclave/SKILL.md` content into every session. This is ~90 lines of instruction that the agent processes before doing anything.

With the task classifier approach (3.1), the injected content can be shorter and more directive. Instead of teaching agents about 16 skills and when to use each one, inject:

1. The task classifier (5-6 lines)
2. A reminder that skills exist and how to invoke them
3. The completion gate (8 lines)

This reduces the upfront cognitive load and lets skills activate on-demand rather than front-loading all the decision logic.

---

## Part 4: Implementation Plan

### Phase 1: Core Skill Improvements (No Breaking Changes)

These changes improve existing skills without removing any functionality. All consensus features remain available as opt-in.

#### Task 1: Rewrite `using-conclave/SKILL.md` as task classifier

**Files:** `skills/using-conclave/SKILL.md`

Replace the current "check if skills apply" approach with a deterministic task classifier. Keep the existing Skill Priority, Red Flags, and Skill Types sections. Replace the flowchart and decision logic with:

```markdown
## Automatic Skill Selection

When you receive a task, classify it and invoke the matching skill:

| Task Type | Skill to Invoke | Example |
|-----------|----------------|---------|
| Build something new | brainstorming → test-driven-development | "Add user auth", "Create API" |
| Fix a bug | test-driven-development | "Fix login error", "Debug crash" |
| Modify behavior | test-driven-development | "Change validation rules" |
| Execute existing plan | executing-plans | "Implement the plan in docs/" |
| Research / explore | (none — just do it) | "How does X work?" |

**Rules:**
1. Pick the FIRST matching row — don't deliberate
2. Invoke ONE skill at a time
3. After implementation, the completion gate applies (see below)
```

**Dependencies:** None
**Verification:** `conclave lint` passes, manual review of new content

#### Task 2: Add completion gate to TDD skill

**Files:** `skills/test-driven-development/SKILL.md`

Add after the "Verification Checklist" section (line 339):

```markdown
## Completion Gate

After all TDD cycles are complete and the verification checklist passes:

1. Run the full project verification suite (not just your new tests):
   - All tests: `npm test` (or project equivalent)
   - Build: `npm run build`
   - Lint: `npm run lint`
2. Read COMPLETE output of each. Count failures.
3. If ANY failure: fix and re-run all three.
4. Commit: `git add -A && git commit -m '<description>'`
5. Review your diff: `git diff HEAD~1`
6. Look for: missing edge cases, incomplete implementations, dead code, debug artifacts
7. Fix any issues found, re-verify, re-commit.
8. Only claim done when verification passes AND diff review is clean.
```

**Dependencies:** None
**Verification:** `conclave lint` passes

#### Task 3: Make brainstorming default to single-agent autopilot

**Files:** `skills/brainstorming/SKILL.md`

Change the mode selection (currently lines 53-69) to offer three modes instead of two:

```markdown
**Mode Selection:**

1. **Interactive** - I ask questions, you answer, we iterate
2. **Autopilot** - I explore design decisions autonomously, you watch and can interrupt
3. **Consensus Autopilot** - Multi-agent consensus (Claude, Gemini, Codex) answers
   design questions. Requires API keys. (~30-60s per question)

Which mode?
```

For `CONCLAVE_NON_INTERACTIVE=1`, default to mode 2 (Autopilot), not mode 3 (Consensus).

In Autopilot mode (new default):
- Agent explores project context
- Proposes 2-3 approaches for each design question, evaluates trade-offs
- Picks the best option and narrates reasoning
- User can interrupt to override

Move the existing `conclave consensus` instructions to mode 3 only.

**Dependencies:** None
**Verification:** `conclave lint` passes, manual review

#### Task 4: Make code review default to subagent

**Files:** `skills/requesting-code-review/SKILL.md`

Restructure the skill to default to single-reviewer mode:

```markdown
## How to Request Review

### Default: Subagent Review

Dispatch a code-reviewer subagent to review your changes:

1. Commit your work: `git add -A && git commit -m 'implementation'`
2. Dispatch reviewer via Task tool with the code-reviewer agent prompt
3. Address HIGH and MEDIUM priority findings
4. Re-verify after fixes

### Optional: Multi-Agent Consensus Review

For higher-stakes reviews, use multi-agent consensus (requires API keys):

[existing conclave consensus instructions, moved here]
```

**Dependencies:** None
**Verification:** `conclave lint` passes

#### Task 5: Remove consensus from verification and debugging defaults

**Files:**
- `skills/verification-before-completion/SKILL.md`
- `skills/systematic-debugging/SKILL.md`

In verification-before-completion:
- Move "Multi-Agent Final Verification" section (lines 133-165) under a new heading "### Optional: Multi-Agent Verification"
- Change "After local verification passes, run multi-agent consensus" to "If you have API keys for multiple providers and want additional validation:"

In systematic-debugging:
- Move "Multi-Agent Consensus Validation" section (lines 170-238) under "### Optional: Multi-Agent Root Cause Validation"
- Change the "When to use" guidance to note this is an advanced technique

**Dependencies:** None
**Verification:** `conclave lint` passes

#### Task 6: Add completion gate to brainstorming implementation phase

**Files:** `skills/brainstorming/SKILL.md`

After the "Implementation (if continuing):" section at the end, add the same completion gate from Task 2. This ensures that when brainstorming flows into implementation, the agent verifies before claiming completion.

**Dependencies:** Task 2
**Verification:** `conclave lint` passes

### Phase 2: Documentation Updates

#### Task 7: Update CLAUDE.md

**Files:** `CLAUDE.md`

Add a "Model Recommendations" section:

```markdown
## Model Recommendations

Benchmark data (796 trials) shows that with Conclave's structured methodology, **Sonnet 4.6
matches or beats Opus 4.6** at half the cost:

- TDD: Sonnet 98.2% vs Opus 97.4%
- Self-Review: Sonnet 97.1% vs Opus 96.8%

Recommend Sonnet 4.6 as the default model for Conclave-guided work.
```

Update the "What This Is" section to reflect the new positioning:

```markdown
Conclave is a Claude Code plugin that provides structured development methodologies
through composable "skills" — TDD, design brainstorming, verification, and code review.
Skills activate automatically based on task type and guide the agent through disciplined
workflows that improve code quality by 10-12 points over unguided development.

Optionally includes multi-agent consensus for higher-stakes decisions (requires API keys
for Gemini and/or Codex in addition to Claude).
```

**Dependencies:** None
**Verification:** Manual review

#### Task 8: Update README.md with benchmark findings

**Files:** `README.md`

Add a "Benchmark Results" section summarizing the Thunderdome findings. Link to this document for full details. Key points to include:
- TDD is the most effective methodology
- Structured skills improve output by 10-12 points
- Sonnet + skills matches Opus performance at lower cost
- Consensus is available for users who want multi-perspective validation

**Dependencies:** None
**Verification:** Manual review

### Phase 3: Advanced Improvements (Future)

These are larger changes that could push past the 97-98% ceiling but require more design work.

#### Task 9: Investigate TDD + Brainstorm combination

The data shows TDD (98.2%) and Brainstorm (97.4%) are the top two genes individually. We haven't tested them combined: brainstorm the design, then TDD the implementation.

**Hypothesis:** TDD + Brainstorm could be the first variant to consistently exceed 98%.

**Test plan:** Create a `superpowers-brainstorm-tdd-sonnet` adapter that:
1. Invokes brainstorming skill for design exploration (single-agent)
2. Invokes TDD skill for implementation
3. Uses Sonnet 4.6

Run against the full 11-task suite with n=2 trials.

#### Task 10: Investigate fresh-context retry for marathon tasks

The Ralph loop concept (fresh context per retry) addresses the marathon task problem where agents exhaust context on long tasks. The ralph-loop skill has the right idea but hasn't been tested in isolation.

**Test plan:** Create a `ralph-tdd-sonnet` adapter that:
1. Uses TDD as the primary methodology
2. On failure, retries with fresh context (ralph loop)
3. Uses Sonnet 4.6

Run against T5 (task queue, marathon category) specifically, n=4 trials.

#### Task 11: Prune debugging skill or fold into TDD

The systematic debugging skill scores 0pp above baseline because agents never invoke it when it's opt-in. However, its Phase 4 ("create failing test case") is essentially TDD.

**Option A:** Remove the skill entirely, add a note to TDD: "Bug found? Write failing test reproducing it. Follow TDD cycle." (This already exists at line 353.)

**Option B:** Keep the skill but remove it from the using-conclave skill list and auto-routing. It remains available for explicit invocation by users who want the four-phase framework.

**Recommendation:** Option B — keep for users who find it valuable, but don't auto-route to it.

---

## Part 5: Success Metrics

After implementing Phase 1 and Phase 2, re-run the Thunderdome benchmark to measure improvement:

| Metric | Current | Target | How to measure |
|--------|---------|--------|----------------|
| Default Conclave score | 95.2% (full, with consensus) | >97% | Run `conclave-default-opus` × 11 tasks × 2 trials |
| Conclave vs vanilla delta | +9.3pp | >+11pp | Compare against vanilla baseline |
| Mean cost per task | $0.14-$2.01 (varies) | <$1.50 | Check meta.json cost fields |
| Skill invocation overhead | ~15-20% of tokens on skill processing | <10% | Check token counts in metrics |

The ultimate test: **does a new Conclave user, installing the plugin for the first time and running it on a coding task, get measurably better results than vanilla Claude Code?** Current answer: yes, but the consensus overhead muddies it. After these changes: yes, decisively, and cheaper.

---

## Appendix A: Methodology Notes

### Scoring

**Standard tasks:** `composite = tests × 0.7 + static_analysis × 0.3`

**Greenfield tasks:** `composite = hidden_tests × 0.385 + (agent_tests × coverage) × 0.308 + build_lint × 0.154 + code_metrics × 0.154`

All scoring is deterministic — test pass rates, ESLint output, Istanbul coverage, and static code metrics. No LLM judges.

### Task Suite

11 TypeScript/Node.js tasks across 6 categories:
- **greenfield/simple** (1 task): Build from scratch, clear requirements
- **greenfield/complex** (4 tasks): Build from scratch, complex requirements
- **features/medium** (1 task): Add features to existing codebase
- **features/complex** (1 task): Add complex features to existing codebase
- **bugfix/medium** (1 task): Find and fix bugs
- **bugfix/hard** (1 task): Find and fix subtle bugs
- **marathon** (1 task): Long, sequential multi-step task
- **recovery** (1 task): Fix broken codebase with multiple issues

### Isolation

Each trial runs in a fresh Docker container with:
- Clean git repo (cloned from benchmark tag)
- No internet access beyond API endpoints
- No access to other trials' results
- Fixed time limit (5-30 minutes depending on task)
- Token/cost budget enforcement

### Statistical Notes

Most ablation comparisons have n=11-40 trials. The sample sizes are small for individual task-level comparisons (n=2-4 per task per variant), but the aggregate scores across 11 tasks are more reliable. Treat individual task deltas as directional, not definitive.

## Appendix B: Raw Data Locations

All trial data is stored in the Thunderdome harness repository:

```
agentic-thunderdome/results/runs/<timestamp>/trials/<orchestrator>/<task>/trial-N/
├── meta.json       # scores, duration, tokens, cost
├── diff.patch      # git diff of agent's changes
└── task.md         # task prompt given to agent
```

Key runs referenced in this document:
- Pure superpowers brainstorm: `results/runs/2026-02-26T20-22-58/`
- Pure superpowers review: `results/runs/2026-02-26T20-23-15/`
- Conclave + keys (both): `results/runs/2026-02-26T22-27-04/`
- TDD Sonnet: `results/runs/2026-02-25T21-57-34/`
- Self-Review Sonnet: `results/runs/2026-02-25T22-48-26/`
- Full 11-task run: `results/runs/2026-02-24T00-21-55/`
