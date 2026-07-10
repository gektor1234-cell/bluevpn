import os
import shutil
import sqlite3
import subprocess
import sys
import tempfile
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


def qident(name: str) -> str:
    return '"' + name.replace('"', '""') + '"'


def log(message: str) -> None:
    print(message, flush=True)


def table_names(conn: sqlite3.Connection) -> list[str]:
    rows = conn.execute(
        """
        SELECT name
        FROM sqlite_master
        WHERE type = 'table' AND name NOT LIKE 'sqlite_%'
        ORDER BY name
        """
    ).fetchall()
    return [row[0] for row in rows]


def columns(conn: sqlite3.Connection, table: str) -> list[str]:
    return [row[1] for row in conn.execute(f"PRAGMA table_info({qident(table)})").fetchall()]


def choose_source() -> Path:
    if len(sys.argv) > 1:
        return Path(sys.argv[1])
    candidates = sorted(DB.parent.glob("bluevpn.db.corrupt_*"), key=lambda path: path.stat().st_mtime, reverse=True)
    return candidates[0] if candidates else DB


def create_app_schema_db(path: Path) -> None:
    data_dir = path.parent
    env = os.environ.copy()
    env["BLUEVPN_DATA_DIR"] = str(data_dir)
    env["BLUEVPN_BASE_DIR"] = str(data_dir.parent)
    env["PYTHONPATH"] = "/opt/bluevpn/backend"
    subprocess.run(
        [
            sys.executable,
            "-c",
            "import app.main as app; app.init_db()",
        ],
        check=True,
        env=env,
        cwd="/opt/bluevpn/backend",
    )


def main() -> int:
    timestamp = time.strftime("%Y%m%dT%H%M%SZ", time.gmtime())
    source = choose_source()
    if not source.exists():
        raise SystemExit(f"source database does not exist: {source}")

    BACKUP_DIR.mkdir(parents=True, exist_ok=True)
    backup_path = BACKUP_DIR / f"bluevpn.db.before_app_schema_recovery_{timestamp}"
    if DB.exists():
        shutil.copy2(DB, backup_path)
        log(f"backup={backup_path}")

    for suffix in ("-wal", "-shm"):
        sidecar = DB.with_name(DB.name + suffix)
        if sidecar.exists():
            shutil.move(str(sidecar), str(BACKUP_DIR / f"{sidecar.name}.before_app_schema_recovery_{timestamp}"))

    tmp_parent = Path(tempfile.mkdtemp(prefix="greenvpn_recover_", dir="/tmp"))
    tmp_data = tmp_parent / "data"
    tmp_data.mkdir(parents=True, exist_ok=True)
    new_db = tmp_data / "bluevpn.db"

    create_app_schema_db(new_db)

    old = sqlite3.connect(f"file:{source}?mode=ro&immutable=1", uri=True)
    old.row_factory = sqlite3.Row
    new = sqlite3.connect(new_db, timeout=30)
    new.row_factory = sqlite3.Row
    new.execute("PRAGMA foreign_keys=OFF")
    new.execute("PRAGMA synchronous=FULL")

    old_tables = set(table_names(old))
    new_tables = table_names(new)
    counts: dict[str, int] = {}
    skipped: list[str] = []

    for table in new_tables:
        if table in SKIP_DATA:
            new.execute(f"DELETE FROM {qident(table)}")
            counts[table] = 0
            skipped.append(table)
            continue
        if table not in old_tables:
            continue

        old_cols = set(columns(old, table))
        new_cols = columns(new, table)
        common_cols = [col for col in new_cols if col in old_cols]
        if not common_cols:
            continue

        new.execute(f"DELETE FROM {qident(table)}")
        col_sql = ",".join(qident(col) for col in common_cols)
        placeholders = ",".join("?" for _ in common_cols)
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
        cur = old.execute(select_sql)
        while True:
            rows = cur.fetchmany(1000)
            if not rows:
                break
            new.executemany(insert_sql, [tuple(row) for row in rows])
            total += len(rows)
        counts[table] = total
        new.commit()

    try:
        new.execute("DELETE FROM sqlite_sequence")
        for table in new_tables:
            if table in SKIP_DATA or table not in old_tables:
                continue
            if "id" not in columns(new, table):
                continue
            max_id = new.execute(f"SELECT MAX(id) FROM {qident(table)}").fetchone()[0]
            if max_id is not None:
                new.execute("INSERT OR REPLACE INTO sqlite_sequence(name, seq) VALUES(?, ?)", (table, int(max_id)))
        new.commit()
    except sqlite3.DatabaseError as exc:
        log(f"sqlite_sequence_warning={type(exc).__name__}: {exc}")

    new.commit()
    new.execute("PRAGMA wal_checkpoint(TRUNCATE)").fetchall()
    new.execute("PRAGMA journal_mode=DELETE").fetchone()
    new.execute("VACUUM")
    new.commit()

    quick = [row[0] for row in new.execute("PRAGMA quick_check").fetchall()]
    if quick != ["ok"]:
        raise RuntimeError("new database quick_check failed: " + repr(quick[:5]))

    old.close()
    new.close()

    if DB.exists():
        stat = DB.stat()
        os.chown(new_db, stat.st_uid, stat.st_gid)
        os.chmod(new_db, stat.st_mode)
        corrupt_keep = DB.with_name(f"bluevpn.db.schema_corrupt_{timestamp}")
        os.replace(DB, corrupt_keep)
        log(f"previous_kept={corrupt_keep}")

    os.replace(new_db, DB)
    shutil.rmtree(tmp_parent, ignore_errors=True)

    log(f"source={source}")
    if skipped:
        log("data_skipped=" + ",".join(sorted(skipped)))
    for table in sorted(counts):
        log(f"copied {table}={counts[table]}")
    log("app_schema_recovery_ok")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
