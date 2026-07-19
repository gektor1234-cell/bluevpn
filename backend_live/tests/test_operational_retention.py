import json
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


if __name__ == "__main__":
    unittest.main()
