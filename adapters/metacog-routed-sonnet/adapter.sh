#!/bin/bash
set -e

# metacog-routed-sonnet: Per-category stratagem routing on Sonnet.
# Uses Haiku to classify task category, then selects the best-performing
# metacog stratagem for that category (based on Opus ablation data).
# Combines zen v3 discipline prompt with category-optimal stratagem.
#
# Routing table (from 16-stratagem Opus ablation, best per category):
#   algorithmic/hard  -> fool (0.925)
#   ambiguity/hard    -> scrying (0.787)
#   reasoning/hard    -> mirror (0.898)
#   greenfield/simple -> drift (0.977)
#   greenfield/complex-> veil (0.769)
#   marathon          -> scrying (0.707)
#   default (bugfix, features, correctness, recovery) -> fool (0.880)

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

# ──────────────────────────────────────────────────────────────────
# ROUTING: Use Haiku to classify task category
# ──────────────────────────────────────────────────────────────────
echo "=== Routing: classifying task category ===" >&2

ROUTING_PROMPT="You are a task classifier for a coding benchmark. Read the task description and classify it into EXACTLY ONE of these categories. Respond with ONLY the category label, nothing else.

Categories:
- GREENFIELD_SIMPLE: Build a small tool or utility from scratch (CLI app, simple API)
- GREENFIELD_COMPLEX: Build a complex system from scratch (real-time server, marketplace, dashboard, e-commerce)
- FEATURES: Add features to existing code (search, plugins, extensions)
- BUGFIX: Find and fix bugs in existing code
- MARATHON: Long multi-phase implementation with many requirements
- RECOVERY: Fix a broken project (build errors, broken tests, config issues)
- ALGORITHMIC: Implement algorithms (scheduling, merging, graph problems, constraint solving)
- AMBIGUITY: Vague or underspecified requirements requiring inference
- REASONING: Logic puzzles, circuit analysis, mathematical reasoning, reverse engineering
- CORRECTNESS: Precision-critical (financial calculations, double-entry accounting)

=== TASK DESCRIPTION ===
$TASK_PROMPT"

CATEGORY=$(claude -p \
  --model claude-haiku-4-5-20251001 \
  --max-turns 1 \
  -- "$ROUTING_PROMPT" 2>/dev/null || echo "GREENFIELD_COMPLEX")

# Clean up response (extract just the category keyword)
CATEGORY=$(echo "$CATEGORY" | tr -d '[:space:]' | tr '[:lower:]' '[:upper:]')

# Map category to stratagem
case "$CATEGORY" in
  *ALGORITHMIC*)    STRATAGEM="fool" ;;
  *AMBIGUITY*)      STRATAGEM="scrying" ;;
  *REASONING*)      STRATAGEM="mirror" ;;
  *GREENFIELD_SIMPLE*|*SIMPLE*) STRATAGEM="drift" ;;
  *GREENFIELD*|*COMPLEX*)       STRATAGEM="veil" ;;
  *MARATHON*)       STRATAGEM="scrying" ;;
  *)                STRATAGEM="fool" ;;  # default for bugfix, features, correctness, recovery
esac

STRATAGEM_UPPER=$(echo "$STRATAGEM" | tr '[:lower:]' '[:upper:]')
echo "  Category: $CATEGORY -> Stratagem: $STRATAGEM_UPPER" >&2

# ──────────────────────────────────────────────────────────────────
# IMPLEMENTATION: Sonnet + metacog plugin + routed stratagem + zen discipline
# ──────────────────────────────────────────────────────────────────
echo "=== Implementation: Sonnet + $STRATAGEM_UPPER ===" >&2

set +e
claude -p \
  --model claude-sonnet-4-6 \
  --output-format stream-json \
  --verbose \
  --dangerously-skip-permissions \
  --plugin-dir /opt/metacog-plugin \
  --disallowed-tools "AskUserQuestion,EnterPlanMode" \
  --append-system-prompt "You are running in a headless benchmark environment. There is no human to interact with.

YOU MUST USE THE METACOG SKILL WITH THE ${STRATAGEM_UPPER} STRATAGEM. This is non-negotiable.

MANDATORY WORKFLOW:
1. Invoke the metacog skill via the Skill tool
2. Run \`metacog stratagem start ${STRATAGEM}\`
3. Complete ALL steps with \`metacog stratagem next\`
4. Let the stratagem genuinely shape your approach -- don't just acknowledge it and revert to default thinking
5. Implement the solution with the stratagem-informed perspective
6. Verify: run tests, build, and lint to confirm correctness

CRITICAL: You MUST use THE ${STRATAGEM_UPPER}. Do NOT choose a different stratagem. Do NOT skip the metacog skill.

## The Way of Working

### First, understand
Read the task fully. Read every existing file. Sit with what is there before adding to it.

### Then, define what done looks like
Before writing implementation, create CONTRACT.md -- every behavior the finished code must exhibit, how to verify each one, what done looks like. This is your definition of done.

### Then, let the tests speak first
For each contract criterion, write the test BEFORE the code. Run it. Watch it fail. Only then write the minimum to make it pass. One small truth at a time.

If you catch yourself writing code before its test, stop. Delete it. The test comes first.

### Then, complete the work
Handle all edge cases. Cover boundaries, errors, empty inputs. The complete implementation, not 90% of it.

### Then, verify against your contract
Go through CONTRACT.md line by line. Run each check. Fix all failures. Do not stop until every criterion passes, tests pass, build is clean, lint is clean." \
  -- "$TASK_PROMPT" \
  > "$OUTPUT_FILE" 2>/workspace/.thunderdome-stderr.log
CLAUDE_EXIT=$?
set -e

# ──────────────────────────────────────────────────────────────────
# METRICS
# ──────────────────────────────────────────────────────────────────
node -e '
const fs = require("fs");
try {
  const lines = fs.readFileSync(process.argv[1], "utf8").split("\n");
  const metrics = {
    input_tokens: 0, output_tokens: 0, cache_read_tokens: 0,
    cache_creation_tokens: 0, turns: 0, tools_used: [],
    duration_ms: 0, total_cost_usd: 0,
    routed_category: process.argv[2],
    routed_stratagem: process.argv[3]
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
' "$OUTPUT_FILE" "$CATEGORY" "$STRATAGEM" || true

exit $CLAUDE_EXIT
