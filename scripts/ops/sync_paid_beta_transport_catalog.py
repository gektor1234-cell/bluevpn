#!/usr/bin/env python3
"""Synchronize the reviewed production transport rows into paid-beta SQLite."""

from __future__ import annotations

import argparse
import datetime as dt
import json
import os
import pathlib
import sqlite3
from typing import Any


TRANSPORT_SERVER_IDS = (
    "nl1-awg2-canary",
    "nl1-hysteria2-canary",
    "nl1-vless-reality-xhttp-canary",
    "nl1-naive-https-canary",
    "nl2-awg2-canary",
    "nl2-hysteria2-canary",
    "nl2-vless-reality-xhttp-canary",
    "nl2-naive-https-canary",
    "nl2-dnstt-canary",
    "gb1-awg2-canary",
    "gb1-hysteria2-canary",
    "gb1-vless-reality-xhttp-canary",
    "gb1-naive-https-canary",
)

EXPECTED_ROUTE_PASSPORTS = {
    "nl1-awg2-canary": (
        "amneziawg",
        "remote_ssh_awg2",
        "nl1.vpn.greenvpn.pro",
        1443,
        "udp",
    ),
    "nl1-hysteria2-canary": (
        "hysteria2",
        "static_hysteria2_canary",
        "37.220.85.211",
        2443,
        "quic",
    ),
    "nl1-vless-reality-xhttp-canary": (
        "vless_reality",
        "static_vless_reality_canary",
        "37.220.85.211",
        443,
        "reality",
    ),
    "nl1-naive-https-canary": (
        "naive_https",
        "static_naive_https_canary",
        "37.220.85.211",
        8443,
        "https",
    ),
    "nl2-awg2-canary": (
        "amneziawg",
        "remote_ssh_awg2",
        "nl2.vpn.greenvpn.pro",
        1443,
        "udp",
    ),
    "nl2-hysteria2-canary": (
        "hysteria2",
        "static_hysteria2_canary",
        "5.129.216.42",
        2443,
        "quic",
    ),
    "nl2-vless-reality-xhttp-canary": (
        "vless_reality",
        "static_vless_reality_canary",
        "5.129.216.42",
        443,
        "reality",
    ),
    "nl2-naive-https-canary": (
        "naive_https",
        "static_naive_https_canary",
        "5.129.216.42",
        8443,
        "https",
    ),
    "nl2-dnstt-canary": (
        "dnstt",
        "static_dnstt_canary",
        "5.129.216.42",
        53,
        "doh",
    ),
    "gb1-awg2-canary": (
        "amneziawg",
        "remote_ssh_awg2",
        "88.218.250.86",
        1443,
        "udp",
    ),
    "gb1-hysteria2-canary": (
        "hysteria2",
        "static_hysteria2_canary",
        "88.218.250.86",
        2443,
        "quic",
    ),
    "gb1-vless-reality-xhttp-canary": (
        "vless_reality",
        "static_vless_reality_canary",
        "88.218.250.86",
        9443,
        "reality",
    ),
    "gb1-naive-https-canary": (
        "naive_https",
        "static_naive_https_canary",
        "88.218.250.86",
        8443,
        "https",
    ),
}

BUSINESS_TABLES = ("users", "subscriptions", "billing_orders")


def _require_regular_file(path: pathlib.Path, label: str) -> pathlib.Path:
    if not path.is_file() or path.is_symlink():
        raise ValueError(f"{label} is missing, symlinked or not a regular file: {path}")
    return path.resolve(strict=True)


def _table_columns(conn: sqlite3.Connection, table: str) -> list[str]:
    return [str(row[1]) for row in conn.execute(f"PRAGMA table_info({table})")]


def _quick_check(conn: sqlite3.Connection, label: str) -> None:
    result = str(conn.execute("PRAGMA quick_check").fetchone()[0])
    if result != "ok":
        raise ValueError(f"{label} quick_check failed: {result}")


def _business_counts(conn: sqlite3.Connection) -> dict[str, int]:
    available = {
        str(row[0])
        for row in conn.execute(
            "SELECT name FROM sqlite_master WHERE type = 'table'"
        ).fetchall()
    }
    return {
        table: int(conn.execute(f"SELECT COUNT(*) FROM {table}").fetchone()[0])
        for table in BUSINESS_TABLES
        if table in available
    }


def _route_rows(
    conn: sqlite3.Connection,
    columns: list[str],
) -> dict[str, dict[str, Any]]:
    placeholders = ",".join("?" for _ in TRANSPORT_SERVER_IDS)
    conn.row_factory = sqlite3.Row
    rows = conn.execute(
        f"""
        SELECT {",".join(columns)}
        FROM server_catalog_entries
        WHERE server_id IN ({placeholders})
        """,
        TRANSPORT_SERVER_IDS,
    ).fetchall()
    return {str(row["server_id"]): dict(row) for row in rows}


def _validate_source_rows(rows: dict[str, dict[str, Any]]) -> None:
    missing = sorted(set(TRANSPORT_SERVER_IDS).difference(rows))
    if missing:
        raise ValueError("production transport set is incomplete: " + ",".join(missing))
    unexpected = sorted(set(rows).difference(TRANSPORT_SERVER_IDS))
    if unexpected:
        raise ValueError("unexpected transport rows: " + ",".join(unexpected))

    for server_id in TRANSPORT_SERVER_IDS:
        row = rows[server_id]
        (
            expected_protocol,
            expected_profile,
            expected_host,
            expected_port,
            expected_transport,
        ) = (
            EXPECTED_ROUTE_PASSPORTS[server_id]
        )
        observed = (
            str(row.get("protocol") or ""),
            str(row.get("client_config_profile") or ""),
            str(row.get("host") or ""),
            int(row.get("port") or 0),
            str(row.get("transport") or ""),
        )
        expected = (
            expected_protocol,
            expected_profile,
            expected_host,
            expected_port,
            expected_transport,
        )
        if observed != expected:
            raise ValueError(f"route passport mismatch: {server_id}")
        if (
            str(row.get("status") or "") != "healthy"
            or int(row.get("is_active") or 0) != 1
            or int(row.get("is_public") or 0) != 0
        ):
            raise ValueError(f"route publication guard failed: {server_id}")


def _row_differs(
    source: dict[str, Any],
    target: dict[str, Any],
    columns: list[str],
) -> bool:
    ignored = {"id", "created_at", "updated_at"}
    return any(
        source.get(column) != target.get(column)
        for column in columns
        if column not in ignored
    )


def _create_online_backup(
    source: sqlite3.Connection,
    backup_path: pathlib.Path,
) -> None:
    if backup_path.exists() or backup_path.is_symlink():
        raise ValueError(f"backup path already exists: {backup_path}")
    parent = backup_path.parent
    if not parent.is_dir() or parent.is_symlink():
        raise ValueError(f"backup parent is unsafe or missing: {parent}")

    descriptor = os.open(
        backup_path,
        os.O_CREAT | os.O_EXCL | os.O_WRONLY,
        0o600,
    )
    os.close(descriptor)
    backup = sqlite3.connect(backup_path)
    try:
        source.backup(backup)
        _quick_check(backup, "backup")
    except Exception:
        backup.close()
        backup_path.unlink(missing_ok=True)
        raise
    finally:
        try:
            backup.close()
        except Exception:
            pass
    os.chmod(backup_path, 0o600)


def sync_transport_catalog(
    production_db: pathlib.Path,
    paid_beta_db: pathlib.Path,
    *,
    apply: bool,
    backup_path: pathlib.Path | None = None,
    generated_at: str | None = None,
) -> dict[str, Any]:
    production_path = _require_regular_file(production_db, "production database")
    paid_beta_path = _require_regular_file(paid_beta_db, "paid-beta database")
    if production_path == paid_beta_path:
        raise ValueError("production and paid-beta databases must differ")
    if apply and backup_path is None:
        raise ValueError("apply mode requires an explicit backup path")

    production = sqlite3.connect(
        f"file:{production_path}?mode=ro",
        uri=True,
        timeout=60,
    )
    paid_mode = "rw" if apply else "ro"
    paid_beta = sqlite3.connect(
        f"file:{paid_beta_path}?mode={paid_mode}",
        uri=True,
        timeout=60,
    )
    try:
        _quick_check(production, "production")
        _quick_check(paid_beta, "paid-beta")
        production_columns = _table_columns(production, "server_catalog_entries")
        paid_columns = _table_columns(paid_beta, "server_catalog_entries")
        if not production_columns or production_columns != paid_columns:
            raise ValueError("server catalog schemas differ")

        source_rows = _route_rows(production, production_columns)
        target_rows = _route_rows(paid_beta, paid_columns)
        _validate_source_rows(source_rows)
        to_insert = [
            server_id
            for server_id in TRANSPORT_SERVER_IDS
            if server_id not in target_rows
        ]
        to_update = [
            server_id
            for server_id in TRANSPORT_SERVER_IDS
            if server_id in target_rows
            and _row_differs(
                source_rows[server_id],
                target_rows[server_id],
                production_columns,
            )
        ]
        business_before = _business_counts(paid_beta)

        if apply:
            resolved_backup = pathlib.Path(backup_path).resolve(strict=False)
            _create_online_backup(paid_beta, resolved_backup)
            timestamp = generated_at or dt.datetime.now(dt.timezone.utc).isoformat()
            insert_columns = [
                column for column in production_columns if column != "id"
            ]
            update_columns = [
                column
                for column in insert_columns
                if column not in {"server_id", "created_at"}
            ]
            assignments = ",".join(
                f"{column}=excluded.{column}" for column in update_columns
            )
            sql = (
                f"INSERT INTO server_catalog_entries ({','.join(insert_columns)}) "
                f"VALUES ({','.join('?' for _ in insert_columns)}) "
                f"ON CONFLICT(server_id) DO UPDATE SET {assignments}"
            )
            try:
                paid_beta.execute("BEGIN IMMEDIATE")
                for server_id in TRANSPORT_SERVER_IDS:
                    values = dict(source_rows[server_id])
                    values["updated_at"] = timestamp
                    paid_beta.execute(
                        sql,
                        [values[column] for column in insert_columns],
                    )
                paid_beta.commit()
            except Exception:
                paid_beta.rollback()
                raise
            _quick_check(paid_beta, "paid-beta after synchronization")

        final_rows = _route_rows(paid_beta, paid_columns)
        business_after = _business_counts(paid_beta)
        final_missing = sorted(set(TRANSPORT_SERVER_IDS).difference(final_rows))
        if apply and final_missing:
            raise ValueError(
                "paid-beta transport set remains incomplete: "
                + ",".join(final_missing)
            )
        if business_before != business_after:
            raise ValueError("business table row counts changed")

        protocol_counts: dict[str, int] = {}
        for row in final_rows.values():
            protocol = str(row.get("protocol") or "unknown")
            protocol_counts[protocol] = protocol_counts.get(protocol, 0) + 1
        return {
            "ok": True,
            "mode": "apply" if apply else "dry-run",
            "sourceTransportRows": len(source_rows),
            "targetTransportRowsBefore": len(target_rows),
            "targetTransportRowsAfter": len(final_rows),
            "insertCount": len(to_insert),
            "updateCount": len(to_update),
            "finalMissingCount": len(final_missing),
            "protocolCounts": dict(sorted(protocol_counts.items())),
            "businessCountsUnchanged": business_before == business_after,
            "backupCreated": bool(apply),
            "secretsPrinted": False,
        }
    finally:
        paid_beta.close()
        production.close()


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--production-db", required=True, type=pathlib.Path)
    parser.add_argument("--paid-beta-db", required=True, type=pathlib.Path)
    parser.add_argument("--backup-path", type=pathlib.Path)
    parser.add_argument("--apply", action="store_true")
    args = parser.parse_args()
    if args.apply and args.backup_path is None:
        parser.error("--backup-path is required with --apply")

    result = sync_transport_catalog(
        args.production_db,
        args.paid_beta_db,
        apply=args.apply,
        backup_path=args.backup_path,
    )
    print(json.dumps(result, ensure_ascii=True, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
