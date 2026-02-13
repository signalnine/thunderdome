# Multi-Agent Consensus Phase 2: Debugging Skills Integration

**Date:** 2025-12-14
**Goal:** Add multi-agent consensus validation to systematic-debugging and root-cause-tracing skills after root cause identification, before implementing fixes

## Problem

Debugging skills (systematic-debugging and root-cause-tracing) help developers identify root causes systematically. However, even with thorough investigation, a single agent may:
- Miss alternative explanations for observed symptoms
- Have blind spots in pattern recognition
- Incorrectly trace causal chains
- Propose fixes for the wrong problem

Phase 1 proved multi-agent consensus works well for code review and design validation. Phase 2 extends this to debugging validation.

## Solution

Integrate multi-agent consensus as a recommended checkpoint after root cause identification in both debugging skills. Agent auto-extracts context from the debugging conversation and gets validation from Claude, Gemini, and Codex before proceeding to implement fixes.

## Integration Points

### systematic-debugging

**Trigger:** After Phase 3 (Hypothesis Testing), before Phase 4 (Implementation)

**Location in SKILL.md:** Between "Phase 3: Hypothesis Testing" and "Phase 4: Implementation" sections

**User experience:**
1. Developer completes Phases 1-3 (investigation, pattern analysis, hypothesis testing)
2. Agent identifies root cause hypothesis
3. Agent asks: "Get multi-agent consensus on root cause? (recommended)"
4. If yes → run consensus validation
5. Display results with confidence-based guidance
6. Proceed to Phase 4 based on confidence level

### root-cause-tracing

**Trigger:** After completing backward trace to root trigger, before implementing fix

**Location in SKILL.md:** After "Finding the Root Trigger" section, before fix implementation

**User experience:**
1. Developer traces backward through call stack to original trigger
2. Agent identifies root trigger
3. Agent asks: "Get multi-agent consensus on root cause? (recommended)"
4. If yes → run consensus validation
5. Display results with confidence-based guidance
6. Proceed to fix based on confidence level

## Context Extraction

**How context is built:**

Agent auto-synthesizes structured template from debugging conversation:

```markdown
## Error Description
<Extracted from user's initial bug report and observed symptoms>

## Evidence Collected
<Summarized: stack traces shown, reproduction steps tried, logs analyzed, tests run>

## Root Cause Hypothesis
<Agent's theory from Phase 3/tracing, including reasoning>

## Proposed Fix
<High-level fix approach agent is considering>
```

**Extraction sources:**
- **Error Description**: User's initial bug report, error messages, symptoms observed
- **Evidence Collected**: Investigation outputs (git diffs checked, stack traces analyzed, tests run, reproduction steps)
- **Root Cause Hypothesis**: Agent's explicit conclusion from Phase 3 or tracing completion
- **Proposed Fix**: Next steps agent was planning (before consensus)

**Fallback strategy:**

If context synthesis fails (insufficient conversation data):
```
Hypothesis: <hypothesis text only>
```

Consensus still runs with simplified prompt.

**GIGO mitigation:**

If agent's context summary is inaccurate, consensus will be on wrong premises. This is acceptable because:
1. User can inspect full breakdown in `/tmp/consensus-XXXXXX.md`
2. If reviewers flag gaps ("missing evidence"), reveals synthesis problems
3. This is validation, not primary analysis - agent already did investigation
4. Alternative (asking user to fill template) breaks debugging flow

## Consensus Execution

**Script invocation:**
```bash
skills/multi-agent-consensus/consensus-synthesis.sh --mode=general-prompt \
  --prompt="<skill-specific prompt>" \
  --context="<extracted context>"
```

**systematic-debugging prompt:**
```
Review this root cause analysis. Does the hypothesis explain all observed symptoms?
Are there alternative explanations we should consider? Are there gaps in the evidence?
Rate your confidence in this diagnosis as STRONG/MODERATE/WEAK.
```

**root-cause-tracing prompt:**
```
Review this causal trace from symptom to root trigger. Is the traced path complete
and correct? Are there missing causal links? Could the symptom have a different
root trigger? Rate your confidence in this trace as STRONG/MODERATE/WEAK.
```

**Output:**
- Console: Final consensus with confidence level and recommendation
- File: `/tmp/consensus-XXXXXX.md` (full breakdown with all analyses)

## Response Logic

**High confidence (agents agree with hypothesis):**
```
Consensus: High confidence in root cause. All/most reviewers agree. Proceed with fix.
```
→ Continue to implementation phase

**Medium confidence (majority agrees, some concerns):**
```
Consensus: Moderate confidence. Concerns raised: <summary>. Proceed with caution.
```
→ Continue to implementation with noted concerns

**Low confidence (reviewers disagree or question hypothesis):**
```
Consensus: Low confidence. Reviewers suggest: <alternatives>.
Recommend more investigation.

Type 'override' to proceed anyway or 'investigate' to gather more evidence.
```
→ Wait for user input:
  - `override` → Proceed to fix with warning
  - `investigate` → Return to investigation phase

**Infrastructure failure:**
```
Warning: Consensus unavailable (<reason>). Proceeding with single-agent analysis.
Consider manual peer review.
```
→ Continue (don't block debugging on infrastructure issues)

## Error Handling & Edge Cases

**Graceful degradation:**
- 3/3 agents → Full consensus
- 2/3 agents → Consensus from 2 (note in output)
- 1/3 agents → Single analysis + warning
- 0/3 agents → Infrastructure failure message

**Timeout handling:**
- 30s per agent in Stage 1 (parallel)
- 30s for chairman in Stage 2
- Total ~60s typical
- Partial results shown if some agents timeout

**Context extraction failures:**
- If insufficient conversation data → fall back to simple prompt
- Note in output: "Using simplified context - limited conversation history"
- Consensus still runs, just with less detail

**User override flow:**
- Low-confidence requires explicit 'override' or 'investigate'
- Prevents accidental proceeding when agents disagree
- 'override' logs warning but respects developer judgment

## Skills Modified

### systematic-debugging/SKILL.md

Add after Phase 3 (Hypothesis Testing), before Phase 4 (Implementation):

```markdown
### Multi-Agent Consensus Validation (Recommended)

Before implementing fix, get validation from multiple agents:

**Prompt:** "Get multi-agent consensus on root cause? (recommended)"

**If yes:**

1. Extract context from investigation
2. Invoke consensus:
   ```bash
   skills/multi-agent-consensus/consensus-synthesis.sh --mode=general-prompt \
     --prompt="Review this root cause analysis..." \
     --context="$DEBUGGING_CONTEXT"
   ```
3. Display consensus results
4. Apply confidence-based guidance (override for low confidence)

**Output:** Detailed breakdown saved to `/tmp/consensus-XXXXXX.md`
```

### root-cause-tracing/SKILL.md

Add after "Finding the Root Trigger", before fix implementation:

```markdown
### Multi-Agent Consensus Validation (Recommended)

Before implementing fix, validate the traced path:

**Prompt:** "Get multi-agent consensus on root cause? (recommended)"

**If yes:**

1. Extract traced path and evidence
2. Invoke consensus:
   ```bash
   skills/multi-agent-consensus/consensus-synthesis.sh --mode=general-prompt \
     --prompt="Review this causal trace..." \
     --context="$TRACE_CONTEXT"
   ```
3. Display consensus results
4. Apply confidence-based guidance (override for low confidence)

**Output:** Detailed breakdown saved to `/tmp/consensus-XXXXXX.md`
```

### multi-agent-consensus/README.md

Add to "Integration Examples" section:

```markdown
**9. Debugging (systematic-debugging)**

Validate root cause hypothesis before implementing fix:
```bash
CONTEXT=$(cat << EOF
## Error Description
Test fails: "Expected 5, got 3"

## Evidence Collected
- Reproduction: Always fails on TestCase.test_calculation
- Stack trace points to calculation() in math.py:42
- Git diff shows recent refactor of calculation logic

## Root Cause Hypothesis
Off-by-two error introduced in refactor - loop starts at 1 instead of 0

## Proposed Fix
Change loop start from 1 to 0
EOF
)

skills/multi-agent-consensus/consensus-synthesis.sh --mode=general-prompt \
  --prompt="Review this root cause analysis. Does hypothesis explain symptoms? Alternative explanations? Gaps in evidence? Rate confidence as STRONG/MODERATE/WEAK." \
  --context="$CONTEXT"
```

**10. Debugging (root-cause-tracing)**

Validate traced causal path:
```bash
CONTEXT=$(cat << EOF
## Error Description
Git init fails with "directory not found"

## Evidence Collected
- Error in WorktreeManager.createWorktree() at line 67
- Called by Session.initialize()
- Called by test Project.create()
- projectDir passed as empty string

## Root Cause Hypothesis
Test setup doesn't initialize projectDir before calling Project.create()

## Proposed Fix
Add projectDir initialization in test setup
EOF
)

skills/multi-agent-consensus/consensus-synthesis.sh --mode=general-prompt \
  --prompt="Review this causal trace. Is traced path complete? Missing links? Different root trigger possible? Rate confidence as STRONG/MODERATE/WEAK." \
  --context="$CONTEXT"
```
```

## Testing Strategy

**Unit tests:**
- Context extraction from mock debugging conversation
- Response logic for each confidence level (high/medium/low)
- Override and investigate user flows
- Infrastructure failure handling

**Integration tests:**
- Full systematic-debugging flow with consensus
- Full root-cause-tracing flow with consensus
- Opt-out path (skip consensus)
- Low-confidence override flow
- Infrastructure failure scenarios

**Manual testing:**
- Real debugging session with consensus
- Verify context extraction accuracy
- Test with partial agent availability (1/3, 2/3)

## Why This Works

**Same checkpoint pattern:** Both skills reach "I know the root cause, should I fix?" - ideal validation point

**Recommended but optional:** Respects debugging flow while encouraging validation

**Auto-extraction:** No manual template filling - agent synthesizes from conversation

**Confidence-based friction:** Low confidence requires override, preventing fixing wrong problem

**Graceful degradation:** Works with 1-3 agents, fails safely on infrastructure issues

**Consistent with Phase 1:** Uses same consensus-synthesis.sh script, same /tmp output location

**Addresses real risk:** Debugging under pressure makes guessing tempting - consensus catches flawed reasoning

## Phase 2 Scope

**In scope:**
- Integration into systematic-debugging SKILL.md
- Integration into root-cause-tracing SKILL.md
- Documentation updates (README examples)
- Testing (unit + integration)

**Out of scope (future):**
- Other skills integration (security-review, performance-optimization, etc.)
- Enhanced context extraction (semantic analysis, automated evidence gathering)
- Custom confidence thresholds per skill
- Consensus caching/memoization

## Implementation Notes

**Context extraction implementation:**

Since this runs within a skill, the agent has full conversation history. Extract by looking for:
- User's initial error description
- Agent's investigation outputs (grep results, test runs, git diffs)
- Agent's explicit hypothesis statement
- Agent's proposed next steps

**Response parsing:**

Agent displays consensus results and waits for user input on low-confidence cases. Use simple string matching for 'override' and 'investigate' commands.

**Integration approach:**

Update SKILL.md files to add consensus checkpoint as optional step. Don't modify core skill logic - consensus is additive validation layer.
