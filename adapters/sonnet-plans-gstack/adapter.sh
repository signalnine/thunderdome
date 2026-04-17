#!/bin/bash
set -e

# sonnet-plans-gstack: Sonnet 4.6 + writing-plans skill + gstack CLAUDE.md.
# Cost-optimization experiment — top 2 ROI genes stacked on cheaper model.

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

# Git identity
git config user.name "sonnet-plans-gstack"
git config user.email "sonnet-plans-gstack@thunderdome"

# Build stripped-down plugin with ONLY writing-plans
PLANS_PLUGIN=/tmp/plans-only-plugin
mkdir -p "$PLANS_PLUGIN/.claude-plugin"
mkdir -p "$PLANS_PLUGIN/skills/writing-plans"
mkdir -p "$PLANS_PLUGIN/skills/using-superpowers"

cp /opt/superpowers-plugin/.claude-plugin/plugin.json "$PLANS_PLUGIN/.claude-plugin/"
cp -r /opt/superpowers-plugin/skills/writing-plans/* "$PLANS_PLUGIN/skills/writing-plans/"
cp -r /opt/superpowers-plugin/skills/using-superpowers/* "$PLANS_PLUGIN/skills/using-superpowers/"

# Inject gstack CLAUDE.md into workspace
if [ -f CLAUDE.md ]; then
  EXISTING=$(cat CLAUDE.md)
  cat > CLAUDE.md << 'GSTACK_EOF'
# gstack Development Philosophy

## Completeness Principle — Boil the Lake

AI-assisted coding makes the marginal cost of completeness near-zero. Always do the complete implementation:

- If Option A is the complete implementation (full parity, all edge cases, 100% coverage) and Option B is a shortcut that saves modest effort — **always choose A**.
- **Lake vs. ocean:** A "lake" is boilable — 100% test coverage, full feature implementation, all edge cases, complete error paths. An "ocean" is not — rewriting an entire system from scratch. Boil lakes. Flag oceans as out of scope.
- This principle applies to test coverage, error handling, edge cases, and feature completeness. Don't skip the last 10%.

## Workflow

1. Read the task fully before writing any code
2. Plan the complete implementation — all functions, all edge cases, all tests
3. Implement everything — don't leave TODOs or partial implementations
4. Write comprehensive tests — cover edge cases, not just happy paths
5. Verify: run build, lint, and tests. Fix any failures before finishing.
6. Review your own work

GSTACK_EOF
  echo "" >> CLAUDE.md
  echo "$EXISTING" >> CLAUDE.md
else
  cat > CLAUDE.md << 'GSTACK_EOF'
# gstack Development Philosophy

## Completeness Principle — Boil the Lake

AI-assisted coding makes the marginal cost of completeness near-zero. Always do the complete implementation:

- If Option A is the complete implementation (full parity, all edge cases, 100% coverage) and Option B is a shortcut that saves modest effort — **always choose A**.
- **Lake vs. ocean:** A "lake" is boilable — 100% test coverage, full feature implementation, all edge cases, complete error paths. An "ocean" is not — rewriting an entire system from scratch. Boil lakes. Flag oceans as out of scope.
- This principle applies to test coverage, error handling, edge cases, and feature completeness. Don't skip the last 10%.

## Workflow

1. Read the task fully before writing any code
2. Plan the complete implementation — all functions, all edge cases, all tests
3. Implement everything — don't leave TODOs or partial implementations
4. Write comprehensive tests — cover edge cases, not just happy paths
5. Verify: run build, lint, and tests. Fix any failures before finishing.
6. Review your own work

GSTACK_EOF
fi

TASK_PROMPT=$(cat "$TASK_DESCRIPTION")
OUTPUT_FILE=/workspace/.thunderdome-output.jsonl

set +e
claude -p \
  --model claude-sonnet-4-6 \
  --output-format stream-json \
  --verbose \
  --dangerously-skip-permissions \
  --plugin-dir "$PLANS_PLUGIN" \
  --disallowed-tools "AskUserQuestion,EnterPlanMode" \
  --append-system-prompt "You are running in a headless benchmark environment. There is no human to interact with.

You follow the gstack 'Boil the Lake' philosophy: always do the complete implementation. The CLAUDE.md in this workspace describes this in detail.

MANDATORY WORKFLOW:

1. Read the task description to understand requirements.
2. Invoke the writing-plans skill IMMEDIATELY:
   Use the Skill tool with skill='writing-plans'
3. Follow the skill to create a detailed implementation plan with bite-sized tasks, exact file paths, complete code examples, and test commands.
4. Save the plan.
5. Implement the plan — execute each task in order.
6. Run tests, build, and lint to verify your implementation.

You MUST invoke the writing-plans skill and create a plan before writing any implementation code. This is non-negotiable." \
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
