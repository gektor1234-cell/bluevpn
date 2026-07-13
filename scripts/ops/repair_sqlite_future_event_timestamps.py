#!/usr/bin/env python3
"""Repair a proven uniform clock offset in future event timestamps."""

from __future__ import annotations

import argparse
import json
import os
import pathlib
import sqlite3
from datetime import datetime, timedelta, timezone
from typing import Any


DEADLINE_COLUMNS = {
    "expires_at",
    "locked_until",
    "sla_due_at",
    "starts_at",
    "sticky_until_at",
}


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--db", required=True, type=pathlib.Path)
    parser.add_argument("--backup", type=pathlib.Path)
    parser.add_argument("--offset-seconds", required=True, type=int)
    parser.add_argument("--grace-seconds", type=int, default=300)
    parser.add_argument("--max-future-seconds", type=int, default=14400)
    parser.add_argument(
        "--reference-now",
        help="Trusted ISO-8601 UTC time for repairing a host with a known clock skew",
    )
    parser.add_argument("--apply", action="store_true")
    return parser.parse_args()


def parse_timestamp(value: Any) -> datetime | None:
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
        parsed = parsed.replace(tzinfo=timezone.utc)
    return parsed.astimezone(timezone.utc)


def format_timestamp(original: Any, corrected: datetime) -> str:
    text = str(original).strip()
    value = corrected.astimezone(timezone.utc)
    if text.endswith("Z"):
        return value.isoformat().replace("+00:00", "Z")
    if "+" not in text[10:] and not text.endswith("+00:00"):
        return value.replace(tzinfo=None).isoformat()
    return value.isoformat()


def quote_identifier(value: str) -> str:
    return '"' + value.replace('"', '""') + '"'


def reference_now(value: str | None) -> datetime:
    if value is None:
        return datetime.now(timezone.utc)
    parsed = parse_timestamp(value)
    if parsed is None:
        raise SystemExit("--reference-now must be a valid ISO-8601 timestamp")
    return parsed


def timestamp_columns(conn: sqlite3.Connection) -> list[tuple[str, str]]:
    result: list[tuple[str, str]] = []
    tables = [
        row[0]
        for row in conn.execute(
            "SELECT name FROM sqlite_master "
            "WHERE type = 'table' AND name NOT LIKE 'sqlite_%' ORDER BY name"
        )
    ]
    for table in tables:
        for row in conn.execute(f"PRAGMA table_info({quote_identifier(table)})"):
            column = str(row[1])
            if (column.endswith("_at") or column.endswith("_until")) and column not in DEADLINE_COLUMNS:
                result.append((table, column))
    return result


def quick_check(conn: sqlite3.Connection) -> str:
    return str(conn.execute("PRAGMA quick_check").fetchone()[0])


def main() -> int:
    args = parse_args()
    if args.offset_seconds <= 0:
        raise SystemExit("--offset-seconds must be positive")
    if args.grace_seconds < 0 or args.max_future_seconds <= args.grace_seconds:
        raise SystemExit("invalid future window")
    if not args.db.is_file() or args.db.is_symlink():
        raise SystemExit("database is missing or unsafe")
    if args.apply and args.backup is None:
        raise SystemExit("--backup is required with --apply")
    if args.backup is not None and (args.backup.exists() or args.backup.is_symlink()):
        raise SystemExit("backup path already exists or is unsafe")

    now = reference_now(args.reference_now)
    cutoff = now + timedelta(seconds=args.grace_seconds)
    maximum = now + timedelta(seconds=args.max_future_seconds)
    offset = timedelta(seconds=args.offset_seconds)
    candidates: dict[tuple[str, str], list[tuple[int, Any, str]]] = {}
    blockers: list[dict[str, Any]] = []

    conn = sqlite3.connect(args.db, timeout=30)
    conn.row_factory = sqlite3.Row
    try:
        before_quick_check = quick_check(conn)
        if before_quick_check != "ok":
            raise SystemExit(f"database quick_check failed: {before_quick_check}")
        for table, column in timestamp_columns(conn):
            rows = conn.execute(
                f"SELECT rowid AS _repair_rowid, {quote_identifier(column)} AS value "
                f"FROM {quote_identifier(table)} "
                f"WHERE {quote_identifier(column)} IS NOT NULL "
                f"AND TRIM(CAST({quote_identifier(column)} AS TEXT)) != ''"
            )
            selected: list[tuple[int, Any, str]] = []
            beyond_window = 0
            corrected_future = 0
            for row in rows:
                parsed = parse_timestamp(row["value"])
                if parsed is None or parsed <= cutoff:
                    continue
                if parsed > maximum:
                    beyond_window += 1
                    continue
                corrected = parsed - offset
                if corrected > cutoff:
                    corrected_future += 1
                    continue
                selected.append(
                    (
                        int(row["_repair_rowid"]),
                        row["value"],
                        format_timestamp(row["value"], corrected),
                    )
                )
            if selected:
                candidates[(table, column)] = selected
            if beyond_window or corrected_future:
                blockers.append(
                    {
                        "table": table,
                        "column": column,
                        "beyondWindow": beyond_window,
                        "correctedStillFuture": corrected_future,
                    }
                )

        report = {
            "mode": "apply" if args.apply else "dry-run",
            "database": str(args.db),
            "checkedAt": now.isoformat().replace("+00:00", "Z"),
            "offsetSeconds": args.offset_seconds,
            "graceSeconds": args.grace_seconds,
            "maxFutureSeconds": args.max_future_seconds,
            "candidateValues": sum(len(rows) for rows in candidates.values()),
            "candidateColumns": [
                {"table": table, "column": column, "count": len(rows)}
                for (table, column), rows in sorted(candidates.items())
            ],
            "blockers": blockers,
            "rowContentsPrinted": False,
        }
        if blockers:
            print(json.dumps(report, ensure_ascii=False, indent=2))
            return 3
        if not args.apply:
            print(json.dumps(report, ensure_ascii=False, indent=2))
            return 0

        assert args.backup is not None
        args.backup.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
        os.chmod(args.backup.parent, 0o700)
        backup_conn = sqlite3.connect(args.backup, timeout=30)
        try:
            conn.backup(backup_conn)
            backup_result = quick_check(backup_conn)
        finally:
            backup_conn.close()
        os.chmod(args.backup, 0o600)
        if backup_result != "ok":
            raise SystemExit(f"backup quick_check failed: {backup_result}")

        conn.execute("BEGIN IMMEDIATE")
        updated = 0
        try:
            for (table, column), rows in sorted(candidates.items()):
                sql = (
                    f"UPDATE {quote_identifier(table)} "
                    f"SET {quote_identifier(column)} = ? "
                    f"WHERE rowid = ? AND {quote_identifier(column)} IS ?"
                )
                for rowid, original, corrected in rows:
                    cursor = conn.execute(sql, (corrected, rowid, original))
                    if cursor.rowcount != 1:
                        raise RuntimeError(f"concurrent change detected in {table}.{column}")
                    updated += 1
            conn.commit()
        except Exception:
            conn.rollback()
            raise
        after_quick_check = quick_check(conn)
        if after_quick_check != "ok":
            raise SystemExit(f"post-repair quick_check failed: {after_quick_check}")
    finally:
        conn.close()

    report["updatedValues"] = updated
    report["backup"] = str(args.backup)
    report["backupQuickCheck"] = backup_result
    report["databaseQuickCheck"] = after_quick_check
    print(json.dumps(report, ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
