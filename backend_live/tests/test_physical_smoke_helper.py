from __future__ import annotations

import contextlib
import importlib.util
import io
import json
import sqlite3
import tempfile
import unittest
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[2]
HELPER_PATH = (
    REPO_ROOT
    / "scripts"
    / "ops"
    / "manage_paid_beta_free_physical_smoke.py"
)


def load_helper():
    spec = importlib.util.spec_from_file_location(
        "manage_paid_beta_free_physical_smoke",
        HELPER_PATH,
    )
    if spec is None or spec.loader is None:
        raise RuntimeError("Unable to load physical smoke helper.")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class FakeBackend:
    PAID_BETA_COHORT_CODE = "paid_beta"

    def __init__(self) -> None:
        self.connection = sqlite3.connect(":memory:")
        self.connection.row_factory = sqlite3.Row
        self.connection.executescript(
            """
            CREATE TABLE users (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                email TEXT NOT NULL,
                password_hash TEXT NOT NULL,
                email_verified INTEGER NOT NULL,
                email_verified_at TEXT,
                access_cohort TEXT,
                acquisition_source TEXT,
                cohort_enrolled_at TEXT,
                created_at TEXT,
                updated_at TEXT
            );
            CREATE TABLE subscriptions (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                user_id INTEGER NOT NULL,
                is_active INTEGER NOT NULL,
                expires_at TEXT,
                updated_at TEXT
            );
            """
        )

    @contextlib.contextmanager
    def db(self):
        yield self.connection

    @staticmethod
    def utc_now_iso() -> str:
        return "2026-07-25T00:00:00Z"

    @staticmethod
    def hash_password(value: str) -> str:
        return f"hashed:{len(value)}"

    @staticmethod
    def create_trial_subscription(conn: sqlite3.Connection, user_id: int) -> None:
        conn.execute(
            """
            INSERT INTO subscriptions(user_id, is_active, expires_at, updated_at)
            VALUES (?, 1, NULL, ?)
            """,
            (user_id, "2026-07-25T00:00:00Z"),
        )


class PhysicalSmokeHelperTests(unittest.TestCase):
    def test_create_writes_context_after_expiring_single_trial(self) -> None:
        helper = load_helper()
        backend = FakeBackend()
        self.addCleanup(backend.connection.close)

        with tempfile.TemporaryDirectory() as temporary:
            context_path = Path(temporary) / "smoke.json"
            with contextlib.redirect_stdout(io.StringIO()):
                result = helper.create_smoke_user(backend, context_path)

            self.assertEqual(result, 0)
            context = json.loads(context_path.read_text(encoding="utf-8"))
            self.assertEqual(context["subscriptionCount"], 1)
            self.assertFalse(context["cleaned"])
            row = backend.connection.execute(
                """
                SELECT is_active, expires_at
                FROM subscriptions
                WHERE user_id = ?
                """,
                (context["userId"],),
            ).fetchone()
            self.assertIsNotNone(row)
            self.assertEqual(row["is_active"], 0)
            self.assertEqual(row["expires_at"], backend.utc_now_iso())


if __name__ == "__main__":
    unittest.main()
