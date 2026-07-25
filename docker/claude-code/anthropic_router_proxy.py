#!/usr/bin/env python3
"""Anthropic Messages API proxy that ROUTES by model to two upstreams.

Usage:
  anthropic_router_proxy.py --port PORT --log LOG \
      --upstream-default https://api.anthropic.com \
      --local-upstream http://host.docker.internal:8080 \
      --local-match haiku --local-model qwopus-27b-mtp

Every request is inspected: if the requested model contains --local-match, it is
forwarded to --local-upstream (with the model rewritten to --local-model),
otherwise it goes to --upstream-default untouched.

This exists so a single Claude Code process can drive subagents on DIFFERENT
backends. Claude Code sends all traffic to one ANTHROPIC_BASE_URL and selects a
subagent's model by name, so name-based dispatch here is what turns
"model: haiku" in an agent definition into "run this on the local box".

It works without any format translation because q27 speaks the Anthropic
Messages API natively -- the local side is the same wire protocol, not an
OpenAI shim.

Auth: headers are forwarded verbatim to the default upstream so OAuth bearer
tokens keep working. They are STRIPPED for the local upstream, which needs no
credentials and should never see them.
"""

import argparse
import json
import sys
import time
from http.server import HTTPServer, ThreadingHTTPServer, BaseHTTPRequestHandler
from urllib.request import Request, urlopen
from urllib.error import HTTPError

args = None
_counts = {"default": 0, "local": 0}

# Headers that must never be copied verbatim to an upstream.
_HOP_BY_HOP = {"host", "content-length", "transfer-encoding", "connection"}
# Credential-bearing headers, dropped on the local route.
_AUTH_HEADERS = {"authorization", "x-api-key"}


class RouterHandler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, fmt, *a):  # silence per-request stderr noise
        pass

    def do_POST(self):
        length = int(self.headers.get("Content-Length", 0))
        body = self.rfile.read(length) if length else b""

        requested_model = ""
        is_streaming = False
        if body:
            try:
                data = json.loads(body)
                requested_model = data.get("model", "") or ""
                is_streaming = bool(data.get("stream", False))
                if args.local_match and args.local_match in requested_model:
                    data["model"] = args.local_model
                    body = json.dumps(data).encode()
            except (json.JSONDecodeError, UnicodeDecodeError):
                pass

        to_local = bool(args.local_match and args.local_match in requested_model)
        base = args.local_upstream if to_local else args.upstream_default
        _counts["local" if to_local else "default"] += 1
        print(f"ROUTE {'LOCAL ' if to_local else 'DEFAULT'} model={requested_model or '?'} "
              f"-> {base}{self.path}", file=sys.stderr, flush=True)

        req = Request(base.rstrip("/") + self.path, data=body, method="POST")
        for key, val in self.headers.items():
            k = key.lower()
            if k in _HOP_BY_HOP:
                continue
            if to_local and k in _AUTH_HEADERS:
                continue
            req.add_header(key, val)
        req.add_header("Content-Length", str(len(body)))

        try:
            resp = urlopen(req, timeout=1800)
        except HTTPError as e:
            payload = e.read()
            print(f"UPSTREAM {e.code} ({'local' if to_local else 'default'}): {payload[:400]}",
                  file=sys.stderr, flush=True)
            self.send_response(e.code)
            self.send_header("Content-Type", e.headers.get("Content-Type", "application/json"))
            self.send_header("Content-Length", str(len(payload)))
            self.end_headers()
            self.wfile.write(payload)
            return
        except Exception as e:
            print(f"PROXY ERROR ({'local' if to_local else 'default'}): {e}",
                  file=sys.stderr, flush=True)
            payload = json.dumps({"error": {"type": "proxy_error", "message": str(e)}}).encode()
            self.send_response(502)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(payload)))
            self.end_headers()
            self.wfile.write(payload)
            return

        is_sse = "text/event-stream" in resp.headers.get("Content-Type", "")
        if is_sse or is_streaming:
            self.send_response(resp.status)
            self.send_header("Content-Type", "text/event-stream; charset=utf-8")
            self.send_header("Cache-Control", "no-cache")
            self.send_header("Connection", "close")
            self.end_headers()
            usage = {"in": 0, "out": 0, "cache_read": 0, "model": requested_model}
            try:
                for raw in resp:
                    self.wfile.write(raw)
                    self.wfile.flush()
                    line = raw.decode("utf-8", errors="ignore").strip()
                    if not line.startswith("data:"):
                        continue
                    payload = line[5:].strip()
                    if not payload or payload == "[DONE]":
                        continue
                    try:
                        chunk = json.loads(payload)
                    except json.JSONDecodeError:
                        continue
                    if chunk.get("type") == "message_start":
                        m = chunk.get("message", {})
                        usage["model"] = m.get("model", usage["model"])
                        u = m.get("usage", {}) or {}
                        usage["in"] = u.get("input_tokens", 0)
                        usage["cache_read"] = u.get("cache_read_input_tokens", 0)
                    elif chunk.get("type") == "message_delta":
                        u = chunk.get("usage", {}) or {}
                        usage["out"] = u.get("output_tokens", usage["out"])
            except (BrokenPipeError, ConnectionResetError):
                pass
            _log(to_local, usage)
            return

        payload = resp.read()
        self.send_response(resp.status)
        for key, val in resp.headers.items():
            if key.lower() in _HOP_BY_HOP:
                continue
            self.send_header(key, val)
        self.send_header("Content-Length", str(len(payload)))
        self.end_headers()
        self.wfile.write(payload)
        try:
            d = json.loads(payload)
            u = d.get("usage", {}) or {}
            _log(to_local, {"model": d.get("model", requested_model),
                            "in": u.get("input_tokens", 0),
                            "out": u.get("output_tokens", 0),
                            "cache_read": u.get("cache_read_input_tokens", 0)})
        except Exception:
            pass

    def do_GET(self):
        self.send_response(200)
        payload = json.dumps({"ok": True, "routed": _counts}).encode()
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(payload)))
        self.end_headers()
        self.wfile.write(payload)


def _log(to_local, usage):
    if not args.log:
        return
    rec = {
        "timestamp": time.time(),
        "route": "local" if to_local else "default",
        "model": usage.get("model"),
        "input_tokens": usage.get("in", 0),
        "output_tokens": usage.get("out", 0),
        "cache_read_input_tokens": usage.get("cache_read", 0),
    }
    with open(args.log, "a") as f:
        f.write(json.dumps(rec) + "\n")


def main():
    global args
    p = argparse.ArgumentParser()
    p.add_argument("--port", type=int, required=True)
    p.add_argument("--log")
    p.add_argument("--upstream-default", required=True)
    p.add_argument("--local-upstream", required=True)
    p.add_argument("--local-match", default="haiku",
                   help="route to the local upstream when the model name contains this")
    p.add_argument("--local-model", default="qwopus-27b-mtp",
                   help="model name to send to the local upstream")
    args = p.parse_args()
    print(f"router on :{args.port}\n  default -> {args.upstream_default}\n"
          f"  local   -> {args.local_upstream} (match '{args.local_match}' -> {args.local_model})",
          file=sys.stderr, flush=True)
    ThreadingHTTPServer(("0.0.0.0", args.port), RouterHandler).serve_forever()


if __name__ == "__main__":
    main()
