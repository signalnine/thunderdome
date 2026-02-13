# Consensus Autopilot for Brainstorming

## Overview

Add a "consensus take the wheel" autopilot mode to the brainstorming skill. Instead of asking the user each design question, multi-agent consensus (Claude, Gemini, Codex) answers them automatically while the user watches and can interrupt anytime.

## Mode Selection

At the start of brainstorming, after checking project context but before the first question:

```
I'll help design this feature. Two modes available:

1. **Interactive** - I ask questions, you answer, we iterate together
2. **Consensus Autopilot** - Multi-agent consensus (Claude, Gemini, Codex)
   answers design questions. You watch decisions narrate and can interrupt
   anytime to override.

Which mode?
```

If user picks Autopilot:
- Set internal flag tracking autopilot mode
- Announce: "Starting autopilot. I'll narrate each decision. Jump in anytime to override."
- Proceed to first question, routing to consensus instead of user

## Question Handling in Autopilot Mode

When a design question arises:

### 1. Format the Question for Consensus

```
Design decision needed: [question]

Context: [what we're building, decisions made so far]

Options I'm considering:
- Option A: [description]
- Option B: [description]
- Option C: [description]

You may suggest alternatives. Recommend one option with brief reasoning.
```

### 2. Call Consensus

```bash
consensus-synthesis.sh --mode=general-prompt \
  --prompt="$FORMATTED_QUESTION" \
  --context="$PROJECT_CONTEXT"
```

### 3. Narrate the Result

```
Q: What database technology?
→ Consensus recommends: PostgreSQL
  Reasoning: "Relational model fits the entity relationships,
  ACID compliance needed for financial data, team has experience."

Proceeding...
```

### 4. Brief Pause

Output the narration and continue. If user sends any message, that's an interrupt. Otherwise proceed to next question.

## Interrupt and Override

When user sends any message during autopilot:

### 1. Pause Immediately

Stop processing and acknowledge.

### 2. Present Options

```
Paused. What would you like to change?

Last decision: [database → PostgreSQL]

Options:
- Override this decision (tell me your preference)
- Go back further (redo earlier decisions)
- Switch to interactive mode (take over from here)
- Resume autopilot (continue as-is)
```

### 3. Handle Response

- **Override**: Record user's choice, resume autopilot from next question
- **Go back**: List recent decisions, let user pick restart point
- **Switch to interactive**: Disable autopilot mode, continue with normal Q&A
- **Resume**: Continue where paused

### 4. On Resume

```
Resuming autopilot with your override: [SQLite instead of PostgreSQL]

Next question...
```

## Final Design and Validation

After all questions answered:

### 1. Present Complete Design

In autopilot mode, present all design sections at once since user has been watching decisions happen.

### 2. Summarize Autopilot Decisions

```
Design complete. Consensus made 8 decisions:

- Database: PostgreSQL (consensus)
- API style: REST (consensus)
- Frontend: React (you overrode → Vue)
- Auth: JWT (consensus)
...

Review the full design below, then we'll run final validation.
```

### 3. Run Multi-Agent Validation

Same as current flow - consensus reviews the complete design for architectural flaws, over-engineering, missing requirements.

### 4. Flag Self-Disagreement

If validation consensus disagrees with a decision made during question-answering:

```
Interesting: Validation consensus questions the PostgreSQL choice
made earlier. They suggest considering SQLite for this scale.
Want to revisit?
```

## Execution Model

**Clarification:** Claude Code itself is the orchestration layer. Skills are instructions followed by an agentic loop that can:
- Call external tools (Bash for consensus-synthesis.sh)
- Output narration text
- Receive user interrupts as normal messages
- Maintain state across the conversation

The "autopilot loop" is simply Claude following skill instructions in sequence, calling consensus for each question, and outputting results. No external driver script needed - Claude Code IS the driver.

**The loop in practice:**
```
Claude: [outputs narration for Q1]
Claude: [calls consensus-synthesis.sh]
Claude: [outputs result, proceeds to Q2]
User: [sends message] ← interrupt detected naturally
Claude: [handles interrupt per skill instructions]
```

## Error Handling and Fallbacks

### Consensus API Failures

If consensus-synthesis.sh fails (timeout, API errors, <2 agents respond):

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

### Contradictory/Split Results

If consensus returns no clear recommendation (2-1 split with conflicting reasoning):

```
Consensus split on this question:
- Claude recommends PostgreSQL (relational model fits)
- Gemini recommends MongoDB (schema flexibility)
- Codex recommends PostgreSQL (team experience)

No strong consensus. Your call - which direction?
```

Then resume autopilot after user decides.

### Timeout Expectations

At mode selection, set expectations:

```
Note: Autopilot calls consensus for each design question (~30-60 seconds each).
Full design typically takes 5-10 minutes. You'll see progress throughout.
```

## State Management for "Go Back"

### Decision Tracking

Maintain explicit decision log during autopilot:

```
DECISION_LOG:
1. [Q: Target users?] → "B2B enterprise" (consensus)
2. [Q: Database?] → "PostgreSQL" (consensus)
3. [Q: API style?] → "GraphQL" (user override)
4. [Q: Auth method?] → "OAuth2 + JWT" (consensus)
```

### Go Back Implementation

When user requests "go back":

```
Recent decisions:
4. Auth method → OAuth2 + JWT (consensus)
3. API style → GraphQL (your override)
2. Database → PostgreSQL (consensus)
1. Target users → B2B enterprise (consensus)

Which decision to revisit? (number, or 'none' to resume)
```

On selection:
- Clear decisions from that point forward (they may have referenced the changed decision)
- Re-ask that question (user answers or new consensus)
- **Re-run ALL subsequent questions from scratch** with fresh consensus calls
- Do NOT reuse previous answers - later decisions may have depended on the changed one

Example: User rolls back Q2 (Database) from PostgreSQL to MongoDB:
```
Rolling back to Q2: Database

Q2: What database technology?
→ You chose: MongoDB

Now re-running subsequent questions with updated context...

Q3: What ORM/query layer?
→ Consensus recommends: Mongoose (was Prisma - changed due to MongoDB)

Q4: Auth method?
→ Consensus recommends: OAuth2 + JWT (unchanged)

Rollback complete. Continuing from Q5...
```

### Context Window Management

If decision log exceeds ~20 decisions:
- Summarize older decisions into compact form
- Keep recent 10 in full detail
- Include summary in consensus context

```
Earlier decisions (summarized): B2B SaaS targeting enterprise,
PostgreSQL + Redis stack, GraphQL API, OAuth2 auth...

Recent decisions:
[full detail for last 10]
```

## Session Persistence

### The Problem

Autopilot sessions take 5-10 minutes. Users may:
- Close browser accidentally
- Lose connection
- Need to step away
- Hit session timeout

Without persistence, all progress is lost.

### Checkpoint Strategy

After each consensus decision, save state to a checkpoint file:

```bash
# Save checkpoint after each decision
CHECKPOINT_FILE="docs/plans/.brainstorm-checkpoint-$(date +%Y%m%d-%H%M%S).json"
```

Checkpoint contains:
```json
{
  "session_id": "uuid",
  "topic": "user authentication feature",
  "mode": "autopilot",
  "created_at": "2025-01-18T10:30:00Z",
  "updated_at": "2025-01-18T10:35:00Z",
  "decisions": [
    {"q": "Target users?", "answer": "B2B enterprise", "source": "consensus"},
    {"q": "Database?", "answer": "PostgreSQL", "source": "consensus"}
  ],
  "current_question": 3,
  "project_context": "summary of codebase state"
}
```

### Recovery Flow

At brainstorming start, check for recent checkpoints:

```
Found incomplete brainstorming session from 10 minutes ago:
Topic: "user authentication feature"
Progress: 4/~12 questions answered (autopilot mode)

Options:
1. Resume from checkpoint
2. Start fresh (discards previous progress)
```

On resume:
- Load decision log
- Summarize progress: "Resuming. So far: B2B enterprise, PostgreSQL, GraphQL, OAuth2..."
- Continue from `current_question`

### Checkpoint Cleanup

- Delete checkpoint when design is complete and saved
- Auto-expire checkpoints older than 24 hours
- Keep only most recent checkpoint per topic

### Implementation Note

Checkpoints are JSON files in `docs/plans/` (gitignored pattern: `.brainstorm-checkpoint-*.json`). Simple file I/O, no database needed.

## Implementation

Changes to `skills/brainstorming/SKILL.md`:

1. **Add checkpoint check** - At start, look for incomplete sessions to resume
2. **Add mode selection** - New section after "Understanding the idea" context check
3. **Add autopilot flow** - New section describing the consensus question loop
4. **Add interrupt handling** - How to pause/resume/override
5. **Add checkpoint saving** - After each decision, persist state to JSON file
6. **Update "After the Design"** - Add decision summary for autopilot runs, cleanup checkpoint

No new scripts needed - uses existing `consensus-synthesis.sh` with `--mode=general-prompt`.

Gitignore addition:
```
docs/plans/.brainstorm-checkpoint-*.json
```

## Key Design Decisions

| Decision | Choice | Reasoning |
|----------|--------|-----------|
| When to offer mode | At start only | Simpler UX, clear commitment |
| Visibility | Narrated progress | User stays informed without blocking |
| Interrupt handling | Anytime override | Flexibility without complexity |
| Question format | Open-ended + suggested options | Leverages consensus creativity while providing guidance |
| Rollback strategy | Re-run all subsequent questions | Later decisions may depend on changed ones |
| Session persistence | JSON checkpoint files | Simple, no infrastructure, gitignored |
| Checkpoint frequency | After each decision | Minimal data loss on interruption |
| Error fallback | Interactive mode | Graceful degradation when consensus unavailable |
