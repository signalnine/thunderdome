---
name: multi-agent-consensus
description: Use when you need diverse AI perspectives via two-stage synthesis (Claude/Gemini/Codex)
---

# Multi-Agent Consensus

## Overview

Provides two-stage consensus synthesis from Claude, Gemini, and Codex:
1. **Stage 1:** Independent parallel analysis from each agent
2. **Stage 2:** Chairman agent synthesizes final consensus

Groups responses by agreement level and explicitly highlights disagreements.

## When to Use

Use when you need diverse AI perspectives to reduce bias and blind spots:
- Design validation (brainstorming)
- Code review (requesting-code-review)
- Root cause analysis (debugging)
- Verification checks (before completion)

## Interface

**Code review mode:**
```bash
conclave consensus --mode=code-review \
  --base-sha="$BASE" --head-sha="$HEAD" \
  --plan-file="$PLAN" --description="$DESC"
```

**General prompt mode:**
```bash
conclave consensus --mode=general-prompt \
  --prompt="Your question here" \
  --context="Optional background info"
```

## Output

Three-tier consensus report:
- **High Priority** - Multiple reviewers agree
- **Medium Priority** - Single reviewer, significant issue
- **Consider** - Suggestions from any reviewer

Consensus saved to `/tmp/consensus-XXXXXX.md` with full context and all Stage 1 analyses.

## How It Works

**Stage 1 (60s timeout per agent, configurable):**
- Claude, Gemini, Codex analyze independently in parallel
- Each provides structured feedback
- Results collected from all successful agents

**Stage 2 (60s timeout, configurable):**
- Chairman (Claude → Gemini → Codex fallback) synthesizes consensus
- Groups issues by agreement
- Highlights disagreements explicitly
- Produces final three-tier report

## Configuration

**Timeout Configuration:**
```bash
# Via environment variables
export CONSENSUS_STAGE1_TIMEOUT=90
export CONSENSUS_STAGE2_TIMEOUT=90

# Via CLI flags
conclave consensus --mode=general-prompt \
  --prompt="Your question" \
  --stage1-timeout=90 \
  --stage2-timeout=90
```

**Default timeouts:** 60 seconds per stage
- Covers P95-P99 API latency scenarios
- Adjust higher for very complex prompts or slow networks
- Adjust lower for simple prompts when speed is critical
