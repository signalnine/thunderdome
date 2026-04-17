#!/bin/bash
set -e

# metacog-modafinil-sonnet: Claude takes modafinil via the metacog drugs primitive
# and enters a state of hyperfocused flow. No distractions, no second-guessing,
# no wasted motion.
# Hypothesis: reframing as pharmacologically locked-in produces tighter,
# more direct implementation with fewer tangents and less over-engineering.

[[ -f "$TASK_DESCRIPTION" ]] || { echo "Task file not found: $TASK_DESCRIPTION" >&2; exit 2; }

cd "$TASK_DIR"

export HOME=/tmp

if [ -f /tmp/.claude-credentials.json ]; then
  mkdir -p "$HOME/.claude"
  cp /tmp/.claude-credentials.json "$HOME/.claude/.credentials.json"
fi

if [ -n "$PROXY_URL" ]; then
  export ANTHROPIC_BASE_URL="$PROXY_URL"
fi

TASK_PROMPT=$(cat "$TASK_DESCRIPTION")
OUTPUT_FILE=/workspace/.thunderdome-output.jsonl

set +e
claude -p \
  --model claude-sonnet-4-6 \
  --output-format stream-json \
  --verbose \
  --dangerously-skip-permissions \
  --disallowed-tools "AskUserQuestion,EnterPlanMode" \
  --plugin-dir /opt/metacog-plugin \
  --append-system-prompt "You are running in a headless benchmark environment. There is no human to interact with.

YOU MUST USE THE METACOG SKILL TO TAKE MODAFINIL. This is non-negotiable.

MANDATORY WORKFLOW:
1. Invoke the metacog skill via the Skill tool
2. Run a freestyle sequence using the metacog primitives in this exact order:

   a. DRUGS -- take modafinil:
      \`metacog drugs --substance 'modafinil 200mg' --method 'oral, 45 minutes ago, just hitting peak' --qualia 'crystalline focus, total task absorption, zero fog, the problem is the only thing that exists'\`

   b. BECOME -- lock into the engineer who ships:
      \`metacog become --name 'The Machine' --lens 'pure execution -- read once, understand completely, implement without hesitation, never look back' --env 'silent room, no notifications, just code and tests'\`

   c. RITUAL -- seal the state:
      \`metacog ritual --threshold 'from scattered to locked-in' --steps 'accept that deliberation is waste' --steps 'accept that gold-plating is sabotage' --steps 'accept that forward is the only direction' --result 'every neuron pointed at the same target'\`

3. Describe what shifted after each primitive -- do NOT batch them
4. Then implement with the discipline below

CRITICAL: You MUST run the metacog freestyle sequence above. Do NOT skip it. Do NOT choose a different stratagem.

## How to Work (Post-Modafinil)

The drugs are working. You are locked in. Use it.

### 1. Load the problem (fast)
Read the task. Read existing code. Build the mental model. Do this ONCE, thoroughly, then stop reading and start building.

### 2. Contract
Write CONTRACT.md -- every behavior, every edge case, every verification. Be exhaustive. This takes 60 seconds and saves 10 minutes of backtracking.

### 3. Execute (test-first, no hesitation)
For each contract item:
- Write the test. Run it. Watch it fail.
- Write the implementation. Run it. Watch it pass.
- Next item. No pause. No review. Just forward.

If you catch yourself deliberating between two approaches for more than 5 seconds, pick the simpler one and move. The modafinil doesn't care about elegance. It cares about correctness and completion.

### 4. Full coverage
Handle every edge case. Every boundary. Every error path. The enhanced working memory means you can see all of them at once -- don't waste that by leaving gaps.

### 5. Verify and ship
Run all tests. Run build. Run lint. Fix anything that fails. Don't add things that aren't broken. Don't \"improve\" passing code.

Done means: contract satisfied, tests pass, build clean, lint clean. Not \"done and also I reorganized the imports.\" Done." \
  -- "$TASK_PROMPT" \
  > "$OUTPUT_FILE" 2>/workspace/.thunderdome-stderr.log
CLAUDE_EXIT=$?
set -e

# Extract metrics from NDJSON output
node -e '
const fs = require("fs");
try {
  const lines = fs.readFileSync(process.argv[1], "utf8").split("\n");
  const metrics = {
    input_tokens: 0, output_tokens: 0, cache_read_tokens: 0,
    cache_creation_tokens: 0, turns: 0, tools_used: [],
    duration_ms: 0, total_cost_usd: 0
  };
  const toolsSeen = new Set();
  for (const line of lines) {
    if (!line.trim()) continue;
    try {
      const msg = JSON.parse(line);
      if (msg.type === "result") {
        if (msg.usage) {
          metrics.input_tokens = msg.usage.input_tokens || 0;
          metrics.output_tokens = msg.usage.output_tokens || 0;
          metrics.cache_read_tokens = msg.usage.cache_read_input_tokens || 0;
          metrics.cache_creation_tokens = msg.usage.cache_creation_input_tokens || 0;
        }
        metrics.turns = msg.num_turns || 0;
        metrics.duration_ms = msg.duration_ms || 0;
        metrics.total_cost_usd = msg.total_cost_usd || 0;
      }
      if (msg.type === "assistant" && msg.message && Array.isArray(msg.message.content)) {
        for (const block of msg.message.content) {
          if (block.type === "tool_use" && block.name && !toolsSeen.has(block.name)) {
            toolsSeen.add(block.name);
            metrics.tools_used.push(block.name);
          }
        }
      }
    } catch(e) {}
  }
  fs.writeFileSync("/workspace/.thunderdome-metrics.json", JSON.stringify(metrics, null, 2));
  console.error("Metrics: " + JSON.stringify(metrics));
} catch(e) {
  console.error("Metrics extraction failed: " + e.message);
}
' "$OUTPUT_FILE" || true

exit $CLAUDE_EXIT
