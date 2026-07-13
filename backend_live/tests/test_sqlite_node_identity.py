import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from backend_live.app import main


class SqliteNodeIdentityTests(unittest.TestCase):
    def test_init_db_reserves_configured_autoincrement_range(self) -> None:
        with tempfile.TemporaryDirectory(prefix="greenvpn-node-id-") as temp_dir:
            data_dir = Path(temp_dir)
            db_path = data_dir / "node.db"
            node_base = 1_000_000_000

            with (
                patch.object(main, "DATA_DIR", data_dir),
                patch.object(main, "DB_PATH", db_path),
                patch.object(main, "SQLITE_NODE_ID_BASE", node_base),
            ):
                main.init_db()
                with main.db() as conn:
                    conn.execute(
                        "INSERT INTO users(email, password_hash, created_at) VALUES (?, ?, ?)",
                        ("node@example.test", "hash", main.utc_now_iso()),
                    )
                    user_id = int(conn.execute("SELECT last_insert_rowid()").fetchone()[0])

            self.assertEqual(user_id, node_base + 1)


if __name__ == "__main__":
    unittest.main()
