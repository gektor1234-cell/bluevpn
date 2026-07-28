import importlib.util
import sqlite3
import tempfile
import unittest
from pathlib import Path


PROJECT_ROOT = Path(__file__).resolve().parents[2]
SYNC_SCRIPT = (
    PROJECT_ROOT / "scripts" / "ops" / "sync_paid_beta_transport_catalog.py"
)
SPEC = importlib.util.spec_from_file_location(
    "greenvpn_paid_beta_transport_catalog_sync",
    SYNC_SCRIPT,
)
assert SPEC and SPEC.loader
SYNC = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(SYNC)


CATALOG_SCHEMA = """
CREATE TABLE server_catalog_entries (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    server_id TEXT NOT NULL UNIQUE,
    title TEXT NOT NULL,
    subtitle TEXT,
    country TEXT NOT NULL,
    city TEXT,
    provider TEXT,
    host TEXT NOT NULL,
    port INTEGER NOT NULL,
    protocol TEXT NOT NULL,
    transport TEXT NOT NULL,
    access_tier TEXT NOT NULL DEFAULT 'free',
    client_config_profile TEXT NOT NULL DEFAULT 'none',
    status TEXT NOT NULL,
    health_score INTEGER NOT NULL DEFAULT 0,
    latency_ms INTEGER,
    priority INTEGER NOT NULL DEFAULT 100,
    is_active INTEGER NOT NULL DEFAULT 0,
    is_public INTEGER NOT NULL DEFAULT 0,
    planned_bandwidth_mbps INTEGER,
    reserved_bandwidth_mbps INTEGER,
    current_load_mbps INTEGER,
    active_clients INTEGER,
    assigned_users INTEGER,
    load_updated_at TEXT,
    notes TEXT,
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL,
    publication_paused_at TEXT,
    publication_paused_reason TEXT,
    publication_paused_by TEXT
);
CREATE TABLE users (id INTEGER PRIMARY KEY);
CREATE TABLE subscriptions (id INTEGER PRIMARY KEY);
CREATE TABLE billing_orders (id INTEGER PRIMARY KEY);
"""


def create_database(path: Path, route_ids: tuple[str, ...]) -> None:
    conn = sqlite3.connect(path)
    try:
        conn.executescript(CATALOG_SCHEMA)
        conn.execute("INSERT INTO users(id) VALUES (1)")
        conn.execute("INSERT INTO subscriptions(id) VALUES (1)")
        conn.execute("INSERT INTO billing_orders(id) VALUES (1)")
        for index, server_id in enumerate(route_ids, start=1):
            protocol, profile, host, port, transport = (
                SYNC.EXPECTED_ROUTE_PASSPORTS[server_id]
            )
            conn.execute(
                """
                INSERT INTO server_catalog_entries(
                    server_id, title, country, host, port, protocol, transport,
                    client_config_profile, status, health_score, priority,
                    is_active, is_public, created_at, updated_at
                ) VALUES (?, ?, 'NL', ?, ?, ?, ?, ?, 'healthy', 100, ?, 1, 0, ?, ?)
                """,
                (
                    server_id,
                    server_id,
                    host,
                    port,
                    protocol,
                    transport,
                    profile,
                    index,
                    "2026-07-28T00:00:00+00:00",
                    "2026-07-28T00:00:00+00:00",
                ),
            )
        conn.commit()
    finally:
        conn.close()


class PaidBetaTransportCatalogSyncTests(unittest.TestCase):
    def test_dry_run_does_not_modify_target(self) -> None:
        with tempfile.TemporaryDirectory(
            prefix="greenvpn-paid-catalog-",
            ignore_cleanup_errors=True,
        ) as root:
            base = Path(root)
            production = base / "production.db"
            paid_beta = base / "paid.db"
            create_database(production, SYNC.TRANSPORT_SERVER_IDS)
            create_database(paid_beta, SYNC.TRANSPORT_SERVER_IDS[:5])

            result = SYNC.sync_transport_catalog(
                production,
                paid_beta,
                apply=False,
            )

            self.assertEqual(result["mode"], "dry-run")
            self.assertEqual(result["insertCount"], 8)
            self.assertEqual(result["targetTransportRowsAfter"], 5)
            with sqlite3.connect(paid_beta) as conn:
                count = conn.execute(
                    "SELECT COUNT(*) FROM server_catalog_entries"
                ).fetchone()[0]
            self.assertEqual(count, 5)

    def test_apply_is_catalog_only_and_creates_verified_backup(self) -> None:
        with tempfile.TemporaryDirectory(
            prefix="greenvpn-paid-catalog-",
            ignore_cleanup_errors=True,
        ) as root:
            base = Path(root)
            production = base / "production.db"
            paid_beta = base / "paid.db"
            backup = base / "paid.before.db"
            create_database(production, SYNC.TRANSPORT_SERVER_IDS)
            create_database(paid_beta, SYNC.TRANSPORT_SERVER_IDS[:5])
            with sqlite3.connect(paid_beta) as conn:
                conn.execute(
                    """
                    UPDATE server_catalog_entries
                    SET title = 'stale'
                    WHERE server_id = ?
                    """,
                    (SYNC.TRANSPORT_SERVER_IDS[0],),
                )
                conn.commit()

            result = SYNC.sync_transport_catalog(
                production,
                paid_beta,
                apply=True,
                backup_path=backup,
                generated_at="2026-07-28T12:00:00+00:00",
            )

            self.assertEqual(result["mode"], "apply")
            self.assertEqual(result["targetTransportRowsAfter"], 13)
            self.assertTrue(result["businessCountsUnchanged"])
            self.assertTrue(backup.is_file())
            with sqlite3.connect(backup) as conn:
                backup_count = conn.execute(
                    "SELECT COUNT(*) FROM server_catalog_entries"
                ).fetchone()[0]
            self.assertEqual(backup_count, 5)
            with sqlite3.connect(paid_beta) as conn:
                self.assertEqual(
                    conn.execute(
                        "SELECT COUNT(*) FROM server_catalog_entries"
                    ).fetchone()[0],
                    13,
                )
                self.assertEqual(
                    conn.execute("SELECT COUNT(*) FROM users").fetchone()[0],
                    1,
                )
                self.assertEqual(
                    conn.execute("PRAGMA quick_check").fetchone()[0],
                    "ok",
                )

    def test_source_route_passport_mismatch_is_rejected(self) -> None:
        with tempfile.TemporaryDirectory(
            prefix="greenvpn-paid-catalog-",
            ignore_cleanup_errors=True,
        ) as root:
            base = Path(root)
            production = base / "production.db"
            paid_beta = base / "paid.db"
            create_database(production, SYNC.TRANSPORT_SERVER_IDS)
            create_database(paid_beta, SYNC.TRANSPORT_SERVER_IDS[:5])
            with sqlite3.connect(production) as conn:
                conn.execute(
                    "UPDATE server_catalog_entries SET port = 1 WHERE server_id = ?",
                    (SYNC.TRANSPORT_SERVER_IDS[0],),
                )
                conn.commit()

            with self.assertRaisesRegex(ValueError, "route passport mismatch"):
                SYNC.sync_transport_catalog(
                    production,
                    paid_beta,
                    apply=False,
                )


if __name__ == "__main__":
    unittest.main()
