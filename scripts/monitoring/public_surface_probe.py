#!/usr/bin/env python3
"""Secretless external checks for the public Green VPN surface."""

from __future__ import annotations

import argparse
import json
import sys
import time
import urllib.error
import urllib.request
from dataclasses import asdict, dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


USER_AGENT = "GreenVPN-PublicSurfaceProbe/1.0"
DEFAULT_TIMEOUT_SECONDS = 15.0


@dataclass(frozen=True)
class Target:
    target_id: str
    url: str
    kind: str
    minimum_bytes: int = 1
    markers: tuple[str, ...] = ()


@dataclass
class Result:
    target_id: str
    url: str
    ok: bool
    status_code: int | None
    latency_ms: int
    size_bytes: int
    error: str


TARGETS = (
    Target("production_api", "https://api.greenvpn.pro/healthz", "health_json"),
    Target(
        "paid_api_primary",
        "https://api.greenvpn.pro/paid-beta-api/healthz",
        "health_json",
    ),
    Target(
        "paid_api_fallback",
        "https://176-113-81-35.sslip.io/paid-beta-api/healthz",
        "health_json",
    ),
    Target("public_site", "https://greenvpn.pro/", "html", 2_000, ("Green VPN",)),
    Target(
        "public_privacy",
        "https://greenvpn.pro/privacy/",
        "html",
        2_000,
        ("Green VPN", "конфиденциаль"),
    ),
    Target(
        "main_legal_requisites",
        "https://greenvpn.pro/legal/requisites",
        "html",
        2_000,
        ("Green VPN", "Реквизиты"),
    ),
    Target(
        "main_legal_offer",
        "https://greenvpn.pro/legal/offer",
        "html",
        2_000,
        ("Green VPN", "оферт"),
    ),
    Target(
        "main_legal_privacy",
        "https://greenvpn.pro/legal/privacy",
        "html",
        2_000,
        ("Green VPN", "конфиденциаль"),
    ),
    Target(
        "main_legal_acceptable_use",
        "https://greenvpn.pro/legal/acceptable-use",
        "html",
        2_000,
        ("Green VPN", "использован"),
    ),
    Target(
        "main_legal_refunds",
        "https://greenvpn.pro/legal/refunds",
        "html",
        2_000,
        ("Green VPN", "Возврат"),
    ),
    Target(
        "legal_requisites",
        "https://api.greenvpn.pro/legal/requisites",
        "html",
        2_000,
        ("Green VPN", "Реквизиты"),
    ),
    Target(
        "legal_offer",
        "https://api.greenvpn.pro/legal/offer",
        "html",
        2_000,
        ("Green VPN", "оферт"),
    ),
    Target(
        "legal_privacy",
        "https://api.greenvpn.pro/legal/privacy",
        "html",
        2_000,
        ("Green VPN", "конфиденциаль"),
    ),
    Target(
        "legal_acceptable_use",
        "https://api.greenvpn.pro/legal/acceptable-use",
        "html",
        2_000,
        ("Green VPN", "использован"),
    ),
    Target(
        "legal_refunds",
        "https://api.greenvpn.pro/legal/refunds",
        "html",
        2_000,
        ("Green VPN", "Возврат"),
    ),
    Target(
        "windows_download",
        "https://greenvpn.pro/downloads/GreenVPN_Setup.exe",
        "download",
        5_000_000,
    ),
    Target(
        "android_download",
        "https://greenvpn.pro/downloads/GreenVPN_Android.apk",
        "download",
        10_000_000,
    ),
    Target(
        "fallback_public_site",
        "https://176-113-81-35.sslip.io/",
        "html",
        2_000,
        ("Green VPN",),
    ),
    Target(
        "fallback_windows_download",
        "https://176-113-81-35.sslip.io/downloads/GreenVPN_Setup.exe",
        "download",
        5_000_000,
    ),
    Target(
        "fallback_android_download",
        "https://176-113-81-35.sslip.io/downloads/GreenVPN_Android.apk",
        "download",
        10_000_000,
    ),
    Target(
        "android_update_primary",
        "https://api.greenvpn.pro/api/v1/updates/manifest?platform=android&currentVersion=0.0.0&channel=stable&deviceId=public-probe",
        "update_manifest",
        300,
        ("android",),
    ),
    Target(
        "android_update_fallback",
        "https://176-113-81-35.sslip.io/api/v1/updates/manifest?platform=android&currentVersion=0.0.0&channel=stable&deviceId=public-probe",
        "update_manifest",
        300,
        ("android",),
    ),
    Target(
        "windows_update_primary",
        "https://api.greenvpn.pro/api/v1/updates/manifest?platform=windows&currentVersion=0.0.0&channel=stable&deviceId=public-probe",
        "update_manifest",
        300,
        ("windows",),
    ),
    Target(
        "windows_update_fallback",
        "https://176-113-81-35.sslip.io/api/v1/updates/manifest?platform=windows&currentVersion=0.0.0&channel=stable&deviceId=public-probe",
        "update_manifest",
        300,
        ("windows",),
    ),
    Target(
        "paid_site_primary",
        "https://greenvpn.pro/paid-beta/",
        "html",
        2_000,
        ("Green VPN",),
    ),
    Target(
        "paid_site_fallback",
        "https://176-113-81-35.sslip.io/paid-beta/",
        "html",
        2_000,
        ("Green VPN",),
    ),
    Target(
        "paid_terms",
        "https://greenvpn.pro/paid-beta/terms/",
        "html",
        2_000,
        ("Green VPN", "Условия"),
    ),
    Target(
        "paid_privacy",
        "https://greenvpn.pro/paid-beta/privacy/",
        "html",
        2_000,
        ("Green VPN", "конфиденциаль"),
    ),
    Target(
        "paid_download_manifest",
        "https://greenvpn.pro/paid-beta/downloads/manifest.json",
        "paid_manifest",
        300,
    ),
    Target(
        "paid_windows_download",
        "https://greenvpn.pro/paid-beta/downloads/GreenVPN_Setup.exe",
        "download",
        5_000_000,
    ),
    Target(
        "paid_android_download",
        "https://greenvpn.pro/paid-beta/downloads/GreenVPN_Android.apk",
        "download",
        10_000_000,
    ),
)


def utc_now() -> str:
    return datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")


def validate_payload(target: Target, payload: bytes) -> None:
    if len(payload) < target.minimum_bytes:
        raise ValueError(f"body_too_small:{len(payload)}<{target.minimum_bytes}")
    if target.kind == "health_json":
        data = json.loads(payload.decode("utf-8"))
        if data.get("ok") is not True:
            raise ValueError("health_not_ok")
        if data.get("service") != "Green VPN Backend":
            raise ValueError("unexpected_health_service")
        return
    if target.kind == "paid_manifest":
        data = json.loads(payload.decode("utf-8-sig"))
        if data.get("channel") != "paid-beta" or data.get("isolated") is not True:
            raise ValueError("unexpected_paid_manifest_identity")
        artifacts = data.get("artifacts")
        if not isinstance(artifacts, list):
            raise ValueError("paid_manifest_artifacts_missing")
        platforms = {str(item.get("platform")) for item in artifacts if isinstance(item, dict)}
        if platforms != {"android", "windows"}:
            raise ValueError("paid_manifest_platforms_invalid")
        for item in artifacts:
            if not isinstance(item, dict):
                raise ValueError("paid_manifest_artifact_invalid")
            if int(item.get("sizeBytes") or 0) <= 0:
                raise ValueError("paid_manifest_size_invalid")
            digest = str(item.get("sha256") or "")
            if len(digest) != 64 or any(char not in "0123456789abcdefABCDEF" for char in digest):
                raise ValueError("paid_manifest_sha256_invalid")
        return
    if target.kind == "update_manifest":
        data = json.loads(payload.decode("utf-8"))
        manifest = data.get("manifest") if isinstance(data, dict) else None
        if not isinstance(data, dict) or data.get("ok") is not True or not isinstance(manifest, dict):
            raise ValueError("update_manifest_missing")
        expected_platform = target.markers[0] if target.markers else ""
        if manifest.get("platform") != expected_platform or manifest.get("channel") != "stable":
            raise ValueError("update_manifest_identity_invalid")
        if not str(manifest.get("latestVersion") or "").strip():
            raise ValueError("update_manifest_version_missing")
        download_url = str(manifest.get("downloadUrl") or "")
        if not download_url.startswith("https://"):
            raise ValueError("update_manifest_download_url_invalid")
        digest = str(manifest.get("sha256") or "")
        if len(digest) != 64 or any(char not in "0123456789abcdefABCDEF" for char in digest):
            raise ValueError("update_manifest_sha256_invalid")
        if manifest.get("fileReady") is not True or manifest.get("releaseBlocked") is True:
            raise ValueError("update_manifest_release_not_ready")
        return
    text = payload.decode("utf-8", errors="replace").casefold()
    for marker in target.markers:
        if marker.casefold() not in text:
            raise ValueError(f"marker_missing:{marker}")


def request_once(target: Target, timeout: float) -> tuple[int, int]:
    method = "HEAD" if target.kind == "download" else "GET"
    request = urllib.request.Request(
        target.url,
        method=method,
        headers={"User-Agent": USER_AGENT, "Accept": "*/*"},
    )
    with urllib.request.urlopen(request, timeout=timeout) as response:
        status_code = int(response.status)
        if status_code != 200:
            raise ValueError(f"unexpected_http_status:{status_code}")
        if target.kind == "download":
            raw_length = response.headers.get("Content-Length")
            size_bytes = int(raw_length or 0)
            if size_bytes < target.minimum_bytes:
                raise ValueError(f"download_too_small:{size_bytes}<{target.minimum_bytes}")
            return status_code, size_bytes
        payload = response.read(512_000)
        validate_payload(target, payload)
        return status_code, len(payload)


def check_target(target: Target, timeout: float, attempts: int) -> Result:
    started = time.perf_counter()
    last_error = ""
    status_code: int | None = None
    size_bytes = 0
    for attempt in range(1, attempts + 1):
        try:
            status_code, size_bytes = request_once(target, timeout)
            return Result(
                target.target_id,
                target.url,
                True,
                status_code,
                round((time.perf_counter() - started) * 1_000),
                size_bytes,
                "",
            )
        except urllib.error.HTTPError as error:
            status_code = int(error.code)
            last_error = f"HTTPError:{error.code}"
        except Exception as error:  # The report intentionally stores only the error type/message.
            last_error = f"{type(error).__name__}:{error}"
        if attempt < attempts:
            time.sleep(min(attempt, 2))
    return Result(
        target.target_id,
        target.url,
        False,
        status_code,
        round((time.perf_counter() - started) * 1_000),
        size_bytes,
        last_error[:300],
    )


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--timeout", type=float, default=DEFAULT_TIMEOUT_SECONDS)
    parser.add_argument("--attempts", type=int, default=3)
    parser.add_argument("--report", type=Path)
    parser.add_argument("--target", action="append", default=[])
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    selected = tuple(target for target in TARGETS if not args.target or target.target_id in args.target)
    unknown = sorted(set(args.target) - {target.target_id for target in TARGETS})
    if unknown:
        raise SystemExit(f"Unknown target ids: {', '.join(unknown)}")
    results = [check_target(target, max(1.0, args.timeout), max(1, args.attempts)) for target in selected]
    failures = [result for result in results if not result.ok]
    report: dict[str, Any] = {
        "ok": not failures,
        "checkedAt": utc_now(),
        "checked": len(results),
        "failed": len(failures),
        "results": [asdict(result) for result in results],
    }
    rendered = json.dumps(report, ensure_ascii=False, indent=2)
    print(rendered)
    if args.report:
        args.report.parent.mkdir(parents=True, exist_ok=True)
        args.report.write_text(rendered + "\n", encoding="utf-8")
    return 0 if not failures else 1


if __name__ == "__main__":
    sys.exit(main())
