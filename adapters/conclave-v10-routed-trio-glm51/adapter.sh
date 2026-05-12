#!/bin/bash
set -e

# conclave-v10-routed-trio-glm51: GLM-5.1-fast-routed three-way model selection.
#
# Identical to conclave-v10-routed-trio but swaps the Haiku 4.5 classifier
# for GLM-5.1-fast on Neuralwatt. Offline router-test (5 trials x 19 tasks,
# 2026-05-12) showed glm-5.1-fast gives 100% deterministic classification
# and 84% agreement with Haiku, at ~$0 cost (energy-billed) vs Haiku's
# ~$0.005/route. Most disagreements skew GLM cheaper than Haiku.
#
# Routing tax: ~$0 (Neuralwatt energy-billed)
# Expected: ~87% / $0.85 (same as Haiku-routed trio, minus the Haiku tax)

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

git config user.name "v10-routed-trio-glm51"
git config user.email "v10-routed-trio-glm51@thunderdome"

TASK_PROMPT=$(cat "$TASK_DESCRIPTION")
OUTPUT_FILE=/workspace/.thunderdome-output.jsonl

# ──────────────────────────────────────────────────────────────────
# ROUTING: GLM-5.1-fast via Neuralwatt classifies as TRIVIAL/EASY/HARD
# ──────────────────────────────────────────────────────────────────
echo "=== Routing: GLM-5.1-fast classifying task complexity (3-way) ===" >&2

# Few-shot routing prompt -- validated 2026-05-12 with 100% determinism on glm-5.1-fast
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
Tier: EASY
Reason: Reconstruction is iterative -- propose, check against logs, refine. Mid-tier converges.

Task: "Find the minimum set of button presses that toggles all N lights to ON, given each button toggles a fixed subset."
Tier: EASY
Reason: Set cover / XOR over GF(2) is a standard algorithmic pattern; mid-tier can implement and test.

Task: "Implement a scheduler that finds a valid assignment of N tasks to M workers under capacity and dependency constraints."
Tier: EASY
Reason: Constraint solving with iterative testing.

Task: "Given observed input/output behavior of a circuit with 200 gates, two wires are swapped somewhere -- identify the specific swap and produce corrected wiring."
Tier: HARD
Reason: Combinatorial reverse-engineering with global invariants. Must commit to a single answer about which two specific wires; partial guesses are hard to verify locally.

INSTRUCTION: Read the task below. Respond with one word only: TRIVIAL, EASY, or HARD. No explanation.

=== TASK ===
EOF

ROUTING_REQUEST=$(jq -n \
  --arg sys "$ROUTING_INSTRUCTIONS" \
  --arg user "$TASK_PROMPT" \
  '{
    model: "glm-5.1-fast",
    max_tokens: 16,
    temperature: 0,
    messages: [{role: "user", content: ($sys + "\n" + $user)}]
  }')

# Neuralwatt requires a browser User-Agent to clear Cloudflare WAF.
# Default to HARD on any failure (parse error, network, etc.) to avoid
# under-routing -- expensive Sonnet timeout > cheap Opus over-spend.
ROUTING_RESPONSE=$(curl -sS --max-time 30 \
  -X POST https://api.neuralwatt.com/v1/chat/completions \
  -H "Authorization: Bearer $NEURALWATT_API_KEY" \
  -H "Content-Type: application/json" \
  -H "User-Agent: Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36" \
  -d "$ROUTING_REQUEST" 2>/dev/null || echo '{}')

ROUTING_RESULT=$(echo "$ROUTING_RESPONSE" | jq -r '.choices[0].message.content // ""' 2>/dev/null || echo "")

if echo "$ROUTING_RESULT" | grep -qi "HARD"; then
  ROUTING_DECISION="HARD"
elif echo "$ROUTING_RESULT" | grep -qi "TRIVIAL"; then
  ROUTING_DECISION="TRIVIAL"
elif echo "$ROUTING_RESULT" | grep -qi "EASY"; then
  ROUTING_DECISION="EASY"
else
  ROUTING_DECISION="HARD"
fi

echo "  GLM-5.1-fast said: $ROUTING_RESULT" >&2
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
  TRIVIAL)
    echo "=== Implementation: DeepSeek v4 Pro (native API) ===" >&2
    SELECTED_MODEL_LABEL="deepseek-v4-pro"
    export ANTHROPIC_BASE_URL="https://api.deepseek.com/anthropic"
    export ANTHROPIC_AUTH_TOKEN="$DEEPSEEK_API_KEY"
    unset ANTHROPIC_API_KEY
    export ANTHROPIC_DEFAULT_OPUS_MODEL="deepseek-v4-pro"
    export ANTHROPIC_DEFAULT_SONNET_MODEL="deepseek-v4-pro"
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
    echo "=== Implementation: Sonnet 4.6 (OAuth) ===" >&2
    SELECTED_MODEL_LABEL="claude-sonnet-4-6"
    [ -n "$ORIG_BASE_URL" ] && export ANTHROPIC_BASE_URL="$ORIG_BASE_URL"
    claude -p \
      --model claude-sonnet-4-6 \
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
const PRICE_IN  = 0.435 / 1e6;
const PRICE_OUT = 0.87  / 1e6;
const PRICE_CACHE_READ = 0.04 / 1e6;
const PRICE_CACHE_WRITE = 0.55 / 1e6;
const model = process.argv[2];
const route = process.argv[3];
const isDeepSeek = model === "deepseek-v4-pro";
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
