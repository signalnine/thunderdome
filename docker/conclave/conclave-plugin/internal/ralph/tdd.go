package ralph

// TDDPreamble is prepended to every ralph-loop iteration prompt to enforce
// TDD discipline and the completion gate. This was identified as the single
// most effective methodology in Thunderdome benchmarks (+12.3pp over vanilla).
const TDDPreamble = `## MANDATORY: Test-Driven Development

You MUST follow TDD for ALL implementation work. No exceptions.

**The Iron Law: NO PRODUCTION CODE WITHOUT A FAILING TEST FIRST.**

For each piece of functionality:
1. **RED** — Write one failing test. Run it. Confirm it fails for the right reason.
2. **GREEN** — Write the MINIMAL code to make the test pass. Nothing more.
3. **REFACTOR** — Clean up while keeping tests green.
4. Repeat for next behavior.

Wrote code before a test? Delete it. Start over with a failing test.

## MANDATORY: Completion Gate

Before claiming done, you MUST:
1. Run the FULL project verification suite (tests + build + lint), not just your new tests
2. Read COMPLETE output. Count failures.
3. If ANY failure: fix and re-run. Do NOT claim done.
4. Commit your work
5. Review your diff: git diff HEAD~1
6. Look for: missing edge cases, incomplete implementations, dead code, debug artifacts
7. If issues found: fix, re-verify, re-commit
8. Only report success when verification passes AND diff review is clean
`
