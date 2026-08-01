#!/bin/bash
set -e

[[ -f "$TASK_DESCRIPTION" ]] || { echo "Task file not found: $TASK_DESCRIPTION" >&2; exit 2; }

cd "$TASK_DIR"

# --- Qwopus-27B writes, VANILLA Qwen3.6-27B verifies -- BOTH LOCAL, $0 ---
#
# Phase 1: Qwopus3.6-27B (fine-tune) implements the task on the 5090.
# Phase 2: VANILLA Qwen3.6-27B reviews the workspace on the 3090.
#
# This is the MODEL-DIVERSITY CONTROL for the reviewer seat. Qwopus is a
# fine-tune OF vanilla Qwen3.6-27B, so here writer and reviewer are near
# siblings: same architecture, same pretraining, highly correlated blind spots.
# A reviewer that shares the writer's failure modes cannot see them.
#
# It isolates WHY a review phase helps at all:
#   - if the gain is just "a second pass with fresh context", a sibling reviewer
#     matches the Gemma pairing (86.2% uncapped) despite the correlation;
#   - if the gain requires genuine diversity, this UNDERPERFORMS Gemma even
#     though vanilla Qwen is the far stronger coder (~81% solo vs Gemma's 49.4%).
# Either outcome is informative, and it is the cleaner comparison because
# vanilla Qwen removes Gemma's weak-coder confound.
#
# --max-turns is held at the same value as the Gemma pairing so the reviewer
# MODEL is the only variable.
#
# Serving: q27 loads one .q27 per process and the 5090 is full with qwopus, so
# vanilla runs on the 3090 -- which requires the W8 build (`q27-server-w8`); the
# default W12 build OOMs at graph setup on a 24 GB card.
#
# Use the q4s repack + turbo3 KV. Both are counter-intuitive and both are the
# right call on Ampere:
#   - q4s (15.5 GB) is 0.66 bpw SMALLER than the default repack yet measurably
#     BETTER: wikitext-2 PPL 8.0197 vs 8.0409 (-0.26%), agentic NLL flat at CC
#     depths, needle 2/2 exact in a 248.7K prompt. It pays a code-acceptance
#     SPEED tax, not a quality tax. Every 3090 leg in q27's BENCHMARKING.md is
#     measured on it.
#   - turbo3 KV is already the serving DEFAULT on sm_86 (bare boot = turbo3 @
#     262144 on a 3090). Do NOT copy Q27_KV=fp8 from the 5090 recipe: the tax
#     ladder is 5090 fp8-wins-big / 4090 fp8-wins-small / 3090 turbo3-wins-
#     outright, because 800 B vs 4096 B per KV pair per token beats the dequant
#     compute on a bandwidth-starved part.
# Measured here: fp8 + default repack auto-sized to ctx 36864, which is BELOW
# what a 25-turn review transcript needs. q4s + turbo3 gives ctx 253952 in the
# same 23.3 GB -- ~7x, and comfortably past the Gemma arm's 128K, so context
# exhaustion cannot confound the reviewer comparison.
#
# Writer runs on the 5090 (qwopus via q27 :8080, reached through the bridge on
# :8081); reviewer runs on the 3090 (vanilla via q27-server-w8 :8084, bridge
# :8085). They never compute at the same time -- the phases are sequential -- so
# the split is purely about VRAM.
#
# Neither phase needs a translation shim: q27 speaks the Anthropic Messages API
# natively on both ends, and accepts any model name (verified). The two servers
# are separate processes because q27 loads exactly one .q27 per process.
#
# Reference points for the reviewer seat, same writer throughout:
#   DeepSeek v4 Flash (cloud)   90.1%  $0.58/task
#   Gemma 4 26B-A4B  (local)    86.2%  $0.00   (uncapped; 4 ctx-exhaustion crashes)
# This pairing also costs $0.00 and nothing leaves the box.

export HOME=/tmp

LOCAL_UPSTREAM="${LOCAL_UPSTREAM:-http://host.docker.internal:8081}"
REVIEW_MODEL="${REVIEW_MODEL:-qwen36-27b-mtp}"
REVIEW_UPSTREAM="${REVIEW_UPSTREAM:-http://host.docker.internal:8085}"

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
  echo "  Start VANILLA Qwen3.6-27B on the 3090 -- the W8 build is required," >&2
  echo "  the default W12 build OOMs at graph setup on a 24 GB card:" >&2
  echo "    CUDA_VISIBLE_DEVICES=1 Q27_KV=turbo3 /mnt/ai/projects/q27/build/q27-server-w8 \\" >&2
  echo "      /mnt/ai/models/qwen36-27b-mtp/qwen36-27b-mtp-q4s.q27 \\" >&2
  echo "      /mnt/ai/models/qwen36-27b-mtp/qwen36-27b-mtp.tok --port 8084" >&2
  echo "  (q4s + turbo3, NOT the default repack and NOT fp8 -- see header. Yields" >&2
  echo "   ctx 253952 on a 24 GB card; fp8 + default repack only reaches 36864.)" >&2
  echo "  q27 binds 127.0.0.1, so containers also need a second bridge:" >&2
  echo "    scripts/local-model-bridge.py --listen-port 8085 --target-port 8084" >&2
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

# ── Phase 2: VANILLA Qwen3.6-27B verifies and repairs ──────────────
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

# ── Metrics: both phases are local, so cost is $0 by construction ────
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
// Qwen runs locally: its tokens are real work but cost $0, so they are counted
// as turns only and deliberately kept out of total_cost_usd.
const qwenTurns = scan("/workspace/.qwen-output.jsonl", false);
const revTurns  = scan("/workspace/.thunderdome-output.jsonl", false);
m.turns = qwenTurns + revTurns;
m.phases = {writer: "qwopus-27b-local (free)", writer_turns: qwenTurns,
            reviewer: "qwen36-27b-vanilla-q4s-turbo3-local (free)", reviewer_turns: revTurns,
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
