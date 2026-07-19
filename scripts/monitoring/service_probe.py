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
import re
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


def env_float(name: str, fallback: float) -> float:
    try:
        return float(os.getenv(name, str(fallback)).replace(",", "."))
    except Exception:
        return fallback


def env_int(name: str, fallback: int) -> int:
    try:
        return int(os.getenv(name, str(fallback)))
    except Exception:
        return fallback


MEDIA_PROBE_BYTES = max(64 * 1024, env_int("GREENVPN_MEDIA_PROBE_BYTES", 1024 * 1024))
MEDIA_PROBE_GREEN_MBPS = max(0.1, env_float("GREENVPN_MEDIA_PROBE_GREEN_MBPS", 4.0))
MEDIA_PROBE_YELLOW_MBPS = max(0.05, env_float("GREENVPN_MEDIA_PROBE_YELLOW_MBPS", 1.0))
YOUTUBE_MEDIA_TEST_URL = os.getenv(
    "GREENVPN_YOUTUBE_MEDIA_TEST_URL",
    "https://www.youtube.com/watch?v=dQw4w9WgXcQ",
).strip()
YOUTUBE_MEDIA_FALLBACK_URL = os.getenv(
    "GREENVPN_YOUTUBE_MEDIA_FALLBACK_URL",
    "https://i.ytimg.com/vi/dQw4w9WgXcQ/maxresdefault.jpg",
).strip()
YOUTUBE_MEDIA_GREEN_MBPS = max(0.1, env_float("GREENVPN_YOUTUBE_MEDIA_GREEN_MBPS", 5.0))
YOUTUBE_MEDIA_YELLOW_MBPS = max(0.05, env_float("GREENVPN_YOUTUBE_MEDIA_YELLOW_MBPS", 1.0))
API_REQUEST_TIMEOUT_SECONDS = max(10.0, env_float("GREENVPN_PROBE_API_TIMEOUT_SECONDS", 60.0))

ALLOWED_ROUTE_PROTOCOLS = {
    "wireguard_udp",
    "wireguard_tcp",
    "amneziawg",
    "openvpn_tcp",
    "shadowsocks",
    "hysteria2",
    "trojan_tls",
    "vless_reality",
    "masque_udp",
}
ALLOWED_ROUTE_TRANSPORTS = {"udp", "tcp", "tls", "quic", "http3", "reality", "masque"}
DEFAULT_ROUTE_CANDIDATE = {
    "endpointId": "intelligent_smew",
    "protocol": "wireguard_udp",
    "transport": "udp",
    "signalKind": "service_target_signal_for_current_route",
}


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
        "--fail-on-post-error",
        action="store_true",
        help="Exit non-zero when an observation POST fails. Disabled by default for systemd probes.",
    )
    parser.add_argument(
        "--server-health",
        action="store_true",
        help=(
            "Also probe active config-ready managed VPN endpoints and post "
            "server-health observations."
        ),
    )
    parser.add_argument(
        "--server-health-server-id",
        action="append",
        default=[],
        help=(
            "Also probe this managed server id even if it is still draft/inactive. "
            "The entry must still be client-config-ready and wireguard_udp. "
            "Can be passed multiple times for pre-publication canaries."
        ),
    )
    parser.add_argument(
        "--route-health",
        action="store_true",
        help=(
            "Also post adaptive routing observations for the current client-ready "
            "route. This lets the backend rank the lightest working route first."
        ),
    )
    parser.add_argument(
        "--route-candidate",
        action="append",
        default=[],
        help=(
            "Route candidate to mark with route-health observations. Format: "
            "endpointId=intelligent_smew,protocol=wireguard_udp,transport=udp,"
            "signalKind=service_target_signal_for_current_route. Can be repeated "
            "for canary transports after their real tunnel/proxy path is configured."
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
    with urllib.request.urlopen(request, timeout=API_REQUEST_TIMEOUT_SECONDS) as response:
        return json.loads(response.read().decode("utf-8"))


def api_error_code(error: Exception) -> str:
    if isinstance(error, urllib.error.HTTPError):
        return f"HTTPError_{error.code}"
    return type(error).__name__


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
    last_error: Exception | None = None
    attempts = 3
    for attempt in range(1, attempts + 1):
        try:
            with urllib.request.urlopen(request, timeout=timeout) as response:
                body = response.read(512)
                status_code = int(response.status)
                latency_ms = round((time.perf_counter() - start) * 1000)
                break
        except urllib.error.HTTPError as error:
            body = error.read(512)
            status_code = int(error.code)
            latency_ms = round((time.perf_counter() - start) * 1000)
            break
        except (urllib.error.URLError, TimeoutError, OSError) as error:
            last_error = error
            if attempt >= attempts:
                raise
            time.sleep(min(0.5 * attempt, 1.5))
    else:
        raise last_error or RuntimeError("HTTP probe failed")
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


def target_tags(target: dict[str, Any]) -> list[str]:
    raw = target.get("tags") or []
    if not isinstance(raw, list):
        return []
    return [str(item or "").strip() for item in raw if str(item or "").strip()]


def target_threshold_float(target: dict[str, Any], key: str, fallback: float) -> float:
    key_lower = key.lower()
    for tag in target_tags(target):
        if "=" not in tag:
            continue
        tag_key, tag_value = tag.split("=", 1)
        if tag_key.strip().lower() != key_lower:
            continue
        try:
            return float(tag_value.strip().replace(",", "."))
        except Exception:
            return fallback
    notes = str(target.get("notes") or "")
    match = re.search(rf"\b{re.escape(key)}\s*[:=]\s*([0-9]+(?:[\.,][0-9]+)?)", notes, re.IGNORECASE)
    if match:
        try:
            return float(match.group(1).replace(",", "."))
        except Exception:
            return fallback
    return fallback


def media_thresholds(target: dict[str, Any], target_type: str) -> tuple[float, float, int]:
    if target_type == "youtube_media":
        green = YOUTUBE_MEDIA_GREEN_MBPS
        yellow = YOUTUBE_MEDIA_YELLOW_MBPS
    else:
        green = MEDIA_PROBE_GREEN_MBPS
        yellow = MEDIA_PROBE_YELLOW_MBPS
    green = max(0.1, target_threshold_float(target, "min_green_mbps", green))
    yellow = max(0.05, target_threshold_float(target, "min_yellow_mbps", yellow))
    bytes_to_read = max(64 * 1024, int(target_threshold_float(target, "probe_bytes", float(MEDIA_PROBE_BYTES))))
    return green, min(yellow, green), bytes_to_read


def http_fetch_text(url: str, timeout: float) -> tuple[str, int, int, dict[str, Any]]:
    start = time.perf_counter()
    request = urllib.request.Request(
        url,
        headers={
            "User-Agent": USER_AGENT,
            "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
        },
        method="GET",
    )
    with urllib.request.urlopen(request, timeout=timeout) as response:
        body = response.read(2_000_000)
        latency_ms = round((time.perf_counter() - start) * 1000)
        charset = response.headers.get_content_charset() or "utf-8"
        text = body.decode(charset, errors="replace")
        return text, int(response.status), latency_ms, {
            "httpStatus": int(response.status),
            "bodyPreviewBytes": len(body),
            "finalHost": urllib.parse.urlparse(response.geturl()).hostname or "",
        }


def extract_balanced_json(text: str, marker: str) -> dict[str, Any] | None:
    marker_index = text.find(marker)
    if marker_index < 0:
        return None
    start = text.find("{", marker_index)
    if start < 0:
        return None
    depth = 0
    in_string = False
    escape_next = False
    for index in range(start, len(text)):
        char = text[index]
        if in_string:
            if escape_next:
                escape_next = False
            elif char == "\\":
                escape_next = True
            elif char == '"':
                in_string = False
            continue
        if char == '"':
            in_string = True
        elif char == "{":
            depth += 1
        elif char == "}":
            depth -= 1
            if depth == 0:
                try:
                    return json.loads(text[start : index + 1])
                except Exception:
                    return None
    return None


def extract_youtube_media_url(page_html: str) -> tuple[str, dict[str, Any]]:
    player_response = extract_balanced_json(page_html, "ytInitialPlayerResponse")
    if not isinstance(player_response, dict):
        raise ValueError("youtube_player_response_not_found")
    streaming_data = player_response.get("streamingData") or {}
    candidates = []
    for key in ("adaptiveFormats", "formats"):
        values = streaming_data.get(key) or []
        if isinstance(values, list):
            candidates.extend(values)
    direct_candidates = []
    for candidate in candidates:
        if not isinstance(candidate, dict):
            continue
        media_url = str(candidate.get("url") or "").strip()
        if not media_url:
            continue
        mime_type = str(candidate.get("mimeType") or "")
        score = 0
        if "video/" in mime_type:
            score += 100
        if "audio/" in mime_type:
            score += 50
        score += safe_int(candidate.get("bitrate"), 0) // 1000
        direct_candidates.append((score, media_url, candidate))
    if not direct_candidates:
        raise ValueError("youtube_direct_media_url_not_found")
    direct_candidates.sort(key=lambda item: item[0], reverse=True)
    _, media_url, selected = direct_candidates[0]
    media_host = urllib.parse.urlparse(media_url).hostname or ""
    return media_url, {
        "extractor": "ytInitialPlayerResponse",
        "mediaHost": media_host,
        "itag": selected.get("itag"),
        "mimeType": selected.get("mimeType") or "",
        "bitrate": selected.get("bitrate"),
        "contentLength": selected.get("contentLength") or "",
    }


def extract_youtube_media_url_with_ytdlp(watch_url: str, timeout: float) -> tuple[str, dict[str, Any]]:
    try:
        import yt_dlp  # type: ignore
    except Exception as error:
        raise ValueError("youtube_ytdlp_not_available") from error

    class SilentYtdlpLogger:
        def debug(self, message: str) -> None:
            return None

        def warning(self, message: str) -> None:
            return None

        def error(self, message: str) -> None:
            return None

    options = {
        "quiet": True,
        "no_warnings": True,
        "skip_download": True,
        "noplaylist": True,
        "socket_timeout": timeout,
        "http_headers": {"User-Agent": USER_AGENT},
        "logger": SilentYtdlpLogger(),
    }
    with yt_dlp.YoutubeDL(options) as ydl:
        info = ydl.extract_info(watch_url, download=False)

    if isinstance(info, dict) and "entries" in info:
        entries = info.get("entries") or []
        info = next((entry for entry in entries if isinstance(entry, dict)), info)

    candidates: list[dict[str, Any]] = []
    if isinstance(info, dict):
        for key in ("requested_formats", "formats"):
            values = info.get(key) or []
            if isinstance(values, list):
                candidates.extend(item for item in values if isinstance(item, dict))
        if isinstance(info.get("url"), str):
            candidates.insert(0, info)

    scored: list[tuple[int, str, dict[str, Any]]] = []
    for candidate in candidates:
        media_url = str(candidate.get("url") or "").strip()
        if not media_url:
            continue
        mime_type = str(candidate.get("mime_type") or candidate.get("mimeType") or "")
        ext = str(candidate.get("ext") or "")
        vcodec = str(candidate.get("vcodec") or "")
        acodec = str(candidate.get("acodec") or "")
        score = safe_int(candidate.get("tbr"), 0)
        score += safe_int(candidate.get("height"), 0)
        if vcodec and vcodec != "none":
            score += 10000
        if acodec and acodec != "none":
            score += 1000
        if mime_type.startswith("video/") or ext in {"mp4", "webm"}:
            score += 5000
        scored.append((score, media_url, candidate))

    if not scored:
        raise ValueError("youtube_ytdlp_media_url_not_found")

    scored.sort(key=lambda item: item[0], reverse=True)
    _, media_url, selected = scored[0]
    media_host = urllib.parse.urlparse(media_url).hostname or ""
    return media_url, {
        "extractor": "yt_dlp",
        "mediaHost": media_host,
        "protocol": selected.get("protocol") or "",
        "formatId": selected.get("format_id") or selected.get("formatId") or "",
        "formatNote": selected.get("format_note") or "",
        "ext": selected.get("ext") or "",
        "height": selected.get("height"),
        "tbr": selected.get("tbr"),
        "vcodec": selected.get("vcodec") or "",
        "acodec": selected.get("acodec") or "",
    }


def resolve_hls_media_segment_url(manifest_url: str, timeout: float) -> tuple[str, dict[str, Any]]:
    current_url = manifest_url
    chain: list[dict[str, Any]] = []
    for depth in range(1, 4):
        text, status_code, latency_ms, fetch_details = http_fetch_text(current_url, timeout)
        chain.append(
            {
                "depth": depth,
                "httpStatus": status_code,
                "latencyMs": latency_ms,
                "host": fetch_details.get("finalHost") or urllib.parse.urlparse(current_url).hostname or "",
                "bodyPreviewBytes": fetch_details.get("bodyPreviewBytes"),
            }
        )
        candidate = ""
        for raw_line in text.splitlines():
            line = raw_line.strip()
            if not line or line.startswith("#"):
                continue
            candidate = urllib.parse.urljoin(current_url, line)
            break
        if not candidate:
            raise ValueError("hls_media_segment_not_found")

        candidate_path = urllib.parse.urlparse(candidate).path.lower()
        if candidate_path.endswith(".m3u8") and depth < 3:
            current_url = candidate
            continue

        return candidate, {
            "hlsResolved": True,
            "hlsDepth": depth,
            "hlsManifestHost": urllib.parse.urlparse(manifest_url).hostname or "",
            "hlsSegmentHost": urllib.parse.urlparse(candidate).hostname or "",
            "hlsChain": chain,
        }
    raise ValueError("hls_media_playlist_depth_exceeded")


def media_download_check(url: str, timeout: float, bytes_to_read: int) -> tuple[int, dict[str, Any]]:
    headers = {
        "User-Agent": USER_AGENT,
        "Accept": "*/*",
        "Range": f"bytes=0-{max(0, bytes_to_read - 1)}",
    }
    request = urllib.request.Request(url, headers=headers, method="GET")
    start = time.perf_counter()
    bytes_read = 0
    status_code = 0
    read_error = ""
    response_host = urllib.parse.urlparse(url).hostname or ""
    try:
        with urllib.request.urlopen(request, timeout=timeout) as response:
            status_code = int(response.status)
            response_host = urllib.parse.urlparse(response.geturl()).hostname or response_host
            while bytes_read < bytes_to_read:
                try:
                    chunk = response.read(min(64 * 1024, bytes_to_read - bytes_read))
                except (TimeoutError, OSError) as error:
                    read_error = type(error).__name__
                    break
                if not chunk:
                    break
                bytes_read += len(chunk)
    except urllib.error.HTTPError as error:
        status_code = int(error.code)
        read_error = type(error).__name__
    except (urllib.error.URLError, TimeoutError, OSError) as error:
        read_error = type(error).__name__
    elapsed_ms = max(1, round((time.perf_counter() - start) * 1000))
    throughput_mbps = round((bytes_read * 8) / (elapsed_ms / 1000) / 1_000_000, 3)
    return elapsed_ms, {
        "httpStatus": status_code,
        "bytesRead": bytes_read,
        "requestedBytes": bytes_to_read,
        "elapsedMs": elapsed_ms,
        "throughputMbps": throughput_mbps,
        "mediaHost": response_host,
        "readError": read_error,
        "rangeRequest": True,
    }


def classify_media_probe(download_details: dict[str, Any], green_mbps: float) -> tuple[bool, str, str, str]:
    status_code = safe_int(download_details.get("httpStatus"), 0)
    bytes_read = safe_int(download_details.get("bytesRead"), 0)
    throughput_mbps = float(download_details.get("throughputMbps") or 0)
    http_ok = status_code in {200, 206}
    if not http_ok or bytes_read <= 0:
        return (
            False,
            "red",
            "blocked_or_unreachable",
            "Media endpoint is not reachable, blocked, or returned no bytes.",
        )
    if throughput_mbps >= green_mbps:
        return True, "green", "ok", "Media throughput is healthy."
    return (
        True,
        "yellow",
        "degraded_throughput",
        "Media endpoint is reachable, but throughput is below the green threshold.",
    )


def probe_media_target(
    target: dict[str, Any],
    target_type: str,
    url: str,
    timeout: float,
    details: dict[str, Any],
    total_start: float,
) -> ProbeResult:
    target_id = str(target.get("targetId") or "unknown")
    green_mbps, yellow_mbps, bytes_to_read = media_thresholds(target, target_type)
    details.update(
        {
            "probeKind": "youtube_media_throughput" if target_type == "youtube_media" else "media_throughput",
            "minGreenMbps": green_mbps,
            "minYellowMbps": yellow_mbps,
            "probeBytes": bytes_to_read,
        }
    )
    media_url = url
    youtube_static_fallback_used = False
    try:
        if target_type == "youtube_media":
            watch_url = url or YOUTUBE_MEDIA_TEST_URL
            text, status_code, page_ms, page_details = http_fetch_text(watch_url, timeout)
            page_ok = 200 <= status_code < 400
            details["steps"].append(
                {"name": "youtube_watch_page", "ok": page_ok, "latencyMs": page_ms, **page_details}
            )
            try:
                media_url, media_details = extract_youtube_media_url_with_ytdlp(watch_url, timeout)
            except Exception as extractor_error:
                details["steps"].append(
                    {
                        "name": "youtube_ytdlp_extractor",
                        "ok": False,
                        "errorCode": str(extractor_error),
                        "errorType": type(extractor_error).__name__,
                    }
                )
                try:
                    media_url, media_details = extract_youtube_media_url(text)
                except Exception as player_error:
                    details["steps"].append(
                        {
                            "name": "youtube_player_response_extractor",
                            "ok": False,
                            "errorCode": str(player_error),
                            "errorType": type(player_error).__name__,
                        }
                    )
                    if not YOUTUBE_MEDIA_FALLBACK_URL:
                        raise
                    youtube_static_fallback_used = True
                    media_url = YOUTUBE_MEDIA_FALLBACK_URL
                    media_details = {
                        "extractor": "static_fallback",
                        "mediaHost": urllib.parse.urlparse(YOUTUBE_MEDIA_FALLBACK_URL).hostname or "",
                    }
            media_host = str(media_details.get("mediaHost") or "")
            media_protocol = str(media_details.get("protocol") or "")
            if media_protocol == "m3u8_native" or media_host == "manifest.googlevideo.com":
                try:
                    media_url, hls_details = resolve_hls_media_segment_url(media_url, timeout)
                    media_details.update(hls_details)
                    media_details["mediaHost"] = hls_details.get("hlsSegmentHost") or media_host
                    details["steps"].append(
                        {
                            "name": "youtube_hls_segment_url",
                            "ok": True,
                            "mediaHost": media_details.get("mediaHost") or "",
                            "hlsDepth": hls_details.get("hlsDepth"),
                        }
                    )
                except Exception as hls_error:
                    details["steps"].append(
                        {
                            "name": "youtube_hls_segment_url",
                            "ok": False,
                            "errorCode": str(hls_error),
                            "errorType": type(hls_error).__name__,
                        }
                    )
                    if YOUTUBE_MEDIA_FALLBACK_URL:
                        youtube_static_fallback_used = True
                        media_url = YOUTUBE_MEDIA_FALLBACK_URL
                        media_details = {
                            "extractor": "static_fallback",
                            "mediaHost": urllib.parse.urlparse(YOUTUBE_MEDIA_FALLBACK_URL).hostname or "",
                        }
                    else:
                        raise
            details["media"] = media_details
            details["steps"].append(
                {
                    "name": "youtube_media_url",
                    "ok": True,
                    "extractor": media_details.get("extractor") or "",
                    "mediaHost": media_details.get("mediaHost") or "",
                    "mimeType": media_details.get("mimeType") or "",
                    "formatId": media_details.get("formatId") or media_details.get("itag"),
                }
            )
        media_ms, download_details = media_download_check(media_url, timeout, bytes_to_read)
        ok, status, failure_mode, classification_message = classify_media_probe(
            download_details,
            green_mbps,
        )
        if target_type == "youtube_media" and youtube_static_fallback_used and status != "red":
            ok = True
            status = "yellow"
            failure_mode = "youtube_stream_probe_unavailable"
            classification_message = (
                "Direct YouTube stream probe was unavailable; static YouTube asset fallback is reachable."
            )
        if target_type == "youtube_media" and status == "red" and YOUTUBE_MEDIA_FALLBACK_URL:
            details["primaryMediaDownload"] = dict(download_details)
            details["steps"].append(
                {
                    "name": "youtube_stream_download",
                    "ok": False,
                    "latencyMs": media_ms,
                    "throughputMbps": download_details.get("throughputMbps"),
                    "bytesRead": download_details.get("bytesRead"),
                    "httpStatus": download_details.get("httpStatus"),
                    "mediaHost": download_details.get("mediaHost") or "",
                }
            )
            fallback_ms, fallback_details = media_download_check(
                YOUTUBE_MEDIA_FALLBACK_URL,
                timeout,
                min(bytes_to_read, 256 * 1024),
            )
            fallback_ok, fallback_status, fallback_failure_mode, fallback_message = classify_media_probe(
                fallback_details,
                max(0.5, min(green_mbps, 2.0)),
            )
            details["fallbackMediaDownload"] = dict(fallback_details)
            details["steps"].append(
                {
                    "name": "youtube_static_fallback",
                    "ok": fallback_status != "red",
                    "latencyMs": fallback_ms,
                    "throughputMbps": fallback_details.get("throughputMbps"),
                    "bytesRead": fallback_details.get("bytesRead"),
                    "httpStatus": fallback_details.get("httpStatus"),
                    "mediaHost": fallback_details.get("mediaHost") or "",
                }
            )
            if fallback_status != "red":
                download_details = fallback_details
                ok = bool(fallback_ok)
                status = "yellow"
                failure_mode = "youtube_stream_probe_unavailable"
                classification_message = (
                    "Direct YouTube stream probe was unavailable; static YouTube asset fallback is reachable."
                )
            else:
                failure_mode = fallback_failure_mode
                classification_message = fallback_message
        severity = "normal"
        throughput_mbps = float(download_details.get("throughputMbps") or 0)
        if status == "yellow" and throughput_mbps < yellow_mbps:
            severity = "severe_degradation"
        details.update(download_details)
        details["failureMode"] = failure_mode
        details["severity"] = severity
        details["steps"].append(
            {
                "name": "media_download",
                "ok": status != "red",
                "latencyMs": media_ms,
                "throughputMbps": download_details.get("throughputMbps"),
                "bytesRead": download_details.get("bytesRead"),
                "httpStatus": download_details.get("httpStatus"),
                "mediaHost": download_details.get("mediaHost") or "",
            }
        )
        latency_ms = round((time.perf_counter() - total_start) * 1000)
        message = (
            f"{target.get('title') or target_id}: {classification_message} "
            f"{throughput_mbps:.2f} Mbps, green >= {green_mbps:.2f} Mbps."
        )
        return ProbeResult(
            ok,
            status,
            latency_ms,
            "" if status != "red" else failure_mode,
            message,
            details,
        )
    except Exception as error:
        latency_ms = round((time.perf_counter() - total_start) * 1000)
        error_name = type(error).__name__
        details["failureMode"] = "blocked_or_unreachable"
        details["steps"].append({"name": "media_exception", "ok": False, "errorType": error_name})
        return ProbeResult(
            False,
            "red",
            latency_ms,
            error_name,
            f"{target.get('title') or target_id} media check failed: {error_name}.",
            details,
        )


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


def clean_candidate_value(value: Any, max_len: int = 80) -> str:
    text = str(value or "").strip().lower()
    allowed = []
    for ch in text[:max_len]:
        if ch.isalnum() or ch in {"_", "-", ".", ":"}:
            allowed.append(ch)
    return "".join(allowed)


def parse_route_candidate(raw: str) -> dict[str, str]:
    candidate = dict(DEFAULT_ROUTE_CANDIDATE)
    raw = str(raw or "").strip()
    if not raw:
        return candidate

    if "=" not in raw and raw.count(":") >= 2:
        endpoint_id, protocol, transport, *rest = raw.split(":")
        candidate["endpointId"] = endpoint_id
        candidate["protocol"] = protocol
        candidate["transport"] = transport
        if rest:
            candidate["signalKind"] = rest[0]
    else:
        for part in raw.split(","):
            if "=" not in part:
                continue
            key, value = part.split("=", 1)
            clean_key = key.strip()
            if clean_key in {"endpointId", "endpoint", "endpoint_id"}:
                candidate["endpointId"] = value
            elif clean_key in {"protocol", "protocolCode"}:
                candidate["protocol"] = value
            elif clean_key == "transport":
                candidate["transport"] = value
            elif clean_key in {"signalKind", "signal", "signal_kind"}:
                candidate["signalKind"] = value

    endpoint_id = clean_candidate_value(candidate.get("endpointId"), 120)
    protocol = clean_candidate_value(candidate.get("protocol"), 40)
    transport = clean_candidate_value(candidate.get("transport"), 40)
    signal_kind = clean_candidate_value(candidate.get("signalKind"), 80)
    if protocol not in ALLOWED_ROUTE_PROTOCOLS:
        raise SystemExit(f"Unsupported --route-candidate protocol: {protocol}")
    if transport not in ALLOWED_ROUTE_TRANSPORTS:
        raise SystemExit(f"Unsupported --route-candidate transport: {transport}")
    if not endpoint_id:
        raise SystemExit("--route-candidate endpointId is required")
    return {
        "endpointId": endpoint_id,
        "protocol": protocol,
        "transport": transport,
        "signalKind": signal_kind or DEFAULT_ROUTE_CANDIDATE["signalKind"],
    }


def route_candidates_from_args(args: argparse.Namespace) -> list[dict[str, str]]:
    if not args.route_health:
        return []
    raw_candidates = args.route_candidate or []
    if not raw_candidates:
        return [dict(DEFAULT_ROUTE_CANDIDATE)]
    candidates: list[dict[str, str]] = []
    seen: set[tuple[str, str, str]] = set()
    for raw in raw_candidates:
        candidate = parse_route_candidate(raw)
        key = (
            candidate["endpointId"],
            candidate["protocol"],
            candidate["transport"],
        )
        if key in seen:
            continue
        seen.add(key)
        candidates.append(candidate)
    return candidates


def clean_server_id(value: Any, max_len: int = 120) -> str:
    text = str(value or "").strip()
    allowed = []
    for ch in text[:max_len]:
        if ch.isalnum() or ch in {"_", "-", ".", ":"}:
            allowed.append(ch)
    return "".join(allowed)


def server_health_candidate_entries(
    catalog_payload: dict[str, Any],
    explicit_server_ids: list[str] | None = None,
) -> tuple[list[dict[str, Any]], list[dict[str, Any]]]:
    entries = catalog_payload.get("managedEntries") or []
    explicit_ids = {clean_server_id(item) for item in (explicit_server_ids or [])}
    explicit_ids.discard("")
    seen_explicit_ids: set[str] = set()
    candidates: list[dict[str, Any]] = []
    skipped: list[dict[str, Any]] = []
    for entry in entries:
        server_id = clean_server_id(entry.get("serverId"))
        is_explicit = server_id in explicit_ids
        if is_explicit:
            seen_explicit_ids.add(server_id)
        if not is_explicit and not entry.get("isActive"):
            continue
        if not entry.get("clientConfigReady"):
            if is_explicit:
                skipped.append(
                    {
                        "endpointId": server_id,
                        "status": "skipped",
                        "ok": False,
                        "latencyMs": None,
                        "posted": False,
                        "postError": "client_config_not_ready",
                        "message": "Explicit server-health canary skipped: client config is not ready.",
                    }
                )
            continue
        if str(entry.get("protocol") or "").lower() != "wireguard_udp":
            if is_explicit:
                skipped.append(
                    {
                        "endpointId": server_id,
                        "status": "skipped",
                        "ok": False,
                        "latencyMs": None,
                        "posted": False,
                        "postError": "unsupported_protocol",
                        "message": "Explicit server-health canary skipped: only wireguard_udp is supported.",
                    }
                )
            continue
        host = str(entry.get("host") or "").strip()
        port = safe_int(entry.get("port"), 0)
        if not host or port <= 0:
            if is_explicit:
                skipped.append(
                    {
                        "endpointId": server_id,
                        "status": "skipped",
                        "ok": False,
                        "latencyMs": None,
                        "posted": False,
                        "postError": "missing_endpoint",
                        "message": "Explicit server-health canary skipped: host or port is missing.",
                    }
                )
            continue
        candidate = dict(entry)
        candidate["_serverHealthExplicit"] = is_explicit
        candidates.append(candidate)
    for missing_id in sorted(explicit_ids - seen_explicit_ids):
        skipped.append(
            {
                "endpointId": missing_id,
                "status": "skipped",
                "ok": False,
                "latencyMs": None,
                "posted": False,
                "postError": "server_id_not_found",
                "message": "Explicit server-health canary skipped: server id was not found in the managed catalog.",
            }
        )
    return candidates, skipped


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
            "isActive": bool(entry.get("isActive")),
            "isPublicCandidate": bool(entry.get("isPublic")),
            "isExplicitDraftCanary": bool(entry.get("_serverHealthExplicit")),
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

        if target_type in {"media", "throughput", "youtube_media"}:
            return probe_media_target(target, target_type, url, timeout, details, total_start)

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
    if args.server_health_server_id:
        args.server_health = True
    route_candidates = route_candidates_from_args(args)
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
                    "serverHealthServerIds": args.server_health_server_id,
                    "routeHealthEnabled": bool(args.route_health),
                    "routeCandidates": route_candidates,
                    "stage": "fetch_targets",
                    "errorCode": api_error_code(error),
                    "message": "Could not fetch monitoring targets from backend.",
                    "targetsChecked": 0,
                    "serverHealthChecked": 0,
                    "routeObservationsPosted": 0,
                    "green": 0,
                    "yellow": 0,
                    "red": 0,
                    "unknown": 0,
                    "failedPosts": 0,
                    "serverHealthFailedPosts": 0,
                    "routeObservationFailedPosts": 0,
                    "results": [],
                    "serverHealth": [],
                    "routeHealth": [],
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
    route_health_results: list[dict[str, Any]] = []
    route_observation_failed_posts = 0
    route_observations_posted = 0
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
                post_error = api_error_code(error)
        for route_candidate in route_candidates:
            route_posted = False
            route_post_error = ""
            route_observation = {
                "endpointId": route_candidate["endpointId"],
                "protocol": route_candidate["protocol"],
                "transport": route_candidate["transport"],
                "targetId": target.get("targetId"),
                "service": target.get("service"),
                "probeId": args.probe_id,
                "probeRegion": args.probe_region,
                "ok": result.ok,
                "status": result.status,
                "latencyMs": result.latency_ms,
                "errorCode": result.error_code,
                "message": result.message,
                "details": {
                    "probeMode": route_candidate["signalKind"],
                    "routeSignalKind": "control_plane_reachability",
                    "automationEligible": False,
                    "egressVerified": False,
                    "protocol": route_candidate["protocol"],
                    "transport": route_candidate["transport"],
                    "endpointId": route_candidate["endpointId"],
                    "targetPublicImpact": bool(target.get("publicImpact")),
                    "limitation": (
                        "This observation is route-specific only when the probe host "
                        "is actually configured to send this check through the named "
                        "tunnel/proxy path. Otherwise it is a control-plane reachability "
                        "signal and must not unlock public rollout by itself."
                    ),
                    "serviceProbeDetails": result.details,
                },
                "observedAt": utc_now_iso(),
            }
            if args.dry_run:
                route_posted = False
            else:
                try:
                    api_request(
                        api_base,
                        token,
                        "/api/v1/admin/resilience/route-observations",
                        method="POST",
                        payload=route_observation,
                    )
                    route_posted = True
                    route_observations_posted += 1
                except Exception as error:
                    route_observation_failed_posts += 1
                    route_post_error = api_error_code(error)
            route_health_results.append(
                {
                    "endpointId": route_candidate["endpointId"],
                    "protocol": route_candidate["protocol"],
                    "transport": route_candidate["transport"],
                    "signalKind": route_candidate["signalKind"],
                    "targetId": target.get("targetId"),
                    "status": result.status,
                    "ok": result.ok,
                    "latencyMs": result.latency_ms,
                    "posted": route_posted,
                    "postError": route_post_error,
                }
            )
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
            server_entries, server_health_skipped = server_health_candidate_entries(
                catalog_payload,
                args.server_health_server_id,
            )
            if server_health_skipped:
                server_health_failed_posts += len(server_health_skipped)
                server_health_results.extend(server_health_skipped)
        except Exception as error:
            server_health_failed_posts += 1
            server_health_results.append(
                {
                    "endpointId": "",
                    "status": "unknown",
                    "ok": False,
                    "latencyMs": None,
                    "posted": False,
                    "postError": api_error_code(error),
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
                    post_error = api_error_code(error)
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
        "serverHealthServerIds": args.server_health_server_id,
        "routeHealthEnabled": bool(args.route_health),
        "routeCandidates": route_candidates,
        "targetsChecked": len(results),
        "serverHealthChecked": len(server_health_results),
        "routeHealthChecked": len(route_health_results),
        "routeObservationsPosted": route_observations_posted,
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
        "routeObservationFailedPosts": route_observation_failed_posts,
        "results": results,
        "serverHealth": server_health_results,
        "routeHealth": route_health_results,
    }
    print(json.dumps(summary, ensure_ascii=False, indent=2))
    if (
        args.fail_on_post_error
        and (
            failed_posts > 0
            or server_health_failed_posts > 0
            or route_observation_failed_posts > 0
        )
    ):
        return 2
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
