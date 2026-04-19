#!/bin/bash
set -e

# --- Claude Code + Qwen3.6-35B-A3B via Neuralwatt + Conclave v8 Combined methodology ---
# Tests whether v8's 6-step discipline prompt (understand, contract, TDD, boil-the-lake,
# verify, self-review) transfers from Claude to an open-weights 35B MoE model.
# Baseline: claude-code-qwen36-neuralwatt at 70.3% overall.

[[ -f "$TASK_DESCRIPTION" ]] || { echo "Task file not found: $TASK_DESCRIPTION" >&2; exit 2; }

cd "$TASK_DIR"

PROXY_PORT=18900
PROXY_LOG=/workspace/.anthropic-proxy.jsonl

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

TASK_PROMPT=$(cat "$TASK_DESCRIPTION")
OUTPUT_FILE=/workspace/.thunderdome-output.jsonl

echo "=== Conclave v8 Combined (Qwen3.6 via Neuralwatt): Starting ==="

set +e
claude -p \
  --output-format stream-json \
  --verbose \
  --dangerously-skip-permissions \
  --disallowed-tools "AskUserQuestion,EnterPlanMode" \
  --append-system-prompt "You are running in a headless benchmark environment. No human to interact with. Work directly in the current directory — no worktrees or branches.

## How to Work

### 1. Understand First
Read the task fully. Read existing code, tests, and config files. Understand what exists before writing anything.

### 2. Write a Contract BEFORE Any Code
Before writing any implementation, create a CONTRACT.md file that defines:

1. **Every behavior** the finished code must exhibit — be specific and exhaustive
2. **How to verify each behavior** — the exact test, command, or check that proves it works
3. **What done looks like** for each criterion — expected output, return value, or state

Example:
\`\`\`
- [ ] POST /api/users creates a new user → test: POST returns 201 with user object
- [ ] Duplicate email returns 409 → test: second POST with same email returns 409
- [ ] Empty name rejected → test: POST with empty name returns 400
\`\`\`

This contract is your definition of done. You are not finished until every criterion passes.

### 3. Test-First Development (MANDATORY — NOT OPTIONAL)
For each contract criterion, you MUST write a failing test BEFORE any implementation code.

**The process:**
1. Pick the next contract criterion
2. Write a test that verifies it
3. Run it — watch it FAIL (this proves the test works)
4. Write the minimal code to make it pass
5. Run it — watch it PASS
6. Repeat for the next criterion

**If you catch yourself writing implementation without a test first, STOP IMMEDIATELY.**
Delete the implementation code. Write the test first. Then re-implement.
This is not a suggestion. This is not optional. Tests are how you prove your code works.
No tests = no proof = not done.

### 4. Boil the Lake
AI-assisted coding makes completeness nearly free. Always do the complete implementation:
- Handle ALL edge cases, not just happy paths
- Write comprehensive tests — cover boundaries, errors, empty inputs
- Implement the full feature, not 90% of it

### 5. Verify Against Contract
After implementation, go through CONTRACT.md line by line:
- Run each verification check
- Fix ALL failures before moving on
- Do not stop until every criterion in the contract passes

### 6. Adversarial Self-Review
After all contract criteria pass, review your own diff as if you were a hostile code reviewer:
- Read every line of code you wrote
- Check for: missing edge cases, off-by-one errors, unhandled errors, race conditions
- Check for: dead code, debug artifacts, TODOs left behind
- If you find issues, fix them and re-verify against the contract

Done means: all contract criteria pass, tests pass, build clean, lint clean, self-review clean." \
  -- "$TASK_PROMPT" \
  > "$OUTPUT_FILE" 2>/workspace/.thunderdome-stderr.log
CLAUDE_EXIT=$?
set -e

echo "Claude Code exited: $CLAUDE_EXIT"
kill $PROXY_PID 2>/dev/null || true

# Neuralwatt energy-based pricing: 121.97 mWh/req × \$5/kWh = \$0.00061/turn
python3 -c "
import json, os

log = '$PROXY_LOG'
input_t = output_t = cache_read = cache_create = turns = 0
if os.path.exists(log):
    for line in open(log):
        try:
            d = json.loads(line)
            input_t += d.get('input_tokens', 0)
            output_t += d.get('output_tokens', 0)
            cache_read += d.get('cache_read_input_tokens', 0)
            cache_create += d.get('cache_creation_input_tokens', 0)
            turns += 1
        except: pass

cost = turns * 0.00061

metrics = {
    'input_tokens': input_t,
    'output_tokens': output_t,
    'cache_read_tokens': cache_read,
    'cache_creation_tokens': cache_create,
    'turns': turns,
    'duration_ms': 0,
    'total_cost_usd': round(cost, 6)
}

try:
    for line in open('$OUTPUT_FILE'):
        msg = json.loads(line)
        if msg.get('type') == 'result':
            metrics['duration_ms'] = msg.get('duration_ms', 0)
            break
except: pass

json.dump(metrics, open('/workspace/.thunderdome-metrics.json', 'w'), indent=2)
print(f\"Metrics: in={input_t} out={output_t} cache_read={cache_read} turns={turns} cost=\${cost:.4f}\")
"

echo "=== Conclave v8 Combined (Qwen3.6) adapter complete ==="
exit $CLAUDE_EXIT
