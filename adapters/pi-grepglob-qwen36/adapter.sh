#!/bin/bash
set -e

# --- Conclave-shaped pi + Qwen3.6-35B-A3B via Neuralwatt ---
# Adds Claude-Code-style tools (Grep, Glob, TodoWrite) and injects the
# Conclave v8 system prompt into pi. Tests whether giving pi Claude Code's
# tool surface + disciplined prompt closes the harness gap on Qwen3.6.
#
# Vanilla pi + Qwen3.6: 55.3%
# Claude Code + Qwen3.6: 70.3%
# Conclave v8 + Qwen3.6: 69.1% (v8 alone with Claude Code tools)
# Expected range for this experiment: 60-80%

[[ -f "$TASK_DESCRIPTION" ]] || { echo "Task file not found: $TASK_DESCRIPTION" >&2; exit 2; }

cd "$TASK_DIR"

export HOME=/tmp
export PATH="/root/.bun/bin:$PATH"
export PI_CODING_AGENT_DIR="/tmp/.pi/agent"
mkdir -p "$PI_CODING_AGENT_DIR/extensions"

git config user.name "pi"
git config user.email "pi@thunderdome"

# Route pi through openai_proxy to fix vLLM role=developer -> role=system.
PROXY_PORT=$(python3 -c "import socket; s=socket.socket(); s.bind(('',0)); print(s.getsockname()[1]); s.close()")
PROXY_LOG=/tmp/pi-proxy.jsonl
python3 /usr/local/bin/openai_proxy.py \
  --port "$PROXY_PORT" \
  --log "$PROXY_LOG" \
  --upstream "https://api.neuralwatt.com/v1" \
  --auth-key "$NEURALWATT_API_KEY" \
  2>/dev/null &
PROXY_PID=$!

for i in {1..10}; do
  if python3 -c "import urllib.request; urllib.request.urlopen('http://localhost:$PROXY_PORT/health', timeout=1)" 2>/dev/null; then
    break
  fi
  sleep 0.5
done

# Register Neuralwatt as a custom provider, pointing at the local proxy.
cat > "$PI_CODING_AGENT_DIR/models.json" <<EOF
{
  "providers": {
    "neuralwatt": {
      "baseUrl": "http://localhost:$PROXY_PORT",
      "api": "openai-completions",
      "apiKey": "NEURALWATT_API_KEY",
      "authHeader": true,
      "models": [
        {
          "id": "Qwen/Qwen3.6-35B-A3B",
          "name": "Qwen3.6 35B-A3B",
          "reasoning": true,
          "input": ["text"],
          "contextWindow": 131072,
          "maxTokens": 65536,
          "cost": { "input": 0.1, "output": 0.1, "cacheRead": 0, "cacheWrite": 0 }
        }
      ]
    }
  }
}
EOF

# Install the Conclave-shaped extension (inlined because thunderdome only
# mounts adapter.sh; we can't copy sidecar files into the container).
cat > "$PI_CODING_AGENT_DIR/extensions/conclave-shaped.ts" <<'EXTENSION_EOF'
import * as fs from "node:fs";
import { spawnSync } from "node:child_process";
import type { ExtensionAPI } from "@mariozechner/pi-coding-agent";
import { Type } from "@sinclair/typebox";

const V8_PROMPT = `

# Conclave v8 Methodology

You are running in a headless benchmark environment. No human to interact with. Work directly in the current directory -- no worktrees or branches.

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

### 6. Adversarial Self-Review
After all contract criteria pass, review your own diff as if you were a hostile code reviewer. Read every line. Check for missing edge cases, off-by-one errors, unhandled errors, race conditions, dead code, debug artifacts, TODOs left behind. If you find issues, fix them and re-verify.

Done means: all contract criteria pass, tests pass, build clean, lint clean, self-review clean.

## Additional Tools Available

Beyond read/bash/edit/write you have:

- **Grep**: ripgrep regex search across files. Use to find symbols/patterns instead of cat'ing.
- **Glob**: fast file pattern matching (e.g. "src/**/*.ts"). Use instead of 'find' shell calls.
- **TodoWrite**: structured todo list to track your plan. Use at start of task and update as you work; externalizes state so you don't re-derive context every turn.
`;

interface TodoItem {
  content: string;
  status: "pending" | "in_progress" | "completed";
  activeForm: string;
}

export default function conclaveShapedExtension(pi: ExtensionAPI) {
  let todos: TodoItem[] = [];

  
pi.registerTool({
    name: "Grep",
    label: "Grep",
    description: "Fast regex search across files using ripgrep. Returns matching lines with file:line. Use to find symbols/patterns/text across the codebase.",
    promptSnippet: "Use Grep to search file contents with regex.",
    parameters: Type.Object({
      pattern: Type.String({ description: "Regex pattern (ripgrep syntax)." }),
      path: Type.Optional(Type.String({ description: "File or directory (defaults to cwd)." })),
      glob: Type.Optional(Type.String({ description: "File glob filter, e.g. '*.ts'." })),
      output_mode: Type.Optional(Type.Union([Type.Literal("content"), Type.Literal("files_with_matches")])),
      case_insensitive: Type.Optional(Type.Boolean()),
    }),
    async execute(_toolCallId, params) {
      const args = ["--no-heading", "--line-number", "--color=never"];
      if (params.case_insensitive) args.push("-i");
      if (params.glob) args.push("--glob", params.glob);
      if ((params.output_mode ?? "content") === "files_with_matches") args.push("--files-with-matches");
      args.push("--", params.pattern);
      if (params.path) args.push(params.path);
      const res = spawnSync("rg", args, { encoding: "utf-8", maxBuffer: 10 * 1024 * 1024 });
      const out = (res.stdout || "") + (res.stderr || "");
      const truncated = out.length > 200_000 ? out.slice(0, 200_000) + "\n... [truncated]" : out;
      return {
        content: [{ type: "text", text: truncated || "(no matches)" }],
        details: { exitCode: res.status, pattern: params.pattern },
      };
    },
  });
pi.registerTool({
    name: "Glob",
    label: "Glob",
    description: "Fast file-path pattern matching. Returns matching file paths sorted by modification time. Use instead of shelling out to 'find'.",
    promptSnippet: "Use Glob to find files by path pattern (e.g. 'src/**/*.ts').",
    parameters: Type.Object({
      pattern: Type.String({ description: "Glob pattern, e.g. '**/*.ts' or 'src/components/**/*.tsx'." }),
      path: Type.Optional(Type.String({ description: "Root directory (defaults to cwd)." })),
    }),
    async execute(_toolCallId, params) {
      const root = params.path ?? ".";
      const rg = spawnSync("rg", ["--files", "--glob", params.pattern, root], {
        encoding: "utf-8",
        maxBuffer: 10 * 1024 * 1024,
      });
      const files = (rg.stdout || "").split("\n").filter(Boolean);
      const withMtime = files
        .map((f) => {
          try { return { f, m: fs.statSync(f).mtimeMs }; } catch { return null; }
        })
        .filter((x): x is { f: string; m: number } => !!x)
        .sort((a, b) => b.m - a.m)
        .map((x) => x.f);
      const out = withMtime.join("\n");
      const truncated = out.length > 100_000 ? out.slice(0, 100_000) + "\n... [truncated]" : out;
      return {
        content: [{ type: "text", text: truncated || "(no matches)" }],
        details: { count: withMtime.length, pattern: params.pattern },
      };
    },
  });
  pi.on("before_agent_start", async (event: any) => {
    return { systemPrompt: event.systemPrompt + V8_PROMPT };
  });

}
EXTENSION_EOF

TASK_PROMPT=$(cat "$TASK_DESCRIPTION")

WALL_CLOCK_START=$(date +%s)

echo "=== Conclave-pi (Qwen3.6 via Neuralwatt): Starting ==="

set +e
pi --provider neuralwatt --model "Qwen/Qwen3.6-35B-A3B" -p \
  "IMPORTANT: Do NOT brainstorm, ask clarifying questions, or create implementation plans. Start writing code immediately. Implement the task directly, then verify with tests/build/lint before finishing.

$TASK_PROMPT" \
  2>&1 | tee /workspace/.pi-stdout.log
PI_EXIT=${PIPESTATUS[0]}
set -e

echo "pi exited: $PI_EXIT"
kill $PROXY_PID 2>/dev/null || true

WALL_CLOCK_END=$(date +%s)
WALL_CLOCK_DURATION=$(( (WALL_CLOCK_END - WALL_CLOCK_START) * 1000 ))

# Count turns from proxy log; Neuralwatt energy-priced at $0.00208/turn.
TURNS=0
if [ -f "$PROXY_LOG" ]; then
  TURNS=$(wc -l < "$PROXY_LOG" | tr -d ' ')
fi
COST=$(python3 -c "print(round($TURNS * 0.00208, 6))")

cat > /workspace/.thunderdome-metrics.json << EOF
{
  "input_tokens": 0,
  "output_tokens": 0,
  "cache_read_tokens": 0,
  "cache_creation_tokens": 0,
  "turns": $TURNS,
  "duration_ms": $WALL_CLOCK_DURATION,
  "total_cost_usd": $COST
}
EOF

exit $PI_EXIT
