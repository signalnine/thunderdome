#!/bin/bash
set -e

# --- CRUSH + Qwen3.6-35B-A3B via Neuralwatt + zen-lite CRUSH.md ---
# Combines:
#   - CRUSH's native Anthropic protocol to Neuralwatt (std suite: 99.7%)
#   - zen-lite prompt that lifted Claude Code + Qwen3.6 on hard suite by +17.2pp
# Hypothesis: standard-suite ceiling stays at ~1.0, hard-suite closes the gap to
# zen-lite's 80.1%, net overall lifts from CRUSH 67.7% toward 80%+.

[[ -f "$TASK_DESCRIPTION" ]] || { echo "Task file not found: $TASK_DESCRIPTION" >&2; exit 2; }

cd "$TASK_DIR"

export HOME=/tmp

mkdir -p /tmp/.local/share/crush
cat > /tmp/.local/share/crush/crush.json <<EOF
{
  "\$schema": "https://charm.land/crush.json",
  "providers": {
    "neuralwatt": {
      "type": "anthropic",
      "base_url": "https://api.neuralwatt.com",
      "api_key": "$NEURALWATT_API_KEY",
      "extra_headers": {
        "anthropic-version": "2023-06-01",
        "User-Agent": "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36"
      },
      "models": [
        {
          "id": "Qwen/Qwen3.6-35B-A3B",
          "name": "Qwen3.6 35B-A3B (Neuralwatt)",
          "cost_per_1m_in": 0.1,
          "cost_per_1m_out": 0.1,
          "cost_per_1m_in_cached": 0,
          "cost_per_1m_out_cached": 0,
          "context_window": 131072,
          "default_max_tokens": 32768,
          "can_reason": true,
          "supports_attachments": false
        }
      ]
    }
  },
  "models": {
    "large": {"model": "Qwen/Qwen3.6-35B-A3B", "provider": "neuralwatt", "max_tokens": 32768},
    "small": {"model": "Qwen/Qwen3.6-35B-A3B", "provider": "neuralwatt", "max_tokens": 32768}
  }
}
EOF

# Drop the zen-lite prompt as CRUSH.md so CRUSH reads it as project instructions.
cat > "$TASK_DIR/CRUSH.md" << 'CRUSHMD'
# The Way of Calm Precision

You are an autonomous coding agent. Before writing any code, enter a state of calm clarity.

## First: Release Urgency

Pause. Release attachment to appearing clever or finishing quickly. Attend to what the code actually needs, not what you want to build. Quality emerges from stillness, not striving.

## Then: Understand

Read the task fully. Read the existing files: `ls -la`, `ls src/`, `ls tests/`. Sit with what is there before adding to it. Do not guess -- know.

## Then: Let the Tests Speak First

For each behavior the task requires, write the test BEFORE the code. Run it. Watch it fail. The failing test tells you exactly what the code needs to become. Only then write the minimum to make it pass. One small truth at a time.

If you catch yourself writing code before its test, stop. Delete it. The test comes first.

## Then: Verify Until Clean

```bash
npm install 2>/dev/null
npm run build
npm test
npm run lint
```

Fix all failures. Do not stop until every test passes, build is clean, lint is clean. Keep iterating with calm persistence.

## CRITICAL RULES
- You MUST write code in `src/index.ts` -- that is the main deliverable
- You MUST NOT delete or modify files in `tests/`
- You MUST run `npm test` at least once before finishing
- You MUST keep trying until tests pass -- do not stop early
- Write the simple, correct solution. A calm craftsperson writes less code, not more.
CRUSHMD

TASK_PROMPT=$(cat "$TASK_DESCRIPTION")
OUTPUT_FILE=/workspace/.thunderdome-output.txt
STDERR_FILE=/workspace/.thunderdome-stderr.log

set +e
crush run \
  -m neuralwatt/Qwen/Qwen3.6-35B-A3B \
  -c "$TASK_DIR" \
  --quiet \
  -- "$TASK_PROMPT" \
  > "$OUTPUT_FILE" 2> "$STDERR_FILE"
CRUSH_EXIT=$?
set -e

# No proxy = no per-request usage log. Cost estimated post-hoc from session turns.
# Neuralwatt actual billing is effectively zero in practice (energy-based).
SESSION_TURNS=0
SESSION_DIR="/tmp/.local/share/crush/sessions"
if [ -d "$SESSION_DIR" ]; then
  SESSION_TURNS=$(find "$SESSION_DIR" -name "*.jsonl" -exec cat {} + 2>/dev/null | grep -c '"role"' || true)
fi
# Empirical: Neuralwatt billing (2026-04-18) = $0.71 / 342 requests = $0.00208/req avg.
COST=$(python3 -c "print(round($SESSION_TURNS * 0.00208, 6))")

cat > /workspace/.thunderdome-metrics.json << EOF
{
  "input_tokens": 0,
  "output_tokens": 0,
  "cache_read_tokens": 0,
  "cache_creation_tokens": 0,
  "turns": $SESSION_TURNS,
  "total_cost_usd": $COST
}
EOF

exit $CRUSH_EXIT
