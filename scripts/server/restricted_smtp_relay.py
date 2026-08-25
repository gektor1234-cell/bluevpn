#!/usr/bin/env python3
"""Restricted IPv4 SMTP TCP relay with background DNS refresh."""

from __future__ import annotations

import ipaddress
import os
import select
import socket
import sys
import threading
import time


LISTEN_HOST = os.getenv("GREENVPN_SMTP_RELAY_LISTEN_HOST", "0.0.0.0")
LISTEN_PORT = int(os.getenv("GREENVPN_SMTP_RELAY_LISTEN_PORT", "2587"))
REMOTE_HOST = os.getenv("GREENVPN_SMTP_RELAY_REMOTE_HOST", "smtp.yandex.ru")
REMOTE_PORT = int(os.getenv("GREENVPN_SMTP_RELAY_REMOTE_PORT", "587"))
RESOLVE_INTERVAL_SECONDS = int(
    os.getenv("GREENVPN_SMTP_RELAY_RESOLVE_INTERVAL_SECONDS", "300")
)
CONNECT_TIMEOUT_SECONDS = float(
    os.getenv("GREENVPN_SMTP_RELAY_CONNECT_TIMEOUT_SECONDS", "5")
)
ALLOWED = {
    ipaddress.ip_address(value.strip())
    for value in os.getenv(
        "GREENVPN_SMTP_RELAY_ALLOWED_IPS",
        "72.56.32.197,127.0.0.1",
    ).split(",")
    if value.strip()
}

_endpoint_lock = threading.Lock()
_remote_endpoints: tuple[tuple[str, int], ...] = ()


def log(message: str) -> None:
    print(message, file=sys.stderr, flush=True)


def resolve_remote() -> tuple[tuple[str, int], ...]:
    global _remote_endpoints
    resolved: list[tuple[str, int]] = []
    for family, socktype, protocol, _, address in socket.getaddrinfo(
        REMOTE_HOST,
        REMOTE_PORT,
        family=socket.AF_INET,
        type=socket.SOCK_STREAM,
    ):
        if family != socket.AF_INET or socktype != socket.SOCK_STREAM:
            continue
        endpoint = (address[0], address[1])
        if endpoint not in resolved:
            resolved.append(endpoint)
    if not resolved:
        raise OSError("SMTP relay DNS returned no IPv4 endpoints")
    endpoints = tuple(resolved)
    with _endpoint_lock:
        _remote_endpoints = endpoints
    log(f"resolved {REMOTE_HOST} to {len(endpoints)} IPv4 endpoint(s)")
    return endpoints


def current_endpoints() -> tuple[tuple[str, int], ...]:
    with _endpoint_lock:
        return _remote_endpoints


def resolver_loop() -> None:
    while True:
        time.sleep(max(30, RESOLVE_INTERVAL_SECONDS))
        try:
            resolve_remote()
        except Exception as exc:
            log(f"background DNS refresh failed: {type(exc).__name__}: {exc}")


def connect_upstream() -> socket.socket:
    endpoints = current_endpoints() or resolve_remote()
    last_error: Exception | None = None
    for endpoint in endpoints:
        upstream = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        upstream.settimeout(CONNECT_TIMEOUT_SECONDS)
        try:
            upstream.connect(endpoint)
            upstream.settimeout(None)
            return upstream
        except Exception as exc:
            last_error = exc
            upstream.close()
    raise OSError(f"all SMTP upstream endpoints failed: {last_error}")


def pipe(source: socket.socket, destination: socket.socket) -> None:
    try:
        while True:
            readable, _, _ = select.select([source], [], [], 60)
            if not readable:
                break
            data = source.recv(65536)
            if not data:
                break
            destination.sendall(data)
    except Exception:
        pass
    finally:
        try:
            destination.shutdown(socket.SHUT_WR)
        except Exception:
            pass


def handle(client: socket.socket, address: tuple[str, int]) -> None:
    upstream: socket.socket | None = None
    try:
        peer_ip = ipaddress.ip_address(address[0])
        if peer_ip not in ALLOWED:
            log(f"refused non-allowlisted relay client {peer_ip}")
            return
        upstream = connect_upstream()
        threading.Thread(
            target=pipe,
            args=(client, upstream),
            daemon=True,
        ).start()
        pipe(upstream, client)
    except Exception as exc:
        log(f"relay connection failed: {type(exc).__name__}: {exc}")
    finally:
        client.close()
        if upstream is not None:
            upstream.close()


def main() -> None:
    resolve_remote()
    threading.Thread(target=resolver_loop, daemon=True).start()

    server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    server.bind((LISTEN_HOST, LISTEN_PORT))
    server.listen(128)
    log(
        f"listening on {LISTEN_HOST}:{LISTEN_PORT}; "
        f"allowed_clients={len(ALLOWED)}"
    )
    while True:
        client, address = server.accept()
        threading.Thread(target=handle, args=(client, address), daemon=True).start()


if __name__ == "__main__":
    main()
