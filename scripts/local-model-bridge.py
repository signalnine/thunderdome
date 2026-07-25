#!/usr/bin/env python3
"""Expose a loopback-bound local model server to Docker containers.

q27-server (and most local inference servers) bind 127.0.0.1, which containers
cannot reach: host.docker.internal resolves to the bridge gateway (172.17.0.1)
and a loopback-bound listener refuses it.

This forwards <bridge-ip>:LISTEN -> 127.0.0.1:TARGET so containers can reach the
model WITHOUT restarting the server. It binds the Docker bridge address ONLY,
not 0.0.0.0, so the model is not exposed to the LAN.

The permanent alternative is to start q27-server with `--host 0.0.0.0`; this
exists so an already-running server does not have to be interrupted.

Usage: local-model-bridge.py [--listen-host 172.17.0.1] [--listen-port 8081]
                             [--target-host 127.0.0.1] [--target-port 8080]
"""

import argparse
import socket
import sys
import threading


def _pump(src, dst):
    try:
        while True:
            data = src.recv(65536)
            if not data:
                break
            dst.sendall(data)
    except OSError:
        pass
    finally:
        for s in (src, dst):
            try:
                s.shutdown(socket.SHUT_RDWR)
            except OSError:
                pass


def _handle(client, target):
    try:
        upstream = socket.create_connection(target, timeout=10)
    except OSError as e:
        print(f"bridge: upstream {target} unreachable: {e}", file=sys.stderr, flush=True)
        client.close()
        return
    # No timeout on the data path: model responses can take many minutes.
    client.settimeout(None)
    upstream.settimeout(None)
    threading.Thread(target=_pump, args=(client, upstream), daemon=True).start()
    threading.Thread(target=_pump, args=(upstream, client), daemon=True).start()


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--listen-host", default="172.17.0.1")
    p.add_argument("--listen-port", type=int, default=8081)
    p.add_argument("--target-host", default="127.0.0.1")
    p.add_argument("--target-port", type=int, default=8080)
    a = p.parse_args()

    srv = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    srv.bind((a.listen_host, a.listen_port))
    srv.listen(128)
    print(f"bridge: {a.listen_host}:{a.listen_port} -> {a.target_host}:{a.target_port}",
          file=sys.stderr, flush=True)
    while True:
        client, _ = srv.accept()
        _handle(client, (a.target_host, a.target_port))


if __name__ == "__main__":
    main()
