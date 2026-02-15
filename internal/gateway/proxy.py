#!/usr/bin/env python3
"""Lightweight Anthropic API proxy that logs token usage to JSONL.

Usage: python3 proxy.py --port PORT --log LOG_PATH --api-key KEY
Forwards all requests to https://api.anthropic.com, copies responses
verbatim, and appends a usage record to LOG_PATH for each /v1/messages call.
"""

import argparse
import gzip
import json
import sys
import time
from http.server import HTTPServer, BaseHTTPRequestHandler
from urllib.request import Request, urlopen
from urllib.error import HTTPError

UPSTREAM = "https://api.anthropic.com"
log_path = None


class ProxyHandler(BaseHTTPRequestHandler):
    def do_POST(self):
        length = int(self.headers.get("Content-Length", 0))
        body = self.rfile.read(length) if length else b""

        # Build upstream request
        url = UPSTREAM + self.path
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

        # Send response back to client
        self.send_response(status)
        for key, val in resp_headers.items():
            if key.lower() in ("transfer-encoding", "content-length", "connection"):
                continue
            self.send_header(key, val)
        self.send_header("Content-Length", str(len(resp_body)))
        self.end_headers()
        self.wfile.write(resp_body)

        # Log usage for successful /v1/messages calls
        if "/v1/messages" in self.path and 200 <= status < 300:
            try:
                # Decompress if gzipped
                decoded = resp_body
                if resp_body[:2] == b'\x1f\x8b':
                    decoded = gzip.decompress(resp_body)
                data = json.loads(decoded)
                usage = data.get("usage", {})
                model = data.get("model", "unknown")
                record = {
                    "timestamp": time.time(),
                    "model": model,
                    "provider": "anthropic",
                    "input_tokens": usage.get("input_tokens", 0),
                    "output_tokens": usage.get("output_tokens", 0),
                    "cache_creation_input_tokens": usage.get("cache_creation_input_tokens", 0),
                    "cache_read_input_tokens": usage.get("cache_read_input_tokens", 0),
                }
                with open(log_path, "a") as f:
                    f.write(json.dumps(record) + "\n")
            except Exception:
                pass

    def do_GET(self):
        # Health check
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
        # Suppress default access logs
        pass


def main():
    global log_path
    parser = argparse.ArgumentParser()
    parser.add_argument("--port", type=int, required=True)
    parser.add_argument("--log", required=True)
    parser.add_argument("--api-key", required=False, help="Not used; key comes from client headers")
    args = parser.parse_args()
    log_path = args.log

    server = HTTPServer(("0.0.0.0", args.port), ProxyHandler)
    print(f"Anthropic proxy listening on port {args.port}, logging to {log_path}", flush=True)
    server.serve_forever()


if __name__ == "__main__":
    main()
