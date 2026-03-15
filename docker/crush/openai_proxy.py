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
                # Rewrite model name if configured
                model = data.get("model", "")
                if model in model_rewrites:
                    data["model"] = model_rewrites[model]
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
        for key, val in self.headers.items():
            if key.lower() in ("host", "content-length", "transfer-encoding"):
                continue
            req.add_header(key, val)
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

            try:
                for raw_line in resp:
                    # Forward each line immediately
                    self.wfile.write(raw_line)
                    self.wfile.flush()

                    # Parse for usage data
                    line = raw_line.decode('utf-8', errors='ignore').strip()
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
                            except (json.JSONDecodeError, KeyError):
                                pass
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
            # Non-streaming: buffer and forward
            resp_body = resp.read()
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
    global upstream_url, log_path, model_rewrites
    parser = argparse.ArgumentParser()
    parser.add_argument("--port", type=int, required=True)
    parser.add_argument("--log", required=True)
    parser.add_argument("--upstream", required=True, help="Upstream API base URL")
    parser.add_argument("--model-rewrite", action="append", default=[],
                        help="Rewrite model name: local=upstream (e.g. minimax-m25=MiniMaxAI/MiniMax-M2.5)")
    args = parser.parse_args()
    upstream_url = args.upstream.rstrip("/")
    log_path = args.log
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
