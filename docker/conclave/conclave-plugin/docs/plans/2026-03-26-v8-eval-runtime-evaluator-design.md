# v8-eval Runtime Evaluator Design

> **For Claude:** REQUIRED SUB-SKILL: Use conclave:executing-plans to implement this plan task-by-task.

**Goal:** Add an evaluator gate to ralph-loop that invokes a separate agent to diagnose test failures, improving scores on hard benchmark tasks beyond v8-combined's 88%.

**Architecture:** Generator-evaluator loop within ralph-loop. After the generator's code fails tests, an evaluator agent (separate `claude -p`) receives the task spec, raw test output, and relevant source files. It produces structured markdown feedback that replaces raw test output in `.ralph_context.md` for the next generator iteration.

**Tech Stack:** Go (ralph-loop internals), bash (adapter scripts), Claude CLI (`claude -p`)

**Design validated by:** Multi-agent consensus (Claude/Gemini/Codex) — 7 questions, all unanimous.

---

## Architecture

```
Generator (claude -p with v8-combined prompt)
    |
Test Gate (npm test / cargo test / etc.)
    | FAIL
Hash raw output -> stuck detection (unchanged)
    |
Evaluator Gate (separate claude -p, diagnostic mode)
    | produces structured feedback
Write to .ralph_context.md
    |
Generator retry (fresh context, iteration N+1)
```

- Evaluator fires only after confirmed deterministic test failure
- Evaluator failure (timeout, error) falls back to raw test output
- Evaluator invocation does NOT count against `max-iterations`
- Stuck detection stays anchored to raw test output hash (computed before evaluator)
- Opt-in via `--eval` flag on `conclave ralph-run`

## Implementation

### New file: `internal/ralph/eval.go`

`RunEvalGate` function:

1. Collect relevant files via `git diff --name-only` + regex extraction of paths from test output
2. Read file contents, deduplicate, filter `node_modules`/vendored paths
3. Build evaluator prompt: diagnostic preamble + spec + raw test output + source files
4. Invoke `claude -p --model <eval-model>`
5. Return structured markdown output (or error for fallback)

Helper functions:
- `ExtractFilePathsFromOutput(output string) []string` — regex for Node.js (`at ... (path:line)`), Python (`File "path"`), Go (`path:line`)
- `CollectRelevantFiles(projectDir, testOutput string) ([]FileContent, error)` — git diff + stack trace, deduplicated, filtered, priority-capped at 8000 lines
- `BuildEvalPrompt(spec, testOutput string, files []FileContent) string` — assembles the full evaluator prompt

### Modified file: `cmd/conclave/ralphrun.go`

New flags:
- `--eval` (bool) — enable evaluator gate
- `--eval-model` (string) — model for evaluator, defaults to empty (same as generator)
- `--eval-timeout` (int) — evaluator timeout in seconds, default 120
- `--system-prompt` (string) — custom system prompt replacing TDDPreamble

After test gate failure, before `sm.Update`:

```go
if evalEnabled {
    evalOutput, evalErr := ralph.RunEvalGate(ctx, cwd, taskFile, testOutput, evalModel, evalTimeout)
    if evalErr == nil {
        sm.Update("tests", 1, evalOutput)
    } else {
        sm.Update("tests", 1, testOutput)
    }
} else {
    sm.Update("tests", 1, testOutput)
}
```

### Modified file: `internal/ralph/state.go`

Add to `Attempt` struct:
- `EvaluatorRan bool   \`json:"evaluator_ran,omitempty"\``
- `RawOutputRef string \`json:"raw_output_ref,omitempty"\``

## Evaluator Prompt

```
You are a diagnostic assistant. Analyze the test/build/lint failures below,
identify root causes, and specify the single most impactful fix. Base your
conclusions only on the provided spec, test output, and source files. If the
root cause appears to be outside the provided files, say so explicitly rather
than speculating.

## Task Spec
{task spec content}

## Test Output (verbatim)
{raw test/build/lint output, truncated to 200 lines}

## Source Files
{each file as: ### path/to/file.ext\n```\ncontent\n```}

## Instructions
Respond using EXACTLY this template. Maximum 5 bullets per section.
Do not restate raw test output verbatim — synthesize into root causes.

## Failing Tests
- [group by root cause, not by test name]

## Unmet Requirements
- [only spec violations evidenced by actual failures]

## Priority Fix
- [exactly one highest-leverage fix, one sentence]

## Suggested Approach
- [3-5 concrete steps at the design/logic level, no code]
```

Source files capped at 8000 lines total. Priority order: files in both git diff AND stack traces > git-diff-only > stack-trace-only.

## Thunderdome Adapters

### `conclave-v8-ralph-sonnet` (control)

Ralph-loop with retry on test failure, NO evaluator. Isolates the value of simple retry.

```bash
conclave ralph-run \
  --task "$TASK_FILE" \
  --system-prompt "$V8_COMBINED_PROMPT" \
  --max-iterations 3 \
  --implement-timeout 300 \
  --test-timeout 120 \
  --skip-spec
```

### `conclave-v8-eval-sonnet` (experimental)

Same as above plus evaluator gate.

```bash
conclave ralph-run \
  --task "$TASK_FILE" \
  --system-prompt "$V8_COMBINED_PROMPT" \
  --max-iterations 3 \
  --implement-timeout 300 \
  --test-timeout 120 \
  --eval \
  --eval-timeout 120 \
  --skip-spec
```

Both use the v8-combined system prompt (~350 words). Max 3 iterations (budget constraint). Metrics: sum tokens across all generator + evaluator invocations.

## Testing

**Unit tests (`internal/ralph/eval_test.go`):**
- `TestExtractFilePaths` — Node.js, Python, Go stack trace parsing
- `TestExtractFilePaths_FiltersNodeModules` — vendored paths excluded
- `TestRunEvalGate_Fallback` — evaluator failure returns error
- `TestRunEvalGate_SourceCapping` — priority truncation at 8000 lines
- `TestBuildEvalPrompt` — prompt assembly

**Integration tests (`internal/ralph/runner_test.go`):**
- `TestRalphLoop_WithEval` — full loop with evaluator
- `TestRalphLoop_EvalTimeout` — fallback on timeout
- `TestRalphLoop_WithoutEvalFlag` — evaluator never invoked

## Success Criteria

- v8-eval-sonnet scores 2+ pp higher than v8-ralph-sonnet on hard tasks
- v8-ralph-sonnet scores >= v8-combined-sonnet (retry adds value)
- Cost per trial tracked and reported (expect 1.5-3x v8-combined)

## Out of Scope

- Multi-pass evaluator refinement
- Evaluator writing code or tests
- Opus benchmarking (deferred until Sonnet results prove pattern)
- Production skill integration
