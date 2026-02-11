# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Agentic Thunderdome is a benchmarking framework for comparing agentic coding orchestrators (AI coding tools) head-to-head using standardized tasks. The full specification lives in `project.md`.

**Current state:** Specification only — no code has been implemented yet. The project is in planning phase.

## Contenders Being Benchmarked

- **Conclave** (Superpowers fork) — Multi-agent consensus with cross-provider models (Codex Max × Opus × Gemini 3 Pro)
- **Superpowers (Original)**, **Amplifier**, **Gas Town**, others TBD

## Planned Architecture

```
benchmarks/
├── greenfield/      # Start from scratch (simple/medium/complex)
├── features/        # Add to existing codebases (simple/medium/complex)
├── bugfix/          # Diagnose and repair (simple/medium/complex)
├── marathon/        # Tests context window management
└── recovery/        # Intentionally broken states to escape
```

Each benchmark task includes: starting state (repo snapshot), task description, validation criteria, and optional reference solution.

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

1. Survey 5-10 orchestrator patterns
2. Define 10 initial benchmark tasks (designed, see design doc)
3. Create harness for running orchestrators against tasks
4. Instrument Conclave for metrics collection
5. Run baseline comparisons
6. Publish results/methodology
