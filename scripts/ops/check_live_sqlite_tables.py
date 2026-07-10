import sqlite3


DB = "/opt/bluevpn/backend/data/bluevpn.db"
TABLES = [
    "users",
    "devices",
    "server_catalog_entries",
    "client_endpoint_assignments",
    "resilience_route_observations",
    "server_health_observations",
    "service_availability_observations",
    "admin_audit_log",
]


def main() -> int:
    con = sqlite3.connect(DB)
    for table in TABLES:
        try:
            count = con.execute(f'SELECT count(*) FROM "{table}"').fetchone()[0]
            print("OK", table, count)
        except Exception as exc:
            print("BAD", table, type(exc).__name__, exc)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
