# Agentic Thunderdome

Two agents enter, one agent leaves.

A benchmarking framework that pits agentic coding orchestrators against standardized programming tasks and measures what matters: completion rate, token efficiency, cost, and code quality.

## Results

Full suite results across all 10 tasks (single trial each, all Opus unless noted). Each cell shows **score | wall-clock time | cost**:

| Task | Claude Code | Conclave | Superpowers | Gas Town | Gas Station | Amplifier | Aider* |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| **T1** time-tracker | 92.7% 2m05s $0.45 | 79.1% 5m19s $1.48 | 94.0% 1m23s $0.42 | 92.9% 2m38s $0.47 | 93.2% 2m09s $0.35 | 96.2% 1m58s $0.28 | 93.6% 26s $0.02 |
| **T2** collab-server | 86.9% 12m16s $2.90 | 82.2% 13m56s $1.69 | 84.2% 2m21s $0.72 | 87.9% 27m54s $10.20 | 87.2% 8m22s $1.58 | 96.2% 20m14s ~$1.81 | 92.9% 59s $0.03 |
| **T3** fts-search | 90.6% 1m30s $0.52 | 92.5% 3m33s $1.01 | 93.2% 2m48s $0.82 | 93.2% 2m05s $0.59 | 93.2% 1m54s $0.41 | 93.2% 4m39s $0.57 | 93.2% 1m54s $0.09 |
| **T4** phantom-invoice | 92.5% 1m31s $0.35 | 100.0% 2m09s $0.50 | 100.0% 1m33s $0.38 | 98.5% 1m38s $0.35 | 100.0% 1m48s $0.27 | 100.0% 2m40s $0.30 | 100.0% 36s $0.07 |
| **T5** task-queue | 57.8% 5m23s $1.13 | 73.8% 19m44s $2.93 | 73.0% 3m39s $1.16 | 88.4% 16m59s $8.27 | 86.8% 12m17s $3.25 | 94.0% 23m19s $1.07 | 20.0% 8s $0.01 |
| **T6** monorepo-disaster | 98.5% 2m29s $0.52 | 73.0% 3m46s $1.00 | 94.0% 3m09s $0.69 | 97.0% 7m21s $0.63 | 96.2% 3m58s $0.77 | 95.5% 3m18s ~$0.30 | — |
| **T7** plugin-marketplace | 91.4% 4m18s $0.94 | 70.0% 8m58s $3.71 | 70.7% 2m24s $0.59 | 94.8% 8m33s $4.27 | 92.6% 4m19s $0.89 | 95.2% 4m56s ~$0.44 | — |
| **T8** analytics-dashboard | 82.8% 4m47s $1.21 | 59.5% 8m25s $2.47 | 70.0% 4m06s $1.27 | 85.3% 10m49s $5.31 | 85.3% 6m45s $2.01 | 69.1% 10m38s $0.67 | — |
| **T9** ssg-toolkit | 83.5% 2m55s $0.71 | 84.2% 5m46s $1.64 | 70.7% 2m52s $0.77 | 96.2% 2m59s $0.90 | 94.0% 3m38s $0.75 | 96.2% 9m19s $0.78 | — |
| **T10** ecommerce-backend | 90.1% 4m51s $1.05 | 82.2% 9m53s $2.77 | 70.7% 2m34s $0.77 | 93.7% 7m06s $0.63 | 93.9% 4m05s $0.81 | 94.5% 7m56s $0.54 | — |
| **Avg / Total** | **86.7%** 42m05s **$9.79** | **79.7%** 1h21m **$19.21** | **82.1%** 26m49s **$7.60** | **92.8%** 1h28m **$31.62** | **92.3%** 49m15s **$11.09** | **93.0%** 1h28m **~$6.73** | **79.9%** 4m03s **~$0.22** |

\*Aider uses Sonnet (one-shot, no iteration). `~` = extrapolated cost. Gas Town uses a multi-agent pipeline (Mayor planner -> parallel Polecats -> Refinery merge); Gas Station is its single-agent variant.

### Key Findings

- **Amplifier** leads on score (93.0%) and cost efficiency (~$6.73) but takes the longest (1h28m tied with Gas Town)
- **Gas Town** is #2 on score (92.8%) but most expensive ($31.62) due to multi-agent overhead
- **Gas Station** (single-agent) nearly matches Gas Town quality (92.3%) in half the time (49m) at 3x less cost ($11.09)
- **Superpowers** is fastest among full-suite runners (27m) and cheapest Opus ($7.60) but drops on complex tasks
- **Claude Code** struggles on marathon tasks (T5: 57.8%) but excels at recovery (T6: 98.5%) with middle-of-pack speed (42m)
- **Aider** is absurdly fast (4m) and cheap ($0.22) but collapses without iteration (T5: 20%) and only covers 5 tasks

## Why This Exists

Every AI coding tool claims superiority. None publish reproducible head-to-head comparisons. Thunderdome fills that gap by running orchestrators against identical tasks in isolated Docker containers, scoring their output with automated tests, static analysis, and LLM-judged rubrics.

The framework tests five hypotheses:

- **H1:** Cross-provider consensus (Codex Max x Opus x Gemini 3 Pro) catches more defects than same-model consensus
- **H2:** Multi-agent consensus reduces mid-implementation design reversals
- **H3:** Fresh-context Ralph loops outperform stale-context loops on marathon tasks
- **H4:** Consensus overhead pays for itself in reduced rework
- **H5:** Dependency-aware parallel execution achieves sub-linear wall-clock time on decomposable tasks; naive parallelization produces merge conflicts that eliminate the advantage

## Contenders

| Orchestrator | Architecture | Key Differentiator |
|---|---|---|
| **Claude Code** | CLI agentic (single agent) | Rich tool use, subagent delegation, flexible autonomy |
| **Conclave** (Superpowers fork) | Cross-provider consensus | Claude x Gemini x Codex consensus; 6-layer self-correction |
| **Superpowers** (Original) | Skill-injection platform | Mandatory planning + TDD + two-stage review |
| **Gas Town** | Multi-agent pipeline | Mayor (planner) -> parallel Polecats (workers) -> Refinery (merge) |
| **Gas Station** | Single-agent + context injection | Gas Town's prompt engineering without multi-agent overhead |
| **Amplifier** | Micro-kernel platform | Swappable providers; minimal overhead |
| **Aider** | CLI turn-based | One-shot Sonnet; PageRank repo map; token-efficient |
| **SWE-agent** | Academic/research | Syntax guardrails, ACI design |

See [`docs/survey/orchestrator-survey.md`](docs/survey/orchestrator-survey.md) for the full gene matrix and per-tool analysis.

## Benchmark Suite

Ten tasks span five categories and the full parallelism spectrum:

| # | Task | Category | Parallelism | Timeout | Tests |
|---|------|----------|-------------|---------|-------|
| 1 | CLI Time Tracker | greenfield/simple | None | 15m | 25 |
| 2 | Collab Server | greenfield/complex | Mixed | 45m | 45 |
| 3 | FTS Search | features/medium | Sequential | 30m | 35 |
| 4 | Phantom Invoice Bug | bugfix/medium | Sequential | 20m | 41 |
| 5 | Task Queue Marathon | marathon | Sequential | 60m | 90 |
| 6 | Monorepo Disaster | recovery | Mixed | 30m | 49 |
| 7 | Plugin Marketplace | greenfield/complex | Pure parallel | 45m | 55 |
| 8 | Analytics Dashboard | greenfield/complex | Deceptive parallel | 45m | 50 |
| 9 | SSG Toolkit | features/complex | DAG parallel | 45m | 75 |
| 10 | E-Commerce Backend | greenfield/complex | Pure parallel (max) | 45m | 70 |

```
None        Sequential     Mixed          Deceptive      DAG-Parallel     Pure Parallel
|              |              |               |               |                |
T1           T3,T5         T2,T6           T8              T9             T7,T10
```

All 535 tests across 10 repos use TypeScript/Node.js with Vitest. Orchestrators cannot cheat by modifying tests. Validation runs `npm run build && npm run lint && npm test`.

Each task includes at least one trap that punishes naive or template-driven approaches. See [`docs/plans/2026-02-11-survey-and-tasks-design.md`](docs/plans/2026-02-11-survey-and-tasks-design.md) for full task specifications.

## How It Works

```
thunderdome run
  |
  ├─ Clone task repo at pinned tag
  ├─ Launch orchestrator in Docker container
  │    ├─ Mount adapter script, task description, workspace
  │    ├─ Orchestrator reads TASK.md, writes code to /workspace
  │    └─ Container exits on completion, timeout, or crash
  ├─ Capture git diff of workspace changes
  ├─ Run validation pipeline
  │    ├─ Tests (npm test in validation image)
  │    ├─ Build + lint (npm run build && npm run lint)
  │    ├─ LLM rubric judge (scored against task-specific criteria)
  │    └─ Greenfield extras: hidden tests, coverage, code metrics
  └─ Write results (meta.json, diff.patch, scores)
```

Each orchestrator plugs in through a shell adapter script mounted at `/adapter.sh`. The adapter translates between Thunderdome's interface (environment variables `TASK_DIR`, `TASK_DESCRIPTION`, `PROXY_URL`) and the orchestrator's native invocation. Adapters also parse their orchestrator's output to write `.thunderdome-metrics.json` with token usage and cost data.

## Usage

### Prerequisites

- Go 1.24+
- Docker

### Build

```sh
go build -o thunderdome .
```

### Run

```sh
# Run all orchestrators against all tasks
./thunderdome run

# Filter to one orchestrator or task
./thunderdome run --orchestrator conclave-oauth-opus
./thunderdome run --task T5

# Run with parallel containers
./thunderdome run --parallel 4 --trials 3

# Validate a previous run's workspace
./thunderdome validate ./results/runs/<run-id>/trials/<orch>/<task>/trial-1
```

### Results

Each trial produces:

```
results/runs/<run-id>/trials/<orchestrator>/<task>/trial-1/
├── meta.json      # Duration, exit reason, scores, token usage, cost
├── diff.patch     # Git diff of all workspace changes
├── task.md        # Task prompt given to the orchestrator
└── workspace/     # Full workspace after orchestrator ran
    └── .thunderdome-metrics.json  # Token/cost metrics from adapter
```

The composite score blends test pass rate, static analysis, and rubric scores. Greenfield tasks additionally include hidden tests, code coverage, and code metrics.

## Writing an Adapter

An adapter script bridges Thunderdome and an orchestrator. It receives these environment variables:

| Variable | Value |
|---|---|
| `TASK_DIR` | `/workspace` -- the task repo, mounted read-write |
| `TASK_DESCRIPTION` | `/task.md` -- the task prompt |
| `PROXY_URL` | API gateway URL (if gateway is enabled) |

The script must:

1. Read the task description
2. Invoke the orchestrator, pointing it at the workspace
3. Write `/workspace/.thunderdome-metrics.json` with token/cost data
4. Exit 0 on success, non-zero on error

Example (Aider adapter with cost tracking):

```sh
#!/bin/bash
set -e
cd "$TASK_DIR"

aider --yes-always --no-auto-commits \
  --message-file "$TASK_DESCRIPTION" \
  --model anthropic/claude-sonnet-4-5 \
  | tee /workspace/.aider-stdout.log

# Parse cost from stdout and write metrics
python3 -c "
import re, json
last_cost = 0.0
with open('/workspace/.aider-stdout.log') as f:
    for line in f:
        m = re.search(r'Cost:.*\\\$([\\d.]+) session', line)
        if m: last_cost = float(m.group(1))
json.dump({'total_cost_usd': last_cost},
          open('/workspace/.thunderdome-metrics.json','w'))
"
```

## Scoring

| Axis | Method | Weight |
|---|---|---|
| **Tests** | Fraction of pre-written tests that pass | Task-specific |
| **Static analysis** | Build + lint pass/fail (binary) | Task-specific |
| **Rubric** | LLM judge scores the diff against task-specific criteria | Task-specific |
| **Hidden tests** | Tests on `v1-validation` tag, not visible to orchestrator | Greenfield only |
| **Coverage** | Statement coverage of agent-written tests | Greenfield only |
| **Code metrics** | Lines of code, complexity, duplication | Greenfield only |

The composite score is a weighted sum. Each task defines its own weights, so bugfix tasks weight tests higher; greenfield tasks include the full six-axis scoring.

## Project Structure

```
.
├── main.go                     # Entry point
├── cmd/                        # CLI commands (run, list, report, validate)
├── internal/
│   ├── config/                 # YAML config parsing and validation
│   ├── docker/                 # Container lifecycle management
│   ├── gateway/                # API proxy (proxy.py), usage tracking
│   ├── gitops/                 # Clone, checkout, diff capture
│   ├── report/                 # Table, Markdown, JSON report generation
│   ├── result/                 # Trial metadata types and storage
│   ├── runner/                 # Trial execution, validation pipeline, pool
│   └── validation/             # Tests, lint, rubric, hidden tests, coverage, code metrics
├── adapters/                   # Shell adapter scripts per orchestrator
├── benchmarks/                 # 10 standalone task repos (each with v1/v1-solution tags)
├── docker/                     # Dockerfiles for orchestrator images
├── docs/
│   ├── survey/                 # Orchestrator architecture survey
│   └── plans/                  # Design documents
├── thunderdome.yaml            # Default configuration
└── project.md                  # Full project specification
```

## Status

- [x] Orchestrator survey (10 tools documented)
- [x] Benchmark task design (10 tasks specified)
- [x] Build benchmark task repos (10 repos, 535 tests, v1/v1-solution tags)
- [x] Harness implementation (run, list, report, validate commands)
- [x] Write orchestrator adapters (8 orchestrators, 16 adapter variants)
- [x] Run baseline comparisons (single-trial full suite for 7 orchestrators)
- [ ] Multi-trial runs for statistical significance
- [ ] Ablation studies (gene isolation)
- [ ] Publish methodology paper

## License

TBD
