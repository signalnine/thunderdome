#!/usr/bin/env python3
"""OpenAI-compatible API proxy that logs token usage to JSONL.

Usage: python3 openai_proxy.py --port PORT --log LOG_PATH --upstream URL
Forwards all requests to the upstream URL, copies responses verbatim,
and appends a usage record to LOG_PATH for each /chat/completions call.
Handles both regular and streaming responses.
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


class ProxyHandler(BaseHTTPRequestHandler):
    def do_POST(self):
        length = int(self.headers.get("Content-Length", 0))
        body = self.rfile.read(length) if length else b""

        # Build upstream request
        url = upstream_url + self.path
        req = Request(url, data=body, method="POST")
        # Forward all headers except Host
        for key, val in self.headers.items():
            if key.lower() in ("host", "content-length", "transfer-encoding"):
                continue
            req.add_header(key, val)

        try:
            resp = urlopen(req, timeout=600)
            resp_body = resp.read()
            status = resp.status
            resp_headers = resp.headers
        except HTTPError as e:
            resp_body = e.read()
            status = e.code
            resp_headers = e.headers
        except Exception as e:
            print(f"PROXY ERROR: {e}", file=sys.stderr, flush=True)
            self.send_response(500)
            self.send_header("Content-Type", "application/json")
            err_body = json.dumps({"error": str(e)}).encode()
            self.send_header("Content-Length", str(len(err_body)))
            self.end_headers()
            self.wfile.write(err_body)
            return

        # Send response back to client
        self.send_response(status)
        for key, val in resp_headers.items():
            if key.lower() in ("transfer-encoding", "content-length", "connection"):
                continue
            self.send_header(key, val)
        self.send_header("Content-Length", str(len(resp_body)))
        self.end_headers()
        self.wfile.write(resp_body)

        # Log usage for chat/completions calls (OpenAI-compatible)
        if "chat/completions" in self.path:
            try:
                # Decompress if gzipped
                decoded = resp_body
                if resp_body[:2] == b'\x1f\x8b':
                    decoded = gzip.decompress(resp_body)

                # Check if streaming response (data: prefix)
                if decoded.startswith(b'data:'):
                    # Parse streaming response - look for usage in final chunk
                    input_tokens = 0
                    output_tokens = 0
                    model = "unknown"

                    for line in decoded.decode('utf-8', errors='ignore').split('\n'):
                        line = line.strip()
                        if line.startswith('data:'):
                            data_str = line[5:].strip()
                            if data_str and data_str != '[DONE]':
                                try:
                                    chunk = json.loads(data_str)
                                    model = chunk.get('model', model)
                                    # Usage might be in the chunk
                                    if 'usage' in chunk:
                                        input_tokens = chunk['usage'].get('prompt_tokens', 0)
                                        output_tokens = chunk['usage'].get('completion_tokens', 0)
                                except:
                                    pass

                    record = {
                        "timestamp": time.time(),
                        "model": model,
                        "provider": "openai-compat",
                        "input_tokens": input_tokens,
                        "output_tokens": output_tokens,
                        "cache_creation_input_tokens": 0,
                        "cache_read_input_tokens": 0,
                        "status": status,
                    }
                    with open(log_path, "a") as f:
                        f.write(json.dumps(record) + "\n")
                    print(f"LOGGED (streaming): in={input_tokens} out={output_tokens}", file=sys.stderr, flush=True)
                else:
                    # Non-streaming response
                    data = json.loads(decoded)
                    usage = data.get("usage", {})
                    model = data.get("model", "unknown")
                    record = {
                        "timestamp": time.time(),
                        "model": model,
                        "provider": "openai-compat",
                        "input_tokens": usage.get("prompt_tokens", 0),
                        "output_tokens": usage.get("completion_tokens", 0),
                        "cache_creation_input_tokens": 0,
                        "cache_read_input_tokens": 0,
                        "status": status,
                    }
                    with open(log_path, "a") as f:
                        f.write(json.dumps(record) + "\n")
                    print(f"LOGGED: in={record['input_tokens']} out={record['output_tokens']}", file=sys.stderr, flush=True)
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
    global upstream_url, log_path
    parser = argparse.ArgumentParser()
    parser.add_argument("--port", type=int, required=True)
    parser.add_argument("--log", required=True)
    parser.add_argument("--upstream", required=True, help="Upstream API base URL")
    args = parser.parse_args()
    upstream_url = args.upstream.rstrip("/")
    log_path = args.log

    server = HTTPServer(("0.0.0.0", args.port), ProxyHandler)
    print(f"OpenAI-compatible proxy listening on port {args.port}", flush=True)
    print(f"  Upstream: {upstream_url}", flush=True)
    print(f"  Logging to: {log_path}", flush=True)
    server.serve_forever()


if __name__ == "__main__":
    main()
