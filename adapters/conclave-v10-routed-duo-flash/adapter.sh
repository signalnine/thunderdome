#!/bin/bash
set -e

# conclave-v10-routed-duo-flash: Two-tier routing -- Flash for everything
# except reasoning/hard tasks, Opus only when classifier picks HARD.
#
# Drops the middle (Sonnet) tier entirely. The Gemini-3-Flash classifier
# still picks TRIVIAL/EASY/HARD, but TRIVIAL and EASY both route to Flash.
#
# Why: standalone Flash hit 85.0% / $0.033 (n=38) -- competitive with or
# beats Sonnet on most EASY-routed tasks (T5, T8, T13, T16) while being
# 30x cheaper. The current routed-trio-flash spends $1.10/trial on Sonnet
# for EASY routes that Flash could plausibly handle at $0.04.
#
# Expected: ~85% / $0.15-0.25 (a fraction of the trio's $0.85).

[[ -f "$TASK_DESCRIPTION" ]] || { echo "Task file not found: $TASK_DESCRIPTION" >&2; exit 2; }

cd "$TASK_DIR"

export HOME=/tmp

if [ -f /tmp/.claude-credentials.json ]; then
  mkdir -p "$HOME/.claude"
  cp /tmp/.claude-credentials.json "$HOME/.claude/.credentials.json"
fi

if [ -n "$PROXY_URL" ]; then
  ORIG_BASE_URL="$PROXY_URL"
else
  ORIG_BASE_URL=""
fi

git config user.name "v10-routed-duo-flash"
git config user.email "v10-routed-duo-flash@thunderdome"

TASK_PROMPT=$(cat "$TASK_DESCRIPTION")
OUTPUT_FILE=/workspace/.thunderdome-output.jsonl

# ──────────────────────────────────────────────────────────────────
# ROUTING: Gemini 3 Flash classifies as TRIVIAL/EASY/HARD
# ──────────────────────────────────────────────────────────────────
echo "=== Routing: Gemini 3 Flash classifying task complexity (3-way) ===" >&2

read -r -d '' ROUTING_INSTRUCTIONS <<'EOF' || true
You are routing a coding task to one of three AI model tiers. Pick the cheapest tier that can reliably complete the task.

TIERS:
- TRIVIAL: Cheap fast model. Concrete CRUD, formatting, simple bugfixes, well-specified small features.
- EASY: Mid-tier model. Multi-file work, real state, debugging, and ALMOST ALL algorithmic work that allows iterative refinement (build, run tests, fix, repeat). This includes most "hard-sounding" tasks: constraint solving, graph algorithms, dependency resolution, reconstruction from logs, structural diffs, permission systems, financial precision, marathon multi-phase work. The mid-tier can iterate.
- HARD: Top-tier model. Reserve for combinatorial reverse-engineering where you must commit to one global structural answer and partial progress is hard to verify locally -- specifically, detecting swapped or mislabeled components from observed system behavior across many interacting parts.

KEY HEURISTIC: When in doubt, pick EASY. The mid-tier handles iteration well -- it can fail a test, look at output, adjust, and converge. HARD is only worth the 3-4x cost when iteration doesn't help.

CALIBRATION EXAMPLES:

Task: "Build a CLI time tracker with start/stop/list commands, storing entries in a JSON file."
Tier: TRIVIAL
Reason: Concrete CRUD, well-defined data model.

Task: "Add a full-text search endpoint with stemming, BM25 ranking, and case-insensitive prefix matching."
Tier: TRIVIAL
Reason: Library work, documented patterns.

Task: "Build a plugin marketplace API with installations, semver dependency resolution, and offline cache."
Tier: EASY
Reason: Multi-component but follows established patterns.

Task: "Build a reactive spreadsheet with formula dependency tracking, cycle detection, and dirty propagation."
Tier: EASY
Reason: Standard reactive pattern; iterative test-and-fix works.

Task: "Given a corrupted factory state with missing config and partial production logs, rebuild the configuration."
Tier: HARD
Reason: Stateful reconstruction with global consistency requirements -- the mid-tier tends to thrash on long-horizon planning; the top tier converges faster and more reliably.

Task: "Implement a scheduler that finds a valid assignment of N tasks to M workers under capacity and dependency constraints."
Tier: EASY
Reason: Constraint solving with iterative testing.

Task: "Find the minimum set of button presses that toggles all N lights to a target configuration, where each button toggles a fixed subset of lights."
Tier: HARD
Reason: Minimum-set-cover under combinatorial constraints. Requires global reasoning about XOR over GF(2); mid-tier thrashes on the exact-minimum requirement.

Task: "Given observed input/output behavior of a circuit with 200 gates, two wires are swapped somewhere -- identify the specific swap and produce corrected wiring."
Tier: HARD
Reason: Combinatorial reverse-engineering with global invariants. Must commit to a single answer about which two specific wires; partial guesses are hard to verify locally.

INSTRUCTION: Read the task below. Respond with one word only: TRIVIAL, EASY, or HARD. No explanation.

=== TASK ===
EOF

# Gemini 3 Flash is a reasoning model -- need thinking budget=0 and enough
# output tokens to emit the classification.
ROUTING_REQUEST=$(jq -n \
  --arg sys "$ROUTING_INSTRUCTIONS" \
  --arg user "$TASK_PROMPT" \
  '{
    contents: [{parts: [{text: ($sys + "\n" + $user)}]}],
    generationConfig: {
      maxOutputTokens: 1024,
      temperature: 0,
      thinkingConfig: {thinkingBudget: 0}
    }
  }')

ROUTING_RESPONSE=$(curl -sS --max-time 30 \
  -X POST "https://generativelanguage.googleapis.com/v1beta/models/gemini-3-flash-preview:generateContent?key=$GEMINI_API_KEY" \
  -H "Content-Type: application/json" \
  -d "$ROUTING_REQUEST" 2>/dev/null || echo '{}')

ROUTING_RESULT=$(echo "$ROUTING_RESPONSE" | jq -r '.candidates[0].content.parts[0].text // ""' 2>/dev/null || echo "")

if echo "$ROUTING_RESULT" | grep -qi "HARD"; then
  ROUTING_DECISION="HARD"
elif echo "$ROUTING_RESULT" | grep -qi "TRIVIAL"; then
  ROUTING_DECISION="TRIVIAL"
elif echo "$ROUTING_RESULT" | grep -qi "EASY"; then
  ROUTING_DECISION="EASY"
else
  ROUTING_DECISION="HARD"
fi

echo "  Gemini 3 Flash said: $ROUTING_RESULT" >&2
echo "  Routing decision: $ROUTING_DECISION" >&2

# ──────────────────────────────────────────────────────────────────
# IMPLEMENTATION: route to backend (identical to routed-trio)
# ──────────────────────────────────────────────────────────────────
V8_PROMPT="You are running in a headless benchmark environment. No human to interact with. Work directly in the current directory -- no worktrees or branches.

## How to Work

### 1. Understand First
Read the task fully. Read existing code, tests, and config files. Understand what exists before writing anything.

### 2. Write a Contract BEFORE Any Code
Before writing any implementation, create a CONTRACT.md file that defines:

1. **Every behavior** the finished code must exhibit -- be specific and exhaustive
2. **How to verify each behavior** -- the exact test, command, or check that proves it works
3. **What done looks like** for each criterion -- expected output, return value, or state

This contract is your definition of done. You are not finished until every criterion passes.

### 3. Test-First Development (MANDATORY -- NOT OPTIONAL)
For each contract criterion, you MUST write a failing test BEFORE any implementation code.

**The process:**
1. Pick the next contract criterion
2. Write a test that verifies it
3. Run it -- watch it FAIL (this proves the test works)
4. Write the minimal code to make it pass
5. Run it -- watch it PASS
6. Repeat for the next criterion

**If you catch yourself writing implementation without a test first, STOP IMMEDIATELY.**
Delete the implementation code. Write the test first. Then re-implement.

### 4. Boil the Lake
AI-assisted coding makes completeness nearly free. Always do the complete implementation:
- Handle ALL edge cases, not just happy paths
- Write comprehensive tests -- cover boundaries, errors, empty inputs
- Implement the full feature, not 90% of it

### 5. Verify Against Contract
After implementation, go through CONTRACT.md line by line:
- Run each verification check
- Fix ALL failures before moving on
- Do not stop until every criterion in the contract passes

Done means: all contract criteria pass, tests pass, build clean, lint clean."

set +e
case "$ROUTING_DECISION" in
  HARD)
    echo "=== Implementation: Opus 4.6 (OAuth) ===" >&2
    SELECTED_MODEL_LABEL="claude-opus-4-6"
    [ -n "$ORIG_BASE_URL" ] && export ANTHROPIC_BASE_URL="$ORIG_BASE_URL"
    claude -p \
      --model claude-opus-4-6 \
      --output-format stream-json \
      --verbose \
      --dangerously-skip-permissions \
      --disallowed-tools "AskUserQuestion,EnterPlanMode" \
      --append-system-prompt "$V8_PROMPT" \
      -- "$TASK_PROMPT" \
      > "$OUTPUT_FILE" 2>/workspace/.thunderdome-stderr.log
    ;;
  *)
    # TRIVIAL or EASY -> DeepSeek v4 Flash (native API)
    echo "=== Implementation: DeepSeek v4 Flash (native API) ===" >&2
    SELECTED_MODEL_LABEL="deepseek-v4-flash"
    export ANTHROPIC_BASE_URL="https://api.deepseek.com/anthropic"
    export ANTHROPIC_AUTH_TOKEN="$DEEPSEEK_API_KEY"
    unset ANTHROPIC_API_KEY
    export ANTHROPIC_DEFAULT_OPUS_MODEL="deepseek-v4-flash"
    export ANTHROPIC_DEFAULT_SONNET_MODEL="deepseek-v4-flash"
    export ANTHROPIC_DEFAULT_HAIKU_MODEL="deepseek-v4-flash"
    export CLAUDE_CODE_SUBAGENT_MODEL="deepseek-v4-flash"
    claude -p \
      --output-format stream-json \
      --verbose \
      --dangerously-skip-permissions \
      --disallowed-tools "AskUserQuestion,EnterPlanMode" \
      --append-system-prompt "$V8_PROMPT" \
      -- "$TASK_PROMPT" \
      > "$OUTPUT_FILE" 2>/workspace/.thunderdome-stderr.log
    ;;
esac
CLAUDE_EXIT=$?
set -e

echo "Claude Code exited: $CLAUDE_EXIT (model: $SELECTED_MODEL_LABEL, route: $ROUTING_DECISION)" >&2

node -e '
const fs = require("fs");
const PRICE_IN  = 0.07 / 1e6;
const PRICE_OUT = 0.27 / 1e6;
const PRICE_CACHE_READ = 0.01 / 1e6;
const PRICE_CACHE_WRITE = 0.09 / 1e6;
const model = process.argv[2];
const route = process.argv[3];
const isDeepSeek = model === "deepseek-v4-flash";
try {
  const lines = fs.readFileSync(process.argv[1], "utf8").split("\n");
  const metrics = {
    input_tokens: 0, output_tokens: 0, cache_read_tokens: 0,
    cache_creation_tokens: 0, turns: 0, tools_used: [],
    duration_ms: 0, total_cost_usd: 0,
    routed_model: model, routing_decision: route,
  };
  const seen = new Set();
  for (const line of lines) {
    if (!line.trim()) continue;
    let m;
    try { m = JSON.parse(line); } catch { continue; }
    if (m.type === "result") {
      const u = m.usage || {};
      metrics.input_tokens          = u.input_tokens          || 0;
      metrics.output_tokens         = u.output_tokens         || 0;
      metrics.cache_read_tokens     = u.cache_read_input_tokens     || 0;
      metrics.cache_creation_tokens = u.cache_creation_input_tokens || 0;
      metrics.turns       = m.num_turns    || 0;
      metrics.duration_ms = m.duration_ms  || 0;
      if (!isDeepSeek) metrics.total_cost_usd = m.total_cost_usd || 0;
    }
    if (m.type === "assistant" && m.message && Array.isArray(m.message.content)) {
      for (const b of m.message.content) {
        if (b.type === "tool_use" && b.name && !seen.has(b.name)) {
          seen.add(b.name);
          metrics.tools_used.push(b.name);
        }
      }
    }
  }
  if (isDeepSeek) {
    metrics.total_cost_usd = +(
        metrics.input_tokens          * PRICE_IN
      + metrics.output_tokens         * PRICE_OUT
      + metrics.cache_read_tokens     * PRICE_CACHE_READ
      + metrics.cache_creation_tokens * PRICE_CACHE_WRITE
    ).toFixed(6);
  }
  fs.writeFileSync("/workspace/.thunderdome-metrics.json", JSON.stringify(metrics, null, 2));
  console.error("Metrics: " + JSON.stringify(metrics));
} catch(e) {
  console.error("Metrics extraction failed: " + e.message);
}
' "$OUTPUT_FILE" "$SELECTED_MODEL_LABEL" "$ROUTING_DECISION" || true

exit $CLAUDE_EXIT
