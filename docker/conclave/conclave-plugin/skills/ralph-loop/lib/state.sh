#!/usr/bin/env bash
# State file management for Ralph Loop
# Uses JSON for reliable parsing (not YAML with sed/grep)

STATE_FILE=".ralph_state.json"
CONTEXT_FILE=".ralph_context.md"

# Check jq is available
command -v jq >/dev/null 2>&1 || { echo "ERROR: jq required but not installed" >&2; exit 1; }

init_state() {
    local task_id="$1"
    local max_iter="${2:-5}"
    local timestamp=$(date -Iseconds)

    cat > "$STATE_FILE" << EOF
{
  "task_id": "$task_id",
  "iteration": 1,
  "max_iterations": $max_iter,
  "last_gate": "",
  "exit_code": 0,
  "error_hash": "",
  "timestamp": "$timestamp",
  "stuck_count": 0,
  "strategy_shifts": 0,
  "attempts": []
}
EOF

    # Separate context file for LLM consumption
    cat > "$CONTEXT_FILE" << EOF
# Ralph Loop Context: $task_id

## Status
- Iteration: 1 of $max_iter
- Last gate: (none yet)

## Previous Output
(First attempt - no previous output)
EOF
}

get_field() {
    local field="$1"
    jq -r ".$field" "$STATE_FILE" 2>/dev/null
}

get_iteration() { get_field "iteration"; }
get_max_iterations() { get_field "max_iterations"; }
get_stuck_count() { get_field "stuck_count"; }
get_error_hash() { get_field "error_hash"; }
get_task_id() { get_field "task_id"; }

set_field() {
    local field="$1"
    local value="$2"
    local tmp=$(mktemp)
    jq ".$field = $value" "$STATE_FILE" > "$tmp" && mv "$tmp" "$STATE_FILE"
}

update_state() {
    local gate="$1"
    local exit_code="$2"
    local output="$3"

    # Compute error hash from first 20 lines
    local new_hash=$(echo "$output" | head -20 | md5sum 2>/dev/null | cut -d' ' -f1 || echo "$output" | head -20 | md5 2>/dev/null)
    local old_hash=$(get_error_hash)
    local stuck=$(get_stuck_count)
    local iter=$(get_iteration)
    local timestamp=$(date -Iseconds)
    local shifts=$(jq -r '.strategy_shifts' "$STATE_FILE")

    # Check if stuck (same error hash)
    if [ "$new_hash" = "$old_hash" ] && [ -n "$old_hash" ]; then
        stuck=$((stuck + 1))
    else
        stuck=0
    fi

    # Truncate output to 100 lines for storage
    local truncated_output=$(echo "$output" | head -100)
    if [ $(echo "$output" | wc -l) -gt 100 ]; then
        truncated_output="$truncated_output
[... truncated, $(echo "$output" | wc -l) total lines ...]"
    fi

    # Update state atomically
    local tmp=$(mktemp)
    jq --arg gate "$gate" \
       --argjson exit_code "$exit_code" \
       --arg hash "$new_hash" \
       --arg ts "$timestamp" \
       --argjson stuck "$stuck" \
       --argjson iter "$iter" \
       --argjson shifts "$shifts" \
       --arg output "$truncated_output" \
       '.iteration = ($iter + 1) |
        .last_gate = $gate |
        .exit_code = $exit_code |
        .error_hash = $hash |
        .timestamp = $ts |
        .stuck_count = $stuck |
        .attempts += [{"iteration": $iter, "gate": $gate, "hash": ($hash[0:8]), "shift": ($shifts > 0)}]' \
       "$STATE_FILE" > "$tmp" && mv "$tmp" "$STATE_FILE"

    # Update human-readable context file
    cat > "$CONTEXT_FILE" << EOF
# Ralph Loop Context: $(get_task_id)

## Status
- Iteration: $((iter + 1)) of $(get_max_iterations)
- Last gate failed: $gate
- Stuck count: $stuck (threshold: 3)

## Last Error Output (verbatim)
\`\`\`
$truncated_output
\`\`\`

## Attempt History
$(jq -r '.attempts | .[-3:] | .[] | "- Iteration \(.iteration): \(.gate) failed (hash: \(.hash))"' "$STATE_FILE" 2>/dev/null || echo "(none)")
EOF
}

cleanup_state() {
    rm -f "$STATE_FILE" "$CONTEXT_FILE"
}

state_exists() {
    [ -f "$STATE_FILE" ]
}
