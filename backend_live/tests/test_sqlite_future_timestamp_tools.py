from __future__ import annotations

import json
import pathlib
import sqlite3
import subprocess
import sys
import tempfile
import unittest


REPO_ROOT = pathlib.Path(__file__).resolve().parents[2]
AUDIT_SCRIPT = REPO_ROOT / "scripts" / "ops" / "audit_sqlite_future_timestamps.py"
REPAIR_SCRIPT = (
    REPO_ROOT / "scripts" / "ops" / "repair_sqlite_future_event_timestamps.py"
)
REFERENCE_NOW = "2026-07-13T14:00:00Z"


def run_json(*args: object) -> dict[str, object]:
    result = subprocess.run(
        [sys.executable, *(str(arg) for arg in args)],
        check=True,
        capture_output=True,
        text=True,
        encoding="utf-8",
    )
    return json.loads(result.stdout)


class SqliteFutureTimestampToolsTest(unittest.TestCase):
    def test_trusted_reference_repairs_event_but_preserves_deadline(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            root = pathlib.Path(temp_dir)
            database = root / "state.sqlite"
            backup = root / "state-before-repair.sqlite"
            conn = sqlite3.connect(database)
            try:
                conn.execute(
                    "CREATE TABLE events ("
                    "id INTEGER PRIMARY KEY, created_at TEXT, expires_at TEXT)"
                )
                conn.execute(
                    "INSERT INTO events(created_at, expires_at) VALUES (?, ?)",
                    ("2026-07-13T17:00:00Z", "2026-07-13T18:00:00Z"),
                )
                conn.commit()
            finally:
                conn.close()

            audit = run_json(
                AUDIT_SCRIPT,
                "--db",
                database,
                "--reference-now",
                REFERENCE_NOW,
            )
            self.assertEqual(audit["eventFutureValues"], 1)
            self.assertEqual(audit["deadlineFutureValues"], 1)

            dry_run = run_json(
                REPAIR_SCRIPT,
                "--db",
                database,
                "--offset-seconds",
                10800,
                "--reference-now",
                REFERENCE_NOW,
            )
            self.assertEqual(dry_run["candidateValues"], 1)
            self.assertEqual(dry_run["blockers"], [])

            applied = run_json(
                REPAIR_SCRIPT,
                "--db",
                database,
                "--backup",
                backup,
                "--offset-seconds",
                10800,
                "--reference-now",
                REFERENCE_NOW,
                "--apply",
            )
            self.assertEqual(applied["updatedValues"], 1)
            self.assertEqual(applied["backupQuickCheck"], "ok")

            conn = sqlite3.connect(database)
            try:
                created_at, expires_at = conn.execute(
                    "SELECT created_at, expires_at FROM events"
                ).fetchone()
            finally:
                conn.close()
            self.assertEqual(created_at, "2026-07-13T14:00:00Z")
            self.assertEqual(expires_at, "2026-07-13T18:00:00Z")

            post_audit = run_json(
                AUDIT_SCRIPT,
                "--db",
                database,
                "--reference-now",
                REFERENCE_NOW,
            )
            self.assertEqual(post_audit["eventFutureValues"], 0)
            self.assertEqual(post_audit["deadlineFutureValues"], 1)
            self.assertTrue(post_audit["ok"])


if __name__ == "__main__":
    unittest.main()
