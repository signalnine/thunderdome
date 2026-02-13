#!/usr/bin/env bash
# Stuck detection for Ralph Loop (v1 - simple threshold)

STUCK_THRESHOLD=${RALPH_STUCK_THRESHOLD:-3}

is_stuck() {
    local state_file="${1:-.ralph_state.json}"
    local stuck_count=$(jq -r '.stuck_count' "$state_file" 2>/dev/null || echo 0)
    [ "$stuck_count" -ge "$STUCK_THRESHOLD" ]
}

get_stuck_directive() {
    cat << 'EOF'
## IMPORTANT: You Are Stuck

You have failed 3+ times with the same error. Your previous approach does not work.

You MUST try a fundamentally different approach:
- Different algorithm or data structure
- Different library or API
- Simplify the problem
- Break into smaller pieces

Do NOT repeat the same approach that failed.
EOF
}

increment_strategy_shift() {
    local state_file="${1:-.ralph_state.json}"
    local tmp=$(mktemp)
    jq '.strategy_shifts += 1' "$state_file" > "$tmp" && mv "$tmp" "$state_file"
}
