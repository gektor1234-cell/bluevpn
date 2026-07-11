#!/usr/bin/env python3
"""Merge critical Green VPN SQLite state from a peer snapshot.

The script never copies a database file over a live DB. It reads a consistent
peer snapshot and performs keyed INSERT/UPDATE operations inside one local
transaction. Conflicts are reported and left untouched.
"""

from __future__ import annotations

import argparse
import json
import pathlib
import sqlite3
import sys
from dataclasses import dataclass
from datetime import datetime, timezone
from typing import Any


NATURAL_KEYS: dict[str, tuple[str, ...]] = {
    "users": ("email",),
    "tokens": ("token",),
    "devices": ("device_uid",),
    "subscriptions": ("user_id",),
    "billing_orders": ("public_id",),
    "client_endpoint_assignments": ("user_id", "device_uid"),
    "device_traffic_usage": ("user_id", "device_uid", "server_id", "period_key"),
    "ad_challenges": ("public_id",),
    "free_access_grants": ("public_id",),
    "email_confirmations": ("token_hash",),
    "email_login_codes": ("email", "code_hash", "created_at"),
    "phone_confirmations": ("phone", "code_hash", "created_at"),
    "email_outbox": ("email", "subject", "created_at"),
    "sms_outbox": ("phone", "body", "created_at"),
    "support_reports": ("report_code",),
    "support_report_comments": ("report_id", "author", "body", "created_at"),
    "billing_orders": ("public_id",),
    "promo_codes": ("code",),
    "promo_redemptions": ("code", "user_id", "order_public_id"),
    "beta_invites": ("public_id",),
    "beta_invite_redemptions": ("user_id",),
    "beta_funnel_events": ("event_id",),
    "admin_staff": ("email",),
    "admin_sessions": ("token_hash",),
    "admin_2fa_challenges": ("challenge_id",),
    "admin_feature_flags": ("flag_key",),
    "admin_owner_action_statuses": ("action_code",),
    "admin_runbooks": ("runbook_key",),
    "admin_incidents": ("incident_key",),
    "monitoring_targets": ("target_id",),
    "server_catalog_entries": ("server_id",),
    "app_releases": ("platform", "channel", "version"),
}

DEFAULT_TABLES: tuple[str, ...] = tuple(NATURAL_KEYS.keys())
NEVER_UPDATE_TABLES = {
    "tokens",
    "email_outbox",
    "sms_outbox",
    "support_report_comments",
    "admin_sessions",
    "beta_funnel_events",
}
CHANGE_COLUMNS = ("updated_at", "last_seen_at", "last_config_at", "consumed_at", "sent_at", "verified_at")
PRESERVE_ID_TABLES = {
    "users",
    "subscriptions",
    "billing_orders",
}


@dataclass
class TableResult:
    table: str
    source_rows: int = 0
    inserted: int = 0
    updated: int = 0
    skipped: int = 0
    conflicts: int = 0
    error: str | None = None


def _connect(path: pathlib.Path, readonly: bool = False) -> sqlite3.Connection:
    if readonly:
        conn = sqlite3.connect(f"file:{path}?mode=ro", uri=True, timeout=30)
    else:
        conn = sqlite3.connect(path, timeout=30)
    conn.row_factory = sqlite3.Row
    conn.execute("PRAGMA busy_timeout = 30000")
    conn.execute("PRAGMA foreign_keys = ON")
    return conn


def _tables(conn: sqlite3.Connection) -> set[str]:
    return {
        row["name"]
        for row in conn.execute(
            "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%'"
        )
    }


def _columns(conn: sqlite3.Connection, table: str) -> list[str]:
    return [row["name"] for row in conn.execute(f"PRAGMA table_info({table})")]


def _pk_columns(conn: sqlite3.Connection, table: str) -> list[str]:
    rows = conn.execute(f"PRAGMA table_info({table})").fetchall()
    return [row["name"] for row in sorted(rows, key=lambda item: int(item["pk"] or 0)) if int(row["pk"] or 0)]


def _where_clause(keys: tuple[str, ...]) -> str:
    return " AND ".join([f"{key} IS ?" for key in keys])


def _row_key(row: sqlite3.Row, keys: tuple[str, ...]) -> tuple[Any, ...]:
    return tuple(row[key] for key in keys)


def _parse_dt(value: Any) -> datetime | None:
    if value is None:
        return None
    text = str(value).strip()
    if not text:
        return None
    try:
        parsed = datetime.fromisoformat(text.replace("Z", "+00:00"))
    except ValueError:
        return None
    if parsed.tzinfo is None:
        return parsed.replace(tzinfo=timezone.utc)
    return parsed.astimezone(timezone.utc)


def _is_source_newer(source: sqlite3.Row, target: sqlite3.Row, columns: list[str]) -> bool:
    for column in CHANGE_COLUMNS:
        if column not in columns:
            continue
        src_dt = _parse_dt(source[column])
        dst_dt = _parse_dt(target[column])
        if src_dt and (dst_dt is None or src_dt > dst_dt):
            return True
    return False


def _has_pk_conflict(
    target_conn: sqlite3.Connection,
    table: str,
    source_row: sqlite3.Row,
    pk_columns: list[str],
    natural_keys: tuple[str, ...],
) -> bool:
    if not pk_columns or set(pk_columns) == set(natural_keys):
        return False
    values = [source_row[column] for column in pk_columns if column in source_row.keys()]
    if len(values) != len(pk_columns) or any(value is None for value in values):
        return False
    where = _where_clause(tuple(pk_columns))
    existing = target_conn.execute(
        f"SELECT * FROM {table} WHERE {where} LIMIT 1",
        tuple(values),
    ).fetchone()
    if existing is None:
        return False
    return _row_key(existing, natural_keys) != _row_key(source_row, natural_keys)


def _can_insert_without_conflicting_id(table: str, pk_columns: list[str]) -> bool:
    return pk_columns == ["id"] and table not in PRESERVE_ID_TABLES


def _insert_row(conn: sqlite3.Connection, table: str, row: sqlite3.Row, columns: list[str]) -> None:
    placeholders = ", ".join(["?"] * len(columns))
    column_sql = ", ".join(columns)
    values = [row[column] for column in columns]
    conn.execute(f"INSERT INTO {table} ({column_sql}) VALUES ({placeholders})", values)


def _update_row(
    conn: sqlite3.Connection,
    table: str,
    source_row: sqlite3.Row,
    target_row: sqlite3.Row,
    columns: list[str],
    keys: tuple[str, ...],
) -> None:
    update_columns = [column for column in columns if column not in keys and column != "id"]
    if not update_columns:
        return
    set_sql = ", ".join([f"{column} = ?" for column in update_columns])
    where = _where_clause(keys)
    values = [source_row[column] for column in update_columns]
    values.extend([target_row[key] for key in keys])
    conn.execute(f"UPDATE {table} SET {set_sql} WHERE {where}", values)


def _sync_table(
    source_conn: sqlite3.Connection,
    target_conn: sqlite3.Connection,
    table: str,
    apply: bool,
) -> TableResult:
    result = TableResult(table=table)
    source_tables = _tables(source_conn)
    target_tables = _tables(target_conn)
    if table not in source_tables or table not in target_tables:
        result.error = "missing table"
        return result

    source_columns = _columns(source_conn, table)
    target_columns = _columns(target_conn, table)
    columns = [column for column in target_columns if column in source_columns]
    keys = NATURAL_KEYS[table]
    if any(key not in columns for key in keys):
        result.error = f"missing key columns: {keys}"
        return result

    pk_columns = _pk_columns(target_conn, table)
    source_rows = source_conn.execute(f"SELECT {', '.join(columns)} FROM {table}").fetchall()
    result.source_rows = len(source_rows)
    lookup_sql = f"SELECT {', '.join(columns)} FROM {table} WHERE {_where_clause(keys)} LIMIT 1"

    for source_row in source_rows:
        key_values = _row_key(source_row, keys)
        target_row = target_conn.execute(lookup_sql, key_values).fetchone()
        if target_row is None:
            if _has_pk_conflict(target_conn, table, source_row, pk_columns, keys):
                if _can_insert_without_conflicting_id(table, pk_columns):
                    insert_columns = [column for column in columns if column != "id"]
                    result.inserted += 1
                    if apply:
                        _insert_row(target_conn, table, source_row, insert_columns)
                    continue
                else:
                    result.conflicts += 1
                    continue
            result.inserted += 1
            if apply:
                _insert_row(target_conn, table, source_row, columns)
            continue

        if table in NEVER_UPDATE_TABLES:
            result.skipped += 1
            continue
        if _is_source_newer(source_row, target_row, columns):
            result.updated += 1
            if apply:
                _update_row(target_conn, table, source_row, target_row, columns, keys)
        else:
            result.skipped += 1

    return result


def _refresh_sequences(conn: sqlite3.Connection, tables: list[str]) -> None:
    sequence_exists = conn.execute(
        "SELECT name FROM sqlite_master WHERE type='table' AND name='sqlite_sequence'"
    ).fetchone()
    if not sequence_exists:
        return
    for table in tables:
        columns = _columns(conn, table)
        if "id" not in columns:
            continue
        try:
            max_id = conn.execute(f"SELECT MAX(id) FROM {table}").fetchone()[0]
            if max_id is not None:
                conn.execute(
                    """
                    INSERT INTO sqlite_sequence(name, seq)
                    VALUES(?, ?)
                    ON CONFLICT(name) DO UPDATE SET seq = MAX(sqlite_sequence.seq, excluded.seq)
                    """,
                    (table, int(max_id)),
                )
        except sqlite3.Error:
            continue


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--source-db", required=True)
    parser.add_argument("--target-db", required=True)
    parser.add_argument("--apply", action="store_true")
    parser.add_argument("--summary-json")
    parser.add_argument("--tables", nargs="*", default=list(DEFAULT_TABLES))
    args = parser.parse_args()

    source_path = pathlib.Path(args.source_db)
    target_path = pathlib.Path(args.target_db)
    if not source_path.exists():
        print(f"source DB not found: {source_path}", file=sys.stderr)
        return 2
    if not target_path.exists():
        print(f"target DB not found: {target_path}", file=sys.stderr)
        return 2

    source_conn = _connect(source_path, readonly=True)
    target_conn = _connect(target_path, readonly=False)
    started_at = datetime.now(timezone.utc).isoformat()
    results: list[TableResult] = []
    try:
        target_conn.execute("BEGIN IMMEDIATE")
        for table in args.tables:
            if table not in NATURAL_KEYS:
                continue
            results.append(_sync_table(source_conn, target_conn, table, apply=args.apply))
        if args.apply:
            _refresh_sequences(target_conn, [result.table for result in results])
            target_conn.commit()
        else:
            target_conn.rollback()
    except Exception:
        target_conn.rollback()
        raise
    finally:
        source_conn.close()
        target_conn.close()

    payload = {
        "ok": True,
        "mode": "apply" if args.apply else "dry-run",
        "startedAt": started_at,
        "finishedAt": datetime.now(timezone.utc).isoformat(),
        "sourceDb": str(source_path),
        "targetDb": str(target_path),
        "tables": [result.__dict__ for result in results],
        "totals": {
            "inserted": sum(result.inserted for result in results),
            "updated": sum(result.updated for result in results),
            "skipped": sum(result.skipped for result in results),
            "conflicts": sum(result.conflicts for result in results),
            "errors": sum(1 for result in results if result.error),
        },
    }

    text = json.dumps(payload, ensure_ascii=False, indent=2)
    if args.summary_json:
        pathlib.Path(args.summary_json).write_text(text + "\n", encoding="utf-8")
    print(text)
    return 0 if payload["totals"]["conflicts"] == 0 and payload["totals"]["errors"] == 0 else 3


if __name__ == "__main__":
    raise SystemExit(main())
