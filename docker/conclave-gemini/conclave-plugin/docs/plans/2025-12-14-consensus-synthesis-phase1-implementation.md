# Consensus Synthesis Phase 1 Implementation Plan

**Date:** 2025-12-14
**Based on:** 2025-12-14-consensus-synthesis-phase1-design.md
**Goal:** Replace multi-consensus.sh with consensus-synthesis.sh

## Task Breakdown

### Task 1: Create consensus-synthesis.sh Core Structure

**Objective:** Create the main script with argument parsing and mode selection.

**Implementation Steps:**

1. Create `/home/gabe/superpowers/.worktrees/consensus-synthesis/skills/multi-agent-consensus/consensus-synthesis.sh`
2. Add shebang and set -euo pipefail
3. Implement argument parsing:
   - `--mode=code-review|general-prompt` (required)
   - Code review mode args: `--base-sha`, `--head-sha`, `--description`, `--plan-file` (optional)
   - General prompt mode args: `--prompt`, `--context` (optional)
4. Add validation: Error if required args missing for selected mode
5. Add usage/help function

**Test Coverage:**
- Test argument parsing for both modes
- Test validation of required arguments
- Test error handling for missing/invalid arguments

**Files Created:**
- `skills/multi-agent-consensus/consensus-synthesis.sh`

**Success Criteria:**
- Script accepts all required arguments without error
- Script rejects invalid argument combinations
- Usage message is clear and accurate

---

### Task 2: Implement Stage 1 - Parallel Agent Execution

**Objective:** Execute Claude, Gemini, and Codex in parallel with timeouts.

**Implementation Steps:**

1. Create helper functions to call each agent:
   - `run_claude()` - Call Claude API/CLI
   - `run_gemini()` - Call Gemini API/CLI
   - `run_codex()` - Call Codex API/CLI
2. Implement parallel execution with temp files:
   - Create temp files for each agent output
   - Launch agents in background with 30s timeout
   - Wait for all to complete
   - Read responses from temp files
3. Implement mode-specific prompt construction:
   - `build_code_review_prompt()` - Constructs Stage 1 code review prompt
   - `build_general_prompt_prompt()` - Constructs Stage 1 general prompt
4. Add context truncation (>10KB warning)
5. Track which agents succeeded/failed

**Test Coverage:**
- Test parallel execution with mocked agents
- Test timeout handling (30s)
- Test response collection from temp files
- Test context truncation
- Test partial success scenarios (3/3, 2/3, 1/3, 0/3)

**Success Criteria:**
- All three agents execute in parallel
- Timeouts work correctly
- Responses collected from successful agents
- Graceful handling of partial failures

---

### Task 3: Implement Stage 2 - Chairman Consensus

**Objective:** Synthesize Stage 1 responses into final consensus.

**Implementation Steps:**

1. Implement chairman selection with fallback:
   - Try Claude first
   - If Claude fails, try Gemini
   - If Gemini fails, try Codex
   - If all fail, abort
2. Implement mode-specific chairman prompt construction:
   - `build_code_review_chairman_prompt()` - Stage 2 code review synthesis
   - `build_general_chairman_prompt()` - Stage 2 general synthesis
3. Add 30s timeout for chairman
4. Parse and format chairman response

**Test Coverage:**
- Test chairman fallback chain (Claude → Gemini → Codex)
- Test chairman timeout handling
- Test both prompt modes
- Test all-chairman-failure scenario

**Success Criteria:**
- Chairman successfully synthesizes responses
- Fallback works when primary chairman fails
- Output matches expected format for each mode

---

### Task 4: Implement Output and Error Handling

**Objective:** Save results, display to user, handle all error cases.

**Implementation Steps:**

1. Implement output file creation:
   - Use `mktemp` to create `/tmp/consensus-XXXXXX.md`
   - Write full context: original prompt/diff, all Stage 1 responses, Stage 2 synthesis
2. Implement console output:
   - Progress indicators during Stage 1
   - Final consensus display
   - Note about temp file location
3. Implement error messages:
   - Stage 1: 0/3 agents succeeded
   - Stage 2: All chairmen failed
   - Invalid arguments
4. Add cleanup for temp files on exit

**Test Coverage:**
- Test output file creation and content
- Test console output format
- Test error message clarity
- Test temp file cleanup

**Success Criteria:**
- Output file contains all expected sections
- Console output is clear and helpful
- Error messages guide user to resolution
- No temp file leaks

---

### Task 5: Create Test Suite

**Objective:** Comprehensive test coverage for all functionality.

**Implementation Steps:**

1. Create `skills/multi-agent-consensus/test-consensus-synthesis.sh`
2. Implement unit tests:
   - Argument parsing
   - Mode validation
   - Context truncation
   - Prompt construction
   - Response parsing
   - Chairman fallback logic
3. Implement integration tests:
   - End-to-end code review mode (mocked agents)
   - End-to-end general prompt mode (mocked agents)
   - Partial success scenarios
   - All failure scenarios
4. Add test helpers:
   - Mock agent responses
   - Assertion functions
   - Test data generation

**Test Coverage:**
- All argument combinations
- All success/failure paths
- Both modes thoroughly tested
- Edge cases covered

**Success Criteria:**
- All tests pass
- Test output is clear
- Edge cases covered
- Easy to add new tests

---

## Verification Plan

After Task 5:
1. Run full test suite
2. Manual test with real agents (if available)
3. Compare output quality to multi-consensus.sh
4. Verify all modes work correctly

## Out of Scope for This Plan

Tasks 6-10 will cover:
- Integration with requesting-code-review skill
- Integration with brainstorming skill
- Updating documentation
- Removing old multi-consensus.sh
- Final regression testing

These will be in a separate implementation plan.
