#!/bin/bash
set -e

# --- Prime Agent (PrimeIntellect) + DeepSeek v4 Flash GA ---
#
# Prime Agent v0.7.3, MIT (github.com/PrimeIntellect-ai/prime-agent). A different
# ORCHESTRATION GENE from everything else on the board: persistent IPython is the
# model's primary tool rather than a fixed tool schema -- file ops, shell,
# subagents are all expressed as Python the model writes and executes.
#
# Backend is DeepSeek v4 Flash GA on its FIRST-PARTY /anthropic endpoint --
# deliberately identical model + endpoint to claude-code-deepseek-v4-flash-native
# (90.7%, std 93.6 / hard 87.5, $0.096/task). Same model, same endpoint, different
# harness, so any delta isolates the harness. Harness effects on this suite are
# large (CRUSH cost GLM-5.1-fast 10.8pp vs Claude Code), which is exactly why this
# is worth measuring rather than assuming.
#
# SECURITY: Prime Agent executes MODEL-GENERATED PYTHON with the invoking user's
# permissions. Acceptable only because the container is the sandbox -- the same
# rationale as Claude Code's --dangerously-skip-permissions. Never run outside a
# container. The image installs from vendored, checksum-verified release
# artifacts rather than the upstream curl|sh installer; see docker/prime-agent/.

[[ -f "$TASK_DESCRIPTION" ]] || { echo "Task file not found: $TASK_DESCRIPTION" >&2; exit 2; }
: "${DEEPSEEK_API_KEY:?DEEPSEEK_API_KEY is required for this adapter}"

cd "$TASK_DIR"
export HOME=/tmp
mkdir -p "$HOME/.prime/agent"

# Custom provider via models.json. `anthropic-messages` matches DeepSeek's native
# /anthropic endpoint. supportsEagerToolInputStreaming=false because Prime Agent
# sends Anthropic fine-grained tool streaming (`eager_input_streaming: true`) by
# default and a non-Anthropic backend may reject the field.
cat > "$HOME/.prime/agent/models.json" <<JSON
{
  "providers": {
    "deepseek": {
      "baseUrl": "https://api.deepseek.com/anthropic",
      "api": "anthropic-messages",
      "apiKey": "$DEEPSEEK_API_KEY",
      "compat": { "supportsEagerToolInputStreaming": false },
      "models": [
        {
          "id": "deepseek-v4-flash",
          "name": "DeepSeek v4 Flash GA",
          "reasoning": true,
          "input": ["text"],
          "contextWindow": 1000000,
          "maxTokens": 32000,
          "cost": { "input": 0.14, "output": 0.28, "cacheRead": 0.003, "cacheWrite": 0 }
        }
      ]
    }
  }
}
JSON

TASK_PROMPT=$(cat "$TASK_DESCRIPTION")
OUTPUT_FILE=/workspace/.thunderdome-output.jsonl
STDERR_FILE=/workspace/.thunderdome-stderr.log

# STREAM VOLUME: --mode json emits a message_update event per token delta. On a
# long autonomous run that is not a nuisance, it is a disk hazard -- one
# unfinished constraint-scheduler trial produced a 4.9 GB
# .thunderdome-output.jsonl inside /workspace, which then lands in diff.patch
# and the results tree (a short task already costs 31 MB, 5293 of its 5372
# events being message_update).
# Filter the incremental events at the source. message_start/message_end,
# turn_*, tool_execution_start/end and agent_* are all retained, so turn counts,
# tool names and the authoritative message_end usage totals survive intact.
# PIPEFAIL NOTE: the exit code we care about is prime-agent's, not grep's, so
# pipefail is enabled and PIPESTATUS[0] is read explicitly below.
set -o pipefail

WALL_CLOCK_START=$(date +%s)

set +e
# AUTONOMOUS MODE, not -p. This was wrong the first time and the failure was
# quiet: `-p/--print` is literally "Print a response and exit", so the agent
# explored for ~4 turns, executed 3 ipython calls, wrote NO source, and exited
# reporting success. It scored 54.1% overall at $0.013/task -- cheap and
# plausible-looking, which is exactly what makes it dangerous. The real signal
# was diffs containing only runtime artifacts and package-lock.json.
#
# --autonomous is the documented mode for "runs where no human input is
# expected": it injects follow-up continuations until GATES PASS or a limit is
# hit. Its defaults are far too small for this suite (max-turns 12,
# max-continuations 3, max-tokens 80000, timeout 30min), so the limits are
# raised well past what a task should need.
#
# --autonomous-gate IS REQUIRED, and omitting it was a mistake. Without a gate
# there is no completion signal, so the agent can only ever exhaust its budget:
# the first correct-mode run scored 0.92 on constraint-scheduler but ran the
# full 90 minutes to the wall, which across 21 tasks is ~31 hours.
# `npm test` is not task-specific scaffolding -- it is the same command the task
# prompts already instruct the agent to run, and every benchmark repo defines
# it. It plays the role the final-answer signal plays for other harnesses.
prime-agent \
  --mode json \
  --provider deepseek \
  --model deepseek-v4-flash \
  --autonomous \
  --autonomous-gate "npm test" \
  --autonomous-gate-retries 1 \
  --autonomous-gate-timeout-ms 600000 \
  --autonomous-max-turns 200 \
  --autonomous-max-continuations 20 \
  --autonomous-max-tokens 4000000 \
  --autonomous-timeout-ms 5400000 \
  "$TASK_PROMPT" \
  2> "$STDERR_FILE" \
  | grep --line-buffered -vF '"type":"message_update"' \
  | grep --line-buffered -vF '"type":"tool_execution_update"' \
  > "$OUTPUT_FILE"
EXIT_CODE=${PIPESTATUS[0]}
set -e

WALL_CLOCK_END=$(date +%s)
WALL_CLOCK_DURATION=$(( (WALL_CLOCK_END - WALL_CLOCK_START) * 1000 ))

# Parse the JSON event stream (schema: packages/coding-agent/docs/json.md).
#
# USAGE SHAPE, established empirically -- it is NOT the Anthropic/OpenAI shape:
#   {"input":N,"output":N,"cacheRead":N,"cacheWrite":N,"totalTokens":N,
#    "cost":{"input":..,"output":..,"cacheRead":..,"cacheWrite":..,"total":..}}
# Fields are `input`/`output`, not `input_tokens`. Prime Agent computes `cost`
# itself from the per-model rates supplied in models.json above, so those figures
# are correct as long as that table is right.
#
# AGGREGATION MATTERS: `message_end` and `turn_end` carry IDENTICAL per-message
# usage -- summing both double-counts. `agent_end` carries ONLY the final
# message, not a cumulative total (5126 in vs 10777 summed on the T1 smoke), so
# reading it as the task total would understate ~2x. Sum message_end only.
python3 -c "
import json, sys

def find_usage(o):
    if isinstance(o, dict):
        u = o.get('usage')
        if isinstance(u, dict) and 'totalTokens' in u: return u
        for v in o.values():
            r = find_usage(v)
            if r: return r
    elif isinstance(o, list):
        for v in o:
            r = find_usage(v)
            if r: return r
    return None

inp = out = cread = cwrite = 0
cost = 0.0
turns = 0
tools = []
try:
    with open('$OUTPUT_FILE') as f:
        for line in f:
            line = line.strip()
            if not line: continue
            try: ev = json.loads(line)
            except json.JSONDecodeError: continue
            t = ev.get('type', '')
            if t == 'turn_end': turns += 1
            if t in ('tool_execution_start', 'tool_execution_update'):
                n = ev.get('toolName') or ev.get('name') or (ev.get('tool') or {}).get('name')
                if n and n not in tools: tools.append(n)
            if t != 'message_end': continue          # <- the one authoritative source
            u = find_usage(ev)
            if not u: continue
            inp    += u.get('input', 0) or 0
            out    += u.get('output', 0) or 0
            cread  += u.get('cacheRead', 0) or 0
            cwrite += u.get('cacheWrite', 0) or 0
            cost   += (u.get('cost') or {}).get('total', 0) or 0
except FileNotFoundError:
    pass

# Fall back to recomputing from tokens if the harness reported no cost, so a
# schema change upstream degrades to an estimate rather than silently to \\$0.
if cost == 0 and (inp or out):
    cost = ((inp + cread + cwrite) * 0.14 + out * 0.28) / 1e6

metrics = {
    'input_tokens': inp,
    'output_tokens': out,
    'cache_read_tokens': cread,
    'cache_creation_tokens': cwrite,
    'turns': turns,
    'tools_used': tools,
    'duration_ms': $WALL_CLOCK_DURATION,
    'total_cost_usd': round(cost, 6),
    'harness': 'prime-agent-0.7.3',
}
with open('/workspace/.thunderdome-metrics.json','w') as f:
    json.dump(metrics, f, indent=2)
print('Metrics: ' + json.dumps(metrics), file=sys.stderr)
" 2>&1 || true

exit $EXIT_CODE
