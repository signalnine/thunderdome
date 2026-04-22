#!/usr/bin/env python3
"""Anthropic -> OpenAI proxy.

Serves an Anthropic-compatible /v1/messages endpoint, translates the
request to OpenAI chat.completions shape, forwards to an upstream,
and translates the response back to Anthropic.

Streaming is synthetic: we always call upstream non-streaming; when
the client requests stream:true, we emit Anthropic SSE events from
the buffered reply. Avoids real-time chunk translation (which is
where Anthropic<->OpenAI tool-call streaming gets flaky).

Usage:
  anth2openai-proxy.py --port 18900 \\
    --upstream https://api.neuralwatt.com/v1 \\
    --api-key $KEY \\
    --model Qwen/Qwen3.6-35B-A3B
"""

import argparse
import json
import sys
import time
import uuid
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.request import Request, urlopen
from urllib.error import HTTPError

UPSTREAM = None
API_KEY = None
DEFAULT_MODEL = None
MIN_MAX_TOKENS = 0  # floor on max_tokens (thinking models need a minimum budget)
LOG_PATH = None


def translate_request(body):
    """Anthropic Messages request -> OpenAI chat.completions request."""
    out = {"model": DEFAULT_MODEL or body.get("model", "")}

    messages = []
    system = body.get("system")
    if system:
        if isinstance(system, list):
            text = "".join(b.get("text", "") for b in system if b.get("type") == "text")
        else:
            text = system
        if text:
            messages.append({"role": "system", "content": text})

    for msg in body.get("messages", []):
        role = msg.get("role")
        content = msg.get("content")

        if isinstance(content, str):
            messages.append({"role": role, "content": content})
            continue

        text_parts = []
        tool_calls = []
        tool_results = []

        for block in content or []:
            btype = block.get("type")
            if btype == "text":
                text_parts.append(block.get("text", ""))
            elif btype == "tool_use":
                tool_calls.append({
                    "id": block.get("id"),
                    "type": "function",
                    "function": {
                        "name": block.get("name"),
                        "arguments": json.dumps(block.get("input", {})),
                    },
                })
            elif btype == "tool_result":
                rc = block.get("content")
                if isinstance(rc, list):
                    rc_text = "".join(
                        b.get("text", "") for b in rc if b.get("type") == "text"
                    )
                else:
                    rc_text = rc or ""
                tool_results.append({
                    "role": "tool",
                    "tool_call_id": block.get("tool_use_id"),
                    "content": rc_text,
                })

        if role == "user":
            # Tool results precede the user text (and each is its own message).
            messages.extend(tool_results)
            text = "".join(text_parts).strip()
            if text:
                messages.append({"role": "user", "content": text})
        elif role == "assistant":
            m = {"role": "assistant"}
            text = "".join(text_parts)
            m["content"] = text if text else None
            if tool_calls:
                m["tool_calls"] = tool_calls
            messages.append(m)

    out["messages"] = messages

    if "max_tokens" in body:
        mt = body["max_tokens"]
        if MIN_MAX_TOKENS and mt < MIN_MAX_TOKENS:
            mt = MIN_MAX_TOKENS
        out["max_tokens"] = mt
    if "temperature" in body:
        out["temperature"] = body["temperature"]
    if "top_p" in body:
        out["top_p"] = body["top_p"]
    if "stop_sequences" in body:
        out["stop"] = body["stop_sequences"]

    if "tools" in body:
        out["tools"] = [
            {
                "type": "function",
                "function": {
                    "name": t.get("name"),
                    "description": t.get("description", ""),
                    "parameters": t.get("input_schema", {"type": "object"}),
                },
            }
            for t in body["tools"]
        ]

    tc = body.get("tool_choice")
    if tc:
        ttype = tc.get("type")
        if ttype == "auto":
            out["tool_choice"] = "auto"
        elif ttype == "any":
            out["tool_choice"] = "required"
        elif ttype == "none":
            out["tool_choice"] = "none"
        elif ttype == "tool":
            out["tool_choice"] = {
                "type": "function",
                "function": {"name": tc.get("name")},
            }

    out["stream"] = False  # always buffer upstream
    return out


FINISH_MAP = {
    "stop": "end_turn",
    "length": "max_tokens",
    "tool_calls": "tool_use",
    "function_call": "tool_use",
    "content_filter": "end_turn",
}


def translate_response(openai_resp, requested_model):
    """OpenAI response -> Anthropic response (non-streaming shape)."""
    choice = (openai_resp.get("choices") or [{}])[0]
    message = choice.get("message", {}) or {}
    finish = choice.get("finish_reason", "stop")
    usage = openai_resp.get("usage", {}) or {}

    content_blocks = []

    text = message.get("content")
    if text:
        content_blocks.append({"type": "text", "text": text})

    for tc in message.get("tool_calls") or []:
        fn = tc.get("function", {}) or {}
        try:
            args = json.loads(fn.get("arguments", "{}") or "{}")
        except json.JSONDecodeError:
            args = {"_raw_arguments": fn.get("arguments", "")}
        content_blocks.append({
            "type": "tool_use",
            "id": tc.get("id") or f"toolu_{uuid.uuid4().hex[:24]}",
            "name": fn.get("name", ""),
            "input": args,
        })

    if not content_blocks:
        content_blocks.append({"type": "text", "text": ""})

    return {
        "id": openai_resp.get("id") or f"msg_{uuid.uuid4().hex[:24]}",
        "type": "message",
        "role": "assistant",
        "model": requested_model,
        "content": content_blocks,
        "stop_reason": FINISH_MAP.get(finish, "end_turn"),
        "stop_sequence": None,
        "usage": {
            "input_tokens": usage.get("prompt_tokens", 0),
            "output_tokens": usage.get("completion_tokens", 0),
            "cache_read_input_tokens": 0,
            "cache_creation_input_tokens": 0,
        },
    }


def emit_sse(wfile, anth_resp):
    """Write Anthropic SSE events from a buffered Anthropic response."""
    def send(event, data):
        wfile.write(f"event: {event}\n".encode())
        wfile.write(b"data: " + json.dumps(data).encode() + b"\n\n")
        wfile.flush()

    send("message_start", {
        "type": "message_start",
        "message": {
            "id": anth_resp["id"],
            "type": "message",
            "role": "assistant",
            "model": anth_resp["model"],
            "content": [],
            "stop_reason": None,
            "stop_sequence": None,
            "usage": {
                "input_tokens": anth_resp["usage"]["input_tokens"],
                "output_tokens": 0,
                "cache_read_input_tokens": 0,
                "cache_creation_input_tokens": 0,
            },
        },
    })

    for idx, block in enumerate(anth_resp["content"]):
        if block["type"] == "text":
            send("content_block_start", {
                "type": "content_block_start",
                "index": idx,
                "content_block": {"type": "text", "text": ""},
            })
            text = block["text"]
            for i in range(0, max(len(text), 1), 120):
                chunk = text[i:i + 120]
                send("content_block_delta", {
                    "type": "content_block_delta",
                    "index": idx,
                    "delta": {"type": "text_delta", "text": chunk},
                })
            send("content_block_stop", {
                "type": "content_block_stop",
                "index": idx,
            })
        elif block["type"] == "tool_use":
            send("content_block_start", {
                "type": "content_block_start",
                "index": idx,
                "content_block": {
                    "type": "tool_use",
                    "id": block["id"],
                    "name": block["name"],
                    "input": {},
                },
            })
            partial = json.dumps(block["input"])
            send("content_block_delta", {
                "type": "content_block_delta",
                "index": idx,
                "delta": {"type": "input_json_delta", "partial_json": partial},
            })
            send("content_block_stop", {
                "type": "content_block_stop",
                "index": idx,
            })

    send("message_delta", {
        "type": "message_delta",
        "delta": {
            "stop_reason": anth_resp["stop_reason"],
            "stop_sequence": None,
        },
        "usage": {"output_tokens": anth_resp["usage"]["output_tokens"]},
    })
    send("message_stop", {"type": "message_stop"})


class Handler(BaseHTTPRequestHandler):
    def log_message(self, fmt, *args):
        sys.stderr.write(f"[{time.strftime('%H:%M:%S')}] {fmt % args}\n")

    def do_GET(self):
        if self.path in ("/health", "/health/liveliness", "/v1/health"):
            self._json(200, {"status": "ok"})
            return
        self.send_error(404)

    def do_POST(self):
        if "/v1/messages" not in self.path:
            self.send_error(404)
            return
        try:
            length = int(self.headers.get("Content-Length", "0"))
            raw = self.rfile.read(length)
            req = json.loads(raw)
        except Exception as e:
            self._anth_err(400, "invalid_request_error", f"bad JSON: {e}")
            return

        stream = bool(req.get("stream"))
        requested_model = req.get("model", "unknown")

        try:
            openai_req = translate_request(req)
        except Exception as e:
            self._anth_err(500, "api_error", f"request translation failed: {e}")
            return

        try:
            upstream_req = Request(
                UPSTREAM.rstrip("/") + "/chat/completions",
                data=json.dumps(openai_req).encode(),
                headers={
                    "Content-Type": "application/json",
                    "Authorization": f"Bearer {API_KEY}",
                    "User-Agent": "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36",
                },
                method="POST",
            )
            with urlopen(upstream_req, timeout=600) as resp:
                upstream_body = resp.read()
            openai_resp = json.loads(upstream_body)
        except HTTPError as e:
            try:
                detail = e.read().decode()
            except Exception:
                detail = str(e)
            self._anth_err(e.code, "api_error", f"upstream {e.code}: {detail[:500]}")
            return
        except Exception as e:
            self._anth_err(502, "api_error", f"upstream request failed: {e}")
            return

        try:
            anth_resp = translate_response(openai_resp, requested_model)
        except Exception as e:
            self._anth_err(500, "api_error", f"response translation failed: {e}")
            return

        if LOG_PATH:
            try:
                u = anth_resp["usage"]
                line = json.dumps({
                    "ts": time.time(),
                    "input_tokens": u.get("input_tokens", 0),
                    "output_tokens": u.get("output_tokens", 0),
                    "cache_read_input_tokens": u.get("cache_read_input_tokens", 0),
                    "cache_creation_input_tokens": u.get("cache_creation_input_tokens", 0),
                    "stop_reason": anth_resp.get("stop_reason"),
                })
                with open(LOG_PATH, "a") as f:
                    f.write(line + "\n")
            except Exception:
                pass

        if stream:
            self.send_response(200)
            self.send_header("Content-Type", "text/event-stream")
            self.send_header("Cache-Control", "no-cache")
            self.send_header("Connection", "keep-alive")
            self.end_headers()
            try:
                emit_sse(self.wfile, anth_resp)
            except (BrokenPipeError, ConnectionResetError):
                pass
        else:
            self._json(200, anth_resp)

    def _json(self, code, obj):
        body = json.dumps(obj).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _anth_err(self, code, err_type, msg):
        sys.stderr.write(f"[err {code}] {msg}\n")
        self._json(code, {"type": "error", "error": {"type": err_type, "message": msg}})


def main():
    global UPSTREAM, API_KEY, DEFAULT_MODEL, MIN_MAX_TOKENS, LOG_PATH
    p = argparse.ArgumentParser()
    p.add_argument("--port", type=int, default=18900)
    p.add_argument("--host", default="127.0.0.1")
    p.add_argument("--upstream", required=True,
                   help="OpenAI-compatible base URL including /v1 (e.g. https://api.neuralwatt.com/v1)")
    p.add_argument("--api-key", required=True)
    p.add_argument("--model", default=None,
                   help="Force every request to this upstream model, ignoring the Anthropic model name.")
    p.add_argument("--min-max-tokens", type=int, default=0,
                   help="Floor on max_tokens. Thinking models (Qwen3.x) burn tokens on reasoning and return empty content if the budget is too small. 2048 is a reasonable floor.")
    p.add_argument("--log", default=None,
                   help="Append one jsonl line per request with usage counters (for thunderdome metrics).")
    args = p.parse_args()

    UPSTREAM = args.upstream
    API_KEY = args.api_key
    DEFAULT_MODEL = args.model
    MIN_MAX_TOKENS = args.min_max_tokens
    LOG_PATH = args.log

    print(f"anth2openai-proxy listening on http://{args.host}:{args.port}", flush=True)
    print(f"  upstream: {UPSTREAM}", flush=True)
    if DEFAULT_MODEL:
        print(f"  forcing model: {DEFAULT_MODEL}", flush=True)

    ThreadingHTTPServer((args.host, args.port), Handler).serve_forever()


if __name__ == "__main__":
    main()
