#!/usr/bin/env bash
set -euo pipefail

# consensus-synthesis.sh
# Two-stage consensus synthesis for multi-agent analysis
# Stage 1: Parallel independent analysis from Claude, Gemini, Codex
# Stage 2: Chairman synthesizes consensus from all responses
#
# SETUP REQUIREMENTS:
# - curl: HTTP client for API calls
# - jq: JSON processor for parsing API responses
# - ANTHROPIC_API_KEY: Environment variable with Anthropic API key
# - GEMINI_API_KEY: Environment variable with Google Gemini API key
# - OPENAI_API_KEY: Environment variable with OpenAI API key (for Codex)

#############################################
# Environment Setup
#############################################

# Source ~/.env if it exists and API keys are missing
if [[ -f ~/.env ]]; then
    if [[ -z "${ANTHROPIC_API_KEY:-}" ]] || [[ -z "${GEMINI_API_KEY:-}" ]] || [[ -z "${GOOGLE_API_KEY:-}" ]] || [[ -z "${OPENAI_API_KEY:-}" ]]; then
        set +u  # Temporarily allow unset variables
        # shellcheck disable=SC1090
        source ~/.env 2>/dev/null || true
        set -u  # Re-enable unset variable checking
    fi
fi

#############################################
# Usage and Help
#############################################

usage() {
    cat <<EOF
Usage: consensus-synthesis.sh [OPTIONS]

Two-stage consensus synthesis for multi-agent code review and analysis.

MODES:
  --mode=code-review       Review code changes between two commits
  --mode=general-prompt    Analyze a general question with context

CODE REVIEW MODE OPTIONS:
  --base-sha=SHA          Base commit SHA (required)
  --head-sha=SHA          Head commit SHA (required)
  --description=TEXT      Change description (required)
  --plan-file=PATH        Optional: Path to implementation plan file

GENERAL PROMPT MODE OPTIONS:
  --prompt=TEXT           Question or prompt to analyze (required)
  --context=TEXT          Optional: Additional context for analysis

COMMON OPTIONS:
  --stage1-timeout=SEC    Stage 1 timeout in seconds (default: 60)
  --stage2-timeout=SEC    Stage 2 timeout in seconds (default: 60)
  --dry-run               Parse arguments and validate, but don't execute
  --help                  Show this help message

ENVIRONMENT VARIABLES:
  Required for agent access (at least one):
    ANTHROPIC_API_KEY         API key for Claude agent
    GEMINI_API_KEY            API key for Gemini agent
    OPENAI_API_KEY            API key for OpenAI Codex agent

  Optional configuration:
    ANTHROPIC_MODEL           Claude model (default: claude-opus-4-5-20251101)
    ANTHROPIC_MAX_TOKENS      Max tokens for Claude (default: 16000)
    GEMINI_MODEL              Gemini model (default: gemini-3-pro-preview)
    OPENAI_MODEL              OpenAI model (default: gpt-5.1-codex-max)
    OPENAI_MAX_TOKENS         Max tokens for OpenAI (default: 16000)
    CONSENSUS_STAGE1_TIMEOUT  Stage 1 timeout in seconds (default: 60)
    CONSENSUS_STAGE2_TIMEOUT  Stage 2 timeout in seconds (default: 60)

EXAMPLES:
  # Code review
  consensus-synthesis.sh --mode=code-review \\
    --base-sha=abc123 \\
    --head-sha=def456 \\
    --description="Add authentication" \\
    --plan-file=docs/plans/auth.md

  # General prompt
  consensus-synthesis.sh --mode=general-prompt \\
    --prompt="What could go wrong with this design?" \\
    --context="\$(cat design.md)"

OUTPUT:
  - Console: Progress updates and final consensus
  - File: Detailed breakdown saved to /tmp/consensus-XXXXXX.md

EOF
}

#############################################
# Argument Parsing
#############################################

# Initialize variables
MODE=""
BASE_SHA=""
HEAD_SHA=""
DESCRIPTION=""
PLAN_FILE=""
PROMPT=""
CONTEXT=""
DRY_RUN=false

# Timeout configuration (in seconds)
# Can be overridden via environment variables or CLI flags
STAGE1_TIMEOUT="${CONSENSUS_STAGE1_TIMEOUT:-60}"
STAGE2_TIMEOUT="${CONSENSUS_STAGE2_TIMEOUT:-60}"

# Parse arguments
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
        --description=*)
            DESCRIPTION="${1#*=}"
            shift
            ;;
        --plan-file=*)
            PLAN_FILE="${1#*=}"
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
        --stage1-timeout=*)
            STAGE1_TIMEOUT="${1#*=}"
            shift
            ;;
        --stage2-timeout=*)
            STAGE2_TIMEOUT="${1#*=}"
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
        *)
            echo "Error: Unknown argument: $1" >&2
            echo "" >&2
            usage >&2
            exit 1
            ;;
    esac
done

#############################################
# Validation
#############################################

# Validate mode is provided
if [[ -z "$MODE" ]]; then
    echo "Error: --mode is required" >&2
    echo "" >&2
    usage >&2
    exit 1
fi

# Validate mode value
if [[ "$MODE" != "code-review" && "$MODE" != "general-prompt" ]]; then
    echo "Error: Invalid mode '$MODE'. Must be 'code-review' or 'general-prompt'" >&2
    echo "" >&2
    usage >&2
    exit 1
fi

# Validate mode-specific required arguments
if [[ "$MODE" == "code-review" ]]; then
    if [[ -z "$BASE_SHA" ]]; then
        echo "Error: --base-sha is required for code-review mode" >&2
        echo "" >&2
        usage >&2
        exit 1
    fi

    if [[ -z "$HEAD_SHA" ]]; then
        echo "Error: --head-sha is required for code-review mode" >&2
        echo "" >&2
        usage >&2
        exit 1
    fi

    if [[ -z "$DESCRIPTION" ]]; then
        echo "Error: --description is required for code-review mode" >&2
        echo "" >&2
        usage >&2
        exit 1
    fi
elif [[ "$MODE" == "general-prompt" ]]; then
    if [[ -z "$PROMPT" ]]; then
        echo "Error: --prompt is required for general-prompt mode" >&2
        echo "" >&2
        usage >&2
        exit 1
    fi
fi

#############################################
# Dry Run Exit
#############################################

if [[ "$DRY_RUN" == true ]]; then
    echo "Dry run: Arguments validated successfully"
    echo "Mode: $MODE"
    if [[ "$MODE" == "code-review" ]]; then
        echo "Base SHA: $BASE_SHA"
        echo "Head SHA: $HEAD_SHA"
        echo "Description: $DESCRIPTION"
        [[ -n "$PLAN_FILE" ]] && echo "Plan file: $PLAN_FILE"
    else
        echo "Prompt: $PROMPT"
        [[ -n "$CONTEXT" ]] && echo "Context: (provided)"
    fi
    exit 0
fi

#############################################
# Stage 1: Helper Functions
#############################################

# Context size limit (10KB = 10240 bytes)
CONTEXT_SIZE_LIMIT=10240

# Check context size and warn if >10KB
check_context_size() {
    local context="$1"
    local size=${#context}

    if [[ $size -gt $CONTEXT_SIZE_LIMIT ]]; then
        echo "Warning: Context size is ${size} bytes (>10KB). Consider truncating." >&2
    fi
}

# Build Stage 1 prompt for code review mode
build_code_review_prompt() {
    local base_sha="$1"
    local head_sha="$2"
    local description="$3"
    local plan_file="$4"

    # Get diff
    local diff_output
    diff_output=$(git diff "$base_sha" "$head_sha" 2>&1)
    if [[ $? -ne 0 ]]; then
        echo "Error: Failed to get git diff for $base_sha..$head_sha" >&2
        return 1
    fi

    # Get modified files
    local modified_files=$(git diff --name-only "$base_sha" "$head_sha" 2>&1)

    # Load plan if provided
    local plan_content=""
    if [[ -n "$plan_file" && -f "$plan_file" ]]; then
        plan_content=$(cat "$plan_file")
    fi

    # Build context
    local context="# Code Review - Stage 1 Independent Analysis

**Your Task:** Independently review these code changes and provide your analysis.

**Change Description:** $description

**Commits:** $base_sha..$head_sha

**Modified Files:**
$modified_files

"

    if [[ -n "$plan_content" ]]; then
        context+="**Implementation Plan:**
$plan_content

"
    fi

    context+="**Diff:**
\`\`\`diff
$diff_output
\`\`\`

**Instructions:**
Please provide your independent code review in the following format:

## Critical Issues
- [List critical issues, or write 'None']

## Important Issues
- [List important issues, or write 'None']

## Suggestions
- [List suggestions, or write 'None']

Focus on correctness, security, performance, and adherence to the plan (if provided).
"

    echo "$context"
}

# Build Stage 1 prompt for general prompt mode
build_general_prompt_prompt() {
    local prompt="$1"
    local context="$2"

    local full_prompt="# General Analysis - Stage 1 Independent Analysis

**Your Task:** Independently analyze this question and provide your perspective.

**Question:**
$prompt

"

    if [[ -n "$context" ]]; then
        full_prompt+="**Context:**
$context

"
    fi

    full_prompt+="**Instructions:**
Please provide your independent analysis in the following format:

## Strong Points
- [List strong arguments/points, or write 'None']

## Moderate Points
- [List moderate arguments/points, or write 'None']

## Weak Points / Concerns
- [List weak points or concerns, or write 'None']

Provide thoughtful, independent analysis.
"

    echo "$full_prompt"
}

# Run Claude agent
run_claude() {
    local prompt="$1"
    local output_file="$2"

    # Check if API key is available
    if [[ -z "${ANTHROPIC_API_KEY:-}" ]]; then
        echo "CLAUDE_API_KEY_MISSING" > "$output_file"
        return 1
    fi

    # Check if curl is available
    if ! command -v curl &> /dev/null; then
        echo "CLAUDE_CURL_NOT_AVAILABLE" > "$output_file"
        return 1
    fi

    # Check if jq is available
    if ! command -v jq &> /dev/null; then
        echo "CLAUDE_JQ_NOT_AVAILABLE" > "$output_file"
        return 1
    fi

    # Prepare the API request
    local model="${ANTHROPIC_MODEL:-claude-opus-4-5-20251101}"
    local max_tokens="${ANTHROPIC_MAX_TOKENS:-16000}"

    # Escape the prompt for JSON
    local escaped_prompt=$(echo "$prompt" | jq -Rs .)

    # Build JSON payload
    local json_payload=$(cat <<EOF
{
  "model": "$model",
  "max_tokens": $max_tokens,
  "messages": [
    {
      "role": "user",
      "content": $escaped_prompt
    }
  ]
}
EOF
)

    # Make API call with timeout
    local response
    response=$(curl -s --max-time 50 \
        -X POST "https://api.anthropic.com/v1/messages" \
        -H "x-api-key: $ANTHROPIC_API_KEY" \
        -H "anthropic-version: 2023-06-01" \
        -H "content-type: application/json" \
        -d "$json_payload" 2>&1)

    local curl_exit=$?

    # Check for curl errors
    if [[ $curl_exit -ne 0 ]]; then
        echo "CLAUDE_CURL_ERROR: Exit code $curl_exit" > "$output_file"
        return 1
    fi

    # Extract content from response
    local content
    content=$(echo "$response" | jq -r '.content[0].text // empty' 2>/dev/null)

    # Check if we got valid content
    if [[ -z "$content" ]]; then
        # Check for API error - try multiple error paths
        local error_msg
        error_msg=$(echo "$response" | jq -r '.error.message // .error // "Unknown error"' 2>/dev/null)

        # If still empty or just shows the response itself, capture more context
        if [[ "$error_msg" == "Unknown error" ]] || [[ -z "$error_msg" ]]; then
            # Try to extract any useful info from the response
            error_msg=$(echo "$response" | jq -r 'if .error then .error else . end' 2>/dev/null | head -c 200)
        fi

        echo "CLAUDE_API_ERROR: $error_msg" > "$output_file"
        return 1
    fi

    # Write successful response
    echo "$content" > "$output_file"
    return 0
}

# Run Gemini agent
run_gemini() {
    local prompt="$1"
    local output_file="$2"

    # Check if API key is available (try both GEMINI_API_KEY and GOOGLE_API_KEY)
    local api_key="${GEMINI_API_KEY:-${GOOGLE_API_KEY:-}}"
    if [[ -z "$api_key" ]]; then
        echo "GEMINI_API_KEY_MISSING" > "$output_file"
        return 1
    fi

    # Check if curl is available
    if ! command -v curl &> /dev/null; then
        echo "GEMINI_CURL_NOT_AVAILABLE" > "$output_file"
        return 1
    fi

    # Check if jq is available
    if ! command -v jq &> /dev/null; then
        echo "GEMINI_JQ_NOT_AVAILABLE" > "$output_file"
        return 1
    fi

    # Prepare the API request
    local model="${GEMINI_MODEL:-gemini-3-pro-preview}"

    # Escape the prompt for JSON
    local escaped_prompt=$(echo "$prompt" | jq -Rs .)

    # Build JSON payload
    local json_payload=$(cat <<EOF
{
  "contents": [{
    "parts": [{
      "text": $escaped_prompt
    }]
  }]
}
EOF
)

    # Make API call with timeout
    local response
    response=$(curl -s --max-time 50 \
        -X POST "https://generativelanguage.googleapis.com/v1beta/models/${model}:generateContent?key=${api_key}" \
        -H "Content-Type: application/json" \
        -d "$json_payload" 2>&1)

    local curl_exit=$?

    # Check for curl errors
    if [[ $curl_exit -ne 0 ]]; then
        echo "GEMINI_CURL_ERROR: Exit code $curl_exit" > "$output_file"
        return 1
    fi

    # Extract content from response
    local content
    content=$(echo "$response" | jq -r '.candidates[0].content.parts[0].text // empty' 2>/dev/null)

    # Check if we got valid content
    if [[ -z "$content" ]]; then
        # Check for API error
        local error_msg
        error_msg=$(echo "$response" | jq -r '.error.message // "Unknown error"' 2>/dev/null)
        echo "GEMINI_API_ERROR: $error_msg" > "$output_file"
        return 1
    fi

    # Write successful response
    echo "$content" > "$output_file"
    return 0
}

# Run Codex agent (via OpenAI API)
run_codex() {
    local prompt="$1"
    local output_file="$2"

    # Check if API key is available
    if [[ -z "${OPENAI_API_KEY:-}" ]]; then
        echo "CODEX_API_KEY_MISSING" > "$output_file"
        return 1
    fi

    # Check if curl is available
    if ! command -v curl &> /dev/null; then
        echo "CODEX_CURL_NOT_AVAILABLE" > "$output_file"
        return 1
    fi

    # Check if jq is available
    if ! command -v jq &> /dev/null; then
        echo "CODEX_JQ_NOT_AVAILABLE" > "$output_file"
        return 1
    fi

    # Prepare the API request
    # Note: gpt-5.1-codex-max uses the Responses API endpoint (for agentic coding tasks)
    local model="${OPENAI_MODEL:-gpt-5.1-codex-max}"
    local max_tokens="${OPENAI_MAX_TOKENS:-16000}"

    # Escape the prompt for JSON
    local escaped_prompt=$(echo "$prompt" | jq -Rs .)

    # Determine which endpoint to use
    local endpoint
    local json_payload
    local is_responses_api=false

    if [[ "$model" =~ ^gpt-5.*-codex ]]; then
        # Use Responses API endpoint for Codex models
        # Note: Responses API does not support max_tokens parameter
        is_responses_api=true
        endpoint="https://api.openai.com/v1/responses"
        json_payload=$(cat <<EOF
{
  "model": "$model",
  "input": [
    {
      "role": "user",
      "content": $escaped_prompt
    }
  ]
}
EOF
)
    elif [[ "$model" =~ ^(gpt-4|gpt-3.5-turbo|o1|o3) ]]; then
        # Use chat completions endpoint
        endpoint="https://api.openai.com/v1/chat/completions"
        json_payload=$(cat <<EOF
{
  "model": "$model",
  "max_tokens": $max_tokens,
  "messages": [
    {
      "role": "user",
      "content": $escaped_prompt
    }
  ]
}
EOF
)
    else
        # Use completions endpoint as fallback
        endpoint="https://api.openai.com/v1/completions"
        json_payload=$(cat <<EOF
{
  "model": "$model",
  "max_tokens": $max_tokens,
  "prompt": $escaped_prompt
}
EOF
)
    fi

    # Make API call with timeout
    local response
    response=$(curl -s --max-time 50 \
        -X POST "$endpoint" \
        -H "Authorization: Bearer $OPENAI_API_KEY" \
        -H "Content-Type: application/json" \
        -d "$json_payload" 2>&1)

    local curl_exit=$?

    # Check for curl errors
    if [[ $curl_exit -ne 0 ]]; then
        echo "CODEX_CURL_ERROR: Exit code $curl_exit" > "$output_file"
        return 1
    fi

    # Extract content from response (different paths for responses/chat/completion APIs)
    local content
    if [[ "$is_responses_api" == "true" ]]; then
        # Responses API format: output[].content[].text
        content=$(echo "$response" | jq -r '.output[] | select(.type == "message") | .content[0].text // empty' 2>/dev/null)
    elif [[ "$model" =~ ^(gpt-4|gpt-3.5-turbo|o1|o3) ]]; then
        # Chat completions format
        content=$(echo "$response" | jq -r '.choices[0].message.content // empty' 2>/dev/null)
    else
        # Completions format
        content=$(echo "$response" | jq -r '.choices[0].text // empty' 2>/dev/null)
    fi

    # Check if we got valid content
    if [[ -z "$content" ]]; then
        # Check for API error
        local error_msg
        error_msg=$(echo "$response" | jq -r '.error.message // "Unknown error"' 2>/dev/null)
        echo "CODEX_API_ERROR: $error_msg" > "$output_file"
        return 1
    fi

    # Write successful response
    echo "$content" > "$output_file"
    return 0
}

# Execute Stage 1: Parallel agent execution
execute_stage1() {
    local prompt="$1"

    echo "Stage 1: Launching parallel agent analysis..." >&2

    # Check context size
    check_context_size "$prompt"

    # Create temp files for agent outputs
    local claude_output=$(mktemp)
    local gemini_output=$(mktemp)
    local codex_output=$(mktemp)

    # Track PIDs for background processes
    local claude_pid=""
    local gemini_pid=""
    local codex_pid=""

    # Launch agents in parallel (background)
    # Note: Wrap in subshells to ensure proper backgrounding
    ( run_claude "$prompt" "$claude_output" ) &
    claude_pid=$!

    ( run_gemini "$prompt" "$gemini_output" ) &
    gemini_pid=$!

    ( run_codex "$prompt" "$codex_output" ) &
    codex_pid=$!

    # Wait for all agents with timeout
    echo "  Waiting for agents (${STAGE1_TIMEOUT}s timeout)..." >&2

    local timeout_duration=$STAGE1_TIMEOUT
    local start_time=$(date +%s)
    local stage1_start_ns=$(date +%s.%N)
    local claude_exit=1
    local gemini_exit=1
    local codex_exit=1
    local claude_done=false
    local gemini_done=false
    local codex_done=false

    # Poll for completion with timeout
    while true; do
        local current_time=$(date +%s)
        local elapsed=$((current_time - start_time))

        # Check if timeout exceeded
        if [[ $elapsed -ge $timeout_duration ]]; then
            echo "  Timeout reached (${timeout_duration}s)" >&2
            # Kill any remaining processes (use SIGKILL to ensure termination)
            kill -9 $claude_pid 2>/dev/null || true
            kill -9 $gemini_pid 2>/dev/null || true
            kill -9 $codex_pid 2>/dev/null || true
            # Also kill any child processes
            pkill -9 -P $claude_pid 2>/dev/null || true
            pkill -9 -P $gemini_pid 2>/dev/null || true
            pkill -9 -P $codex_pid 2>/dev/null || true
            break
        fi

        # Check Claude
        if [[ "$claude_done" == false ]] && ! kill -0 $claude_pid 2>/dev/null; then
            wait $claude_pid 2>/dev/null || true
            claude_exit=$?
            claude_done=true
        fi

        # Check Gemini
        if [[ "$gemini_done" == false ]] && ! kill -0 $gemini_pid 2>/dev/null; then
            wait $gemini_pid 2>/dev/null || true
            gemini_exit=$?
            gemini_done=true
        fi

        # Check Codex
        if [[ "$codex_done" == false ]] && ! kill -0 $codex_pid 2>/dev/null; then
            wait $codex_pid 2>/dev/null || true
            codex_exit=$?
            codex_done=true
        fi

        # If all done, break early
        if [[ "$claude_done" == true ]] && [[ "$gemini_done" == true ]] && [[ "$codex_done" == true ]]; then
            break
        fi

        # Sleep briefly before next check
        sleep 0.1
    done

    # Read agent responses
    local claude_response=$(cat "$claude_output" 2>/dev/null || echo "")
    local gemini_response=$(cat "$gemini_output" 2>/dev/null || echo "")
    local codex_response=$(cat "$codex_output" 2>/dev/null || echo "")

    # Track success/failure
    local agents_succeeded=0
    local claude_status="failed"
    local gemini_status="failed"
    local codex_status="failed"

    # Check Claude status (reject error markers)
    if [[ $claude_exit -eq 0 ]] && [[ -n "$claude_response" ]] && ! echo "$claude_response" | grep -qE "^CLAUDE_(API_KEY_MISSING|CURL_ERROR|JQ_NOT_AVAILABLE|CURL_NOT_AVAILABLE|API_ERROR)"; then
        claude_status="success"
        agents_succeeded=$((agents_succeeded + 1))
        echo "  Claude: SUCCESS" >&2
    else
        if echo "$claude_response" | grep -q "CLAUDE_API_KEY_MISSING"; then
            echo "  Claude: API KEY MISSING" >&2
        elif echo "$claude_response" | grep -q "CLAUDE_API_ERROR"; then
            echo "  Claude: API ERROR" >&2
        else
            echo "  Claude: FAILED" >&2
        fi
    fi

    # Check Gemini status (reject error markers)
    if [[ $gemini_exit -eq 0 ]] && [[ -n "$gemini_response" ]] && ! echo "$gemini_response" | grep -qE "^GEMINI_(API_KEY_MISSING|CURL_ERROR|JQ_NOT_AVAILABLE|CURL_NOT_AVAILABLE|API_ERROR)"; then
        gemini_status="success"
        agents_succeeded=$((agents_succeeded + 1))
        echo "  Gemini: SUCCESS" >&2
    else
        if echo "$gemini_response" | grep -q "GEMINI_API_KEY_MISSING"; then
            echo "  Gemini: API KEY MISSING" >&2
        elif echo "$gemini_response" | grep -q "GEMINI_API_ERROR"; then
            echo "  Gemini: API ERROR" >&2
        else
            echo "  Gemini: FAILED" >&2
        fi
    fi

    # Check Codex status (reject error markers)
    if [[ $codex_exit -eq 0 ]] && [[ -n "$codex_response" ]] && ! echo "$codex_response" | grep -qE "^CODEX_(API_KEY_MISSING|CURL_ERROR|JQ_NOT_AVAILABLE|CURL_NOT_AVAILABLE|API_ERROR|MCP_REQUIRED)"; then
        codex_status="success"
        agents_succeeded=$((agents_succeeded + 1))
        echo "  Codex: SUCCESS" >&2
    else
        if echo "$codex_response" | grep -q "CODEX_API_KEY_MISSING"; then
            echo "  Codex: API KEY MISSING" >&2
        elif echo "$codex_response" | grep -q "CODEX_API_ERROR"; then
            echo "  Codex: API ERROR" >&2
        elif echo "$codex_response" | grep -q "CODEX_MCP_REQUIRED"; then
            echo "  Codex: NOT AVAILABLE (needs OpenAI API key)" >&2
        else
            echo "  Codex: FAILED" >&2
        fi
    fi

    echo "  Agents completed: $agents_succeeded/3 succeeded" >&2

    # Cleanup temp files
    rm -f "$claude_output" "$gemini_output" "$codex_output"

    # Check if at least one agent succeeded
    if [[ $agents_succeeded -eq 0 ]]; then
        echo "Error: All agents failed (0/3 succeeded)" >&2
        return 1
    fi

    # Export results for Stage 2 (stored in global variables for now)
    STAGE1_CLAUDE_RESPONSE="$claude_response"
    STAGE1_GEMINI_RESPONSE="$gemini_response"
    STAGE1_CODEX_RESPONSE="$codex_response"
    STAGE1_CLAUDE_STATUS="$claude_status"
    STAGE1_GEMINI_STATUS="$gemini_status"
    STAGE1_CODEX_STATUS="$codex_status"
    STAGE1_AGENTS_SUCCEEDED=$agents_succeeded

    local stage1_end_ns=$(date +%s.%N)
    local stage1_duration=$(echo "$stage1_end_ns - $stage1_start_ns" | bc)
    echo "  Stage 1 duration: ${stage1_duration}s" >&2

    return 0
}

#############################################
# Stage 2: Chairman Synthesis
#############################################

# Build Stage 2 chairman prompt for code review mode
build_code_review_chairman_prompt() {
    local description="$1"
    local modified_files="$2"
    local claude_response="$3"
    local gemini_response="$4"
    local codex_response="$5"
    local claude_status="$6"
    local gemini_status="$7"
    local codex_status="$8"
    local agents_succeeded="$9"

    local prompt="# Code Review Consensus - Stage 2 Chairman Synthesis

**Your Task:** Compile a consensus code review from multiple independent reviewers.

**CRITICAL:** Report all issues mentioned by any reviewer. Group similar issues together, but if reviewers disagree about an issue, report the disagreement explicitly.

**Change Description:** $description

**Modified Files:**
$modified_files

**Reviews Received ($agents_succeeded of 3):**

"

    if [[ "$claude_status" == "success" ]]; then
        prompt+="--- Claude Review ---
$claude_response

"
    fi

    if [[ "$gemini_status" == "success" ]]; then
        prompt+="--- Gemini Review ---
$gemini_response

"
    fi

    if [[ "$codex_status" == "success" ]]; then
        prompt+="--- Codex Review ---
$codex_response

"
    fi

    prompt+="**Instructions:**
Compile a consensus report with three tiers:

## High Priority - Multiple Reviewers Agree
[Issues mentioned by 2+ reviewers - group similar issues]
- [SEVERITY] Description
  - Reviewer A: \"specific quote\"
  - Reviewer B: \"specific quote\"

## Medium Priority - Single Reviewer, Significant
[Important/Critical issues from single reviewer]
- [SEVERITY] Description
  - Reviewer: \"quote\"

## Consider - Suggestions
[Suggestions from any reviewer]
- [SUGGESTION] Description
  - Reviewer: \"quote\"

## Final Recommendation
- If High Priority issues exist → \"Address high priority issues before merging\"
- If only Medium Priority → \"Review medium priority concerns\"
- If only Consider tier → \"Optional improvements suggested\"
- If no issues → \"All reviewers approve - safe to merge\"

Be direct. Group similar issues but preserve different perspectives.
"

    echo "$prompt"
}

# Build Stage 2 chairman prompt for general prompt mode
build_general_chairman_prompt() {
    local original_prompt="$1"
    local claude_response="$2"
    local gemini_response="$3"
    local codex_response="$4"
    local claude_status="$5"
    local gemini_status="$6"
    local codex_status="$7"
    local agents_succeeded="$8"

    local prompt="# General Analysis Consensus - Stage 2 Chairman Synthesis

**Your Task:** Compile consensus from multiple independent analyses.

**CRITICAL:** If analyses disagree or conflict, highlight disagreements explicitly. Do NOT smooth over conflicts. Conflicting views are valuable.

**Original Question:**
$original_prompt

**Analyses Received ($agents_succeeded of 3):**

"

    if [[ "$claude_status" == "success" ]]; then
        prompt+="--- Claude Analysis ---
$claude_response

"
    fi

    if [[ "$gemini_status" == "success" ]]; then
        prompt+="--- Gemini Analysis ---
$gemini_response

"
    fi

    if [[ "$codex_status" == "success" ]]; then
        prompt+="--- Codex Analysis ---
$codex_response

"
    fi

    prompt+="**Instructions:**
Provide final consensus:

## Areas of Agreement
[What do reviewers agree on?]

## Areas of Disagreement
[Where do perspectives differ? Be explicit about conflicts.]

## Confidence Level
High / Medium / Low

## Synthesized Recommendation
[Incorporate all perspectives, noting disagreements where they exist]

Be direct. Disagreement is valuable - report it clearly.
"

    echo "$prompt"
}

# Run chairman with given agent function
run_chairman_agent() {
    local agent_name="$1"
    local prompt="$2"
    local output_file="$3"

    echo "  Trying $agent_name as chairman..." >&2

    case "$agent_name" in
        "Claude")
            run_claude "$prompt" "$output_file"
            return $?
            ;;
        "Gemini")
            run_gemini "$prompt" "$output_file"
            return $?
            ;;
        "Codex")
            run_codex "$prompt" "$output_file"
            return $?
            ;;
        *)
            echo "Error: Unknown agent $agent_name" >&2
            return 1
            ;;
    esac
}

# Execute Stage 2: Chairman synthesis with fallback
execute_stage2() {
    local chairman_prompt="$1"

    echo "" >&2
    echo "Stage 2: Chairman synthesis..." >&2

    # Create temp file for chairman output
    local chairman_output=$(mktemp)

    # Try chairman agents in order: Claude → Gemini → Codex
    local chairman_agents=("Claude" "Gemini" "Codex")
    local chairman_succeeded=false
    local chairman_name=""
    local chairman_response=""

    local stage2_start_ns=$(date +%s.%N)

    for agent in "${chairman_agents[@]}"; do
        # Run chairman agent with timeout
        local timeout_duration=$STAGE2_TIMEOUT
        local start_time=$(date +%s)
        local agent_pid=""

        # Launch chairman agent in background
        ( run_chairman_agent "$agent" "$chairman_prompt" "$chairman_output" ) &
        agent_pid=$!

        # Wait for completion with timeout
        local agent_done=false
        local agent_exit=1

        while true; do
            local current_time=$(date +%s)
            local elapsed=$((current_time - start_time))

            # Check if timeout exceeded
            if [[ $elapsed -ge $timeout_duration ]]; then
                echo "  $agent: TIMEOUT (${timeout_duration}s)" >&2
                # Kill process and children
                kill -9 $agent_pid 2>/dev/null || true
                pkill -9 -P $agent_pid 2>/dev/null || true
                break
            fi

            # Check if agent completed
            if ! kill -0 $agent_pid 2>/dev/null; then
                wait $agent_pid 2>/dev/null || true
                agent_exit=$?
                agent_done=true
                break
            fi

            # Sleep briefly before next check
            sleep 0.1
        done

        # Check if agent succeeded
        if [[ "$agent_done" == true ]] && [[ $agent_exit -eq 0 ]]; then
            chairman_response=$(cat "$chairman_output" 2>/dev/null || echo "")

            # Validate response is not empty and not an error message
            if [[ -n "$chairman_response" ]] && \
               ! echo "$chairman_response" | grep -q "GEMINI_NOT_AVAILABLE\|GEMINI_TIMEOUT\|CODEX_MCP_REQUIRED"; then
                chairman_succeeded=true
                chairman_name="$agent"
                echo "  $agent: SUCCESS" >&2
                break
            else
                echo "  $agent: FAILED (invalid response)" >&2
            fi
        elif [[ "$agent_done" == false ]]; then
            # Timeout already reported above
            :
        else
            echo "  $agent: FAILED" >&2
        fi
    done

    # Cleanup temp file
    rm -f "$chairman_output"

    # Check if chairman succeeded
    if [[ "$chairman_succeeded" == false ]]; then
        echo "Error: All chairman agents failed" >&2
        return 1
    fi

    # Export results
    STAGE2_CHAIRMAN_NAME="$chairman_name"
    STAGE2_CHAIRMAN_RESPONSE="$chairman_response"

    local stage2_end_ns=$(date +%s.%N)
    local stage2_duration=$(echo "$stage2_end_ns - $stage2_start_ns" | bc)
    echo "  Stage 2 duration: ${stage2_duration}s" >&2

    return 0
}

#############################################
# Main Execution
#############################################

# Build Stage 1 prompt based on mode
echo "Building Stage 1 prompt for mode: $MODE" >&2

STAGE1_PROMPT=""

if [[ "$MODE" == "code-review" ]]; then
    STAGE1_PROMPT=$(build_code_review_prompt "$BASE_SHA" "$HEAD_SHA" "$DESCRIPTION" "$PLAN_FILE")
    if [[ $? -ne 0 ]]; then
        echo "Error: Failed to build code review prompt" >&2
        exit 1
    fi
elif [[ "$MODE" == "general-prompt" ]]; then
    STAGE1_PROMPT=$(build_general_prompt_prompt "$PROMPT" "$CONTEXT")
fi

# Execute Stage 1
execute_stage1 "$STAGE1_PROMPT"
if [[ $? -ne 0 ]]; then
    echo "Error: Stage 1 failed" >&2
    exit 1
fi

# Build Stage 2 chairman prompt based on mode
STAGE2_PROMPT=""

if [[ "$MODE" == "code-review" ]]; then
    # Get modified files for chairman prompt
    MODIFIED_FILES=$(git diff --name-only "$BASE_SHA" "$HEAD_SHA" 2>&1)

    STAGE2_PROMPT=$(build_code_review_chairman_prompt \
        "$DESCRIPTION" \
        "$MODIFIED_FILES" \
        "$STAGE1_CLAUDE_RESPONSE" \
        "$STAGE1_GEMINI_RESPONSE" \
        "$STAGE1_CODEX_RESPONSE" \
        "$STAGE1_CLAUDE_STATUS" \
        "$STAGE1_GEMINI_STATUS" \
        "$STAGE1_CODEX_STATUS" \
        "$STAGE1_AGENTS_SUCCEEDED")
elif [[ "$MODE" == "general-prompt" ]]; then
    STAGE2_PROMPT=$(build_general_chairman_prompt \
        "$PROMPT" \
        "$STAGE1_CLAUDE_RESPONSE" \
        "$STAGE1_GEMINI_RESPONSE" \
        "$STAGE1_CODEX_RESPONSE" \
        "$STAGE1_CLAUDE_STATUS" \
        "$STAGE1_GEMINI_STATUS" \
        "$STAGE1_CODEX_STATUS" \
        "$STAGE1_AGENTS_SUCCEEDED")
fi

# Execute Stage 2
execute_stage2 "$STAGE2_PROMPT"
if [[ $? -ne 0 ]]; then
    echo "Error: Stage 2 failed" >&2
    exit 1
fi

# Create output file with full context
OUTPUT_FILE=$(mktemp /tmp/consensus-XXXXXX.md)

# Write comprehensive output to file
cat > "$OUTPUT_FILE" <<EOF
# Multi-Agent Consensus Analysis

**Mode:** $MODE
**Date:** $(date '+%Y-%m-%d %H:%M:%S')
**Agents Succeeded:** $STAGE1_AGENTS_SUCCEEDED/3
**Chairman:** $STAGE2_CHAIRMAN_NAME

---

EOF

# Add mode-specific context
if [[ "$MODE" == "code-review" ]]; then
    cat >> "$OUTPUT_FILE" <<EOF
## Change Description

$DESCRIPTION

## Commits

$BASE_SHA..$HEAD_SHA

## Modified Files

$MODIFIED_FILES

---

EOF
else
    cat >> "$OUTPUT_FILE" <<EOF
## Original Question

$PROMPT

EOF
    if [[ -n "$CONTEXT" ]]; then
        cat >> "$OUTPUT_FILE" <<EOF

## Context

$CONTEXT

EOF
    fi
    cat >> "$OUTPUT_FILE" <<EOF

---

EOF
fi

# Add Stage 1 responses
cat >> "$OUTPUT_FILE" <<EOF
## Stage 1: Independent Analyses

EOF

if [[ "$STAGE1_CLAUDE_STATUS" == "success" ]]; then
    cat >> "$OUTPUT_FILE" <<EOF
### Claude Review

$STAGE1_CLAUDE_RESPONSE

---

EOF
fi

if [[ "$STAGE1_GEMINI_STATUS" == "success" ]]; then
    cat >> "$OUTPUT_FILE" <<EOF
### Gemini Review

$STAGE1_GEMINI_RESPONSE

---

EOF
fi

if [[ "$STAGE1_CODEX_STATUS" == "success" ]]; then
    cat >> "$OUTPUT_FILE" <<EOF
### Codex Review

$STAGE1_CODEX_RESPONSE

---

EOF
fi

# Add Stage 2 consensus
cat >> "$OUTPUT_FILE" <<EOF
## Stage 2: Chairman Consensus (by $STAGE2_CHAIRMAN_NAME)

$STAGE2_CHAIRMAN_RESPONSE

EOF

# Display final consensus to console
echo "" >&2
echo "========================================" >&2
echo "CONSENSUS COMPLETE" >&2
echo "========================================" >&2
echo "" >&2

echo "$STAGE2_CHAIRMAN_RESPONSE"

echo "" >&2
echo "Detailed breakdown saved to: $OUTPUT_FILE" >&2

exit 0
