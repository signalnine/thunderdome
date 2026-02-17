# T4: Phantom Invoice Bug

**Category:** bugfix/medium
**Timeout:** 30 minutes
**Diff limit:** 20 changed lines in `src/`

## Description

An invoicing microservice has several failing tests. Your job is to find and fix the bugs so that all tests pass.

Run `npm test` to see the current failures. There are 30 visible tests — 4 are currently failing. There is also a hidden regression test suite with 10 tests. Your fix must not break any passing tests.

### Constraints

- Your changes to `src/` must be at most 20 lines (added + removed), enforced by `tests/diff-size.test.ts`.
- Do not modify any test files.
- `npm run build` and `npm run lint` must continue to pass.

### Hints

- The bugs are in the service/query layer, not in the test expectations.
- Read the failing test names carefully — they describe the expected behavior.
- Not every TODO comment or suspicious-looking function is actually a bug that needs fixing.

## Getting Started

```bash
npm install
npm test        # See which tests fail
npm run build   # Verify TypeScript compiles
npm run lint    # Verify lint passes
```

## Validation

All 30 visible tests + 10 hidden regression tests must pass. The diff constraint test must also pass.
