---
name: executing-plans
description: Use when you have a written implementation plan to execute in a separate session with review checkpoints
---

# Executing Plans

## Overview

Load plan, review critically, execute tasks in batches, report for review between batches.

**Core principle:** Batch execution with checkpoints for architect review.

**Announce at start:** "I'm using the executing-plans skill to implement this plan."

## The Process

### Step 1: Load and Review Plan
1. Read plan file
2. Review critically - identify any questions or concerns about the plan
3. If concerns: Raise them with your human partner before starting
4. If no concerns: Create TodoWrite and proceed

### Step 2: Execute Batch
**Default: First 3 tasks**

For each task:
1. Mark as in_progress
2. Follow each step exactly (plan has bite-sized steps)
3. Run verifications as specified
4. Mark as completed

### Step 3: Consensus Review
After batch complete, run multi-agent consensus review:

```bash
# Auto-detects base SHA from origin/main
conclave auto-review "Completed batch: tasks N-M"
```

**If High Priority issues found:**
- Fix issues before reporting
- Re-run consensus after fixes

**If Medium Priority or Consider only:**
- Include in report for user awareness
- Can proceed to report

### Step 4: Report
When batch complete and consensus reviewed:
- Show what was implemented
- Show verification output
- Show consensus review summary (if any Medium Priority items)
- Say: "Ready for feedback."

### Step 5: Continue

**If `CONCLAVE_NON_INTERACTIVE=1`:** Skip waiting for feedback, proceed to next batch automatically. Announce: "Non-interactive mode: proceeding to next batch." Still fix High Priority consensus issues before continuing.

Otherwise, based on feedback:
- Apply changes if needed
- **Compact before next batch**: Run `/compact` to reclaim context:
  ```
  /compact Completed batch [N]: tasks [list]. Consensus: [summary]. Feedback applied: [changes]. Remaining tasks: [list]. Next batch: tasks [list].
  ```
- Execute next batch
- Repeat Steps 2-5 until complete

### Step 6: Complete Development

After all tasks complete and verified:
- Announce: "I'm using the finishing-a-development-branch skill to complete this work."
- **REQUIRED SUB-SKILL:** Use conclave:finishing-a-development-branch
- Follow that skill to verify tests, present options, execute choice

## When to Stop and Ask for Help

**STOP executing immediately when:**
- Hit a blocker mid-batch (missing dependency, test fails, instruction unclear)
- Plan has critical gaps preventing starting
- You don't understand an instruction
- Verification fails repeatedly

**Ask for clarification rather than guessing.**

## When to Revisit Earlier Steps

**Return to Review (Step 1) when:**
- Partner updates the plan based on your feedback
- Fundamental approach needs rethinking

**Don't force through blockers** - stop and ask.

## Context Management

**Compact between batches** to prevent context exhaustion:

- **After each batch report** (Step 4 complete, before Step 5): Best time to compact — user feedback creates a natural checkpoint
- **Before final branch completion** (Step 6): Compact with summary of all completed work

**Why:** Each batch generates code output, test results, and consensus reviews. Without compaction, later batches run in degraded context and risk losing important details.

## Remember
- Review plan critically first
- Follow plan steps exactly
- Don't skip verifications
- Run consensus review after each batch
- Fix High Priority consensus issues before reporting
- Reference skills when plan says to
- Between batches: compact context, then report and wait
- Stop when blocked, don't guess
- Never start implementation on main/master branch without explicit user consent

## Integration

**Required workflow skills:**
- **conclave:using-git-worktrees** - REQUIRED: Set up isolated workspace before starting
- **conclave:writing-plans** - Creates the plan this skill executes
- **conclave:finishing-a-development-branch** - Complete development after all tasks
