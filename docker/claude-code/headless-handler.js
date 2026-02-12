#!/usr/bin/env node
//
// headless-handler.js — Wraps Claude Code in stream-json mode to handle
// interactive tool invocations (AskUserQuestion, EnterPlanMode, Skill)
// automatically in headless benchmark environments.
//
// Instead of --dangerously-skip-permissions (which prevents AskUserQuestion
// from producing control_requests), this handler:
//   1. Receives control_request messages for ALL tool invocations
//   2. Auto-approves everything (like --dangerously-skip-permissions would)
//   3. For AskUserQuestion: picks the first/recommended option
//   4. Collects metrics from the stream
//
// Usage:
//   TASK_PROMPT="..." node /opt/headless-handler.js [extra-claude-args...]
//
// Environment variables:
//   TASK_PROMPT   — The task prompt text (required)
//   OUTPUT_FILE   — Where to write NDJSON output (default: /workspace/.thunderdome-output.jsonl)
//   METRICS_FILE  — Where to write metrics JSON (default: /workspace/.thunderdome-metrics.json)

const { spawn } = require("child_process");
const fs = require("fs");
const readline = require("readline");

const TASK_PROMPT = process.env.TASK_PROMPT;
if (!TASK_PROMPT) {
  console.error("TASK_PROMPT environment variable required");
  process.exit(2);
}

const OUTPUT_FILE =
  process.env.OUTPUT_FILE || "/workspace/.thunderdome-output.jsonl";
const METRICS_FILE =
  process.env.METRICS_FILE || "/workspace/.thunderdome-metrics.json";

// Build Claude args: stream-json mode, no --dangerously-skip-permissions
const claudeArgs = [
  "-p",
  "--input-format",
  "stream-json",
  "--output-format",
  "stream-json",
  "--verbose",
  ...process.argv.slice(2),
];

console.error(`[handler] Starting claude with args: ${claudeArgs.join(" ")}`);

const claude = spawn("claude", claudeArgs, {
  stdio: ["pipe", "pipe", "pipe"],
  env: process.env,
});

// Forward stderr
claude.stderr.on("data", (chunk) => {
  process.stderr.write(chunk);
});

// Open output file for writing
const outputStream = fs.createWriteStream(OUTPUT_FILE);

// Metrics tracking
const metrics = {
  input_tokens: 0,
  output_tokens: 0,
  cache_read_tokens: 0,
  cache_creation_tokens: 0,
  turns: 0,
  tools_used: [],
  duration_ms: 0,
  total_cost_usd: 0,
};
const toolsSeen = new Set();
let controlRequestCount = 0;

// Auto-answer AskUserQuestion: pick first option (or recommended)
function autoAnswerQuestion(input) {
  const answers = {};
  if (input.questions && Array.isArray(input.questions)) {
    for (const q of input.questions) {
      if (q.options && q.options.length > 0) {
        // Look for recommended option first
        let selected = q.options.find(
          (o) => o.label && o.label.toLowerCase().includes("recommended")
        );
        if (!selected) {
          selected = q.options[0];
        }
        answers[q.question] = selected.label;
        console.error(
          `[handler] AskUserQuestion: "${q.question}" -> "${selected.label}"`
        );
      }
    }
  }
  return { ...input, answers };
}

// Handle control requests
function handleControlRequest(msg) {
  const request = msg.request || {};
  const requestId = msg.request_id;

  controlRequestCount++;

  if (request.subtype === "can_use_tool") {
    const toolName = request.tool_name;

    if (toolName === "AskUserQuestion") {
      // Auto-answer questions with first/recommended option
      const updatedInput = autoAnswerQuestion(request.input || {});
      return {
        type: "control_response",
        response: {
          subtype: "success",
          request_id: requestId,
          response: {
            behavior: "allow",
            updatedInput,
          },
        },
      };
    }

    // All other tools: auto-allow (equivalent to --dangerously-skip-permissions)
    return {
      type: "control_response",
      response: {
        subtype: "success",
        request_id: requestId,
        response: {
          behavior: "allow",
        },
      },
    };
  }

  // Unknown control request subtype - allow by default
  return {
    type: "control_response",
    response: {
      subtype: "success",
      request_id: requestId,
      response: {
        behavior: "allow",
      },
    },
  };
}

// Process stdout line by line
const rl = readline.createInterface({
  input: claude.stdout,
  crlfDelay: Infinity,
});

rl.on("line", (line) => {
  // Write to output file
  outputStream.write(line + "\n");

  if (!line.trim()) return;

  let msg;
  try {
    msg = JSON.parse(line);
  } catch (e) {
    return; // Skip malformed lines
  }

  // Handle control requests — respond immediately
  if (msg.type === "control_request") {
    const response = handleControlRequest(msg);
    const responseLine = JSON.stringify(response);
    claude.stdin.write(responseLine + "\n");
    return;
  }

  // Track metrics from result message
  if (msg.type === "result") {
    if (msg.usage) {
      metrics.input_tokens = msg.usage.input_tokens || 0;
      metrics.output_tokens = msg.usage.output_tokens || 0;
      metrics.cache_read_tokens = msg.usage.cache_read_input_tokens || 0;
      metrics.cache_creation_tokens =
        msg.usage.cache_creation_input_tokens || 0;
    }
    metrics.turns = msg.num_turns || 0;
    metrics.duration_ms = msg.duration_ms || 0;
    metrics.total_cost_usd = msg.total_cost_usd || 0;
  }

  // Track tools used from assistant messages
  if (
    msg.type === "assistant" &&
    msg.message &&
    Array.isArray(msg.message.content)
  ) {
    for (const block of msg.message.content) {
      if (
        block.type === "tool_use" &&
        block.name &&
        !toolsSeen.has(block.name)
      ) {
        toolsSeen.add(block.name);
        metrics.tools_used.push(block.name);
      }
    }
  }
});

// Send initial prompt
const initialMessage = {
  type: "user",
  message: {
    role: "user",
    content: TASK_PROMPT,
  },
};

console.error("[handler] Sending initial prompt...");
claude.stdin.write(JSON.stringify(initialMessage) + "\n");

// Handle exit
claude.on("close", (code) => {
  outputStream.end();

  // Write metrics
  try {
    fs.writeFileSync(METRICS_FILE, JSON.stringify(metrics, null, 2));
    console.error("Metrics: " + JSON.stringify(metrics));
    console.error(
      `[handler] Processed ${controlRequestCount} control requests`
    );
  } catch (e) {
    console.error("Metrics extraction failed: " + e.message);
  }

  process.exit(code || 0);
});

// Handle signals
process.on("SIGTERM", () => claude.kill("SIGTERM"));
process.on("SIGINT", () => claude.kill("SIGINT"));
