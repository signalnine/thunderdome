#!/bin/bash
set -e

[[ -f "$TASK_DESCRIPTION" ]] || { echo "Task file not found: $TASK_DESCRIPTION" >&2; exit 2; }

cd "$TASK_DIR"

# --- Qwopus-27B writes, Ornith-9B verifies -- BOTH LOCAL, $0 end to end ---
#
# Phase 1: Qwen3.6-27B on the local q27 box implements the task (free).
# Phase 2: Ornith-1.0-9B (DeepReinforce agentic-coding tune) reviews the
#          workspace, runs the suite, and repairs whatever is not green.
#
# Writer runs on the 5090 (q27, port 8080 via the bridge); reviewer runs on the
# 3090 (llama.cpp, port 8083). They never compute at the same time -- the phases
# are sequential -- so the split is purely about VRAM.
#
# The 3090 needs a DUAL-ARCH llama.cpp build: the default turboquant build is
# CMAKE_CUDA_ARCHITECTURES=120 (5090 only) and silently fails on sm_86. Use
# build86/ (ARCHS = 860,1200). llama.cpp serves Anthropic /v1/messages natively,
# so like q27 it needs no translation shim.
#
# Tests whether a LOCAL reviewer can stand in for a cloud one. The same writer
# with DeepSeek v4 Flash reviewing scored 88.3% at $0.58/task; this pairing costs
# $0.00. Nothing leaves the box.
#
# Phase 1 needs no proxy: q27 speaks the Anthropic Messages API natively and
# accepts any model name (verified -- it serves qwopus-27b-mtp regardless).
# Phase 2 uses DeepSeek's own /anthropic endpoint the same way.

export HOME=/tmp

LOCAL_UPSTREAM="${LOCAL_UPSTREAM:-http://host.docker.internal:8081}"
REVIEW_MODEL="${REVIEW_MODEL:-ornith-1.0-9b}"
REVIEW_UPSTREAM="${REVIEW_UPSTREAM:-http://host.docker.internal:8083}"

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
if ! python3 -c "
import urllib.request,sys
try: urllib.request.urlopen('$REVIEW_UPSTREAM/v1/models', timeout=5)
except Exception: sys.exit(1)
" 2>/dev/null; then
  echo "ERROR: reviewer endpoint $REVIEW_UPSTREAM unreachable." >&2
  echo "  Start Ornith-9B on the 3090 with the DUAL-ARCH build:" >&2
  echo "  CUDA_VISIBLE_DEVICES=1 llama.cpp-turboquant/build86/bin/llama-server --model .../ornith-1.0-9b-Q5_K_M.gguf --port 8083 --host 0.0.0.0" >&2
  exit 4
fi

TASK_PROMPT=$(cat "$TASK_DESCRIPTION")
QWEN_OUTPUT=/workspace/.qwen-output.jsonl
FINAL_OUTPUT=/workspace/.thunderdome-output.jsonl

# ── Phase 1: Qwen implements ───────────────────────────────────────
# The zen framing is not decoration: on this model family it is worth ~+6.9pp
# overall and +13.4pp on the hard suite versus a plain prompt, and it beats a
# heavyweight 6-step methodology. Reused verbatim from qwen-sonnet-verify.
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
  > "$QWEN_OUTPUT" 2>/workspace/.qwen-stderr.log
QWEN_EXIT=$?
set -e

# ── Phase 2: DeepSeek v4 Flash verifies and repairs ────────────────
unset ANTHROPIC_AUTH_TOKEN
export ANTHROPIC_BASE_URL="$REVIEW_UPSTREAM"
export ANTHROPIC_API_KEY="placeholder"

REVIEW_PROMPT="Another agent has just attempted this task:

$TASK_PROMPT

The workspace reflects their attempt. Your job is verification and repair, not feature work.

1. Run the verification suite: npm install (if needed), npm run build, npm test, npm run lint.
2. Read any failures carefully.
3. Fix the code so that every test passes and the build/lint are clean.
4. Do NOT add features the task didn't ask for.
5. Do NOT delete or modify files in tests/ unless the previous agent's implementation is obviously wrong about the contract.
6. Keep iterating until everything is green.

Done means: build passes, tests pass, lint passes."

set +e
claude -p \
  --model "$REVIEW_MODEL" \
  --output-format stream-json \
  --verbose \
  --dangerously-skip-permissions \
  --setting-sources '' \
  --strict-mcp-config \
  --disallowed-tools "AskUserQuestion,EnterPlanMode" \
  -- "$REVIEW_PROMPT" \
  > "$FINAL_OUTPUT" 2>/workspace/.review-stderr.log
REVIEW_EXIT=$?
set -e

# ── Metrics: both phases are local, so cost is $0 by construction ────
node -e '
const fs = require("fs");
const m = {input_tokens:0, output_tokens:0, cache_read_tokens:0, cache_creation_tokens:0,
           turns:0, tools_used:[], duration_ms:0, total_cost_usd:0};
const tools = new Set();
function scan(file, billed) {
  let turns = 0;
  try {
    for (const line of fs.readFileSync(file, "utf8").split("\n")) {
      if (!line.trim()) continue;
      let msg; try { msg = JSON.parse(line); } catch { continue; }
      if (msg.type === "result") {
        turns += msg.num_turns || 0;
        m.duration_ms += msg.duration_ms || 0;
        if (billed) {
          const u = msg.usage || {};
          m.input_tokens += u.input_tokens || 0;
          m.output_tokens += u.output_tokens || 0;
          m.cache_read_tokens += u.cache_read_input_tokens || 0;
          m.cache_creation_tokens += u.cache_creation_input_tokens || 0;
          m.total_cost_usd += msg.total_cost_usd || 0;
        }
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
// Qwen runs locally: its tokens are real work but cost $0, so they are counted
// as turns only and deliberately kept out of total_cost_usd.
const qwenTurns = scan("/workspace/.qwen-output.jsonl", false);
const revTurns  = scan("/workspace/.thunderdome-output.jsonl", false);
m.turns = qwenTurns + revTurns;
m.phases = {writer: "qwopus-27b-local (free)", writer_turns: qwenTurns,
            reviewer: "ornith-1.0-9b-local (free)", reviewer_turns: revTurns};
fs.writeFileSync("/workspace/.thunderdome-metrics.json", JSON.stringify(m, null, 2));
console.error("Metrics: " + JSON.stringify(m));
' || true

# The review phase owns the final state; surface its exit unless it never ran.
if [ "$REVIEW_EXIT" -ne 0 ] && [ "$QWEN_EXIT" -ne 0 ]; then
  exit "$QWEN_EXIT"
fi
exit "$REVIEW_EXIT"
