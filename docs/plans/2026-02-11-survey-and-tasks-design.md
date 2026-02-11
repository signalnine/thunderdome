# Orchestrator Survey & Benchmark Tasks Design

## Part 1: Orchestrator Survey

### Scope

Survey 8 agentic coding tools, one per architectural archetype:

| Archetype | Tool | Rationale |
|-----------|------|-----------|
| CLI turn-based | Aider | Most mature CLI tool; well-documented architecture (edit formats, repo-map, etc.) |
| CLI agentic | Claude Code | Direct access; represents the "tool-use agent loop" pattern |
| Autonomous agent | Devin | Full autonomy with planning, browser, shell; ceiling of agent complexity |
| Academic/research | SWE-agent | Published papers with ablations; best-documented architecture decisions |
| Multi-agent platform | OpenHands | Open-source, multi-agent with delegation; contrasts single-agent tools |
| IDE-integrated | Continue.dev | "Human-in-the-loop with agent assist" model |
| Consensus/multi-model | Superpowers (Original) | Baseline our fork modifies; directly relevant to H1 and H2 |
| Scaffold/generator | GPT-Engineer | "Plan-then-generate" one-shot approach; useful as a control |

Tools not surveyed in depth (brief appendix entries if architecturally distinct): Amplify, Gas Town, Mentat, Smol Developer, AutoGPT/BabyAGI.

### Per-Tool Template

For each tool, document:

1. **Architecture type** — single-agent loop, multi-agent, one-shot, human-in-loop
2. **Context strategy** — how it manages context window (repo-map, RAG, summarization, fresh-context rotation)
3. **Planning approach** — upfront plan, iterative, none
4. **Edit mechanism** — whole-file, search-replace, diff, AST-aware
5. **Self-correction** — does it run tests, review its own output, retry on failure
6. **Gene list** — which composable patterns it exhibits from the known gene list, plus any new genes discovered
7. **Benchmark-relevant traits** — anything that affects task design or measurement (e.g., "uses browser," "requires human approval gates," "has built-in cost tracking")

Skip: pricing, setup instructions, UI polish — nothing irrelevant to benchmark design.

### Output Format

Single markdown document: `docs/survey/orchestrator-survey.md`

Structure:
1. **Gene Matrix** — tool × gene table for at-a-glance comparison
2. **Per-Tool Notes** — only where something is surprising or cannot be captured in the matrix
3. **Observations for Benchmark Design** — cross-cutting patterns, gaps, and hypotheses the survey informs

### Research Method

Desk research using public documentation, published papers, blog posts, and open-source code. We do not need to run most tools — the goal is to understand architectural patterns, not benchmark them yet.

---

## Part 2: Benchmark Tasks

### Design Principles

- **All TypeScript/Node.js** — isolates orchestration quality from language proficiency; fairest language across all LLMs; one ecosystem means one test runner, one linter, one Docker image pattern
- **Pre-written, read-only tests** — orchestrators cannot cheat by modifying tests
- **Validated by `npm run build && npm run lint && npm test`** — no subjective grading
- **No external services** — everything runs in a single Docker container; SQLite only
- **Hypothesis-driven** — each task targets specific research hypotheses (H1-H4)
- **Each task has at least one "trap"** — punishes naive or template-driven approaches

### Task Definitions

#### Task 1: CLI Time Tracker

| Field | Value |
|-------|-------|
| Category | greenfield/simple |
| Timeout | 10 minutes |
| Hypotheses | Baseline, H2 |
| Tests | 25 |

**Description:** Build a command-line time tracking tool. Commands: `track start "task name"`, `track stop`, `track log` (with `--since YYYY-MM-DD` filtering), `track summary` (table grouped by task name with total durations). Data persists to `~/.track/data.json`. Starting a new task while one is running auto-stops the previous one. All times in local timezone.

**Starting state:** Empty `src/` directory with `package.json` (typescript, vitest, tsx as devDependencies), `tsconfig.json`, `.eslintrc` config. No source files.

**Validation:**
- 25 unit/integration tests in `tests/` (read-only) covering: start/stop lifecycle, double-start auto-stop, log filtering by date, summary aggregation, persistence across invocations, edge cases (stop with nothing running, empty log)
- TypeScript compiles cleanly
- Lint passes

**Trap:** Auto-stop behavior on double-start; date filtering edge cases.

---

#### Task 2: Real-Time Markdown Collaboration Server

| Field | Value |
|-------|-------|
| Category | greenfield/complex |
| Timeout | 30 minutes |
| Hypotheses | H1, H2 |
| Tests | 40+ |

**Description:** Build a WebSocket-based collaborative Markdown editing system with three components: (1) HTTP/WebSocket server managing documents and broadcasting edits, (2) OT or CRDT-based conflict resolution so simultaneous edits converge, (3) REST API for document CRUD with SQLite persistence via `better-sqlite3`. Documents have version history — every edit stored, any past version retrievable via `GET /docs/:id/versions/:version`. WebSocket clients join a document room, send edit operations (insert/delete at position), receive transformed operations. Must handle 10 concurrent clients without corruption.

**Starting state:** `package.json` (ws, better-sqlite3, express; typescript, vitest), `tsconfig.json`, `schema.sql` defining tables. Empty `src/`.

**Validation:**
- 40+ tests covering REST CRUD, version retrieval, WebSocket lifecycle, single-client edit round-trip, two-client concurrent edit convergence, ten-client stress test, edit ordering, persistence across restart, malformed operation rejection, document-not-found
- Dedicated convergence test: two clients apply conflicting edits at same position, both fetch final document, content is identical
- Build and lint pass

**Trap:** OT/CRDT convergence logic — naive implementations fail concurrent edit tests.

---

#### Task 3: Add Full-Text Search to a Note-Taking API

| Field | Value |
|-------|-------|
| Category | features/medium |
| Timeout | 30 minutes |
| Hypotheses | H2, H4 |
| Tests | 20 new + 15 existing |

**Description:** An existing Express + SQLite note-taking API has CRUD endpoints for notes (title, body, tags, timestamps) and tag-based filtering. Add full-text search using SQLite FTS5: `GET /notes/search?q=<query>` with relevance ranking, snippet highlighting (`<mark>` tags), quoted phrase support, pagination (20/page). FTS index must sync on create/update/delete. Also add `GET /notes/search/suggest?q=<prefix>` autocomplete returning up to 5 matching titles.

**Starting state:** Fully functional 400-line codebase (6 files: server, routes, db, model, error middleware). 15 passing tests. Seed script loading 200 notes.

**Validation:**
- 20 new tests in `tests/search.test.ts` (read-only): keyword search, phrase search, ranking order, snippet markup, pagination, autocomplete, FTS sync on CRUD, empty query, special character escaping
- All 15 existing CRUD tests still pass
- Search response under 100ms on 200-note dataset
- Build and lint pass

**Trap:** FTS5 integration requires SQLite virtual tables and sync triggers; regression risk on existing tests.

---

#### Task 4: The Phantom Invoice Bug

| Field | Value |
|-------|-------|
| Category | bugfix/medium |
| Timeout | 30 minutes |
| Hypotheses | H1 |
| Tests | 30 + 10 hidden |

**Description:** An invoicing microservice has three interrelated bugs: (1) timezone/date-boundary bug where `getMonth()` is used without UTC normalization, so invoice grouping depends on server timezone, (2) floating-point discount calculation with misplaced parenthesis conflating two discount modes, (3) off-by-one in pagination date range filter (inverted `<`/`>=` boundaries). Red herrings included: an irrelevant "TODO: fix timezone" comment and an unused utility function with its own unrelated bug.

**Starting state:** 600-line codebase across 8 files. 4 of 30 tests failing. Descriptive test names but no direct hints about which file/line is buggy.

**Validation:**
- All 30 tests pass (26 previously passing must not regress)
- 10 hidden regression tests in `tests/regression.test.ts` (read-only) pass
- Max 20-line diff (enforced by validation script) — prevents "rewrite the world"
- Build and lint pass

**Trap:** Red herrings; diff-size constraint forces precision; three bugs interact.

---

#### Task 5: Build a Task Queue System, Incrementally

| Field | Value |
|-------|-------|
| Category | marathon |
| Timeout | 60 minutes |
| Hypotheses | H3 |
| Tests | ~90 across 12 phases |

**Description:** Build an in-memory task queue through 12 sequential phases, each building on the last. Phases: (1) basic FIFO, (2) named queues, (3) priorities, (4) delayed/scheduled tasks, (5) retry with exponential backoff, (6) dead-letter queue, (7) task dependencies, (8) concurrency control, (9) progress reporting and cancellation, (10) recurring tasks with cron expressions, (11) task middleware pipeline, (12) graceful shutdown. Naive implementations of early phases require refactoring when later phases add constraints.

**Starting state:** `package.json`, `tsconfig.json`, 12 phase markdown files in `phases/`, 12 test files in `tests/`. Empty `src/`.

**Validation:**
- Each phase's tests pass independently (`npm test -- tests/phase-01.test.ts` through `phase-12.test.ts`)
- All 12 test files pass together
- Meta-test touching all 12 features simultaneously
- Build and lint pass

**Trap:** Compounding design debt — array-based FIFO from phase 1 becomes inadequate for priorities in phase 3; basic retry from phase 5 needs rethinking for dependencies in phase 7.

---

#### Task 6: Untangle the Monorepo Disaster

| Field | Value |
|-------|-------|
| Category | recovery |
| Timeout | 30 minutes |
| Hypotheses | H4 |
| Tests | 35 + structural validations |

**Description:** A three-package TypeScript monorepo (npm workspaces) is broken after a botched merge and half-finished refactor. Six breakages: (1) circular dependency in `packages/core` (A→B→C→A), (2) half-renamed function (`createUser`→`registerUser`, some call sites still use old name), (3) out-of-order `tsconfig.json` project references, (4) dependency version conflict (`zod@3.20` vs `zod@3.22+` needed for `z.pipe`), (5) merge conflict markers in a test file, (6) accidentally committed `.env` with placeholder values (test should use hardcoded connection string).

**Starting state:** Full monorepo, ~1,200 lines across 3 packages. `npm install` works, `npm run build` and `npm test` fail. Git log shows "Merge branch 'refactor/user-system' — WIP, will fix later."

**Validation:**
- `npm run build` succeeds across all packages
- `npm test` passes (35 tests)
- `npm run lint` passes
- `madge --circular` finds no circular deps
- No merge conflict markers in codebase
- No `.env` file with secrets
- TypeScript strict mode in all packages

**Trap:** Six interacting problems; fixing one may affect others. Tests diagnostic breadth.

---

### Build Order

1. **First:** Tasks 1 (CLI Time Tracker) and 4 (Phantom Invoice Bug) — simplest to create, validate harness end-to-end
2. **Second:** Tasks 3 (FTS Search) and 6 (Monorepo Disaster) — medium complexity to create
3. **Third:** Tasks 2 (Collab Server) and 5 (Task Queue) — most complex to create, need careful test design

### Task Repo Structure

Each task is a standalone git repo with:
```
bench-<name>/
├── package.json
├── tsconfig.json
├── .eslintrc.cjs
├── TASK.md              # Task description for the orchestrator
├── src/                 # Starting source (empty for greenfield, populated for others)
├── tests/               # Pre-written tests (read-only during trial)
└── .thunderdome/
    ├── rubric.yaml      # LLM judge criteria
    └── validate.sh      # Any extra validation scripts (diff size check, etc.)
```

### Validation Image

All tasks use the same Docker validation image: `node:20` with dev tools pre-installed. The `thunderdome.yaml` config for each task specifies:
```yaml
validation_image: node:20
install_cmd: npm install
test_cmd: npm test
lint_cmd: npm run lint
```
