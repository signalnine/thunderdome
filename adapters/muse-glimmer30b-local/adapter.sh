#!/bin/bash
set -e

[[ -f "$TASK_DESCRIPTION" ]] || { echo "Task file not found: $TASK_DESCRIPTION" >&2; exit 2; }

cd "$TASK_DIR"

# --- Muse Glimmer 30B, fully local on the 5090 -- $0 ---
#
# Meta`s dense 30B open-weight agentic model, served by llama.cpp on GPU0 and
# driven by vanilla Claude Code. Single phase: no reviewer, no supervisor.
#
# THE POINT: every prior local arm needed TWO phases to be competitive
# (qwopus solo 84.5% vs qwopus+vanilla-Qwen 88.9%). This asks whether one
# purpose-built agentic model beats a two-phase pipeline of a general one.
# On the four most-differentiated tasks the HOSTED version scored 0.771 vs
# qwopus solo`s 0.649 -- a large single-model win -- but still short of the
# all-local pair`s 0.917. This run is the local read at full suite length.
#
# SERVING (see /tmp/muse-final.log for the live config):
#   llama.cpp @ 2026-08-11 HEAD or newer -- muse_glimmer support merged 10 Aug
#   2026 (PR #26841, build b10353); ALL four pre-existing local builds were
#   blind to the arch. PR #26879 (tool-call detection after EOM) matters for
#   agentic use, so track HEAD rather than just the merge commit.
#   --ctx-size 131072 (full native window, only +534 MiB over 65K thanks to
#   heavy GQA + q8_0 KV), 19.7 GB kquant-dynamic build, ~23 GB of 32.6 total.
#   --reasoning-preserve is REQUIRED: it is OFF by default and keeps the
#   reasoning trace across the whole history rather than the last turn only.
#   Losing that is what collapsed GLM-5.2 to 27.4% on this suite.
#   -md dflash-kquant.gguf -ngld 99 --spec-type draft-dflash --spec-draft-n-max 24
#   --spec-type DEFAULTS TO none: passing -md alone loads the drafter and never
#   uses it -- correct output, zero speedup, +8 MiB VRAM instead of +2004 MiB.
#   Measured ~67 -> ~122 tok/s (1.8x) on code-shaped output; the vendor claims
#   3.1x on this same GPU, likely on the smaller 17 GB quant.
#
# llama-server binds 0.0.0.0, so containers reach it directly -- unlike q27,
# which binds loopback and needs scripts/local-model-bridge.py.

export HOME=/tmp

LOCAL_UPSTREAM="${LOCAL_UPSTREAM:-http://host.docker.internal:8086}"

# Retry rather than exit on the first miss. A bare 5s check discarded 32 of 42
# trials across two DeepSeek arms: fast reviews (~seconds) cycle trials
# back-to-back, and q27 does not answer /v1/models promptly while it is still
# finishing the previous trial, so the guard exited 3 BEFORE phase 1 wrote any
# file -- surfacing as "crashed [NO AGENT CONTRIBUTION]" with zero tokens and no
# stderr. The same tasks pass in isolation. A health check must not destroy a trial.
_upstream_ready() {
  local i
  for i in 1 2 3 4 5 6; do
    python3 -c "
import urllib.request,sys
try: urllib.request.urlopen('$LOCAL_UPSTREAM/v1/models', timeout=20)
except Exception: sys.exit(1)
" 2>/dev/null && return 0
    sleep 10
  done
  return 1
}
if ! _upstream_ready; then
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
  --model muse-glimmer-30b \
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
m.phases = {writer: "muse-glimmer-30b-local (free)", writer_turns: qwenTurns,
            reviewer: "none (single model)", reviewer_turns: 0};
fs.writeFileSync("/workspace/.thunderdome-metrics.json", JSON.stringify(m, null, 2));
console.error("Metrics: " + JSON.stringify(m));
' || true

exit "$QWEN_EXIT"
