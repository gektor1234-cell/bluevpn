import json
import importlib.util
import sqlite3
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


PROJECT_ROOT = Path(__file__).resolve().parents[2]
PRUNE_SCRIPT = (
    PROJECT_ROOT / "scripts" / "ops" / "greenvpn_prune_operational_history.py"
)
SPEC = importlib.util.spec_from_file_location("greenvpn_operational_retention", PRUNE_SCRIPT)
assert SPEC and SPEC.loader
RETENTION = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(RETENTION)


class OperationalRetentionTests(unittest.TestCase):
    def test_prune_removes_machine_noise_and_old_history_only(self) -> None:
        with tempfile.TemporaryDirectory(
            prefix="greenvpn-retention-",
            ignore_cleanup_errors=True,
        ) as root:
            database = Path(root) / "bluevpn.db"
            with sqlite3.connect(database) as conn:
                conn.executescript(
                    """
                    CREATE TABLE users (
                        id INTEGER PRIMARY KEY AUTOINCREMENT,
                        email TEXT NOT NULL UNIQUE
                    );
                    CREATE TABLE admin_audit_log (
                        id INTEGER PRIMARY KEY AUTOINCREMENT,
                        action TEXT NOT NULL,
                        created_at TEXT NOT NULL
                    );
                    CREATE TABLE service_availability_observations (
                        id INTEGER PRIMARY KEY AUTOINCREMENT,
                        created_at TEXT NOT NULL
                    );
                    """
                )
                conn.execute("INSERT INTO users(email) VALUES ('owner@example.test')")
                conn.executemany(
                    "INSERT INTO admin_audit_log(action, created_at) VALUES (?, ?)",
                    [
                        (
                            "service_availability_observation_created",
                            "2026-07-18T00:00:00+00:00",
                        ),
                        ("admin_staff_login_succeeded", "2026-07-18T00:00:00+00:00"),
                    ],
                )
                conn.executemany(
                    "INSERT INTO service_availability_observations(created_at) VALUES (?)",
                    [
                        ("2020-01-01T00:00:00+00:00",),
                        ("2099-01-01T00:00:00+00:00",),
                    ],
                )
                conn.commit()

            dry_run = subprocess.run(
                [sys.executable, str(PRUNE_SCRIPT), "--db", str(database)],
                cwd=PROJECT_ROOT,
                text=True,
                capture_output=True,
                check=False,
            )
            self.assertEqual(dry_run.returncode, 0, dry_run.stderr)
            self.assertEqual(
                json.loads(dry_run.stdout)["results"][0]["tables"][
                    "admin_audit_noise"
                ]["candidates"],
                1,
            )

            applied = subprocess.run(
                [
                    sys.executable,
                    str(PRUNE_SCRIPT),
                    "--db",
                    str(database),
                    "--apply",
                    "--batch-size",
                    "100",
                ],
                cwd=PROJECT_ROOT,
                text=True,
                capture_output=True,
                check=False,
            )
            self.assertEqual(applied.returncode, 0, applied.stderr)
            with sqlite3.connect(database) as conn:
                actions = conn.execute(
                    "SELECT action FROM admin_audit_log ORDER BY id"
                ).fetchall()
                observations = conn.execute(
                    "SELECT created_at FROM service_availability_observations ORDER BY id"
                ).fetchall()
                users = conn.execute("SELECT COUNT(*) FROM users").fetchone()[0]
                quick_check = conn.execute("PRAGMA quick_check").fetchone()[0]
            self.assertEqual(actions, [("admin_staff_login_succeeded",)])
            self.assertEqual(observations, [("2099-01-01T00:00:00+00:00",)])
            self.assertEqual(users, 1)
            self.assertEqual(quick_check, "ok")

    def test_row_limit_removes_oldest_observations(self) -> None:
        with tempfile.TemporaryDirectory(
            prefix="greenvpn-retention-limit-",
            ignore_cleanup_errors=True,
        ) as root:
            database = Path(root) / "bluevpn.db"
            with sqlite3.connect(database) as conn:
                conn.execute(
                    """
                    CREATE TABLE service_availability_observations (
                        id INTEGER PRIMARY KEY AUTOINCREMENT,
                        created_at TEXT NOT NULL
                    )
                    """
                )
                conn.executemany(
                    "INSERT INTO service_availability_observations(created_at) VALUES (?)",
                    [
                        (f"2099-01-01T00:00:0{index}+00:00",)
                        for index in range(1, 6)
                    ],
                )
                conn.commit()
                rows_before, candidates, deleted = RETENTION.delete_oldest_over_limit(
                    conn,
                    "service_availability_observations",
                    "created_at",
                    max_rows=2,
                    batch_size=100,
                )
                remaining = conn.execute(
                    "SELECT id FROM service_availability_observations ORDER BY id"
                ).fetchall()

            self.assertEqual(rows_before, 5)
            self.assertEqual(candidates, 3)
            self.assertEqual(deleted, 3)
            self.assertEqual(remaining, [(4,), (5,)])


if __name__ == "__main__":
    unittest.main()
