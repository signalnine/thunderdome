#!/usr/bin/env python3
"""Anthropic API proxy that rewrites model names and logs token usage.

Usage: python3 anthropic_proxy.py --port PORT --log LOG_PATH --upstream URL --model-rewrite local=upstream --api-key KEY
Forwards all Anthropic Messages API requests to an upstream provider,
rewriting model names and logging token usage per request.
Handles both regular and streaming (SSE) responses.
"""

import argparse
import json
import sys
import time
from http.server import HTTPServer, BaseHTTPRequestHandler
from urllib.request import Request, urlopen
from urllib.error import HTTPError

upstream_url = None
log_path = None
model_rewrites = {}
api_key_override = None


class ProxyHandler(BaseHTTPRequestHandler):
    def do_POST(self):
        length = int(self.headers.get("Content-Length", 0))
        body = self.rfile.read(length) if length else b""

        is_messages = "/messages" in self.path
        is_streaming = False

        if body:
            try:
                data = json.loads(body)
                model = data.get("model", "")
                for local, upstream in model_rewrites.items():
                    if local in model:
                        data["model"] = upstream
                        break
                is_streaming = data.get("stream", False)
                body = json.dumps(data).encode()
            except (json.JSONDecodeError, UnicodeDecodeError):
                pass

        # Build upstream request
        url = upstream_url.rstrip("/") + self.path
        req = Request(url, data=body, method="POST")
        saw_ua = False
        for key, val in self.headers.items():
            if key.lower() in ("host", "content-length", "transfer-encoding"):
                continue
            if key.lower() == "x-api-key" and api_key_override:
                req.add_header("x-api-key", api_key_override)
                continue
            if key.lower() == "authorization" and api_key_override:
                # Claude Code may send Authorization instead of x-api-key
                req.add_header("x-api-key", api_key_override)
                continue
            if key.lower() == "user-agent":
                # Override client UA with a browser UA so Cloudflare WAF
                # (e.g. Neuralwatt) doesn't block the Claude Code client.
                req.add_header("User-Agent", "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36")
                saw_ua = True
                continue
            req.add_header(key, val)
        if not saw_ua:
            req.add_header("User-Agent", "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36")
        if api_key_override and not any(k.lower() == "x-api-key" for k in self.headers):
            req.add_header("x-api-key", api_key_override)
        req.add_header("Content-Length", str(len(body)))

        try:
            resp = urlopen(req, timeout=600)
        except HTTPError as e:
            resp_body = e.read()
            print(f"UPSTREAM ERROR {e.code}: {resp_body[:500]}", file=sys.stderr, flush=True)
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
            err_body = json.dumps({"error": {"type": "proxy_error", "message": str(e)}}).encode()
            self.send_header("Content-Length", str(len(err_body)))
            self.end_headers()
            self.wfile.write(err_body)
            return

        content_type = resp.headers.get("Content-Type", "")
        is_sse = "text/event-stream" in content_type

        if is_sse or is_streaming:
            self.send_response(resp.status)
            self.send_header("Content-Type", "text/event-stream; charset=utf-8")
            self.send_header("Cache-Control", "no-cache")
            self.send_header("Connection", "close")
            self.end_headers()

            input_tokens = 0
            output_tokens = 0
            cache_read = 0
            cache_creation = 0
            resp_model = "unknown"

            try:
                for raw_line in resp:
                    self.wfile.write(raw_line)
                    self.wfile.flush()

                    line = raw_line.decode("utf-8", errors="ignore").strip()
                    if line.startswith("data:"):
                        data_str = line[5:].strip()
                        if data_str and data_str != "[DONE]":
                            try:
                                chunk = json.loads(data_str)
                                chunk_type = chunk.get("type", "")
                                if chunk_type == "message_start":
                                    msg = chunk.get("message", {})
                                    resp_model = msg.get("model", resp_model)
                                    u = msg.get("usage", {})
                                    input_tokens = u.get("input_tokens", 0)
                                    cache_read = u.get("cache_read_input_tokens", 0)
                                    cache_creation = u.get("cache_creation_input_tokens", 0)
                                elif chunk_type == "message_delta":
                                    u = chunk.get("usage", {})
                                    output_tokens = u.get("output_tokens", output_tokens)
                                    # z.ai reports input_tokens in message_delta, not message_start
                                    if u.get("input_tokens", 0) > 0:
                                        input_tokens = u["input_tokens"]
                                    if u.get("cache_read_input_tokens", 0) > 0:
                                        cache_read = u["cache_read_input_tokens"]
                            except (json.JSONDecodeError, KeyError):
                                pass
            except (BrokenPipeError, ConnectionResetError) as e:
                print(f"STREAM CLOSED: {e}", file=sys.stderr, flush=True)

            if is_messages:
                record = {
                    "timestamp": time.time(),
                    "model": resp_model,
                    "input_tokens": input_tokens,
                    "output_tokens": output_tokens,
                    "cache_read_input_tokens": cache_read,
                    "cache_creation_input_tokens": cache_creation,
                    "status": resp.status,
                }
                with open(log_path, "a") as f:
                    f.write(json.dumps(record) + "\n")
                print(f"LOGGED (stream): in={input_tokens} out={output_tokens} cache_read={cache_read} model={resp_model}",
                      file=sys.stderr, flush=True)
        else:
            resp_body = resp.read()
            self.send_response(resp.status)
            for key, val in resp.headers.items():
                if key.lower() in ("transfer-encoding", "content-length", "connection"):
                    continue
                self.send_header(key, val)
            self.send_header("Content-Length", str(len(resp_body)))
            self.end_headers()
            self.wfile.write(resp_body)

            if is_messages:
                try:
                    data = json.loads(resp_body)
                    usage = data.get("usage", {})
                    resp_model = data.get("model", "unknown")
                    record = {
                        "timestamp": time.time(),
                        "model": resp_model,
                        "input_tokens": usage.get("input_tokens", 0),
                        "output_tokens": usage.get("output_tokens", 0),
                        "cache_read_input_tokens": usage.get("cache_read_input_tokens", 0),
                        "cache_creation_input_tokens": usage.get("cache_creation_input_tokens", 0),
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
            body = b'{"status":"ok"}'
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
            return
        self.send_response(404)
        self.end_headers()

    def log_message(self, fmt, *args):
        pass


def main():
    global upstream_url, log_path, model_rewrites, api_key_override
    parser = argparse.ArgumentParser()
    parser.add_argument("--port", type=int, required=True)
    parser.add_argument("--log", required=True)
    parser.add_argument("--upstream", required=True)
    parser.add_argument("--model-rewrite", action="append", default=[])
    parser.add_argument("--api-key", default=None)
    args = parser.parse_args()
    upstream_url = args.upstream.rstrip("/")
    log_path = args.log
    api_key_override = args.api_key
    for rw in args.model_rewrite:
        if "=" in rw:
            local, upstream = rw.split("=", 1)
            model_rewrites[local] = upstream
            print(f"  Model rewrite: {local} -> {upstream}", flush=True)

    server = HTTPServer(("0.0.0.0", args.port), ProxyHandler)
    print(f"Anthropic proxy listening on port {args.port}", flush=True)
    print(f"  Upstream: {upstream_url}", flush=True)
    print(f"  Logging to: {log_path}", flush=True)
    server.serve_forever()


if __name__ == "__main__":
    main()
