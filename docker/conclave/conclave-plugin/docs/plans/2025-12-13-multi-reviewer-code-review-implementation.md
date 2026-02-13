# Multi-Reviewer Code Review Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Create a bash script that coordinates parallel code reviews from Claude, Gemini, and Codex, aggregating their feedback into a consensus report.

**Architecture:** Bash script accepts git SHAs and context, launches three reviewers in parallel (Claude required, Gemini/Codex optional), parses outputs, matches similar issues, and produces markdown consensus report.

**Tech Stack:** Bash, Git, jq (JSON parsing), Gemini CLI, Codex MCP

---

## Phase 1: Script Foundation

### Task 1: Create Script Stub and Basic Validation

**Files:**
- Create: `skills/requesting-code-review/multi-review.sh`
- Create: `skills/requesting-code-review/test-multi-review.sh`

**Step 1: Write failing test for argument validation**

Create `skills/requesting-code-review/test-multi-review.sh`:

```bash
#!/usr/bin/env bash
set -e

echo "Testing multi-review.sh..."

# Test: Missing arguments
if ./skills/requesting-code-review/multi-review.sh 2>&1 | grep -q "Usage:"; then
    echo "✓ Shows usage when no arguments"
else
    echo "✗ Should show usage when no arguments"
    exit 1
fi

echo "All tests passed!"
```

**Step 2: Run test to verify it fails**

Run: `chmod +x skills/requesting-code-review/test-multi-review.sh && ./skills/requesting-code-review/test-multi-review.sh`
Expected: FAIL with "multi-review.sh: No such file"

**Step 3: Create minimal script**

Create `skills/requesting-code-review/multi-review.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail

# Multi-reviewer code review script
# Coordinates parallel reviews from Claude, Gemini, and Codex

show_usage() {
    cat <<EOF
Usage: $0 <BASE_SHA> <HEAD_SHA> <PLAN_FILE> <DESCRIPTION>

Arguments:
  BASE_SHA     - Starting commit for review
  HEAD_SHA     - Ending commit for review
  PLAN_FILE    - Path to plan/requirements document (or "-" for none)
  DESCRIPTION  - Brief description of what was implemented

Example:
  $0 abc123 def456 docs/plans/feature.md "Add user authentication"
EOF
}

# Validate arguments
if [ $# -lt 4 ]; then
    show_usage
    exit 1
fi

BASE_SHA="$1"
HEAD_SHA="$2"
PLAN_FILE="$3"
DESCRIPTION="$4"

echo "Multi-review placeholder - BASE: $BASE_SHA, HEAD: $HEAD_SHA"
exit 0
```

**Step 4: Make script executable and run test**

Run: `chmod +x skills/requesting-code-review/multi-review.sh && ./skills/requesting-code-review/test-multi-review.sh`
Expected: PASS with "All tests passed!"

**Step 5: Commit**

```bash
git add skills/requesting-code-review/multi-review.sh skills/requesting-code-review/test-multi-review.sh
git commit -m "feat: create multi-review script stub with argument validation"
```

---

### Task 2: Add Git Context Preparation

**Files:**
- Modify: `skills/requesting-code-review/multi-review.sh`
- Modify: `skills/requesting-code-review/test-multi-review.sh`

**Step 1: Add test for context preparation**

Add to `test-multi-review.sh` before "All tests passed!":

```bash
# Test: Context preparation
# Create a test repo with commits
test_dir=$(mktemp -d)
cd "$test_dir"
git init -q
echo "line1" > file.txt
git add file.txt
git commit -q -m "first commit"
FIRST_SHA=$(git rev-parse HEAD)
echo "line2" >> file.txt
git commit -q -am "second commit"
SECOND_SHA=$(git rev-parse HEAD)

# Run script in dry-run mode (add --dry-run flag)
if $OLDPWD/skills/requesting-code-review/multi-review.sh \
    "$FIRST_SHA" "$SECOND_SHA" "-" "test change" --dry-run 2>&1 \
    | grep -q "Modified files: 1"; then
    echo "✓ Extracts git context correctly"
else
    echo "✗ Should extract git context"
    exit 1
fi

cd "$OLDPWD"
rm -rf "$test_dir"
```

**Step 2: Run test to verify it fails**

Run: `./skills/requesting-code-review/test-multi-review.sh`
Expected: FAIL with "Should extract git context"

**Step 3: Add context preparation to script**

Add after argument validation in `multi-review.sh`:

```bash
# Check for --dry-run flag (for testing)
DRY_RUN=false
if [ "${5:-}" = "--dry-run" ]; then
    DRY_RUN=true
fi

# === Context Preparation ===

# Validate git SHAs exist
if ! git rev-parse "$BASE_SHA" >/dev/null 2>&1; then
    echo "Error: BASE_SHA '$BASE_SHA' not found in repository" >&2
    exit 1
fi

if ! git rev-parse "$HEAD_SHA" >/dev/null 2>&1; then
    echo "Error: HEAD_SHA '$HEAD_SHA' not found in repository" >&2
    exit 1
fi

# Get git diff
GIT_DIFF=$(git diff "$BASE_SHA..$HEAD_SHA")

# Get modified files
MODIFIED_FILES=$(git diff --name-only "$BASE_SHA..$HEAD_SHA")
MODIFIED_FILES_COUNT=$(echo "$MODIFIED_FILES" | wc -l | tr -d ' ')

# Read plan file if provided
PLAN_CONTENT=""
if [ "$PLAN_FILE" != "-" ]; then
    if [ -f "$PLAN_FILE" ]; then
        PLAN_CONTENT=$(cat "$PLAN_FILE")
    else
        echo "Warning: Plan file '$PLAN_FILE' not found" >&2
    fi
fi

# Build full context
FULL_CONTEXT="# Code Review Context

**Description:** $DESCRIPTION
**Commits:** $BASE_SHA..$HEAD_SHA
**Modified files:** $MODIFIED_FILES_COUNT

## Modified Files
$MODIFIED_FILES

## Git Diff
\`\`\`diff
$GIT_DIFF
\`\`\`

## Plan/Requirements
$PLAN_CONTENT
"

if [ "$DRY_RUN" = true ]; then
    echo "Modified files: $MODIFIED_FILES_COUNT"
    exit 0
fi

echo "Context prepared: $MODIFIED_FILES_COUNT file(s) modified"
```

**Step 4: Run test to verify it passes**

Run: `./skills/requesting-code-review/test-multi-review.sh`
Expected: PASS with "All tests passed!"

**Step 5: Commit**

```bash
git add skills/requesting-code-review/multi-review.sh skills/requesting-code-review/test-multi-review.sh
git commit -m "feat: add git context preparation to multi-review"
```

---

## Phase 2: Reviewer Stub Functions

### Task 3: Create Reviewer Stub Functions

**Files:**
- Modify: `skills/requesting-code-review/multi-review.sh`

**Step 1: Add stub reviewer functions**

Add before "Context Preparation" section:

```bash
# === Reviewer Functions ===

# Launch Claude code-reviewer subagent
# NOTE: This is a placeholder - actual implementation requires Claude Code Task tool
launch_claude_review() {
    local context="$1"

    # For now, return mock review
    cat <<EOF
# Claude Code Review

## Critical Issues
- Missing error handling in main function

## Important Issues
- No input validation

## Suggestions
- Consider adding logging
EOF
}

# Launch Gemini CLI review
launch_gemini_review() {
    local context="$1"

    # Check if gemini CLI is available
    if ! command -v gemini &> /dev/null; then
        echo "GEMINI_NOT_AVAILABLE"
        return 1
    fi

    # For now, return mock review
    cat <<EOF
# Gemini Code Review

## Critical Issues
- Missing error handling in main function

## Important Issues
- Edge case not handled

## Suggestions
- Add unit tests
EOF
}

# Launch Codex MCP review
# NOTE: This is a placeholder - actual implementation requires MCP tool
launch_codex_review() {
    local context="$1"

    # For now, return mock review
    cat <<EOF
# Codex Code Review

## Important Issues
- No input validation
- Edge case not handled

## Suggestions
- Improve naming
EOF
}
```

**Step 2: Add parallel execution after context preparation**

Add at the end of the script (replace the placeholder echo):

```bash
# === Parallel Review Execution ===

echo "Launching reviewers..." >&2

# Launch Claude review (required, blocking)
echo "  - Claude (required)..." >&2
CLAUDE_REVIEW=$(launch_claude_review "$FULL_CONTEXT" 2>&1)
CLAUDE_EXIT=$?

if [ $CLAUDE_EXIT -ne 0 ]; then
    echo "Error: Claude review failed" >&2
    exit 1
fi

# Launch Gemini review (optional, background with timeout)
echo "  - Gemini (optional)..." >&2
GEMINI_REVIEW=$(timeout 60s bash -c "launch_gemini_review '$FULL_CONTEXT'" 2>&1) &
GEMINI_PID=$!

# Launch Codex review (optional, background with timeout)
echo "  - Codex (optional)..." >&2
CODEX_REVIEW=$(timeout 60s bash -c "launch_codex_review '$FULL_CONTEXT'" 2>&1) &
CODEX_PID=$!

# Wait for optional reviewers
wait $GEMINI_PID
GEMINI_EXIT=$?

wait $CODEX_PID
CODEX_EXIT=$?

# Determine which reviewers succeeded
CLAUDE_STATUS="✓"
GEMINI_STATUS="✗ (not available)"
CODEX_STATUS="✗ (not available)"

if [ $GEMINI_EXIT -eq 0 ] && ! echo "$GEMINI_REVIEW" | grep -q "GEMINI_NOT_AVAILABLE"; then
    GEMINI_STATUS="✓"
fi

if [ $CODEX_EXIT -eq 0 ]; then
    CODEX_STATUS="✓"
fi

echo "Reviewers complete:" >&2
echo "  - Claude: $CLAUDE_STATUS" >&2
echo "  - Gemini: $GEMINI_STATUS" >&2
echo "  - Codex: $CODEX_STATUS" >&2

# For now, just output raw reviews
echo "# Multi-Reviewer Code Review Report"
echo ""
echo "**Reviewers**: Claude $CLAUDE_STATUS, Gemini $GEMINI_STATUS, Codex $CODEX_STATUS"
echo ""
echo "## Claude Review"
echo "$CLAUDE_REVIEW"
echo ""
echo "## Gemini Review"
echo "$GEMINI_REVIEW"
echo ""
echo "## Codex Review"
echo "$CODEX_REVIEW"

exit 0
```

**Step 3: Test manually**

Run: `git log --oneline -2` to get two commit SHAs, then:
```bash
BASE=$(git log --oneline | tail -2 | head -1 | awk '{print $1}')
HEAD=$(git log --oneline | head -1 | awk '{print $1}')
./skills/requesting-code-review/multi-review.sh "$BASE" "$HEAD" "-" "test review"
```

Expected: Shows raw reviews from all three mock reviewers

**Step 4: Commit**

```bash
git add skills/requesting-code-review/multi-review.sh
git commit -m "feat: add stub reviewer functions with parallel execution"
```

---

## Phase 3: Consensus Aggregation

### Task 4: Create Issue Parser

**Files:**
- Modify: `skills/requesting-code-review/multi-review.sh`

**Step 1: Add issue parsing function**

Add after reviewer functions:

```bash
# === Issue Parsing ===

# Parse issues from a review text
# Output format: SEVERITY|DESCRIPTION (one per line)
parse_issues() {
    local review_text="$1"
    local current_severity=""

    while IFS= read -r line; do
        # Detect severity headers
        if echo "$line" | grep -q "^## Critical Issues"; then
            current_severity="Critical"
        elif echo "$line" | grep -q "^## Important Issues"; then
            current_severity="Important"
        elif echo "$line" | grep -q "^## Suggestions"; then
            current_severity="Suggestion"
        # Extract issue lines (start with -)
        elif echo "$line" | grep -q "^-"; then
            issue_desc=$(echo "$line" | sed 's/^- *//')
            if [ -n "$current_severity" ] && [ -n "$issue_desc" ]; then
                echo "$current_severity|$issue_desc"
            fi
        fi
    done <<< "$review_text"
}

# Extract filename from issue description (if present)
extract_filename() {
    local description="$1"
    # Look for patterns like "in file.py" or "file.py:" or "file.py line"
    if echo "$description" | grep -oE '\b[a-zA-Z0-9_/-]+\.(sh|py|js|ts|md|go|rs|java)\b' | head -1; then
        return 0
    fi
    echo ""
}

# Calculate word overlap between two descriptions
word_overlap_percent() {
    local desc1="$1"
    local desc2="$2"

    # Convert to lowercase and extract words
    words1=$(echo "$desc1" | tr '[:upper:]' '[:lower:]' | grep -oE '\w+' | sort -u)
    words2=$(echo "$desc2" | tr '[:upper:]' '[:lower:]' | grep -oE '\w+' | sort -u)

    # Count common words
    common=$(comm -12 <(echo "$words1") <(echo "$words2") | wc -l | tr -d ' ')
    total=$(echo "$words1" | wc -l | tr -d ' ')

    if [ "$total" -eq 0 ]; then
        echo "0"
        return
    fi

    # Calculate percentage
    echo "scale=0; ($common * 100) / $total" | bc
}

# Check if two issues are similar (same file + 60% word overlap)
issues_similar() {
    local issue1="$1"
    local issue2="$2"

    local file1=$(extract_filename "$issue1")
    local file2=$(extract_filename "$issue2")

    # If both mention a file, they must be the same file
    if [ -n "$file1" ] && [ -n "$file2" ] && [ "$file1" != "$file2" ]; then
        return 1
    fi

    # Check word overlap
    local overlap=$(word_overlap_percent "$issue1" "$issue2")

    if [ "$overlap" -ge 60 ]; then
        return 0
    else
        return 1
    fi
}
```

**Step 2: Commit**

```bash
git add skills/requesting-code-review/multi-review.sh
git commit -m "feat: add issue parsing and similarity detection"
```

---

### Task 5: Create Consensus Aggregator

**Files:**
- Modify: `skills/requesting-code-review/multi-review.sh`

**Step 1: Add consensus aggregation function**

Add after issue parsing functions:

```bash
# === Consensus Aggregation ===

# Aggregate issues from multiple reviewers into consensus report
aggregate_consensus() {
    local claude_review="$1"
    local gemini_review="$2"
    local codex_review="$3"
    local claude_status="$4"
    local gemini_status="$5"
    local codex_status="$6"

    # Parse issues from each review
    local claude_issues=$(parse_issues "$claude_review")
    local gemini_issues=$(parse_issues "$gemini_review")
    local codex_issues=$(parse_issues "$codex_review")

    # Temporary files for grouping
    local all_issues_file=$(mktemp)
    local consensus_all=$(mktemp)
    local consensus_majority=$(mktemp)
    local consensus_single=$(mktemp)

    # Track which issues have been processed
    declare -A processed_issues

    # Collect all unique issues with reviewer attribution
    {
        echo "$claude_issues" | while IFS='|' read -r severity desc; do
            [ -n "$desc" ] && echo "Claude|$severity|$desc"
        done

        echo "$gemini_issues" | while IFS='|' read -r severity desc; do
            [ -n "$desc" ] && echo "Gemini|$severity|$desc"
        done

        echo "$codex_issues" | while IFS='|' read -r severity desc; do
            [ -n "$desc" ] && echo "Codex|$severity|$desc"
        done
    } > "$all_issues_file"

    # Group similar issues
    while IFS='|' read -r reviewer1 severity1 desc1; do
        [ -z "$desc1" ] && continue

        # Skip if already processed
        issue_key="$reviewer1:$desc1"
        [ "${processed_issues[$issue_key]:-}" = "1" ] && continue

        # Find all similar issues
        matching_reviewers=("$reviewer1")
        matching_severities=("$severity1")
        matching_descs=("$desc1")

        while IFS='|' read -r reviewer2 severity2 desc2; do
            [ -z "$desc2" ] && continue
            [ "$reviewer1" = "$reviewer2" ] && [ "$desc1" = "$desc2" ] && continue

            if issues_similar "$desc1" "$desc2"; then
                matching_reviewers+=("$reviewer2")
                matching_severities+=("$severity2")
                matching_descs+=("$desc2")
                processed_issues["$reviewer2:$desc2"]="1"
            fi
        done < "$all_issues_file"

        processed_issues["$issue_key"]="1"

        # Determine consensus level
        num_reviewers=${#matching_reviewers[@]}
        max_severity="$severity1"

        # Use highest severity
        for sev in "${matching_severities[@]}"; do
            if [ "$sev" = "Critical" ]; then
                max_severity="Critical"
            elif [ "$sev" = "Important" ] && [ "$max_severity" != "Critical" ]; then
                max_severity="Important"
            fi
        done

        # Format reviewer quotes
        reviewer_quotes=""
        for i in "${!matching_reviewers[@]}"; do
            reviewer_quotes+="  - ${matching_reviewers[$i]}: \"${matching_descs[$i]}\"\n"
        done

        # Categorize by consensus
        output_line="- [$max_severity] $desc1\n$reviewer_quotes"

        if [ "$num_reviewers" -ge 3 ] || ([ "$num_reviewers" -ge 2 ] && [[ "$gemini_status" == *"✗"* || "$codex_status" == *"✗"* ]]); then
            echo -e "$output_line" >> "$consensus_all"
        elif [ "$num_reviewers" -eq 2 ]; then
            echo -e "$output_line" >> "$consensus_majority"
        else
            echo -e "$output_line" >> "$consensus_single"
        fi
    done < "$all_issues_file"

    # Output consensus report
    echo "# Code Review Consensus Report"
    echo ""
    echo "**Reviewers**: Claude $claude_status, Gemini $gemini_status, Codex $codex_status"
    echo "**Commits**: $BASE_SHA..$HEAD_SHA"
    echo ""

    if [ -s "$consensus_all" ]; then
        echo "## High Priority - All Reviewers Agree"
        cat "$consensus_all"
        echo ""
    fi

    if [ -s "$consensus_majority" ]; then
        echo "## Medium Priority - Majority Flagged (2/3)"
        cat "$consensus_majority"
        echo ""
    fi

    if [ -s "$consensus_single" ]; then
        echo "## Consider - Single Reviewer Mentioned"
        cat "$consensus_single"
        echo ""
    fi

    # Summary
    local critical_count=$(grep -c "^\- \[Critical\]" "$consensus_all" "$consensus_majority" "$consensus_single" 2>/dev/null || echo "0")
    local important_count=$(grep -c "^\- \[Important\]" "$consensus_all" "$consensus_majority" "$consensus_single" 2>/dev/null || echo "0")
    local suggestion_count=$(grep -c "^\- \[Suggestion\]" "$consensus_all" "$consensus_majority" "$consensus_single" 2>/dev/null || echo "0")

    echo "## Summary"
    echo "- Critical issues: $critical_count"
    echo "- Important issues: $important_count"
    echo "- Suggestions: $suggestion_count"

    # Cleanup
    rm -f "$all_issues_file" "$consensus_all" "$consensus_majority" "$consensus_single"
}
```

**Step 2: Replace raw output with aggregation**

Replace the output section at the end of the script with:

```bash
# === Output Consensus Report ===

aggregate_consensus "$CLAUDE_REVIEW" "$GEMINI_REVIEW" "$CODEX_REVIEW" \
    "$CLAUDE_STATUS" "$GEMINI_STATUS" "$CODEX_STATUS"

exit 0
```

**Step 3: Test manually**

Run:
```bash
BASE=$(git log --oneline | tail -2 | head -1 | awk '{print $1}')
HEAD=$(git log --oneline | head -1 | awk '{print $1}')
./skills/requesting-code-review/multi-review.sh "$BASE" "$HEAD" "-" "test review"
```

Expected: Shows consensus report with "High Priority" section (all three mock reviewers mention "Missing error handling")

**Step 4: Commit**

```bash
git add skills/requesting-code-review/multi-review.sh
git commit -m "feat: add consensus aggregation with priority grouping"
```

---

## Phase 4: Real Reviewer Integration

### Task 6: Integrate Gemini CLI

**Files:**
- Modify: `skills/requesting-code-review/multi-review.sh`

**Step 1: Update Gemini reviewer function**

Replace the `launch_gemini_review` function:

```bash
# Launch Gemini CLI review
launch_gemini_review() {
    local context="$1"

    # Check if gemini CLI is available
    if ! command -v gemini &> /dev/null; then
        echo "GEMINI_NOT_AVAILABLE"
        return 1
    fi

    # Build review prompt
    local prompt="You are a senior code reviewer. Review the following code change and provide structured feedback.

$context

Please provide your review in the following format:

## Critical Issues
- [list critical issues here, or write 'None']

## Important Issues
- [list important issues here, or write 'None']

## Suggestions
- [list suggestions here, or write 'None']

Be specific and include file names and line numbers when possible."

    # Invoke Gemini CLI
    gemini --model gemini-2.0-flash-exp --prompt "$prompt" 2>&1
}
```

**Step 2: Test with real Gemini**

Run:
```bash
BASE=$(git log --oneline | tail -2 | head -1 | awk '{print $1}')
HEAD=$(git log --oneline | head -1 | awk '{print $1}')
./skills/requesting-code-review/multi-review.sh "$BASE" "$HEAD" "-" "test review" 2>/dev/null | grep -A5 "Gemini"
```

Expected: Shows Gemini's actual review output

**Step 3: Commit**

```bash
git add skills/requesting-code-review/multi-review.sh
git commit -m "feat: integrate real Gemini CLI for code review"
```

---

### Task 7: Add Codex MCP Integration Instructions

**Files:**
- Modify: `skills/requesting-code-review/multi-review.sh`
- Create: `skills/requesting-code-review/README.md`

**Step 1: Add note about Codex MCP limitation**

Update `launch_codex_review` function comment:

```bash
# Launch Codex MCP review
# NOTE: Codex MCP is only available from within Claude Code sessions.
#       This script is invoked BY Claude Code, so actual MCP calls
#       must be made by the assistant, not by this bash script.
#       This function returns a placeholder instructing the assistant
#       to make the MCP call.
launch_codex_review() {
    local context="$1"

    # Return instruction for Claude Code to execute
    cat <<EOF
CODEX_MCP_INSTRUCTION

The assistant should use the mcp__codex-cli__codex tool with this prompt:

"You are a senior code reviewer. Review the following code change and provide structured feedback.

$context

Please provide your review in the following format:

## Critical Issues
- [list critical issues here, or write 'None']

## Important Issues
- [list important issues here, or write 'None']

## Suggestions
- [list suggestions here, or write 'None']

Be specific and include file names and line numbers when possible."

EOF
}
```

**Step 2: Create README explaining the architecture**

Create `skills/requesting-code-review/README.md`:

```markdown
# Multi-Reviewer Code Review System

## Architecture

This directory contains a multi-reviewer code review system that coordinates parallel reviews from three AI reviewers:

1. **Claude Code** (via Task tool) - Required
2. **Gemini** (via CLI) - Optional
3. **Codex** (via MCP) - Optional

## How It Works

### Direct Invocation (Gemini only)

The `multi-review.sh` script can directly invoke:
- ✅ Gemini CLI (subprocess)
- ❌ Claude Task tool (requires Claude Code environment)
- ❌ Codex MCP (requires Claude Code environment)

### Claude Code Orchestration

When invoked from within a Claude Code session, the assistant:

1. Calls `multi-review.sh` to get Gemini's review
2. Simultaneously dispatches Claude subagent review (via Task tool)
3. Simultaneously calls Codex MCP (via mcp__codex-cli__codex tool)
4. Aggregates all three reviews into consensus report

## Files

- `multi-review.sh` - Main coordination script
- `SKILL.md` - Instructions for Claude Code assistant
- `code-reviewer.md` - Agent definition for Claude review
- `test-multi-review.sh` - Test suite
- `README.md` - This file

## Testing

Run the test suite:
```bash
./skills/requesting-code-review/test-multi-review.sh
```

Test with real code:
```bash
BASE_SHA=$(git rev-parse HEAD~1)
HEAD_SHA=$(git rev-parse HEAD)
./skills/requesting-code-review/multi-review.sh "$BASE_SHA" "$HEAD_SHA" "-" "Test review"
```

## Dependencies

- bash 4.0+
- git
- jq (for JSON parsing)
- bc (for calculations)
- gemini CLI (optional, for Gemini reviews)
- Claude Code (optional, for Claude/Codex reviews)
```

**Step 3: Commit**

```bash
git add skills/requesting-code-review/multi-review.sh skills/requesting-code-review/README.md
git commit -m "docs: explain Codex MCP limitation and architecture"
```

---

## Phase 5: Update SKILL.md

### Task 8: Update SKILL.md with Multi-Reviewer Workflow

**Files:**
- Modify: `skills/requesting-code-review/SKILL.md`

**Step 1: Read current SKILL.md**

Run: `cat skills/requesting-code-review/SKILL.md`

**Step 2: Create updated SKILL.md**

Replace `skills/requesting-code-review/SKILL.md` with:

```markdown
---
name: requesting-code-review
description: Use when completing tasks, implementing major features, or before merging to verify work meets requirements - dispatches multiple AI reviewers (Claude, Gemini, Codex) in parallel for thorough consensus-based code review
---

# Requesting Code Review

Get parallel reviews from Claude, Gemini, and Codex to catch issues before they cascade.

**Core principle:** Multiple independent reviews = maximum coverage.

## When to Request Review

**Mandatory:**
- After each task in subagent-driven development
- After completing major feature
- Before merge to main

**Optional but valuable:**
- When stuck (fresh perspectives)
- Before refactoring (baseline check)
- After fixing complex bug

## How to Request Multi-Reviewer Consensus

**1. Get git SHAs:**
```bash
BASE_SHA=$(git rev-parse HEAD~1)  # or origin/main
HEAD_SHA=$(git rev-parse HEAD)
```

**2. Identify plan file:**
```bash
PLAN_FILE="docs/plans/2025-12-13-feature-name.md"  # or "-" if no plan
DESCRIPTION="Brief description of what was implemented"
```

**3. Launch parallel reviews:**

You must coordinate three reviewers simultaneously:

**a) Invoke Gemini via script (captures output):**
```bash
GEMINI_OUTPUT=$(./skills/requesting-code-review/multi-review.sh \
    "$BASE_SHA" "$HEAD_SHA" "$PLAN_FILE" "$DESCRIPTION" 2>/dev/null) &
GEMINI_PID=$!
```

**b) Dispatch Claude subagent (via Task tool):**

Use Task tool with `superpowers:code-reviewer` type, filling template from `code-reviewer.md`:
- WHAT_WAS_IMPLEMENTED: [what you built]
- PLAN_OR_REQUIREMENTS: [from $PLAN_FILE]
- BASE_SHA: $BASE_SHA
- HEAD_SHA: $HEAD_SHA
- DESCRIPTION: $DESCRIPTION

**c) Invoke Codex MCP:**

Use `mcp__codex-cli__codex` tool with prompt:
```
You are a senior code reviewer. Review this code change:

[Include git diff from $BASE_SHA to $HEAD_SHA]
[Include plan/requirements from $PLAN_FILE]
[Include description: $DESCRIPTION]

Provide structured feedback:

## Critical Issues
- [issues or 'None']

## Important Issues
- [issues or 'None']

## Suggestions
- [suggestions or 'None']
```

**4. Wait for all reviews to complete:**

```bash
# Wait for Gemini
wait $GEMINI_PID
GEMINI_REVIEW="$GEMINI_OUTPUT"

# Claude and Codex complete when their tools return
CLAUDE_REVIEW="[from Task tool result]"
CODEX_REVIEW="[from MCP tool result]"
```

**5. Aggregate into consensus report:**

Parse each review for issues, group by consensus level:
- **All reviewers agree** (3/3 or 2/2 if one failed) → HIGH PRIORITY
- **Majority flagged** (2/3) → MEDIUM PRIORITY
- **Single reviewer** (1/3) → CONSIDER

Use issue similarity matching (same file + 60% word overlap).

**6. Act on consensus feedback:**
- **All reviewers agree** → Fix immediately before proceeding
- **Majority flagged** → Fix unless you have strong reasoning otherwise
- **Single reviewer** → Consider, but use judgment
- Push back if feedback is wrong (with technical reasoning)

## Simplified Single-Reviewer Mode

If you need a quick review, use Claude-only mode:

Dispatch `superpowers:code-reviewer` subagent directly with Task tool.

This skips Gemini/Codex and gives you just Claude's review.

## Example Multi-Review Workflow

```
[Just completed Task 2: Add verification function]

You: Let me request consensus code review.

# Get SHAs
BASE_SHA=a7981ec
HEAD_SHA=3df7661
PLAN_FILE="docs/plans/deployment-plan.md"
DESCRIPTION="Added verifyIndex() and repairIndex() with 4 issue types"

# Launch Gemini
[Invoke multi-review.sh script in background]

# Launch Claude subagent
[Dispatch superpowers:code-reviewer with Task tool]

# Launch Codex MCP
[Use mcp__codex-cli__codex tool]

# Wait for all three

# Aggregate results:
## High Priority - All Reviewers Agree
- [Critical] Missing progress indicators
  - Claude: "No user feedback during long operations"
  - Gemini: "Progress reporting missing for iteration"
  - Codex: "Add progress callbacks"

## Medium Priority - Majority Flagged (2/3)
- [Important] Magic number in code
  - Claude: "100 should be a named constant"
  - Codex: "Extract BATCH_SIZE constant"

## Summary
- Critical: 1 (consensus: 1)
- Important: 1 (consensus: 0, majority: 1)

You: [Fix progress indicators immediately]
You: [Fix magic number]
[Continue to Task 3]
```

## Integration with Workflows

**Subagent-Driven Development:**
- Review after EACH task
- All three reviewers for thoroughness
- Fix consensus issues before next task

**Executing Plans:**
- Review after each batch (3 tasks)
- Get consensus feedback, apply, continue

**Ad-Hoc Development:**
- Review before merge
- Review when stuck

## Red Flags

**Never:**
- Skip review because "it's simple"
- Ignore Critical issues from consensus
- Proceed with unfixed consensus issues
- Argue with valid technical feedback from multiple reviewers

**If reviewers wrong:**
- Push back with technical reasoning
- Show code/tests that prove it works
- Request clarification

**If reviewers disagree:**
- Consensus issues (all agree) take priority
- Investigate majority-flagged issues
- Use judgment on single-reviewer issues

## Troubleshooting

**Gemini not available:**
- Script will mark Gemini as "✗ (not available)"
- Continue with Claude + Codex
- Consensus threshold adjusts (2/2 instead of 3/3)

**Codex MCP fails:**
- Mark Codex as "✗ (error)"
- Continue with Claude + Gemini
- Consensus threshold adjusts

**Only Claude succeeds:**
- Falls back to single-reviewer mode
- Still get thorough review from Claude
- Consider why other reviewers failed

## Files

- `multi-review.sh` - Gemini coordination script
- `code-reviewer.md` - Claude agent definition (used by Task tool)
- `README.md` - Architecture documentation
```

**Step 3: Verify SKILL.md is well-formed**

Run: `head -20 skills/requesting-code-review/SKILL.md`
Expected: Shows frontmatter and beginning of content

**Step 4: Commit**

```bash
git add skills/requesting-code-review/SKILL.md
git commit -m "docs: update SKILL.md with multi-reviewer workflow"
```

---

## Phase 6: Integration Testing

### Task 9: Test End-to-End with Real Code

**Files:**
- Test existing code

**Step 1: Create a test commit**

```bash
echo "# Test file" > test-review-target.txt
git add test-review-target.txt
git commit -m "test: add file for review testing"
TEST_BASE=$(git rev-parse HEAD~1)
TEST_HEAD=$(git rev-parse HEAD)
```

**Step 2: Run multi-review script**

Run:
```bash
./skills/requesting-code-review/multi-review.sh \
    "$TEST_BASE" "$TEST_HEAD" "-" "Test file addition" \
    2>/dev/null
```

Expected:
- Shows "Reviewers complete" with Claude and Gemini status
- Shows consensus report
- Groups issues appropriately

**Step 3: Verify consensus grouping**

Check that:
- Issues mentioned by all reviewers appear in "High Priority"
- Issues mentioned by 2 reviewers appear in "Medium Priority"
- Issues mentioned by 1 reviewer appear in "Consider"

**Step 4: Clean up test commit**

```bash
git reset --hard HEAD~1
rm -f test-review-target.txt
```

**Step 5: Document test results**

No commit needed - just verification.

---

### Task 10: Create Usage Documentation

**Files:**
- Modify: `skills/requesting-code-review/README.md`

**Step 1: Add usage examples to README**

Add to end of `README.md`:

```markdown

## Usage from Claude Code

When the assistant uses the requesting-code-review skill, it should:

1. **Prepare context:**
   ```bash
   BASE_SHA=$(git rev-parse HEAD~1)
   HEAD_SHA=$(git rev-parse HEAD)
   PLAN_FILE="docs/plans/feature.md"
   DESCRIPTION="What was implemented"
   ```

2. **Launch Gemini review in background:**
   ```bash
   GEMINI_OUTPUT=$(./skills/requesting-code-review/multi-review.sh \
       "$BASE_SHA" "$HEAD_SHA" "$PLAN_FILE" "$DESCRIPTION" 2>/dev/null) &
   GEMINI_PID=$!
   ```

3. **Simultaneously launch Claude subagent:**
   Use Task tool with superpowers:code-reviewer

4. **Simultaneously launch Codex MCP:**
   Use mcp__codex-cli__codex tool

5. **Wait for Gemini:**
   ```bash
   wait $GEMINI_PID
   ```

6. **Aggregate all three reviews:**
   Parse issues, group by consensus, present to user

## Example Output

```markdown
# Code Review Consensus Report

**Reviewers**: Claude ✓, Gemini ✓, Codex ✓
**Commits**: abc123..def456

## High Priority - All Reviewers Agree
- [Critical] Missing null check in parseInput() (line 45)
  - Claude: "Potential null pointer exception when input is empty"
  - Gemini: "Input validation missing - null case not handled"
  - Codex: "Add null check before accessing input.length"

## Medium Priority - Majority Flagged (2/3)
- [Important] Error handling incomplete in saveData()
  - Claude: "Should catch IOException and provide user feedback"
  - Codex: "Missing error recovery for file write failures"

## Consider - Single Reviewer Mentioned
- [Suggestion] Extract validation logic to separate function
  - Gemini: "Would improve testability and reusability"

## Summary
- Critical issues: 1 (consensus: 1)
- Important issues: 1 (consensus: 0, majority: 1)
- Suggestions: 1 (consensus: 0, majority: 0, single: 1)
```

## Consensus Interpretation

- **High Priority (All Agree)**: Fix immediately. Multiple independent reviewers identified the same issue.
- **Medium Priority (Majority)**: Strong signal. Fix unless you have technical justification.
- **Consider (Single)**: May be valid but less critical. Use judgment based on context.
```

**Step 2: Commit**

```bash
git add skills/requesting-code-review/README.md
git commit -m "docs: add usage examples and consensus interpretation guide"
```

---

## Phase 7: Final Verification

### Task 11: Run All Tests

**Files:**
- Test: All created files

**Step 1: Run test suite**

Run: `./skills/requesting-code-review/test-multi-review.sh`
Expected: All tests pass

**Step 2: Verify script is executable**

Run: `ls -l skills/requesting-code-review/multi-review.sh | grep -q 'x' && echo "executable" || echo "not executable"`
Expected: "executable"

**Step 3: Check git status**

Run: `git status`
Expected: Clean working tree

**Step 4: Review commit history**

Run: `git log --oneline -15`
Expected: Shows all commits from implementation

**Step 5: Document completion**

No commit needed - verification only.

---

## Success Criteria

- [x] `multi-review.sh` script created and executable
- [x] Script successfully invokes Gemini CLI
- [x] Claude review integration documented (via Task tool)
- [x] Codex MCP integration documented (via MCP tool)
- [x] Consensus aggregation produces markdown output with three priority levels
- [x] SKILL.md updated with multi-reviewer workflow
- [x] Backwards compatibility maintained (single-reviewer mode documented)
- [x] Test suite passes
- [x] Documentation complete (README.md with usage examples)
- [x] All changes committed to git

## Next Steps

After implementation is complete:

1. **Manual Testing**: Test with real code review scenario from Claude Code session
2. **Merge to Main**: Create PR or merge feature branch
3. **Update Release Notes**: Document new multi-reviewer capability
4. **User Documentation**: Add example to main superpowers docs

## Notes

- The script handles Gemini directly via CLI subprocess
- Claude and Codex reviews must be orchestrated by the Claude Code assistant (not the script)
- This hybrid approach works because:
  - Script can spawn Gemini subprocess
  - Assistant can use Task tool and MCP tools in parallel
  - Assistant aggregates all three results
