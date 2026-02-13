# Multi-Reviewer Code Review System

## Migration Note

**The multi-review.sh script has been migrated to the multi-agent-consensus framework.**

- **Old location:** `skills/requesting-code-review/multi-review.sh` (deprecated)
- **New location:** `skills/multi-agent-consensus/consensus-synthesis.sh --mode=code-review`

The requesting-code-review skill now uses the new framework for all multi-agent reviews.

## Architecture

This directory contains integration with the multi-agent consensus framework that coordinates parallel reviews from three AI reviewers:

1. **Claude Code** (required) - Mock review for now
2. **Gemini** (via CLI) - Optional
3. **Codex** (via MCP) - Optional

## How It Works

### Direct Invocation (Gemini only)

The `multi-review.sh` script can directly invoke:
- ✅ Gemini CLI (subprocess)
- ❌ Claude Task tool (requires Claude Code environment)
- ❌ Codex MCP (requires Claude Code environment)

### Claude Code Orchestration

When invoked from within a Claude Code session, the assistant:

1. Calls `multi-review.sh` to get Gemini's review
2. Simultaneously dispatches Claude subagent review (via Task tool)
3. Simultaneously calls Codex MCP (via mcp__codex-cli__codex tool)
4. Aggregates all three reviews into consensus report

## Files

- `multi-review.sh` - Main coordination script
- `SKILL.md` - Instructions for Claude Code assistant
- `code-reviewer.md` - Agent definition for Claude review
- `test-multi-review.sh` - Test suite
- `README.md` - This file

## Testing

Run the test suite:
```bash
./skills/requesting-code-review/test-multi-review.sh
```

Test with real code:
```bash
BASE_SHA=$(git rev-parse HEAD~1)
HEAD_SHA=$(git rev-parse HEAD)
./skills/requesting-code-review/multi-review.sh "$BASE_SHA" "$HEAD_SHA" "-" "Test review"
```

## Dependencies

- bash 4.0+
- git
- bc (for calculations)
- gemini CLI (optional, for Gemini reviews)
- Claude Code (optional, for Claude/Codex reviews)

## Usage from Claude Code

When the assistant uses the requesting-code-review skill, it should:

1. **Prepare context:**
   ```bash
   BASE_SHA=$(git rev-parse HEAD~1)
   HEAD_SHA=$(git rev-parse HEAD)
   PLAN_FILE="docs/plans/feature.md"
   DESCRIPTION="What was implemented"
   ```

2. **Launch Gemini review in background:**
   ```bash
   GEMINI_OUTPUT=$(./skills/requesting-code-review/multi-review.sh \
       "$BASE_SHA" "$HEAD_SHA" "$PLAN_FILE" "$DESCRIPTION" 2>/dev/null) &
   GEMINI_PID=$!
   ```

   **Note:** This shows the conceptual workflow. In practice, the script handles Gemini directly while the assistant must orchestrate Claude and Codex reviews separately.

3. **Simultaneously launch Claude subagent:**
   Use Task tool with conclave:code-reviewer

4. **Simultaneously launch Codex MCP:**
   Use mcp__codex-cli__codex tool

5. **Wait for Gemini:**
   ```bash
   wait $GEMINI_PID
   ```

6. **Aggregate all three reviews:**
   Parse issues, group by consensus, present to user

## Example Output

```markdown
# Code Review Consensus Report

**Reviewers**: Claude ✓, Gemini ✓, Codex ✓
**Commits**: abc123..def456

## High Priority - All Reviewers Agree
- [Critical] Missing null check in parseInput() (line 45)
  - Claude: "Potential null pointer exception when input is empty"
  - Gemini: "Input validation missing - null case not handled"
  - Codex: "Add null check before accessing input.length"

## Medium Priority - Majority Flagged (2/3)
- [Important] Error handling incomplete in saveData()
  - Claude: "Should catch IOException and provide user feedback"
  - Codex: "Missing error recovery for file write failures"

## Consider - Single Reviewer Mentioned
- [Suggestion] Extract validation logic to separate function
  - Gemini: "Would improve testability and reusability"

## Summary
- Critical issues: 1 (consensus: 1)
- Important issues: 1 (consensus: 0, majority: 1)
- Suggestions: 1 (consensus: 0, majority: 0, single: 1)
```

## Consensus Interpretation

- **High Priority (All Agree)**: Fix immediately. Multiple independent reviewers identified the same issue.
- **Medium Priority (Majority)**: Strong signal. Fix unless you have technical justification.
- **Consider (Single)**: May be valid but less critical. Use judgment based on context.
