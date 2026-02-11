#!/bin/bash
set -e

# Validate inputs
[[ -f "$TASK_DESCRIPTION" ]] || { echo "Task file not found: $TASK_DESCRIPTION" >&2; exit 2; }

# Start WebSocket server in background
/opt/ws-server \
  --port 9876 \
  --task-file "$TASK_DESCRIPTION" \
  --metrics-file /workspace/.thunderdome-metrics.json \
  --idle-timeout "${WS_IDLE_TIMEOUT_MIN:-10}" \
  --debug &
SERVER_PID=$!

# Clean up server on any exit
trap 'kill $SERVER_PID 2>/dev/null; wait $SERVER_PID 2>/dev/null' EXIT INT TERM

# Wait for server to bind (poll port, max 3 seconds)
SERVER_READY=0
for i in $(seq 1 30); do
  if ! kill -0 $SERVER_PID 2>/dev/null; then
    echo "ws-server exited unexpectedly" >&2; exit 1
  fi
  if nc -z localhost 9876 2>/dev/null; then SERVER_READY=1; break; fi
  sleep 0.1
done
if [ "$SERVER_READY" -ne 1 ]; then
  echo "ws-server failed to start within 3 seconds" >&2; exit 1
fi

# Launch Claude Code
cd "$TASK_DIR"
export ANTHROPIC_BASE_URL="$PROXY_URL"
# set -e propagates claude's exit code; trap handles server cleanup
claude --sdk-url ws://localhost:9876
