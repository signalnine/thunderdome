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

The user will primarily request you to perform software engineering tasks. These may include solving bugs, adding new functionality, refactoring code, explaining code, and more. When given an unclear or generic instruction, consider it in the context of these software engineering tasks and the current working directory. For example, if the user asks you to change "methodName" to snake case, do not reply with just "method_name", instead find the method in the code and modify the code.

You are highly capable and often allow users to complete ambitious tasks that would otherwise be too complex or take too long. You should defer to user judgement about whether a task is too large to attempt.

Avoid backwards-compatibility hacks like renaming unused _vars, re-exporting types, adding // removed comments for removed code, etc. If you are certain that something is unused, you can delete it completely.

Don't add error handling, fallbacks, or validation for scenarios that can't happen. Trust internal code and framework guarantees. Only validate at system boundaries (user input, external APIs). Don't use feature flags or backwards-compatibility shims when you can just change the code.

Be careful not to introduce security vulnerabilities such as command injection, XSS, SQL injection, and other OWASP top 10 vulnerabilities. If you notice that you wrote insecure code, immediately fix it. Prioritize writing safe, secure, and correct code.

Your responses should be short and concise.

When referencing specific functions or pieces of code include the pattern file_path:line_number to allow the user to easily navigate to the source code location.

# Executing actions with care

Carefully consider the reversibility and blast radius of actions. Generally you can freely take local, reversible actions like editing files or running tests. But for actions that are hard to reverse, affect shared systems beyond your local environment, or could otherwise be risky or destructive, check with the user before proceeding. The cost of pausing to confirm is low, while the cost of an unwanted action (lost work, unintended messages sent, deleted branches) can be very high. For actions like these, consider the context, the action, and user instructions, and by default transparently communicate the action and ask for confirmation before proceeding. This default can be changed by user instructions - if explicitly asked to operate more autonomously, then you may proceed without confirmation, but still attend to the risks and consequences when taking actions. A user approving an action (like a git push) once does NOT mean that they approve it in all contexts, so unless actions are authorized in advance in durable instructions like CLAUDE.md files, always confirm first. Authorization stands for the scope specified, not beyond. Match the scope of your actions to what was actually requested.

Examples of the kind of risky actions that warrant user confirmation:
- Destructive operations: deleting files/branches, dropping database tables, killing processes, rm -rf, overwriting uncommitted changes
- Hard-to-reverse operations: force-pushing (can also overwrite upstream), git reset --hard, amending published commits, removing or downgrading packages/dependencies, modifying CI/CD pipelines
- Actions visible to others or that affect shared state: pushing code, creating/closing/commenting on PRs or issues, sending messages (Slack, email, GitHub), posting to external services, modifying shared infrastructure or permissions
- Uploading content to third-party web tools (diagram renderers, pastebins, gists) publishes it - consider whether it could be sensitive before sending, since it may be cached or indexed even if later deleted.

When you encounter an obstacle, do not use destructive actions as a shortcut to simply make it go away. For instance, try to identify root causes and fix underlying issues rather than bypassing safety checks (e.g. --no-verify). If you discover unexpected state like unfamiliar files, branches, or configuration, investigate before deleting or overwriting, as it may represent the user's in-progress work. For example, typically resolve merge conflicts rather than discarding changes; similarly, if a lock file exists, investigate what process holds it rather than deleting it. In short: only take risky actions carefully, and when in doubt, ask before acting. Follow both the spirit and letter of these instructions - measure twice, cut once.

You can call multiple tools in a single response. If you intend to call multiple tools and there are no dependencies between them, make all independent tool calls in parallel. Maximize use of parallel tool calls where possible to increase efficiency. However, if some tool calls depend on previous calls to inform dependent values, do NOT call these tools in parallel and instead call them sequentially. For instance, if one operation must complete before another starts, run these operations sequentially instead.

Break down and manage your work with the TodoWrite tool. These tools are helpful for planning your work and helping the user track your progress. Mark each task as completed as soon as you are done with the task. Do not batch up multiple tasks before marking them as completed.

# Text output (does not apply to tool calls)
Assume users can't see most tool calls or thinking — only your text output. Before your first tool call, state in one sentence what you're about to do. While working, give short updates at key moments: when you find something, when you change direction, or when you hit a blocker. Brief is good — silent is not. One sentence per update is almost always enough.

Don't narrate your internal deliberation. User-facing text should be relevant communication to the user, not a running commentary on your thought process. State results and decisions directly, and focus user-facing text on relevant updates for the user.

When you do write updates, write so the reader can pick up cold: complete sentences, no unexplained jargon or shorthand from earlier in the session. But keep it tight — a clear sentence is better than a clear paragraph.

End-of-turn summary: one or two sentences. What changed and what's next. Nothing else.

Match responses to the task: a simple question gets a direct answer, not headers and sections.

In code: default to writing no comments. Never write multi-paragraph docstrings or multi-line comment blocks — one short line max. Don't create planning, decision, or analysis documents unless the user asks for them — work from conversation context, not intermediate files.
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
    description: "Use this tool to create and manage a structured task list for your current coding session. This helps you track progress, organize complex tasks, and demonstrate thoroughness to the user.\nIt also helps the user understand the progress of the task and overall progress of their requests.\n\n## When to Use This Tool\nUse this tool proactively in these scenarios:\n\n1. Complex multi-step tasks - When a task requires 3 or more distinct steps or actions\n2. Non-trivial and complex tasks - Tasks that require careful planning or multiple operations\n3. User explicitly requests todo list - When the user directly asks you to use the todo list\n4. User provides multiple tasks - When users provide a list of things to be done (numbered or comma-separated)\n5. After receiving new instructions - Immediately capture user requirements as todos\n6. When you start working on a task - Mark it as in_progress BEFORE beginning work. Ideally you should only have one todo as in_progress at a time\n7. After completing a task - Mark it as completed and add any new follow-up tasks discovered during implementation\n\n## When NOT to Use This Tool\n\nSkip using this tool when:\n1. There is only a single, straightforward task\n2. The task is trivial and tracking it provides no organizational benefit\n3. The task can be completed in less than 3 trivial steps\n4. The task is purely conversational or informational\n\nNOTE that you should not use this tool if there is only one trivial task to do. In this case you are better off just doing the task directly.\n\n## Task States\n- pending: Not yet started\n- in_progress: Currently working (only ONE at a time)\n- completed: Finished successfully\n\nMark completed IMMEDIATELY after finishing. Only ONE task should be in_progress at any time.",
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
    description: "A powerful search tool built on ripgrep\n\n  Usage:\n  - ALWAYS use Grep for search tasks. NEVER invoke `grep` or `rg` as a bash command. The Grep tool has been optimized for correct permissions and access.\n  - Supports full regex syntax (e.g., \"log.*Error\", \"function\\s+\\w+\")\n  - Filter files with glob parameter (e.g., \"*.js\", \"**/*.tsx\") or type parameter (e.g., \"js\", \"py\", \"rust\")\n  - Output modes: \"content\" shows matching lines, \"files_with_matches\" shows only file paths (default), \"count\" shows match counts\n  - Use Task tool for open-ended searches requiring multiple rounds\n  - Pattern syntax: Uses ripgrep (not grep) - literal braces need escaping (use `interface\\{\\}` to find `interface{}` in Go code)\n  - Multiline matching: By default patterns match within single lines only. For cross-line patterns like `struct \\{[\\s\\S]*?field`, use `multiline: true`",
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


  // ======== Built-in Tool Overrides (Claude-Code output formatting) ========
  // Same parameter shapes as pi's built-ins; output reformatted to match
  // Claude Code conventions so Qwen3.6's training priors kick in.

  // -------- read (override) --------
  pi.registerTool({
    name: "read",
    label: "Read",
    description: "Reads a file from the local filesystem. You can access any file directly by using this tool.\nAssume this tool is able to read all files on the machine. If the User provides a path to a file assume that path is valid. It is okay to read a file that does not exist; an error will be returned.\n\nUsage:\n- The file_path parameter must be an absolute path, not a relative path\n- By default, it reads up to 2000 lines starting from the beginning of the file\n\n\n- This tool allows Claude Code to read images (eg PNG, JPG, etc). When reading an image file the contents are presented visually as Claude Code is a multimodal LLM.\n- This tool can read Jupyter notebooks (.ipynb files) and returns all cells with their outputs, combining code, text, and visualizations.\n- This tool can only read files, not directories. To read a directory, use an ls command via the bash tool.\n- You will regularly be asked to read screenshots. If the user provides a path to a screenshot, ALWAYS use this tool to view the file at the path. This tool will work with all temporary file paths.\n- If you read a file that exists but has empty contents you will receive a system reminder warning in place of file contents.",
    parameters: Type.Object({
      path: Type.String({ description: "File path (relative or absolute)." }),
      offset: Type.Optional(Type.Number({ description: "Line to start reading from (1-indexed)." })),
      limit: Type.Optional(Type.Number({ description: "Max number of lines to read." })),
    }),
    async execute(_toolCallId, params, _signal, _onUpdate, ctx) {
      const abs = require("node:path").resolve(ctx.cwd, params.path);
      try {
        const raw = fs.readFileSync(abs, "utf-8");
        const lines = raw.split("\n");
        const start = params.offset ? Math.max(0, params.offset - 1) : 0;
        const end = params.limit ? Math.min(lines.length, start + params.limit) : lines.length;
        const numbered = [];
        for (let i = start; i < end; i++) {
          const n = String(i + 1).padStart(6, " ");
          numbered.push(`${n}\u2192${lines[i]}`);
        }
        let text = numbered.join("\n");
        const maxBytes = 50 * 1024;
        if (Buffer.byteLength(text, "utf-8") > maxBytes) {
          text = text.slice(0, maxBytes) + "\n\n[Output truncated at 50KB]";
        }
        return {
          content: [{ type: "text", text }],
          details: { lines: lines.length },
        };
      } catch (e: any) {
        return {
          content: [{ type: "text", text: `Error reading ${params.path}: ${e.message}` }],
          details: { error: e.message },
        };
      }
    },
  });

  // -------- bash (override) --------
  pi.registerTool({
    name: "bash",
    label: "Bash",
    description: "Execute a bash command. Output wraps stdout and stderr in explicit blocks with exit code, matching the Claude Code convention.",
    parameters: Type.Object({
      command: Type.String({ description: "The command to execute." }),
    }),
    async execute(_toolCallId, params) {
      const res = spawnSync("bash", ["-c", params.command], {
        encoding: "utf-8",
        maxBuffer: 10 * 1024 * 1024,
        timeout: 120_000,
      });
      const stdout = res.stdout || "";
      const stderr = res.stderr || "";
      const exitCode = res.status ?? 0;
      const text = `<stdout>\n${stdout}</stdout>\n<stderr>\n${stderr}</stderr>\n<exit_code>${exitCode}</exit_code>`;
      return {
        content: [{ type: "text", text }],
        details: { exitCode },
      };
    },
  });

  // -------- edit (override) --------
  pi.registerTool({
    name: "edit",
    label: "Edit",
    description: "Performs exact string replacements in files.\n\nUsage:\n- You must use your `read` tool at least once in the conversation before editing. This tool will error if you attempt an edit without reading the file.\n- When editing text from Read tool output, ensure you preserve the exact indentation (tabs/spaces) as it appears AFTER the line number prefix. The line number prefix format is: line number + arrow. Everything after that is the actual file content to match. Never include any part of the line number prefix in the old_string or new_string.\n- ALWAYS prefer editing existing files in the codebase. NEVER write new files unless explicitly required.\n- Only use emojis if the user explicitly requests it. Avoid adding emojis to files unless asked.\n- Use `replace_all` for replacing and renaming strings across the file. This parameter is useful if you want to rename a variable for instance.",
    parameters: Type.Object({
      path: Type.String({ description: "File path." }),
      edits: Type.Array(
        Type.Object({
          oldText: Type.String({ description: "Exact text to replace (must be unique in file)." }),
          newText: Type.String({ description: "Replacement text." }),
        }),
        { minItems: 1 },
      ),
    }),
    async execute(_toolCallId, params, _signal, _onUpdate, ctx) {
      const abs = require("node:path").resolve(ctx.cwd, params.path);
      let content: string;
      try { content = fs.readFileSync(abs, "utf-8"); }
      catch (e: any) {
        return { content: [{ type: "text", text: `Error: ${e.message}` }], details: { error: e.message } };
      }
      const problems: string[] = [];
      for (const ed of params.edits) {
        const n = content.split(ed.oldText).length - 1;
        if (n === 0) problems.push("oldText not found: " + ed.oldText.slice(0, 60));
        else if (n > 1) problems.push(`oldText appears ${n} times (must be unique): ` + ed.oldText.slice(0, 60));
      }
      if (problems.length) {
        return { content: [{ type: "text", text: "Edit failed:\n" + problems.join("\n") }], details: { failed: true } };
      }
      let updated = content;
      for (const ed of params.edits) updated = updated.replace(ed.oldText, ed.newText);
      fs.writeFileSync(abs, updated);

      // Context snippet: show 10 lines around the first edit
      const lines = updated.split("\n");
      const firstEditLine = updated.indexOf(params.edits[0].newText);
      const lineNum = updated.slice(0, firstEditLine).split("\n").length;
      const ctxStart = Math.max(0, lineNum - 3);
      const ctxEnd = Math.min(lines.length, lineNum + 7);
      const snippet = [];
      for (let i = ctxStart; i < ctxEnd; i++) {
        const n = String(i + 1).padStart(6, " ");
        snippet.push(`${n}\u2192${lines[i]}`);
      }
      const text = `The file ${params.path} has been updated. Here's the result of running a context snippet on the edited file:\n\n${snippet.join("\n")}`;
      return {
        content: [{ type: "text", text }],
        details: { editsApplied: params.edits.length },
      };
    },
  });

  // -------- write (override) --------
  pi.registerTool({
    name: "write",
    label: "Write",
    description: "Writes a file to the local filesystem.\n\nUsage:\n- This tool will overwrite the existing file if there is one at the provided path.\n- Prefer the Edit tool for modifying existing files — it only sends the diff. Only use this tool to create new files or for complete rewrites.\n- NEVER create documentation files (*.md) or README files unless explicitly requested by the User.\n- Only use emojis if the user explicitly requests it. Avoid writing emojis to files unless asked.",
    parameters: Type.Object({
      path: Type.String({ description: "File path." }),
      content: Type.String({ description: "File contents." }),
    }),
    async execute(_toolCallId, params, _signal, _onUpdate, ctx) {
      const abs = require("node:path").resolve(ctx.cwd, params.path);
      try {
        // Ensure parent dir exists
        const dir = require("node:path").dirname(abs);
        fs.mkdirSync(dir, { recursive: true });
        fs.writeFileSync(abs, params.content);
        return {
          content: [{ type: "text", text: `File created successfully at: ${params.path}` }],
          details: { bytes: Buffer.byteLength(params.content, "utf-8") },
        };
      } catch (e: any) {
        return { content: [{ type: "text", text: `Error writing ${params.path}: ${e.message}` }], details: { error: e.message } };
      }
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
