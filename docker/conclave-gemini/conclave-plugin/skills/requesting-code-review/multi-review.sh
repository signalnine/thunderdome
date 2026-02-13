#!/usr/bin/env bash
set -euo pipefail

# Multi-reviewer code review script
# Coordinates parallel reviews from Claude, Gemini, and Codex

# Configuration
SIMILARITY_THRESHOLD="${SIMILARITY_THRESHOLD:-60}"  # Default 60% word overlap for issue similarity

# Check Bash version (requires 4.0+ for associative arrays)
if [ "${BASH_VERSINFO[0]}" -lt 4 ]; then
    echo "Error: Bash 4.0+ required (found $BASH_VERSION)" >&2
    echo "On macOS, install with: brew install bash" >&2
    exit 1
fi

# Check required dependencies
command -v bc >/dev/null 2>&1 || {
    echo "Error: 'bc' not installed (required for calculations)" >&2
    echo "Install with: apt-get install bc (Debian/Ubuntu) or brew install bc (macOS)" >&2
    exit 1
}

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

# Check for --dry-run flag (for testing)
DRY_RUN=false
if [ "${5:-}" = "--dry-run" ]; then
    DRY_RUN=true
fi

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

    # Invoke Gemini CLI with timeout (using positional prompt, model flag removed as it's not needed)
    timeout 120s gemini "$prompt" 2>&1 || {
        local exit_code=$?
        if [ $exit_code -eq 124 ]; then
            echo "GEMINI_TIMEOUT"
            return 1
        fi
        return $exit_code
    }
}

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
# Normalizes paths by removing leading ./ and converting to relative paths
extract_filename() {
    local description="$1"
    # Look for patterns like "in file.py" or "file.py:" or "file.py line"
    local filename=$(echo "$description" | grep -oE '\b[a-zA-Z0-9_/-]+\.(sh|py|js|ts|md|go|rs|java)\b' | head -1)

    if [ -n "$filename" ]; then
        # Normalize path: remove leading ./
        filename=$(echo "$filename" | sed 's|^\./||')
        echo "$filename"
        return 0
    fi
    echo ""
}

# Calculate word overlap between two descriptions
# Uses configurable threshold and filters common stop words
word_overlap_percent() {
    local desc1="$1"
    local desc2="$2"

    # Handle empty strings
    if [ -z "$desc1" ] || [ -z "$desc2" ]; then
        echo "0"
        return
    fi

    # Common stop words to filter (reduces false matches)
    local stop_words="the a an and or but in on at to for of with is are was were be been being have has had do does did will would should could may might must can"

    # Convert to lowercase and extract words
    local words1=$(echo "$desc1" | tr '[:upper:]' '[:lower:]' | grep -oE '\w+' | sort -u)
    local words2=$(echo "$desc2" | tr '[:upper:]' '[:lower:]' | grep -oE '\w+' | sort -u)

    # Filter stop words
    for stop in $stop_words; do
        words1=$(echo "$words1" | grep -v "^${stop}$" || true)
        words2=$(echo "$words2" | grep -v "^${stop}$" || true)
    done

    # Handle case where all words were stop words
    if [ -z "$words1" ] || [ -z "$words2" ]; then
        echo "0"
        return
    fi

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

# Check if two issues are similar (same file + configurable% word overlap)
issues_similar() {
    local issue1="$1"
    local issue2="$2"

    local file1=$(extract_filename "$issue1")
    local file2=$(extract_filename "$issue2")

    # If both mention a file, they must be the same file
    if [ -n "$file1" ] && [ -n "$file2" ] && [ "$file1" != "$file2" ]; then
        return 1
    fi

    # Check word overlap against configurable threshold
    local overlap=$(word_overlap_percent "$issue1" "$issue2")

    if [ "$overlap" -ge "$SIMILARITY_THRESHOLD" ]; then
        return 0
    else
        return 1
    fi
}

# === Consensus Aggregation ===

# Aggregate issues from multiple reviewers into consensus report
# Arguments:
#   $1 - claude_review: Full review text from Claude
#   $2 - gemini_review: Full review text from Gemini
#   $3 - codex_review: Full review text from Codex
#   $4 - claude_status: Status symbol (✓ or ✗)
#   $5 - gemini_status: Status symbol (✓ or ✗)
#   $6 - codex_status: Status symbol (✓ or ✗)
# Output: Formatted markdown consensus report to stdout
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
    local critical_count=$(cat "$consensus_all" "$consensus_majority" "$consensus_single" 2>/dev/null | grep -c "^\- \[Critical\]" || echo "0")
    local important_count=$(cat "$consensus_all" "$consensus_majority" "$consensus_single" 2>/dev/null | grep -c "^\- \[Important\]" || echo "0")
    local suggestion_count=$(cat "$consensus_all" "$consensus_majority" "$consensus_single" 2>/dev/null | grep -c "^\- \[Suggestion\]" || echo "0")

    echo "## Summary"
    echo "- Critical issues: $critical_count"
    echo "- Important issues: $important_count"
    echo "- Suggestions: $suggestion_count"

    # Cleanup
    rm -f "$all_issues_file" "$consensus_all" "$consensus_majority" "$consensus_single"
}

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

# Validate SHAs are different
if [ "$(git rev-parse "$BASE_SHA")" = "$(git rev-parse "$HEAD_SHA")" ]; then
    echo "Warning: BASE_SHA and HEAD_SHA point to the same commit - no changes to review" >&2
fi

# Get git diff
GIT_DIFF=$(git diff "$BASE_SHA..$HEAD_SHA")

# Get modified files
MODIFIED_FILES=$(git diff --name-only "$BASE_SHA..$HEAD_SHA")
if [ -z "$MODIFIED_FILES" ]; then
    MODIFIED_FILES_COUNT=0
else
    MODIFIED_FILES_COUNT=$(echo "$MODIFIED_FILES" | wc -l | tr -d ' ')
fi

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

# Launch Gemini review (optional, synchronous)
echo "  - Gemini (optional)..." >&2
GEMINI_REVIEW=$(launch_gemini_review "$FULL_CONTEXT" 2>&1)
GEMINI_EXIT=$?
GEMINI_ERROR_TYPE=""

# Determine specific error type for better reporting
if [ $GEMINI_EXIT -ne 0 ]; then
    if echo "$GEMINI_REVIEW" | grep -q "GEMINI_NOT_AVAILABLE"; then
        GEMINI_ERROR_TYPE="not installed"
    elif echo "$GEMINI_REVIEW" | grep -q "GEMINI_TIMEOUT"; then
        GEMINI_ERROR_TYPE="timeout after 120s"
    else
        GEMINI_ERROR_TYPE="error (exit $GEMINI_EXIT)"
    fi
fi

# Launch Codex review (optional, synchronous)
echo "  - Codex (optional)..." >&2
CODEX_REVIEW=$(launch_codex_review "$FULL_CONTEXT" 2>&1)
CODEX_EXIT=$?

# Determine which reviewers succeeded
CLAUDE_STATUS="✓"  # Always succeeds (script exits on Claude failure)
GEMINI_STATUS="✗ (not available)"
CODEX_STATUS="✗ (not available)"

if [ $GEMINI_EXIT -eq 0 ] && ! echo "$GEMINI_REVIEW" | grep -q "GEMINI_NOT_AVAILABLE"; then
    GEMINI_STATUS="✓"
elif [ -n "$GEMINI_ERROR_TYPE" ]; then
    GEMINI_STATUS="✗ ($GEMINI_ERROR_TYPE)"
fi

if [ $CODEX_EXIT -eq 0 ]; then
    CODEX_STATUS="✓"
fi

echo "Reviewers complete:" >&2
echo "  - Claude: $CLAUDE_STATUS" >&2
echo "  - Gemini: $GEMINI_STATUS" >&2
echo "  - Codex: $CODEX_STATUS" >&2

# === Output Consensus Report ===

aggregate_consensus "$CLAUDE_REVIEW" "$GEMINI_REVIEW" "$CODEX_REVIEW" \
    "$CLAUDE_STATUS" "$GEMINI_STATUS" "$CODEX_STATUS"

exit 0
