#!/usr/bin/env bash
# Plan parser for parallel-runner.sh
# Extracts tasks, dependencies, files, and computes execution waves

# Global arrays populated by parse_tasks()
declare -a TASK_IDS=()
declare -a TASK_NAMES=()
declare -A TASK_DEPS=()
declare -A TASK_FILES=()
declare -A TASK_WAVE=()
declare -a IMPLICIT_DEPS=()
MAX_WAVE=0

# Parse all tasks from a plan markdown file
# Populates: TASK_IDS, TASK_NAMES, TASK_DEPS, TASK_FILES
parse_tasks() {
    local plan_file="$1"

    TASK_IDS=()
    TASK_NAMES=()
    TASK_DEPS=()
    TASK_FILES=()

    local current_id=""
    local in_task=false
    local collecting_files=false

    while IFS= read -r line; do
        # Match task header: "## Task N: Name" or "### Task N: Name"
        if echo "$line" | grep -qE "^#{2,3} Task [0-9]+:"; then
            # Save previous task defaults (only default files, not deps)
            if [ -n "$current_id" ]; then
                if [ -z "${TASK_FILES[$current_id]+x}" ]; then TASK_FILES[$current_id]="none"; fi
            fi

            current_id=$(echo "$line" | grep -oE "Task [0-9]+" | grep -oE "[0-9]+")
            local current_name=$(echo "$line" | sed -E 's/^#{2,3} Task [0-9]+: //')
            TASK_IDS+=("$current_id")
            TASK_NAMES+=("$current_name")
            in_task=true
            collecting_files=false
            continue
        fi

        if [ "$in_task" != true ]; then continue; fi

        # Match "**Files:**" or "Files:" header
        if echo "$line" | grep -qiE "^\*?\*?Files:?\*?\*?"; then
            collecting_files=true
            continue
        fi

        # Collect file paths from "- Create/Modify/Test: `path`" lines
        if $collecting_files && echo "$line" | grep -qE "^- (Create|Modify|Test):"; then
            local file_path=$(echo "$line" | grep -oE '`[^`]+`' | tr -d '`' | sed 's/:[0-9-]*$//')
            if [ -n "$file_path" ]; then
                if [ -z "${TASK_FILES[$current_id]+x}" ]; then
                    TASK_FILES[$current_id]="$file_path"
                else
                    TASK_FILES[$current_id]="${TASK_FILES[$current_id]} $file_path"
                fi
            fi
            continue
        fi

        # Stop collecting files on non-file lines (but not blank lines)
        if $collecting_files && [ -n "$line" ] && ! echo "$line" | grep -qE "^- (Create|Modify|Test):"; then
            collecting_files=false
        fi

        # Match "**Dependencies:**" or "Dependencies:" line
        if echo "$line" | grep -qiE "^\*?\*?Dependencies:?\*?\*?"; then
            local deps_value=$(echo "$line" | sed -E 's/^\*?\*?Dependencies:?\*?\*? *//')
            if echo "$deps_value" | grep -qiE "^none$"; then
                TASK_DEPS[$current_id]="none"
            else
                local dep_ids=$(echo "$deps_value" | grep -oE "Task [0-9]+" | grep -oE "[0-9]+" | tr '\n' ' ' | sed 's/ $//')
                TASK_DEPS[$current_id]="$dep_ids"
            fi
            continue
        fi
    done < "$plan_file"

    # Save last task defaults (only default files, not deps - missing deps is a validation error)
    if [ -n "$current_id" ]; then
        if [ -z "${TASK_FILES[$current_id]+x}" ]; then TASK_FILES[$current_id]="none"; fi
    fi
    return 0
}

# Detect file overlaps between tasks and add implicit dependencies
detect_file_overlaps() {
    IMPLICIT_DEPS=()

    for ((i=0; i<${#TASK_IDS[@]}; i++)); do
        local id_i="${TASK_IDS[$i]}"
        local files_i="${TASK_FILES[$id_i]}"
        if [ "$files_i" = "none" ]; then continue; fi

        for ((j=i+1; j<${#TASK_IDS[@]}; j++)); do
            local id_j="${TASK_IDS[$j]}"
            local files_j="${TASK_FILES[$id_j]}"
            if [ "$files_j" = "none" ]; then continue; fi

            for file_i in $files_i; do
                for file_j in $files_j; do
                    if [ "$file_i" = "$file_j" ]; then
                        IMPLICIT_DEPS+=("${id_i}:${id_j}")
                        echo "WARNING: Tasks $id_i and $id_j both touch $file_i - serializing" >&2
                        if [ "${TASK_DEPS[$id_j]}" = "none" ]; then
                            TASK_DEPS[$id_j]="$id_i"
                        elif ! echo "${TASK_DEPS[$id_j]}" | grep -qw "$id_i"; then
                            TASK_DEPS[$id_j]="${TASK_DEPS[$id_j]} $id_i"
                        fi
                        break 2
                    fi
                done
            done
        done
    done
    return 0
}

# Compute execution waves based on dependency depth
compute_waves() {
    TASK_WAVE=()
    MAX_WAVE=0
    for id in "${TASK_IDS[@]}"; do
        _compute_depth "$id" > /dev/null
    done
    return 0
}

_compute_depth() {
    local id="$1"
    if [ -n "${TASK_WAVE[$id]+x}" ]; then
        echo "${TASK_WAVE[$id]}"
        return
    fi
    local deps="${TASK_DEPS[$id]}"
    if [ "$deps" = "none" ] || [ -z "$deps" ]; then
        TASK_WAVE[$id]=0
        echo 0
        return
    fi
    local max_dep=0
    for dep_id in $deps; do
        local d=$(_compute_depth "$dep_id")
        if [ "$d" -gt "$max_dep" ]; then max_dep=$d; fi
    done
    local my_depth=$((max_dep + 1))
    TASK_WAVE[$id]=$my_depth
    if [ "$my_depth" -gt "$MAX_WAVE" ]; then MAX_WAVE=$my_depth; fi
    echo "$my_depth"
}

# Get task IDs for a specific wave
get_wave_tasks() {
    local wave="$1"
    local result=""
    for id in "${TASK_IDS[@]}"; do
        if [ "${TASK_WAVE[$id]}" = "$wave" ]; then
            result="${result:+$result }$id"
        fi
    done
    echo "$result"
}

# Validate a plan file
validate_plan() {
    local plan_file="$1"
    local errors=0

    parse_tasks "$plan_file"

    if [ ${#TASK_IDS[@]} -eq 0 ]; then
        echo "ERROR: No tasks found in plan" >&2
        return 1
    fi

    for id in "${TASK_IDS[@]}"; do
        if [ -z "${TASK_DEPS[$id]+x}" ]; then
            echo "ERROR: Task $id missing Dependencies field" >&2
            errors=$((errors + 1))
        fi
    done

    # Check dependency references
    for id in "${TASK_IDS[@]}"; do
        local deps="${TASK_DEPS[$id]}"
        if [ "$deps" = "none" ]; then continue; fi
        for dep_id in $deps; do
            local found=false
            for check_id in "${TASK_IDS[@]}"; do
                if [ "$check_id" = "$dep_id" ]; then found=true; break; fi
            done
            if ! $found; then
                echo "ERROR: Task $id references non-existent dependency Task $dep_id" >&2
                errors=$((errors + 1))
            fi
        done
    done

    # Check for cycles
    for id in "${TASK_IDS[@]}"; do
        if _has_cycle "$id" ""; then
            echo "ERROR: Dependency cycle detected involving Task $id" >&2
            errors=$((errors + 1))
        fi
    done

    if [ $errors -eq 0 ]; then
        return 0
    else
        return 1
    fi
}

_has_cycle() {
    local node="$1"
    local visited="$2"
    if echo "$visited" | grep -qw "$node"; then return 0; fi
    local deps="${TASK_DEPS[$node]}"
    if [ "$deps" = "none" ]; then return 1; fi
    if [ -z "$deps" ]; then return 1; fi
    for dep in $deps; do
        if _has_cycle "$dep" "$visited $node"; then return 0; fi
    done
    return 1
}

# Extract the full text content of a specific task
extract_task_spec() {
    local plan_file="$1"
    local target_id="$2"
    local capturing=false
    local content=""

    while IFS= read -r line; do
        if echo "$line" | grep -qE "^#{2,3} Task ${target_id}:"; then
            capturing=true
            content="$line"
            continue
        fi
        if $capturing; then
            if echo "$line" | grep -qE "^#{2,3} Task [0-9]+:"; then
                break
            fi
            # Also stop at "---" separators between tasks
            if [ "$line" = "---" ]; then
                break
            fi
            content="$content
$line"
        fi
    done < "$plan_file"

    echo "$content"
}
