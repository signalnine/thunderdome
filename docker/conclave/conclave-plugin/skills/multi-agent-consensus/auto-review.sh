#!/usr/bin/env bash
set -euo pipefail

# auto-review.sh
# Simplified wrapper for consensus-synthesis.sh that auto-detects git SHAs
#
# Usage:
#   ./auto-review.sh "Description of changes"
#   ./auto-review.sh --base="abc123" "Description"
#   ./auto-review.sh --plan-file=docs/plan.md "Description"
#
# Auto-detects:
#   - Base SHA: from origin/main merge-base, or HEAD~N
#   - Head SHA: HEAD
#
# Options:
#   --base=SHA         Override base SHA (default: auto-detect)
#   --head=SHA         Override head SHA (default: HEAD)
#   --plan-file=PATH   Path to implementation plan file
#   --dry-run          Validate arguments without executing
#   --help             Show this help message

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

#############################################
# Usage
#############################################

usage() {
    cat <<EOF
Usage: auto-review.sh [OPTIONS] "Description of changes"

Simplified wrapper for multi-agent consensus code review.
Auto-detects git SHAs for the review range.

OPTIONS:
  --base=SHA         Override base SHA (default: auto-detect from origin/main)
  --head=SHA         Override head SHA (default: HEAD)
  --plan-file=PATH   Path to implementation plan file
  --dry-run          Validate arguments and show what would be reviewed
  --help             Show this help message

EXAMPLES:
  # Review changes since origin/main (auto-detected)
  ./auto-review.sh "Added user authentication"

  # Review with explicit base
  ./auto-review.sh --base=abc123 "Refactored API endpoints"

  # Review with plan file context
  ./auto-review.sh --plan-file=docs/plans/feature.md "Completed task 1"

  # Review last 3 commits
  ./auto-review.sh --base=HEAD~3 "Recent fixes"

AUTO-DETECTION:
  Base SHA detection order:
    1. origin/main merge-base (if origin/main exists)
    2. origin/master merge-base (if origin/master exists)
    3. HEAD~1 (fallback)

EOF
}

#############################################
# Argument Parsing
#############################################

BASE_SHA=""
HEAD_SHA="HEAD"
PLAN_FILE=""
DESCRIPTION=""
DRY_RUN=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --base=*)
            BASE_SHA="${1#*=}"
            shift
            ;;
        --head=*)
            HEAD_SHA="${1#*=}"
            shift
            ;;
        --plan-file=*)
            PLAN_FILE="${1#*=}"
            shift
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --help)
            usage
            exit 0
            ;;
        -*)
            echo "Error: Unknown option: $1" >&2
            echo "" >&2
            usage >&2
            exit 1
            ;;
        *)
            # Positional argument = description
            if [[ -z "$DESCRIPTION" ]]; then
                DESCRIPTION="$1"
            else
                echo "Error: Multiple descriptions provided" >&2
                exit 1
            fi
            shift
            ;;
    esac
done

#############################################
# Validation
#############################################

# Description is required
if [[ -z "$DESCRIPTION" ]]; then
    echo "Error: Description is required" >&2
    echo "" >&2
    usage >&2
    exit 1
fi

# Validate plan file if provided
if [[ -n "$PLAN_FILE" ]] && [[ ! -f "$PLAN_FILE" ]]; then
    echo "Error: Plan file not found: $PLAN_FILE" >&2
    exit 1
fi

#############################################
# Auto-detect Base SHA
#############################################

auto_detect_base() {
    # Try origin/main first
    if git rev-parse origin/main &>/dev/null; then
        git merge-base origin/main HEAD 2>/dev/null
        return
    fi

    # Try origin/master
    if git rev-parse origin/master &>/dev/null; then
        git merge-base origin/master HEAD 2>/dev/null
        return
    fi

    # Try main (local)
    if git rev-parse main &>/dev/null; then
        git merge-base main HEAD 2>/dev/null
        return
    fi

    # Try master (local)
    if git rev-parse master &>/dev/null; then
        git merge-base master HEAD 2>/dev/null
        return
    fi

    # Fallback to HEAD~1
    git rev-parse HEAD~1 2>/dev/null || echo ""
}

if [[ -z "$BASE_SHA" ]]; then
    BASE_SHA=$(auto_detect_base)
    if [[ -z "$BASE_SHA" ]]; then
        echo "Error: Could not auto-detect base SHA. Use --base=SHA to specify." >&2
        exit 1
    fi
    echo "Auto-detected base: $BASE_SHA ($(git log -1 --format='%s' "$BASE_SHA" 2>/dev/null | head -c 50))" >&2
fi

# Resolve HEAD to actual SHA
HEAD_SHA=$(git rev-parse "$HEAD_SHA" 2>/dev/null)
if [[ -z "$HEAD_SHA" ]]; then
    echo "Error: Could not resolve head SHA" >&2
    exit 1
fi

#############################################
# Check for changes
#############################################

# Verify there are actual changes between base and head
CHANGED_FILES=$(git diff --name-only "$BASE_SHA" "$HEAD_SHA" 2>/dev/null || echo "")
if [[ -z "$CHANGED_FILES" ]]; then
    echo "No changes between $BASE_SHA and $HEAD_SHA - nothing to review." >&2
    exit 0
fi

FILE_COUNT=$(echo "$CHANGED_FILES" | wc -l)
echo "Reviewing $FILE_COUNT changed files" >&2

#############################################
# Dry Run
#############################################

if [[ "$DRY_RUN" == true ]]; then
    echo "" >&2
    echo "=== Dry Run ===" >&2
    echo "Base SHA: $BASE_SHA" >&2
    echo "Head SHA: $HEAD_SHA" >&2
    echo "Description: $DESCRIPTION" >&2
    [[ -n "$PLAN_FILE" ]] && echo "Plan file: $PLAN_FILE" >&2
    echo "" >&2
    echo "Changed files:" >&2
    echo "$CHANGED_FILES" >&2
    echo "" >&2
    echo "Would run:" >&2
    echo "  $SCRIPT_DIR/consensus-synthesis.sh \\" >&2
    echo "    --mode=code-review \\" >&2
    echo "    --base-sha=\"$BASE_SHA\" \\" >&2
    echo "    --head-sha=\"$HEAD_SHA\" \\" >&2
    echo "    --description=\"$DESCRIPTION\"" >&2
    [[ -n "$PLAN_FILE" ]] && echo "    --plan-file=\"$PLAN_FILE\"" >&2
    exit 0
fi

#############################################
# Execute Consensus Review
#############################################

echo "" >&2
echo "Starting multi-agent consensus review..." >&2
echo "Base: $BASE_SHA" >&2
echo "Head: $HEAD_SHA" >&2
echo "" >&2

# Build command
CMD=("$SCRIPT_DIR/consensus-synthesis.sh"
    "--mode=code-review"
    "--base-sha=$BASE_SHA"
    "--head-sha=$HEAD_SHA"
    "--description=$DESCRIPTION")

if [[ -n "$PLAN_FILE" ]]; then
    CMD+=("--plan-file=$PLAN_FILE")
fi

# Execute
exec "${CMD[@]}"
