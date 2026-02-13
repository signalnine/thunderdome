#!/usr/bin/env bash
# Ensures the conclave binary exists, downloading it if needed,
# then runs the session-start hook.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
PLUGIN_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
BINARY="${PLUGIN_ROOT}/conclave"

# If binary exists and is executable, run it directly
if [ -x "$BINARY" ]; then
    exec "$BINARY" hook session-start
fi

# Detect OS
case "$(uname -s)" in
    Linux)  OS="linux" ;;
    Darwin) OS="darwin" ;;
    *)
        # Unsupported OS, fall back to bash script
        exec "${SCRIPT_DIR}/session-start.sh"
        ;;
esac

# Detect architecture
case "$(uname -m)" in
    x86_64)  ARCH="amd64" ;;
    aarch64) ARCH="arm64" ;;
    arm64)   ARCH="arm64" ;;
    *)
        exec "${SCRIPT_DIR}/session-start.sh"
        ;;
esac

# Read version from plugin.json (no jq dependency)
VERSION=$(grep -o '"version"[[:space:]]*:[[:space:]]*"[^"]*"' "${PLUGIN_ROOT}/.claude-plugin/plugin.json" | grep -o '"[^"]*"$' | tr -d '"')

if [ -z "$VERSION" ]; then
    exec "${SCRIPT_DIR}/session-start.sh"
fi

# Download binary
URL="https://github.com/signalnine/conclave/releases/download/v${VERSION}/conclave-${OS}-${ARCH}"

if curl -fsSL -o "$BINARY" "$URL" 2>/dev/null; then
    chmod +x "$BINARY"
    exec "$BINARY" hook session-start
fi

# Download failed, fall back to bash script
exec "${SCRIPT_DIR}/session-start.sh"
