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

## Built-in Tool Guidance

The pi runtime gives you four built-in tools (read, bash, edit, write). Use them with these rules:

- **read**: Always read a file before editing it. When the file might have changed (you or a test modified it), re-read to pick up the new state. Skip files over 100KB unless explicitly needed.
- **edit**: Always prefer edit over write when modifying existing files. edit takes a list of exact-text replacements. Each old text must match EXACTLY (including whitespace) and be UNIQUE in the file. If a replacement fails, make your edit more specific (add surrounding context) -- don't give up or switch to write.
- **write**: Only use write for brand-new files or complete rewrites. NEVER use write when edit would work. Writing a whole file loses history and is wasteful of tokens.
- **bash**: For running tests, builds, and lint. Examples: npm run build, npm test, npm run lint. Do NOT use bash for file search (use Grep) or file listing (use Glob). Keep commands focused -- prefer a single npm test over a pipeline of find piped to xargs.

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
    name: "TodoWrite",
    label: "TodoWrite",
    description: "Create and manage a structured task list for the current coding session. This helps you track progress, organize complex tasks, and demonstrate thoroughness. Use this tool PROACTIVELY for complex multi-step tasks (3+ distinct steps), non-trivial tasks requiring careful planning, and when capturing requirements as todos. Skip for single straightforward tasks, trivial tasks (1-2 steps), or purely conversational exchanges. Task states: pending (not started), in_progress (currently working -- only ONE at a time), completed (finished successfully). Update the list as you work -- mark tasks completed IMMEDIATELY after finishing, don't batch. If you discover new subtasks mid-work, add them. Use activeForm (present-continuous) to describe what you're doing right now.",
    promptSnippet: "Use TodoWrite to plan and track multi-step work. Mark todos in_progress when you start and completed when done.",
    parameters: Type.Object({
      todos: Type.Array(
        Type.Object({
          content: Type.String({ description: "Task description (imperative, e.g. 'Fix auth bug')." }),
          status: Type.Union([Type.Literal("pending"), Type.Literal("in_progress"), Type.Literal("completed")]),
          activeForm: Type.String({ description: "Present-continuous form shown while in_progress." }),
        }),
      ),
    }),
    async execute(_toolCallId, params) {
      todos = params.todos as TodoItem[];
      const rendered = todos
        .map((t) => {
          const box = t.status === "completed" ? "[x]" : t.status === "in_progress" ? "[~]" : "[ ]";
          return `${box} ${t.content}`;
        })
        .join("\n");
      return {
        content: [{ type: "text", text: `Todos updated:\n${rendered}` }],
        details: { count: todos.length },
      };
    },
  });

  pi.registerTool({
    name: "Grep",
    label: "Grep",
    description: "A powerful search tool built on ripgrep. ALWAYS use Grep for search tasks. NEVER invoke grep or rg as a Bash command -- the Grep tool is optimized for this benchmark's file layouts. Supports full regex syntax (e.g. 'log.*Error', 'function\\\\s+\\\\w+'). Filter files with the glob parameter (e.g. '*.ts', '**/*.tsx') rather than piping through find. Output modes: 'content' shows matching lines (default, use for understanding code), 'files_with_matches' shows only file paths (use when you just need to locate). Prefer Grep over cat/Read when you want to find something -- Grep returns exactly what matches, saving tokens.",
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
    description: "Fast file-path pattern matching tool that works with any codebase size. ALWAYS use Glob to find files by name patterns. NEVER invoke find via Bash for this purpose. Supports glob patterns like '**/*.js' or 'src/**/*.ts'. Returns matching file paths sorted by modification time (most recently modified first), which usually puts the files you care about at the top. Use this tool when you need to locate files; combine with Read/Grep afterward for content inspection.",
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
