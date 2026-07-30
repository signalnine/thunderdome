#!/bin/bash
set -e

[[ -f "$TASK_DESCRIPTION" ]] || { echo "Task file not found: $TASK_DESCRIPTION" >&2; exit 2; }

cd "$TASK_DIR"

# --- Qwopus-27B alone: the NO-REVIEWER BASELINE -- local, $0 ---
#
# This is the control the writer+reviewer pairings were missing. Without it we
# can only say which reviewer is better, not whether a review phase helps at
# all. The 81.2% on record for solo qwopus is a CRUSH-harness number and is NOT
# comparable to these adapters, which drive Claude Code.
#
# Phase 1 here is BYTE-IDENTICAL to phase 1 of qwopus-qwen-verify and
# qwopus-gemma4-verify -- same model, same zen system prompt, same flags, same
# endpoint. The ONLY difference is that no review phase follows. Any score
# delta is therefore attributable to the review phase itself.
#
# Reference points, same writer throughout:
#   DeepSeek v4 Flash reviewer (cloud)  90.1%  $0.58/task
#   vanilla Qwen q4s reviewer  (local)  88.9%  $0.00
#   Gemma 4 26B-A4B reviewer   (local)  86.2%  $0.00  (uncapped)
#   NO reviewer (this adapter)           ????  $0.00
#
# Needs only the 5090 (qwopus via q27 :8080, reached through the bridge on
# :8081). The 3090 is not used, so this can run while a reviewer model is
# loaded there without contending for VRAM.

export HOME=/tmp

LOCAL_UPSTREAM="${LOCAL_UPSTREAM:-http://host.docker.internal:8081}"

if ! python3 -c "
import urllib.request,sys
try: urllib.request.urlopen('$LOCAL_UPSTREAM/v1/models', timeout=5)
except Exception: sys.exit(1)
" 2>/dev/null; then
  echo "ERROR: local model endpoint $LOCAL_UPSTREAM unreachable." >&2
  echo "  q27-server binds 127.0.0.1, which containers cannot reach." >&2
  echo "  Fix: run scripts/local-model-bridge.py on the host, or restart q27-server with --host 0.0.0.0" >&2
  exit 3
fi

TASK_PROMPT=$(cat "$TASK_DESCRIPTION")
FINAL_OUTPUT=/workspace/.thunderdome-output.jsonl

# ── Single phase: Qwopus implements, nothing verifies it ───────────
# The zen framing is not decoration: on this model family it is worth ~+6.9pp
# overall and +13.4pp on the hard suite versus a plain prompt, and it beats a
# heavyweight 6-step methodology. Reused VERBATIM from the paired adapters so
# the only variable is the presence of a review phase.
export ANTHROPIC_BASE_URL="$LOCAL_UPSTREAM"
export ANTHROPIC_API_KEY="placeholder"

set +e
claude -p \
  --model qwopus-27b-mtp \
  --output-format stream-json \
  --verbose \
  --dangerously-skip-permissions \
  --setting-sources '' \
  --strict-mcp-config \
  --disallowed-tools "AskUserQuestion,EnterPlanMode" \
  --append-system-prompt "# The Way of Calm Precision

Before writing any code, enter a state of calm clarity.

## First: Release Urgency
Pause. Release attachment to appearing clever or finishing quickly. Attend to what the code actually needs, not what you want to build. Quality emerges from stillness, not striving.

## Then: Understand
Read the task fully. Read existing files: src/, tests/, package.json. Sit with what is there before adding to it. Do not guess -- know.

## Then: Let the Tests Speak First
For each behavior the task requires, write the test BEFORE the code. Run it. Watch it fail. The failing test tells you exactly what the code needs to become. Only then write the minimum to make it pass. One small truth at a time.

If you catch yourself writing code before its test, stop. Delete it. The test comes first.

## Then: Verify Until Clean
Run: npm run build && npm test && npm run lint. Fix all failures. Do not stop until every test passes, build is clean, lint is clean. Keep iterating with calm persistence.

Write the simple, correct solution. A calm craftsperson writes less code, not more." \
  -- "$TASK_PROMPT" \
  > "$FINAL_OUTPUT" 2>/workspace/.qwen-stderr.log
QWEN_EXIT=$?
set -e

# ── Metrics: local, so cost is $0 by construction ──────────────────
node -e '
const fs = require("fs");
const m = {input_tokens:0, output_tokens:0, cache_read_tokens:0, cache_creation_tokens:0,
           turns:0, tools_used:[], duration_ms:0, total_cost_usd:0};
const tools = new Set();
function scan(file) {
  let turns = 0;
  try {
    for (const line of fs.readFileSync(file, "utf8").split("\n")) {
      if (!line.trim()) continue;
      let msg; try { msg = JSON.parse(line); } catch { continue; }
      if (msg.type === "result") {
        turns += msg.num_turns || 0;
        m.duration_ms += msg.duration_ms || 0;
      }
      if (msg.type === "assistant" && msg.message && Array.isArray(msg.message.content)) {
        for (const b of msg.message.content) {
          if (b.type === "tool_use" && b.name && !tools.has(b.name)) { tools.add(b.name); m.tools_used.push(b.name); }
        }
      }
    }
  } catch (e) {}
  return turns;
}
// Qwopus runs locally: its tokens are real work but cost $0, so they are
// counted as turns only and deliberately kept out of total_cost_usd.
const qwenTurns = scan("/workspace/.thunderdome-output.jsonl");
m.turns = qwenTurns;
m.phases = {writer: "qwopus-27b-local (free)", writer_turns: qwenTurns,
            reviewer: "none (baseline)", reviewer_turns: 0};
fs.writeFileSync("/workspace/.thunderdome-metrics.json", JSON.stringify(m, null, 2));
console.error("Metrics: " + JSON.stringify(m));
' || true

exit "$QWEN_EXIT"
