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

    def test_email_verification_timestamp_converges_without_updated_at_change(self) -> None:
        with tempfile.TemporaryDirectory(
            prefix="greenvpn-email-verified-sync-",
            ignore_cleanup_errors=True,
        ) as root:
            source_db = Path(root) / "source.sqlite"
            target_db = Path(root) / "target.sqlite"
            schema = """
                CREATE TABLE users (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    email TEXT NOT NULL UNIQUE,
                    email_verified INTEGER NOT NULL,
                    email_verified_at TEXT,
                    access_cohort TEXT NOT NULL,
                    created_at TEXT NOT NULL,
                    updated_at TEXT
                );
            """
            for path, verified_at, cohort in [
                (source_db, "2026-07-18T10:00:00+00:00", "stable"),
                (target_db, "2026-07-01T10:00:00+00:00", "paid_beta_v1"),
            ]:
                with sqlite3.connect(path) as conn:
                    conn.executescript(schema)
                    conn.execute(
                        """
                        INSERT INTO users(
                            email, email_verified, email_verified_at,
                            access_cohort, created_at, updated_at
                        ) VALUES (?, ?, ?, ?, ?, ?)
                        """,
                        (
                            "verified@example.test",
                            1,
                            verified_at,
                            cohort,
                            "2026-06-01T00:00:00+00:00",
                            "2026-07-10T00:00:00+00:00",
                        ),
                    )
                    conn.commit()

            result = self.run_sync(source_db, target_db)
            self.assertEqual(result.returncode, 0, result.stderr or result.stdout)
            with sqlite3.connect(target_db) as conn:
                row = conn.execute(
                    "SELECT email_verified_at, access_cohort FROM users"
                ).fetchone()
            self.assertEqual(
                row,
                ("2026-07-18T10:00:00+00:00", "paid_beta_v1"),
            )

    def test_newer_general_update_cannot_regress_verified_contacts(self) -> None:
        with tempfile.TemporaryDirectory(
            prefix="greenvpn-contact-state-sync-",
            ignore_cleanup_errors=True,
        ) as root:
            source_db = Path(root) / "source.sqlite"
            target_db = Path(root) / "target.sqlite"
            schema = """
                CREATE TABLE users (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    email TEXT NOT NULL UNIQUE,
                    email_verified INTEGER NOT NULL,
                    email_verified_at TEXT,
                    phone TEXT,
                    phone_verified INTEGER NOT NULL,
                    phone_verified_at TEXT,
                    access_cohort TEXT NOT NULL,
                    created_at TEXT NOT NULL,
                    updated_at TEXT
                );
            """
            rows = (
                (
                    source_db,
                    "2026-07-10T10:00:00+00:00",
                    "+70000000001",
                    0,
                    None,
                    "paid_beta_v1",
                    "2026-07-19T10:00:00+00:00",
                ),
                (
                    target_db,
                    "2026-07-18T10:00:00+00:00",
                    "+70000000002",
                    1,
                    "2026-07-18T11:00:00+00:00",
                    "stable",
                    "2026-07-18T12:00:00+00:00",
                ),
            )
            for (
                path,
                email_verified_at,
                phone,
                phone_verified,
                phone_verified_at,
                cohort,
                updated_at,
            ) in rows:
                with sqlite3.connect(path) as conn:
                    conn.executescript(schema)
                    conn.execute(
                        """
                        INSERT INTO users(
                            email, email_verified, email_verified_at,
                            phone, phone_verified, phone_verified_at,
                            access_cohort, created_at, updated_at
                        ) VALUES (?, 1, ?, ?, ?, ?, ?, ?, ?)
                        """,
                        (
                            "verified@example.test",
                            email_verified_at,
                            phone,
                            phone_verified,
                            phone_verified_at,
                            cohort,
                            "2026-06-01T00:00:00+00:00",
                            updated_at,
                        ),
                    )
                    conn.commit()

            result = self.run_sync(source_db, target_db)
            self.assertEqual(result.returncode, 0, result.stderr or result.stdout)
            with sqlite3.connect(target_db) as conn:
                row = conn.execute(
                    """
                    SELECT email_verified, email_verified_at, phone,
                           phone_verified, phone_verified_at, access_cohort
                    FROM users
                    """
                ).fetchone()
            self.assertEqual(
                row,
                (
                    1,
                    "2026-07-18T10:00:00+00:00",
                    "+70000000002",
                    1,
                    "2026-07-18T11:00:00+00:00",
                    "paid_beta_v1",
                ),
            )

    def test_admin_session_revocation_and_last_seen_merge_monotonically(self) -> None:
        with tempfile.TemporaryDirectory(
            prefix="greenvpn-admin-session-sync-",
            ignore_cleanup_errors=True,
        ) as root:
            source_db = Path(root) / "source.sqlite"
            target_db = Path(root) / "target.sqlite"
            schema = """
                CREATE TABLE admin_sessions (
                    token_hash TEXT PRIMARY KEY,
                    staff_id INTEGER NOT NULL,
                    created_at TEXT NOT NULL,
                    expires_at TEXT NOT NULL,
                    last_seen_at TEXT,
                    revoked_at TEXT,
                    request_ip TEXT,
                    user_agent TEXT
                );
            """
            for path, last_seen, revoked_at in [
                (
                    source_db,
                    "2026-07-18T10:00:00+00:00",
                    "2026-07-18T10:05:00+00:00",
                ),
                (target_db, "2026-07-18T10:10:00+00:00", None),
            ]:
                with sqlite3.connect(path) as conn:
                    conn.executescript(schema)
                    conn.execute(
                        """
                        INSERT INTO admin_sessions(
                            token_hash, staff_id, created_at, expires_at,
                            last_seen_at, revoked_at, request_ip, user_agent
                        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                        """,
                        (
                            "session-hash",
                            1,
                            "2026-07-18T09:00:00+00:00",
                            "2026-07-19T09:00:00+00:00",
                            last_seen,
                            revoked_at,
                            "127.0.0.1",
                            "test",
                        ),
                    )
                    conn.commit()

            result = self.run_sync(
                source_db,
                target_db,
                tables=["admin_sessions"],
            )
            self.assertEqual(result.returncode, 0, result.stderr or result.stdout)
            with sqlite3.connect(target_db) as conn:
                row = conn.execute(
                    "SELECT last_seen_at, revoked_at FROM admin_sessions"
                ).fetchone()
            self.assertEqual(
                row,
                (
                    "2026-07-18T10:10:00+00:00",
                    "2026-07-18T10:05:00+00:00",
                ),
            )

    def test_sent_outbox_state_reaches_pending_peer_and_cannot_revert(self) -> None:
        with tempfile.TemporaryDirectory(
            prefix="greenvpn-outbox-sync-",
            ignore_cleanup_errors=True,
        ) as root:
            sent_db = Path(root) / "sent.sqlite"
            pending_db = Path(root) / "pending.sqlite"
            schema = """
                CREATE TABLE email_outbox (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    user_id INTEGER,
                    email TEXT NOT NULL,
                    subject TEXT NOT NULL,
                    body TEXT NOT NULL,
                    status TEXT NOT NULL,
                    error TEXT,
                    created_at TEXT NOT NULL,
                    sent_at TEXT
                );
            """
            for path, status, sent_at in [
                (sent_db, "sent", "2026-07-18T10:05:00+00:00"),
                (pending_db, "pending", None),
            ]:
                with sqlite3.connect(path) as conn:
                    conn.executescript(schema)
                    conn.execute(
                        """
                        INSERT INTO email_outbox(
                            user_id, email, subject, body, status,
                            error, created_at, sent_at
                        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                        """,
                        (
                            1,
                            "mail@example.test",
                            "Login code",
                            "masked",
                            status,
                            None,
                            "2026-07-18T10:00:00+00:00",
                            sent_at,
                        ),
                    )
                    conn.commit()

            result = self.run_sync(
                sent_db,
                pending_db,
                tables=["email_outbox"],
            )
            self.assertEqual(result.returncode, 0, result.stderr or result.stdout)
            reverse = self.run_sync(
                pending_db,
                sent_db,
                tables=["email_outbox"],
            )
            self.assertEqual(reverse.returncode, 0, reverse.stderr or reverse.stdout)
            for path in (sent_db, pending_db):
                with sqlite3.connect(path) as conn:
                    row = conn.execute(
                        "SELECT status, sent_at FROM email_outbox"
                    ).fetchone()
                self.assertEqual(
                    row,
                    ("sent", "2026-07-18T10:05:00+00:00"),
                )

    def test_optional_table_missing_on_both_nodes_is_not_an_error(self) -> None:
        with tempfile.TemporaryDirectory(
            prefix="greenvpn-optional-table-absent-",
            ignore_cleanup_errors=True,
        ) as root:
            source_db = Path(root) / "source.sqlite"
            target_db = Path(root) / "target.sqlite"
            for path in (source_db, target_db):
                with sqlite3.connect(path) as conn:
                    conn.execute("CREATE TABLE placeholder(id INTEGER PRIMARY KEY)")
                    conn.commit()

            result = self.run_sync(
                source_db,
                target_db,
                tables=["beta_invites"],
            )

            self.assertEqual(result.returncode, 0, result.stderr or result.stdout)

    def test_table_present_on_only_one_node_remains_an_error(self) -> None:
        with tempfile.TemporaryDirectory(
            prefix="greenvpn-table-schema-mismatch-",
            ignore_cleanup_errors=True,
        ) as root:
            source_db = Path(root) / "source.sqlite"
            target_db = Path(root) / "target.sqlite"
            with sqlite3.connect(source_db) as conn:
                conn.execute(
                    "CREATE TABLE beta_invites(public_id TEXT PRIMARY KEY)"
                )
                conn.commit()
            with sqlite3.connect(target_db) as conn:
                conn.execute("CREATE TABLE placeholder(id INTEGER PRIMARY KEY)")
                conn.commit()

            result = self.run_sync(
                source_db,
                target_db,
                tables=["beta_invites"],
            )

            self.assertEqual(result.returncode, 3, result.stderr or result.stdout)

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

    def test_transport_assignment_reaches_peer_without_id_collision(self) -> None:
        with tempfile.TemporaryDirectory(
            prefix="greenvpn-transport-assignment-sync-",
            ignore_cleanup_errors=True,
        ) as root:
            source_db = Path(root) / "source.sqlite"
            target_db = Path(root) / "target.sqlite"
            schema = """
                CREATE TABLE device_transport_assignments (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    device_uid TEXT NOT NULL,
                    transport_key TEXT NOT NULL,
                    assigned_ip TEXT NOT NULL,
                    created_at TEXT NOT NULL,
                    updated_at TEXT NOT NULL,
                    UNIQUE(device_uid, transport_key),
                    UNIQUE(transport_key, assigned_ip)
                );
            """
            for path in (source_db, target_db):
                with sqlite3.connect(path) as conn:
                    conn.executescript(schema)
                    conn.commit()
            with sqlite3.connect(source_db) as conn:
                conn.execute(
                    """
                    INSERT INTO device_transport_assignments(
                        id, device_uid, transport_key, assigned_ip, created_at, updated_at
                    ) VALUES (?, ?, ?, ?, ?, ?)
                    """,
                    (1, "device-a", "amneziawg", "10.202.0.50", "2026-07-11T18:00:00+00:00", "2026-07-11T18:00:00+00:00"),
                )
                conn.commit()
            with sqlite3.connect(target_db) as conn:
                conn.execute(
                    """
                    INSERT INTO device_transport_assignments(
                        id, device_uid, transport_key, assigned_ip, created_at, updated_at
                    ) VALUES (?, ?, ?, ?, ?, ?)
                    """,
                    (1, "device-b", "amneziawg", "10.202.0.60", "2026-07-11T17:00:00+00:00", "2026-07-11T17:00:00+00:00"),
                )
                conn.commit()

            result = self.run_sync(
                source_db,
                target_db,
                tables=["device_transport_assignments"],
            )
            self.assertEqual(result.returncode, 0, result.stderr or result.stdout)
            with sqlite3.connect(target_db) as conn:
                row = conn.execute(
                    """
                    SELECT assigned_ip
                    FROM device_transport_assignments
                    WHERE device_uid = 'device-a' AND transport_key = 'amneziawg'
                    """
                ).fetchone()
            self.assertEqual(row, ("10.202.0.50",))

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

    def test_naive_source_timestamp_updates_older_aware_target(self) -> None:
        with tempfile.TemporaryDirectory(
            prefix="greenvpn-state-sync-",
            ignore_cleanup_errors=True,
        ) as root:
            source_db = Path(root) / "source.sqlite"
            target_db = Path(root) / "target.sqlite"
            create_users_db(
                source_db,
                cohort="paid_beta_v1",
                source="payment",
                updated_at="2026-07-10T10:00:00",
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
            self.assertEqual(row, ("paid_beta_v1", "payment"))

    def test_older_naive_source_does_not_overwrite_newer_aware_target(self) -> None:
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
                updated_at="2026-07-10T09:00:00",
            )
            create_users_db(
                target_db,
                cohort="paid_beta_v1",
                source="payment",
                updated_at="2026-07-10T10:00:00+00:00",
            )

            result = self.run_sync(source_db, target_db)
            self.assertEqual(result.returncode, 0, result.stderr or result.stdout)
            with sqlite3.connect(target_db) as conn:
                row = conn.execute(
                    "SELECT access_cohort, acquisition_source FROM users WHERE id = 1"
                ).fetchone()
            self.assertEqual(row, ("paid_beta_v1", "payment"))

    def test_explicit_tombstone_deletes_peer_row(self) -> None:
        with tempfile.TemporaryDirectory(
            prefix="greenvpn-tombstone-sync-",
            ignore_cleanup_errors=True,
        ) as root:
            source_db = Path(root) / "source.sqlite"
            target_db = Path(root) / "target.sqlite"
            schema = """
                CREATE TABLE users (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    email TEXT NOT NULL UNIQUE,
                    created_at TEXT NOT NULL,
                    updated_at TEXT
                );
                CREATE TABLE replication_tombstones (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    table_name TEXT NOT NULL,
                    natural_key_json TEXT NOT NULL,
                    deleted_at TEXT NOT NULL,
                    origin_node TEXT NOT NULL,
                    UNIQUE(table_name, natural_key_json)
                );
            """
            for path in (source_db, target_db):
                with sqlite3.connect(path) as conn:
                    conn.executescript(schema)
                    conn.commit()
            with sqlite3.connect(target_db) as conn:
                conn.execute(
                    "INSERT INTO users(email, created_at, updated_at) VALUES (?, ?, ?)",
                    (
                        "deleted@example.test",
                        "2026-07-13T08:00:00+00:00",
                        "2026-07-13T08:00:00+00:00",
                    ),
                )
                conn.commit()
            with sqlite3.connect(source_db) as conn:
                conn.execute(
                    """
                    INSERT INTO replication_tombstones(
                        table_name, natural_key_json, deleted_at, origin_node
                    ) VALUES (?, ?, ?, ?)
                    """,
                    (
                        "users",
                        '{"email":"deleted@example.test"}',
                        "2026-07-13T09:00:00+00:00",
                        "timeweb",
                    ),
                )
                conn.commit()

            result = self.run_sync(
                source_db,
                target_db,
                tables=["users", "replication_tombstones"],
            )

            self.assertEqual(result.returncode, 0, result.stderr or result.stdout)
            with sqlite3.connect(target_db) as conn:
                user_count = conn.execute("SELECT COUNT(*) FROM users").fetchone()[0]
                tombstone_count = conn.execute(
                    "SELECT COUNT(*) FROM replication_tombstones"
                ).fetchone()[0]
            self.assertEqual(user_count, 0)
            self.assertEqual(tombstone_count, 1)

    def test_newer_recreated_row_survives_old_tombstone(self) -> None:
        with tempfile.TemporaryDirectory(
            prefix="greenvpn-tombstone-recreate-",
            ignore_cleanup_errors=True,
        ) as root:
            source_db = Path(root) / "source.sqlite"
            target_db = Path(root) / "target.sqlite"
            schema = """
                CREATE TABLE users (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    email TEXT NOT NULL UNIQUE,
                    created_at TEXT NOT NULL,
                    updated_at TEXT
                );
                CREATE TABLE replication_tombstones (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    table_name TEXT NOT NULL,
                    natural_key_json TEXT NOT NULL,
                    deleted_at TEXT NOT NULL,
                    origin_node TEXT NOT NULL,
                    UNIQUE(table_name, natural_key_json)
                );
            """
            for path in (source_db, target_db):
                with sqlite3.connect(path) as conn:
                    conn.executescript(schema)
                    conn.execute(
                        """
                        INSERT INTO replication_tombstones(
                            table_name, natural_key_json, deleted_at, origin_node
                        ) VALUES (?, ?, ?, ?)
                        """,
                        (
                            "users",
                            '{"email":"recreated@example.test"}',
                            "2026-07-13T09:00:00+00:00",
                            "timeweb",
                        ),
                    )
                    conn.commit()
            with sqlite3.connect(target_db) as conn:
                conn.execute(
                    "INSERT INTO users(email, created_at, updated_at) VALUES (?, ?, ?)",
                    (
                        "recreated@example.test",
                        "2026-07-13T10:00:00+00:00",
                        "2026-07-13T10:00:00+00:00",
                    ),
                )
                conn.commit()

            result = self.run_sync(
                source_db,
                target_db,
                tables=["users", "replication_tombstones"],
            )

            self.assertEqual(result.returncode, 0, result.stderr or result.stdout)
            with sqlite3.connect(target_db) as conn:
                row = conn.execute(
                    "SELECT email FROM users WHERE email = ?",
                    ("recreated@example.test",),
                ).fetchone()
            self.assertEqual(row, ("recreated@example.test",))

    def test_user_tombstone_removes_network_and_access_dependents(self) -> None:
        with tempfile.TemporaryDirectory(
            prefix="greenvpn-account-tombstone-sync-",
            ignore_cleanup_errors=True,
        ) as root:
            source_db = Path(root) / "source.sqlite"
            target_db = Path(root) / "target.sqlite"
            schema = """
                CREATE TABLE users (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    email TEXT NOT NULL UNIQUE,
                    created_at TEXT NOT NULL,
                    updated_at TEXT
                );
                CREATE TABLE devices (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    user_id INTEGER NOT NULL,
                    device_uid TEXT NOT NULL UNIQUE,
                    created_at TEXT NOT NULL,
                    updated_at TEXT NOT NULL
                );
                CREATE TABLE device_transport_assignments (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    device_uid TEXT NOT NULL,
                    transport_key TEXT NOT NULL,
                    assigned_ip TEXT NOT NULL,
                    created_at TEXT NOT NULL,
                    updated_at TEXT NOT NULL,
                    UNIQUE(device_uid, transport_key),
                    UNIQUE(transport_key, assigned_ip)
                );
                CREATE TABLE client_endpoint_assignments (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    user_id INTEGER NOT NULL,
                    device_uid TEXT NOT NULL,
                    server_id TEXT NOT NULL,
                    created_at TEXT NOT NULL,
                    updated_at TEXT NOT NULL,
                    UNIQUE(user_id, device_uid)
                );
                CREATE TABLE client_route_events (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    user_id INTEGER NOT NULL,
                    device_uid TEXT NOT NULL,
                    created_at TEXT NOT NULL
                );
                CREATE TABLE ad_challenges (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    public_id TEXT NOT NULL UNIQUE,
                    user_id INTEGER NOT NULL,
                    device_uid TEXT NOT NULL,
                    created_at TEXT NOT NULL,
                    updated_at TEXT NOT NULL
                );
                CREATE TABLE free_access_grants (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    public_id TEXT NOT NULL UNIQUE,
                    user_id INTEGER NOT NULL,
                    device_uid TEXT NOT NULL,
                    created_at TEXT NOT NULL,
                    updated_at TEXT NOT NULL
                );
                CREATE TABLE replication_tombstones (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    table_name TEXT NOT NULL,
                    natural_key_json TEXT NOT NULL,
                    deleted_at TEXT NOT NULL,
                    origin_node TEXT NOT NULL,
                    UNIQUE(table_name, natural_key_json)
                );
            """
            for path in (source_db, target_db):
                with sqlite3.connect(path) as conn:
                    conn.executescript(schema)
                    conn.commit()
            with sqlite3.connect(target_db) as conn:
                created = "2026-07-13T08:00:00+00:00"
                conn.execute(
                    "INSERT INTO users(id, email, created_at, updated_at) VALUES (?, ?, ?, ?)",
                    (1, "network-delete@example.test", created, created),
                )
                conn.execute(
                    "INSERT INTO devices(user_id, device_uid, created_at, updated_at) VALUES (?, ?, ?, ?)",
                    (1, "network-delete-device", created, created),
                )
                conn.execute(
                    "INSERT INTO device_transport_assignments(device_uid, transport_key, assigned_ip, created_at, updated_at) VALUES (?, ?, ?, ?, ?)",
                    ("network-delete-device", "amneziawg", "10.202.0.24", created, created),
                )
                conn.execute(
                    "INSERT INTO client_endpoint_assignments(user_id, device_uid, server_id, created_at, updated_at) VALUES (?, ?, ?, ?, ?)",
                    (1, "network-delete-device", "intelligent_smew", created, created),
                )
                conn.execute(
                    "INSERT INTO client_route_events(user_id, device_uid, created_at) VALUES (?, ?, ?)",
                    (1, "network-delete-device", created),
                )
                conn.execute(
                    "INSERT INTO ad_challenges(public_id, user_id, device_uid, created_at, updated_at) VALUES (?, ?, ?, ?, ?)",
                    ("ad-delete", 1, "network-delete-device", created, created),
                )
                conn.execute(
                    "INSERT INTO free_access_grants(public_id, user_id, device_uid, created_at, updated_at) VALUES (?, ?, ?, ?, ?)",
                    ("grant-delete", 1, "network-delete-device", created, created),
                )
                conn.commit()
            with sqlite3.connect(source_db) as conn:
                conn.execute(
                    """
                    INSERT INTO replication_tombstones(
                        table_name, natural_key_json, deleted_at, origin_node
                    ) VALUES (?, ?, ?, ?)
                    """,
                    (
                        "users",
                        '{"email":"network-delete@example.test"}',
                        "2026-07-13T09:00:00+00:00",
                        "timeweb",
                    ),
                )
                conn.commit()

            result = self.run_sync(
                source_db,
                target_db,
                tables=[
                    "users",
                    "devices",
                    "device_transport_assignments",
                    "client_endpoint_assignments",
                    "ad_challenges",
                    "free_access_grants",
                    "replication_tombstones",
                ],
            )

            self.assertEqual(result.returncode, 0, result.stderr or result.stdout)
            with sqlite3.connect(target_db) as conn:
                for table in (
                    "users",
                    "devices",
                    "device_transport_assignments",
                    "client_endpoint_assignments",
                    "client_route_events",
                    "ad_challenges",
                    "free_access_grants",
                ):
                    self.assertEqual(
                        conn.execute(f"SELECT COUNT(*) FROM {table}").fetchone()[0],
                        0,
                        table,
                    )

    def test_user_foreign_key_is_remapped_when_local_ids_differ(self) -> None:
        with tempfile.TemporaryDirectory(
            prefix="greenvpn-user-id-remap-",
            ignore_cleanup_errors=True,
        ) as root:
            source_db = Path(root) / "source.sqlite"
            target_db = Path(root) / "target.sqlite"
            schema = """
                CREATE TABLE users (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    email TEXT NOT NULL UNIQUE,
                    created_at TEXT NOT NULL,
                    updated_at TEXT
                );
                CREATE TABLE subscriptions (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    user_id INTEGER NOT NULL UNIQUE,
                    plan_code TEXT NOT NULL,
                    created_at TEXT NOT NULL,
                    updated_at TEXT NOT NULL,
                    FOREIGN KEY(user_id) REFERENCES users(id)
                );
            """
            for path in (source_db, target_db):
                with sqlite3.connect(path) as conn:
                    conn.executescript(schema)
                    conn.commit()
            with sqlite3.connect(source_db) as conn:
                conn.execute(
                    "INSERT INTO users(id, email, created_at, updated_at) VALUES (?, ?, ?, ?)",
                    (1001, "mapped@example.test", "2026-07-13T08:00:00+00:00", "2026-07-13T08:00:00+00:00"),
                )
                conn.execute(
                    "INSERT INTO subscriptions(id, user_id, plan_code, created_at, updated_at) VALUES (?, ?, ?, ?, ?)",
                    (1001, 1001, "green_30d", "2026-07-13T08:00:00+00:00", "2026-07-13T10:00:00+00:00"),
                )
                conn.commit()
            with sqlite3.connect(target_db) as conn:
                conn.execute(
                    "INSERT INTO users(id, email, created_at, updated_at) VALUES (?, ?, ?, ?)",
                    (1, "mapped@example.test", "2026-07-13T08:00:00+00:00", "2026-07-13T08:00:00+00:00"),
                )
                conn.execute(
                    "INSERT INTO subscriptions(id, user_id, plan_code, created_at, updated_at) VALUES (?, ?, ?, ?, ?)",
                    (1, 1, "trial", "2026-07-13T08:00:00+00:00", "2026-07-13T09:00:00+00:00"),
                )
                conn.commit()

            result = self.run_sync(
                source_db,
                target_db,
                tables=["users", "subscriptions"],
            )

            self.assertEqual(result.returncode, 0, result.stderr or result.stdout)
            with sqlite3.connect(target_db) as conn:
                users = conn.execute("SELECT id, email FROM users").fetchall()
                subscription = conn.execute(
                    "SELECT user_id, plan_code FROM subscriptions"
                ).fetchone()
            self.assertEqual(users, [(1, "mapped@example.test")])
            self.assertEqual(subscription, (1, "green_30d"))

    def test_user_primary_key_collision_uses_local_id_and_remaps_dependents(
        self,
    ) -> None:
        with tempfile.TemporaryDirectory(
            prefix="greenvpn-user-pk-collision-",
            ignore_cleanup_errors=True,
        ) as root:
            source_db = Path(root) / "source.sqlite"
            target_db = Path(root) / "target.sqlite"
            schema = """
                CREATE TABLE users (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    email TEXT NOT NULL UNIQUE,
                    created_at TEXT NOT NULL,
                    updated_at TEXT
                );
                CREATE TABLE subscriptions (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    user_id INTEGER NOT NULL UNIQUE,
                    plan_code TEXT NOT NULL,
                    created_at TEXT NOT NULL,
                    updated_at TEXT NOT NULL,
                    FOREIGN KEY(user_id) REFERENCES users(id)
                );
            """
            for path in (source_db, target_db):
                with sqlite3.connect(path) as conn:
                    conn.executescript(schema)
                    conn.commit()
            with sqlite3.connect(source_db) as conn:
                conn.execute(
                    "INSERT INTO users(id, email, created_at, updated_at) VALUES (?, ?, ?, ?)",
                    (
                        1,
                        "source-collision@example.test",
                        "2026-07-30T19:00:00+00:00",
                        "2026-07-30T19:00:00+00:00",
                    ),
                )
                conn.execute(
                    """
                    INSERT INTO subscriptions(
                        id, user_id, plan_code, created_at, updated_at
                    ) VALUES (?, ?, ?, ?, ?)
                    """,
                    (
                        1001,
                        1,
                        "green_30d",
                        "2026-07-30T19:00:00+00:00",
                        "2026-07-30T20:00:00+00:00",
                    ),
                )
                conn.commit()
            with sqlite3.connect(target_db) as conn:
                conn.execute(
                    "INSERT INTO users(id, email, created_at, updated_at) VALUES (?, ?, ?, ?)",
                    (
                        1,
                        "target-collision@example.test",
                        "2026-07-30T18:00:00+00:00",
                        "2026-07-30T18:00:00+00:00",
                    ),
                )
                conn.commit()

            result = self.run_sync(
                source_db,
                target_db,
                tables=["users", "subscriptions"],
            )

            self.assertEqual(result.returncode, 0, result.stderr or result.stdout)
            with sqlite3.connect(target_db) as conn:
                source_user_id = conn.execute(
                    "SELECT id FROM users WHERE email = ?",
                    ("source-collision@example.test",),
                ).fetchone()[0]
                subscription_user_id = conn.execute(
                    "SELECT user_id FROM subscriptions WHERE plan_code = ?",
                    ("green_30d",),
                ).fetchone()[0]
                user_count = conn.execute("SELECT COUNT(*) FROM users").fetchone()[0]
            self.assertNotEqual(source_user_id, 1)
            self.assertEqual(subscription_user_id, source_user_id)
            self.assertEqual(user_count, 2)

    def test_traffic_usage_converges_by_database_unique_key(self) -> None:
        with tempfile.TemporaryDirectory(
            prefix="greenvpn-traffic-unique-key-",
            ignore_cleanup_errors=True,
        ) as root:
            source_db = Path(root) / "source.sqlite"
            target_db = Path(root) / "target.sqlite"
            schema = """
                CREATE TABLE users (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    email TEXT NOT NULL UNIQUE,
                    created_at TEXT NOT NULL,
                    updated_at TEXT
                );
                CREATE TABLE device_traffic_usage (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    user_id INTEGER NOT NULL,
                    device_uid TEXT NOT NULL,
                    server_id TEXT NOT NULL,
                    period_key TEXT NOT NULL,
                    rx_bytes INTEGER NOT NULL DEFAULT 0,
                    tx_bytes INTEGER NOT NULL DEFAULT 0,
                    created_at TEXT NOT NULL,
                    updated_at TEXT NOT NULL,
                    UNIQUE(device_uid, server_id, period_key)
                );
            """
            for path in (source_db, target_db):
                with sqlite3.connect(path) as conn:
                    conn.executescript(schema)
                    conn.commit()
            with sqlite3.connect(source_db) as conn:
                conn.execute(
                    "INSERT INTO users(id, email, created_at, updated_at) VALUES (?, ?, ?, ?)",
                    (
                        1001,
                        "source-owner@example.test",
                        "2026-07-30T19:00:00+00:00",
                        "2026-07-30T19:00:00+00:00",
                    ),
                )
                conn.execute(
                    """
                    INSERT INTO device_traffic_usage(
                        id, user_id, device_uid, server_id, period_key,
                        rx_bytes, tx_bytes, created_at, updated_at
                    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
                    """,
                    (
                        1001,
                        1001,
                        "shared-device",
                        "nl1",
                        "2026-07",
                        300,
                        400,
                        "2026-07-30T19:00:00+00:00",
                        "2026-07-30T20:00:00+00:00",
                    ),
                )
                conn.commit()
            with sqlite3.connect(target_db) as conn:
                conn.execute(
                    "INSERT INTO users(id, email, created_at, updated_at) VALUES (?, ?, ?, ?)",
                    (
                        1,
                        "target-owner@example.test",
                        "2026-07-30T18:00:00+00:00",
                        "2026-07-30T18:00:00+00:00",
                    ),
                )
                conn.execute(
                    """
                    INSERT INTO device_traffic_usage(
                        id, user_id, device_uid, server_id, period_key,
                        rx_bytes, tx_bytes, created_at, updated_at
                    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
                    """,
                    (
                        1,
                        1,
                        "shared-device",
                        "nl1",
                        "2026-07",
                        100,
                        200,
                        "2026-07-30T18:00:00+00:00",
                        "2026-07-30T19:00:00+00:00",
                    ),
                )
                conn.commit()

            result = self.run_sync(
                source_db,
                target_db,
                tables=["users", "device_traffic_usage"],
            )

            self.assertEqual(result.returncode, 0, result.stderr or result.stdout)
            with sqlite3.connect(target_db) as conn:
                rows = conn.execute(
                    """
                    SELECT user_id, device_uid, server_id, period_key,
                           rx_bytes, tx_bytes
                    FROM device_traffic_usage
                    """
                ).fetchall()
            self.assertEqual(
                rows,
                [(1001, "shared-device", "nl1", "2026-07", 300, 400)],
            )

    def test_tombstone_user_id_is_remapped_when_local_ids_differ(self) -> None:
        with tempfile.TemporaryDirectory(
            prefix="greenvpn-tombstone-user-id-remap-",
            ignore_cleanup_errors=True,
        ) as root:
            source_db = Path(root) / "source.sqlite"
            target_db = Path(root) / "target.sqlite"
            schema = """
                CREATE TABLE users (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    email TEXT NOT NULL UNIQUE,
                    created_at TEXT NOT NULL,
                    updated_at TEXT
                );
                CREATE TABLE subscriptions (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    user_id INTEGER NOT NULL UNIQUE,
                    plan_code TEXT NOT NULL,
                    created_at TEXT NOT NULL,
                    updated_at TEXT NOT NULL,
                    FOREIGN KEY(user_id) REFERENCES users(id)
                );
                CREATE TABLE replication_tombstones (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    table_name TEXT NOT NULL,
                    natural_key_json TEXT NOT NULL,
                    deleted_at TEXT NOT NULL,
                    origin_node TEXT NOT NULL,
                    UNIQUE(table_name, natural_key_json)
                );
            """
            for path in (source_db, target_db):
                with sqlite3.connect(path) as conn:
                    conn.executescript(schema)
                    conn.commit()
            with sqlite3.connect(source_db) as conn:
                conn.execute(
                    "INSERT INTO users(id, email, created_at, updated_at) VALUES (?, ?, ?, ?)",
                    (
                        1001,
                        "deleted-subscription@example.test",
                        "2026-07-13T08:00:00+00:00",
                        "2026-07-13T08:00:00+00:00",
                    ),
                )
                conn.execute(
                    """
                    INSERT INTO replication_tombstones(
                        table_name, natural_key_json, deleted_at, origin_node
                    ) VALUES (?, ?, ?, ?)
                    """,
                    (
                        "subscriptions",
                        '{"user_id":1001}',
                        "2026-07-13T10:00:00+00:00",
                        "timeweb",
                    ),
                )
                conn.commit()
            with sqlite3.connect(target_db) as conn:
                conn.execute(
                    "INSERT INTO users(id, email, created_at, updated_at) VALUES (?, ?, ?, ?)",
                    (
                        1,
                        "deleted-subscription@example.test",
                        "2026-07-13T08:00:00+00:00",
                        "2026-07-13T08:00:00+00:00",
                    ),
                )
                conn.execute(
                    """
                    INSERT INTO subscriptions(
                        id, user_id, plan_code, created_at, updated_at
                    ) VALUES (?, ?, ?, ?, ?)
                    """,
                    (
                        1,
                        1,
                        "green_30d",
                        "2026-07-13T08:00:00+00:00",
                        "2026-07-13T09:00:00+00:00",
                    ),
                )
                conn.commit()

            result = self.run_sync(
                source_db,
                target_db,
                tables=["users", "subscriptions", "replication_tombstones"],
            )

            self.assertEqual(result.returncode, 0, result.stderr or result.stdout)
            with sqlite3.connect(target_db) as conn:
                subscription_count = conn.execute(
                    "SELECT COUNT(*) FROM subscriptions"
                ).fetchone()[0]
                tombstone_key = conn.execute(
                    "SELECT natural_key_json FROM replication_tombstones"
                ).fetchone()[0]
            self.assertEqual(subscription_count, 0)
            self.assertEqual(tombstone_key, '{"user_id":1}')

    def test_admin_audit_log_converges_without_primary_key_collisions(self) -> None:
        with tempfile.TemporaryDirectory(
            prefix="greenvpn-admin-audit-sync-",
            ignore_cleanup_errors=True,
        ) as root:
            source_db = Path(root) / "source.sqlite"
            target_db = Path(root) / "target.sqlite"
            schema = """
                CREATE TABLE admin_audit_log (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    actor TEXT NOT NULL,
                    action TEXT NOT NULL,
                    target_type TEXT,
                    target_id TEXT,
                    details_json TEXT,
                    request_ip TEXT,
                    user_agent TEXT,
                    created_at TEXT NOT NULL
                );
            """
            for path in (source_db, target_db):
                with sqlite3.connect(path) as conn:
                    conn.executescript(schema)
                    conn.commit()
            with sqlite3.connect(source_db) as conn:
                conn.execute(
                    """
                    INSERT INTO admin_audit_log(
                        id, actor, action, target_type, target_id, details_json,
                        request_ip, user_agent, created_at
                    ) VALUES (1, ?, ?, ?, ?, '{}', '', '', ?)
                    """,
                    (
                        "owner",
                        "support_report_status_updated",
                        "support_report",
                        "9",
                        "2026-07-18T20:52:19+00:00",
                    ),
                )
                conn.commit()
            with sqlite3.connect(target_db) as conn:
                conn.execute(
                    """
                    INSERT INTO admin_audit_log(
                        id, actor, action, target_type, target_id, details_json,
                        request_ip, user_agent, created_at
                    ) VALUES (1, ?, ?, ?, ?, '{}', '', '', ?)
                    """,
                    (
                        "fallback-owner",
                        "admin_staff_login_succeeded",
                        "admin_staff",
                        "1",
                        "2026-07-18T20:50:00+00:00",
                    ),
                )
                conn.commit()

            first = self.run_sync(
                source_db,
                target_db,
                tables=["admin_audit_log"],
            )
            reverse = self.run_sync(
                target_db,
                source_db,
                tables=["admin_audit_log"],
            )

            self.assertEqual(first.returncode, 0, first.stderr or first.stdout)
            self.assertEqual(reverse.returncode, 0, reverse.stderr or reverse.stdout)
            for path in (source_db, target_db):
                with sqlite3.connect(path) as conn:
                    rows = conn.execute(
                        "SELECT actor, action, target_id FROM admin_audit_log ORDER BY action"
                    ).fetchall()
                self.assertEqual(
                    rows,
                    [
                        ("fallback-owner", "admin_staff_login_succeeded", "1"),
                        ("owner", "support_report_status_updated", "9"),
                    ],
                )

    def test_app_release_registry_converges_by_platform_channel_and_version(self) -> None:
        with tempfile.TemporaryDirectory(
            prefix="greenvpn-app-release-sync-",
            ignore_cleanup_errors=True,
        ) as root:
            source_db = Path(root) / "source.sqlite"
            target_db = Path(root) / "target.sqlite"
            schema = """
                CREATE TABLE app_releases (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    platform TEXT NOT NULL,
                    channel TEXT NOT NULL,
                    version TEXT NOT NULL,
                    build_number TEXT,
                    download_url TEXT,
                    sha256 TEXT,
                    size_bytes INTEGER,
                    is_required INTEGER NOT NULL DEFAULT 0,
                    min_supported_version TEXT,
                    rollout_percent INTEGER NOT NULL DEFAULT 100,
                    changelog_json TEXT NOT NULL,
                    status TEXT NOT NULL,
                    created_at TEXT NOT NULL,
                    updated_at TEXT NOT NULL,
                    published_at TEXT,
                    retired_at TEXT,
                    UNIQUE(platform, channel, version)
                );
            """
            for path, status, updated_at in (
                (source_db, "published", "2026-07-18T21:00:00+00:00"),
                (target_db, "draft", "2026-07-18T20:00:00+00:00"),
            ):
                with sqlite3.connect(path) as conn:
                    conn.executescript(schema)
                    conn.execute(
                        """
                        INSERT INTO app_releases(
                            platform, channel, version, build_number,
                            download_url, sha256, size_bytes, is_required,
                            min_supported_version, rollout_percent,
                            changelog_json, status, created_at, updated_at,
                            published_at, retired_at
                        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, NULL)
                        """,
                        (
                            "android",
                            "stable",
                            "0.3.6",
                            "2026071802",
                            "https://example.test/GreenVPN_Android.apk",
                            "A" * 64,
                            100,
                            1,
                            "0.3.6",
                            100,
                            "[]",
                            status,
                            "2026-07-18T19:00:00+00:00",
                            updated_at,
                            updated_at if status == "published" else None,
                        ),
                    )
                    conn.commit()

            result = self.run_sync(
                source_db,
                target_db,
                tables=["app_releases"],
            )

            self.assertEqual(result.returncode, 0, result.stderr or result.stdout)
            with sqlite3.connect(target_db) as conn:
                row = conn.execute(
                    """
                    SELECT status, is_required, rollout_percent, published_at
                    FROM app_releases
                    WHERE platform = 'android' AND channel = 'stable' AND version = '0.3.6'
                    """
                ).fetchone()
            self.assertEqual(
                row,
                ("published", 1, 100, "2026-07-18T21:00:00+00:00"),
            )


if __name__ == "__main__":
    unittest.main()
