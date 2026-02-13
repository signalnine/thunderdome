# Multi-Reviewer Code Review Design

**Goal:** Enhance the code review skill to use multiple AI reviewers (Claude, Gemini, Codex) in parallel for maximum coverage and thoroughness.

**Status:** Design validated, ready for implementation

**Date:** 2025-12-13

---

## Architecture Overview

The multi-reviewer code review system will enhance the existing `requesting-code-review` skill to automatically invoke three independent reviewers in parallel:

**Core Components:**

1. **Enhanced SKILL.md** - Updated instructions that orchestrate the multi-review process
2. **Helper Script** (`multi-review.sh`) - Bash script that coordinates parallel reviews and aggregates consensus
3. **Three Review Channels:**
   - Claude subagent (via Task tool) - Required, primary reviewer
   - Gemini CLI - Optional enhancement
   - Codex MCP - Optional enhancement

**Data Flow:**

1. Assistant collects context: git diff, modified files, plan/requirements, relevant docs
2. Assistant invokes `multi-review.sh` with context as arguments
3. Script launches three reviewers in parallel background processes:
   - Spawns Claude subagent review (blocks until complete)
   - Spawns Gemini CLI review (with timeout)
   - Spawns Codex MCP review (with timeout)
4. Script captures each review output in memory (variables)
5. Script aggregates into consensus levels:
   - **All 3 agree** (or Claude + 1 other if one failed)
   - **2 reviewers flagged**
   - **Single reviewer mentioned**
6. Script outputs markdown report to stdout
7. Assistant presents report to user

**Error Handling:**
Claude review is required - if it fails, the whole process fails. Gemini/Codex are optional - if they timeout or error, continue with remaining reviewers and note the failure in the final report.

---

## Adaptive Prompting Strategy

Each reviewer receives the same review criteria but formatted appropriately for their interface.

**Base Review Prompt** (shared criteria for all reviewers):

The core prompt includes:
- **Context**: What was implemented, the plan/requirements, BASE_SHA to HEAD_SHA
- **Review Areas**: Plan alignment, code quality, architecture, documentation, testing
- **Output Format**: Structured response with issue categories (Critical, Important, Suggestions)
- **Specific Guidance**: Include code snippets in feedback, categorize severity, explain reasoning

**Adapter Layer** (per reviewer):

1. **Claude Subagent** (via Task tool):
   - Uses existing `code-reviewer.md` agent definition as-is
   - Receives full context in the task prompt
   - Natural language instruction format

2. **Gemini CLI**:
   - Wrapped command: `gemini --prompt "..." --model gemini-2.0-flash-exp`
   - Prompt formatted as single-string instruction
   - Context embedded inline in the prompt text
   - Request JSON-structured output for easier parsing

3. **Codex MCP**:
   - Uses `mcp__codex-cli__codex` tool
   - Formatted as coding assistance request: "Review this code change..."
   - Context provided via `prompt` parameter
   - Request structured feedback with clear severity markers

**Consistency Mechanism**:

The helper script contains a shared prompt template with placeholders:
```
TEMPLATE="Review the following code change:
{CONTEXT}
Evaluate: plan alignment, quality, architecture, documentation, testing
Categorize issues: Critical, Important, Suggestions
{TOOL_SPECIFIC_FORMAT}"
```

Each reviewer gets the template with tool-specific formatting instructions injected.

---

## Consensus Aggregation Logic

The `multi-review.sh` script will parse each reviewer's output and build a consensus report.

**Parsing Strategy:**

1. **Extract Issues from Each Review:**
   - Parse each reviewer's output to identify discrete issues
   - Extract: severity level, description, code location, recommendation
   - Handle varying output formats (Claude prose, Gemini JSON, Codex structured)
   - Use simple regex/grep patterns for robustness

2. **Issue Matching Algorithm:**
   - Issues are "similar" if they reference the same file/function AND similar concern
   - Simple heuristic: same filename + keyword overlap in description (≥60% word overlap)
   - Group similar issues together across reviewers

3. **Consensus Categorization:**
   - **All reviewers agree**: Issue appears in all successful reviews (3/3 or 2/2 if one failed)
   - **Majority flagged**: Issue appears in 2 out of 3 reviews
   - **Single reviewer**: Issue appears in only 1 review

**Markdown Output Format:**

```markdown
# Code Review Consensus Report

**Reviewers**: Claude ✓, Gemini ✓, Codex ✗ (timeout)
**Commits**: {BASE_SHA}...{HEAD_SHA}

## High Priority - All Reviewers Agree
- [Critical] Missing null check in parseUserInput() (line 45)
  - Claude: "Potential null pointer exception..."
  - Gemini: "Input validation missing..."

## Medium Priority - Majority Flagged (2/3)
- [Important] Error handling incomplete in saveData()
  - Claude: "Should catch IOException..."
  - Codex: "Missing error recovery..."

## Consider - Single Reviewer Mentioned
- [Suggestion] Consider extracting validation logic (Gemini only)
  - Gemini: "Could improve testability..."

## Summary
- Critical issues: 1 (consensus: 1)
- Important issues: 3 (consensus: 1, majority: 2)
- Suggestions: 5 (consensus: 0, majority: 1, single: 4)
```

**Deduplication**: If multiple reviewers mention the exact same issue, show it once with all reviewer quotes beneath it.

---

## Helper Script Implementation

The `multi-review.sh` script will be located at `skills/requesting-code-review/multi-review.sh`.

**Script Interface:**

```bash
./multi-review.sh <BASE_SHA> <HEAD_SHA> <PLAN_FILE> <DESCRIPTION>
```

Arguments:
- `BASE_SHA`: Starting commit for review
- `HEAD_SHA`: Ending commit for review
- `PLAN_FILE`: Path to plan/requirements document (or "-" for none)
- `DESCRIPTION`: Brief description of what was implemented

**Internal Structure:**

1. **Context Preparation** (lines 1-50):
   - Validate arguments
   - Generate git diff: `git diff ${BASE_SHA}..${HEAD_SHA}`
   - Get list of modified files: `git diff --name-only`
   - Read full content of modified files
   - Read plan/requirements if provided
   - Build context package (stored in variables)

2. **Parallel Review Execution** (lines 51-150):
   ```bash
   # Launch Claude subagent (required)
   claude_review=$(launch_claude_review "$context_package")
   claude_exit=$?

   # Launch Gemini in background (optional)
   gemini_review=$(timeout 60s gemini_review "$context_package") &
   gemini_pid=$!

   # Launch Codex in background (optional)
   codex_review=$(timeout 60s codex_review "$context_package") &
   codex_pid=$!

   # Wait for optional reviewers
   wait $gemini_pid; gemini_exit=$?
   wait $codex_pid; codex_exit=$?
   ```

3. **Result Handling** (lines 151-200):
   - Check Claude exit code (fail if non-zero)
   - Capture Gemini/Codex output if successful, mark failed otherwise
   - Track which reviewers succeeded for consensus calculation

4. **Consensus Aggregation** (lines 201-400):
   - Parse issues from each review (regex-based extraction)
   - Match similar issues across reviewers
   - Categorize by consensus level
   - Build markdown output

5. **Output** (lines 401-end):
   - Echo markdown report to stdout
   - Exit with 0 if Claude succeeded, 1 otherwise

**Dependencies:**
- `jq` for JSON parsing (Gemini output)
- Standard bash, git, timeout

---

## SKILL.md Integration and Workflow

The existing `skills/requesting-code-review/SKILL.md` will be updated to use the multi-reviewer system.

**Updated Workflow in SKILL.md:**

1. **Get git SHAs** (unchanged):
   ```bash
   BASE_SHA=$(git rev-parse HEAD~1)
   HEAD_SHA=$(git rev-parse HEAD)
   ```

2. **Prepare context** (new):
   - Identify the plan/requirements document path
   - Write brief description of what was implemented
   - Set variables for script invocation

3. **Invoke multi-review script**:
   ```bash
   PLAN_FILE="docs/plans/2025-12-13-feature-name.md"
   DESCRIPTION="Implemented user authentication with JWT tokens"

   ./skills/requesting-code-review/multi-review.sh \
     "$BASE_SHA" \
     "$HEAD_SHA" \
     "$PLAN_FILE" \
     "$DESCRIPTION"
   ```

4. **Act on consensus feedback** (updated):
   - **All reviewers agree** → Fix immediately before proceeding
   - **Majority flagged** → Fix unless you have strong reasoning otherwise
   - **Single reviewer** → Consider, but use judgment
   - Push back if feedback is wrong (with technical reasoning)

**Backwards Compatibility:**

The old workflow (using Task tool to dispatch code-reviewer subagent directly) still works if someone wants just Claude's review. The new workflow is the default in the updated skill.

**Documentation Updates:**

- Update `SKILL.md` with new workflow instructions
- Keep the old Task-based example in a "Single Reviewer Mode" section
- Add troubleshooting section for Gemini/Codex failures
- Update the example to show consensus output

**Files to Modify:**
1. `skills/requesting-code-review/SKILL.md` - Updated workflow
2. Create `skills/requesting-code-review/multi-review.sh` - New helper script
3. `skills/requesting-code-review/code-reviewer.md` - Keep unchanged (still used for Claude)

---

## Implementation Plan

See `2025-12-13-multi-reviewer-code-review-implementation.md` for detailed implementation tasks.

---

## Success Criteria

- [ ] `multi-review.sh` script created and executable
- [ ] Script successfully invokes all three reviewers in parallel
- [ ] Claude review is required; Gemini/Codex are optional
- [ ] Consensus aggregation produces markdown output with three priority levels
- [ ] SKILL.md updated with new workflow
- [ ] Backwards compatibility maintained for single-reviewer mode
- [ ] All changes tested with real code review scenario
- [ ] Documentation updated
