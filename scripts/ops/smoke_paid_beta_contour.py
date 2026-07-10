#!/usr/bin/env python3
"""Run a non-payment end-to-end smoke against the isolated paid beta contour."""

from __future__ import annotations

import argparse
import json
import os
import pathlib
import secrets
import ssl
import sys
import time
import urllib.error
import urllib.request
from typing import Any, Callable


CLIENT_MARKER = "green-vpn-paid-beta-v1"
RELEASE_CHANNEL = "paid-beta"
APP_VERSION = "0.3.0-paid-beta.2"
EXPECTED_ANDROID_SHA256 = "29252A8AE44BA4487363E669A0ED31DDAC159289A49254EBBED34F123D20AB50"
EXPECTED_WINDOWS_SHA256 = "41F96CB95118507AACA861721F83B2972CF419E2F10BA2FCF38CB73800988332"


class ApiError(RuntimeError):
    def __init__(self, status: int, payload: Any):
        super().__init__(f"HTTP {status}")
        self.status = status
        self.payload = payload


def load_env_file(path: pathlib.Path) -> None:
    for raw in path.read_text(encoding="utf-8").splitlines():
        line = raw.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        os.environ[key.strip()] = value.strip().strip("\"'")


def request_json(
    base_url: str,
    path: str,
    *,
    method: str = "GET",
    payload: dict[str, Any] | None = None,
    headers: dict[str, str] | None = None,
    timeout: int = 30,
) -> dict[str, Any]:
    body = None
    request_headers = {"Accept": "application/json", **(headers or {})}
    if payload is not None:
        body = json.dumps(payload, ensure_ascii=False).encode("utf-8")
        request_headers["Content-Type"] = "application/json"
    request = urllib.request.Request(
        f"{base_url.rstrip('/')}/{path.lstrip('/')}",
        data=body,
        headers=request_headers,
        method=method,
    )
    try:
        with urllib.request.urlopen(
            request,
            timeout=timeout,
            context=ssl.create_default_context(),
        ) as response:
            result = json.load(response)
    except urllib.error.HTTPError as exc:
        try:
            result = json.loads(exc.read().decode("utf-8", errors="replace"))
        except Exception:
            result = {"detail": "non-json error"}
        raise ApiError(exc.code, result) from exc
    if not isinstance(result, dict):
        raise RuntimeError("API returned a non-object JSON payload")
    return result


def poll(
    label: str,
    operation: Callable[[], dict[str, Any]],
    predicate: Callable[[dict[str, Any]], bool] = lambda value: bool(value),
    *,
    timeout_seconds: int = 40,
) -> dict[str, Any]:
    deadline = time.monotonic() + timeout_seconds
    last_status = "not called"
    while time.monotonic() < deadline:
        try:
            value = operation()
            if predicate(value):
                return value
            last_status = "predicate not satisfied"
        except ApiError as exc:
            last_status = f"HTTP {exc.status}"
        except Exception as exc:
            last_status = type(exc).__name__
        time.sleep(1)
    raise RuntimeError(f"{label} timed out: {last_status}")


def bearer(token: str) -> dict[str, str]:
    return {"Authorization": f"Bearer {token}"}


def require(condition: bool, message: str) -> None:
    if not condition:
        raise RuntimeError(message)


def write_context(path: pathlib.Path, values: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(
        json.dumps(values, ensure_ascii=False, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )
    path.chmod(0o600)


def check_update_manifest(base_url: str, platform: str, expected_sha256: str) -> None:
    result = request_json(
        base_url,
        "/api/v1/updates/manifest"
        f"?platform={platform}&channel={RELEASE_CHANNEL}"
        f"&currentVersion={APP_VERSION}&clientId=paid-beta-smoke-update",
    )
    manifest = result.get("manifest") or {}
    require(manifest.get("channel") == RELEASE_CHANNEL, f"{platform} update channel mismatch")
    require(manifest.get("latestVersion") == APP_VERSION, f"{platform} update version mismatch")
    require(manifest.get("sha256") == expected_sha256, f"{platform} update hash mismatch")
    require(bool(manifest.get("fileReady")), f"{platform} update artifact is not ready")
    require(not bool(manifest.get("required")), f"{platform} update must not be forced")
    require("/paid-beta/downloads/" in str(manifest.get("downloadUrl") or ""), f"{platform} update URL is not isolated")


def cleanup_smoke(backend: Any, context_path: pathlib.Path, remove_peer: bool) -> int:
    context = json.loads(context_path.read_text(encoding="utf-8"))
    email = str(context.get("email") or "").strip().lower()
    device_uid = str(context.get("deviceUid") or "").strip()
    invite_id = str(context.get("inviteId") or "").strip()
    require(email.startswith("paid-beta-smoke-") and email.endswith("@example.invalid"), "unsafe smoke email")
    require(device_uid.startswith("paid-beta-smoke-"), "unsafe smoke device uid")

    peer_removed = False
    with backend.db() as conn:
        user = conn.execute("SELECT id FROM users WHERE email = ?", (email,)).fetchone()
        user_id = int(user["id"]) if user is not None else int(context.get("userId") or 0)
        device = conn.execute(
            "SELECT client_public_key FROM devices WHERE device_uid = ? LIMIT 1",
            (device_uid,),
        ).fetchone()
        assignment = conn.execute(
            "SELECT server_id FROM client_endpoint_assignments WHERE device_uid = ? LIMIT 1",
            (device_uid,),
        ).fetchone()

    public_key = str(device["client_public_key"] or "") if device is not None else ""
    server_id = (
        str(assignment["server_id"] or "")
        if assignment is not None
        else str(context.get("serverId") or "")
    )
    if remove_peer and public_key and server_id:
        peer_removed = bool(
            backend.best_effort_remove_peer_from_server(
                server_id,
                device_uid=device_uid,
                public_key=public_key,
            )
        )

    deleted: dict[str, int] = {}
    with backend.db() as conn:
        tables = {
            row["name"]
            for row in conn.execute(
                "SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%'"
            )
        }

        def delete(table: str, where: str, values: tuple[Any, ...]) -> None:
            if table not in tables:
                return
            cursor = conn.execute(f"DELETE FROM {table} WHERE {where}", values)
            deleted[table] = deleted.get(table, 0) + max(0, int(cursor.rowcount or 0))

        if user_id:
            if "support_report_comments" in tables and "support_reports" in tables:
                delete(
                    "support_report_comments",
                    "report_id IN (SELECT id FROM support_reports WHERE user_id = ?)",
                    (user_id,),
                )
            for table in (
                "beta_funnel_events",
                "beta_invite_redemptions",
                "client_route_events",
                "client_endpoint_assignments",
                "device_traffic_usage",
                "ad_challenges",
                "free_access_grants",
                "promo_redemptions",
                "admin_support_actions",
                "subscription_expiry_reviews",
                "billing_orders",
                "support_reports",
                "sms_outbox",
                "email_login_codes",
                "phone_confirmations",
                "email_confirmations",
                "email_outbox",
                "auth_events",
                "tokens",
                "subscriptions",
                "devices",
            ):
                if table in tables:
                    columns = {
                        row["name"] for row in conn.execute(f"PRAGMA table_info({table})")
                    }
                    if "user_id" in columns:
                        delete(table, "user_id = ?", (user_id,))
            delete("users", "id = ?", (user_id,))
        delete("devices", "device_uid = ?", (device_uid,))
        delete("client_endpoint_assignments", "device_uid = ?", (device_uid,))
        delete("device_traffic_usage", "device_uid = ?", (device_uid,))
        if invite_id:
            delete("beta_funnel_events", "invite_public_id = ?", (invite_id,))
            delete("beta_invite_redemptions", "invite_public_id = ?", (invite_id,))
            delete("beta_invites", "public_id = ?", (invite_id,))
            delete(
                "admin_audit_log",
                "action = 'paid_beta_invites_created' AND details_json LIKE ?",
                (f"%{invite_id}%",),
            )
        conn.commit()

        remaining_user = conn.execute(
            "SELECT COUNT(*) FROM users WHERE email = ?",
            (email,),
        ).fetchone()[0]
        remaining_device = conn.execute(
            "SELECT COUNT(*) FROM devices WHERE device_uid = ?",
            (device_uid,),
        ).fetchone()[0]
        remaining_invite = (
            conn.execute(
                "SELECT COUNT(*) FROM beta_invites WHERE public_id = ?",
                (invite_id,),
            ).fetchone()[0]
            if invite_id
            else 0
        )
    require(not remaining_user and not remaining_device and not remaining_invite, "smoke cleanup incomplete")

    context["cleaned"] = True
    context["cleanedAt"] = backend.utc_now_iso()
    context["peerRemoved"] = peer_removed
    write_context(context_path, context)
    print(
        json.dumps(
            {
                "ok": True,
                "cleaned": True,
                "email": email,
                "deviceUid": device_uid,
                "inviteId": invite_id,
                "peerRemovalRequested": remove_peer,
                "peerRemoved": peer_removed,
                "deletedRows": sum(deleted.values()),
            },
            ensure_ascii=False,
            sort_keys=True,
        )
    )
    return 0


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--primary")
    parser.add_argument("--fallback")
    parser.add_argument("--backend-dir", required=True)
    parser.add_argument("--env-file", required=True)
    parser.add_argument("--admin-token-file")
    parser.add_argument("--context-out", required=True)
    parser.add_argument("--cleanup", action="store_true")
    parser.add_argument("--remove-peer", action="store_true")
    args = parser.parse_args()

    backend_dir = pathlib.Path(args.backend_dir).resolve()
    env_file = pathlib.Path(args.env_file).resolve()
    context_path = pathlib.Path(args.context_out).resolve()
    load_env_file(env_file)
    sys.path.insert(0, str(backend_dir))
    os.chdir(backend_dir)
    from app import main as backend  # type: ignore

    backend.init_db()
    if args.cleanup:
        return cleanup_smoke(backend, context_path, args.remove_peer)

    if not args.primary or not args.fallback or not args.admin_token_file:
        raise SystemExit("smoke mode requires --primary, --fallback and --admin-token-file")
    primary = args.primary.rstrip("/")
    fallback = args.fallback.rstrip("/")
    for label, value in (("primary", primary), ("fallback", fallback)):
        if not value.startswith("https://") or "/paid-beta-api" not in value:
            raise SystemExit(f"{label} must be an isolated HTTPS /paid-beta-api URL")
    if primary == fallback:
        raise SystemExit("primary and fallback must differ")
    admin_token_file = pathlib.Path(args.admin_token_file).resolve()

    stamp = int(time.time())
    email = f"paid-beta-smoke-{stamp}@example.invalid"
    password = secrets.token_urlsafe(24)
    device_uid = f"paid-beta-smoke-{stamp}"
    now = backend.utc_now_iso()
    with backend.db() as conn:
        cursor = conn.execute(
            "INSERT INTO users(email, password_hash, created_at, updated_at) VALUES (?, ?, ?, ?)",
            (email, backend.hash_password(password), now, now),
        )
        user_id = int(cursor.lastrowid)
        backend.create_trial_subscription(conn, user_id)
        conn.commit()

    context: dict[str, Any] = {
        "createdAt": now,
        "email": email,
        "userId": user_id,
        "deviceUid": device_uid,
        "inviteId": None,
        "assignedIp": None,
        "serverId": None,
        "completed": False,
    }
    write_context(context_path, context)

    admin_token = admin_token_file.read_text(encoding="utf-8").strip()
    require(len(admin_token) >= 24, "beta admin token is not ready")
    admin_headers = {"X-Admin-Token": admin_token}

    check_update_manifest(primary, "android", EXPECTED_ANDROID_SHA256)
    check_update_manifest(primary, "windows", EXPECTED_WINDOWS_SHA256)
    check_update_manifest(fallback, "android", EXPECTED_ANDROID_SHA256)
    check_update_manifest(fallback, "windows", EXPECTED_WINDOWS_SHA256)

    login_payload = {"email": email, "password": password}
    primary_login = request_json(primary, "/api/v1/auth/login", method="POST", payload=login_payload)
    primary_token = str(primary_login.get("accessToken") or primary_login.get("token") or "")
    require(len(primary_token) >= 24, "primary login did not return a token")

    bootstrap_payload = {
        "deviceUid": device_uid,
        "deviceName": "Paid beta smoke",
        "platform": "android",
        "appVersion": APP_VERSION,
        "releaseChannel": RELEASE_CHANNEL,
        "clientMarker": CLIENT_MARKER,
    }
    denied = request_json(
        primary,
        "/api/v1/client/bootstrap",
        method="POST",
        payload=bootstrap_payload,
        headers=bearer(primary_token),
    )
    require(not bool(denied.get("canConnect")), "non-cohort beta user was allowed")
    require(denied.get("reason") == "beta_cohort_required", "non-cohort denial reason mismatch")

    fallback_login = poll(
        "fallback password login sync",
        lambda: request_json(fallback, "/api/v1/auth/login", method="POST", payload=login_payload),
        lambda value: bool(value.get("accessToken") or value.get("token")),
    )
    fallback_token = str(fallback_login.get("accessToken") or fallback_login.get("token") or "")
    require(len(fallback_token) >= 24, "fallback login did not return a token")
    poll(
        "primary token sync to fallback",
        lambda: request_json(
            fallback,
            "/api/v1/subscription/me",
            headers=bearer(primary_token),
        ),
        lambda value: value.get("accessCohort") == "stable",
    )

    invite_response = request_json(
        primary,
        "/api/v1/admin/paid-beta/invites/batch",
        method="POST",
        payload={
            "count": 1,
            "labelPrefix": "smoke",
            "source": "smoke-test",
            "maxUses": 1,
        },
        headers=admin_headers,
    )
    invites = invite_response.get("invites") or []
    require(len(invites) == 1, "admin invite creation did not return one code")
    invite_code = str(invites[0].get("code") or "")
    invite_id = str(invites[0].get("inviteId") or "")
    require(invite_code.startswith("GREEN-"), "admin invite code format mismatch")
    require(bool(invite_id), "admin invite id missing")
    context["inviteId"] = invite_id
    write_context(context_path, context)

    claim_payload = {
        "code": invite_code,
        "deviceUid": device_uid,
        "platform": "android",
        "appVersion": APP_VERSION,
        "clientMarker": CLIENT_MARKER,
        "releaseChannel": RELEASE_CHANNEL,
    }
    claim = request_json(
        primary,
        "/api/v1/paid-beta/invite/claim",
        method="POST",
        payload=claim_payload,
        headers=bearer(primary_token),
    )
    require(claim.get("accessCohort") == "paid_beta_v1", "invite did not enroll paid beta cohort")
    require((claim.get("subscription") or {}).get("maxDevices") == 2, "beta claim device limit mismatch")

    tariff_payload = {
        "devices": 5,
        "dedicatedIp": True,
        "autoRenew": True,
        "clientMarker": CLIENT_MARKER,
        "releaseChannel": RELEASE_CHANNEL,
    }
    quote_result = request_json(
        primary,
        "/api/v1/subscription/quote",
        method="POST",
        payload=tariff_payload,
        headers=bearer(primary_token),
    )
    quote = quote_result.get("quote") or {}
    selection = quote_result.get("selection") or {}
    require(quote.get("monthlyPriceRub") == 149, "invite quote is not 149 RUB")
    require(bool(quote.get("inviteApplied")), "invite discount was not applied")
    require(quote.get("includedDevices") == 2, "quote device limit mismatch")
    require(not bool(quote.get("adsEnabled")), "ads are enabled in paid beta quote")
    require(selection.get("devices") == 2, "unsupported device count was not normalized")
    require(not bool(selection.get("dedicatedIp")), "dedicated IP was not removed")
    require(not bool(selection.get("autoRenew")), "auto-renew was not disabled")

    event_payload = {
        "eventType": "app_open",
        "deviceUid": device_uid,
        "platform": "android",
        "appVersion": APP_VERSION,
        "clientMarker": CLIENT_MARKER,
        "releaseChannel": RELEASE_CHANNEL,
    }
    request_json(
        primary,
        "/api/v1/paid-beta/events",
        method="POST",
        payload=event_payload,
        headers=bearer(primary_token),
    )

    primary_bootstrap = request_json(
        primary,
        "/api/v1/client/bootstrap",
        method="POST",
        payload=bootstrap_payload,
        headers=bearer(primary_token),
    )
    require(bool(primary_bootstrap.get("canConnect")), "primary beta bootstrap denied enrolled user")
    require(not bool((primary_bootstrap.get("adGate") or {}).get("enabled")), "primary beta ads are enabled")
    require(not bool((primary_bootstrap.get("adGate") or {}).get("sessionTimerEnabled")), "primary beta timer is enabled")

    fallback_bootstrap = poll(
        "cohort and trial sync to fallback",
        lambda: request_json(
            fallback,
            "/api/v1/client/bootstrap",
            method="POST",
            payload=bootstrap_payload,
            headers=bearer(primary_token),
        ),
        lambda value: bool(value.get("canConnect")),
    )
    require(not bool((fallback_bootstrap.get("adGate") or {}).get("enabled")), "fallback beta ads are enabled")
    require(not bool((fallback_bootstrap.get("adGate") or {}).get("sessionTimerEnabled")), "fallback beta timer is enabled")

    config_payload = {
        "deviceUid": device_uid,
        "mode": "full",
        "serverId": "auto",
        "releaseChannel": RELEASE_CHANNEL,
        "clientMarker": CLIENT_MARKER,
    }
    primary_config = request_json(
        primary,
        "/api/v1/client/config",
        method="POST",
        payload=config_payload,
        headers=bearer(primary_token),
        timeout=45,
    )
    assigned_ip = str(primary_config.get("assignedIp") or "")
    server_id = str(primary_config.get("serverId") or "")
    require(assigned_ip.startswith("10.10.0."), "primary config returned an unexpected IP")
    host_octet = int(assigned_ip.rsplit(".", 1)[1])
    require(180 <= host_octet <= 229, "primary config escaped the reserved beta IP range")
    require(bool(server_id), "primary config server id missing")
    require("[Interface]" in str(primary_config.get("configText") or ""), "primary config body missing")
    context["assignedIp"] = assigned_ip
    context["serverId"] = server_id
    write_context(context_path, context)

    # Let the primary device keys reach fallback before asking fallback to provision.
    time.sleep(15)
    fallback_config = poll(
        "device config sync to fallback",
        lambda: request_json(
            fallback,
            "/api/v1/client/config",
            method="POST",
            payload=config_payload,
            headers=bearer(primary_token),
            timeout=45,
        ),
        lambda value: value.get("assignedIp") == assigned_ip,
        timeout_seconds=50,
    )
    require(fallback_config.get("serverId") == server_id, "fallback changed the sticky server assignment")
    require(
        fallback_config.get("configText") == primary_config.get("configText"),
        "fallback did not preserve the synced device key material",
    )

    event_payload["eventType"] = "vpn_connected"
    request_json(
        fallback,
        "/api/v1/paid-beta/events",
        method="POST",
        payload=event_payload,
        headers=bearer(fallback_token),
    )
    funnel = poll(
        "fallback funnel event sync to primary",
        lambda: request_json(
            primary,
            "/api/v1/admin/paid-beta/funnel?limit=50",
            headers=admin_headers,
        ),
        lambda value: (value.get("stages") or {}).get("vpnConnectedUsers", 0) >= 1,
    )
    require((funnel.get("stages") or {}).get("claimedUsers", 0) >= 1, "funnel claim stage missing")

    context["completed"] = True
    write_context(context_path, context)
    print(
        json.dumps(
            {
                "ok": True,
                "email": email,
                "userId": user_id,
                "inviteId": invite_id,
                "assignedIp": assigned_ip,
                "serverId": server_id,
                "quoteRub": quote.get("monthlyPriceRub"),
                "maxDevices": quote.get("includedDevices"),
                "adsEnabled": quote.get("adsEnabled"),
                "sessionTimerEnabled": (primary_bootstrap.get("adGate") or {}).get("sessionTimerEnabled"),
                "primaryBootstrap": bool(primary_bootstrap.get("canConnect")),
                "fallbackBootstrap": bool(fallback_bootstrap.get("canConnect")),
                "fallbackConfig": fallback_config.get("assignedIp") == assigned_ip,
                "contextPath": str(context_path),
            },
            ensure_ascii=False,
            sort_keys=True,
        )
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
