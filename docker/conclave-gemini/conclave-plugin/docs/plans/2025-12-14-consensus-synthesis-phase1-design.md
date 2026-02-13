# Multi-Agent Consensus Synthesis - Phase 1: Replacement

**Date:** 2025-12-14
**Goal:** Replace word-clustering consensus (multi-consensus.sh) with 2-stage synthesis approach for existing integrations only.

**Phase 2 (separate):** Add consensus to systematic-debugging and root-cause-tracing

## Why Replace

**Word clustering problems:**
- Semantic negation failure: "Root cause is X" vs "Root cause is NOT X" have same keywords
- No true consensus: Just groups similar text, doesn't assess agreement
- Complex similarity algorithm: 60% threshold, stop words, file matching - all heuristics
- False positives: Unrelated issues cluster together by keyword overlap

**Synthesis approach benefits:**
- True consensus: Chairman evaluates actual agreement
- Handles negation: Explicit assessment, not keyword matching
- Simpler algorithm: No word overlap math
- Better quality: Groups issues by semantic similarity via LLM synthesis

## Architecture Overview

**Single script:** `skills/multi-agent-consensus/consensus-synthesis.sh`

**Two modes:**
1. `--mode=code-review` - For reviewing code changes
2. `--mode=general-prompt` - For design validation, architecture decisions

**Two-stage process:**

### Stage 1: Independent Analysis
- Context sent to Claude, Gemini, Codex in parallel
- Mode-specific prompts with **structured output format**
- 30s timeout per agent
- Collect all responses that succeed

### Stage 2: Consensus Synthesis
- Chairman (Claude → Gemini → Codex fallback) receives all Stage 1 analyses
- Compiles consensus report
- Mode-specific output format
- Saved to temp file (mktemp)

## Mode-Specific Implementation

### Code Review Mode

**Stage 1 Prompt (with structured output):**
```
You are reviewing a code change for potential issues.

CHANGE DESCRIPTION: <description>

PLAN (if provided): <plan file content>

CODE CHANGES:
<git diff output - truncated if >10KB>

FILES CHANGED:
<file list>

Provide your review in this EXACT format:

## ISSUES FOUND
[If no issues, write "None"]

[For each issue, use this format:]
- SEVERITY: CRITICAL | IMPORTANT | SUGGESTION
- LOCATION: file:line (if applicable)
- DESCRIPTION: What's wrong and why it matters

## OVERALL ASSESSMENT
APPROVE | APPROVE_WITH_CONCERNS | REQUEST_CHANGES

Be thorough but concise.
```

**Context truncation strategy:**
- If git diff >10KB, truncate with note: "[Diff truncated - showing first 10KB]"
- Always include: file list, change description, plan
- Prevents token overflow in Stage 2

**Stage 2 Chairman Prompt:**
```
You are compiling a code review consensus from multiple reviewers.

CRITICAL: Report all issues mentioned by any reviewer. Group similar issues together, but if reviewers disagree about an issue, report the disagreement explicitly.

CHANGE DESCRIPTION: <description>

FILES CHANGED: <file list>

REVIEWS RECEIVED (<X> of 3):

--- Claude ---
<review>

--- Gemini ---
<review>

--- Codex ---
<review>

Compile a consensus report with three tiers:

## High Priority - Multiple Reviewers Agree
[Issues mentioned by 2+ reviewers - group similar issues]
- [SEVERITY] Description
  - Reviewer A: "specific quote"
  - Reviewer B: "specific quote"

## Medium Priority - Single Reviewer, Significant
[Important/Critical issues from single reviewer]
- [SEVERITY] Description
  - Reviewer: "quote"

## Consider - Suggestions
[Suggestions from any reviewer]
- [SUGGESTION] Description
  - Reviewer: "quote"

FINAL RECOMMENDATION:
- If High Priority issues exist → "Address high priority issues before merging"
- If only Medium Priority → "Review medium priority concerns"
- If only Consider tier → "Optional improvements suggested"
- If no issues → "All reviewers approve - safe to merge"

Be direct. Group similar issues but preserve different perspectives.
```

**Note:** Stage 2 doesn't re-send full diff, reducing token usage

### General Prompt Mode

**Stage 1 Prompt (with structured output):**
```
<USER_PROMPT>

CONTEXT (if provided):
<user context - truncated if >10KB>

Provide your analysis in this format:

## ANALYSIS
[Your assessment]

## CONCERNS
[Any concerns or issues - list with severity if applicable]

## RECOMMENDATIONS
[Actionable recommendations]

Be specific and actionable.
```

**Stage 2 Chairman Prompt:**
```
You are compiling consensus from multiple analyses.

CRITICAL: If analyses disagree or conflict, highlight disagreements explicitly. Do NOT smooth over conflicts. Conflicting views are valuable.

ORIGINAL PROMPT:
<user prompt>

ANALYSES RECEIVED (<X> of 3):

--- Claude ---
<analysis>

--- Gemini ---
<analysis>

--- Codex ---
<analysis>

Provide final consensus:
1. Areas of agreement (what do reviewers agree on?)
2. Areas of disagreement (where do perspectives differ?)
3. Confidence level (High/Medium/Low)
4. Synthesized recommendation incorporating all perspectives

Be direct. Disagreement is valuable - report it clearly.
```

## Interface

**Code review:**
```bash
consensus-synthesis.sh --mode=code-review \
  --base-sha="abc123" \
  --head-sha="def456" \
  --description="Add authentication" \
  --plan-file="docs/plans/feature.md" # optional
```

**General prompt:**
```bash
consensus-synthesis.sh --mode=general-prompt \
  --prompt="What could go wrong with this design?" \
  --context="$(cat design.md)" # optional
```

## Output Format

**Console output:**
- Progress indicator: "Stage 1: Collecting reviews... 2/3 complete"
- Final consensus displayed to user
- Note: "Detailed breakdown: /tmp/consensus-XXXXXX.md"

**File output (mktemp):**
- `/tmp/consensus-XXXXXX.md`
- Contains: original context, all Stage 1 responses, Stage 2 synthesis
- User can inspect for verification

## Error Handling

**Stage 1 partial success:**
- 3/3 → Full consensus
- 2/3 → Consensus from 2 (noted in output)
- 1/3 → Single analysis + warning
- 0/3 → Abort with error

**Stage 2 failures:**
- Claude timeout → Try Gemini as chairman
- Gemini timeout → Try Codex as chairman
- All fail → Abort consensus

**Timeouts:**
- Stage 1: 30s per agent (parallel)
- Stage 2: 30s for chairman
- Total: ~60s typical

## Implementation Details

**Response parsing (Bash):**

Use clear delimiters for parallel agent responses:

```bash
# Launch agents with output to temp files
CLAUDE_OUT=$(mktemp)
GEMINI_OUT=$(mktemp)
CODEX_OUT=$(mktemp)

timeout 30s run_claude "$PROMPT" > "$CLAUDE_OUT" 2>&1 &
timeout 30s run_gemini "$PROMPT" > "$GEMINI_OUT" 2>&1 &
timeout 30s run_codex "$PROMPT" > "$CODEX_OUT" 2>&1 &

wait

# Read responses from files (no complex parsing needed)
CLAUDE_RESPONSE=$(cat "$CLAUDE_OUT")
GEMINI_RESPONSE=$(cat "$GEMINI_OUT")
CODEX_RESPONSE=$(cat "$CODEX_OUT")
```

**No need for jq or complex parsing** - each agent writes to its own file.

## Phase 1 Migration Plan

**Files to replace:**
- DELETE: `skills/multi-agent-consensus/multi-consensus.sh` (690 lines)
- DELETE: `skills/multi-agent-consensus/test-multi-consensus.sh`
- CREATE: `skills/multi-agent-consensus/consensus-synthesis.sh` (new implementation)
- CREATE: `skills/multi-agent-consensus/test-consensus-synthesis.sh`
- UPDATE: `skills/multi-agent-consensus/README.md`
- UPDATE: `skills/multi-agent-consensus/SKILL.md`

**Skills to update:**
- `skills/requesting-code-review/SKILL.md` - Update to call consensus-synthesis.sh
- `skills/brainstorming/SKILL.md` - Update to call consensus-synthesis.sh

**README examples to update:**
- All 8 integration examples → new script name

**CRITICAL - Also check:**
- `skills/requesting-code-review/multi-review.sh` - May reference multi-consensus.sh
- `skills/requesting-code-review/test-multi-review.sh` - May test old approach
- Search codebase for any other references to `multi-consensus.sh`

## Testing Strategy

**Test migration path:**
1. Create consensus-synthesis.sh
2. Run existing code review through BOTH scripts, compare output quality
3. Run existing brainstorming through BOTH scripts, compare
4. Update integrations to use new script
5. Verify all tests pass
6. Delete old script

**Unit tests:**
- Mode argument parsing
- Stage 1: Parallel collection with timeouts
- Stage 2: Chairman selection and fallback
- Context truncation (>10KB)
- Error handling
- Response parsing from temp files

**Integration tests:**
- Code review mode end-to-end
- General prompt mode end-to-end
- Partial success scenarios (2/3, 1/3)
- All failure scenarios
- Chairman fallback path

**Regression tests:**
- Verify requesting-code-review skill works
- Verify brainstorming skill works
- Compare output quality vs old approach

## Success Criteria

**Phase 1 complete when:**
- consensus-synthesis.sh works for code-review and general-prompt modes
- requesting-code-review uses new script successfully
- brainstorming uses new script successfully
- All existing tests pass
- multi-consensus.sh deleted
- No references to old script remain

## Out of Scope (Phase 2)

**NOT included in Phase 1:**
- systematic-debugging integration
- root-cause-tracing integration
- Context extraction from debugging sessions
- Debugging-specific prompts

**Phase 2 will add:** Consensus to debugging skills after Phase 1 is proven stable.

## Why This Approach

**Reduced risk:**
- Replace existing, don't add new features
- Validate synthesis approach works before expanding
- Easy to rollback if issues found

**Clear success criteria:**
- Existing integrations work with new approach
- Output quality equal or better

**Separates concerns:**
- Phase 1: Prove synthesis works
- Phase 2: Expand to new use cases

**Addresses consensus review concerns:**
- Migration plan includes multi-review.sh
- Context truncation prevents token overflow
- Structured Stage 1 output improves parsing reliability
- Temp file strategy avoids complex Bash parsing
- Phased approach reduces scope/risk
