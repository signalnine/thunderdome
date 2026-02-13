---
name: requesting-code-review
description: Use when completing tasks, implementing major features, or before merging to verify work meets requirements
---

# Requesting Code Review

Get parallel reviews from Claude, Gemini, and Codex to catch issues before they cascade.

**Core principle:** Multiple independent reviews = maximum coverage.

## When to Request Review

**Mandatory:**
- After each task in subagent-driven development
- After completing major feature
- Before merge to main

**Optional but valuable:**
- When stuck (fresh perspectives)
- Before refactoring (baseline check)
- After fixing complex bug

## How to Request Multi-Reviewer Consensus

**1. Get git SHAs:**
```bash
BASE_SHA=$(git rev-parse HEAD~1)  # or origin/main
HEAD_SHA=$(git rev-parse HEAD)
```

**2. Identify plan file:**
```bash
PLAN_FILE="docs/plans/2025-12-13-feature-name.md"  # or "-" if no plan
DESCRIPTION="Brief description of what was implemented"
```

**3. Run multi-agent consensus:**

```bash
conclave consensus --mode=code-review \
  --base-sha="$BASE_SHA" \
  --head-sha="$HEAD_SHA" \
  --plan-file="$PLAN_FILE" \
  --description="$DESCRIPTION"
```

The framework uses a two-stage process:
- **Stage 1:** Launches Claude, Gemini, and Codex reviewers in parallel for independent analysis
- **Stage 2:** Chairman agent (Claude → Gemini → Codex fallback) synthesizes consensus
- Groups issues by agreement level:
  - **High Priority** - Multiple reviewers agree
  - **Medium Priority** - Single reviewer, significant issue
  - **Consider** - Suggestions from any reviewer
- Gracefully degrades if reviewers are unavailable

**4. Act on consensus feedback:**
- **All reviewers agree** → Fix immediately before proceeding
- **Majority flagged** → Fix unless you have strong reasoning otherwise
- **Single reviewer** → Consider, but use judgment
- Push back if feedback is wrong (with technical reasoning)

## Simplified Single-Reviewer Mode

If you need a quick review, use Claude-only mode:

Dispatch `conclave:code-reviewer` subagent directly with Task tool.

This skips Gemini/Codex and gives you just Claude's review.

## Example Multi-Review Workflow

```
[Just completed Task 2: Add verification function]

You: Let me request consensus code review.

# Get SHAs
BASE_SHA=a7981ec
HEAD_SHA=3df7661
PLAN_FILE="docs/plans/deployment-plan.md"
DESCRIPTION="Added verifyIndex() and repairIndex() with 4 issue types"

# Run multi-agent consensus
[Invoke conclave consensus]

# Framework produces consensus report:
## High Priority - All Reviewers Agree
- [Critical] Missing progress indicators
  - Claude: "No user feedback during long operations"
  - Gemini: "Progress reporting missing for iteration"
  - Codex: "Add progress callbacks"

## Medium Priority - Majority Flagged (2/3)
- [Important] Magic number in code
  - Claude: "100 should be a named constant"
  - Codex: "Extract BATCH_SIZE constant"

## Summary
- Critical: 1 (consensus: 1)
- Important: 1 (consensus: 0, majority: 1)

You: [Fix progress indicators immediately]
You: [Fix magic number]
[Continue to Task 3]
```

## Integration with Workflows

**Subagent-Driven Development:**
- Review after EACH task
- All three reviewers for thoroughness
- Fix consensus issues before next task

**Executing Plans:**
- Review after each batch (3 tasks)
- Get consensus feedback, apply, continue

**Ad-Hoc Development:**
- Review before merge
- Review when stuck

## Red Flags

**Never:**
- Skip review because "it's simple"
- Ignore Critical issues from consensus
- Proceed with unfixed consensus issues
- Argue with valid technical feedback from multiple reviewers

**If reviewers wrong:**
- Push back with technical reasoning
- Show code/tests that prove it works
- Request clarification

**If reviewers disagree:**
- Consensus issues (all agree) take priority
- Investigate majority-flagged issues
- Use judgment on single-reviewer issues

## Troubleshooting

**Gemini not available:**
- Script will mark Gemini as "✗ (not available)"
- Continue with Claude + Codex
- Consensus threshold adjusts (2/2 instead of 3/3)

**Codex MCP fails:**
- Mark Codex as "✗ (error)"
- Continue with Claude + Gemini
- Consensus threshold adjusts

**Only Claude succeeds:**
- Falls back to single-reviewer mode
- Still get thorough review from Claude
- Consider why other reviewers failed

## Files

- `conclave consensus` - Multi-agent consensus framework (code-review mode)
- `code-reviewer.md` - Claude agent definition (legacy, for single-reviewer mode)
- `multi-review.sh` - Legacy script (deprecated, use `conclave consensus` instead)
- `README.md` - Architecture documentation
