#!/bin/bash
set -e

# conclave-v10-routed-trio: Haiku-routed three-way model selection.
#
# Routes tasks to DeepSeek v4 Pro, Sonnet 4.6, or Opus 4.6 based on Haiku's
# complexity classification. Implementation uses the v8 no-review prompt.
#
# Hypothesis: v10 routed lands at 90.4% by sending easy tasks to Sonnet and
# hard tasks to Opus. Adding DeepSeek as a third tier for "trivial" tasks
# saves ~50c/task on the easiest work without quality loss (DeepSeek scores
# near-1.0 on fts-search/monorepo/ssg/debug-nightmare/phantom-invoice).
# Hard tasks still go to Opus (best reasoning); medium to Sonnet.
#
# Routing tax: Haiku call ~$0.005/task. If accurate, expect <$1.00/task avg.

[[ -f "$TASK_DESCRIPTION" ]] || { echo "Task file not found: $TASK_DESCRIPTION" >&2; exit 2; }

cd "$TASK_DIR"

export HOME=/tmp

# Mount OAuth credentials so Haiku/Sonnet/Opus can use the user's plan
if [ -f /tmp/.claude-credentials.json ]; then
  mkdir -p "$HOME/.claude"
  cp /tmp/.claude-credentials.json "$HOME/.claude/.credentials.json"
fi

if [ -n "$PROXY_URL" ]; then
  ORIG_BASE_URL="$PROXY_URL"
else
  ORIG_BASE_URL=""
fi

git config user.name "v10-routed-trio"
git config user.email "v10-routed-trio@thunderdome"

TASK_PROMPT=$(cat "$TASK_DESCRIPTION")
OUTPUT_FILE=/workspace/.thunderdome-output.jsonl

# ──────────────────────────────────────────────────────────────────
# ROUTING: Haiku classifies as TRIVIAL / EASY / HARD
# ──────────────────────────────────────────────────────────────────
echo "=== Routing: classifying task complexity (3-way) ===" >&2

ROUTING_PROMPT="You are a task complexity classifier. Read the task description below and classify it as TRIVIAL, EASY, or HARD.

A task is TRIVIAL if ALL of these hold:
- The spec is concrete and unambiguous
- Implementation is straightforward (CRUD, formatting, well-known patterns)
- Few interacting components; simple data flow
- A capable junior engineer could finish it without research
- Examples: write a small library with documented API, implement standard search/index, fix bugs with clear repro steps

A task is HARD if it has ANY of these characteristics:
- Algorithmic reasoning requiring careful logic (constraint solving, graph analysis, structural pattern recognition)
- Concurrent or async operations with ordering constraints that must be reasoned about
- Deeply ambiguous specifications requiring significant inference
- Edge-case-rich numeric work (decimals, overflow, financial precision)
- Multiple subsystems that must coordinate under invariants (real-time + persistence + protocol)
- Reverse-engineering circuit/system structure from behavior

A task is EASY if it falls between -- non-trivial but not algorithmically hard. Multiple components, some state, but follows established patterns.

Respond with ONLY one of these three words: TRIVIAL, EASY, or HARD. Nothing else.

=== TASK DESCRIPTION ===
$TASK_PROMPT"

# Call Haiku via OAuth (cheapest)
ROUTING_RESULT=$(claude -p \
  --model claude-haiku-4-5-20251001 \
  --max-turns 1 \
  -- "$ROUTING_PROMPT" 2>/dev/null || echo "EASY")

# Parse the classification (default to EASY on garbled output)
if echo "$ROUTING_RESULT" | grep -qi "HARD"; then
  ROUTING_DECISION="HARD"
elif echo "$ROUTING_RESULT" | grep -qi "TRIVIAL"; then
  ROUTING_DECISION="TRIVIAL"
else
  ROUTING_DECISION="EASY"
fi

echo "  Haiku said: $ROUTING_RESULT" >&2
echo "  Routing decision: $ROUTING_DECISION" >&2

# ──────────────────────────────────────────────────────────────────
# IMPLEMENTATION: route to backend
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
    # DeepSeek native Anthropic endpoint -- no proxy translation
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

# ──────────────────────────────────────────────────────────────────
# METRICS
# ──────────────────────────────────────────────────────────────────
# DeepSeek v4 Pro pricing if used; otherwise rely on Anthropic's reported cost
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
