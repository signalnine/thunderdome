#!/usr/bin/env bash
# Lockfile management for Ralph Loop

LOCK_FILE=".ralph.lock"

acquire_lock() {
    if [ -f "$LOCK_FILE" ]; then
        local pid=$(cat "$LOCK_FILE" 2>/dev/null)
        if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
            echo "ERROR: Another Ralph loop is active (PID $pid)" >&2
            return 1
        else
            echo "WARNING: Removing stale lock (PID $pid no longer running)" >&2
            rm -f "$LOCK_FILE"
        fi
    fi
    echo $$ > "$LOCK_FILE"
    return 0
}

release_lock() {
    rm -f "$LOCK_FILE"
}

setup_lock_trap() {
    trap 'release_lock; exit 130' INT TERM
    trap 'release_lock' EXIT
}
