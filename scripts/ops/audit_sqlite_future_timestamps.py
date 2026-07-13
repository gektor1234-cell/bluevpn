#!/usr/bin/env python3
"""Report impossible future event timestamps without exposing row contents."""

from __future__ import annotations

import argparse
import json
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
    parser.add_argument("--grace-seconds", type=int, default=300)
    parser.add_argument(
        "--reference-now",
        help="Trusted ISO-8601 UTC time for auditing a host with a known clock skew",
    )
    parser.add_argument("--fail-on-event-future", action="store_true")
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


def quote_identifier(value: str) -> str:
    return '"' + value.replace('"', '""') + '"'


def reference_now(value: str | None) -> datetime:
    if value is None:
        return datetime.now(timezone.utc)
    parsed = parse_timestamp(value)
    if parsed is None:
        raise SystemExit("--reference-now must be a valid ISO-8601 timestamp")
    return parsed


def main() -> int:
    args = parse_args()
    if args.grace_seconds < 0:
        raise SystemExit("--grace-seconds must be non-negative")
    if not args.db.is_file() or args.db.is_symlink():
        raise SystemExit("database is missing or unsafe")

    now = reference_now(args.reference_now)
    cutoff = now + timedelta(seconds=args.grace_seconds)
    findings: list[dict[str, Any]] = []
    scanned_values = 0
    unparseable_values = 0

    conn = sqlite3.connect(f"file:{args.db}?mode=ro", uri=True, timeout=30)
    try:
        conn.row_factory = sqlite3.Row
        quick_check = conn.execute("PRAGMA quick_check").fetchone()[0]
        tables = [
            row[0]
            for row in conn.execute(
                "SELECT name FROM sqlite_master "
                "WHERE type = 'table' AND name NOT LIKE 'sqlite_%' ORDER BY name"
            )
        ]
        for table in tables:
            columns = [
                str(row[1])
                for row in conn.execute(f"PRAGMA table_info({quote_identifier(table)})")
                if str(row[1]).endswith("_at") or str(row[1]).endswith("_until")
            ]
            for column in columns:
                values = conn.execute(
                    f"SELECT {quote_identifier(column)} FROM {quote_identifier(table)} "
                    f"WHERE {quote_identifier(column)} IS NOT NULL "
                    f"AND TRIM(CAST({quote_identifier(column)} AS TEXT)) != ''"
                )
                future_count = 0
                max_future: datetime | None = None
                for row in values:
                    scanned_values += 1
                    parsed = parse_timestamp(row[0])
                    if parsed is None:
                        unparseable_values += 1
                        continue
                    if parsed <= cutoff:
                        continue
                    future_count += 1
                    if max_future is None or parsed > max_future:
                        max_future = parsed
                if future_count:
                    findings.append(
                        {
                            "table": table,
                            "column": column,
                            "kind": "deadline" if column in DEADLINE_COLUMNS else "event",
                            "count": future_count,
                            "maxTimestamp": max_future.isoformat().replace("+00:00", "Z"),
                            "maxSecondsAhead": round((max_future - now).total_seconds()),
                        }
                    )
    finally:
        conn.close()

    event_future = sum(item["count"] for item in findings if item["kind"] == "event")
    deadline_future = sum(item["count"] for item in findings if item["kind"] == "deadline")
    report = {
        "ok": quick_check == "ok" and event_future == 0,
        "database": str(args.db),
        "checkedAt": now.isoformat().replace("+00:00", "Z"),
        "graceSeconds": args.grace_seconds,
        "quickCheck": quick_check,
        "eventFutureValues": event_future,
        "deadlineFutureValues": deadline_future,
        "scannedValues": scanned_values,
        "unparseableValues": unparseable_values,
        "findings": findings,
        "rowContentsPrinted": False,
    }
    print(json.dumps(report, ensure_ascii=False, indent=2))
    if args.fail_on_event_future and event_future:
        return 2
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
