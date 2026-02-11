# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Agentic Thunderdome is a benchmarking framework for comparing agentic coding orchestrators (AI coding tools) head-to-head using standardized tasks. The full specification lives in `project.md`.

**Current state:** Benchmark repos built. 10 task repos with 535 tests total, each with v1 (starting state) and v1-solution (reference) tags. Next step: build the test harness.

## Contenders Being Benchmarked

- **Conclave** (Superpowers fork) — Multi-agent consensus with cross-provider models (Codex Max × Opus × Gemini 3 Pro)
- **Superpowers (Original)**, **Amplifier**, **Gas Town**, others TBD

## Benchmark Repos

```
benchmarks/
├── bench-time-tracker/         # T1: greenfield/simple (25 tests)
├── bench-collab-server/        # T2: greenfield/complex (45 tests)
├── bench-fts-search/           # T3: features/medium (35 tests)
├── bench-phantom-invoice/      # T4: bugfix/medium (41 tests)
├── bench-task-queue/           # T5: marathon (90 tests, 12 phases)
├── bench-monorepo-disaster/    # T6: recovery (49 tests, 6 breakages)
├── bench-plugin-marketplace/   # T7: greenfield/complex (55 tests)
├── bench-analytics-dashboard/  # T8: greenfield/complex (50 tests, parallel trap)
├── bench-ssg-toolkit/          # T9: features/complex (75 tests, DAG plugins)
└── bench-ecommerce-backend/    # T10: greenfield/complex (70 tests, event-driven)
```

Each repo is its own git repository with `v1` (starting state) and `v1-solution` (reference solution) tags. All use TypeScript/Node.js with Vitest. The harness clones at `v1`, lets the orchestrator work, then validates with `npm test && npm run build && npm run lint`.

## Key Concepts

- **Orchestrator "Genes"** — Composable features (multi-agent-consensus, ralph-loop, fresh-context, plan-before-code, etc.) that can be added/removed for ablation studies
- **Benchmark Dimensions** — Completion rate, token efficiency, turn count, error recovery, code quality, context endurance
- **Measurement approach** — Docker containers per run, git snapshots for reproducibility, automated test harness, cost tracking via API logs

## Research Hypotheses

- H1: Cross-provider consensus outperforms same-model consensus on defect catch rate
- H2: Multi-agent consensus reduces design reversals vs solo agents
- H3: Fresh context Ralph loops outperform stale-context loops on marathon tasks
- H4: Consensus overhead pays for itself in reduced rework
- H5: Dependency-aware parallel execution achieves sub-linear wall-clock time on decomposable tasks; naive parallelization produces merge conflicts that eliminate the advantage

## Next Steps (from project.md)

1. ~~Survey 5-10 orchestrator patterns~~ (done — docs/survey/)
2. ~~Define 10 initial benchmark tasks~~ (done — design doc + all 10 repos built)
3. Create harness for running orchestrators against tasks
4. Instrument Conclave for metrics collection
5. Run baseline comparisons
6. Publish results/methodology
