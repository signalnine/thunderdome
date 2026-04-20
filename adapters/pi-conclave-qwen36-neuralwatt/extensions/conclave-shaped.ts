/**
 * Conclave-shaped pi extension.
 *
 * Adds Claude-Code-style tools (Grep, Glob, TodoWrite) and injects the
 * Conclave v8 system prompt. Tests whether giving pi Claude Code's tool
 * surface + disciplined prompt closes the harness gap on Qwen3.6.
 */

import * as fs from "node:fs";
import * as path from "node:path";
import { spawnSync } from "node:child_process";
import type { ExtensionAPI } from "@mariozechner/pi-coding-agent";
import { Type } from "@sinclair/typebox";

// -- Conclave v8 system prompt (same as adapters/conclave-v8-combined-sonnet) --
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
After all contract criteria pass, review your own diff as if you were a hostile code reviewer. Read every line. Check for missing edge cases, off-by-one errors, unhandled errors, race conditions, dead code, debug artifacts, TODOs left behind. If you find issues, fix them and re-verify against the contract.

Done means: all contract criteria pass, tests pass, build clean, lint clean, self-review clean.

## Tools Available

Beyond read/bash/edit/write, you have:

- **Grep**: Regex search across files (uses ripgrep). Use this to find symbols, patterns, or text across the codebase instead of cat'ing files.
- **Glob**: Fast file pattern matching (e.g., "src/**/*.ts"). Use this instead of 'find' shell calls to locate files.
- **TodoWrite**: Track your plan as a structured todo list. Use this at the start of each task and update as you work. Externalizes your state so you can reason about progress without re-deriving context each turn.
`;

// -- Todo state (in-memory across a session) --
interface TodoItem {
	content: string;
	status: "pending" | "in_progress" | "completed";
	activeForm: string;
}

export default function conclaveShapedExtension(pi: ExtensionAPI) {
	let todos: TodoItem[] = [];

	// -------- TodoWrite --------
	pi.registerTool({
		name: "TodoWrite",
		label: "TodoWrite",
		description:
			"Create and manage a structured task list for the current session. Use this proactively to track progress on multi-step tasks.",
		promptSnippet:
			"Use TodoWrite to plan and track multi-step work. Mark todos in_progress when you start and completed when done.",
		parameters: Type.Object({
			todos: Type.Array(
				Type.Object({
					content: Type.String({ description: "The task description (imperative form, e.g. 'Fix auth bug')." }),
					status: Type.Union([Type.Literal("pending"), Type.Literal("in_progress"), Type.Literal("completed")]),
					activeForm: Type.String({ description: "Present-continuous form shown while task is in_progress (e.g. 'Fixing auth bug')." }),
				}),
			),
		}),
		async execute(_toolCallId, params) {
			todos = params.todos as TodoItem[];
			const rendered = todos
				.map((t, i) => {
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

	// -------- Grep (ripgrep wrapper) --------
	pi.registerTool({
		name: "Grep",
		label: "Grep",
		description:
			"Fast regex search across files using ripgrep. Returns file paths and matching lines. Use this to find symbols, patterns, or text across the codebase.",
		promptSnippet: "Use Grep to search file contents with regex.",
		parameters: Type.Object({
			pattern: Type.String({ description: "Regular expression pattern (ripgrep syntax)." }),
			path: Type.Optional(Type.String({ description: "File or directory to search (defaults to cwd)." })),
			glob: Type.Optional(Type.String({ description: "Glob pattern to filter files, e.g. '*.ts'." })),
			output_mode: Type.Optional(
				Type.Union([Type.Literal("content"), Type.Literal("files_with_matches")], {
					description: "content shows matching lines; files_with_matches shows file paths only.",
				}),
			),
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

	// -------- Glob (file pattern matching) --------
	pi.registerTool({
		name: "Glob",
		label: "Glob",
		description:
			"Fast file-path pattern matching. Returns matching file paths sorted by modification time. Use this instead of shelling out to find.",
		promptSnippet: "Use Glob to find files by path pattern (e.g. 'src/**/*.ts').",
		parameters: Type.Object({
			pattern: Type.String({ description: "Glob pattern, e.g. '**/*.ts' or 'src/components/**/*.tsx'." }),
			path: Type.Optional(Type.String({ description: "Root directory (defaults to cwd)." })),
		}),
		async execute(_toolCallId, params) {
			// Use bash + find since minimatch isn't necessarily available; rg --files is cleaner.
			const root = params.path ?? ".";
			// Use rg --files as a fast file enumerator and pipe through grep for the pattern.
			// For simplicity we let ripgrep handle the glob natively.
			const rg = spawnSync("rg", ["--files", "--glob", params.pattern, root], {
				encoding: "utf-8",
				maxBuffer: 10 * 1024 * 1024,
			});
			const files = (rg.stdout || "").split("\n").filter(Boolean);
			// Sort by mtime desc
			const withMtime = files
				.map((f) => {
					try {
						return { f, m: fs.statSync(f).mtimeMs };
					} catch {
						return null;
					}
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

	// -------- System prompt injection --------
	pi.on("before_agent_start", async (event) => {
		return {
			systemPrompt: event.systemPrompt + V8_PROMPT,
		};
	});
}
