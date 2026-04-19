#!/bin/bash
set -e

# v11-qwen-routed: Haiku routing.
# EASY -> Qwen3.6 (zen-lite) + Sonnet verify pass (review + fix + green tests)
# HARD -> Sonnet v8 no-review (same as v10's hard path -- direct implementation)
# Tests whether Qwen handles easy tasks well enough that Sonnet review is cheap,
# while Sonnet still leads on hard tasks.

[[ -f "$TASK_DESCRIPTION" ]] || { echo "Task file not found: $TASK_DESCRIPTION" >&2; exit 2; }

cd "$TASK_DIR"

export HOME=/tmp

if [ -f /tmp/.claude-credentials.json ]; then
  mkdir -p "$HOME/.claude"
  cp /tmp/.claude-credentials.json "$HOME/.claude/.credentials.json"
fi

TASK_PROMPT=$(cat "$TASK_DESCRIPTION")

# ── Haiku classifier ────────────────────────────────────────────────
echo "=== Routing: Haiku classifier ===" >&2

ROUTING_PROMPT="You are a task complexity classifier. Read the task description below and classify it as HARD or EASY.

A task is HARD if it has ANY of these characteristics:
- Complex state management with multiple interacting components that must stay consistent
- Concurrent or async operations with ordering constraints
- Algorithmic reasoning requiring careful logic (scheduling, constraint solving, graph traversal)
- Ambiguous specifications requiring significant inference about intended behavior
- Multiple subsystems that must coordinate (e.g., real-time updates + persistence + API)
- Complex data transformations with edge cases (overflow, empty, boundary conditions)

A task is EASY if it is:
- A straightforward CRUD feature or API endpoint
- A bug fix with clear reproduction steps
- A well-specified feature with clear inputs/outputs
- Adding tests, documentation, or configuration
- Simple refactoring or code cleanup

Respond with ONLY the single word HARD or EASY. Nothing else.

=== TASK DESCRIPTION ===
$TASK_PROMPT"

ROUTING_RESULT=$(claude -p \
  --model claude-haiku-4-5-20251001 \
  --max-turns 1 \
  -- "$ROUTING_PROMPT" 2>/dev/null || echo "EASY")

if echo "$ROUTING_RESULT" | grep -qi "HARD"; then
  ROUTE="HARD"
  echo "  Routing decision: HARD -> Sonnet v8 direct" >&2
else
  ROUTE="EASY"
  echo "  Routing decision: EASY -> Qwen + Sonnet verify" >&2
fi

# Common v8 no-review prompt (shared by Qwen zen-lite and Sonnet hard path)
SONNET_V8_PROMPT="You are running in a headless benchmark environment. No human to interact with. Work directly in the current directory -- no worktrees or branches.

## How to Work

### 1. Understand First
Read the task fully. Read existing code, tests, and config files. Understand what exists before writing anything.

### 2. Write a Contract BEFORE Any Code
Before writing any implementation, create a CONTRACT.md file that defines every behavior the finished code must exhibit, how to verify each one, and what done looks like. This is your definition of done.

### 3. Test-First Development (MANDATORY)
For each contract criterion, write a failing test BEFORE implementation. Run it and watch it fail. Then write the minimal code to make it pass. Then run it again to watch it pass. Repeat.

### 4. Boil the Lake
Handle ALL edge cases, not just happy paths. Write comprehensive tests. Implement the full feature, not 90% of it.

### 5. Verify Against Contract
Go through CONTRACT.md line by line. Run each check. Fix ALL failures before moving on.

Done means: all contract criteria pass, tests pass, build clean, lint clean."

ZEN_LITE_PROMPT="# The Way of Calm Precision

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

Write the simple, correct solution. A calm craftsperson writes less code, not more."

QWEN_TURNS=0

if [ "$ROUTE" = "HARD" ]; then
  # ── HARD: Sonnet v8 direct ──────────────────────────────────────
  echo "=== HARD path: Sonnet v8 ===" >&2
  OUTPUT_FILE=/workspace/.thunderdome-output.jsonl

  set +e
  claude -p \
    --model claude-sonnet-4-6 \
    --output-format stream-json \
    --verbose \
    --dangerously-skip-permissions \
    --disallowed-tools "AskUserQuestion,EnterPlanMode" \
    --append-system-prompt "$SONNET_V8_PROMPT" \
    -- "$TASK_PROMPT" \
    > "$OUTPUT_FILE" 2>/workspace/.thunderdome-stderr.log
  EXIT_CODE=$?
  set -e
else
  # ── EASY: Qwen zen-lite, then Sonnet verify ─────────────────────
  echo "=== EASY path, Phase 1: Qwen3.6 zen-lite ===" >&2

  PROXY_PORT=18903
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

  set +e
  claude -p \
    --output-format stream-json \
    --verbose \
    --dangerously-skip-permissions \
    --disallowed-tools "AskUserQuestion,EnterPlanMode" \
    --append-system-prompt "$ZEN_LITE_PROMPT" \
    -- "$TASK_PROMPT" \
    > /workspace/.qwen-output.jsonl 2>/workspace/.qwen-stderr.log
  set -e

  kill $PROXY_PID 2>/dev/null || true

  if [ -f "$PROXY_LOG" ]; then
    QWEN_TURNS=$(wc -l < "$PROXY_LOG" | tr -d ' ')
  fi

  echo "=== EASY path, Phase 2: Sonnet verify ===" >&2

  unset ANTHROPIC_BASE_URL
  unset ANTHROPIC_API_KEY
  if [ -f /tmp/.claude-credentials.json ]; then
    mkdir -p "$HOME/.claude"
    cp /tmp/.claude-credentials.json "$HOME/.claude/.credentials.json"
  fi

  REVIEW_PROMPT="Another agent has just attempted this task:

$TASK_PROMPT

The workspace reflects their attempt. Your job is verification and repair, not feature work.

1. Run: npm install (if needed), npm run build, npm test, npm run lint.
2. Read any failures carefully.
3. Fix the code so every test passes and build/lint are clean.
4. Do NOT add features the task didn't ask for.
5. Do NOT delete or modify files in tests/ unless the previous agent's implementation is obviously wrong.
6. Keep iterating until everything is green.

Done means: build passes, tests pass, lint passes."

  OUTPUT_FILE=/workspace/.thunderdome-output.jsonl

  set +e
  claude -p \
    --model claude-sonnet-4-6 \
    --output-format stream-json \
    --verbose \
    --dangerously-skip-permissions \
    --disallowed-tools "AskUserQuestion,EnterPlanMode" \
    -- "$REVIEW_PROMPT" \
    > "$OUTPUT_FILE" 2>/workspace/.thunderdome-stderr.log
  EXIT_CODE=$?
  set -e
fi

# ── Metrics ─────────────────────────────────────────────────────────
node -e '
const fs = require("fs");
const route = process.argv[2];
const qwenTurns = parseInt(process.argv[3]) || 0;
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
const s = sonnetMetrics("/workspace/.thunderdome-output.jsonl");
const qwenCost = qwenTurns * 0.00208;
const combined = {
  input_tokens: s.input_tokens,
  output_tokens: s.output_tokens,
  cache_read_tokens: s.cache_read,
  cache_creation_tokens: s.cache_creation,
  turns: qwenTurns + s.turns,
  tools_used: s.tools_used,
  duration_ms: s.duration_ms,
  total_cost_usd: Math.round((qwenCost + s.total_cost_usd) * 1000000) / 1000000,
  route: route,
  qwen_turns: qwenTurns,
  qwen_cost_usd: Math.round(qwenCost * 1000000) / 1000000,
  sonnet_cost_usd: s.total_cost_usd
};
fs.writeFileSync("/workspace/.thunderdome-metrics.json", JSON.stringify(combined, null, 2));
console.error("Metrics: " + JSON.stringify(combined));
' "$ROUTE" "$QWEN_TURNS" || true

exit ${EXIT_CODE:-0}
