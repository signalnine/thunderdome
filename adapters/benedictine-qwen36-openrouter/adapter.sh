#!/bin/bash
set -e

# Benedictine + Qwen3.6 via OpenRouter native Anthropic endpoint.
# Skips our broken anth2openai_proxy.py entirely (which hangs on
# tool_result followups for non-Anthropic models). OpenRouter's
# /api/v1/messages serves Qwen3.6-35B-A3B in native Anthropic shape.
# OpenRouter pricing per token, not Neuralwatt's energy-priced flat rate.

[[ -f "$TASK_DESCRIPTION" ]] || { echo "Task file not found: $TASK_DESCRIPTION" >&2; exit 2; }

cd "$TASK_DIR"

export ANTHROPIC_BASE_URL="https://openrouter.ai/api"
export ANTHROPIC_AUTH_TOKEN="$OPENROUTER_API_KEY"
unset ANTHROPIC_API_KEY

export ANTHROPIC_DEFAULT_OPUS_MODEL="qwen/qwen3.6-35b-a3b"
export ANTHROPIC_DEFAULT_SONNET_MODEL="qwen/qwen3.6-35b-a3b"
export ANTHROPIC_DEFAULT_HAIKU_MODEL="qwen/qwen3.6-35b-a3b"
export CLAUDE_CODE_SUBAGENT_MODEL="qwen/qwen3.6-35b-a3b"

TASK_PROMPT=$(cat "$TASK_DESCRIPTION")
OUTPUT_FILE=/workspace/.thunderdome-output.jsonl

echo "=== Claude Code (Benedictine + Qwen3.6 via OpenRouter): Starting ==="

set +e
claude -p \
  --output-format stream-json \
  --verbose \
  --dangerously-skip-permissions \
  --disallowed-tools "AskUserQuestion,EnterPlanMode" \
  --append-system-prompt "You are running in a headless benchmark environment. No human to interact with. Work directly in the current directory.

# The Rule of the Workshop

Ora et labora -- pray and work. The craftsperson keeps the hours. Each phase has its season; do not confuse them.

## Lectio: The Reading

First, read. Read the task slowly, twice if needed. Then read the surrounding land: src/, tests/, package.json. Lectio is not skimming -- it is letting the text say what it says before you respond. The codebase has its own life and its own customs; learn them before you presume to add. Do not guess -- know.

## Meditatio: The Sitting With

Pause after reading. Hold the task in mind without rushing to act. What does the work actually require? What is essential, what is decoration? The novice reaches for tools immediately; the experienced hand sits a moment longer, and finishes sooner. Resist the urge to begin building before you have understood.

## Oratio: Let the Tests Speak

For each behavior the task asks for, write the test before the code. Run it. Watch it fail. The failing test is the small voice that tells you precisely what to build, no more and no less. Write the minimum to make it pass. Then the next test. Then the next.

If you catch yourself writing code without its test, stop. That is the agitation of haste. Set it aside. Begin the cycle again, properly.

## Contemplatio: The Full Verification

When the work feels done, prove it done. Run npm install if needed, then npm run build, npm test, npm run lint. Mend every failure. The Rule does not permit calling work complete before it is complete. Iterate with the steady patience of one who keeps the hours -- without panic, without sloth, without skipping the office.

Humility is the mark of good craft: write less code, not more. Decoration is vanity; the simple correct solution is the prayer answered. Complete the task, then rest." \
  -- "$TASK_PROMPT" \
  > "$OUTPUT_FILE" 2>/workspace/.thunderdome-stderr.log
CLAUDE_EXIT=$?
set -e

echo "Claude Code exited: $CLAUDE_EXIT"

# Qwen3.6-35B-A3B on OpenRouter: $0.15/M input, $1.00/M output.
# Cost per turn varies; pricing computed locally since OpenRouter usage
# data is non-Anthropic-shape and Claude Code reports nothing.
node -e '
const fs = require("fs");
const PRICE_IN  = 0.15 / 1e6;
const PRICE_OUT = 1.00 / 1e6;
try {
  const lines = fs.readFileSync(process.argv[1], "utf8").split("\n");
  const metrics = {
    input_tokens: 0, output_tokens: 0, cache_read_tokens: 0,
    cache_creation_tokens: 0, turns: 0, tools_used: [],
    duration_ms: 0, total_cost_usd: 0,
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
  metrics.total_cost_usd = +(metrics.input_tokens * PRICE_IN + metrics.output_tokens * PRICE_OUT).toFixed(6);
  fs.writeFileSync("/workspace/.thunderdome-metrics.json", JSON.stringify(metrics, null, 2));
  console.error("Metrics: " + JSON.stringify(metrics));
} catch(e) {
  console.error("Metrics extraction failed: " + e.message);
}
' "$OUTPUT_FILE"

echo "=== Claude Code (Benedictine + Qwen3.6) adapter complete ==="
exit $CLAUDE_EXIT
