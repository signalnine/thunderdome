---
name: brainstorming
description: Use when starting any creative work - creating features, building components, adding functionality, or modifying behavior
---

# Brainstorming Ideas Into Designs

## Overview

Help turn ideas into fully formed designs and specs through natural collaborative dialogue.

Start by understanding the current project context, then ask questions one at a time to refine the idea. Once you understand what you're building, present the design in small sections (200-300 words), checking after each section whether it looks right so far.

## Session Recovery

**At the start of every brainstorming session**, check for incomplete checkpoints:

```bash
ls docs/plans/.brainstorm-checkpoint-*.json 2>/dev/null | head -1
```

If checkpoint exists and is less than 24 hours old:

```
Found incomplete brainstorming session from [time ago]:
Topic: "[topic from checkpoint]"
Progress: [N] questions answered ([mode] mode)

Options:
1. Resume from checkpoint
2. Start fresh (discards previous progress)
```

On resume:
- Load decisions from checkpoint JSON
- Summarize: "Resuming. Decisions so far: [list key decisions]..."
- Continue from where session left off

If no checkpoint or user chooses fresh start, proceed to The Process.

## The Process

**Understanding the idea:**
- Check out the current project state first (files, docs, recent commits)
- Then offer mode selection (see below)
- Ask questions one at a time to refine the idea
- Prefer multiple choice questions when possible, but open-ended is fine too
- Only one question per message - if a topic needs more exploration, break it into multiple questions
- Focus on understanding: purpose, constraints, success criteria

**Mode Selection** (after checking project context):

**If `CONCLAVE_NON_INTERACTIVE=1`:** Skip mode selection, use Consensus Autopilot automatically. Announce: "Non-interactive mode: using Consensus Autopilot."

Otherwise, present the choice:

```
I'll help design this feature. Two modes available:

1. **Interactive** - I ask questions, you answer, we iterate together
2. **Consensus Autopilot** - Multi-agent consensus (Claude, Gemini, Codex)
   answers design questions. You watch decisions narrate and can interrupt
   anytime to override.

Note: Autopilot calls consensus for each question (~30-60 seconds each).
Full design typically takes 5-10 minutes.

Which mode?
```

- If **Interactive**: Proceed with normal question flow (one at a time, user answers)
- If **Autopilot**: See "Autopilot Mode" section below

**Exploring approaches:**
- Propose 2-3 different approaches with trade-offs
- Present options conversationally with your recommendation and reasoning
- Lead with your recommended option and explain why

**Presenting the design:**
- Once you believe you understand what you're building, present the design
- Break it into sections of 200-300 words
- Ask after each section whether it looks right so far
- Cover: architecture, components, data flow, error handling, testing
- Be ready to go back and clarify if something doesn't make sense

## Autopilot Mode

When user selects autopilot, announce: "Starting autopilot. I'll narrate each decision. Jump in anytime to override."

**For each design question:**

1. **Format the question for consensus:**
   ```
   Design decision needed: [question]

   Context: [what we're building, decisions made so far]

   Options I'm considering:
   - Option A: [description]
   - Option B: [description]
   - Option C: [description]

   You may suggest alternatives. Recommend one option with brief reasoning.
   ```

2. **Call consensus:**
   ```bash
   conclave consensus --mode=general-prompt \
     --prompt="$FORMATTED_QUESTION" \
     --context="$PROJECT_CONTEXT"
   ```

3. **Narrate the result:**
   ```
   Q: What database technology?
   → Consensus recommends: PostgreSQL
     Reasoning: "Relational model fits the entity relationships,
     ACID compliance needed for financial data, team has experience."

   Proceeding...
   ```

4. **Save checkpoint** (see Checkpoint Saving below)

5. **Continue to next question** - if user sends any message, that's an interrupt

**Error Handling:**

If consensus fails (timeout, API errors, <2 agents respond):
```
Consensus unavailable for this question. Falling back to interactive:

Q: What database technology?
Options:
1. PostgreSQL - relational, ACID compliant
2. MongoDB - document store, flexible schema
3. SQLite - embedded, simple

Your choice?
```
After user answers, offer: "Resume autopilot for remaining questions, or stay interactive?"

If consensus returns split decision (no clear winner):
```
Consensus split on this question:
- Claude recommends PostgreSQL (relational model fits)
- Gemini recommends MongoDB (schema flexibility)
- Codex recommends PostgreSQL (team experience)

No strong consensus. Your call - which direction?
```
Then resume autopilot after user decides.

## Interrupt Handling

When user sends any message during autopilot:

1. **Pause immediately** and acknowledge

2. **Present options:**
   ```
   Paused. What would you like to change?

   Last decision: [question → answer]

   Options:
   - Override this decision (tell me your preference)
   - Go back further (redo earlier decisions)
   - Switch to interactive mode (take over from here)
   - Resume autopilot (continue as-is)
   ```

3. **Handle response:**
   - **Override**: Record user's choice, resume autopilot from next question
   - **Go back**: Show recent decisions, let user pick restart point, then re-run ALL subsequent questions with fresh consensus (don't reuse old answers)
   - **Switch to interactive**: Continue with normal Q&A flow
   - **Resume**: Continue where paused

4. **On resume:**
   ```
   Resuming autopilot with your override: [change made]

   Next question...
   ```

## Checkpoint Saving

**After each decision** (in either mode), save state:

```bash
# Checkpoint file path
CHECKPOINT="docs/plans/.brainstorm-checkpoint-$(date +%Y%m%d).json"
```

Checkpoint JSON structure:
```json
{
  "topic": "user authentication feature",
  "mode": "autopilot",
  "created_at": "2025-01-18T10:30:00Z",
  "updated_at": "2025-01-18T10:35:00Z",
  "decisions": [
    {"q": "Target users?", "answer": "B2B enterprise", "source": "consensus"},
    {"q": "Database?", "answer": "PostgreSQL", "source": "user"}
  ],
  "current_phase": "questions",
  "project_context": "summary of what we're building"
}
```

Write checkpoint after each decision using the Write tool.

**Cleanup:** Delete checkpoint file when design is complete and saved to final document.

## Context Management

**Compact at phase transitions** to preserve context for later phases:

- **Before design presentation** (after all questions answered): Run `/compact` with decisions summary:
  ```
  /compact Brainstorming [topic]. Decisions made: [list key decisions]. Mode: [interactive/autopilot]. Ready to present design.
  ```
- **Before consensus validation** (after design written): Run `/compact` with design file reference:
  ```
  /compact Design written to [file path]. Ready for multi-agent validation.
  ```
- **Before implementation handoff** (after validation): Run `/compact` with final state:
  ```
  /compact Design validated. File: [path]. Ready for implementation setup.
  ```

**Why:** Brainstorming accumulates substantial context from questions, consensus calls, and design iterations. Compacting before validation ensures the consensus agents get clean, focused context.

## After the Design

**For Autopilot Mode - Summarize Decisions:**
```
Design complete. Consensus made [N] decisions:

- Database: PostgreSQL (consensus)
- API style: REST (consensus)
- Frontend: React (you overrode → Vue)
- Auth: JWT (consensus)
...

Review the full design below, then we'll run final validation.
```

**Documentation:**
- Write the validated design to `docs/plans/YYYY-MM-DD-<topic>-design.md`
- Use elements-of-style:writing-clearly-and-concisely skill if available
- Commit the design document to git
- **Delete checkpoint file** after successful save

**Multi-Agent Design Validation (Recommended):**

After the user validates the complete design, run multi-agent review:

"Running multi-agent validation. Claude, Gemini, and Codex will review for architectural flaws, over-engineering, and missing requirements..."

**Always run unless user explicitly skips:**
1. Prepare validation prompt:
   ```
   Review this software design for issues. Find architectural flaws, missing
   requirements, over-engineering, maintainability concerns, testing gaps, or
   any other problems. Rate each issue as:
   STRONG (critical flaw), MODERATE (should address), WEAK (minor concern)
   ```

2. Invoke consensus:
   ```bash
   DESIGN_TEXT=$(cat "docs/plans/YYYY-MM-DD-<topic>-design.md")

   conclave consensus --mode=general-prompt \
     --prompt="Review this software design..." \
     --context="$DESIGN_TEXT"
   ```

3. Present results:
   - **High Priority issues**: "Consensus found X critical concerns. Recommend addressing before implementation."
   - **Medium Priority**: "Y moderate concerns identified. Review recommended."
   - **Consider only**: "Design validated. Z minor suggestions noted."

4. Handle response:
   - High Priority issues → Revise design, re-run consensus
   - User accepts concerns → Proceed to Implementation
   - User wants details → Show full consensus breakdown from `/tmp/consensus-*.md`

5. **For Autopilot Mode - Flag self-disagreement:**
   If validation consensus disagrees with a decision made during autopilot:
   ```
   Interesting: Validation consensus questions the PostgreSQL choice
   made earlier. They suggest considering SQLite for this scale.
   Want to revisit?
   ```

**Implementation (if continuing):**
- Ask: "Ready to set up for implementation?"
- Use conclave:using-git-worktrees to create isolated workspace
- Use conclave:writing-plans to create detailed implementation plan

## Key Principles

- **One question at a time** - Don't overwhelm with multiple questions
- **Multiple choice preferred** - Easier to answer than open-ended when possible
- **YAGNI ruthlessly** - Remove unnecessary features from all designs
- **Explore alternatives** - Always propose 2-3 approaches before settling
- **Incremental validation** - Present design in sections, validate each
- **Be flexible** - Go back and clarify when something doesn't make sense
