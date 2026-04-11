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

**If `CONCLAVE_NON_INTERACTIVE=1`:** Skip mode selection, use Autopilot automatically. Announce: "Non-interactive mode: using Autopilot."

Otherwise, present the choice:

```
I'll help design this feature. Three modes available:

1. **Interactive** - I ask questions, you answer, we iterate together
2. **Autopilot** - I explore design decisions autonomously, you watch
   and can interrupt anytime to override
3. **Consensus Autopilot** - Multi-agent consensus (Claude, Gemini, Codex)
   answers design questions. Requires API keys. (~30-60s per question)

Which mode?
```

- If **Interactive**: Proceed with normal question flow (one at a time, user answers)
- If **Autopilot**: See "Autopilot Mode" section below
- If **Consensus Autopilot**: See "Consensus Autopilot Mode" section below

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

1. **Explore the project context** — read relevant code, docs, recent commits
2. **Propose 2-3 approaches** with trade-offs for this design question
3. **Evaluate and pick the best option** — narrate your reasoning:
   ```
   Q: What database technology?
   → Choosing: PostgreSQL
     Reasoning: Relational model fits the entity relationships,
     ACID compliance needed for financial data, team has experience.

   Proceeding...
   ```
4. **Save checkpoint** (see Checkpoint Saving below)
5. **Continue to next question** — if user sends any message, that's an interrupt

## Consensus Autopilot Mode

Same flow as Autopilot, but each design question goes to multi-agent consensus instead of the agent's own judgment. Requires API keys for Gemini and/or Codex.

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
5. **Continue to next question** — if user sends any message, that's an interrupt

**Error Handling:**

If consensus fails (timeout, API errors, <2 agents respond):
```
Consensus unavailable for this question. Falling back to interactive.
```
After user answers, offer: "Resume consensus autopilot for remaining questions, or stay interactive?"

If consensus returns split decision (no clear winner):
```
Consensus split on this question. Your call - which direction?
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

**For Autopilot/Consensus Autopilot - Summarize Decisions:**
```
Design complete. Made [N] decisions:

- Database: PostgreSQL
- API style: REST
- Frontend: Vue (you overrode)
- Auth: JWT
...

Review the full design below.
```

**Documentation:**
- Write the validated design to `docs/plans/YYYY-MM-DD-<topic>-design.md`
- Use elements-of-style:writing-clearly-and-concisely skill if available
- Commit the design document to git
- **Delete checkpoint file** after successful save

**Implementation (if continuing):**
- Ask: "Ready to set up for implementation?"
- Use conclave:using-git-worktrees to create isolated workspace
- Use conclave:writing-plans to create detailed implementation plan

**Completion Gate** (when brainstorming flows into implementation):

After all implementation work, before claiming done:
1. Run the full verification suite fresh (test + build + lint)
2. Read COMPLETE output. Count failures.
3. If ANY failure: fix and re-run. Do NOT proceed.
4. Commit: `git add -A && git commit -m '<description>'`
5. Review your diff: `git diff HEAD~1`
6. Look for: missing edge cases, incomplete implementations, dead code, debug artifacts
7. If issues found: fix, re-verify, re-commit
8. Only stop when verification passes AND diff review is clean

### Optional: Multi-Agent Design Validation

If you have API keys for multiple providers and want additional validation:

```bash
DESIGN_TEXT=$(cat "docs/plans/YYYY-MM-DD-<topic>-design.md")

conclave consensus --mode=general-prompt \
  --prompt="Review this software design for architectural flaws, missing requirements, over-engineering, and testing gaps. Rate each issue as STRONG/MODERATE/WEAK." \
  --context="$DESIGN_TEXT"
```

Present results and address High Priority issues before proceeding to implementation.

## Key Principles

- **One question at a time** - Don't overwhelm with multiple questions
- **Multiple choice preferred** - Easier to answer than open-ended when possible
- **YAGNI ruthlessly** - Remove unnecessary features from all designs
- **Explore alternatives** - Always propose 2-3 approaches before settling
- **Incremental validation** - Present design in sections, validate each
- **Be flexible** - Go back and clarify when something doesn't make sense
