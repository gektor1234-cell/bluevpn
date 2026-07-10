import os
import shutil
import sqlite3
import time
from pathlib import Path


DB = Path("/opt/bluevpn/backend/data/bluevpn.db")
BACKUP_DIR = Path("/root/greenvpn-db-backups")

SKIP_DATA = {
    "admin_audit_log",
    "resilience_route_observations",
    "server_health_observations",
    "service_availability_observations",
}

CRITICAL_TABLES = {
    "users",
    "devices",
    "tokens",
    "subscriptions",
    "billing_orders",
    "server_catalog_entries",
    "client_endpoint_assignments",
    "email_login_codes",
    "email_outbox",
    "free_access_grants",
    "ad_challenges",
    "admin_staff",
    "admin_sessions",
    "support_reports",
}

ADMIN_AUDIT_SQL = """CREATE TABLE IF NOT EXISTS admin_audit_log (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    actor TEXT NOT NULL,
    action TEXT NOT NULL,
    target_type TEXT,
    target_id TEXT,
    details_json TEXT,
    request_ip TEXT,
    user_agent TEXT,
    created_at TEXT NOT NULL
)"""


def qident(name: str) -> str:
    return '"' + name.replace('"', '""') + '"'


def log(message: str) -> None:
    print(message, flush=True)


def main() -> None:
    timestamp = time.strftime("%Y%m%dT%H%M%SZ", time.gmtime())
    new_db = DB.with_name(f"bluevpn.db.recovered_{timestamp}.tmp")
    corrupt_keep = DB.with_name(f"bluevpn.db.corrupt_{timestamp}")
    backup_path = BACKUP_DIR / f"bluevpn.db.before_recovery_{timestamp}"

    BACKUP_DIR.mkdir(parents=True, exist_ok=True)
    if new_db.exists():
        new_db.unlink()

    shutil.copy2(DB, backup_path)
    for suffix in ("-wal", "-shm"):
        sidecar = DB.with_name(DB.name + suffix)
        if sidecar.exists():
            shutil.copy2(sidecar, BACKUP_DIR / f"{sidecar.name}.before_recovery_{timestamp}")
    log(f"backup={backup_path}")

    old = sqlite3.connect(f"file:{DB}?mode=ro", uri=True)
    old.row_factory = sqlite3.Row
    new = sqlite3.connect(new_db)
    new.execute("PRAGMA foreign_keys=OFF")
    new.execute("PRAGMA journal_mode=DELETE")
    new.execute("PRAGMA synchronous=FULL")

    schema_rows = old.execute(
        """
        SELECT type, name, tbl_name, sql
        FROM sqlite_master
        WHERE sql IS NOT NULL
        ORDER BY CASE type
            WHEN 'table' THEN 0
            WHEN 'view' THEN 2
            WHEN 'index' THEN 3
            WHEN 'trigger' THEN 4
            ELSE 5
        END, name
        """
    ).fetchall()

    tables: list[str] = []
    for row in schema_rows:
        if row["type"] != "table":
            continue
        name = row["name"]
        if name.startswith("sqlite_"):
            continue
        sql = ADMIN_AUDIT_SQL if name == "admin_audit_log" else row["sql"]
        new.execute(sql)
        tables.append(name)
    new.commit()
    log(f"tables_created={len(tables)}")

    counts: dict[str, int] = {}
    skipped: list[str] = []
    failed_noncritical: list[str] = []

    for table in tables:
        if table in SKIP_DATA:
            skipped.append(table)
            counts[table] = 0
            continue

        info = old.execute(f"PRAGMA table_info({qident(table)})").fetchall()
        cols = [row["name"] for row in info]
        if not cols:
            counts[table] = 0
            continue

        col_sql = ",".join(qident(col) for col in cols)
        placeholders = ",".join("?" for _ in cols)
        select_sql = "SELECT " + col_sql + " FROM " + qident(table)
        insert_sql = (
            "INSERT INTO "
            + qident(table)
            + " ("
            + col_sql
            + ") VALUES ("
            + placeholders
            + ")"
        )

        total = 0
        try:
            cur = old.execute(select_sql)
            while True:
                rows = cur.fetchmany(1000)
                if not rows:
                    break
                new.executemany(insert_sql, [tuple(row) for row in rows])
                total += len(rows)
            new.commit()
            counts[table] = total
        except Exception as exc:
            new.rollback()
            log(f"copy_failed table={table} error={type(exc).__name__}: {exc}")
            if table in CRITICAL_TABLES:
                raise
            failed_noncritical.append(table)
            counts[table] = 0

    created_secondary = 0
    for row in schema_rows:
        kind = row["type"]
        name = row["name"]
        sql = row["sql"]
        if kind == "table" or not sql or name.startswith("sqlite_"):
            continue
        new.execute(sql)
        created_secondary += 1
    new.commit()

    try:
        seq_rows = old.execute("SELECT name, seq FROM sqlite_sequence").fetchall()
        for row in seq_rows:
            if row["name"] in SKIP_DATA:
                continue
            new.execute(
                "INSERT OR REPLACE INTO sqlite_sequence(name, seq) VALUES(?, ?)",
                (row["name"], row["seq"]),
            )
        new.commit()
    except Exception as exc:
        log(f"sqlite_sequence_copy_warning={type(exc).__name__}: {exc}")

    quick = [row[0] for row in new.execute("PRAGMA quick_check").fetchall()]
    if quick != ["ok"]:
        raise RuntimeError("new database quick_check failed: " + repr(quick[:5]))

    new.close()
    old.close()

    stat = DB.stat()
    os.chown(new_db, stat.st_uid, stat.st_gid)
    os.chmod(new_db, stat.st_mode)
    for suffix in ("-wal", "-shm"):
        sidecar = DB.with_name(DB.name + suffix)
        if sidecar.exists():
            shutil.move(str(sidecar), str(BACKUP_DIR / f"{sidecar.name}.stale_before_replace_{timestamp}"))
    os.replace(DB, corrupt_keep)
    os.replace(new_db, DB)

    log(f"corrupt_kept={corrupt_keep}")
    log(f"secondary_schema_created={created_secondary}")
    if skipped:
        log("data_skipped=" + ",".join(sorted(skipped)))
    if failed_noncritical:
        log("noncritical_copy_failed=" + ",".join(sorted(failed_noncritical)))
    for table in sorted(counts):
        log(f"copied {table}={counts[table]}")
    log("recovery_ok")


if __name__ == "__main__":
    main()
