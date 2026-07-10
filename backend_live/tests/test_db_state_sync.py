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
    def run_sync(
        self,
        source_db: Path,
        target_db: Path,
        tables: list[str] | None = None,
    ) -> subprocess.CompletedProcess:
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
                *(tables or ["users"]),
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

    def test_beta_invite_redemption_and_funnel_event_reach_peer(self) -> None:
        with tempfile.TemporaryDirectory(
            prefix="greenvpn-beta-sync-",
            ignore_cleanup_errors=True,
        ) as root:
            source_db = Path(root) / "source.sqlite"
            target_db = Path(root) / "target.sqlite"
            for path, used_count, updated_at in [
                (source_db, 1, "2026-07-10T11:00:00+00:00"),
                (target_db, 0, "2026-07-10T10:00:00+00:00"),
            ]:
                with sqlite3.connect(path) as conn:
                    conn.executescript(
                        """
                        CREATE TABLE beta_invites (
                            id INTEGER PRIMARY KEY AUTOINCREMENT,
                            public_id TEXT NOT NULL UNIQUE,
                            code_hash TEXT NOT NULL UNIQUE,
                            used_count INTEGER NOT NULL,
                            updated_at TEXT NOT NULL
                        );
                        CREATE TABLE beta_invite_redemptions (
                            id INTEGER PRIMARY KEY AUTOINCREMENT,
                            public_id TEXT NOT NULL UNIQUE,
                            invite_public_id TEXT NOT NULL,
                            user_id INTEGER NOT NULL UNIQUE,
                            status TEXT NOT NULL,
                            created_at TEXT NOT NULL,
                            updated_at TEXT NOT NULL
                        );
                        CREATE TABLE beta_funnel_events (
                            id INTEGER PRIMARY KEY AUTOINCREMENT,
                            event_id TEXT NOT NULL UNIQUE,
                            event_type TEXT NOT NULL,
                            user_id INTEGER,
                            created_at TEXT NOT NULL,
                            updated_at TEXT NOT NULL
                        );
                        """
                    )
                    conn.execute(
                        "INSERT INTO beta_invites(public_id, code_hash, used_count, updated_at) VALUES (?, ?, ?, ?)",
                        ("inv_sync", "hash_sync", used_count, updated_at),
                    )
                    if path == source_db:
                        conn.execute(
                            """
                            INSERT INTO beta_invite_redemptions(
                                public_id, invite_public_id, user_id, status,
                                created_at, updated_at
                            ) VALUES (?, ?, ?, ?, ?, ?)
                            """,
                            (
                                "red_sync",
                                "inv_sync",
                                1,
                                "redeemed",
                                updated_at,
                                updated_at,
                            ),
                        )
                        conn.execute(
                            """
                            INSERT INTO beta_funnel_events(
                                event_id, event_type, user_id, created_at, updated_at
                            ) VALUES (?, ?, ?, ?, ?)
                            """,
                            (
                                "invite_claimed:inv_sync:1",
                                "invite_claimed",
                                1,
                                updated_at,
                                updated_at,
                            ),
                        )
                    conn.commit()

            result = self.run_sync(
                source_db,
                target_db,
                tables=[
                    "beta_invites",
                    "beta_invite_redemptions",
                    "beta_funnel_events",
                ],
            )
            self.assertEqual(result.returncode, 0, result.stderr or result.stdout)
            with sqlite3.connect(target_db) as conn:
                invite = conn.execute(
                    "SELECT used_count FROM beta_invites WHERE public_id = 'inv_sync'"
                ).fetchone()
                redemption = conn.execute(
                    "SELECT status FROM beta_invite_redemptions WHERE user_id = 1"
                ).fetchone()
                event = conn.execute(
                    "SELECT event_type FROM beta_funnel_events WHERE event_id = 'invite_claimed:inv_sync:1'"
                ).fetchone()
            self.assertEqual(invite, (1,))
            self.assertEqual(redemption, ("redeemed",))
            self.assertEqual(event, ("invite_claimed",))

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
