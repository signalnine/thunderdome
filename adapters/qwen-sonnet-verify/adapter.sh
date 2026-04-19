#!/bin/bash
set -e

# qwen-sonnet-verify: No routing. Qwen3.6 codes, Sonnet verifies and fixes.
# Phase 1: Claude Code + Qwen3.6 via Neuralwatt anthropic proxy does impl.
# Phase 2: Claude Code + Sonnet via Anthropic OAuth runs verification pass.
# Baseline: Qwen3.6 alone = 70.3%. Sonnet v8 alone = 88.6%. Hybrid lands where?

[[ -f "$TASK_DESCRIPTION" ]] || { echo "Task file not found: $TASK_DESCRIPTION" >&2; exit 2; }

cd "$TASK_DIR"

export HOME=/tmp

if [ -f /tmp/.claude-credentials.json ]; then
  mkdir -p "$HOME/.claude"
  cp /tmp/.claude-credentials.json "$HOME/.claude/.credentials.json"
fi

TASK_PROMPT=$(cat "$TASK_DESCRIPTION")

# ── Phase 1: Qwen3.6 writes the implementation ──────────────────────
echo "=== Phase 1: Qwen3.6 implementation ===" >&2

PROXY_PORT=18902
PROXY_LOG=/workspace/.qwen-proxy.jsonl

python3 /usr/local/bin/anthropic_proxy.py \
  --port $PROXY_PORT \
  --log "$PROXY_LOG" \
  --upstream "https://api.neuralwatt.com" \
  --model-rewrite "claude=Qwen/Qwen3.6-35B-A3B" \
  --api-key "$NEURALWATT_API_KEY" &
PROXY_PID=$!

for i in $(seq 1 30); do
  curl -s http://localhost:$PROXY_PORT/health >/dev/null 2>&1 && break
  sleep 0.2
done

export ANTHROPIC_BASE_URL="http://localhost:$PROXY_PORT"
export ANTHROPIC_API_KEY="placeholder"

QWEN_OUTPUT=/workspace/.qwen-output.jsonl

set +e
claude -p \
  --output-format stream-json \
  --verbose \
  --dangerously-skip-permissions \
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

kill $PROXY_PID 2>/dev/null || true

# ── Phase 2: Sonnet verifies and fixes ──────────────────────────────
echo "=== Phase 2: Sonnet verification pass ===" >&2

unset ANTHROPIC_BASE_URL
unset ANTHROPIC_API_KEY
# Restore OAuth credentials for Sonnet (claude -p reads from ~/.claude/.credentials.json)
if [ -f /tmp/.claude-credentials.json ]; then
  mkdir -p "$HOME/.claude"
  cp /tmp/.claude-credentials.json "$HOME/.claude/.credentials.json"
fi

SONNET_OUTPUT=/workspace/.thunderdome-output.jsonl

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
  --model claude-sonnet-4-6 \
  --output-format stream-json \
  --verbose \
  --dangerously-skip-permissions \
  --disallowed-tools "AskUserQuestion,EnterPlanMode" \
  -- "$REVIEW_PROMPT" \
  > "$SONNET_OUTPUT" 2>/workspace/.sonnet-stderr.log
SONNET_EXIT=$?
set -e

# ── Metrics: combine Qwen (energy-priced) + Sonnet (tokens) ─────────
node -e '
const fs = require("fs");
function qwenTurns(log) {
  try {
    return fs.readFileSync(log, "utf8").split("\n").filter(l => l.trim()).length;
  } catch { return 0; }
}
function sonnetMetrics(f) {
  const m = {input_tokens:0,output_tokens:0,cache_read:0,cache_creation:0,duration_ms:0,total_cost_usd:0,turns:0,tools_used:[]};
  try {
    const lines = fs.readFileSync(f,"utf8").split("\n");
    const tools = new Set();
    for (const line of lines) {
      if (!line.trim()) continue;
      try {
        const msg = JSON.parse(line);
        if (msg.type === "result") {
          if (msg.usage) {
            m.input_tokens = msg.usage.input_tokens || 0;
            m.output_tokens = msg.usage.output_tokens || 0;
            m.cache_read = msg.usage.cache_read_input_tokens || 0;
            m.cache_creation = msg.usage.cache_creation_input_tokens || 0;
          }
          m.turns = msg.num_turns || 0;
          m.duration_ms = msg.duration_ms || 0;
          m.total_cost_usd = msg.total_cost_usd || 0;
        }
        if (msg.type === "assistant" && msg.message && Array.isArray(msg.message.content)) {
          for (const b of msg.message.content) {
            if (b.type === "tool_use" && b.name && !tools.has(b.name)) {
              tools.add(b.name); m.tools_used.push(b.name);
            }
          }
        }
      } catch {}
    }
  } catch {}
  return m;
}
const qturns = qwenTurns("/workspace/.qwen-proxy.jsonl");
const s = sonnetMetrics("/workspace/.thunderdome-output.jsonl");
// Qwen energy-priced: $0.00208/turn. Sonnet: already USD from claude -p.
const qwenCost = qturns * 0.00208;
const combined = {
  input_tokens: s.input_tokens,
  output_tokens: s.output_tokens,
  cache_read_tokens: s.cache_read,
  cache_creation_tokens: s.cache_creation,
  turns: qturns + s.turns,
  tools_used: s.tools_used,
  duration_ms: s.duration_ms,
  total_cost_usd: Math.round((qwenCost + s.total_cost_usd) * 1000000) / 1000000,
  qwen_turns: qturns,
  qwen_cost_usd: Math.round(qwenCost * 1000000) / 1000000,
  sonnet_cost_usd: s.total_cost_usd
};
fs.writeFileSync("/workspace/.thunderdome-metrics.json", JSON.stringify(combined, null, 2));
console.error("Metrics: " + JSON.stringify(combined));
' || true

exit $SONNET_EXIT
