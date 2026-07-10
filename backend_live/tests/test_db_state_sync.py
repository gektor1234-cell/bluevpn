import sqlite3
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


PROJECT_ROOT = Path(__file__).resolve().parents[2]
SYNC_SCRIPT = PROJECT_ROOT / "scripts" / "ops" / "greenvpn_sqlite_state_sync.py"


def create_users_db(
    path: Path,
    *,
    cohort: str,
    source: str,
    updated_at: str,
) -> None:
    with sqlite3.connect(path) as conn:
        conn.execute(
            """
            CREATE TABLE users (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                email TEXT NOT NULL UNIQUE,
                access_cohort TEXT NOT NULL DEFAULT 'stable',
                acquisition_source TEXT,
                cohort_enrolled_at TEXT,
                created_at TEXT NOT NULL,
                updated_at TEXT
            )
            """
        )
        conn.execute(
            """
            INSERT INTO users(
                id, email, access_cohort, acquisition_source,
                cohort_enrolled_at, created_at, updated_at
            )
            VALUES (?, ?, ?, ?, ?, ?, ?)
            """,
            (
                1,
                "sync@example.test",
                cohort,
                source,
                "2026-07-10T10:00:00+00:00",
                "2026-07-01T00:00:00+00:00",
                updated_at,
            ),
        )
        conn.commit()


class DbStateSyncTests(unittest.TestCase):
    def run_sync(self, source_db: Path, target_db: Path) -> subprocess.CompletedProcess:
        return subprocess.run(
            [
                sys.executable,
                str(SYNC_SCRIPT),
                "--source-db",
                str(source_db),
                "--target-db",
                str(target_db),
                "--apply",
                "--tables",
                "users",
            ],
            cwd=PROJECT_ROOT,
            text=True,
            capture_output=True,
            check=False,
        )

    def test_newer_cohort_update_reaches_peer(self) -> None:
        with tempfile.TemporaryDirectory(
            prefix="greenvpn-state-sync-",
            ignore_cleanup_errors=True,
        ) as root:
            source_db = Path(root) / "source.sqlite"
            target_db = Path(root) / "target.sqlite"
            create_users_db(
                source_db,
                cohort="paid_beta_v1",
                source="invite-alpha",
                updated_at="2026-07-10T10:00:00+00:00",
            )
            create_users_db(
                target_db,
                cohort="stable",
                source="legacy",
                updated_at="2026-07-10T09:00:00+00:00",
            )

            result = self.run_sync(source_db, target_db)
            self.assertEqual(result.returncode, 0, result.stderr or result.stdout)
            with sqlite3.connect(target_db) as conn:
                row = conn.execute(
                    "SELECT access_cohort, acquisition_source FROM users WHERE id = 1"
                ).fetchone()
            self.assertEqual(row, ("paid_beta_v1", "invite-alpha"))

    def test_older_snapshot_does_not_overwrite_newer_cohort(self) -> None:
        with tempfile.TemporaryDirectory(
            prefix="greenvpn-state-sync-",
            ignore_cleanup_errors=True,
        ) as root:
            source_db = Path(root) / "source.sqlite"
            target_db = Path(root) / "target.sqlite"
            create_users_db(
                source_db,
                cohort="stable",
                source="legacy",
                updated_at="2026-07-10T09:00:00+00:00",
            )
            create_users_db(
                target_db,
                cohort="paid_beta_v1",
                source="invite-alpha",
                updated_at="2026-07-10T10:00:00+00:00",
            )

            result = self.run_sync(source_db, target_db)
            self.assertEqual(result.returncode, 0, result.stderr or result.stdout)
            with sqlite3.connect(target_db) as conn:
                row = conn.execute(
                    "SELECT access_cohort, acquisition_source FROM users WHERE id = 1"
                ).fetchone()
            self.assertEqual(row, ("paid_beta_v1", "invite-alpha"))


if __name__ == "__main__":
    unittest.main()
