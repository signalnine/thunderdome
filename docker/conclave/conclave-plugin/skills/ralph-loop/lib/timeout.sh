#!/usr/bin/env bash
# Timeout handling for Ralph Loop

# Default timeouts (in seconds) - configurable via environment
TIMEOUT_IMPLEMENT=${RALPH_TIMEOUT_IMPLEMENT:-1200}  # 20 min
TIMEOUT_TEST=${RALPH_TIMEOUT_TEST:-600}             # 10 min
TIMEOUT_SPEC=${RALPH_TIMEOUT_SPEC:-300}             # 5 min
TIMEOUT_QUALITY=${RALPH_TIMEOUT_QUALITY:-180}       # 3 min
TIMEOUT_GLOBAL=${RALPH_TIMEOUT_GLOBAL:-3600}        # 60 min

run_with_timeout() {
    local timeout_secs="$1"
    local gate_name="$2"
    shift 2

    echo "[TIMEOUT] Running $gate_name with ${timeout_secs}s limit"

    # Use timeout command (GNU coreutils)
    local start=$(date +%s)
    timeout --signal=TERM --kill-after=10 "$timeout_secs" "$@"
    local exit_code=$?
    local elapsed=$(($(date +%s) - start))

    if [ $exit_code -eq 124 ]; then
        echo "TIMEOUT: $gate_name exceeded ${timeout_secs}s limit" >&2
        return 124
    fi

    # Soft warning at 60% of limit
    local soft_limit=$((timeout_secs * 6 / 10))
    if [ $elapsed -gt $soft_limit ]; then
        echo "WARNING: $gate_name took ${elapsed}s (soft limit: ${soft_limit}s)" >&2
    fi

    return $exit_code
}

get_gate_timeout() {
    local gate="$1"
    case "$gate" in
        implement) echo $TIMEOUT_IMPLEMENT ;;
        test)      echo $TIMEOUT_TEST ;;
        spec)      echo $TIMEOUT_SPEC ;;
        quality)   echo $TIMEOUT_QUALITY ;;
        *)         echo 600 ;;
    esac
}

check_global_timeout() {
    local start_time="$1"
    local elapsed=$(($(date +%s) - start_time))
    if [ $elapsed -gt $TIMEOUT_GLOBAL ]; then
        echo "GLOBAL TIMEOUT: Exceeded ${TIMEOUT_GLOBAL}s (${elapsed}s elapsed)" >&2
        return 1
    fi
    return 0
}
