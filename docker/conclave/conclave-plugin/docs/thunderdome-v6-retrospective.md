# How Gene Ablation Studies Shaped Conclave v6

> 796 isolated Docker trials. 34 orchestrator variants. 11 standardized tasks. Zero LLM judges. The results fundamentally changed what Conclave is.

## The Experiment

We wanted to answer a simple question: **which parts of Conclave actually matter?**

Conclave had grown to 16 skills, a multi-agent consensus engine calling Claude/Gemini/Codex in parallel, a two-stage synthesis protocol, and an orchestration binary. The assumption was that more perspective — more models, more review passes, more skills — meant better code. We had never tested that assumption.

So we built [Thunderdome](https://github.com/signalnine/agentic-thunderdome): a benchmark harness that runs coding tasks in isolated Docker containers with deterministic scoring. No LLM judges — just test pass rates, build/lint output, coverage metrics, and static analysis. Each trial gets a clean git repo, no internet beyond API endpoints, and a fixed time budget.

We treated each Conclave feature as a **gene** and ran ablation studies — testing each gene in isolation, in combinations, and against a vanilla Claude Code baseline. The approach was borrowed from genetics: if you want to know what a gene does, knock it out and see what breaks.

## The Baseline

Vanilla Claude Code — no plugins, no skills, no special instructions — scores **85.9%** across 11 tasks. That's our control group.

## Gene-by-Gene Results

Every gene was tested in isolation. Same container, same tasks, same scoring — only the system prompt and skill text differ.

| Gene | Score | Delta vs Vanilla | Cost/Task | Trials |
|------|------:|------:|-----:|--:|
| TDD (Sonnet 4.6) | 98.2% | +12.3pp | $1.08 | 22 |
| TDD (Opus 4.6) | 97.4% | +11.5pp | $2.32 | 16 |
| Brainstorm | 97.4% | +11.5pp | $1.43 | 38 |
| Verify | 97.3% | +11.4pp | $0.94 | 11 |
| Code Review | 97.0% | +11.1pp | $2.01 | 34 |
| Plans | 96.9% | +11.0pp | $1.05 | 11 |
| Self-Review (prompt only) | 96.8% | +10.9pp | $1.33 | 40 |
| Debug | 96.4% | +10.5pp | $0.88 | 9 |

Two findings jumped out immediately:

**1. Every discipline gene works.** The gap between any structured methodology and no methodology is massive (+10.5 to +12.3 points). All discipline genes cluster within 1.4 points of each other. Having *a* methodology matters enormously; which methodology matters surprisingly little.

**2. TDD is the single most effective gene.** And Sonnet 4.6 + TDD (98.2%) beats every Opus variant, including Opus + TDD (97.4%). Structure matters more than model capability. The cheaper model, given the right discipline, outperforms the expensive one.

## The Consensus Knockout

This was the critical experiment. Conclave's signature feature was multi-agent consensus — running Claude, Gemini, and Codex in parallel and synthesizing their findings. We tested it three ways:

1. **Skill text only** — no conclave binary, no consensus, just the skill prompt
2. **Conclave, Claude only** — binary present, but only Claude API key
3. **Conclave, all keys** — Claude + Gemini + OpenAI (true multi-provider)

| Configuration | Brainstorm Score | Review Score |
|---|---:|---:|
| Skill text only | **97.1%** | **97.0%** |
| Conclave + all keys | 95.7% | 96.9% |
| Conclave, Claude only | 95.6% | 96.0% |

The consensus engine — the thing that made Conclave different from a collection of markdown files — either hurt performance (brainstorming: -1.5 points) or added nothing (review: -0.1 points). The skill text drove all the value. The binary was overhead.

## Gene Stacking

If one quality gate is good, two must be better, right?

| Configuration | Score |
|---|---:|
| Verify alone | 97.3% |
| Review alone | 97.0% |
| Review + Verify stacked | 97.2% |

No. Stacking quality gates shows diminishing returns. Two checkpoints don't catch more than one. The agent either gets it right with one gate or doesn't.

## The Self-Review Floor

Perhaps the most uncomfortable finding: a 15-line system prompt, with zero infrastructure, scores 96.8%:

```
MANDATORY BEFORE FINISHING:
1. Implement the task using your best judgment.
2. Run the FULL verification suite fresh (npm test, npm run build, npm run lint).
3. Read the COMPLETE output. Count failures.
4. Fix and re-run until clean.
5. Commit, then review your diff (git diff HEAD~1).
6. Fix anything wrong. Re-verify.
7. Only stop when verification passes AND diff review is clean.
```

This is the floor. Any skill-based approach must beat 96.8% to justify its existence. The entire Conclave skill infrastructure fights over the remaining 1.4 points between 96.8% and 98.2%.

## Model vs. Methodology

With structured methodology, the Sonnet-Opus gap effectively disappears:

| Methodology | Opus 4.6 | Sonnet 4.6 |
|---|---:|---:|
| TDD | 97.4% | **98.2%** |
| Self-Review | 96.8% | **97.1%** |
| Vanilla | 85.9% | ~85% |

Without methodology, model capability matters. With methodology, it doesn't. Sonnet + TDD is the Pareto-optimal point: highest score at half the cost.

## What We Changed in v6

The data told a clear story. We executed it in two releases.

### v6.0.0: Architecture Shift

**Rewrote `using-conclave` as a deterministic task classifier.** The old version taught agents about 16 skills and said "check if any apply." The new version is a lookup table — classify your task, invoke one skill, done:

| Task Type | Skill |
|-----------|-------|
| Build something new | brainstorming, then TDD |
| Fix a bug | TDD |
| Modify existing behavior | TDD |
| Execute a plan | executing-plans |
| Research | none needed |

No deliberation. Pick the first match. This routes the overwhelming majority of tasks to TDD, which is where the data says they should go.

**Demoted consensus to opt-in everywhere.** Every skill that previously called `conclave consensus` by default now uses single-agent execution. Consensus still exists for users who want it — it's under "Optional" headings in brainstorming, code review, verification, and debugging. But it never fires unless you explicitly ask.

**Made brainstorming default to single-agent autopilot.** Three modes now: Interactive (human answers design questions), Autopilot (agent explores autonomously — the new default), and Consensus Autopilot (multi-agent, opt-in). The pure single-agent mode scored 1.5 points higher than consensus in benchmarks.

**Changed code review to subagent dispatch.** Instead of running a multi-provider consensus review, the default is now dispatching a single `code-reviewer` subagent. Same score, simpler, cheaper.

**Added the Completion Gate.** Baked the self-review prompt (the one that scores 96.8% by itself) directly into TDD and brainstorming as an exit gate. Every implementation path now ends with: run full suite, read output, commit, review diff, fix issues, verify again.

### v6.1.0: Fresh Context TDD Enforcement

**Wired TDD into every ralph-loop iteration.** The ralph-loop runs tasks with fresh context per retry — each iteration starts a new `claude -p` session. The problem: fresh context means the new session doesn't know about TDD discipline. The fix: a `TDDPreamble` constant that gets prepended to every iteration prompt, ensuring the RED-GREEN-REFACTOR cycle and completion gate are enforced even in agents that have never seen the TDD skill.

**Updated the implementer prompt template.** The subagent-driven-development template previously said "Write tests (following TDD if task says to)." Now it says "Follow TDD: write a failing test FIRST, then minimal code to pass, repeat." No conditional. TDD is the default, always.

## The Design Principle

The Thunderdome findings crystallized a design principle that now guides Conclave development:

**The skill text is the product.**

Not the binary. Not the consensus protocol. Not the multi-model orchestration. The carefully-written prompts that change how an agent approaches a coding task — that's what drives the 10-12 point improvement. Everything else is optional infrastructure.

Conclave v6 is organized around this principle. The core value is a task classifier that routes to the right methodology, and methodology prompts that enforce discipline the model naturally resists. Multi-agent consensus, parallel execution, and external model calls are available for users who want them, but they're opt-in additions, not the default path.

## What's Next

Two hypotheses remain untested:

1. **TDD + Brainstorm combined.** The two top genes individually (98.2% and 97.4%) have never been tested together. The using-conclave classifier routes "build something new" through brainstorming then TDD, but we haven't benchmarked this specific combination.

2. **Fresh-context TDD on marathon tasks.** The ralph-loop with TDD enforcement (v6.1.0) targets the marathon category where agents exhaust context on long tasks. T5 (task queue) went from 62.1% vanilla to 96.6% with fresh context + verification — but we haven't tested it with TDD specifically.

Both require more Thunderdome runs to validate. The benchmark harness is [open source](https://github.com/signalnine/agentic-thunderdome).

## Methodology Notes

All scoring is deterministic: `composite = tests * 0.7 + static_analysis * 0.3` for standard tasks, with a weighted formula including hidden tests, agent tests, coverage, build/lint, and code metrics for greenfield tasks. Each trial runs in an isolated Docker container with no cross-trial contamination. Sample sizes range from n=9 to n=62 per variant. See the [full findings document](plans/2026-02-26-thunderdome-findings-and-roadmap.md) for raw data locations and statistical notes.
