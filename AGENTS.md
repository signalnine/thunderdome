# AGENTS.md

Guidance for AI coding agents (Claude Code, Codex, Cursor, Aider, etc.) working in this repository. `CLAUDE.md` is a symlink to this file — edit here.

## Project Overview

Agentic Thunderdome is a benchmarking framework that pits agentic coding orchestrators against standardized programming tasks in isolated Docker containers, scoring output with automated tests and static analysis. No LLM judges — all scoring is deterministic.

Full specification: `project.md`. Current results and ablation studies: `README.md`.

## Build and Run Commands

Prefer `Makefile` targets — they handle cross-compile + Docker steps in the right order:

```bash
make build       # go build -o thunderdome .
make adapters    # cross-compiles adapters/claude-code/ws-server for linux/amd64 (CGO_ENABLED=0)
make docker      # depends on `adapters`; builds claude-code + aider images
make test        # go test ./...
make smoke       # null adapter × bench-time-tracker, single trial — fastest end-to-end check
```

Other Docker images are built by hand: `docker build -t thunderdome/<name>:latest docker/<name>/`.

Single-package tests: `go test ./internal/validation/...` or `go test ./cmd/...`.

```bash
# Run benchmarks
./thunderdome run                                              # all orchestrators × all tasks
./thunderdome run --orchestrator conclave-review-opus          # single orchestrator (exact name)
./thunderdome run --task T5                                    # single task (matches ID, repo name, or path suffix)
./thunderdome run --category "greenfield/*"                    # filter by category (wildcard supported)
./thunderdome run --parallel 4 --trials 3                      # parallel containers, multiple trials

# Other commands
./thunderdome list                                             # show configured orchestrators and tasks
./thunderdome report [run-dir]                                 # generate results (defaults to results/latest)
./thunderdome report --format markdown                         # table | markdown | json
```

## Architecture

**Go harness** (`main.go` → `cmd/` → `internal/`): Cobra CLI that orchestrates benchmark runs. Config is in `thunderdome.yaml`.

**Execution flow**: `cmd/run.go` loads config → filters orchestrators/tasks → creates run directory → launches Docker containers via `internal/docker/runner.go` → captures workspace diffs → runs validation pipeline → writes `meta.json` per trial.

**Key internal packages**:
- `internal/config/` — YAML config parsing; orchestrator/task/weights types
- `internal/docker/` — Container lifecycle (uses Docker SDK, not CLI). All containers get `--security-opt=apparmor=unconfined` and `--security-opt=seccomp=unconfined` (hardcoded at `internal/docker/runner.go:94` — required on Proxmox/AppArmor hosts)
- `internal/gitops/` — `git clone --branch <tag> --depth 1` with tag/repo validation (used to materialize benchmark workspaces)
- `internal/runner/` — Trial execution (`RunTrial` in `trial.go`), validation pipeline (`ValidateAndScore`), worker pool (`RunPool` in `pool.go`)
- `internal/validation/` — Test runner, lint checker, hidden tests, coverage, code metrics, composite scoring
- `internal/result/` — Trial directory structure, `meta.json` read/write
- `internal/report/` — Table/Markdown/JSON output generation
- `internal/gateway/` — LiteLLM API proxy (currently bypassed; thunderdome.yaml sets `gateway: none`)
- `internal/pricing/` — Token cost estimation (rates in `pricing.yaml`)

**Adapter system**: Each orchestrator plugs in via a shell script at `adapters/<name>/adapter.sh`, mounted at `/adapter.sh` in the container. Adapters receive env vars `TASK_DIR=/workspace`, `TASK_DESCRIPTION=/task.md`, and optionally `PROXY_URL`. They invoke the orchestrator and write `/workspace/.thunderdome-metrics.json` with token/cost data.

There is also a Go WebSocket SDK bridge at `adapters/claude-code/main.go` (built as `ws-server` by `make adapters`). It implements the Claude Code agent-SDK protocol but is **not** wired into the active `docker/claude-code/Dockerfile` — the live adapter calls `claude -p` headless. Treat `ws-server` as opt-in/experimental.

**Benchmark repos**: 10 standalone git repos in `benchmarks/bench-*/`, each with `v1` (starting state), `v1-solution` (reference), and optionally `v1-validation` (hidden tests) tags. The hard suite reuses several repos via additional tags. All use TypeScript/Node.js with Vitest. Currently 19 configured tasks (T1–T19): T1–T11 standard suite, T12–T19 hard suite.

**Docker images**: Built from `docker/<name>/Dockerfile`. The base `claude-code` image is the foundation for most Claude-based adapters. Other tools (Conclave, Amplifier, Gastown, Gemini CLI, Codex, CRUSH, Forge, Goose, OpenHands, Pi, etc.) ship their own images under `docker/`.

## Scoring

Two scoring paths based on task type.

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

Secrets load from `.env.secrets` (referenced via `secrets.env_file`). Env vars in orchestrator configs use `${VAR}` syntax expanded from this file.

## Docker / Host Gotchas

- **AppArmor**: All containers require `seccomp=unconfined` and `apparmor=unconfined` — hardcoded in `internal/docker/runner.go`
- **No rsync in containers**: Use `tar cf - . | tar xf - -C "$DEST"` instead
- **Shallow clone ignored on local paths**: `git clone --depth 1 ./local/path` silently ignores `--depth`
- **LiteLLM proxy bypassed**: `gateway: none` in `thunderdome.yaml`; budget enforcement not active

## Claude Code Adapter Notes

- Base adapter (`adapters/claude-code/adapter.sh`) uses `-p` headless mode: `claude -p --output-format stream-json --verbose --dangerously-skip-permissions`
- `--dangerously-skip-permissions` is required for Write/Edit in `-p` mode (the container is the sandbox)
- Some variant adapters add `--disallowed-tools "AskUserQuestion,EnterPlanMode"` (e.g. `conclave-v8-no-review-opus`, `sonnet-gstack`) — no user is present to respond
- NDJSON output on stdout contains metrics (tokens, cost); adapter parses it into `.thunderdome-metrics.json`
- OAuth-based adapters (suffix `-oauth-opus`) use Claude's built-in OAuth instead of API keys
- The `claude-code` image pins `@anthropic-ai/claude-code@2.1.119` (bumped 2026-04-25 for `--bare` support)

## Key Research Concepts

- **Orchestrator "Genes"**: Composable features (multi-agent-consensus, ralph-loop, fresh-context, plan-before-code, self-review, test-first, …) that can be isolated via ablation studies
- **Ablation methodology**: Hold everything constant except one gene; compare against vanilla Claude Code baseline
- **Task filtering**: `--task` matches task ID (T1–T19), repo name, or repo path suffix

## Issue Tracking — bd (beads)

This project uses [**bd** (beads)](https://github.com/bd-tools/bd) for issue tracking. State lives in `.bd/` at the repo root (`issues.jsonl`, `config.yaml`, push-state, etc.). Run `bd onboard` if `bd` is not yet set up locally.

```bash
bd ready                              # find available work
bd show <id>                          # view issue details
bd update <id> --status in_progress   # claim work
bd close <id>                         # complete work
bd sync                               # sync with git
```

## Landing the Plane (Session Completion)

When ending a work session, complete ALL steps. Work is NOT complete until `git push` succeeds.

1. **File issues for remaining work** — create issues for anything that needs follow-up
2. **Run quality gates** (if code changed) — `make test`, linters, builds
3. **Update issue status** — close finished work, update in-progress items
4. **Push to remote** — mandatory:
   ```bash
   git pull --rebase
   bd sync
   git push
   git status   # MUST show "up to date with origin"
   ```
5. **Clean up** — clear stashes, prune remote branches
6. **Verify** — all changes committed AND pushed
7. **Hand off** — provide context for next session

**Rules**: Work is not complete until `git push` succeeds. Never stop before pushing — that leaves work stranded locally. If push fails, resolve and retry.
