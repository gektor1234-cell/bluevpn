#!/usr/bin/env python3
"""Create or clean up an isolated free-tier user for a physical paid-beta smoke."""

from __future__ import annotations

import argparse
import json
import os
import pathlib
import secrets
import string
import sys
import time
from typing import Any


EMAIL_PREFIX = "paid-beta-free-physical-"
EMAIL_SUFFIX = "@example.invalid"


def load_env_file(path: pathlib.Path) -> None:
    for raw in path.read_text(encoding="utf-8").splitlines():
        line = raw.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        os.environ[key.strip()] = value.strip().strip("\"'")


def write_private_json(path: pathlib.Path, value: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_name(path.name + ".tmp")
    temporary.write_text(
        json.dumps(value, ensure_ascii=False, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )
    temporary.chmod(0o600)
    temporary.replace(path)
    path.chmod(0o600)


def require_safe_email(email: str) -> None:
    if not (email.startswith(EMAIL_PREFIX) and email.endswith(EMAIL_SUFFIX)):
        raise RuntimeError("Refusing to manage a user outside the physical-smoke namespace.")


def create_smoke_user(backend: Any, context_path: pathlib.Path) -> int:
    if context_path.exists():
        raise RuntimeError("Context already exists; clean it up or choose another path.")

    stamp = int(time.time())
    suffix = secrets.token_hex(4)
    email = f"{EMAIL_PREFIX}{stamp}-{suffix}{EMAIL_SUFFIX}"
    password_alphabet = string.ascii_letters + string.digits
    password = "".join(secrets.choice(password_alphabet) for _ in range(28))
    now = backend.utc_now_iso()

    with backend.db() as conn:
        cursor = conn.execute(
            """
            INSERT INTO users(
                email,
                password_hash,
                email_verified,
                email_verified_at,
                access_cohort,
                acquisition_source,
                cohort_enrolled_at,
                created_at,
                updated_at
            )
            VALUES (?, ?, 1, ?, ?, ?, ?, ?, ?)
            """,
            (
                email,
                backend.hash_password(password),
                now,
                backend.PAID_BETA_COHORT_CODE,
                "physical-release-smoke",
                now,
                now,
                now,
            ),
        )
        user_id = int(cursor.lastrowid)
        backend.create_trial_subscription(conn, user_id)
        conn.execute(
            """
            UPDATE subscriptions
            SET is_active = 0,
                expires_at = ?,
                updated_at = ?
            WHERE user_id = ?
            """,
            (now, now, user_id),
        )
        subscription_count = int(
            conn.execute(
                "SELECT COUNT(*) FROM subscriptions WHERE user_id = ?",
                (user_id,),
            ).fetchone()[0]
        )
        conn.commit()

    if subscription_count != 1:
        raise RuntimeError(
            "Physical smoke user must have exactly one expired trial subscription."
        )

    write_private_json(
        context_path,
        {
            "contour": "paid-beta",
            "createdAt": now,
            "email": email,
            "password": password,
            "userId": user_id,
            "accessCohort": backend.PAID_BETA_COHORT_CODE,
            "subscriptionCount": subscription_count,
            "cleaned": False,
        },
    )
    print(
        json.dumps(
            {
                "ok": True,
                "action": "created",
                "userId": user_id,
                "subscriptionCount": subscription_count,
                "contextPath": str(context_path),
            },
            sort_keys=True,
        )
    )
    return 0


def prepare_free_tier(backend: Any, context_path: pathlib.Path) -> int:
    context = json.loads(context_path.read_text(encoding="utf-8"))
    email = str(context.get("email") or "").strip().lower()
    user_id = int(context.get("userId") or 0)
    require_safe_email(email)
    if user_id <= 0:
        raise RuntimeError("Context does not contain a valid user id.")

    now = backend.utc_now_iso()
    with backend.db() as conn:
        user = conn.execute(
            "SELECT id, email, access_cohort FROM users WHERE id = ?",
            (user_id,),
        ).fetchone()
        if user is None or str(user["email"] or "").strip().lower() != email:
            raise RuntimeError("Context user does not exist or no longer matches.")
        row = conn.execute(
            "SELECT id FROM subscriptions WHERE user_id = ? ORDER BY id DESC LIMIT 1",
            (user_id,),
        ).fetchone()
        if row is None:
            backend.create_trial_subscription(conn, user_id)
        conn.execute(
            """
            UPDATE subscriptions
            SET is_active = 0,
                expires_at = ?,
                updated_at = ?
            WHERE id = (
                SELECT id
                FROM subscriptions
                WHERE user_id = ?
                ORDER BY id DESC
                LIMIT 1
            )
            """,
            (now, now, user_id),
        )
        conn.commit()

    raw_sub = backend.subscription_status(backend.get_subscription_row(user_id))
    effective_sub = backend.effective_client_subscription(user, raw_sub)
    if not effective_sub.get("isFreeTier"):
        raise RuntimeError("User did not transition to the paid-beta free tier.")

    context["preparedFreeTierAt"] = now
    context["expectedPlanCode"] = backend.FREE_TIER_PLAN_CODE
    context["subscriptionCount"] = 1
    write_private_json(context_path, context)
    print(
        json.dumps(
            {
                "ok": True,
                "action": "prepared-free-tier",
                "userId": user_id,
                "planCode": effective_sub.get("planCode"),
                "quotaEnforced": (effective_sub.get("freeTier") or {}).get(
                    "quotaEnforced"
                ),
                "speedSustainedMbps": effective_sub.get("speedSustainedMbps"),
                "maxDevices": effective_sub.get("maxDevices"),
            },
            sort_keys=True,
        )
    )
    return 0


def cleanup_smoke_user(backend: Any, context_path: pathlib.Path) -> int:
    context = json.loads(context_path.read_text(encoding="utf-8"))
    email = str(context.get("email") or "").strip().lower()
    user_id = int(context.get("userId") or 0)
    require_safe_email(email)
    if user_id <= 0:
        raise RuntimeError("Context does not contain a valid user id.")

    with backend.db() as conn:
        user = conn.execute(
            "SELECT id, email FROM users WHERE id = ?",
            (user_id,),
        ).fetchone()
    if user is not None and str(user["email"] or "").strip().lower() != email:
        raise RuntimeError("Context user id no longer matches the smoke email.")

    result: dict[str, Any] | None = None
    if user is not None:
        with backend.db() as conn:
            devices = conn.execute(
                """
                SELECT device_uid, client_public_key
                FROM devices
                WHERE user_id = ?
                """,
                (user_id,),
            ).fetchall()
        server_ids = {"current_wg0", "intelligent_smew"}
        for entry in backend.list_managed_server_catalog_entries(limit=500):
            server_id = str(entry.get("serverId") or "").strip()
            if server_id:
                server_ids.add(server_id)
        broad_peer_cleanup = {"attempted": 0, "removed": 0}
        for device in devices:
            public_key = str(device["client_public_key"] or "").strip()
            if not public_key:
                continue
            for server_id in sorted(server_ids):
                broad_peer_cleanup["attempted"] += 1
                if backend.best_effort_remove_peer_from_server(
                    server_id,
                    device_uid=str(device["device_uid"]),
                    public_key=public_key,
                ):
                    broad_peer_cleanup["removed"] += 1
        result = backend.delete_admin_user_record(
            user_id,
            backend.AdminUserDeleteIn(
                reason="Physical paid-beta smoke cleanup",
                confirmEmail=email,
            ),
        )
        result["broadPeerCleanup"] = broad_peer_cleanup

    with backend.db() as conn:
        remaining = int(
            conn.execute(
                "SELECT COUNT(*) FROM users WHERE id = ? OR email = ?",
                (user_id, email),
            ).fetchone()[0]
        )
    if remaining:
        raise RuntimeError("Physical smoke cleanup did not remove the user.")

    write_private_json(
        context_path,
        {
            "contour": "paid-beta",
            "createdAt": context.get("createdAt"),
            "cleanedAt": backend.utc_now_iso(),
            "userId": user_id,
            "cleaned": True,
            "credentialsRemoved": True,
            "peerCleanup": (result or {}).get("peerCleanup") or {},
            "broadPeerCleanup": (result or {}).get("broadPeerCleanup") or {},
        },
    )
    print(
        json.dumps(
            {
                "ok": True,
                "action": "cleaned",
                "userId": user_id,
                "peerCleanup": (result or {}).get("peerCleanup") or {},
                "broadPeerCleanup": (result or {}).get("broadPeerCleanup") or {},
                "contextPath": str(context_path),
            },
            sort_keys=True,
        )
    )
    return 0


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--backend-dir", required=True)
    parser.add_argument("--env-file", required=True)
    parser.add_argument("--context-out", required=True)
    parser.add_argument("--cleanup", action="store_true")
    parser.add_argument("--prepare-free", action="store_true")
    args = parser.parse_args()

    backend_dir = pathlib.Path(args.backend_dir).resolve()
    env_file = pathlib.Path(args.env_file).resolve()
    context_path = pathlib.Path(args.context_out).resolve()
    load_env_file(env_file)
    sys.path.insert(0, str(backend_dir))
    os.chdir(backend_dir)
    from app import main as backend  # type: ignore

    backend.init_db()
    if args.cleanup and args.prepare_free:
        raise SystemExit("--cleanup and --prepare-free are mutually exclusive")
    if args.cleanup:
        return cleanup_smoke_user(backend, context_path)
    if args.prepare_free:
        return prepare_free_tier(backend, context_path)
    return create_smoke_user(backend, context_path)


if __name__ == "__main__":
    raise SystemExit(main())
