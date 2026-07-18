#!/usr/bin/env python3
"""Back up and remove an explicitly confirmed set of test accounts.

The script is intentionally fail-closed: every listed account must exist with
the expected id before any deletion starts, and every non-candidate identity
must remain byte-for-byte identical after the operation.
"""

from __future__ import annotations

import argparse
import gzip
import hashlib
import json
import os
import pathlib
import shutil
import sqlite3
import subprocess
import urllib.error
import urllib.request
from typing import Any


CONFIRMATION = "DELETE-CONFIRMED-TEST-ACCOUNTS"
CONTOURS = {
    "production": {
        "default_db": "/opt/bluevpn/backend/data/bluevpn.db",
        "default_api": "http://127.0.0.1:8000",
        "default_token": "/opt/bluevpn/backend/data/admin_token.txt",
    },
    "paid_beta": {
        "default_db": "/opt/bluevpn-paid-beta/data/bluevpn.db",
        "default_api": "http://127.0.0.1:8010",
        "default_token": "/opt/bluevpn-paid-beta/data/admin_token.txt",
    },
}


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--role", required=True, choices=("timeweb", "ruvds"))
    parser.add_argument("--candidate-file", required=True, type=pathlib.Path)
    parser.add_argument("--backup-dir", required=True, type=pathlib.Path)
    parser.add_argument("--confirmation", required=True)
    parser.add_argument("--apply", action="store_true")
    parser.add_argument("--verify-only", action="store_true")
    for contour, defaults in CONTOURS.items():
        option = contour.replace("_", "-")
        parser.add_argument(
            f"--{option}-db",
            type=pathlib.Path,
            default=pathlib.Path(defaults["default_db"]),
        )
        parser.add_argument(f"--{option}-api", default=defaults["default_api"])
        parser.add_argument(
            f"--{option}-token-file",
            type=pathlib.Path,
            default=pathlib.Path(defaults["default_token"]),
        )
    return parser.parse_args()


def connect(path: pathlib.Path, *, readonly: bool) -> sqlite3.Connection:
    if readonly:
        conn = sqlite3.connect(f"file:{path}?mode=ro", uri=True, timeout=60)
    else:
        conn = sqlite3.connect(path, timeout=60)
    conn.row_factory = sqlite3.Row
    conn.execute("PRAGMA busy_timeout = 60000")
    return conn


def table_names(conn: sqlite3.Connection) -> set[str]:
    return {
        str(row["name"])
        for row in conn.execute(
            "SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%'"
        )
    }


def table_columns(conn: sqlite3.Connection, table: str) -> set[str]:
    return {str(row["name"]) for row in conn.execute(f"PRAGMA table_info({table})")}


def identity_digest(conn: sqlite3.Connection, excluded: set[str]) -> tuple[int, str]:
    values = [
        str(row[0]).strip().lower()
        for row in conn.execute("SELECT email FROM users ORDER BY lower(email)")
        if str(row[0]).strip().lower() not in excluded
    ]
    digest = hashlib.sha256("\n".join(values).encode("utf-8")).hexdigest()
    return len(values), digest


def load_candidates(path: pathlib.Path) -> dict[str, list[dict[str, Any]]]:
    value = json.loads(path.read_text(encoding="utf-8-sig"))
    if not isinstance(value, dict) or set(value) != set(CONTOURS):
        raise SystemExit("candidate file must contain production and paid_beta only")
    result: dict[str, list[dict[str, Any]]] = {}
    for contour in CONTOURS:
        rows = value.get(contour)
        if not isinstance(rows, list) or not rows:
            raise SystemExit(f"candidate list is empty: {contour}")
        normalized = []
        seen = set()
        for row in rows:
            if not isinstance(row, dict):
                raise SystemExit(f"invalid candidate row: {contour}")
            email = str(row.get("email") or "").strip().lower()
            expected_id = int(row.get("expectedId") or 0)
            if not email or expected_id < 1 or email in seen:
                raise SystemExit(f"invalid candidate identity: {contour}")
            seen.add(email)
            normalized.append({"email": email, "expectedId": expected_id})
        result[contour] = normalized
    return result


def inspect_before(
    db_path: pathlib.Path,
    candidates: list[dict[str, Any]],
) -> dict[str, Any]:
    candidate_emails = {row["email"] for row in candidates}
    with connect(db_path, readonly=True) as conn:
        if conn.execute("PRAGMA quick_check").fetchone()[0] != "ok":
            raise SystemExit(f"database quick_check failed: {db_path}")
        user_count = int(conn.execute("SELECT COUNT(*) FROM users").fetchone()[0])
        candidate_ids = []
        for row in candidates:
            user = conn.execute(
                "SELECT id FROM users WHERE lower(email) = lower(?)",
                (row["email"],),
            ).fetchone()
            if user is None or int(user["id"]) != row["expectedId"]:
                raise SystemExit("candidate presence or id precondition failed")
            candidate_ids.append(int(user["id"]))
        placeholders = ",".join(["?"] * len(candidate_ids))
        device_uids = [
            str(row[0])
            for row in conn.execute(
                f"SELECT device_uid FROM devices WHERE user_id IN ({placeholders})",
                tuple(candidate_ids),
            )
        ]
        report_ids = [
            int(row[0])
            for row in conn.execute(
                f"SELECT id FROM support_reports WHERE user_id IN ({placeholders})",
                tuple(candidate_ids),
            )
        ]
        preserved_count, preserved_digest = identity_digest(conn, candidate_emails)
    return {
        "users": user_count,
        "candidateIds": candidate_ids,
        "deviceUids": device_uids,
        "reportIds": report_ids,
        "preservedCount": preserved_count,
        "preservedDigest": preserved_digest,
    }


def backup_database(source_path: pathlib.Path, target_path: pathlib.Path) -> str:
    source = connect(source_path, readonly=True)
    target = connect(target_path, readonly=False)
    try:
        source.backup(target)
        result = str(target.execute("PRAGMA quick_check").fetchone()[0])
    finally:
        target.close()
        source.close()
    if result != "ok":
        raise SystemExit(f"backup quick_check failed: {source_path}")
    os.chmod(target_path, 0o600)
    compressed = target_path.with_suffix(target_path.suffix + ".gz")
    with target_path.open("rb") as src, gzip.open(compressed, "wb", compresslevel=1) as dst:
        shutil.copyfileobj(src, dst)
    os.chmod(compressed, 0o600)
    return hashlib.sha256(target_path.read_bytes()).hexdigest()


def load_admin_token(path: pathlib.Path) -> str:
    if not path.is_file() or path.is_symlink():
        raise SystemExit("admin token file is missing or unsafe")
    token = path.read_text(encoding="utf-8").strip()
    if len(token) < 20:
        raise SystemExit("admin token is invalid")
    return token


def delete_candidate(
    api_base: str,
    token: str,
    candidate: dict[str, Any],
) -> dict[str, Any]:
    payload = json.dumps(
        {
            "reason": "Confirmed Codex test and smoke account cleanup",
            "confirmEmail": candidate["email"],
        },
        separators=(",", ":"),
    ).encode("utf-8")
    request = urllib.request.Request(
        f"{api_base.rstrip('/')}/api/v1/admin/users/{candidate['expectedId']}/delete",
        data=payload,
        headers={
            "Content-Type": "application/json",
            "X-Admin-Token": token,
        },
        method="POST",
    )
    try:
        with urllib.request.urlopen(request, timeout=90) as response:
            value = json.loads(response.read().decode("utf-8"))
    except urllib.error.HTTPError as error:
        raise SystemExit(f"account deletion API returned HTTP {error.code}") from error
    if value.get("ok") is not True:
        raise SystemExit("account deletion API did not confirm success")
    if int(value.get("userId") or 0) != candidate["expectedId"]:
        raise SystemExit("account deletion API returned the wrong user")
    if str(value.get("email") or "").strip().lower() != candidate["email"]:
        raise SystemExit("account deletion API returned the wrong identity")
    peer = value.get("peerCleanup") or {}
    return {
        "deleted": value.get("deleted") or {},
        "peerAttempted": int(peer.get("attempted") or 0),
        "peerRemoved": int(peer.get("removed") or 0),
    }


def verify_after(
    db_path: pathlib.Path,
    candidates: list[dict[str, Any]],
    before: dict[str, Any],
) -> dict[str, Any]:
    emails = {row["email"] for row in candidates}
    candidate_ids = tuple(before["candidateIds"])
    with connect(db_path, readonly=True) as conn:
        quick = str(conn.execute("PRAGMA quick_check").fetchone()[0])
        if quick != "ok":
            raise SystemExit("post-delete quick_check failed")
        for email in emails:
            if conn.execute(
                "SELECT 1 FROM users WHERE lower(email) = lower(?)",
                (email,),
            ).fetchone():
                raise SystemExit("candidate still exists after deletion")
        preserved_count, preserved_digest = identity_digest(conn, emails)
        if (
            preserved_count != before["preservedCount"]
            or preserved_digest != before["preservedDigest"]
        ):
            raise SystemExit("preserved account set changed")
        tables = table_names(conn)
        placeholders = ",".join(["?"] * len(candidate_ids))
        orphan_rows = 0
        for table in tables:
            if "user_id" not in table_columns(conn, table):
                continue
            orphan_rows += int(
                conn.execute(
                    f"SELECT COUNT(*) FROM {table} WHERE user_id IN ({placeholders})",
                    candidate_ids,
                ).fetchone()[0]
            )
        device_uids = tuple(before["deviceUids"])
        if device_uids and "device_transport_assignments" in tables:
            device_placeholders = ",".join(["?"] * len(device_uids))
            orphan_rows += int(
                conn.execute(
                    f"SELECT COUNT(*) FROM device_transport_assignments WHERE device_uid IN ({device_placeholders})",
                    device_uids,
                ).fetchone()[0]
            )
        report_ids = tuple(before["reportIds"])
        if report_ids and "support_report_comments" in tables:
            report_placeholders = ",".join(["?"] * len(report_ids))
            orphan_rows += int(
                conn.execute(
                    f"SELECT COUNT(*) FROM support_report_comments WHERE report_id IN ({report_placeholders})",
                    report_ids,
                ).fetchone()[0]
            )
        if orphan_rows:
            raise SystemExit("candidate dependent rows remain after deletion")
        users = int(conn.execute("SELECT COUNT(*) FROM users").fetchone()[0])
    return {
        "users": users,
        "preservedCount": preserved_count,
        "preservedDigest": preserved_digest,
        "quickCheck": quick,
        "orphanRows": orphan_rows,
    }


def verify_local_wireguard_cleanup(
    backup_dir: pathlib.Path,
    before_by_contour: dict[str, dict[str, Any]],
) -> dict[str, int]:
    public_keys = []
    for contour, before in before_by_contour.items():
        candidate_ids = tuple(before["candidateIds"])
        placeholders = ",".join(["?"] * len(candidate_ids))
        with connect(backup_dir / f"{contour}.sqlite", readonly=True) as conn:
            public_keys.extend(
                str(row[0]).strip()
                for row in conn.execute(
                    f"""
                    SELECT client_public_key
                    FROM devices
                    WHERE user_id IN ({placeholders})
                      AND client_public_key IS NOT NULL
                    """,
                    candidate_ids,
                )
                if str(row[0]).strip()
            )
    live = subprocess.run(
        ["wg", "show", "wg0", "peers"],
        text=True,
        capture_output=True,
        check=False,
    ).stdout
    config_path = pathlib.Path("/etc/wireguard/wg0.conf")
    config = (
        config_path.read_text(encoding="utf-8", errors="ignore")
        if config_path.is_file()
        else ""
    )
    return {
        "candidateKeys": len(public_keys),
        "liveHits": sum(1 for key in public_keys if key in live),
        "configHits": sum(1 for key in public_keys if key in config),
    }


def protected_account_state_digest(
    db_path: pathlib.Path,
    candidate_ids: tuple[int, ...],
) -> str:
    tables = ("users", "devices", "subscriptions", "billing_orders")
    volatile = {
        "updated_at",
        "last_seen_at",
        "last_config_at",
        "support_config_refresh_requested_at",
        "support_config_refresh_applied_at",
    }
    placeholders = ",".join(["?"] * len(candidate_ids))
    snapshot: dict[str, list[dict[str, Any]]] = {}
    with connect(db_path, readonly=True) as conn:
        available = table_names(conn)
        for table in tables:
            if table not in available:
                continue
            columns = [
                str(row["name"])
                for row in conn.execute(f"PRAGMA table_info({table})")
                if str(row["name"]) not in volatile
            ]
            owner_column = "id" if table == "users" else "user_id"
            rows = conn.execute(
                f"""
                SELECT {', '.join(columns)}
                FROM {table}
                WHERE {owner_column} NOT IN ({placeholders})
                ORDER BY {owner_column}, id
                """,
                candidate_ids,
            ).fetchall()
            snapshot[table] = [
                {column: row[column] for column in columns}
                for row in rows
            ]
    payload = json.dumps(
        snapshot,
        ensure_ascii=True,
        sort_keys=True,
        separators=(",", ":"),
        default=str,
    ).encode("utf-8")
    return hashlib.sha256(payload).hexdigest()


def main() -> int:
    args = parse_args()
    if args.confirmation != CONFIRMATION:
        raise SystemExit("confirmation phrase mismatch")
    candidates = load_candidates(args.candidate_file)
    if args.verify_only:
        if not args.backup_dir.is_dir():
            raise SystemExit("verification backup directory is missing")
        before_by_contour = {
            contour: inspect_before(
                args.backup_dir / f"{contour}.sqlite",
                candidates[contour],
            )
            for contour in CONTOURS
        }
        after_by_contour = {
            contour: verify_after(
                getattr(args, f"{contour}_db"),
                candidates[contour],
                before_by_contour[contour],
            )
            for contour in CONTOURS
        }
        protected_state_matches = {}
        for contour in CONTOURS:
            candidate_ids = tuple(before_by_contour[contour]["candidateIds"])
            protected_state_matches[contour] = (
                protected_account_state_digest(
                    args.backup_dir / f"{contour}.sqlite",
                    candidate_ids,
                )
                == protected_account_state_digest(
                    getattr(args, f"{contour}_db"),
                    candidate_ids,
                )
            )
        if not all(protected_state_matches.values()):
            raise SystemExit("protected account core state changed")
        wireguard = verify_local_wireguard_cleanup(
            args.backup_dir,
            before_by_contour,
        )
        if wireguard["liveHits"] or wireguard["configHits"]:
            raise SystemExit("candidate WireGuard peer remains on the local node")
        print("cleanup_verification=ok")
        print(f"role={args.role}")
        for contour in CONTOURS:
            print(f"{contour}_users={after_by_contour[contour]['users']}")
            print(f"{contour}_orphan_rows={after_by_contour[contour]['orphanRows']}")
            print(f"{contour}_protected_state_matches=true")
        print(f"candidate_peer_keys={wireguard['candidateKeys']}")
        print(f"local_live_peer_hits={wireguard['liveHits']}")
        print(f"local_config_peer_hits={wireguard['configHits']}")
        return 0
    if not args.apply:
        raise SystemExit("refusing to delete without --apply")
    if args.backup_dir.exists():
        raise SystemExit("backup directory already exists")
    args.backup_dir.mkdir(parents=True, mode=0o700)
    os.chmod(args.backup_dir, 0o700)

    manifest: dict[str, Any] = {
        "schema": 1,
        "role": args.role,
        "contours": {},
    }
    for contour in CONTOURS:
        option = contour.replace("_", "-")
        db_path = getattr(args, f"{contour}_db")
        api_base = getattr(args, f"{contour}_api")
        token_path = getattr(args, f"{contour}_token_file")
        before = inspect_before(db_path, candidates[contour])
        backup_sha256 = backup_database(
            db_path,
            args.backup_dir / f"{contour}.sqlite",
        )
        token = load_admin_token(token_path)
        deleted = [
            delete_candidate(api_base, token, candidate)
            for candidate in candidates[contour]
        ]
        after = verify_after(db_path, candidates[contour], before)
        manifest["contours"][contour] = {
            "before": {
                "users": before["users"],
                "candidateCount": len(candidates[contour]),
                "preservedCount": before["preservedCount"],
                "preservedDigest": before["preservedDigest"],
            },
            "after": after,
            "backupSha256": backup_sha256,
            "deletedTableRows": {
                table: sum(int(item["deleted"].get(table) or 0) for item in deleted)
                for table in sorted(
                    {table for item in deleted for table in item["deleted"]}
                )
            },
            "peerCleanup": {
                "attempted": sum(item["peerAttempted"] for item in deleted),
                "removed": sum(item["peerRemoved"] for item in deleted),
            },
        }
        del token

    manifest_path = args.backup_dir / "cleanup-manifest.json"
    manifest_path.write_text(
        json.dumps(manifest, ensure_ascii=True, sort_keys=True, separators=(",", ":"))
        + "\n",
        encoding="utf-8",
    )
    os.chmod(manifest_path, 0o600)
    print("cleanup_status=ok")
    print(f"role={args.role}")
    print(f"backup_dir={args.backup_dir}")
    for contour in CONTOURS:
        value = manifest["contours"][contour]
        print(f"{contour}_users_before={value['before']['users']}")
        print(f"{contour}_users_after={value['after']['users']}")
        print(f"{contour}_deleted_candidates={value['before']['candidateCount']}")
        print(f"{contour}_orphan_rows={value['after']['orphanRows']}")
        print(f"{contour}_peer_attempted={value['peerCleanup']['attempted']}")
        print(f"{contour}_peer_removed={value['peerCleanup']['removed']}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
