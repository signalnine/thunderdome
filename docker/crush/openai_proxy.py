#!/usr/bin/env python3
"""OpenAI-compatible API proxy that logs token usage to JSONL.

Usage: python3 openai_proxy.py --port PORT --log LOG_PATH --upstream URL
Forwards all requests to the upstream URL, streams responses back in real-time,
and appends a usage record to LOG_PATH for each /chat/completions call.
Handles both regular and streaming (SSE) responses.
"""

import argparse
import gzip
import json
import sys
import time
from http.server import HTTPServer, BaseHTTPRequestHandler
from urllib.request import Request, urlopen
from urllib.error import HTTPError

upstream_url = None
log_path = None
model_rewrites = {}  # local_name -> upstream_name
max_tokens_clamp = 0  # 0 = no clamping
auth_override = None  # if set, replace Authorization header with this key
no_think = False  # if set, inject enable_thinking=false into chat requests
reasoning_effort_override = None  # if set, inject reasoning_effort into chat requests
exclude_reasoning = False  # if set, inject reasoning.exclude=true (OpenRouter)
force_greedy = False  # if set, force temperature=0 (greedy) on chat requests


class ProxyHandler(BaseHTTPRequestHandler):
    def do_POST(self):
        length = int(self.headers.get("Content-Length", 0))
        body = self.rfile.read(length) if length else b""

        is_chat = "chat/completions" in self.path
        is_streaming = False

        # Parse and potentially modify the request body
        if body:
            try:
                data = json.loads(body)
                # Rewrite model name if configured. Also support a wildcard
                # entry under key "*" so the proxy can force a model regardless
                # of what the client sends.
                model = data.get("model", "")
                if model in model_rewrites:
                    data["model"] = model_rewrites[model]
                elif "*" in model_rewrites:
                    data["model"] = model_rewrites["*"]
                if data.get("model") != model:
                    print(f"  Model: {model} -> {data.get('model')}", flush=True)
                # Clamp max_tokens if configured
                if max_tokens_clamp and "max_tokens" in data:
                    if data["max_tokens"] > max_tokens_clamp:
                        data["max_tokens"] = max_tokens_clamp
                # Disable or limit thinking if configured. Different vLLM
                # reasoning setups read the toggle from different places:
                # top-level `enable_thinking` (some Qwen builds) vs nested
                # `chat_template_kwargs.enable_thinking` (GLM-5.2 on Neuralwatt
                # -- top-level is silently ignored there). Inject both so a
                # single --no-think reliably suppresses the `reasoning` deltas
                # that otherwise flood CRUSH's stream with empty deltas.
                if no_think and is_chat:
                    data["enable_thinking"] = False
                    ctk = data.get("chat_template_kwargs")
                    if not isinstance(ctk, dict):
                        ctk = {}
                    ctk["enable_thinking"] = False
                    data["chat_template_kwargs"] = ctk
                if force_greedy and is_chat:
                    data["temperature"] = 0
                    data.pop("top_p", None)
                    data.pop("top_k", None)
                if reasoning_effort_override and is_chat:
                    data["reasoning_effort"] = reasoning_effort_override
                # Exclude reasoning chunks (OpenRouter-specific). Thinking
                # models like Kimi K2.6 stream `delta.reasoning` chunks that
                # OpenAI-compatible clients (crush) can't parse, causing
                # "unexpected end of JSON input". exclude=true makes the
                # upstream behave as a regular non-thinking model.
                if exclude_reasoning and is_chat:
                    r = data.get("reasoning") or {}
                    if isinstance(r, dict):
                        # exclude=true hides reasoning chunks from the stream
                        # but the model still spends time thinking, which
                        # delays time-to-first-token past crush's tolerance.
                        # enabled=false disables reasoning entirely on
                        # OpenRouter for models that support that switch.
                        r["exclude"] = True
                        r["enabled"] = False
                        data["reasoning"] = r
                # Some clients (e.g. pi-coding-agent) use OpenAI's newer
                # `"role": "developer"` for system instructions. Older
                # OpenAI-compatible servers (vLLM) return 400 on that; rewrite
                # to the legacy `"role": "system"`.
                if is_chat and isinstance(data.get("messages"), list):
                    for msg in data["messages"]:
                        if isinstance(msg, dict) and msg.get("role") == "developer":
                            msg["role"] = "system"
                # Check if streaming
                is_streaming = data.get("stream", False)
                # Inject stream_options.include_usage for streaming chat requests
                if is_chat and is_streaming:
                    opts = data.get("stream_options", {})
                    opts["include_usage"] = True
                    data["stream_options"] = opts
                body = json.dumps(data).encode()
            except (json.JSONDecodeError, UnicodeDecodeError):
                pass

        # Build upstream request
        url = upstream_url + self.path
        req = Request(url, data=body, method="POST")
        saw_user_agent = False
        saw_auth = False
        for key, val in self.headers.items():
            if key.lower() in ("host", "content-length", "transfer-encoding"):
                continue
            if key.lower() == "authorization":
                if auth_override:
                    req.add_header("Authorization", f"Bearer {auth_override}")
                else:
                    req.add_header("Authorization", val)
                saw_auth = True
                continue
            if key.lower() == "user-agent":
                # Override client UA with a browser UA so Cloudflare WAF (e.g. Neuralwatt)
                # doesn't block Go-http-client / python-urllib as a suspected bot.
                req.add_header("User-Agent", "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36")
                saw_user_agent = True
                continue
            req.add_header(key, val)
        if not saw_user_agent:
            req.add_header("User-Agent", "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36")
        if not saw_auth and auth_override:
            # Client didn't send auth but we have an override key; inject it.
            req.add_header("Authorization", f"Bearer {auth_override}")
        req.add_header("Content-Length", str(len(body)))

        try:
            resp = urlopen(req, timeout=600)
        except HTTPError as e:
            resp_body = e.read()
            self.send_response(e.code)
            for key, val in e.headers.items():
                if key.lower() in ("transfer-encoding", "content-length", "connection"):
                    continue
                self.send_header(key, val)
            self.send_header("Content-Length", str(len(resp_body)))
            self.end_headers()
            self.wfile.write(resp_body)
            return
        except Exception as e:
            print(f"PROXY ERROR: {e}", file=sys.stderr, flush=True)
            self.send_response(500)
            self.send_header("Content-Type", "application/json")
            err_body = json.dumps({"error": str(e)}).encode()
            self.send_header("Content-Length", str(len(err_body)))
            self.end_headers()
            self.wfile.write(err_body)
            return

        content_type = resp.headers.get("Content-Type", "")
        is_sse = "text/event-stream" in content_type

        if is_sse or is_streaming:
            # Stream SSE response back line by line
            self.send_response(resp.status)
            self.send_header("Content-Type", "text/event-stream; charset=utf-8")
            self.send_header("Cache-Control", "no-cache")
            self.send_header("Connection", "close")
            self.end_headers()

            input_tokens = 0
            output_tokens = 0
            resp_model = "unknown"
            pending_data = False  # a data: line was forwarded but not yet terminated by a blank

            try:
                for raw_line in resp:
                    line = raw_line.decode('utf-8', errors='ignore').strip()
                    rewritten = raw_line

                    # Drop non-standard SSE comment lines AND the blank lines they
                    # leave behind. Two sources emit comments: Neuralwatt telemetry
                    # (`: energy {...}` / `: cost {...}`) and OpenRouter keepalives
                    # (`: OPENROUTER PROCESSING`, streamed while a reasoning model
                    # like Laguna-XS-2.1 thinks -- BEFORE any data line). Comments
                    # are valid SSE that compliant clients ignore, but each is
                    # followed by its own blank line; CRUSH's reader dispatches an
                    # SSE event on every blank, and an empty event becomes
                    # json.Unmarshal("") -> "unexpected end of JSON input", aborting
                    # the whole stream. A blank is only meaningful when it TERMINATES
                    # a data event we forwarded -- so drop the comment, and only
                    # forward a blank when there is a pending data line to close.
                    if line.startswith(':'):
                        continue
                    if line == '':
                        if not pending_data:
                            continue
                        pending_data = False
                        self.wfile.write(rewritten)
                        self.wfile.flush()
                        continue

                    # Some vLLM servers (e.g. Neuralwatt Qwen3.6) emit chain-of-thought
                    # in a nonstandard `reasoning` delta field. Strip it -- clients like
                    # CRUSH treat unexpected fields as malformed and abort with
                    # "unexpected end of JSON input".
                    if line.startswith('data:'):
                        data_str = line[5:].strip()
                        if data_str and data_str != '[DONE]':
                            try:
                                chunk = json.loads(data_str)
                                resp_model = chunk.get('model', resp_model)
                                if 'usage' in chunk and chunk['usage']:
                                    u = chunk['usage']
                                    input_tokens = u.get('prompt_tokens', 0) or u.get('input_tokens', 0)
                                    output_tokens = u.get('completion_tokens', 0) or u.get('output_tokens', 0)
                                # Strip `reasoning`/`reasoning_details` from each
                                # choice's delta/message. OpenRouter reasoning models
                                # (e.g. Nemotron 3) emit a `reasoning_details` array, and llama.cpp
                                # with --reasoning-format deepseek emits `reasoning_content`;
                                # alongside `reasoning`; clients like CRUSH abort with
                                # "unexpected end of JSON input" on either field.
                                modified = False
                                for ch in chunk.get('choices', []) or []:
                                    for k in ('delta', 'message'):
                                        if k in ch and isinstance(ch[k], dict):
                                            for rk in ('reasoning', 'reasoning_details', 'reasoning_content'):
                                                if rk in ch[k]:
                                                    del ch[k][rk]
                                                    modified = True
                                if modified:
                                    # Preserve original SSE framing: the upstream
                                    # data line is `\n`-terminated and the
                                    # event-separating blank line arrives as its
                                    # own iteration. Re-emit a single `\n` here --
                                    # appending `\n\n` injected a spurious empty
                                    # event after every stripped chunk, which
                                    # strict clients (CRUSH on GLM-5.2) decode as
                                    # `json.Unmarshal("")` -> "unexpected end of
                                    # JSON input" and abort the whole stream.
                                    rewritten = ('data: ' + json.dumps(chunk) + '\n').encode('utf-8')
                            except (json.JSONDecodeError, KeyError):
                                pass

                    # Forward (possibly rewritten) data line; a blank must follow
                    # to terminate the event before the client will dispatch it.
                    self.wfile.write(rewritten)
                    self.wfile.flush()
                    pending_data = True
            except (BrokenPipeError, ConnectionResetError) as e:
                print(f"STREAM CLOSED: {e}", file=sys.stderr, flush=True)

            # Log usage
            if is_chat:
                record = {
                    "timestamp": time.time(),
                    "model": resp_model,
                    "provider": "openai-compat",
                    "input_tokens": input_tokens,
                    "output_tokens": output_tokens,
                    "cache_creation_input_tokens": 0,
                    "cache_read_input_tokens": 0,
                    "status": resp.status,
                }
                with open(log_path, "a") as f:
                    f.write(json.dumps(record) + "\n")
                print(f"LOGGED (streaming): in={input_tokens} out={output_tokens} model={resp_model}",
                      file=sys.stderr, flush=True)
        else:
            # Non-streaming: buffer, strip nonstandard `reasoning` field, forward.
            resp_body = resp.read()
            gzipped = resp_body[:2] == b'\x1f\x8b'
            try:
                decoded_bytes = gzip.decompress(resp_body) if gzipped else resp_body
                data = json.loads(decoded_bytes)
                modified = False
                for ch in data.get('choices', []) or []:
                    for k in ('delta', 'message'):
                        if k in ch and isinstance(ch[k], dict):
                            for rk in ('reasoning', 'reasoning_details', 'reasoning_content'):
                                if rk in ch[k]:
                                    del ch[k][rk]
                                    modified = True
                if modified:
                    new_body = json.dumps(data).encode('utf-8')
                    resp_body = gzip.compress(new_body) if gzipped else new_body
            except (json.JSONDecodeError, UnicodeDecodeError, OSError):
                pass

            self.send_response(resp.status)
            for key, val in resp.headers.items():
                if key.lower() in ("transfer-encoding", "content-length", "connection"):
                    continue
                self.send_header(key, val)
            self.send_header("Content-Length", str(len(resp_body)))
            self.end_headers()
            self.wfile.write(resp_body)

            # Log usage
            if is_chat:
                try:
                    decoded = resp_body
                    if resp_body[:2] == b'\x1f\x8b':
                        decoded = gzip.decompress(resp_body)
                    data = json.loads(decoded)
                    usage = data.get("usage", {})
                    resp_model = data.get("model", "unknown")
                    record = {
                        "timestamp": time.time(),
                        "model": resp_model,
                        "provider": "openai-compat",
                        "input_tokens": usage.get("prompt_tokens", 0),
                        "output_tokens": usage.get("completion_tokens", 0),
                        "cache_creation_input_tokens": 0,
                        "cache_read_input_tokens": 0,
                        "status": resp.status,
                    }
                    with open(log_path, "a") as f:
                        f.write(json.dumps(record) + "\n")
                    print(f"LOGGED: in={record['input_tokens']} out={record['output_tokens']} model={resp_model}",
                          file=sys.stderr, flush=True)
                except Exception as e:
                    print(f"PARSE ERROR: {e}", file=sys.stderr, flush=True)

    def do_GET(self):
        if self.path == "/health":
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            body = b'{"status":"ok"}'
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
            return
        self.send_response(404)
        self.end_headers()

    def log_message(self, fmt, *args):
        pass


def main():
    global upstream_url, log_path, model_rewrites, max_tokens_clamp, auth_override, no_think, reasoning_effort_override, exclude_reasoning, force_greedy
    parser = argparse.ArgumentParser()
    parser.add_argument("--port", type=int, required=True)
    parser.add_argument("--log", required=True)
    parser.add_argument("--upstream", required=True, help="Upstream API base URL")
    parser.add_argument("--model-rewrite", action="append", default=[],
                        help="Rewrite model name: local=upstream (e.g. minimax-m25=MiniMaxAI/MiniMax-M2.5)")
    parser.add_argument("--max-tokens", type=int, default=0,
                        help="Clamp max_tokens to this value (0 = no clamping)")
    parser.add_argument("--auth-key", default=None,
                        help="Override Authorization header with this API key")
    parser.add_argument("--no-think", action="store_true", default=False,
                        help="Inject enable_thinking=false into chat requests")
    parser.add_argument("--reasoning-effort", default=None, choices=["low", "medium", "high"],
                        help="Inject reasoning_effort into chat requests")
    parser.add_argument("--exclude-reasoning", action="store_true", default=False,
                        help="Inject reasoning.exclude=true (OpenRouter) so thinking-model chunks don't reach the client")
    parser.add_argument("--force-greedy", action="store_true", default=False,
                        help="force temperature=0 (greedy) on chat requests")
    args = parser.parse_args()
    upstream_url = args.upstream.rstrip("/")
    log_path = args.log
    max_tokens_clamp = args.max_tokens
    auth_override = args.auth_key
    no_think = args.no_think
    reasoning_effort_override = args.reasoning_effort
    exclude_reasoning = args.exclude_reasoning
    force_greedy = args.force_greedy
    if no_think:
        print("  Thinking disabled (enable_thinking=false)", flush=True)
    if reasoning_effort_override:
        print(f"  Reasoning effort: {reasoning_effort_override}", flush=True)
    for rw in args.model_rewrite:
        if "=" in rw:
            local, upstream = rw.split("=", 1)
            model_rewrites[local] = upstream
            print(f"  Model rewrite: {local} -> {upstream}", flush=True)

    server = HTTPServer(("0.0.0.0", args.port), ProxyHandler)
    print(f"OpenAI-compatible proxy listening on port {args.port}", flush=True)
    print(f"  Upstream: {upstream_url}", flush=True)
    print(f"  Logging to: {log_path}", flush=True)
    server.serve_forever()


if __name__ == "__main__":
    main()
