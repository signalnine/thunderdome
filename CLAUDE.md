# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Agentic Thunderdome is a benchmarking framework that pits agentic coding orchestrators (AI coding tools) against standardized programming tasks in isolated Docker containers, scoring output with automated tests and static analysis. No LLM judges — all scoring is deterministic.

The full specification lives in `project.md`. Current results and ablation studies are in `README.md`.

## Build and Run Commands

```bash
# Build the harness binary
go build -o thunderdome .

# Run all Go tests
go test ./...

# Run tests for a specific package
go test ./internal/validation/...
go test ./cmd/...

# Build Docker images (each orchestrator has its own image)
docker build -t thunderdome/claude-code:latest docker/claude-code/
docker build -t thunderdome/conclave:latest docker/conclave/

# Run benchmarks
./thunderdome run                                              # all orchestrators × all tasks
./thunderdome run --orchestrator conclave-review-opus           # single orchestrator
./thunderdome run --task T5                                     # single task (matches ID, repo name, or repo path suffix)
./thunderdome run --category "greenfield/*"                     # filter by category (supports wildcard)
./thunderdome run --parallel 4 --trials 3                       # parallel containers, multiple trials

# Other commands
./thunderdome list                                              # show configured orchestrators and tasks
./thunderdome report [run-dir]                                  # generate results (defaults to results/latest)
./thunderdome report --format markdown                          # table, markdown, or json
```

## Architecture

**Go harness** (`main.go` → `cmd/` → `internal/`): Cobra CLI that orchestrates benchmark runs. Config is in `thunderdome.yaml`.

**Execution flow**: `cmd/run.go` loads config → filters orchestrators/tasks → creates run directory → launches Docker containers via `internal/docker/runner.go` → captures workspace diffs → runs validation pipeline → writes `meta.json` per trial.

**Key internal packages**:
- `internal/config/` — YAML config parsing, orchestrator/task/weights types
- `internal/docker/` — Container lifecycle (uses Docker SDK, not CLI). All containers get `--security-opt=apparmor=unconfined` and `--security-opt=seccomp=unconfined` (required on Proxmox/AppArmor hosts)
- `internal/runner/` — Trial execution (`runner.RunTrial`), validation pipeline (`runner.ValidateAndScore`), worker pool (`runner.RunPool`)
- `internal/validation/` — Test runner, lint checker, hidden tests, coverage, code metrics, composite scoring
- `internal/result/` — Trial directory structure, `meta.json` read/write
- `internal/report/` — Table/Markdown/JSON output generation
- `internal/gateway/` — LiteLLM API proxy (currently bypassed with `gateway: none`)
- `internal/pricing/` — Token cost estimation

**Adapter system**: Each orchestrator plugs in via a shell script at `adapters/<name>/adapter.sh`, mounted at `/adapter.sh` in the container. Adapters receive env vars `TASK_DIR=/workspace`, `TASK_DESCRIPTION=/task.md`, `PROXY_URL`. They invoke the orchestrator and write `/workspace/.thunderdome-metrics.json` with token/cost data.

**Benchmark repos**: 11 standalone git repos in `benchmarks/bench-*/`, each with `v1` (starting state), `v1-solution` (reference), and optionally `v1-validation` (hidden tests) tags. All use TypeScript/Node.js with Vitest.

**Docker images**: Built from `docker/<name>/Dockerfile`. The base `claude-code` image is used by most Claude-based adapters. Conclave, Amplifier, Gastown, Gemini CLI, etc. each have their own images.

## Scoring

Two scoring paths based on task type:

**Standard tasks** (features, bugfix, recovery): `composite = tests × 0.7 + static_analysis × 0.3`

**Greenfield tasks** (`greenfield: true` in config): `composite = hidden_tests × 0.385 + (agent_tests × coverage) × 0.308 + build_lint × 0.154 + code_metrics × 0.154`. Weights are per-task in `thunderdome.yaml` under `green_weights`.

Test output parsing handles both Vitest line format (`N passed, M failed`) and JUnit XML.

## Results Structure

```
results/runs/<timestamp>/trials/<orchestrator>/<task>/trial-N/
├── meta.json       # scores, duration, exit reason, token usage
├── diff.patch      # git diff of workspace changes
└── task.md         # task prompt given to orchestrator
```

`results/latest` symlinks to the most recent run.

## Configuration

`thunderdome.yaml` defines orchestrators (name, adapter path, Docker image, env vars) and tasks (ID, repo, tag, category, greenfield flag, validation commands, time limits, scoring weights).

Secrets are loaded from `.env.secrets` (referenced via `secrets.env_file`). Env vars in orchestrator configs use `${VAR}` syntax expanded from this file.

## Docker / Host Gotchas

- **AppArmor**: All containers require `seccomp=unconfined` and `apparmor=unconfined` — hardcoded in `internal/docker/runner.go`
- **No rsync in containers**: Use `tar cf - . | tar xf - -C "$DEST"` instead
- **Shallow clone ignored**: `git clone --depth 1 ./local/path` silently ignores `--depth` for local paths
- **LiteLLM proxy**: Currently bypassed (`gateway: none`). Budget enforcement not active.

## Claude Code Adapter Notes

- Uses `-p` mode (headless): `claude -p --output-format stream-json --verbose --dangerously-skip-permissions`
- `--dangerously-skip-permissions` is required for Write/Edit in `-p` mode
- `--disallowed-tools "AskUserQuestion,EnterPlanMode"` on headless variants — no user to respond
- NDJSON output on stdout contains metrics (tokens, cost)
- OAuth-based adapters (suffix `-oauth-opus`) use Claude's built-in OAuth instead of API keys

## Key Research Concepts

- **Orchestrator "Genes"**: Composable features (multi-agent-consensus, ralph-loop, fresh-context, plan-before-code, self-review, test-first, etc.) that can be isolated via ablation studies
- **Ablation methodology**: Hold everything constant except one gene, compare against vanilla Claude Code baseline
- **Task filtering**: `--task` matches task ID (T1-T11), repo name, or repo path suffix
