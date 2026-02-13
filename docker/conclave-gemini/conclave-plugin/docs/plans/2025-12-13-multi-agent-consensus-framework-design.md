# Multi-Agent Consensus Framework Design

**Date:** 2025-12-13
**Goal:** Create reusable infrastructure for any superpowers skill to leverage multi-agent consensus, reducing model bias and blind spots

## Problem

Different AI models have different strengths and weaknesses. A single agent may miss issues, exhibit biases, or have blind spots. The multi-reviewer code review proved that consensus from Claude, Gemini, and Codex produces more comprehensive, balanced output than any single agent.

Other superpowers workflows would benefit from this same multi-agent approach: design validation during brainstorming, root cause analysis during debugging, verification checks before completion. Rather than reimplementing consensus logic in each skill, we need reusable infrastructure.

## Solution

Build a general-purpose multi-agent consensus framework as a new top-level skill. Any skill can invoke it with a prompt and optional context, receiving back a structured consensus report grouped by agreement level.

## Architecture

### Location and Structure

```
skills/multi-agent-consensus/
├── SKILL.md                    # Skill documentation
├── multi-consensus.sh          # Main consensus script
├── test-multi-consensus.sh     # Test suite
└── README.md                   # Architecture and usage docs
```

### Interface Design

**Mode-based invocation:**
```bash
multi-consensus.sh --mode=MODE [mode-specific args]
```

**Two modes:**

1. **Code Review Mode** (migrated from requesting-code-review):
   ```bash
   multi-consensus.sh --mode=code-review \
     --base-sha="$BASE" --head-sha="$HEAD" \
     --plan-file="$PLAN" --description="$DESC"
   ```

2. **General Prompt Mode** (new):
   ```bash
   multi-consensus.sh --mode=general-prompt \
     --prompt="Should we use Redis or Postgres?" \
     --context="Background info here"
   ```

**Configuration:**
- `SIMILARITY_THRESHOLD` environment variable (default 60%)
- Mode flag is required (explicit, no auto-detection)
- Context parameter is optional in general-prompt mode

### Agent Selection

Always uses Claude, Gemini, and Codex for all modes. Maintains consistency across use cases and leverages proven working combination.

Graceful degradation:
- Claude required (script exits if Claude fails)
- Gemini optional (marks as unavailable if missing/timeout)
- Codex optional (marks as error if fails)

Consensus threshold adjusts automatically (2/2 if one fails, 3/3 if all succeed).

### Response Format

All modes require structured responses in `SEVERITY|DESCRIPTION` format.

**Code review mode:**
- `CRITICAL|description of critical issue`
- `IMPORTANT|description of important issue`
- `SUGGESTION|description of suggestion`

**General prompt mode:**
- `STRONG|description of strong point`
- `MODERATE|description of moderate point`
- `WEAK|description of weak point`

Each mode's severity labels are hardcoded in the script. Prompts instruct agents which labels to use.

### Consensus Algorithm

**Current implementation:** Word overlap with stop word filtering
- Extract unique words from each description
- Filter common stop words (the, a, an, and, or, but, in, on, at, to, for, of, with, is, are, was, were, be, been, being, have, has, had, do, does, did, will, would, should, could, may, might, must, can)
- Calculate percentage of shared words
- Normalize filenames (remove leading ./)
- Issues match if: same file AND overlap ≥ threshold

**Future upgrade path:** Semantic embeddings
- Architecture designed for pluggable consensus strategies
- Can swap in embedding-based similarity without breaking callers
- Start with word overlap, plan for semantic matching later

### Output Format

All modes produce three-tier markdown reports:

```markdown
## High Priority - All Reviewers Agree
- [SEVERITY] description
  - Reviewer1: "issue text"
  - Reviewer2: "issue text"
  - Reviewer3: "issue text"

## Medium Priority - Majority Flagged (2/3)
- [SEVERITY] description
  - Reviewer1: "issue text"
  - Reviewer2: "issue text"

## Consider - Single Reviewer Mentioned
- [SEVERITY] description
  - Reviewer1: "issue text"
```

Interpretation depends on context:
- Code review: High Priority = must fix
- General prompts: High Priority = strong consensus
- Skills adapt semantics to their use case

## Integration

### Brainstorming Skill (First Adopter)

After user validates complete design, run multi-agent validation:

1. **Prepare validation prompt:**
   ```
   Review this software design for issues. Find architectural flaws,
   missing requirements, over-engineering, maintainability concerns,
   testing gaps, or any other problems. Rate each issue as:
   STRONG (critical flaw), MODERATE (should address), WEAK (minor concern)
   ```

2. **Include design context:**
   Pass full design document text via `--context` parameter

3. **Invoke consensus:**
   ```bash
   ../multi-agent-consensus/multi-consensus.sh \
     --mode=general-prompt \
     --prompt="..." \
     --context="$DESIGN_TEXT"
   ```

4. **Present results:**
   Show consensus report to user and ask: "Multi-agent validation found X High Priority issues. Would you like to address these before proceeding to implementation?"

5. **User decides:**
   User can revise design, proceed anyway, or ask questions about feedback

### Requesting Code Review (Migration)

Update call from:
```bash
./multi-review.sh "$BASE_SHA" "$HEAD_SHA" "$PLAN_FILE" "$DESCRIPTION"
```

To:
```bash
../multi-agent-consensus/multi-consensus.sh --mode=code-review \
  --base-sha="$BASE_SHA" --head-sha="$HEAD_SHA" \
  --plan-file="$PLAN_FILE" --description="$DESCRIPTION"
```

Functionality remains unchanged. Output format identical.

### Future Skills

Any skill can invoke multi-agent consensus:

```bash
multi-consensus.sh --mode=general-prompt \
  --prompt="What could go wrong with this approach?" \
  --context="$RELEVANT_BACKGROUND"
```

Framework handles orchestration, consensus aggregation, formatted output.

## Implementation

### Refactoring Strategy

Extract from existing `multi-review.sh`:

**Shared functions (mode-agnostic):**
- `parse_issues()` - Extract SEVERITY|DESCRIPTION lines
- `extract_filename()` - Normalize file paths
- `word_overlap_percent()` - Calculate similarity
- `issues_similar()` - Check if issues match
- `aggregate_consensus()` - Group by agreement level

**Mode-specific functions:**
- `prepare_code_review_context()` - Git diff extraction
- `prepare_general_prompt_context()` - Format prompt + context
- `get_severity_labels()` - Return labels based on mode
- `format_prompt_for_mode()` - Build agent prompts

**Main script flow:**
1. Parse arguments (validate mode and mode-specific args)
2. Prepare context based on mode
3. Launch Claude/Gemini/Codex in parallel
4. Parse responses with shared parser
5. Aggregate with shared consensus algorithm
6. Output markdown report

### Error Handling

- Missing required arguments → exit with usage message
- Invalid mode → exit with error
- Claude failure → exit (required reviewer)
- Gemini failure → mark as unavailable, continue
- Codex failure → mark as error, continue
- Empty responses → treat as zero issues found

Show specific error types in report:
- "✓" - Success
- "✗ (not installed)" - CLI not found
- "✗ (timeout after 120s)" - Request timed out
- "✗ (error (exit N))" - Other error with exit code

## Testing

### Automated Tests

**Argument validation:**
- Missing --mode → error
- Invalid mode value → error
- Code review missing --base-sha → error
- General prompt missing --prompt → error

**Mode-specific behavior:**
- Code review extracts git context correctly
- General prompt formats prompt correctly
- Context parameter passes through

**Consensus algorithm** (reuse from multi-review tests):
- Filename normalization
- Word overlap with stop words
- Issue similarity matching
- Consensus grouping (High/Medium/Consider)

**Integration:**
- Code review produces expected report
- General prompt produces expected report
- Graceful degradation when reviewers fail
- Error messages show specific failure types

### Manual Validation

1. Run `requesting-code-review` on real commit → verify same quality as before
2. Run brainstorming with multi-agent validation → verify useful, actionable feedback
3. Test Gemini timeout/failure → verify error messages clear

### Success Criteria

- All automated tests pass
- Code review functionality unchanged (except script path)
- Brainstorming gets actionable multi-agent feedback
- Documentation clear for future skill authors

## Future Enhancements

**Semantic similarity matching:**
- Use embeddings instead of word overlap
- Detect paraphrasing more reliably
- Plug in without changing caller interface

**Additional modes:**
- Debugging mode (specialized prompts for root cause analysis)
- Architecture mode (design critique with specific checklist)
- Verification mode (pass/fail validation)

**Configurable severity labels:**
- Let callers specify custom labels via --severities flag
- Maintain hardcoded defaults for common modes

**More agents:**
- Support other AI models as they become available
- Configurable agent selection per mode

## Migration Path

1. Create `skills/multi-agent-consensus/` directory
2. Copy `multi-review.sh` → `multi-consensus.sh`
3. Refactor into mode-based architecture
4. Add general-prompt mode
5. Update test suite
6. Write documentation
7. Update `requesting-code-review` skill to call new location
8. Integrate into brainstorming skill
9. Validate everything works end-to-end
10. Commit and document

## Summary

This framework extracts proven multi-agent consensus logic into reusable infrastructure. Skills provide prompts, receive structured consensus reports. Architecture supports future enhancements (semantic matching, new modes) without breaking existing callers.

First integration: brainstorming skill uses multi-agent validation to catch design flaws before implementation starts. Future integrations: any skill needing diverse perspectives can tap into the same infrastructure.
