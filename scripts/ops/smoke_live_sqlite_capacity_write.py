import sqlite3

import app.main as app


DB = "/opt/bluevpn/backend/data/bluevpn.db"


def quick_check(label: str) -> None:
    con = sqlite3.connect(DB)
    rows = [row[0] for row in con.execute("PRAGMA quick_check").fetchall()]
    con.close()
    print(label, rows[:5], flush=True)
    if rows != ["ok"]:
        raise RuntimeError(f"{label} failed: {rows[:5]}")


def main() -> int:
    quick_check("before")
    payload = app.AdminServerCapacityIn(
        currentLoadMbps=0,
        activeClients=0,
        assignedUsers=0,
        loadUpdatedAt=app.utc_now_iso(),
    )
    app.update_managed_server_capacity_by_server_id("ruvds-2584554-ld8", payload)
    quick_check("after_capacity_update")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
