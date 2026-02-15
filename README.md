# Agentic Thunderdome

Two agents enter, one agent leaves.

A benchmarking framework that pits agentic coding orchestrators against standardized programming tasks and measures what matters: completion rate, token efficiency, error recovery, code quality, and context endurance.

## Why This Exists

Every AI coding tool claims superiority. None publish reproducible head-to-head comparisons. Thunderdome fills that gap by running orchestrators against identical tasks in isolated Docker containers, scoring their output with automated tests, static analysis, and LLM-judged rubrics.

The framework tests five hypotheses:

- **H1:** Cross-provider consensus (Codex Max x Opus x Gemini 3 Pro) catches more defects than same-model consensus
- **H2:** Multi-agent consensus reduces mid-implementation design reversals
- **H3:** Fresh-context Ralph loops outperform stale-context loops on marathon tasks
- **H4:** Consensus overhead pays for itself in reduced rework
- **H5:** Dependency-aware parallel execution achieves sub-linear wall-clock time on decomposable tasks; naive parallelization produces merge conflicts that eliminate the advantage

## Contenders

Ten orchestrators surveyed, spanning every major architecture:

| Orchestrator | Archetype | Core Strength |
|---|---|---|
| **Conclave** (Superpowers fork) | Cross-provider consensus | Only tool with Claude x Gemini x Codex consensus; 6-layer self-correction |
| **Superpowers** (Original) | Skill-injection platform | Mandatory planning + TDD + two-stage review; strongest quality gates |
| **Claude Code** | CLI agentic | Rich tool use, subagent delegation, flexible autonomy |
| **Claude Squad** | Multi-instance orchestrator | Parallel Claude Code instances in isolated git worktrees via tmux |
| **Gas Town** | Multi-agent workspace | Disposable sessions, parallel Polecats, supervisor hierarchy |
| **Amplifier** | Micro-kernel platform | Swappable everything; ideal for gene ablation studies |
| **OpenHands** | Multi-agent platform | Sandboxed execution, context condensation, inference-time scaling |
| **Aider** | CLI turn-based | PageRank repo map, edit format research, token-efficient |
| **SWE-agent** | Academic/research | Best instrumentation, syntax guardrails, ACI design |

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

All 535 tests across 10 repos use TypeScript/Node.js with pre-written, read-only tests. Orchestrators cannot cheat by modifying tests. Validation runs `npm run build && npm run lint && npm test` -- no subjective grading.

Each task includes at least one trap that punishes naive or template-driven approaches. See [`docs/plans/2026-02-11-survey-and-tasks-design.md`](docs/plans/2026-02-11-survey-and-tasks-design.md) for full task specifications.

## How It Works

```
thunderdome run
  |
  ├─ Clone task repo at pinned tag
  ├─ Start LiteLLM gateway (API proxy with budget caps and usage logging)
  ├─ Launch orchestrator in Docker container
  │    ├─ Mount adapter script, task description, workspace
  │    ├─ Orchestrator reads TASK.md, writes code to /workspace
  │    └─ Container exits on completion, timeout, or crash
  ├─ Capture git diff of workspace changes
  ├─ Run validation pipeline
  │    ├─ Tests (in validation image)
  │    ├─ Lint / static analysis
  │    └─ LLM rubric judge (scored against task-specific criteria)
  └─ Write results (meta.json, diff.patch, scores)
```

Each orchestrator plugs in through a shell adapter script mounted at `/adapter.sh`. The adapter translates between Thunderdome's interface (environment variables `TASK_DIR`, `TASK_DESCRIPTION`, `PROXY_URL`) and the orchestrator's native invocation.

## Usage

### Prerequisites

- Go 1.24+
- Docker

### Build

```sh
go build -o thunderdome .
```

### Configure

Create a `thunderdome.yaml`:

```yaml
orchestrators:
  - name: conclave
    adapter: ./adapters/conclave.sh
    image: conclave:latest
    env:
      CONCLAVE_MODE: autopilot

  - name: claude-code
    adapter: ./adapters/claude-code.sh
    image: claude-code:latest

tasks:
  - repo: ./benchmarks/cli-time-tracker
    tag: v1
    category: greenfield/simple
    validation_image: node:20
    install_cmd: npm install
    test_cmd: npm test
    lint_cmd: npm run lint
    rubric:
      - criterion: "Code is idiomatic TypeScript"
        weight: 0.3
      - criterion: "Error handling covers edge cases"
        weight: 0.2
    weights:
      tests: 0.5
      static_analysis: 0.2
      rubric: 0.3

trials: 3

proxy:
  gateway: litellm
  log_dir: ./results/proxy-logs
  budget_per_trial_usd: 5.00

results:
  dir: ./results
```

### Run

```sh
# Run all orchestrators against all tasks
thunderdome run

# Filter to one orchestrator or task
thunderdome run --orchestrator conclave
thunderdome run --task cli-time-tracker
thunderdome run --category greenfield/*

# Run multiple trials in parallel
thunderdome run --parallel 4 --trials 5

# List configured orchestrators and tasks
thunderdome list

# Generate report from a previous run
thunderdome report                          # latest run
thunderdome report ./results/2026-02-11_001 # specific run
thunderdome report --format markdown
thunderdome report --format json
```

### Results

Each trial produces:

```
results/<run-id>/<orchestrator>/<task>/<trial>/
├── meta.json      # Duration, exit reason, scores, token usage, cost
├── diff.patch     # Git diff of all workspace changes
└── workspace/     # Full workspace after orchestrator ran
```

The composite score blends test pass rate, static analysis, and rubric scores using task-specific weights.

## Project Structure

```
.
├── main.go                     # Entry point
├── cmd/                        # CLI commands (run, list, report, validate)
├── internal/
│   ├── config/                 # YAML config parsing and validation
│   ├── docker/                 # Container lifecycle management
│   ├── gateway/                # LiteLLM proxy start/stop, usage log parsing
│   ├── gitops/                 # Clone, checkout, diff capture
│   ├── pricing/                # Token cost calculation from pricing.yaml
│   ├── report/                 # Table, Markdown, JSON report generation
│   ├── result/                 # Trial metadata types and storage
│   ├── runner/                 # Trial execution, validation pipeline, pool
│   └── validation/             # Test runner, lint, rubric judge, composite scoring
├── adapters/                   # Shell adapter scripts per orchestrator
├── benchmarks/                 # 10 standalone task repos (each with v1/v1-solution tags)
│   ├── bench-time-tracker/     # T1: greenfield/simple (25 tests)
│   ├── bench-collab-server/    # T2: greenfield/complex (45 tests)
│   ├── bench-fts-search/       # T3: features/medium (35 tests)
│   ├── bench-phantom-invoice/  # T4: bugfix/medium (41 tests)
│   ├── bench-task-queue/       # T5: marathon (90 tests, 12 phases)
│   ├── bench-monorepo-disaster/# T6: recovery (49 tests, 6 breakages)
│   ├── bench-plugin-marketplace/# T7: greenfield/complex (55 tests)
│   ├── bench-analytics-dashboard/# T8: greenfield/complex (50 tests, parallel trap)
│   ├── bench-ssg-toolkit/      # T9: features/complex (75 tests, DAG plugins)
│   └── bench-ecommerce-backend/# T10: greenfield/complex (70 tests, event-driven)
├── docs/
│   ├── survey/                 # Orchestrator architecture survey (10 tools)
│   └── plans/                  # Design documents
├── thunderdome.yaml            # Default configuration
├── pricing.yaml                # Per-model token costs
└── project.md                  # Full project specification
```

## Writing an Adapter

An adapter script bridges Thunderdome and an orchestrator. It receives three environment variables:

| Variable | Value |
|---|---|
| `TASK_DIR` | `/workspace` -- the task repo, mounted read-write |
| `TASK_DESCRIPTION` | `/task.md` -- the task prompt |
| `PROXY_URL` | LiteLLM gateway URL for all LLM API calls |

The script must:

1. Read the task description
2. Invoke the orchestrator, pointing it at the workspace and proxy
3. Exit 0 on success, 2 if the orchestrator gives up, non-zero on error

Example (null adapter that does nothing):

```sh
#!/bin/bash
exit 0
```

## Scoring

Thunderdome scores each trial on three axes:

| Axis | Method |
|---|---|
| **Tests** | Fraction of pre-written tests that pass |
| **Static analysis** | Lint pass/fail (binary) |
| **Rubric** | LLM judge scores the diff against task-specific criteria |

The composite score is a weighted sum. Each task defines its own weights, so bugfix tasks can weight tests higher; greenfield tasks can weight the rubric higher.

## Orchestrator Genes

Thunderdome treats orchestrator features as composable "genes" for ablation studies:

| Gene | Description |
|---|---|
| `multi-agent-consensus` | Multiple models agree before proceeding |
| `cross-provider-consensus` | Different providers vs same-model copies |
| `ralph-loop` | Subagent execution pattern |
| `fresh-context` | Clear context between loop iterations |
| `plan-before-code` | Explicit architecture step before implementation |
| `self-review` | Agent reviews own code before submitting |
| `parallel-wave-execution` | Dependency-aware parallel dispatch |
| `repo-mapping` | Build codebase understanding first |

The goal: run ablation studies, add and subtract genes, and find the minimal effective set.

## Status

- [x] Orchestrator survey (10 tools documented)
- [x] Benchmark task design (10 tasks specified)
- [x] Build benchmark task repos (10 repos, 535 tests, v1/v1-solution tags)
- [ ] Harness implementation (run, list, report, validate commands)
- [ ] Write orchestrator adapters
- [ ] Run baseline comparisons
- [ ] Publish results

## License

TBD
