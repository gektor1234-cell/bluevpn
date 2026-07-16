#!/usr/bin/env python3
"""Promote reviewed paid-contour state into the production SQLite database."""

from __future__ import annotations

import argparse
import datetime as dt
import json
import pathlib
import sqlite3


TRANSPORT_SERVER_IDS = (
    "nl2-awg2-canary",
    "nl2-hysteria2-canary",
    "nl2-vless-reality-xhttp-canary",
    "nl2-naive-https-canary",
    "nl2-dnstt-canary",
)
EXPECTED_PROFILES = {
    "nl2-awg2-canary": "remote_ssh_awg2",
    "nl2-hysteria2-canary": "static_hysteria2_canary",
    "nl2-vless-reality-xhttp-canary": "static_vless_reality_canary",
    "nl2-naive-https-canary": "static_naive_https_canary",
    "nl2-dnstt-canary": "static_dnstt_canary",
}
PUBLIC_PLAN_CODES = {"green_30d", "green_90d", "green_180d"}


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--production-db", required=True, type=pathlib.Path)
    parser.add_argument("--candidate-db", required=True, type=pathlib.Path)
    parser.add_argument("--apply", action="store_true")
    return parser.parse_args()


def columns(conn: sqlite3.Connection, table: str) -> list[str]:
    return [str(row[1]) for row in conn.execute(f"PRAGMA table_info({table})")]


def parse_timestamp(value: str | None) -> dt.datetime:
    normalized = str(value or "").strip().replace("Z", "+00:00")
    parsed = dt.datetime.fromisoformat(normalized)
    if parsed.tzinfo is None:
        parsed = parsed.replace(tzinfo=dt.timezone.utc)
    return parsed.astimezone(dt.timezone.utc)


def main() -> int:
    args = parse_args()
    for path in (args.production_db, args.candidate_db):
        if not path.is_file() or path.is_symlink():
            raise SystemExit(f"unsafe or missing database: {path}")

    production = sqlite3.connect(args.production_db, timeout=60)
    candidate = sqlite3.connect(
        f"file:{args.candidate_db}?mode=ro",
        uri=True,
        timeout=60,
    )
    production.row_factory = sqlite3.Row
    candidate.row_factory = sqlite3.Row
    try:
        for label, conn in (("production", production), ("candidate", candidate)):
            result = conn.execute("PRAGMA quick_check").fetchone()[0]
            if result != "ok":
                raise SystemExit(f"{label} quick_check failed: {result}")

        catalog_columns = columns(production, "server_catalog_entries")
        if catalog_columns != columns(candidate, "server_catalog_entries"):
            raise SystemExit("server catalog schemas differ")
        subscription_columns = columns(production, "subscriptions")
        if subscription_columns != columns(candidate, "subscriptions"):
            raise SystemExit("subscription schemas differ")

        placeholders = ",".join("?" for _ in TRANSPORT_SERVER_IDS)
        transport_rows = candidate.execute(
            f"SELECT * FROM server_catalog_entries WHERE server_id IN ({placeholders})",
            TRANSPORT_SERVER_IDS,
        ).fetchall()
        if {row["server_id"] for row in transport_rows} != set(TRANSPORT_SERVER_IDS):
            raise SystemExit("candidate transport set is incomplete")
        for row in transport_rows:
            server_id = str(row["server_id"])
            if (
                row["status"] != "healthy"
                or int(row["is_active"] or 0) != 1
                or int(row["is_public"] or 0) != 0
                or row["client_config_profile"] != EXPECTED_PROFILES[server_id]
            ):
                raise SystemExit(f"candidate transport guard failed: {server_id}")
            collision = production.execute(
                "SELECT server_id FROM server_catalog_entries WHERE id = ? AND server_id <> ?",
                (row["id"], server_id),
            ).fetchone()
            if collision is not None:
                raise SystemExit(f"catalog id collision for {server_id}")

        now = dt.datetime.now(dt.timezone.utc)
        paid_rows = candidate.execute(
            """
            SELECT s.*, u.email AS user_email
            FROM subscriptions s
            JOIN users u ON u.id = s.user_id
            WHERE s.is_active = 1
              AND s.plan_code IN ('green_30d', 'green_90d', 'green_180d')
              AND s.monthly_price_rub > 0
            """
        ).fetchall()
        paid_rows = [row for row in paid_rows if parse_timestamp(row["expires_at"]) > now]
        if len(paid_rows) != 1:
            raise SystemExit(f"expected one active paid candidate, found {len(paid_rows)}")
        paid = paid_rows[0]
        if int(paid["auto_renew"] or 0) != 0 or str(
            paid["provider_payment_method_id"] or ""
        ).strip():
            raise SystemExit("candidate unlink smoke state is not clean")
        production_user = production.execute(
            "SELECT id FROM users WHERE lower(email) = lower(?)",
            (paid["user_email"],),
        ).fetchone()
        if production_user is None:
            raise SystemExit("paid candidate user does not exist in production")
        production_subscription = production.execute(
            "SELECT * FROM subscriptions WHERE user_id = ?",
            (production_user["id"],),
        ).fetchone()
        if production_subscription is None:
            raise SystemExit("production subscription row is missing")

        current_expiry = parse_timestamp(production_subscription["expires_at"])
        candidate_expiry = parse_timestamp(paid["expires_at"])
        effective_expiry = max(current_expiry, candidate_expiry)
        generated_at = now.isoformat()

        production.execute("BEGIN IMMEDIATE")
        insert_columns = catalog_columns
        update_columns = [name for name in catalog_columns if name not in {"id", "server_id"}]
        insert_sql = (
            f"INSERT INTO server_catalog_entries ({','.join(insert_columns)}) "
            f"VALUES ({','.join('?' for _ in insert_columns)}) "
            "ON CONFLICT(server_id) DO UPDATE SET "
            + ",".join(f"{name}=excluded.{name}" for name in update_columns)
        )
        for row in transport_rows:
            values = dict(row)
            values["updated_at"] = generated_at
            production.execute(insert_sql, [values[name] for name in insert_columns])

        selection = json.loads(str(paid["selection_json"] or "{}"))
        if not isinstance(selection, dict):
            raise SystemExit("candidate subscription selection is invalid")
        selection["autoRenew"] = False
        production.execute(
            """
            UPDATE subscriptions
            SET plan_code = ?, plan_name = ?, max_devices = ?, is_active = 1,
                expires_at = ?, updated_at = ?, monthly_price_rub = ?,
                selection_json = ?, auto_renew = 0,
                provider_payment_method_id = NULL
            WHERE user_id = ?
            """,
            (
                paid["plan_code"],
                paid["plan_name"],
                paid["max_devices"],
                effective_expiry.isoformat(),
                generated_at,
                paid["monthly_price_rub"],
                json.dumps(selection, ensure_ascii=False, separators=(",", ":")),
                production_user["id"],
            ),
        )

        promoted_count = production.execute(
            f"SELECT COUNT(*) FROM server_catalog_entries WHERE server_id IN ({placeholders})",
            TRANSPORT_SERVER_IDS,
        ).fetchone()[0]
        if promoted_count != len(TRANSPORT_SERVER_IDS):
            raise SystemExit("production transport count mismatch")
        if args.apply:
            production.commit()
        else:
            production.rollback()

        print("mode=" + ("apply" if args.apply else "dry-run"))
        print(f"transport_rows={len(transport_rows)}")
        print("paid_subscription_rows=1")
        print("paid_expiry_extended=" + str(candidate_expiry > current_expiry).lower())
        print("saved_payment_method_copied=false")
        print("database_quick_check=ok")
        return 0
    finally:
        candidate.close()
        production.close()


if __name__ == "__main__":
    raise SystemExit(main())
