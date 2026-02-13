# Multi-Agent Consensus Framework Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Create reusable multi-agent consensus infrastructure that any superpowers skill can leverage for diverse AI perspectives

**Architecture:** Extract consensus logic from `requesting-code-review/multi-review.sh` into new `multi-agent-consensus` skill with mode-based interface (code-review vs general-prompt). Shared consensus algorithm handles both modes.

**Tech Stack:** Bash 4.0+, bc for calculations, existing Claude/Gemini/Codex integration patterns

---

## Phase 1: Foundation

### Task 1: Create Skill Directory Structure

**Files:**
- Create: `skills/multi-agent-consensus/`
- Create: `skills/multi-agent-consensus/SKILL.md`
- Create: `skills/multi-agent-consensus/README.md`
- Create: `skills/multi-agent-consensus/multi-consensus.sh`
- Create: `skills/multi-agent-consensus/test-multi-consensus.sh`

**Step 1: Create directory**

```bash
mkdir -p skills/multi-agent-consensus
```

**Step 2: Create SKILL.md stub**

```markdown
---
name: multi-agent-consensus
description: Reusable multi-agent consensus infrastructure for any skill needing diverse AI perspectives (Claude/Gemini/Codex)
---

# Multi-Agent Consensus

## Overview

Provides reusable infrastructure for getting consensus from Claude, Gemini, and Codex on any prompt or task. Groups responses by agreement level (all agree, majority, single reviewer).

## When to Use

Use when you need diverse AI perspectives to reduce bias and blind spots:
- Design validation (brainstorming)
- Code review (requesting-code-review)
- Root cause analysis (debugging)
- Verification checks (before completion)

## Interface

**Code review mode:**
```bash
multi-consensus.sh --mode=code-review \
  --base-sha="$BASE" --head-sha="$HEAD" \
  --plan-file="$PLAN" --description="$DESC"
```

**General prompt mode:**
```bash
multi-consensus.sh --mode=general-prompt \
  --prompt="Your question here" \
  --context="Optional background info"
```

## Output

Three-tier consensus report:
- **High Priority** - All reviewers agree
- **Medium Priority** - Majority (2/3) flagged
- **Consider** - Single reviewer mentioned

## Configuration

- `SIMILARITY_THRESHOLD=60` - Word overlap threshold for issue matching (default 60%)
```

**Step 3: Create README.md stub**

```markdown
# Multi-Agent Consensus Framework

Reusable infrastructure for multi-agent consensus. Any skill can invoke Claude, Gemini, and Codex to get diverse perspectives on prompts, designs, code, or decisions.

## Architecture

See: `docs/plans/2025-12-13-multi-agent-consensus-framework-design.md`

## Usage

From any skill:

\`\`\`bash
../multi-agent-consensus/multi-consensus.sh --mode=general-prompt \
  --prompt="What could go wrong?" \
  --context="$BACKGROUND"
\`\`\`

Output: Markdown consensus report grouped by agreement level.
```

**Step 4: Create executable script stub**

```bash
#!/usr/bin/env bash
set -euo pipefail

# Multi-agent consensus framework
# Provides reusable infrastructure for Claude/Gemini/Codex consensus

echo "multi-consensus.sh stub"
exit 1
```

Make executable:
```bash
chmod +x skills/multi-agent-consensus/multi-consensus.sh
```

**Step 5: Create test suite stub**

```bash
#!/usr/bin/env bash
set -e

echo "Testing multi-consensus.sh..."
echo "Tests not yet implemented"
exit 1
```

Make executable:
```bash
chmod +x skills/multi-agent-consensus/test-multi-consensus.sh
```

**Step 6: Commit**

```bash
git add skills/multi-agent-consensus/
git commit -m "feat: create multi-agent-consensus skill structure"
```

### Task 2: Copy and Rename Base Script

**Files:**
- Copy: `skills/requesting-code-review/multi-review.sh` → `skills/multi-agent-consensus/multi-consensus.sh`

**Step 1: Copy script**

```bash
cp skills/requesting-code-review/multi-review.sh skills/multi-agent-consensus/multi-consensus.sh
```

**Step 2: Update header comment**

Edit `skills/multi-agent-consensus/multi-consensus.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail

# Multi-agent consensus framework
# Provides reusable infrastructure for Claude, Gemini, and Codex consensus
# Supports multiple modes: code-review, general-prompt
```

**Step 3: Verify script is executable**

```bash
chmod +x skills/multi-agent-consensus/multi-consensus.sh
```

**Step 4: Test current functionality**

```bash
# Should show usage and exit
skills/multi-agent-consensus/multi-consensus.sh || echo "Expected failure - not yet refactored"
```

**Step 5: Commit**

```bash
git add skills/multi-agent-consensus/multi-consensus.sh
git commit -m "feat: copy multi-review.sh as base for multi-consensus"
```

## Phase 2: Mode-Based Architecture

### Task 3: Add Mode Argument Parsing

**Files:**
- Modify: `skills/multi-agent-consensus/multi-consensus.sh:24-54`

**Step 1: Write test for mode validation**

Edit `skills/multi-agent-consensus/test-multi-consensus.sh`:

```bash
#!/usr/bin/env bash
set -e

SCRIPT="$(dirname "$0")/multi-consensus.sh"

echo "Testing multi-consensus.sh..."

# Test: Missing --mode flag
if $SCRIPT 2>&1 | grep -q "Error.*--mode"; then
    echo "✓ Requires --mode flag"
else
    echo "✗ Should require --mode flag"
    exit 1
fi

# Test: Invalid mode value
if $SCRIPT --mode=invalid 2>&1 | grep -q "Error.*Invalid mode"; then
    echo "✓ Rejects invalid mode"
else
    echo "✗ Should reject invalid mode"
    exit 1
fi

# Test: Valid mode without required args
if $SCRIPT --mode=code-review 2>&1 | grep -q "Error.*base-sha"; then
    echo "✓ Code review mode requires --base-sha"
else
    echo "✗ Code review mode should require --base-sha"
    exit 1
fi

if $SCRIPT --mode=general-prompt 2>&1 | grep -q "Error.*prompt"; then
    echo "✓ General prompt mode requires --prompt"
else
    echo "✗ General prompt mode should require --prompt"
    exit 1
fi

echo "All tests passed!"
```

**Step 2: Run test to verify it fails**

```bash
./skills/multi-agent-consensus/test-multi-consensus.sh
```

Expected: FAIL (functionality not implemented yet)

**Step 3: Implement mode argument parsing**

Replace `show_usage()` and argument parsing in `multi-consensus.sh`:

```bash
show_usage() {
    cat <<EOF
Usage: $0 --mode=MODE [mode-specific arguments]

Modes:
  code-review        Review git changes (requires --base-sha, --head-sha)
  general-prompt     Multi-agent consensus on prompt (requires --prompt)

Code Review Mode:
  $0 --mode=code-review --base-sha=SHA --head-sha=SHA [--plan-file=FILE] [--description=TEXT]

General Prompt Mode:
  $0 --mode=general-prompt --prompt=TEXT [--context=TEXT]

Environment:
  SIMILARITY_THRESHOLD    Word overlap threshold (default: 60)

Examples:
  $0 --mode=code-review --base-sha=abc123 --head-sha=def456 --description="Add auth"
  $0 --mode=general-prompt --prompt="What could go wrong?" --context="Background info"
EOF
}

# Parse arguments
MODE=""
BASE_SHA=""
HEAD_SHA=""
PLAN_FILE="-"
DESCRIPTION=""
PROMPT=""
CONTEXT=""

while [[ $# -gt 0 ]]; do
    case $1 in
        --mode=*)
            MODE="${1#*=}"
            shift
            ;;
        --base-sha=*)
            BASE_SHA="${1#*=}"
            shift
            ;;
        --head-sha=*)
            HEAD_SHA="${1#*=}"
            shift
            ;;
        --plan-file=*)
            PLAN_FILE="${1#*=}"
            shift
            ;;
        --description=*)
            DESCRIPTION="${1#*=}"
            shift
            ;;
        --prompt=*)
            PROMPT="${1#*=}"
            shift
            ;;
        --context=*)
            CONTEXT="${1#*=}"
            shift
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        *)
            echo "Error: Unknown argument: $1" >&2
            show_usage
            exit 1
            ;;
    esac
done

# Validate mode is provided
if [ -z "$MODE" ]; then
    echo "Error: --mode is required" >&2
    show_usage
    exit 1
fi

# Validate mode value
case "$MODE" in
    code-review|general-prompt)
        # Valid modes
        ;;
    *)
        echo "Error: Invalid mode '$MODE'. Must be 'code-review' or 'general-prompt'" >&2
        show_usage
        exit 1
        ;;
esac

# Validate mode-specific required arguments
if [ "$MODE" = "code-review" ]; then
    if [ -z "$BASE_SHA" ]; then
        echo "Error: --base-sha is required for code-review mode" >&2
        show_usage
        exit 1
    fi
    if [ -z "$HEAD_SHA" ]; then
        echo "Error: --head-sha is required for code-review mode" >&2
        show_usage
        exit 1
    fi
elif [ "$MODE" = "general-prompt" ]; then
    if [ -z "$PROMPT" ]; then
        echo "Error: --prompt is required for general-prompt mode" >&2
        show_usage
        exit 1
    fi
fi
```

**Step 4: Run test to verify it passes**

```bash
./skills/multi-agent-consensus/test-multi-consensus.sh
```

Expected: PASS (all 4 tests)

**Step 5: Commit**

```bash
git add skills/multi-agent-consensus/multi-consensus.sh skills/multi-agent-consensus/test-multi-consensus.sh
git commit -m "feat: add mode-based argument parsing with validation"
```

### Task 4: Add Mode-Specific Context Preparation

**Files:**
- Modify: `skills/multi-agent-consensus/multi-consensus.sh` (after argument parsing, before reviewer functions)

**Step 1: Write test for context preparation**

Add to `test-multi-consensus.sh`:

```bash
# Test: Code review mode prepares git context
test_code_review_context() {
    # Create temporary git repo for testing
    local test_dir=$(mktemp -d)
    cd "$test_dir"
    git init -q
    git config user.email "test@test.com"
    git config user.name "Test"
    echo "original" > file.txt
    git add file.txt
    git commit -q -m "initial"
    local base_sha=$(git rev-parse HEAD)
    echo "modified" > file.txt
    git add file.txt
    git commit -q -m "change"
    local head_sha=$(git rev-parse HEAD)

    # Run with --dry-run to test context preparation
    local output=$("$OLDPWD/$SCRIPT" --mode=code-review --base-sha="$base_sha" --head-sha="$head_sha" --description="test" --dry-run 2>&1 || true)

    cd "$OLDPWD"
    rm -rf "$test_dir"

    if echo "$output" | grep -q "file.txt"; then
        echo "✓ Code review mode extracts file changes"
        return 0
    else
        echo "✗ Code review mode should extract file changes"
        return 1
    fi
}

# Test: General prompt mode formats prompt
test_general_prompt_context() {
    local output=$("$SCRIPT" --mode=general-prompt --prompt="test question" --context="background" --dry-run 2>&1 || true)

    if echo "$output" | grep -q "test question"; then
        echo "✓ General prompt mode includes prompt"
        return 0
    else
        echo "✗ General prompt mode should include prompt"
        return 1
    fi
}

# Run new tests
test_code_review_context
test_general_prompt_context
```

**Step 2: Run test to verify it fails**

```bash
./skills/multi-agent-consensus/test-multi-consensus.sh
```

Expected: FAIL (--dry-run not implemented yet)

**Step 3: Implement context preparation functions**

Add after argument validation in `multi-consensus.sh`:

```bash
# === Context Preparation Functions ===

# Prepare context for code review mode
prepare_code_review_context() {
    local base_sha="$1"
    local head_sha="$2"
    local plan_file="$3"
    local description="$4"

    # Check if commits are the same
    if [ "$base_sha" = "$head_sha" ]; then
        echo "Error: BASE_SHA and HEAD_SHA are the same ($base_sha)" >&2
        echo "Nothing to review" >&2
        exit 1
    fi

    # Get list of modified files
    MODIFIED_FILES=$(git diff --name-only "$base_sha" "$head_sha" 2>/dev/null || echo "")

    if [ -z "$MODIFIED_FILES" ]; then
        MODIFIED_FILES_COUNT=0
    else
        MODIFIED_FILES_COUNT=$(echo "$MODIFIED_FILES" | wc -l | tr -d ' ')
    fi

    # Get full diff
    FULL_DIFF=$(git diff "$base_sha" "$head_sha" 2>/dev/null || echo "")

    if [ -z "$FULL_DIFF" ]; then
        echo "Warning: No changes between $base_sha and $head_sha" >&2
    fi

    # Load plan content if provided
    PLAN_CONTENT=""
    if [ "$plan_file" != "-" ] && [ -f "$plan_file" ]; then
        PLAN_CONTENT=$(cat "$plan_file")
    fi

    # Build full context
    FULL_CONTEXT="# Code Review Context

**Description:** $description

**Commits:** $base_sha..$head_sha

**Files Changed:** $MODIFIED_FILES_COUNT

**Modified Files:**
$MODIFIED_FILES

**Plan/Requirements:**
${PLAN_CONTENT:-None provided}

**Full Diff:**
\`\`\`diff
$FULL_DIFF
\`\`\`
"
}

# Prepare context for general prompt mode
prepare_general_prompt_context() {
    local prompt="$1"
    local context="$2"

    # Build full context
    if [ -n "$context" ]; then
        FULL_CONTEXT="# Context

$context

# Prompt

$prompt"
    else
        FULL_CONTEXT="$prompt"
    fi
}

# Prepare context based on mode
if [ "$MODE" = "code-review" ]; then
    prepare_code_review_context "$BASE_SHA" "$HEAD_SHA" "$PLAN_FILE" "$DESCRIPTION"
elif [ "$MODE" = "general-prompt" ]; then
    prepare_general_prompt_context "$PROMPT" "$CONTEXT"
fi

# Exit early if --dry-run (for testing)
if [ "${DRY_RUN:-false}" = "true" ]; then
    echo "DRY RUN MODE"
    echo "$FULL_CONTEXT"
    exit 0
fi
```

**Step 4: Run test to verify it passes**

```bash
./skills/multi-agent-consensus/test-multi-consensus.sh
```

Expected: PASS

**Step 5: Commit**

```bash
git add skills/multi-agent-consensus/multi-consensus.sh skills/multi-agent-consensus/test-multi-consensus.sh
git commit -m "feat: add mode-specific context preparation"
```

## Phase 3: General Prompt Mode

### Task 5: Add Severity Label Configuration

**Files:**
- Modify: `skills/multi-agent-consensus/multi-consensus.sh` (add function after context preparation)

**Step 1: Write test (manual verification)**

This will be verified manually in integration testing.

**Step 2: Implement get_severity_labels function**

Add after context preparation functions:

```bash
# === Severity Label Functions ===

# Get severity labels based on mode
get_severity_labels() {
    local mode="$1"

    case "$mode" in
        code-review)
            echo "CRITICAL IMPORTANT SUGGESTION"
            ;;
        general-prompt)
            echo "STRONG MODERATE WEAK"
            ;;
        *)
            echo "Error: Unknown mode for severity labels: $mode" >&2
            exit 1
            ;;
    esac
}

# Get severity labels for current mode
SEVERITY_LABELS=$(get_severity_labels "$MODE")
SEVERITY_HIGH=$(echo "$SEVERITY_LABELS" | cut -d' ' -f1)
SEVERITY_MED=$(echo "$SEVERITY_LABELS" | cut -d' ' -f2)
SEVERITY_LOW=$(echo "$SEVERITY_LABELS" | cut -d' ' -f3)
```

**Step 3: Update reviewer prompts to use dynamic labels**

Find the `launch_gemini_review` and `launch_codex_review` functions. Update the prompts to use the severity labels:

In `launch_gemini_review()`, replace the hardcoded format section:

```bash
    local prompt="You are a senior code reviewer. Review the following and provide structured feedback.

$context

Please provide your review in the following format:

## ${SEVERITY_HIGH} Issues
- [list ${SEVERITY_HIGH} issues here, or write 'None']

## ${SEVERITY_MED} Issues
- [list ${SEVERITY_MED} issues here, or write 'None']

## ${SEVERITY_LOW}
- [list ${SEVERITY_LOW} here, or write 'None']

Each issue should be on its own line starting with a dash (-).
Use format: ${SEVERITY_HIGH}|description or ${SEVERITY_MED}|description or ${SEVERITY_LOW}|description
"
```

Do the same for `launch_codex_review()`.

**Step 4: Test with --dry-run**

```bash
skills/multi-agent-consensus/multi-consensus.sh --mode=general-prompt --prompt="test" --dry-run | grep -q "STRONG"
echo "✓ General prompt mode uses STRONG/MODERATE/WEAK labels"
```

**Step 5: Commit**

```bash
git add skills/multi-agent-consensus/multi-consensus.sh
git commit -m "feat: add mode-specific severity labels"
```

## Phase 4: Integration and Testing

### Task 6: Update Requesting-Code-Review Integration

**Files:**
- Modify: `skills/requesting-code-review/SKILL.md` (update multi-review.sh call)

**Step 1: Read current SKILL.md**

Check the current integration point in `skills/requesting-code-review/SKILL.md`.

**Step 2: Update call to multi-consensus.sh**

Find the section that calls multi-review.sh and update it:

```markdown
**3. Run multi-agent consensus:**

\`\`\`bash
../multi-agent-consensus/multi-consensus.sh --mode=code-review \
  --base-sha="$BASE_SHA" \
  --head-sha="$HEAD_SHA" \
  --plan-file="$PLAN_FILE" \
  --description="$DESCRIPTION"
\`\`\`
```

**Step 3: Add note about migration**

Add a note in the README:

```markdown
## Migration Note

The multi-review.sh script has been moved to `skills/multi-agent-consensus/multi-consensus.sh`.
The requesting-code-review skill now calls the new location with `--mode=code-review`.

Old location: `skills/requesting-code-review/multi-review.sh` (deprecated)
New location: `skills/multi-agent-consensus/multi-consensus.sh --mode=code-review`
```

**Step 4: Test code review mode**

```bash
# Get a real commit range
BASE=$(git rev-parse HEAD~1)
HEAD=$(git rev-parse HEAD)

# Test the new script
skills/multi-agent-consensus/multi-consensus.sh --mode=code-review \
  --base-sha="$BASE" \
  --head-sha="$HEAD" \
  --description="Test review"
```

Expected: Should produce consensus report (or fail gracefully if Gemini/Codex unavailable)

**Step 5: Commit**

```bash
git add skills/requesting-code-review/SKILL.md
git commit -m "docs: update requesting-code-review to use multi-consensus.sh"
```

### Task 7: Add Comprehensive Test Suite

**Files:**
- Modify: `skills/multi-agent-consensus/test-multi-consensus.sh`

**Step 1: Expand test suite**

Replace test file with comprehensive tests:

```bash
#!/usr/bin/env bash
set -e

SCRIPT="$(dirname "$0")/multi-consensus.sh"

echo "Testing multi-consensus.sh..."

# Test: Missing --mode flag
if $SCRIPT 2>&1 | grep -q "Error.*--mode"; then
    echo "✓ Requires --mode flag"
else
    echo "✗ Should require --mode flag"
    exit 1
fi

# Test: Invalid mode value
if $SCRIPT --mode=invalid 2>&1 | grep -q "Error.*Invalid mode"; then
    echo "✓ Rejects invalid mode"
else
    echo "✗ Should reject invalid mode"
    exit 1
fi

# Test: Code review mode missing --base-sha
if $SCRIPT --mode=code-review 2>&1 | grep -q "Error.*base-sha"; then
    echo "✓ Code review mode requires --base-sha"
else
    echo "✗ Code review mode should require --base-sha"
    exit 1
fi

# Test: General prompt mode missing --prompt
if $SCRIPT --mode=general-prompt 2>&1 | grep -q "Error.*prompt"; then
    echo "✓ General prompt mode requires --prompt"
else
    echo "✗ General prompt mode should require --prompt"
    exit 1
fi

# Test: Code review mode extracts git context
test_dir=$(mktemp -d)
cd "$test_dir"
git init -q
git config user.email "test@test.com"
git config user.name "Test"
echo "original" > file.txt
git add file.txt
git commit -q -m "initial"
base_sha=$(git rev-parse HEAD)
echo "modified" > file.txt
git add file.txt
git commit -q -m "change"
head_sha=$(git rev-parse HEAD)

output=$("$OLDPWD/$SCRIPT" --mode=code-review --base-sha="$base_sha" --head-sha="$head_sha" --description="test" --dry-run 2>&1 || true)

cd "$OLDPWD"
rm -rf "$test_dir"

if echo "$output" | grep -q "file.txt"; then
    echo "✓ Code review mode extracts git context"
else
    echo "✗ Code review mode should extract git context"
    exit 1
fi

# Test: General prompt mode includes prompt
output=$("$SCRIPT" --mode=general-prompt --prompt="test question" --context="background" --dry-run 2>&1 || true)

if echo "$output" | grep -q "test question"; then
    echo "✓ General prompt mode includes prompt"
else
    echo "✗ General prompt mode should include prompt"
    exit 1
fi

# Test: Context parameter passes through
if echo "$output" | grep -q "background"; then
    echo "✓ Context parameter passes through"
else
    echo "✗ Context parameter should pass through"
    exit 1
fi

# Test: Severity labels based on mode
output_cr=$("$SCRIPT" --mode=code-review --base-sha="HEAD~1" --head-sha="HEAD" --description="test" --dry-run 2>&1 || true)
output_gp=$("$SCRIPT" --mode=general-prompt --prompt="test" --dry-run 2>&1 || true)

# Note: Full verification requires running actual reviewers, tested in integration

echo "All tests passed!"
```

**Step 2: Run tests**

```bash
./skills/multi-agent-consensus/test-multi-consensus.sh
```

Expected: All tests pass

**Step 3: Add to repository test suite**

Check if there's a main test runner and add this test.

**Step 4: Commit**

```bash
git add skills/multi-agent-consensus/test-multi-consensus.sh
git commit -m "test: add comprehensive test suite for multi-consensus"
```

### Task 8: Write Complete Documentation

**Files:**
- Modify: `skills/multi-agent-consensus/README.md`
- Modify: `skills/multi-agent-consensus/SKILL.md`

**Step 1: Complete README.md**

```markdown
# Multi-Agent Consensus Framework

Reusable infrastructure for multi-agent consensus. Any skill can invoke Claude, Gemini, and Codex to get diverse perspectives on prompts, designs, code, or decisions.

## Purpose

Different AI models have different strengths and weaknesses. Single agents may miss issues, exhibit biases, or have blind spots. This framework provides consensus from multiple agents, grouped by agreement level.

## Architecture

**Design:** `docs/plans/2025-12-13-multi-agent-consensus-framework-design.md`

**Key components:**
- Mode-based interface (code-review vs general-prompt)
- Shared consensus algorithm (word overlap + file matching)
- Three-tier output (High/Medium/Consider priority)
- Graceful degradation (works with 1, 2, or 3 reviewers)

## Usage

### Code Review Mode

```bash
skills/multi-agent-consensus/multi-consensus.sh --mode=code-review \
  --base-sha="abc123" \
  --head-sha="def456" \
  --plan-file="docs/plans/feature.md" \
  --description="Add authentication"
```

### General Prompt Mode

```bash
skills/multi-agent-consensus/multi-consensus.sh --mode=general-prompt \
  --prompt="What could go wrong with this design?" \
  --context="$(cat design.md)"
```

## Output Format

Three-tier consensus report:

```markdown
## High Priority - All Reviewers Agree
- [SEVERITY] description
  - Claude: "issue text"
  - Gemini: "issue text"
  - Codex: "issue text"

## Medium Priority - Majority Flagged (2/3)
- [SEVERITY] description
  - Claude: "issue text"
  - Gemini: "issue text"

## Consider - Single Reviewer Mentioned
- [SEVERITY] description
  - Codex: "issue text"
```

## Configuration

- `SIMILARITY_THRESHOLD=60` - Word overlap threshold for matching issues (default 60%)

## Dependencies

- Bash 4.0+
- git
- bc (for calculations)
- gemini CLI (optional, for Gemini reviews)
- Claude Code (optional, for Claude/Codex reviews)

## Integration Examples

**Brainstorming (design validation):**

```bash
DESIGN=$(cat docs/plans/2025-12-13-feature-design.md)

skills/multi-agent-consensus/multi-consensus.sh --mode=general-prompt \
  --prompt="Review this design for flaws, over-engineering, or missing requirements. Rate as STRONG/MODERATE/WEAK." \
  --context="$DESIGN"
```

**Systematic Debugging (root cause analysis):**

```bash
skills/multi-agent-consensus/multi-consensus.sh --mode=general-prompt \
  --prompt="What could cause this error? Analyze root causes." \
  --context="Error log: $ERROR_LOG"
```

## Testing

```bash
./skills/multi-agent-consensus/test-multi-consensus.sh
```

## Migration from multi-review.sh

Old code review calls:
```bash
skills/requesting-code-review/multi-review.sh "$BASE" "$HEAD" "$PLAN" "$DESC"
```

New code review calls:
```bash
skills/multi-agent-consensus/multi-consensus.sh --mode=code-review \
  --base-sha="$BASE" --head-sha="$HEAD" \
  --plan-file="$PLAN" --description="$DESC"
```
```

**Step 2: Complete SKILL.md**

(Already created in Task 1, verify it's complete)

**Step 3: Commit**

```bash
git add skills/multi-agent-consensus/README.md skills/multi-agent-consensus/SKILL.md
git commit -m "docs: complete multi-agent-consensus documentation"
```

## Phase 5: Brainstorming Integration

### Task 9: Integrate into Brainstorming Skill

**Files:**
- Modify: `skills/brainstorming/SKILL.md` (add multi-agent validation step)

**Step 1: Read current brainstorming skill**

Check `skills/brainstorming/SKILL.md` to find the right integration point.

**Step 2: Add multi-agent validation step**

Add after "After the Design" section:

```markdown
**Multi-Agent Design Validation (Optional):**

After the user validates the complete design, offer multi-agent review:

"Would you like multi-agent validation of this design? Claude, Gemini, and Codex will review for architectural flaws, over-engineering, and missing requirements."

If yes:
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

   ../multi-agent-consensus/multi-consensus.sh --mode=general-prompt \
     --prompt="Review this software design..." \
     --context="$DESIGN_TEXT"
   ```

3. Present results:
   "Multi-agent validation found X High Priority issues, Y Medium Priority, Z Consider.
   Would you like to address the High Priority issues before proceeding?"

4. User decides: revise, proceed, or ask questions
```

**Step 3: Test integration manually**

Will be tested in end-to-end validation.

**Step 4: Commit**

```bash
git add skills/brainstorming/SKILL.md
git commit -m "feat: integrate multi-agent validation into brainstorming"
```

## Phase 6: End-to-End Validation

### Task 10: Validate Code Review Mode

**Files:**
- Test: Existing code review functionality

**Step 1: Get real commit range**

```bash
BASE=$(git rev-parse HEAD~3)
HEAD=$(git rev-parse HEAD)
```

**Step 2: Run old script (baseline)**

```bash
skills/requesting-code-review/multi-review.sh "$BASE" "$HEAD" "-" "Test baseline"
```

Save output to `/tmp/baseline-review.txt`

**Step 3: Run new script**

```bash
skills/multi-agent-consensus/multi-consensus.sh --mode=code-review \
  --base-sha="$BASE" \
  --head-sha="$HEAD" \
  --description="Test new implementation"
```

Save output to `/tmp/new-review.txt`

**Step 4: Compare outputs**

```bash
# Check both have same structure
grep -c "High Priority" /tmp/baseline-review.txt
grep -c "High Priority" /tmp/new-review.txt

# Both should have consensus sections
echo "✓ Code review mode produces same output format"
```

**Step 5: Document results**

Note: This is manual verification, document in commit message.

**Step 6: Commit verification notes**

```bash
git commit --allow-empty -m "test: verify code review mode matches original behavior"
```

### Task 11: Validate General Prompt Mode

**Files:**
- Test: New general-prompt mode

**Step 1: Create test design document**

```bash
cat > /tmp/test-design.md <<'EOF'
# Test Feature Design

## Architecture
- Use Redis for caching
- PostgreSQL for persistent storage
- REST API with Express.js

## Components
- API Gateway
- Cache Layer
- Database Layer
EOF
```

**Step 2: Run general-prompt mode**

```bash
DESIGN=$(cat /tmp/test-design.md)

skills/multi-agent-consensus/multi-consensus.sh --mode=general-prompt \
  --prompt="Review this design for architectural flaws, over-engineering, or missing requirements. Rate as STRONG/MODERATE/WEAK." \
  --context="$DESIGN"
```

**Step 3: Verify output structure**

Check for:
- Three-tier sections (High/Medium/Consider)
- Severity labels (STRONG/MODERATE/WEAK)
- Reviewer attribution
- Consensus grouping

**Step 4: Document results**

```bash
echo "✓ General prompt mode produces consensus report"
echo "✓ Uses STRONG/MODERATE/WEAK labels"
echo "✓ Groups by agreement level"
```

**Step 5: Commit verification notes**

```bash
git commit --allow-empty -m "test: verify general-prompt mode works end-to-end"
```

## Phase 7: Finalization

### Task 12: Update Main Documentation

**Files:**
- Modify: `README.md` (add multi-agent-consensus to skills list)
- Modify: `RELEASE-NOTES.md` (add v3.8.0 entry)

**Step 1: Update README.md skills list**

Find the Collaboration section and update:

```markdown
**Collaboration**
- **brainstorming** - Socratic design refinement with optional multi-agent validation
- **multi-agent-consensus** - Reusable Claude/Gemini/Codex consensus infrastructure
- **requesting-code-review** - Multi-reviewer code review using consensus framework
...
```

**Step 2: Add RELEASE-NOTES entry**

```markdown
## v3.8.0 (2025-12-13)

### Added

- **Multi-Agent Consensus Framework**: New reusable infrastructure for getting diverse AI perspectives
  - Mode-based interface: code-review and general-prompt modes
  - Shared consensus algorithm with word overlap and file matching
  - Three-tier output: High Priority (all agree), Medium (majority), Consider (single)
  - Graceful degradation: works with 1, 2, or 3 reviewers (Claude required)
  - Configurable similarity threshold via SIMILARITY_THRESHOLD env var
  - New skill at `skills/multi-agent-consensus/`
  - Complete test suite and documentation

### Changed

- **Requesting Code Review**: Migrated to use multi-agent-consensus framework
  - Now calls `multi-consensus.sh --mode=code-review`
  - Original `multi-review.sh` logic extracted into reusable framework
  - Functionality unchanged, improved architecture

- **Brainstorming**: Added optional multi-agent design validation
  - After design approval, can invoke multi-agent review
  - Catches architectural flaws and over-engineering before implementation
  - Uses STRONG/MODERATE/WEAK severity labels for design feedback

---
```

**Step 3: Commit**

```bash
git add README.md RELEASE-NOTES.md
git commit -m "docs: update main documentation for multi-agent-consensus framework"
```

### Task 13: Final Verification and Cleanup

**Files:**
- Test: All tests pass
- Verify: All documentation complete

**Step 1: Run all tests**

```bash
./skills/multi-agent-consensus/test-multi-consensus.sh
./skills/requesting-code-review/test-multi-review.sh
```

Expected: All tests pass

**Step 2: Check documentation completeness**

```bash
# Verify all docs exist
ls skills/multi-agent-consensus/SKILL.md
ls skills/multi-agent-consensus/README.md
ls docs/plans/2025-12-13-multi-agent-consensus-framework-design.md
ls docs/plans/2025-12-13-multi-agent-consensus-framework-implementation.md
```

**Step 3: Verify git status is clean**

```bash
git status
```

Expected: All changes committed

**Step 4: Create summary commit**

```bash
git commit --allow-empty -m "feat: complete multi-agent-consensus framework implementation

Summary of changes:
- New skill: skills/multi-agent-consensus/
- Mode-based interface (code-review, general-prompt)
- Shared consensus algorithm
- Comprehensive test suite
- Complete documentation
- Integration with brainstorming and requesting-code-review
- Backward compatible migration

All tests passing.
Ready for use."
```

**Step 5: Push to fork (if applicable)**

Note: This will be done after merging back to main branch.

---

## Summary

This plan creates the multi-agent-consensus framework by:

1. **Foundation** - Directory structure, base script copy
2. **Mode Architecture** - Argument parsing, context preparation
3. **General Prompt** - New mode implementation, severity labels
4. **Integration** - Update requesting-code-review, comprehensive tests
5. **Brainstorming** - Add design validation step
6. **Validation** - End-to-end testing of both modes
7. **Finalization** - Documentation, cleanup

**Total Tasks:** 13 tasks
**Estimated Time:** 2-3 hours with careful TDD approach
**Testing Strategy:** Unit tests per task, integration tests at end

**Key Success Criteria:**
- ✓ All tests pass
- ✓ Code review mode works identically to original
- ✓ General prompt mode produces consensus reports
- ✓ Documentation complete and clear
- ✓ Brainstorming integration functional
