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
import base64
import json
import re
import sys
import time
import uuid
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.request import Request, urlopen
from urllib.error import HTTPError


# Claude Code validates tool_use IDs against ^toolu_[A-Za-z0-9_]+$ and silently
# drops tool calls whose IDs don't match. Some upstream models (e.g. Kimi K2)
# emit IDs like "Read:0" or "functions.TodoWrite:0" that fail the check, which
# stalls the agentic loop. We rewrite IDs on the response side and decode them
# back on the request side. Encoding is base32 so the result fits the regex.
def _encode_tool_id(orig):
    if not orig:
        return f"toolu_{uuid.uuid4().hex[:24]}"
    if re.fullmatch(r"toolu_[A-Za-z0-9_]+", orig):
        return orig
    enc = base64.b32encode(orig.encode("utf-8")).decode("ascii").rstrip("=").lower()
    return f"toolu_orig_{enc}"


def _decode_tool_id(anth_id):
    if not isinstance(anth_id, str) or not anth_id.startswith("toolu_orig_"):
        return anth_id
    enc = anth_id[len("toolu_orig_"):].upper()
    pad = "=" * (-len(enc) % 8)
    try:
        return base64.b32decode(enc + pad).decode("utf-8")
    except Exception:
        return anth_id

UPSTREAM = None
API_KEY = None
DEFAULT_MODEL = None
PROVIDER_PREF = None  # OpenRouter provider routing preference (dict) injected into each request
NO_THINK = False  # if set, inject enable_thinking=false (disable hybrid-model reasoning)
MIN_MAX_TOKENS = 0  # floor on max_tokens (thinking models need a minimum budget)
LOG_PATH = None
TRACE_PATH = None


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
        # Captured `thinking` blocks (from prior turns of reasoning models).
        # OpenRouter / OpenAI-compatible thinking-model APIs preserve chain-of-thought
        # across turns when the assistant message includes `reasoning_details`. Without
        # this, thinking models lose their thread mid-conversation and end_turn early
        # (observed with Kimi K2.6 -- gave up after one tool call).
        reasoning_details = []

        for block in content or []:
            btype = block.get("type")
            if btype == "text":
                text_parts.append(block.get("text", ""))
            elif btype == "thinking":
                # Anthropic-format thinking block from a prior assistant turn.
                # Translate back to OpenRouter's reasoning_details so the model
                # sees its own prior chain-of-thought.
                reasoning_details.append({
                    "type": "reasoning.text",
                    "text": block.get("thinking", ""),
                })
            elif btype == "tool_use":
                tool_calls.append({
                    "id": _decode_tool_id(block.get("id")),
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
                    "tool_call_id": _decode_tool_id(block.get("tool_use_id")),
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
            if reasoning_details:
                m["reasoning_details"] = reasoning_details
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

    # Anthropic clients send `thinking: {type: enabled, budget_tokens: N}` to
    # request extended thinking; OpenRouter accepts the same shape.
    if "thinking" in body:
        out["reasoning"] = {"enabled": True}
        bt = body["thinking"].get("budget_tokens") if isinstance(body["thinking"], dict) else None
        if bt:
            out["reasoning"]["max_tokens"] = bt

    # OpenRouter provider routing preferences (e.g. {"sort":"throughput"} or a
    # pinned {"order":[...]}). Default OpenRouter routing for z-ai/glm-5.2
    # intermittently lands on a provider that takes ~5 min to prefill a 24K-token
    # agentic turn, which times out the task; the fast providers serve the same
    # request in 5-18s. Passing a preference keeps turns inside the time limit.
    if PROVIDER_PREF is not None:
        out["provider"] = PROVIDER_PREF

    # Force-disable thinking for hybrid reasoning models (Qwen3.x/Qwopus on
    # local llama.cpp). Inject both the top-level and nested
    # chat_template_kwargs toggles -- llama.cpp honors the nested form. Without
    # this the model reasons for minutes per turn (non-streamed) and times out
    # short-time-limit tasks before writing code.
    if NO_THINK:
        out["enable_thinking"] = False
        ctk = out.get("chat_template_kwargs")
        if not isinstance(ctk, dict):
            ctk = {}
        ctk["enable_thinking"] = False
        out["chat_template_kwargs"] = ctk

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

    # Note: reasoning content from OpenRouter (reasoning_details / reasoning)
    # is intentionally dropped here. Tried surfacing it as Anthropic `thinking`
    # blocks but Claude Code 2.1.119 hangs when it sees thinking blocks without
    # the cryptographic signature Anthropic's real API supplies. The chain-of-
    # thought is therefore not preserved across turns for thinking models routed
    # through this proxy. If the upstream supports it, set the request body's
    # reasoning.encrypted=true and we could pass an opaque blob through the
    # `signature` slot, but OpenRouter doesn't currently expose that.

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
            "id": _encode_tool_id(tc.get("id")),
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
        elif block["type"] == "thinking":
            send("content_block_start", {
                "type": "content_block_start",
                "index": idx,
                "content_block": {"type": "thinking", "thinking": ""},
            })
            text = block.get("thinking", "")
            for i in range(0, max(len(text), 1), 120):
                send("content_block_delta", {
                    "type": "content_block_delta",
                    "index": idx,
                    "delta": {"type": "thinking_delta", "thinking": text[i:i + 120]},
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

        # Trace dump: capture full request + response shape for debugging
        # (only when --trace flag set; off by default to keep logs small).
        if TRACE_PATH:
            try:
                with open(TRACE_PATH, "a") as tf:
                    tf.write(json.dumps({
                        "ts": time.time(),
                        "anth_request_summary": {
                            "msg_count": len(req.get("messages", [])),
                            "msg_role_blocks": [
                                (m.get("role"), [b.get("type") if isinstance(b, dict) else type(b).__name__
                                                 for b in (m.get("content") if isinstance(m.get("content"), list) else [])])
                                for m in req.get("messages", [])
                            ],
                        },
                        "openai_request_summary": {
                            "msg_count": len(openai_req.get("messages", [])),
                            "msg_roles": [m.get("role") for m in openai_req.get("messages", [])],
                            "tool_count": len(openai_req.get("tools", []) or []),
                        },
                        "openai_response": openai_resp,
                        "anth_response": anth_resp,
                    }) + "\n")
            except Exception:
                pass

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
    global UPSTREAM, API_KEY, DEFAULT_MODEL, PROVIDER_PREF, NO_THINK, MIN_MAX_TOKENS, LOG_PATH, TRACE_PATH
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
    p.add_argument("--trace", default=None,
                   help="Append full request+response trace dumps (debugging).")
    p.add_argument("--no-think", action="store_true", default=False,
                   help="Inject enable_thinking=false (disable hybrid reasoning models' thinking).")
    p.add_argument("--provider", default=None,
                   help='OpenRouter provider routing JSON injected into each request, '
                        'e.g. \'{"sort":"throughput"}\' or \'{"order":["Z.AI","Novita"]}\'. '
                        'Avoids slow providers that time out large agentic turns.')
    args = p.parse_args()

    UPSTREAM = args.upstream
    API_KEY = args.api_key
    DEFAULT_MODEL = args.model
    MIN_MAX_TOKENS = args.min_max_tokens
    LOG_PATH = args.log
    TRACE_PATH = args.trace
    NO_THINK = args.no_think
    if args.provider:
        PROVIDER_PREF = json.loads(args.provider)

    print(f"anth2openai-proxy listening on http://{args.host}:{args.port}", flush=True)
    print(f"  upstream: {UPSTREAM}", flush=True)
    if DEFAULT_MODEL:
        print(f"  forcing model: {DEFAULT_MODEL}", flush=True)
    if PROVIDER_PREF:
        print(f"  provider routing: {PROVIDER_PREF}", flush=True)

    ThreadingHTTPServer((args.host, args.port), Handler).serve_forever()


if __name__ == "__main__":
    main()
