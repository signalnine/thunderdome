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
- **RunTests**: run the test suite and get structured pass/fail results (parsed summary + raw output). Use this instead of shelling out to npm test.
- **ApplyPatch**: apply coordinated multi-file edits atomically. Rolls back if any edit fails. Use for changes that span multiple files.
- **VerifyContract**: mechanically verify each checkbox in CONTRACT.md by running its test command. Format each contract item as: "- [ ] behavior -> test: <command>".
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
    description: "Create and manage a structured task list for the current session. Use proactively to track progress on multi-step tasks.",
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


  // -------- RunTests --------
  pi.registerTool({
    name: "RunTests",
    label: "RunTests",
    description: "Run the test suite (npm test). Returns the raw output (truncated to 8KB) plus a parsed summary of passed/failed counts and failing test file names. Use this instead of shelling out to npm test -- gives you structured feedback loops.",
    promptSnippet: "Use RunTests to execute tests and see failures in structured form.",
    parameters: Type.Object({
      pattern: Type.Optional(Type.String({ description: "Test file pattern to filter (e.g. 'src/user.test.ts'). Omit to run all." })),
    }),
    async execute(_toolCallId, params) {
      const args = params.pattern ? ["test", "--", params.pattern] : ["test"];
      const res = spawnSync("npm", args, { encoding: "utf-8", maxBuffer: 50 * 1024 * 1024 });
      const raw = (res.stdout || "") + "\n" + (res.stderr || "");
      // Truncate long output, keep end (where failures usually are)
      const maxOut = 8000;
      const out = raw.length > maxOut ? "... [truncated start]\n" + raw.slice(raw.length - maxOut) : raw;

      // Parse summary: look for vitest's "Tests  N passed | M failed" line
      const summary: { passed?: number; failed?: number; failingFiles: string[] } = { failingFiles: [] };
      const sumMatch = raw.match(/Tests\s+(\d+)\s+passed[^\d]+(\d+)\s+failed/i)
                      || raw.match(/Test Files\s+(\d+)\s+passed\s*\|\s*(\d+)\s+failed/i);
      if (sumMatch) {
        summary.passed = parseInt(sumMatch[1], 10);
        summary.failed = parseInt(sumMatch[2], 10);
      } else {
        // Alternate: just "Tests  N passed"
        const passOnly = raw.match(/Tests\s+(\d+)\s+passed/i);
        if (passOnly) { summary.passed = parseInt(passOnly[1], 10); summary.failed = 0; }
      }
      // Collect FAIL lines (vitest prints "FAIL path/to/test.ts")
      const failRe = /^FAIL\s+(.+\.(?:test|spec)\.[tj]sx?)/gm;
      let m;
      while ((m = failRe.exec(raw)) !== null) summary.failingFiles.push(m[1]);

      const summaryText = `Summary: passed=${summary.passed ?? "?"} failed=${summary.failed ?? "?"}`
        + (summary.failingFiles.length ? `\nFailing files:\n  ${summary.failingFiles.join("\n  ")}` : "");
      return {
        content: [{ type: "text", text: summaryText + "\n\n--- raw output ---\n" + out }],
        details: { exitCode: res.status, ...summary },
      };
    },
  });

  // -------- ApplyPatch (atomic multi-file edit) --------
  pi.registerTool({
    name: "ApplyPatch",
    label: "ApplyPatch",
    description: "Apply multiple edits across multiple files atomically. Each edit specifies a file path, an exact old_string to find, and the new_string to replace it with. If any edit can't apply (old_string not found or not unique), the entire patch rolls back with no changes. Use this when changes span multiple files that must stay in sync.",
    promptSnippet: "Use ApplyPatch for coordinated multi-file edits. Prevents half-applied changes.",
    parameters: Type.Object({
      edits: Type.Array(
        Type.Object({
          path: Type.String({ description: "File path (relative to cwd)." }),
          old_string: Type.String({ description: "Exact text to replace (must appear exactly once in the file)." }),
          new_string: Type.String({ description: "Replacement text." }),
        }),
      ),
    }),
    async execute(_toolCallId, params) {
      const backups: { path: string; content: string }[] = [];
      const problems: string[] = [];

      // Validate + snapshot
      for (const edit of params.edits) {
        let content: string;
        try { content = fs.readFileSync(edit.path, "utf-8"); }
        catch (e: any) { problems.push(`${edit.path}: read failed (${e.message})`); continue; }
        backups.push({ path: edit.path, content });

        // Count occurrences
        const occurrences = content.split(edit.old_string).length - 1;
        if (occurrences === 0) problems.push(`${edit.path}: old_string not found`);
        else if (occurrences > 1) problems.push(`${edit.path}: old_string appears ${occurrences} times (must be unique)`);
      }

      if (problems.length > 0) {
        return {
          content: [{ type: "text", text: "Patch rejected (no changes applied):\n" + problems.join("\n") }],
          details: { applied: 0, rejected: problems.length },
        };
      }

      // Apply all edits; track applied for rollback
      const applied: { path: string; content: string }[] = [];
      try {
        for (const edit of params.edits) {
          const current = fs.readFileSync(edit.path, "utf-8");
          const updated = current.replace(edit.old_string, edit.new_string);
          applied.push({ path: edit.path, content: current });
          fs.writeFileSync(edit.path, updated);
        }
        return {
          content: [{ type: "text", text: `Applied ${params.edits.length} edits across ${new Set(params.edits.map(e => e.path)).size} files.` }],
          details: { applied: params.edits.length },
        };
      } catch (e: any) {
        // Rollback
        for (const b of applied) fs.writeFileSync(b.path, b.content);
        return {
          content: [{ type: "text", text: `Patch failed mid-apply, rolled back: ${e.message}` }],
          details: { applied: 0, error: e.message },
        };
      }
    },
  });

  // -------- VerifyContract --------
  pi.registerTool({
    name: "VerifyContract",
    label: "VerifyContract",
    description: "Read CONTRACT.md, find each checklist item with a '→ test: <command>' suffix, run the commands, and report which pass and which fail. Use this to mechanically verify your implementation against the contract you wrote.",
    promptSnippet: "Use VerifyContract after finishing an implementation to check each criterion.",
    parameters: Type.Object({
      path: Type.Optional(Type.String({ description: "Path to the contract file (default: CONTRACT.md)." })),
    }),
    async execute(_toolCallId, params) {
      const contractPath = params.path ?? "CONTRACT.md";
      let content: string;
      try { content = fs.readFileSync(contractPath, "utf-8"); }
      catch (e: any) {
        return {
          content: [{ type: "text", text: `Contract file not found: ${contractPath}` }],
          details: { found: false },
        };
      }

      // Parse lines like "- [ ] behavior -> test: command" or "- [x] behavior → test: command"
      const lines = content.split("\n");
      const items: { label: string; command: string }[] = [];
      for (const line of lines) {
        const m = line.match(/^\s*-\s*\[[\s xX]\]\s*(.+?)\s*(?:->|→|=>)\s*test:\s*(.+)$/);
        if (m) items.push({ label: m[1].trim(), command: m[2].trim() });
      }

      if (items.length === 0) {
        return {
          content: [{ type: "text", text: "No verifiable items found in CONTRACT.md. Format each item as: - [ ] behavior -> test: <command>" }],
          details: { items: 0 },
        };
      }

      const results: { label: string; passed: boolean; output: string }[] = [];
      for (const item of items) {
        const res = spawnSync("bash", ["-c", item.command], {
          encoding: "utf-8",
          maxBuffer: 1024 * 1024,
          timeout: 60_000,
        });
        results.push({
          label: item.label,
          passed: res.status === 0,
          output: ((res.stdout || "") + (res.stderr || "")).slice(-500),
        });
      }

      const passCount = results.filter((r) => r.passed).length;
      const text = `Contract verification: ${passCount}/${results.length} passed\n\n` +
        results
          .map(
            (r) =>
              `[${r.passed ? "PASS" : "FAIL"}] ${r.label}` +
              (r.passed ? "" : `\n  Output: ${r.output.slice(-300)}`),
          )
          .join("\n");
      return {
        content: [{ type: "text", text }],
        details: { total: results.length, passed: passCount, failed: results.length - passCount },
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
