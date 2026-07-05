#!/bin/bash
set -e

# --- Claude Code + q27 v1.4 (Qwopus3.6-27B-MTP) on host.docker.internal:8081 ---
# q27-server speaks the Anthropic Messages protocol natively (tool_use,
# thinking blocks, input_json_delta streaming) -- no translation proxy.
# Server runs --no-think --slots 2 + R1b round-interleaving, greedy-only by
# construction. Cross-HARNESS/cross-ENGINE A/B leg: identical to
# claude-code-q5km-haight except the upstream engine (port 8081 vs 8080) --
# do not edit one without the other. Workflow is disallowed on BOTH legs:
# its schema (maxLength 524288 on `script`) breaks llama.cpp's
# json-schema-to-grammar ("failed to parse grammar" at sampler init), and the
# tool block must stay byte-identical across legs.

[[ -f "$TASK_DESCRIPTION" ]] || { echo "Task file not found: $TASK_DESCRIPTION" >&2; exit 2; }

cd "$TASK_DIR"

export ANTHROPIC_BASE_URL="http://host.docker.internal:8081"
export ANTHROPIC_API_KEY="placeholder"

export ANTHROPIC_DEFAULT_OPUS_MODEL="q27-qwopus-27b"
export ANTHROPIC_DEFAULT_SONNET_MODEL="q27-qwopus-27b"
export ANTHROPIC_DEFAULT_HAIKU_MODEL="q27-qwopus-27b"
export CLAUDE_CODE_SUBAGENT_MODEL="q27-qwopus-27b"

TASK_PROMPT=$(cat "$TASK_DESCRIPTION")
OUTPUT_FILE=/workspace/.thunderdome-output.jsonl

echo "=== Claude Code (q27 Qwopus3.6-27B v1.4, native Anthropic): Starting ==="

set +e
claude -p \
  --output-format stream-json \
  --verbose \
  --dangerously-skip-permissions \
  --disallowed-tools "AskUserQuestion,EnterPlanMode,Workflow" \
  -- "$TASK_PROMPT" \
  > "$OUTPUT_FILE" 2>/workspace/.thunderdome-stderr.log
CLAUDE_EXIT=$?
set -e

echo "Claude Code exited: $CLAUDE_EXIT"

# Local inference, cost $0. Token/turn accounting from the stream-json result.
python3 - "$OUTPUT_FILE" << 'PYEOF'
import json, sys
metrics = {"input_tokens": 0, "output_tokens": 0, "cache_read_tokens": 0,
           "cache_creation_tokens": 0, "turns": 0, "duration_ms": 0,
           "total_cost_usd": 0.0}
turns = 0
try:
    for line in open(sys.argv[1]):
        line = line.strip()
        if not line:
            continue
        try:
            m = json.loads(line)
        except Exception:
            continue
        if m.get("type") == "assistant":
            turns += 1
        if m.get("type") == "result":
            u = m.get("usage", {})
            metrics["input_tokens"] = u.get("input_tokens", 0)
            metrics["output_tokens"] = u.get("output_tokens", 0)
            metrics["cache_read_tokens"] = u.get("cache_read_input_tokens", 0)
            metrics["cache_creation_tokens"] = u.get("cache_creation_input_tokens", 0)
            metrics["duration_ms"] = m.get("duration_ms", 0)
            metrics["turns"] = m.get("num_turns", 0)
except Exception:
    pass
if not metrics["turns"]:
    metrics["turns"] = turns
json.dump(metrics, open("/workspace/.thunderdome-metrics.json", "w"), indent=2)
print(f"Metrics: in={metrics['input_tokens']} out={metrics['output_tokens']} turns={metrics['turns']}")
PYEOF

echo "=== Claude Code (q27) adapter complete ==="
exit $CLAUDE_EXIT
