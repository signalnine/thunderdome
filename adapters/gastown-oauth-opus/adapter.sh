#!/bin/bash
set -e

# --- Gas Town Adapter (OAuth + Opus) ---
# Full multi-agent pipeline:
#   Mayor (planner) -> parallel Polecats (workers) -> Refinery (merge + fixup)
# For the single-agent variant, see gas-station-oauth-opus.

# ============================================================================
# Phase 0: Setup & Validation
# ============================================================================

[[ -f "$TASK_DESCRIPTION" ]] || { echo "Task file not found: $TASK_DESCRIPTION" >&2; exit 2; }

cd "$TASK_DIR"

export HOME=/tmp
GT_MAX_POLECATS="${GT_MAX_POLECATS:-4}"
METRICS_DIR="/tmp/gastown-metrics"
mkdir -p "$METRICS_DIR"

WALL_CLOCK_START=$(date +%s)

# Set up OAuth credentials
if [ -f /tmp/.claude-credentials.json ]; then
  mkdir -p "$HOME/.claude"
  cp /tmp/.claude-credentials.json "$HOME/.claude/.credentials.json"
fi

# Route API calls through proxy gateway if configured
if [ -n "$PROXY_URL" ]; then
  export ANTHROPIC_BASE_URL="$PROXY_URL"
fi

TASK_PROMPT=$(cat "$TASK_DESCRIPTION")

echo "=== Gas Town: Setting up workspace ==="

# Ensure /workspace has a real branch (harness leaves HEAD detached)
DEFAULT_BRANCH=$(git -C /workspace symbolic-ref --short HEAD 2>/dev/null || echo "")
if [ -z "$DEFAULT_BRANCH" ]; then
  DEFAULT_BRANCH="main"
  git -C /workspace checkout -b "$DEFAULT_BRANCH" 2>/dev/null || true
fi
echo "Branch: $DEFAULT_BRANCH"

# Initialize Gas Town
export GT_TOWN_ROOT=/tmp/town
gt install /tmp/town --no-beads --name benchmark >/dev/null 2>&1 || true

cd /tmp/town
bd init --prefix hq >/dev/null 2>&1 || true

git clone --bare /workspace /tmp/workspace-bare.git 2>/dev/null

gt rig add bench file:///tmp/workspace-bare.git --prefix bench --branch "$DEFAULT_BRANCH" >/dev/null 2>&1

cd /tmp/town/bench
BEAD_JSON=$(bd create --title "Benchmark Task" --body "$TASK_PROMPT" --json 2>/dev/null)
BEAD_ID=$(echo "$BEAD_JSON" | grep -oP '"id":\s*"[^"]+"' | head -1 | sed 's/.*"id":\s*"//' | sed 's/"//')

if [ -z "$BEAD_ID" ]; then
  echo "ERROR: Failed to create bead" >&2
  exit 1
fi
echo "Created bead: $BEAD_ID"

# ============================================================================
# Phase 1: Mayor — Task Decomposition
# ============================================================================

echo "=== Gas Town: Mayor planning phase ==="

# Get the file tree for Mayor's context
FILE_TREE=$(cd /workspace && find . -type f \
  -not -path './.git/*' \
  -not -path './node_modules/*' \
  -not -path './dist/*' \
  -not -path './.beads/*' \
  | head -200 | sort)

MAYOR_SYSTEM_PROMPT='You are the Mayor in a Gas Town multi-agent pipeline. Your ONLY job is to analyze a task and output a JSON decomposition plan. Do NOT use any tools — no file reading, no bash commands, no code execution. You have all the information you need in the user message. Respond with ONLY a JSON object, nothing else.

CRITICAL: Your entire response must be a single valid JSON object. No text before or after. No markdown code fences. Just raw JSON.

JSON schema:
{"strategy":"single"|"parallel","beads":[{"id":"bead-1","title":"Short title","description":"What to implement","files_to_create":["src/foo.ts"],"files_to_modify":["src/bar.ts"],"context_files":["src/types.ts"],"shared_files":["src/index.ts"]}],"integration_notes":"How beads connect","post_merge_tasks":["Update exports"]}

RULES:
- "single" for simple tasks (bug fixes, small features, <3 files). "parallel" for complex tasks (multiple modules, >5 files).
- Maximum BEAD_COUNT beads (injected below). Each bead must be independently implementable.
- shared_files = files multiple polecats may touch. context_files = read-only reference.
- For "single", output exactly 1 bead with the full task description.'

MAYOR_PROMPT="BEAD_COUNT limit: ${GT_MAX_POLECATS}

TASK DESCRIPTION:
${TASK_PROMPT}

EXISTING FILES IN REPO:
${FILE_TREE}

Analyze this task and output your decomposition as a single JSON object. Do NOT use tools. Do NOT explore files. Just output JSON."

set +e
claude -p \
  --model claude-opus-4-6 \
  --max-turns 1 \
  --output-format stream-json \
  --verbose \
  --dangerously-skip-permissions \
  --disallowed-tools "AskUserQuestion,EnterPlanMode,Bash,Read,Write,Edit,Glob,Grep,Task,WebFetch,WebSearch" \
  --append-system-prompt "$MAYOR_SYSTEM_PROMPT" \
  -- "$MAYOR_PROMPT" \
  > "$METRICS_DIR/mayor.jsonl" 2>"$METRICS_DIR/mayor-stderr.log"
MAYOR_EXIT=$?
set -e

echo "Mayor exited: $MAYOR_EXIT"

# Extract Mayor's JSON output from the NDJSON stream
MAYOR_PLAN=""
if [ -f "$METRICS_DIR/mayor.jsonl" ]; then
  # Extract text content to a temp file — prefer result.result over assistant text
  node -e '
const fs = require("fs");
const lines = fs.readFileSync(process.argv[1], "utf8").split("\n");
let assistantText = "";
let resultText = "";
for (const line of lines) {
  if (!line.trim()) continue;
  try {
    const msg = JSON.parse(line);
    if (msg.type === "assistant" && msg.message && Array.isArray(msg.message.content)) {
      for (const block of msg.message.content) {
        if (block.type === "text") assistantText += block.text;
      }
    }
    if (msg.type === "result" && msg.result) resultText = msg.result;
  } catch(e) {}
}
const text = resultText || assistantText;
fs.writeFileSync(process.argv[2], text);
' "$METRICS_DIR/mayor.jsonl" "$METRICS_DIR/mayor-text.tmp" 2>/dev/null || true

  # Extract JSON from the text file and write to mayor-plan.json
  # (all intermediate data stays in files to avoid shell arg length limits and stderr leaks)
  if [ -f "$METRICS_DIR/mayor-text.tmp" ] && [ -s "$METRICS_DIR/mayor-text.tmp" ]; then
    node -e '
const fs = require("fs");
const text = fs.readFileSync(process.argv[1], "utf8");
let json = null;
// Try direct parse first
try { json = JSON.parse(text); } catch(e) {}
// Try extracting from code block
if (!json) {
  const m = text.match(/```(?:json)?\s*([\s\S]*?)```/);
  if (m) { try { json = JSON.parse(m[1].trim()); } catch(e) {} }
}
// Try finding JSON object in text
if (!json) {
  const m2 = text.match(/\{[\s\S]*\}/);
  if (m2) { try { json = JSON.parse(m2[0]); } catch(e) {} }
}
if (json) {
  fs.writeFileSync(process.argv[2], JSON.stringify(json));
} else {
  console.error("Mayor JSON extraction failed. Text starts with: " + text.substring(0, 200));
  process.exit(1);
}
' "$METRICS_DIR/mayor-text.tmp" "$METRICS_DIR/mayor-plan.json" 2>&1 || true
  else
    echo "  Mayor text file missing or empty"
  fi
fi

# Validate and parse the plan — all via files to avoid argv limits
STRATEGY="single"
POLECAT_COUNT=1
BEADS_JSON="[]"

if [ -f "$METRICS_DIR/mayor-plan.json" ] && [ -s "$METRICS_DIR/mayor-plan.json" ]; then
  node -e '
const fs = require("fs");
const plan = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
if (!plan.beads || !Array.isArray(plan.beads) || plan.beads.length === 0) {
  console.error("Mayor plan has no beads");
  process.exit(1);
}
const cap = parseInt(process.argv[2]) || 4;
if (plan.beads.length > cap) plan.beads = plan.beads.slice(0, cap);
const parsed = {
  strategy: plan.strategy || "single",
  count: plan.beads.length,
  beads: plan.beads,
  integration_notes: plan.integration_notes || "",
  post_merge_tasks: plan.post_merge_tasks || []
};
fs.writeFileSync(process.argv[3], JSON.stringify(parsed));
' "$METRICS_DIR/mayor-plan.json" "$GT_MAX_POLECATS" "$METRICS_DIR/mayor-parsed.json" 2>&1 || true

  if [ -f "$METRICS_DIR/mayor-parsed.json" ] && [ -s "$METRICS_DIR/mayor-parsed.json" ]; then
    STRATEGY=$(node -e 'const d=JSON.parse(require("fs").readFileSync(process.argv[1],"utf8"));console.log(d.strategy)' "$METRICS_DIR/mayor-parsed.json")
    POLECAT_COUNT=$(node -e 'const d=JSON.parse(require("fs").readFileSync(process.argv[1],"utf8"));console.log(d.count)' "$METRICS_DIR/mayor-parsed.json")
    BEADS_JSON=$(node -e 'const d=JSON.parse(require("fs").readFileSync(process.argv[1],"utf8"));console.log(JSON.stringify(d.beads))' "$METRICS_DIR/mayor-parsed.json")
    INTEGRATION_NOTES=$(node -e 'const d=JSON.parse(require("fs").readFileSync(process.argv[1],"utf8"));console.log(d.integration_notes)' "$METRICS_DIR/mayor-parsed.json")
    POST_MERGE_TASKS=$(node -e 'const d=JSON.parse(require("fs").readFileSync(process.argv[1],"utf8"));console.log(JSON.stringify(d.post_merge_tasks))' "$METRICS_DIR/mayor-parsed.json")
    echo "Mayor plan: strategy=$STRATEGY, polecats=$POLECAT_COUNT"
  else
    echo "WARN: Mayor plan validation failed, falling back to single-polecat mode"
    STRATEGY="single"
    POLECAT_COUNT=1
  fi
else
  echo "WARN: Mayor produced no parseable JSON, falling back to single-polecat mode"
  STRATEGY="single"
  POLECAT_COUNT=1
fi

# Build fallback single bead if needed
if [ "$POLECAT_COUNT" -eq 1 ] && [ "$BEADS_JSON" = "[]" ]; then
  BEADS_JSON='[{"id":"bead-1","title":"Full Task","description":"'"$(echo "$TASK_PROMPT" | head -c 500 | sed 's/"/\\"/g' | tr '\n' ' ')"'","files_to_create":[],"files_to_modify":[],"context_files":[],"shared_files":[]}]'
fi

echo "Strategy: $STRATEGY, Polecats: $POLECAT_COUNT"

# ============================================================================
# Phase 2: Parallel Polecats — One per bead
# ============================================================================

echo "=== Gas Town: Launching $POLECAT_COUNT polecat(s) ==="

POLECAT_PIDS=()
POLECAT_DIRS=()
POLECAT_BRANCHES=()
POLECAT_EXITS=()

for i in $(seq 0 $((POLECAT_COUNT - 1))); do
  BEAD=$(echo "$BEADS_JSON" | node -e "const d=JSON.parse(require('fs').readFileSync(0,'utf8'));console.log(JSON.stringify(d[$i]))")
  BEAD_TITLE=$(echo "$BEAD" | node -e 'const d=JSON.parse(require("fs").readFileSync(0,"utf8"));console.log(d.title||"task")')
  BEAD_DESC=$(echo "$BEAD" | node -e 'const d=JSON.parse(require("fs").readFileSync(0,"utf8"));console.log(d.description||"")')
  BEAD_ID_LOCAL=$(echo "$BEAD" | node -e 'const d=JSON.parse(require("fs").readFileSync(0,"utf8"));console.log(d.id||"bead-'$i'")')
  BEAD_CONTEXT=$(echo "$BEAD" | node -e 'const d=JSON.parse(require("fs").readFileSync(0,"utf8"));console.log(JSON.stringify(d.context_files||[]))')
  BEAD_SHARED=$(echo "$BEAD" | node -e 'const d=JSON.parse(require("fs").readFileSync(0,"utf8"));console.log(JSON.stringify(d.shared_files||[]))')

  POLECAT_NAME="pc-${i}"
  POLECAT_BRANCH="polecat-${BEAD_ID_LOCAL}"
  POLECAT_DIR="/tmp/town/bench/polecats/${POLECAT_NAME}/bench"
  POLECAT_HOME="/tmp/home-${POLECAT_NAME}"

  POLECAT_DIRS+=("$POLECAT_DIR")
  POLECAT_BRANCHES+=("$POLECAT_BRANCH")

  # Create worktree
  mkdir -p "/tmp/town/bench/polecats/${POLECAT_NAME}"
  cd /tmp/town/bench/.repo.git
  git worktree add -b "$POLECAT_BRANCH" "$POLECAT_DIR" "$DEFAULT_BRANCH" 2>&1

  echo "  Polecat $i ($BEAD_TITLE): worktree at $POLECAT_DIR"

  # Each polecat gets its own HOME to avoid OAuth credential races
  mkdir -p "$POLECAT_HOME/.claude"
  if [ -f /tmp/.claude-credentials.json ]; then
    cp /tmp/.claude-credentials.json "$POLECAT_HOME/.claude/.credentials.json"
  fi

  # Build polecat prompt
  POLECAT_PROMPT="You are polecat worker ${i} in a Gas Town multi-agent pipeline.

YOUR ASSIGNMENT (bead: ${BEAD_ID_LOCAL} — ${BEAD_TITLE}):
${BEAD_DESC}

CONTEXT FILES (read these for reference): ${BEAD_CONTEXT}
SHARED FILES (others may also modify these — be careful): ${BEAD_SHARED}

FULL TASK (for reference — implement ONLY your assignment above):
${TASK_PROMPT}"

  POLECAT_SYSTEM="You are a Gas Town polecat worker in a headless benchmark environment. There is no human to interact with.
- Implement ONLY your assigned bead — do not attempt the entire task
- Work in the current directory, do NOT create git worktrees or branches
- Read context_files for understanding, but focus changes on your assignment
- When done, commit your work with: git add -A && git commit -m 'polecat-${POLECAT_NAME}: ${BEAD_TITLE}'
- Focus on correctness: write code, run tests for your area, iterate"

  # Launch polecat in background
  (
    export HOME="$POLECAT_HOME"
    if [ -n "$PROXY_URL" ]; then
      export ANTHROPIC_BASE_URL="$PROXY_URL"
    fi
    cd "$POLECAT_DIR"

    # Set up GT environment for this polecat
    export GT_RIG=bench
    export GT_ROLE=polecat
    export GT_POLECAT="$POLECAT_NAME"
    export BD_ACTOR="bench/polecats/${POLECAT_NAME}"
    export BEADS_AGENT_NAME="bench/${POLECAT_NAME}"
    bd init --prefix bench >/dev/null 2>&1 || true

    claude -p \
      --model claude-opus-4-6 \
      --output-format stream-json \
      --verbose \
      --dangerously-skip-permissions \
      --disallowed-tools "AskUserQuestion,EnterPlanMode" \
      --append-system-prompt "$POLECAT_SYSTEM" \
      -- "$POLECAT_PROMPT" \
      > "$METRICS_DIR/polecat-${i}.jsonl" 2>"$METRICS_DIR/polecat-${i}-stderr.log"

    PC_EXIT=$?
    # Ensure work is committed even if polecat didn't do it
    cd "$POLECAT_DIR"
    git add -A 2>/dev/null || true
    git diff --cached --quiet 2>/dev/null || \
      git commit -m "polecat-${POLECAT_NAME}: ${BEAD_TITLE}" --no-verify 2>/dev/null || true
    exit $PC_EXIT
  ) &
  POLECAT_PIDS+=($!)
done

# Wait for all polecats
echo "=== Gas Town: Waiting for polecats ==="
WORST_EXIT=0
for i in $(seq 0 $((POLECAT_COUNT - 1))); do
  set +e
  wait "${POLECAT_PIDS[$i]}"
  EXIT_CODE=$?
  set -e
  POLECAT_EXITS+=($EXIT_CODE)
  echo "  Polecat $i exited: $EXIT_CODE"
  if [ $EXIT_CODE -ne 0 ] && [ $EXIT_CODE -gt $WORST_EXIT ]; then
    WORST_EXIT=$EXIT_CODE
  fi
done

# ============================================================================
# Phase 3: Refinery — Merge polecat branches
# ============================================================================

echo "=== Gas Town: Refinery merge phase ==="

# Work in the bare repo to merge branches, then sync result to /workspace
cd /tmp/town/bench/.repo.git

# Create a merge worktree on a new branch (can't checkout DEFAULT_BRANCH — already in rig worktree)
MERGE_DIR="/tmp/gastown-merge"
git worktree add -b merge-result "$MERGE_DIR" "$DEFAULT_BRANCH" 2>&1
cd "$MERGE_DIR"

# Configure git for merge commits
git config user.email "gastown@thunderdome.local"
git config user.name "Gas Town Refinery"

MERGE_CONFLICTS=0

if [ "$POLECAT_COUNT" -eq 1 ]; then
  # Single polecat: just fast-forward or merge
  echo "  Single polecat — merging ${POLECAT_BRANCHES[0]}"
  set +e
  git merge --no-edit "${POLECAT_BRANCHES[0]}" 2>&1
  MERGE_EXIT=$?
  set -e
  if [ $MERGE_EXIT -ne 0 ]; then
    echo "  WARN: Single polecat merge had issues (exit $MERGE_EXIT)"
    # Force take polecat's work
    git checkout --theirs . 2>/dev/null || true
    git add -A 2>/dev/null || true
    git commit --no-edit -m "refinery: resolved merge from single polecat" --no-verify 2>/dev/null || true
  fi
else
  # Multiple polecats: sequential merge
  for i in $(seq 0 $((POLECAT_COUNT - 1))); do
    BRANCH="${POLECAT_BRANCHES[$i]}"
    echo "  Merging branch: $BRANCH"

    set +e
    git merge --no-edit "$BRANCH" 2>&1
    MERGE_EXIT=$?
    set -e

    if [ $MERGE_EXIT -ne 0 ]; then
      echo "  CONFLICT merging $BRANCH — invoking Refinery resolver"
      MERGE_CONFLICTS=$((MERGE_CONFLICTS + 1))

      # Get conflict file list
      CONFLICT_FILES=$(git diff --name-only --diff-filter=U 2>/dev/null || echo "")
      if [ -n "$CONFLICT_FILES" ]; then
        CONFLICT_CONTENT=""
        for cf in $CONFLICT_FILES; do
          if [ -f "$cf" ]; then
            CONFLICT_CONTENT="${CONFLICT_CONTENT}
=== FILE: ${cf} ===
$(cat "$cf")
"
          fi
        done

        RESOLVER_PROMPT="You are the Gas Town Refinery conflict resolver. Merge conflicts occurred when integrating polecat branch '${BRANCH}'.

CONFLICTING FILES:
${CONFLICT_FILES}

FILE CONTENTS WITH CONFLICT MARKERS:
${CONFLICT_CONTENT}

TASK CONTEXT:
${TASK_PROMPT}

Resolve ALL conflicts by editing each conflicting file. Keep both sides' work where possible. Remove all <<<<<<< ======= >>>>>>> markers. Then run: git add -A"

        RESOLVER_SYSTEM="You are a merge conflict resolver in a headless environment. No human interaction available.
- Edit each conflicting file to resolve ALL conflict markers
- Prefer keeping both sides' changes where they don't contradict
- After resolving, stage all files with: git add -A
- Do NOT commit — the script will commit after you're done"

        set +e
        cd "$MERGE_DIR"
        claude -p \
          --model claude-opus-4-6 \
          --max-turns 5 \
          --output-format stream-json \
          --verbose \
          --dangerously-skip-permissions \
          --disallowed-tools "AskUserQuestion,EnterPlanMode" \
          --append-system-prompt "$RESOLVER_SYSTEM" \
          -- "$RESOLVER_PROMPT" \
          > "$METRICS_DIR/refinery-merge-${i}.jsonl" 2>"$METRICS_DIR/refinery-merge-${i}-stderr.log"
        set -e

        # Ensure everything is staged and commit
        cd "$MERGE_DIR"
        git add -A 2>/dev/null || true
        git diff --cached --quiet 2>/dev/null || \
          git commit --no-edit -m "refinery: resolved conflicts from $BRANCH" --no-verify 2>/dev/null || true
      else
        # No actual file conflicts, just commit the merge
        git add -A 2>/dev/null || true
        git commit --no-edit -m "refinery: merged $BRANCH" --no-verify 2>/dev/null || true
      fi
    fi
  done
fi

echo "  Merge complete. Conflicts resolved: $MERGE_CONFLICTS"

# Sync merged result to /workspace (no rsync in Docker — use tar)
cd "$MERGE_DIR"
tar cf - --exclude='.git' --exclude='.beads' . | (cd /workspace && tar xf -)

# ============================================================================
# Phase 4: Post-Merge Fixup
# ============================================================================

echo "=== Gas Town: Post-merge fixup check ==="

cd /workspace

# Check if build passes
set +e
npm install --ignore-scripts 2>/dev/null
npm run build 2>"$METRICS_DIR/build-check-stderr.log"
BUILD_EXIT=$?
set -e

NEEDS_FIXUP=0
if [ $BUILD_EXIT -ne 0 ]; then
  echo "  Build failed (exit $BUILD_EXIT) — running Refinery fixup"
  NEEDS_FIXUP=1
elif [ $MERGE_CONFLICTS -gt 0 ]; then
  echo "  Merge conflicts were resolved — running Refinery fixup for safety"
  NEEDS_FIXUP=1
else
  echo "  Build passed clean — skipping fixup"
fi

if [ $NEEDS_FIXUP -eq 1 ]; then
  BUILD_ERRORS=""
  if [ -f "$METRICS_DIR/build-check-stderr.log" ]; then
    BUILD_ERRORS=$(cat "$METRICS_DIR/build-check-stderr.log" | tail -50)
  fi

  FIXUP_PROMPT="You are the Gas Town Refinery post-merge fixup agent. Multiple polecats worked in parallel and their code has been merged. There may be integration issues.

BUILD RESULT: $([ $BUILD_EXIT -eq 0 ] && echo 'PASSED' || echo 'FAILED')
BUILD ERRORS:
${BUILD_ERRORS}

MERGE CONFLICTS RESOLVED: ${MERGE_CONFLICTS}

ORIGINAL TASK:
${TASK_PROMPT}

Fix any compilation errors, missing imports/exports, type mismatches, or integration issues. Make minimal, targeted fixes — do not refactor or rewrite working code. After fixes, run: npm run build && npm test"

  FIXUP_SYSTEM="You are a post-merge fixup agent in a headless benchmark environment. No human interaction.
- Fix ONLY integration issues: missing imports, type mismatches, duplicate declarations, unresolved references
- Do NOT rewrite or refactor working code
- Run build and tests to verify your fixes
- Keep changes minimal and targeted"

  set +e
  # Reset HOME to /tmp for the fixup agent
  export HOME=/tmp
  if [ -f /tmp/.claude-credentials.json ]; then
    mkdir -p "$HOME/.claude"
    cp /tmp/.claude-credentials.json "$HOME/.claude/.credentials.json"
  fi

  claude -p \
    --model claude-opus-4-6 \
    --output-format stream-json \
    --verbose \
    --dangerously-skip-permissions \
    --disallowed-tools "AskUserQuestion,EnterPlanMode" \
    --append-system-prompt "$FIXUP_SYSTEM" \
    -- "$FIXUP_PROMPT" \
    > "$METRICS_DIR/refinery-fixup.jsonl" 2>"$METRICS_DIR/refinery-fixup-stderr.log"
  FIXUP_EXIT=$?
  set -e

  echo "  Fixup agent exited: $FIXUP_EXIT"
fi

# ============================================================================
# Phase 5: Metrics Aggregation
# ============================================================================

echo "=== Gas Town: Aggregating metrics ==="

WALL_CLOCK_END=$(date +%s)
WALL_CLOCK_DURATION=$(( (WALL_CLOCK_END - WALL_CLOCK_START) * 1000 ))

node -e '
const fs = require("fs");
const path = require("path");

const metricsDir = process.argv[1];
const wallClockMs = parseInt(process.argv[2]) || 0;
const strategy = process.argv[3] || "single";
const polecatCount = parseInt(process.argv[4]) || 1;

function parseJsonlMetrics(filepath) {
  const m = {
    input_tokens: 0, output_tokens: 0, cache_read_tokens: 0,
    cache_creation_tokens: 0, turns: 0, tools_used: [],
    duration_ms: 0, total_cost_usd: 0
  };
  const toolsSeen = new Set();
  try {
    const lines = fs.readFileSync(filepath, "utf8").split("\n");
    for (const line of lines) {
      if (!line.trim()) continue;
      try {
        const msg = JSON.parse(line);
        if (msg.type === "result") {
          if (msg.usage) {
            m.input_tokens = msg.usage.input_tokens || 0;
            m.output_tokens = msg.usage.output_tokens || 0;
            m.cache_read_tokens = msg.usage.cache_read_input_tokens || 0;
            m.cache_creation_tokens = msg.usage.cache_creation_input_tokens || 0;
          }
          m.turns = msg.num_turns || 0;
          m.duration_ms = msg.duration_ms || 0;
          m.total_cost_usd = msg.total_cost_usd || 0;
        }
        if (msg.type === "assistant" && msg.message && Array.isArray(msg.message.content)) {
          for (const block of msg.message.content) {
            if (block.type === "tool_use" && block.name && !toolsSeen.has(block.name)) {
              toolsSeen.add(block.name);
              m.tools_used.push(block.name);
            }
          }
        }
      } catch(e) {}
    }
  } catch(e) {}
  return m;
}

// Parse all JSONL files
const roles = {};
const allTools = new Set();
let totalInput = 0, totalOutput = 0, totalCacheRead = 0, totalCacheCreate = 0;
let totalTurns = 0, totalCost = 0;

const files = fs.readdirSync(metricsDir).filter(f => f.endsWith(".jsonl"));
for (const f of files) {
  const m = parseJsonlMetrics(path.join(metricsDir, f));
  const role = f.replace(".jsonl", "");
  roles[role] = m;
  totalInput += m.input_tokens;
  totalOutput += m.output_tokens;
  totalCacheRead += m.cache_read_tokens;
  totalCacheCreate += m.cache_creation_tokens;
  totalTurns += m.turns;
  totalCost += m.total_cost_usd;
  m.tools_used.forEach(t => allTools.add(t));
}

const metrics = {
  input_tokens: totalInput,
  output_tokens: totalOutput,
  cache_read_tokens: totalCacheRead,
  cache_creation_tokens: totalCacheCreate,
  turns: totalTurns,
  tools_used: Array.from(allTools),
  duration_ms: wallClockMs,
  total_cost_usd: Math.round(totalCost * 1000) / 1000,
  gastown_meta: {
    strategy: strategy,
    polecat_count: polecatCount,
    roles: roles
  }
};

fs.writeFileSync("/workspace/.thunderdome-metrics.json", JSON.stringify(metrics, null, 2));
console.error("Metrics: " + JSON.stringify({
  strategy, polecats: polecatCount,
  tokens: totalInput + totalOutput,
  cost: metrics.total_cost_usd,
  turns: totalTurns,
  wall_clock_s: Math.round(wallClockMs / 1000)
}));
' "$METRICS_DIR" "$WALL_CLOCK_DURATION" "$STRATEGY" "$POLECAT_COUNT" || true

cd /workspace
echo "=== Gas Town adapter complete ==="
exit 0
