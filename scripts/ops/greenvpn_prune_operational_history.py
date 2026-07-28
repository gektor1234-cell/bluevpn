#!/usr/bin/env python3
"""Bound Green VPN operational history without touching business records."""

from __future__ import annotations

import argparse
import json
import os
import pathlib
import sqlite3
from datetime import datetime, timedelta, timezone


NOISY_ADMIN_AUDIT_ACTIONS = (
    "resilience_route_observation_created",
    "service_availability_observation_created",
    "server_catalog_capacity_updated",
    "wireguard_traffic_report_received",
    "server_health_observation_created",
)

RETENTION_TABLES = {
    "client_route_events": ("created_at", 30),
    "auth_events": ("created_at", 180),
    "service_availability_observations": ("created_at", 7),
    "server_health_observations": ("created_at", 7),
    "resilience_route_observations": ("created_at", 7),
    "admin_audit_log": ("created_at", 365),
    "admin_alert_events": ("created_at", 180),
    "admin_support_actions": ("created_at", 365),
    "subscription_expiry_reviews": ("created_at", 365),
}

ROW_LIMITS = {
    "service_availability_observations": ("created_at", 30_000),
    "server_health_observations": ("created_at", 12_000),
    "resilience_route_observations": ("created_at", 30_000),
}


def utc_cutoff(days: int) -> str:
    return (datetime.now(timezone.utc) - timedelta(days=days)).isoformat()


def table_names(conn: sqlite3.Connection) -> set[str]:
    return {
        str(row[0])
        for row in conn.execute(
            "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%'"
        )
    }


def count_where(
    conn: sqlite3.Connection,
    table: str,
    where_sql: str,
    values: tuple[object, ...],
) -> int:
    return int(
        conn.execute(
            f"SELECT COUNT(*) FROM {table} WHERE {where_sql}",
            values,
        ).fetchone()[0]
    )


def delete_in_batches(
    conn: sqlite3.Connection,
    table: str,
    where_sql: str,
    values: tuple[object, ...],
    batch_size: int,
) -> int:
    deleted = 0
    while True:
        conn.execute("BEGIN IMMEDIATE")
        cursor = conn.execute(
            f"""
            DELETE FROM {table}
            WHERE id IN (
                SELECT id FROM {table}
                WHERE {where_sql}
                ORDER BY id
                LIMIT ?
            )
            """,
            (*values, batch_size),
        )
        batch = max(0, int(cursor.rowcount or 0))
        conn.commit()
        deleted += batch
        if batch < batch_size:
            return deleted


def delete_oldest_over_limit(
    conn: sqlite3.Connection,
    table: str,
    timestamp_column: str,
    max_rows: int,
    batch_size: int,
) -> tuple[int, int, int]:
    rows_before = int(conn.execute(f"SELECT COUNT(*) FROM {table}").fetchone()[0])
    candidates = max(0, rows_before - max_rows)
    deleted = 0
    while deleted < candidates:
        limit = min(batch_size, candidates - deleted)
        conn.execute("BEGIN IMMEDIATE")
        cursor = conn.execute(
            f"""
            DELETE FROM {table}
            WHERE id IN (
                SELECT id FROM {table}
                ORDER BY {timestamp_column}, id
                LIMIT ?
            )
            """,
            (limit,),
        )
        batch = max(0, int(cursor.rowcount or 0))
        conn.commit()
        deleted += batch
        if batch < limit:
            break
    return rows_before, candidates, deleted


def inspect_database(
    path: pathlib.Path,
    apply: bool,
    batch_size: int,
    run_quick_check: bool,
) -> dict:
    resolved = path.expanduser().resolve(strict=True)
    if not resolved.is_file() or path.is_symlink():
        raise ValueError(f"database path is not a regular file: {path}")

    conn = sqlite3.connect(resolved, timeout=60)
    conn.execute("PRAGMA busy_timeout = 60000")
    available = table_names(conn)
    result: dict[str, object] = {
        "database": str(resolved),
        "apply": apply,
        "beforeBytes": os.path.getsize(resolved),
        "tables": {},
    }
    table_results: dict[str, dict[str, object]] = result["tables"]  # type: ignore[assignment]

    if "admin_audit_log" in available:
        placeholders = ",".join("?" for _ in NOISY_ADMIN_AUDIT_ACTIONS)
        where_sql = f"action IN ({placeholders})"
        values: tuple[object, ...] = tuple(NOISY_ADMIN_AUDIT_ACTIONS)
        candidates = count_where(conn, "admin_audit_log", where_sql, values)
        deleted = (
            delete_in_batches(
                conn,
                "admin_audit_log",
                where_sql,
                values,
                batch_size,
            )
            if apply and candidates
            else 0
        )
        table_results["admin_audit_noise"] = {
            "candidates": candidates,
            "deleted": deleted,
        }

    for table, (timestamp_column, days) in RETENTION_TABLES.items():
        if table not in available:
            table_results[table] = {"status": "missing"}
            continue
        cutoff = utc_cutoff(days)
        where_sql = f"{timestamp_column} < ?"
        values = (cutoff,)
        candidates = count_where(conn, table, where_sql, values)
        deleted = (
            delete_in_batches(conn, table, where_sql, values, batch_size)
            if apply and candidates
            else 0
        )
        table_results[table] = {
            "retentionDays": days,
            "cutoff": cutoff,
            "candidates": candidates,
            "deleted": deleted,
        }

    for table, (timestamp_column, max_rows) in ROW_LIMITS.items():
        if table not in available:
            continue
        rows_before = int(conn.execute(f"SELECT COUNT(*) FROM {table}").fetchone()[0])
        time_candidates = int(table_results.get(table, {}).get("candidates", 0))
        rows_before_limit = (
            rows_before
            if apply
            else max(0, rows_before - time_candidates)
        )
        candidates = max(0, rows_before_limit - max_rows)
        deleted = 0
        if apply and candidates:
            rows_before_limit, candidates, deleted = delete_oldest_over_limit(
                conn,
                table,
                timestamp_column,
                max_rows,
                batch_size,
            )
        table_results.setdefault(table, {}).update(
            {
                "rowLimit": max_rows,
                "rowsBeforeLimit": rows_before_limit,
                "limitCandidates": candidates,
                "limitDeleted": deleted,
            }
        )

    quick_check = "skipped"
    if run_quick_check:
        quick_check = str(conn.execute("PRAGMA quick_check").fetchone()[0])
        if quick_check != "ok":
            raise RuntimeError(f"database quick_check failed: {quick_check}")
    freelist_pages = int(conn.execute("PRAGMA freelist_count").fetchone()[0])
    page_size = int(conn.execute("PRAGMA page_size").fetchone()[0])
    conn.close()
    result.update(
        {
            "quickCheck": quick_check,
            "afterBytes": os.path.getsize(resolved),
            "reusableBytes": freelist_pages * page_size,
        }
    )
    return result


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--db", action="append", required=True, type=pathlib.Path)
    parser.add_argument("--apply", action="store_true")
    parser.add_argument("--quick-check", action="store_true")
    parser.add_argument("--batch-size", type=int, default=5000)
    args = parser.parse_args()
    if args.batch_size < 100 or args.batch_size > 50000:
        parser.error("--batch-size must be between 100 and 50000")

    results = [
        inspect_database(
            path,
            apply=args.apply,
            batch_size=args.batch_size,
            run_quick_check=args.quick_check,
        )
        for path in args.db
    ]
    print(json.dumps({"ok": True, "results": results}, ensure_ascii=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
