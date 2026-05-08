#!/usr/bin/env python3
"""
Green VPN controlled service probe.

Reads managed monitoring targets from the backend, checks them from the current
network, and posts sanitized service availability observations back to the
admin API. No secrets are written to disk by this script.
"""

from __future__ import annotations

import argparse
import json
import os
import socket
import ssl
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from dataclasses import dataclass
from datetime import datetime, timezone
from typing import Any


DEFAULT_API_BASE = "https://api.greenvpn.pro"
USER_AGENT = "GreenVPN-ServiceProbe/0.1"


@dataclass
class ProbeResult:
    ok: bool
    status: str
    latency_ms: int | None
    error_code: str
    message: str
    details: dict[str, Any]


def utc_now_iso() -> str:
    return datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Run one controlled Green VPN service monitoring probe pass.",
    )
    parser.add_argument(
        "--api-base",
        default=os.getenv("GREENVPN_API_BASE", DEFAULT_API_BASE),
        help="Backend API base URL. Defaults to GREENVPN_API_BASE or https://api.greenvpn.pro.",
    )
    parser.add_argument(
        "--admin-token-file",
        default=os.getenv("GREENVPN_ADMIN_TOKEN_FILE", ""),
        help="Path to a file containing admin_token. Prefer paths outside the repo.",
    )
    parser.add_argument(
        "--admin-token-stdin",
        action="store_true",
        help="Read admin_token from stdin. Useful for wrappers that avoid command-line secrets.",
    )
    parser.add_argument(
        "--admin-token-env",
        default="GREENVPN_ADMIN_TOKEN",
        help="Environment variable name containing admin_token.",
    )
    parser.add_argument(
        "--probe-id",
        default=os.getenv("GREENVPN_PROBE_ID", socket.gethostname() or "local-probe"),
        help="Probe identity stored with observations.",
    )
    parser.add_argument(
        "--probe-region",
        default=os.getenv("GREENVPN_PROBE_REGION", "local"),
        help="Probe region/network label stored with observations.",
    )
    parser.add_argument(
        "--target-id",
        action="append",
        default=[],
        help="Limit run to one target id. Can be passed multiple times.",
    )
    parser.add_argument(
        "--status",
        default="active",
        choices=["active", "paused", "disabled", "all"],
        help="Monitoring target status to fetch.",
    )
    parser.add_argument(
        "--limit",
        type=int,
        default=500,
        help="Maximum targets to fetch from backend.",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Run checks but do not post observations.",
    )
    parser.add_argument(
        "--server-health",
        action="store_true",
        help=(
            "Also probe active config-ready managed VPN endpoints and post "
            "server-health observations."
        ),
    )
    return parser.parse_args()


def load_admin_token(args: argparse.Namespace) -> str:
    if args.admin_token_stdin:
        token = sys.stdin.read().strip()
    elif args.admin_token_file:
        with open(args.admin_token_file, "r", encoding="utf-8") as fh:
            token = fh.read().strip()
    else:
        token = os.getenv(args.admin_token_env, "").strip()
    if not token:
        raise SystemExit(
            "admin_token is required. Use --admin-token-stdin, --admin-token-file, "
            "or GREENVPN_ADMIN_TOKEN."
        )
    return token


def api_request(
    api_base: str,
    token: str,
    path: str,
    method: str = "GET",
    payload: dict[str, Any] | None = None,
) -> dict[str, Any]:
    data = None
    headers = {
        "Accept": "application/json",
        "User-Agent": USER_AGENT,
        "X-Admin-Token": token,
        "X-Admin-Actor": "service-probe",
    }
    if payload is not None:
        data = json.dumps(payload).encode("utf-8")
        headers["Content-Type"] = "application/json"
    request = urllib.request.Request(
        api_base.rstrip("/") + path,
        data=data,
        headers=headers,
        method=method,
    )
    with urllib.request.urlopen(request, timeout=20) as response:
        return json.loads(response.read().decode("utf-8"))


def target_host(target: dict[str, Any]) -> str:
    host = str(target.get("host") or "").strip()
    if host:
        return host
    url = str(target.get("url") or "").strip()
    if url:
        return urllib.parse.urlparse(url).hostname or ""
    return ""


def target_port(target: dict[str, Any]) -> int | None:
    raw = target.get("port")
    if raw not in (None, ""):
        try:
            return int(raw)
        except Exception:
            return None
    url = str(target.get("url") or "").strip()
    if not url:
        return None
    parsed = urllib.parse.urlparse(url)
    if parsed.port:
        return int(parsed.port)
    if parsed.scheme == "https":
        return 443
    if parsed.scheme == "http":
        return 80
    return None


def resolve_host(host: str, port: int | None, timeout: float) -> tuple[list[str], int]:
    start = time.perf_counter()
    socket.setdefaulttimeout(timeout)
    records = socket.getaddrinfo(host, port or 443, type=socket.SOCK_STREAM)
    latency_ms = round((time.perf_counter() - start) * 1000)
    addresses = sorted({item[4][0] for item in records})
    return addresses, latency_ms


def tcp_connect(host: str, port: int, timeout: float) -> int:
    start = time.perf_counter()
    with socket.create_connection((host, port), timeout=timeout):
        return round((time.perf_counter() - start) * 1000)


def tls_connect(host: str, port: int, timeout: float) -> tuple[int, dict[str, Any]]:
    start = time.perf_counter()
    context = ssl.create_default_context()
    with socket.create_connection((host, port), timeout=timeout) as sock:
        with context.wrap_socket(sock, server_hostname=host) as wrapped:
            cert = wrapped.getpeercert() or {}
            latency_ms = round((time.perf_counter() - start) * 1000)
            return latency_ms, {
                "tlsVersion": wrapped.version(),
                "certSubject": cert.get("subject", [])[:2],
                "certNotAfter": cert.get("notAfter", ""),
            }


def http_check(url: str, expected_status: int | None, timeout: float) -> tuple[bool, str, int, dict[str, Any]]:
    start = time.perf_counter()
    request = urllib.request.Request(
        url,
        headers={
            "User-Agent": USER_AGENT,
            "Accept": "*/*",
        },
        method="GET",
    )
    try:
        with urllib.request.urlopen(request, timeout=timeout) as response:
            body = response.read(512)
            status_code = int(response.status)
            latency_ms = round((time.perf_counter() - start) * 1000)
    except urllib.error.HTTPError as error:
        body = error.read(512)
        status_code = int(error.code)
        latency_ms = round((time.perf_counter() - start) * 1000)
    if expected_status is not None:
        ok = status_code == expected_status
    else:
        ok = 200 <= status_code < 400
    status = "green" if ok else "yellow"
    details = {
        "httpStatus": status_code,
        "bodyPreviewBytes": len(body or b""),
    }
    return ok, status, latency_ms, details


def udp_route_check(host: str, port: int, timeout: float) -> tuple[bool, int, dict[str, Any]]:
    start = time.perf_counter()
    try:
        with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as sock:
            sock.settimeout(timeout)
            sock.connect((host, int(port)))
            sock.send(b"")
        return True, round((time.perf_counter() - start) * 1000), {}
    except Exception as error:
        return (
            False,
            round((time.perf_counter() - start) * 1000),
            {"errorType": type(error).__name__},
        )


def safe_int(value: Any, fallback: int = 0) -> int:
    try:
        return int(value)
    except Exception:
        return fallback


def server_health_candidate_entries(catalog_payload: dict[str, Any]) -> list[dict[str, Any]]:
    entries = catalog_payload.get("managedEntries") or []
    candidates: list[dict[str, Any]] = []
    for entry in entries:
        if not entry.get("isActive"):
            continue
        if not entry.get("clientConfigReady"):
            continue
        if str(entry.get("protocol") or "").lower() != "wireguard_udp":
            continue
        host = str(entry.get("host") or "").strip()
        port = safe_int(entry.get("port"), 0)
        if not host or port <= 0:
            continue
        candidates.append(entry)
    return candidates


def probe_server_entry(entry: dict[str, Any], api_base: str) -> ProbeResult:
    endpoint_id = str(entry.get("serverId") or "unknown")
    host = str(entry.get("host") or "").strip()
    port = safe_int(entry.get("port"), 0)
    timeout = 6.0
    details: dict[str, Any] = {
        "score": 0,
        "probeKind": "external_endpoint_probe",
        "safeForPublicRouting": False,
        "verificationLimitations": [
            "External probe can verify DNS/API reachability and local UDP route only.",
            "It does not possess client WireGuard private keys and cannot complete a VPN handshake.",
        ],
        "endpoint": {
            "serverId": endpoint_id,
            "host": host,
            "port": port,
            "protocol": entry.get("protocol") or "",
            "transport": entry.get("transport") or "",
            "clientConfigReady": bool(entry.get("clientConfigReady")),
            "clientConfigProfile": entry.get("clientConfigProfile") or "",
            "isPublicCandidate": bool(entry.get("isPublic")),
        },
        "steps": [],
    }
    total_start = time.perf_counter()
    penalty = 0

    def add_step(name: str, ok: bool, penalty_points: int, **extra: Any) -> None:
        nonlocal penalty
        if not ok:
            penalty += max(0, penalty_points)
        details["steps"].append({"name": name, "ok": bool(ok), **extra})

    try:
        addresses, dns_ms = resolve_host(host, port, timeout)
        add_step("dns", True, 35, latencyMs=dns_ms, addresses=addresses[:6])
    except Exception as error:
        add_step("dns", False, 35, errorType=type(error).__name__)

    udp_ok, udp_ms, udp_details = udp_route_check(host, port, timeout)
    add_step("udp_socket_route", udp_ok, 20, latencyMs=udp_ms, **udp_details)

    api_health_url = api_base.rstrip("/") + "/healthz"
    try:
        api_ok, api_status, api_ms, api_details = http_check(api_health_url, 200, timeout)
        add_step(
            "api_healthz",
            api_ok,
            25,
            latencyMs=api_ms,
            status=api_status,
            apiBasePresent=True,
            **api_details,
        )
    except Exception as error:
        add_step("api_healthz", False, 25, errorType=type(error).__name__, apiBasePresent=True)

    config_ready = bool(entry.get("clientConfigReady"))
    add_step(
        "client_config_ready",
        config_ready,
        20,
        profile=entry.get("clientConfigProfile") or "",
    )

    score = max(0, min(100, 100 - penalty))
    details["score"] = score
    if score >= 80:
        status = "healthy"
    elif score >= 50:
        status = "degraded"
    else:
        status = "down"
    failed_steps = [item["name"] for item in details["steps"] if not item.get("ok")]
    latency_ms = round((time.perf_counter() - total_start) * 1000)
    if status == "healthy":
        message = f"External probe sees {endpoint_id} as healthy: score={score}."
        error_code = ""
    else:
        message = f"External probe sees {endpoint_id} as {status}: score={score}."
        error_code = failed_steps[0] if failed_steps else status
    return ProbeResult(
        ok=status == "healthy",
        status=status,
        latency_ms=latency_ms,
        error_code=error_code,
        message=message,
        details=details,
    )


def probe_target(target: dict[str, Any]) -> ProbeResult:
    target_id = target.get("targetId") or "unknown"
    target_type = str(target.get("targetType") or "web").lower()
    host = target_host(target)
    port = target_port(target)
    url = str(target.get("url") or "").strip()
    timeout = float(target.get("timeoutSeconds") or 8)
    expected_status = target.get("expectedStatus")
    if expected_status in ("", None):
        expected_status = None
    else:
        expected_status = int(expected_status)

    details: dict[str, Any] = {
        "targetId": target_id,
        "targetType": target_type,
        "host": host,
        "port": port,
        "urlPresent": bool(url),
        "steps": [],
    }
    total_start = time.perf_counter()

    try:
        if not host:
            raise ValueError("target has no host/url")

        addresses, dns_ms = resolve_host(host, port, timeout)
        details["steps"].append({"name": "dns", "ok": True, "latencyMs": dns_ms, "addresses": addresses[:6]})
        if target_type == "dns":
            return ProbeResult(True, "green", dns_ms, "", f"DNS resolved {host}.", details)

        if port is None:
            port = 443 if url.startswith("https://") else 80
            details["port"] = port

        if target_type in {"tcp"}:
            tcp_ms = tcp_connect(host, port, timeout)
            details["steps"].append({"name": "tcp", "ok": True, "latencyMs": tcp_ms})
            return ProbeResult(True, "green", tcp_ms, "", f"TCP {host}:{port} reachable.", details)

        if target_type in {"tls"}:
            tls_ms, tls_details = tls_connect(host, port, timeout)
            details["steps"].append({"name": "tls", "ok": True, "latencyMs": tls_ms, **tls_details})
            return ProbeResult(True, "green", tls_ms, "", f"TLS {host}:{port} reachable.", details)

        if url.startswith("https://"):
            tls_ms, tls_details = tls_connect(host, port, timeout)
            details["steps"].append({"name": "tls", "ok": True, "latencyMs": tls_ms, **tls_details})
        elif port:
            tcp_ms = tcp_connect(host, port, timeout)
            details["steps"].append({"name": "tcp", "ok": True, "latencyMs": tcp_ms})

        if not url:
            latency_ms = round((time.perf_counter() - total_start) * 1000)
            return ProbeResult(True, "green", latency_ms, "", f"{target_type.upper()} target reachable.", details)

        ok, status, http_ms, http_details = http_check(url, expected_status, timeout)
        details["steps"].append({"name": "http", "ok": ok, "latencyMs": http_ms, **http_details})
        message = (
            f"{target.get('title') or target_id} responded as expected."
            if ok
            else f"{target.get('title') or target_id} responded with unexpected HTTP status."
        )
        return ProbeResult(ok, status, http_ms, "" if ok else "unexpected_http_status", message, details)
    except Exception as error:
        latency_ms = round((time.perf_counter() - total_start) * 1000)
        error_name = type(error).__name__
        details["steps"].append({"name": "exception", "ok": False, "errorType": error_name})
        return ProbeResult(
            False,
            "red",
            latency_ms,
            error_name,
            f"{target.get('title') or target_id} check failed: {error_name}.",
            details,
        )


def main() -> int:
    args = parse_args()
    token = load_admin_token(args)
    api_base = args.api_base.rstrip("/")
    params = urllib.parse.urlencode({"status": args.status, "limit": args.limit})
    try:
        payload = api_request(api_base, token, f"/api/v1/admin/monitoring/targets?{params}")
    except Exception as error:
        print(
            json.dumps(
                {
                    "ok": False,
                    "apiBase": api_base,
                    "probeId": args.probe_id,
                    "probeRegion": args.probe_region,
                    "dryRun": bool(args.dry_run),
                    "serverHealthEnabled": bool(args.server_health),
                    "stage": "fetch_targets",
                    "errorCode": type(error).__name__,
                    "message": "Could not fetch monitoring targets from backend.",
                    "targetsChecked": 0,
                    "serverHealthChecked": 0,
                    "green": 0,
                    "yellow": 0,
                    "red": 0,
                    "unknown": 0,
                    "failedPosts": 0,
                    "serverHealthFailedPosts": 0,
                    "results": [],
                    "serverHealth": [],
                },
                ensure_ascii=False,
                indent=2,
            )
        )
        return 2
    targets = payload.get("targets") or []
    wanted = set(args.target_id or [])
    if wanted:
        targets = [target for target in targets if target.get("targetId") in wanted]

    results: list[dict[str, Any]] = []
    failed_posts = 0
    server_health_results: list[dict[str, Any]] = []
    server_health_failed_posts = 0
    for target in targets:
        result = probe_target(target)
        observation = {
            "targetId": target.get("targetId"),
            "probeId": args.probe_id,
            "probeRegion": args.probe_region,
            "ok": result.ok,
            "status": result.status,
            "latencyMs": result.latency_ms,
            "errorCode": result.error_code,
            "message": result.message,
            "details": result.details,
            "observedAt": utc_now_iso(),
        }
        posted = False
        post_error = ""
        if not args.dry_run:
            try:
                api_request(
                    api_base,
                    token,
                    "/api/v1/admin/monitoring/service-observations",
                    method="POST",
                    payload=observation,
                )
                posted = True
            except Exception as error:
                failed_posts += 1
                post_error = type(error).__name__
        results.append(
            {
                "targetId": target.get("targetId"),
                "status": result.status,
                "ok": result.ok,
                "latencyMs": result.latency_ms,
                "posted": posted,
                "postError": post_error,
                "message": result.message,
            }
        )

    if args.server_health:
        try:
            catalog_payload = api_request(
                api_base,
                token,
                "/api/v1/admin/server-catalog?status=all&active=all&public=all&limit=500",
            )
            server_entries = server_health_candidate_entries(catalog_payload)
        except Exception as error:
            server_health_failed_posts += 1
            server_health_results.append(
                {
                    "endpointId": "",
                    "status": "unknown",
                    "ok": False,
                    "latencyMs": None,
                    "posted": False,
                    "postError": type(error).__name__,
                    "message": "Could not fetch server catalog for endpoint health.",
                }
            )
            server_entries = []

        for entry in server_entries:
            result = probe_server_entry(entry, api_base)
            observation = {
                "endpointId": entry.get("serverId"),
                "probeId": args.probe_id,
                "probeRegion": args.probe_region,
                "protocol": entry.get("protocol") or "wireguard_udp",
                "transport": entry.get("transport") or "udp",
                "target": f"{entry.get('host')}:{entry.get('port')}",
                "ok": result.ok,
                "status": result.status,
                "latencyMs": result.latency_ms,
                "packetLossPercent": None,
                "errorCode": result.error_code,
                "message": result.message,
                "details": result.details,
                "observedAt": utc_now_iso(),
            }
            posted = False
            post_error = ""
            if not args.dry_run:
                try:
                    api_request(
                        api_base,
                        token,
                        "/api/v1/admin/server-health/observations",
                        method="POST",
                        payload=observation,
                    )
                    posted = True
                except Exception as error:
                    server_health_failed_posts += 1
                    post_error = type(error).__name__
            server_health_results.append(
                {
                    "endpointId": entry.get("serverId"),
                    "status": result.status,
                    "ok": result.ok,
                    "latencyMs": result.latency_ms,
                    "posted": posted,
                    "postError": post_error,
                    "message": result.message,
                }
            )

    summary = {
        "ok": True,
        "apiBase": api_base,
        "probeId": args.probe_id,
        "probeRegion": args.probe_region,
        "dryRun": bool(args.dry_run),
        "serverHealthEnabled": bool(args.server_health),
        "targetsChecked": len(results),
        "serverHealthChecked": len(server_health_results),
        "green": len([item for item in results if item["status"] == "green"]),
        "yellow": len([item for item in results if item["status"] == "yellow"]),
        "red": len([item for item in results if item["status"] == "red"]),
        "unknown": len([item for item in results if item["status"] == "unknown"]),
        "failedPosts": failed_posts,
        "serverHealthHealthy": len(
            [item for item in server_health_results if item["status"] == "healthy"]
        ),
        "serverHealthDegraded": len(
            [item for item in server_health_results if item["status"] == "degraded"]
        ),
        "serverHealthDown": len(
            [item for item in server_health_results if item["status"] == "down"]
        ),
        "serverHealthFailedPosts": server_health_failed_posts,
        "results": results,
        "serverHealth": server_health_results,
    }
    print(json.dumps(summary, ensure_ascii=False, indent=2))
    return (
        0
        if summary["red"] == 0
        and failed_posts == 0
        and summary["serverHealthDown"] == 0
        and server_health_failed_posts == 0
        else 2
    )


if __name__ == "__main__":
    raise SystemExit(main())
