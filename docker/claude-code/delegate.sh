#!/bin/bash
# delegate -- run a subtask on a chosen backend and print its answer.
#
#   delegate light "<instruction>"   -> local Qwen3.6-27B (q27), free
#   delegate heavy "<instruction>"   -> Opus 5 via the normal Claude Code auth
#
# Why a CLI instead of Claude Code subagents: this CLI version pins subagents to
# the SESSION model -- the `model` field in an agent definition (both --agents
# JSON and ~/.claude/agents/*.md frontmatter) is accepted but ignored, so every
# Task-tool delegation silently ran on the supervisor's own model. Verified by
# inspecting modelUsage: the only non-session model billed was a 20-output-token
# internal title call. Explicit delegation is also easier to audit -- every call
# is logged with its backend. The log lives in /tmp, never the workspace, so it
# cannot leak into the captured diff.
#
# The light path talks to q27's native Anthropic Messages endpoint. The heavy
# path shells out to `claude -p`, which reuses the container's existing OAuth
# rather than re-implementing token handling.

set -uo pipefail

TARGET="${1:-}"
shift || true
PROMPT="${*:-}"

LOG=/tmp/.delegate-log.jsonl
LOCAL_URL="${LOCAL_UPSTREAM:-http://host.docker.internal:8081}"
LOCAL_MODEL="${LOCAL_MODEL:-qwopus-27b-mtp}"
HEAVY_MODEL="${HEAVY_MODEL:-claude-opus-5}"

if [ -z "$TARGET" ] || [ -z "$PROMPT" ]; then
  echo "usage: delegate {light|heavy} \"<instruction>\"" >&2
  exit 2
fi

start=$(date +%s)

case "$TARGET" in
  light)
    OUT=$(python3 - "$LOCAL_URL" "$LOCAL_MODEL" "$PROMPT" <<'PY'
import json, sys, urllib.request
url, model, prompt = sys.argv[1], sys.argv[2], sys.argv[3]
body = json.dumps({
    "model": model,
    "max_tokens": 8000,
    "messages": [{"role": "user", "content": prompt}],
}).encode()
req = urllib.request.Request(url.rstrip("/") + "/v1/messages", data=body,
                             headers={"Content-Type": "application/json"}, method="POST")
try:
    with urllib.request.urlopen(req, timeout=900) as r:
        d = json.loads(r.read())
    parts = [b.get("text", "") for b in (d.get("content") or []) if b.get("type") == "text"]
    print("\n".join(p for p in parts if p).strip())
    u = d.get("usage", {}) or {}
    print(f"__USAGE__ {u.get('input_tokens',0)} {u.get('output_tokens',0)}", file=sys.stderr)
except Exception as e:
    print(f"delegate(light) FAILED: {e}", file=sys.stderr)
    sys.exit(1)
PY
    ) 2>/tmp/.delegate-err
    RC=$?
    USAGE=$(grep -a "__USAGE__" /tmp/.delegate-err 2>/dev/null | tail -1)
    ;;
  heavy)
    OUT=$(claude -p --model "$HEAVY_MODEL" \
            --dangerously-skip-permissions --setting-sources '' --strict-mcp-config \
            -- "$PROMPT" 2>/tmp/.delegate-err)
    RC=$?
    USAGE=""
    ;;
  *)
    echo "unknown target '$TARGET' (use: light | heavy)" >&2
    exit 2
    ;;
esac

end=$(date +%s)
python3 - "$TARGET" "$RC" "$((end-start))" "${USAGE:-}" <<'PY' 2>/dev/null || true
import json, sys, time
target, rc, dur, usage = sys.argv[1], int(sys.argv[2]), int(sys.argv[3]), sys.argv[4]
tin = tout = 0
if usage.startswith("__USAGE__"):
    try: _, tin, tout = usage.split()[:3]; tin, tout = int(tin), int(tout)
    except Exception: pass
with open("/tmp/.delegate-log.jsonl", "a") as f:
    f.write(json.dumps({"timestamp": time.time(), "target": target, "exit": rc,
                        "duration_s": dur, "input_tokens": tin, "output_tokens": tout}) + "\n")
PY

if [ "$RC" -ne 0 ]; then
  echo "delegate($TARGET) failed:" >&2
  tail -5 /tmp/.delegate-err >&2
  exit "$RC"
fi

printf '%s\n' "$OUT"
