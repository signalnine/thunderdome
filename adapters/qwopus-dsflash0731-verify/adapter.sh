#!/bin/bash
set -e

[[ -f "$TASK_DESCRIPTION" ]] || { echo "Task file not found: $TASK_DESCRIPTION" >&2; exit 2; }

cd "$TASK_DIR"

# --- Qwopus-27B writes (local, free), DeepSeek v4 Flash verifies (cloud) ---
#
# DeepSeek v4 Flash is the BEST reviewer measured (90.1%, hard 86.8 -- the only
# arm that meaningfully clears the 82.0 no-reviewer baseline). A new version
# shipped 2026-07-31, so this arm re-tests the seat on the new weights.
#
# PINNED to the dated snapshot deepseek-v4-flash-0731 ON PURPOSE. DeepSeek's own
# API exposes ONLY floating names (deepseek-v4-flash / -pro, no dated
# snapshots), and the existing qwen-deepseek-verify adapter calls the floating
# one against api.deepseek.com/anthropic. That means the recorded 90.1% is a
# measurement of whatever was live on 2026-07-25 and CANNOT BE REPRODUCED -- the
# same non-hermetic floating-alias trap that invalidated the old "opus-48"
# baseline. OpenRouter is used here precisely because it publishes the dated
# snapshot.
#
# Neither endpoint reveals which snapshot served a request (both echo back the
# requested name), so the alias flip is not externally observable. Hence the
# companion arm: run the FLOATING deepseek/deepseek-v4-flash through this same
# adapter via REVIEW_MODEL over the SAME OpenRouter Anthropic path. Identical
# infrastructure means any score gap isolates the version, and identical scores
# indicate the alias has already moved to 0731.
#
# Reference points for the reviewer seat, same qwopus writer throughout:
#   none (solo baseline)          84.5%  std 86.8  hard 82.0  $0
#   Gemma 4 26B-A4B    (local)    85.3%  std 90.2  hard 79.9  $0
#   GPT-5.6 Luna       (cloud)    86.8%  std 93.2  hard 79.7  $0.060/task
#   GPT-5.6 Terra      (cloud)    87.5%  std 93.6  hard 80.9  $0.561/task
#   vanilla Qwen q4s   (local)    88.9%  std 93.5  hard 83.8  $0
#   DeepSeek v4 Flash  (old, native endpoint, 2026-07-25)
#                                 90.1%  std 93.1  hard 86.8  $0.578/task
#
# Writer runs on the 5090 via q27 :8080 through the bridge on :8081.

export HOME=/tmp

LOCAL_UPSTREAM="${LOCAL_UPSTREAM:-http://host.docker.internal:8081}"
REVIEW_MODEL="${REVIEW_MODEL:-deepseek/deepseek-v4-flash-0731}"
REVIEW_UPSTREAM="${REVIEW_UPSTREAM:-https://openrouter.ai/api}"

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
: "${OPENROUTER_API_KEY:?OPENROUTER_API_KEY is required -- Luna is served via OpenRouter}"

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

# ── DO-NO-HARM GATE, part 1: snapshot + baseline measurement ───────
#
# Measured on 21 tasks: the review phase is worth +4.4pp overall, but that is
# +6.0pp of rescues MINUS 1.8pp of self-inflicted damage. On 15 of 21 tasks the
# reviewer changed nothing that mattered; where the writer had already
# succeeded, the reviewer was a net liability (reactive-spreadsheet 0.881 ->
# 0.575, structural-merge 0.929 -> 0.861). Uncapped Gemma expressed the same
# defect more violently: 154 turns ending with coverage/ deleted, 0.470.
#
# The common defect is that the reviewer may leave the workspace WORSE than it
# found it. A turn cap only changes when the damage stops. This gate removes the
# failure mode outright: keep the reviewer's edits only if they do not regress
# the suite, otherwise restore the writer's tree byte for byte.
#
# VALIDATED end-to-end against a real vitest project by vandalising a writer
# tree (break a source file, delete a test, delete coverage/, add junk):
# writer [0 136 10] vs vandalised [0 0 77] -> reverted; source byte-identical,
# deleted test restored, junk removed, coverage-summary.json restored,
# node_modules and both transcripts preserved, re-measured state an exact match.
# A live trial also exercised the keep path (writer [1 69 0], reviewer [1 69 0]
# -> kept).
SNAPSHOT=/tmp/writer-snapshot.tar
DNH_ENABLED="${DNH_ENABLED:-1}"

# Emits "<build_ok> <passed> <failed>". Vitest prints "Test Files ..." before
# "Tests ...", so the last "N passed"/"N failed" match is the test-level count.
measure_state() {
  local b=0 p f out
  timeout 300 npm run build >/dev/null 2>&1 && b=1
  out=$(timeout 600 npm test 2>&1 | tail -80)
  p=$(printf '%s' "$out" | grep -oE '[0-9]+ passed' | tail -1 | grep -oE '[0-9]+')
  f=$(printf '%s' "$out" | grep -oE '[0-9]+ failed' | tail -1 | grep -oE '[0-9]+')
  echo "${b} ${p:-0} ${f:-0}"
}

WRITER_STATE=""
if [ "$DNH_ENABLED" = "1" ] && [ -f /workspace/package.json ]; then
  # dist/ and coverage/ MUST be snapshotted -- the harness reads
  # coverage/coverage-summary.json from the workspace. Runtime artifacts are
  # excluded from BOTH the snapshot and the revert: .thunderdome-output.jsonl is
  # written DURING review, so a naive revert would delete the reviewer
  # transcript and silently zero reviewer_turns in the metrics.
  tar cf "$SNAPSHOT" --exclude=./node_modules --exclude=./.git \
    --exclude='./.thunderdome*' --exclude='./.qwen-*' --exclude='./.review-*' \
    -C /workspace . 2>/dev/null || true
  [ -f "$SNAPSHOT" ] && WRITER_STATE=$(measure_state)
  echo "do-no-harm: writer baseline (build passed failed) = ${WRITER_STATE:-unavailable}" >&2
fi

# ── Phase 2: DeepSeek v4 Flash verifies and repairs (via OpenRouter) 
unset ANTHROPIC_AUTH_TOKEN
export ANTHROPIC_BASE_URL="$REVIEW_UPSTREAM"
export ANTHROPIC_API_KEY="$OPENROUTER_API_KEY"

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

# Held at the Gemma pairing's value so the reviewer MODEL is the only variable.
# The cap exists because a local reviewer that engages deeply may not converge:
# Gemma ground until it filled the context window (identical crashes at 32K and
# 128K), and its engagement was anti-correlated with score (<10 turns -> 0.913,
# >=10 turns -> 0.806). Vanilla Qwen is a much stronger coder and may not need
# the leash, but changing the cap here would confound the comparison.
REVIEW_MAX_TURNS="${REVIEW_MAX_TURNS:-25}"

set +e
claude -p \
  --model "$REVIEW_MODEL" \
  --output-format stream-json \
  --verbose \
  --dangerously-skip-permissions \
  --setting-sources '' \
  --strict-mcp-config \
  --max-turns "$REVIEW_MAX_TURNS" \
  --disallowed-tools "AskUserQuestion,EnterPlanMode" \
  -- "$REVIEW_PROMPT" \
  > "$FINAL_OUTPUT" 2>/workspace/.review-stderr.log
REVIEW_EXIT=$?
set -e

# ── DO-NO-HARM GATE, part 2: verdict ───────────────────────────────
# Keep the review only if NOTHING got worse: build must not break, failures must
# not rise, passes must not drop. Ties are kept -- a reviewer that changed
# nothing measurable is harmless, and reverting it would discard genuine
# refactors that happen to be score-neutral.
DNH_VERDICT="disabled"
if [ -n "$WRITER_STATE" ]; then
  REVIEWER_STATE=$(measure_state)
  read -r WB WP WF <<<"$WRITER_STATE"
  read -r RB RP RF <<<"$REVIEWER_STATE"
  echo "do-no-harm: writer=[$WRITER_STATE] reviewer=[$REVIEWER_STATE]" >&2
  # Keep if nothing got worse. Failures are STRICT (must not rise); the pass
  # count is tolerant, because requiring passed >= writer's reverted a genuine
  # repair: Luna on yaml-escapes took failures 1 -> 0 while consolidating tests
  # 957 -> 949, and the strict rule threw the fix away and scored 0.300. The
  # total-count floor (95%) still blocks the gaming case -- a reviewer deleting
  # most of the suite to reach "0 failed" trips it and reverts.
  WT=$(( WP + WF )); RT=$(( RP + RF ))
  if [ "$RB" -ge "$WB" ] && [ "$RF" -le "$WF" ] && [ $(( RT * 100 )) -ge $(( WT * 95 )) ]; then
    DNH_VERDICT="kept"
  else
    DNH_VERDICT="reverted"
    # Restore the writer's tree exactly: drop everything the reviewer left
    # behind (including files it ADDED), then unpack the snapshot. node_modules,
    # .git and the runtime artifacts are preserved -- they were never
    # snapshotted, so deleting them here would be unrecoverable.
    find /workspace -mindepth 1 -maxdepth 1 \
      ! -name node_modules ! -name .git \
      ! -name '.thunderdome*' ! -name '.qwen-*' ! -name '.review-*' \
      -exec rm -rf {} + 2>/dev/null || true
    tar xf "$SNAPSHOT" -C /workspace 2>/dev/null || true
    echo "do-no-harm: REVERTED -- reviewer regressed the suite, writer tree restored" >&2
  fi
fi
echo "do-no-harm: verdict=$DNH_VERDICT" >&2
rm -f "$SNAPSHOT"

# ── Metrics: writer is local ($0), reviewer is metered via OpenRouter ──
REVIEW_EXIT="$REVIEW_EXIT" REVIEW_MAX_TURNS="$REVIEW_MAX_TURNS" \
DNH_VERDICT="$DNH_VERDICT" DNH_WRITER="$WRITER_STATE" DNH_REVIEWER="${REVIEWER_STATE:-}" node -e '
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
// Qwopus runs locally: its tokens are real work but cost $0, so they are
// counted as turns only and deliberately kept out of total_cost_usd. The
// REVIEWER is billed -- scan(billed=true) collects its token usage.
const qwenTurns = scan("/workspace/.qwen-output.jsonl", false);
const revTurns  = scan("/workspace/.thunderdome-output.jsonl", true);
// Claude Code prices against its own model table and cannot know an OpenRouter
// model -- it reported $4.82 for a review that actually cost ~$0.08 -- so
// msg.total_cost_usd is discarded and cost is recomputed from tokens at the
// published DeepSeek v4 Flash rate ($0.14/M in, $0.28/M out).
//
// cache_creation_input_tokens MUST be counted as input. Verified against
// OpenRouter /api/v1/generation: an envelope reporting input_tokens=3 +
// cache_creation_input_tokens=4409 was billed as native_tokens_prompt=4412,
// i.e. exactly their sum. Omitting the field understated one review by 55x
// ($0.0014 vs $0.077), because Claude Code re-sends a growing transcript every
// turn and nearly all prompt volume lands in that field, not input_tokens.
//
// Caveat: that same ground-truth check billed 4412 prompt tokens at $0.000551,
// an effective $0.125/M against a $0.10/M list -- OpenRouter markup. So these
// figures are a LOWER bound, unlike the local arms.
m.total_cost_usd = ((m.input_tokens + m.cache_creation_tokens + m.cache_read_tokens) * 0.14
                    + m.output_tokens * 0.28) / 1e6;
m.turns = qwenTurns + revTurns;
m.phases = {writer: "qwopus-27b-local (free)", writer_turns: qwenTurns,
            reviewer: process.env.REVIEW_MODEL || "deepseek/deepseek-v4-flash-0731", reviewer_turns: revTurns,
            reviewer_exit: Number(process.env.REVIEW_EXIT || 0),
            reviewer_max_turns: Number(process.env.REVIEW_MAX_TURNS || 0),
            // do-no-harm gate: "kept" | "reverted" | "disabled". A revert means
            // the reviewer regressed the suite and the writer tree was restored,
            // so the trial scores as writer-only. Recorded so a revert is never
            // invisible in the results.
            dnh_verdict: process.env.DNH_VERDICT || "disabled",
            dnh_writer_state: process.env.DNH_WRITER || null,
            dnh_reviewer_state: process.env.DNH_REVIEWER || null};
fs.writeFileSync("/workspace/.thunderdome-metrics.json", JSON.stringify(m, null, 2));
console.error("Metrics: " + JSON.stringify(m));
' || true

# The reviewer is BEST-EFFORT repair on top of code the writer already produced,
# so its failure must not invalidate the trial. Previously a reviewer error
# surfaced as the adapter's exit and the harness marked the trial "crashed" --
# which gen-scores.py excludes from _WORKED_REASONS -- disqualifying trials whose
# code was fine (debug-nightmare scored 0.959 and was still thrown away as a
# crash). The writer's exit governs; a reviewer failure is logged, not fatal.
if [ "$REVIEW_EXIT" -ne 0 ]; then
  echo "WARNING: review phase exited $REVIEW_EXIT (best-effort; writer output retained)" >&2
  tail -3 /workspace/.review-stderr.log >&2 2>/dev/null || true
fi
exit "$QWEN_EXIT"
