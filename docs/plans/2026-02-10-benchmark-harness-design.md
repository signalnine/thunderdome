# Benchmark Harness Design

## System Overview

The benchmark harness is a Go CLI tool that runs agentic coding orchestrators against standardized tasks and measures their performance. It runs unattended, suitable for CI triggers or scheduled jobs.

**Core flow:**

1. Parse a run configuration (which orchestrators, which tasks, how many trials)
2. For each (orchestrator, task, trial) combination:
   - Clone the task repo and check out the tagged starting state
   - Spin up a fresh Docker container with the repo mounted
   - Start a local API proxy for cost tracking
   - Invoke the orchestrator's CLI adapter
   - Collect results: `git add -A && git diff --cached` (captures untracked files), exit code, timing, gateway logs
3. Run multi-layer validation (tests, static analysis, LLM rubric)
4. Write results to local filesystem as JSON
5. Print summary to stdout

**Key components:**

- `thunderdome` CLI binary (Go)
- Orchestrator adapter scripts (bash, one per contender)
- LiteLLM gateway for API proxying and cost tracking
- Validation pipeline (test runner, linter, LLM judge)
- Task repos with tagged starting states

## CLI Interface and Configuration

### Commands

```
thunderdome run       # Execute a benchmark run
thunderdome list      # List available tasks and orchestrators
thunderdome report    # Generate summary from stored results
thunderdome validate  # Re-score an existing result
```

### Configuration File

Run configuration lives in `thunderdome.yaml`:

```yaml
orchestrators:
  - name: superpowers-fork
    adapter: ./adapters/superpowers-fork.sh
    image: thunderdome/superpowers-fork:latest
  - name: amplify
    adapter: ./adapters/amplify.sh
    image: thunderdome/amplify:latest

tasks:
  - repo: git@github.com:org/bench-greenfield-cli.git
    tag: v1
    category: greenfield/simple
    validation_image: node:20          # Image for running tests/lints
    install_cmd: npm install           # Run before validation
    test_cmd: npm test
    lint_cmd: npx eslint .
  - repo: git@github.com:org/bench-bugfix-subtle.git
    tag: v1
    category: bugfix/complex
    validation_image: python:3.12
    install_cmd: pip install -r requirements.txt
    test_cmd: pytest
    lint_cmd: mypy .

trials: 5

proxy:
  gateway: litellm              # Use LiteLLM as the LLM gateway
  log_dir: ./results/proxy-logs
  budget_per_trial_usd: 5.00    # Kill the run if a single trial exceeds this

network:
  # Package registries the container can reach (in addition to the proxy)
  allowlist:
    - registry.npmjs.org
    - pypi.org
    - files.pythonhosted.org
    - proxy.golang.org
    - sum.golang.org
    - rubygems.org
    - ghcr.io
    - registry-1.docker.io

secrets:
  # Secrets injected into the proxy process (never into containers)
  env_file: .env.secrets         # ANTHROPIC_API_KEY, OPENAI_API_KEY, etc.

results:
  dir: ./results
```

### Run Flags

- `--config` — Path to config file (default: `thunderdome.yaml`)
- `--orchestrator` — Filter to a single orchestrator
- `--task` — Filter to a single task
- `--category` — Filter by category (e.g., `bugfix/*`)
- `--trials` — Override trial count
- `--parallel` — Max concurrent containers (default: 1)

## Orchestrator Adapters

Each orchestrator gets an adapter script that conforms to a standard contract. The harness calls the adapter; the adapter calls the orchestrator.

### Contract

```
INPUTS (environment variables):
  TASK_DIR         — Path to the mounted task repo (already at starting state)
  TASK_DESCRIPTION — Path to a file containing the task prompt
  PROXY_URL        — URL of the API proxy (e.g., http://localhost:8080)

OUTPUT:
  Exit code 0      — Orchestrator finished (not necessarily succeeded)
  Exit code 1      — Orchestrator crashed
  Exit code 2      — Orchestrator reported it cannot complete the task
  Exit code 124    — Reserved by harness for timeout (adapter should not use)

  All work happens in-place in TASK_DIR. The harness diffs against
  the starting state after the adapter exits.
```

### Example Adapter

`adapters/superpowers-fork.sh`:

```bash
#!/bin/bash
export ANTHROPIC_BASE_URL="$PROXY_URL/anthropic"
export OPENAI_BASE_URL="$PROXY_URL/openai"
export GOOGLE_BASE_URL="$PROXY_URL/google"

cd "$TASK_DIR"
superpowers run --task-file "$TASK_DESCRIPTION" --non-interactive
```

### Design Decisions

- **Bash scripts, not Go plugins.** Easy to write, debug, and contribute without touching the harness.
- **No structured output from the adapter.** The harness infers everything from the git diff and proxy logs. Adapters stay minimal.
- **Proxy URLs are the one hard requirement.** The orchestrator must route API calls through the proxy for cost tracking to work.
- **Timeouts enforced by the harness** at the container level, not by the adapter.

## Docker Container Lifecycle

Each trial runs in an isolated container.

### Per-Trial Setup

1. Clone the task repo to a temp directory, check out the tagged starting state
2. Assign a dynamic port for the LLM gateway instance (avoid collisions during parallel runs)
3. Launch a container from the orchestrator's image:
   - Task repo mounted at `/workspace`
   - Gateway URL injected as environment variable
   - Task description file mounted read-only
   - Network access limited to the gateway + allowlisted package registries
   - No API keys in the container — only the gateway holds secrets
4. Execute the adapter script inside the container
5. Enforce timeout (configurable per task category: 10 min simple, 30 min complex, 60 min marathon)
6. On exit or timeout, run `git add -A` in the workspace, then snapshot the state
7. Clean up: remove the container, its volumes, and the cloned repo temp directory

### Constraints

- No persistent volumes across trials — each run starts clean
- Network policy: containers can reach the LLM gateway and allowlisted package registries only. Orchestrators cannot call LLM APIs directly or cache results externally.
- CPU/memory limits configurable per orchestrator
- Secrets never enter containers. API keys live in the gateway process, which runs on the host (or a sidecar). The gateway scrubs keys from all logged request/response bodies.

### Parallel Execution

When `--parallel N` is set, the harness runs up to N containers concurrently. Each gets its own cloned repo, dynamically assigned gateway port, and isolated network namespace. A simple worker pool dispatches tasks in config order and collects results as they finish.

### Cleanup

After each trial, the harness removes the container and its temp directory. After the entire run completes, the harness prunes dangling Docker images and volumes older than the current run. For CI environments, an optional `--cleanup-aggressive` flag removes all thunderdome-tagged images after the run.

## LLM Gateway and Cost Tracking

Instead of building a custom proxy, the harness uses [LiteLLM](https://github.com/BerriAI/litellm) as an LLM gateway. LiteLLM already handles provider-specific API formats, streaming/SSE, and token counting — avoiding significant implementation risk.

### How It Works

The harness starts a LiteLLM instance per trial (or a shared instance with per-trial tagging). LiteLLM presents an OpenAI-compatible endpoint. Adapters that need provider-specific URLs use LiteLLM's routing:

- All providers reachable through a single base URL
- LiteLLM handles translation between provider APIs
- Token counts extracted from LiteLLM's built-in logging

The orchestrator sees a standard API. The adapter sets `PROXY_URL` to the LiteLLM instance.

### Request Log Format

LiteLLM logs are post-processed into a normalized JSONL format:

```json
{
  "timestamp": "2026-02-10T12:00:00Z",
  "orchestrator": "superpowers-fork",
  "task": "greenfield-cli",
  "trial": 3,
  "provider": "anthropic",
  "model": "claude-opus-4-6",
  "input_tokens": 4200,
  "output_tokens": 1800,
  "latency_ms": 3200,
  "status": 200
}
```

### Cost Calculation

LiteLLM tracks token counts natively. The harness also maintains a pricing table for report-time cost calculation, since LiteLLM's built-in pricing may lag behind actual rates.

```yaml
# pricing.yaml
anthropic:
  claude-opus-4-6: { input: 0.015, output: 0.075 }
openai:
  codex-max: { input: 0.01, output: 0.03 }
google:
  gemini-3-pro: { input: 0.007, output: 0.021 }
```

**Derived metrics:** total tokens, total cost, tokens per trial, cost per trial, cost per successful completion.

### Budget Enforcement

The gateway enforces a per-trial spending cap (configured in `thunderdome.yaml`). If a trial exceeds the cap, the gateway returns 429 errors for subsequent requests, and the harness records the trial as budget-exceeded. This prevents runaway loops from burning through API credits.

### Secrets Handling

API keys live in `.env.secrets` on the host, loaded only into the gateway process. They never appear in:

- Container environment variables
- Proxy logs (request/response bodies are scrubbed of Authorization headers and key parameters)
- Result artifacts

The `.env.secrets` file is gitignored. CI environments inject secrets via their native secrets manager (GitHub Actions secrets, etc.).

## Validation Pipeline

Three layers of validation run after each trial completes.

### Layer 1: Test Suite

Each task repo includes tests. The harness runs them in a **validation container** built from the task's declared validation image (specified in the task config). This image includes the language runtime and tooling the task needs.

Before running tests, the harness executes the task's declared install command (e.g., `npm install`, `pip install -r requirements.txt`) inside the validation container with the orchestrator's modified workspace mounted. This ensures any dependencies the orchestrator added are available.

- Run the task's declared test command (e.g., `go test ./...`, `pytest`, `npm test`)
- Capture: pass/fail count, total assertions, exit code, stderr
- Score: percentage of tests passing

### Layer 2: Static Analysis

Run the task's declared linters and type checkers against the modified repo, in the same validation container.

- Tools vary per task (e.g., `golangci-lint`, `eslint`, `mypy`)
- Capture: warning count, error count, diff from baseline (starting state may already have warnings)
- Score: net new warnings/errors introduced

### Layer 3: LLM Rubric

A structured evaluation by an LLM judge. Each task defines a rubric:

```yaml
rubric:
  - criterion: "Follows existing code patterns"
    weight: 2
  - criterion: "Minimal diff — no unnecessary changes"
    weight: 1
  - criterion: "Handles edge cases from the task description"
    weight: 3
```

The harness sends the git diff, task description, and rubric to an LLM (via the gateway — costs tracked separately as "harness overhead"). The judge returns a score per criterion.

**Reproducibility:** To reduce LLM judge variance, the harness runs the rubric evaluation 3 times per trial with temperature 0 and a fixed model version, then takes the median score per criterion. Results are cached by diff hash — re-running `thunderdome validate` on the same diff reuses cached scores.

### Composite Score

Each layer produces a normalized 0–1 score. The final score is a weighted combination, configurable per task category:

```yaml
weights:
  tests: 0.5
  static_analysis: 0.2
  rubric: 0.3
```

## Results Storage and Reporting

All results land on the local filesystem as structured JSON.

### Directory Layout

```
results/
├── runs/
│   └── 2026-02-10T12-00-00/
│       ├── config.yaml              # Snapshot of run config
│       ├── summary.json             # Aggregate scores
│       └── trials/
│           └── superpowers-fork/
│               └── greenfield-cli/
│                   ├── trial-1/
│                   │   ├── diff.patch
│                   │   ├── proxy-log.jsonl
│                   │   ├── test-output.txt
│                   │   ├── lint-output.txt
│                   │   ├── rubric-scores.json
│                   │   └── meta.json
│                   ├── trial-2/
│                   └── trial-3/
├── pricing.yaml
└── latest -> runs/2026-02-10T12-00-00/
```

### Trial Metadata

`meta.json` per trial:

```json
{
  "orchestrator": "superpowers-fork",
  "task": "greenfield-cli",
  "trial": 1,
  "duration_s": 342,
  "exit_code": 0,
  "exit_reason": "completed",
  "scores": { "tests": 0.95, "static_analysis": 0.88, "rubric": 0.72 },
  "composite_score": 0.87,
  "total_tokens": 48000,
  "total_cost_usd": 1.23,
  "budget_exceeded": false
}
```

`exit_reason` is one of: `completed`, `crashed`, `gave_up`, `timeout`, `budget_exceeded`.

### Reporting

`thunderdome report` reads a run directory and prints a comparison table to stdout — one row per orchestrator, columns for each metric (mean composite score, cost, tokens, pass rate). Suitable for piping to a file or rendering in CI logs.

The `latest` symlink always points to the most recent run.

## Baselines

Scores are meaningless without context. The harness includes two baseline mechanisms:

### Null Adapter

A built-in adapter (`adapters/null.sh`) that does nothing — it exits immediately without modifying the workspace. Running the null adapter against every task establishes a floor: the score you get for zero effort. Any orchestrator that scores at or below the null baseline has failed.

```bash
#!/bin/bash
# adapters/null.sh — does nothing
exit 0
```

### Reference Solutions

Tasks may include an optional reference solution (a branch or tag in the task repo). When present, the harness runs validation against the reference solution to establish a ceiling. Orchestrator scores are then reportable as a percentage of the reference score, making cross-task comparisons more meaningful.

```yaml
tasks:
  - repo: git@github.com:org/bench-greenfield-cli.git
    tag: v1
    reference_tag: v1-solution    # Optional: branch/tag with known-good solution
    category: greenfield/simple
    # ...
```

`thunderdome report` shows both raw scores and normalized scores (relative to null floor and reference ceiling) when baselines are available.

## CI Integration and Ablation Support

### CI Integration

The harness runs as a single CI step. A typical workflow:

1. CI triggers on schedule or when orchestrator adapters change
2. `thunderdome run --config thunderdome.yaml --parallel 4`
3. `thunderdome report --format markdown > results/latest/report.md`
4. Commit results to a results branch or upload as CI artifact

Dependencies: the harness binary, Docker, LiteLLM, and network access to LLM APIs. A CI runner with Docker-in-Docker or a privileged runner is required. API keys injected via CI secrets.

### Ablation Studies

The spec defines orchestrator "genes" — composable features that can be toggled. The harness supports ablation through multiple adapter configurations for the same tool:

```yaml
orchestrators:
  - name: superpowers-full
    adapter: ./adapters/superpowers-fork.sh
    image: thunderdome/superpowers-fork:latest
    env:
      CONSENSUS_ENABLED: "true"
      FRESH_CONTEXT: "true"
      SELF_REVIEW: "true"

  - name: superpowers-no-consensus
    adapter: ./adapters/superpowers-fork.sh
    image: thunderdome/superpowers-fork:latest
    env:
      CONSENSUS_ENABLED: "false"
      FRESH_CONTEXT: "true"
      SELF_REVIEW: "true"
```

Same adapter, same image, different env vars. Each variant appears as a separate orchestrator in results. Compare `superpowers-full` vs `superpowers-no-consensus` to measure the impact of a single gene.

The harness does not understand genes — it runs what the config says. Gene semantics are the adapter's responsibility.
