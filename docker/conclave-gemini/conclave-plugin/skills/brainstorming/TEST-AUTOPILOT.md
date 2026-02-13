# Brainstorming Autopilot Integration Tests

Manual test guide for the consensus autopilot feature in brainstorming.

## Prerequisites

- API keys configured: `ANTHROPIC_API_KEY`, `GEMINI_API_KEY`, `OPENAI_API_KEY`
- At least one API key working (graceful degradation)

## Test 1: Mode Selection

**Steps:**
1. Start a new Claude Code session
2. Say: "I want to add a dark mode feature to my app"
3. Wait for project context check

**Expected:**
- Claude offers two modes: Interactive and Consensus Autopilot
- Mode selection includes latency warning (5-10 minutes)

**Pass criteria:** Mode selection prompt appears with both options

---

## Test 2: Autopilot Execution

**Steps:**
1. Complete Test 1
2. Select option 2 (Consensus Autopilot)

**Expected:**
- Announcement: "Starting autopilot. I'll narrate each decision..."
- For each question:
  - Shows question being asked
  - Shows consensus recommendation with reasoning
  - Shows "Proceeding..."
- Multiple questions answered automatically

**Pass criteria:** At least 3 questions answered via consensus with narration

---

## Test 3: Interrupt and Override

**Steps:**
1. Start autopilot mode (Test 2)
2. While autopilot is running, send any message (e.g., "wait")

**Expected:**
- Autopilot pauses
- Shows last decision made
- Presents options: Override, Go back, Switch to interactive, Resume

**Pass criteria:** Interrupt recognized and options presented

---

## Test 4: Override a Decision

**Steps:**
1. Complete Test 3 (interrupt)
2. Override the last decision with a different choice

**Expected:**
- User's choice recorded
- Autopilot resumes with acknowledgment of override
- Continues to next question

**Pass criteria:** Override applied, autopilot continues

---

## Test 5: Go Back (Rollback)

**Steps:**
1. Let autopilot make at least 3 decisions
2. Interrupt and select "Go back"
3. Choose to go back to decision 1

**Expected:**
- Lists recent decisions
- After rollback selection:
  - Re-asks decision 1 (user answers or new consensus)
  - Re-runs ALL subsequent questions with fresh consensus
  - Does NOT reuse previous answers

**Pass criteria:** Rollback re-runs subsequent questions, not reuses old answers

---

## Test 6: Error Fallback

**Steps:**
1. Start autopilot mode
2. (If possible) Temporarily invalidate API keys, or wait for a timeout

**Expected:**
- On consensus failure: "Consensus unavailable for this question"
- Falls back to interactive mode for that question
- Offers to resume autopilot or stay interactive

**Pass criteria:** Graceful fallback to interactive on failure

---

## Test 7: Consensus Split

**Steps:**
1. Run autopilot on a question where agents might disagree
2. Observe behavior when no clear consensus

**Expected:**
- Shows each agent's recommendation
- "No strong consensus. Your call - which direction?"
- User decides, then autopilot resumes

**Pass criteria:** Split decision escalated to user

---

## Test 8: Decision Summary

**Steps:**
1. Complete full autopilot session (all questions answered)

**Expected:**
- Summary showing all decisions made:
  - Which were consensus
  - Which were user overrides
- Format: "Database: PostgreSQL (consensus)"

**Pass criteria:** Complete decision summary with sources shown

---

## Test 9: Self-Disagreement Flagging

**Steps:**
1. Complete autopilot session
2. Wait for final multi-agent validation

**Expected:**
- If validation consensus disagrees with an earlier autopilot decision:
  - Explicitly flags the disagreement
  - "Interesting: Validation consensus questions the X choice..."
  - Offers to revisit

**Pass criteria:** Self-disagreement flagged when it occurs

---

## Test 10: Session Checkpoint (Recovery)

**Steps:**
1. Start autopilot mode
2. Let it make 2-3 decisions
3. Close the session (browser close, ctrl+c, etc.)
4. Start new session, invoke brainstorming skill

**Expected:**
- Detects incomplete checkpoint
- "Found incomplete brainstorming session from X minutes ago"
- Offers to resume or start fresh
- If resume: continues from where left off

**Pass criteria:** Checkpoint detected and resume offered

---

## Test 11: Checkpoint Cleanup

**Steps:**
1. Complete full autopilot session through to saved design
2. Check `docs/plans/` directory

**Expected:**
- Design document saved
- No `.brainstorm-checkpoint-*.json` files remaining

**Pass criteria:** Checkpoint file deleted after successful completion

---

## Test 12: Interactive Mode (Control)

**Steps:**
1. Start brainstorming
2. Select option 1 (Interactive)

**Expected:**
- Normal brainstorming behavior
- Questions asked one at a time
- User answers each

**Pass criteria:** Interactive mode works as before

---

## Quick Smoke Test

For rapid validation, run this abbreviated test:

1. Start brainstorming: "Add user authentication"
2. Select Autopilot
3. Watch 2 decisions narrate
4. Interrupt with "stop"
5. Select "Resume"
6. Watch 1 more decision
7. Verify flow worked

**Pass:** All steps complete without errors

---

## Known Limitations

- Autopilot takes 30-60 seconds per question (API latency)
- Total session may take 5-10 minutes
- Requires working API keys for at least one agent
- Checkpoint only persists locally (not across machines)
