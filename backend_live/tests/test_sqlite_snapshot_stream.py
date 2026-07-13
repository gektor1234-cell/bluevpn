import gzip
import os
import sqlite3
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


SCRIPT = (
    Path(__file__).resolve().parents[2]
    / "scripts"
    / "ops"
    / "greenvpn_sqlite_snapshot_stdout.py"
)


class SqliteSnapshotStreamTests(unittest.TestCase):
    def _source_db(self, root: Path) -> Path:
        path = root / "source.db"
        conn = sqlite3.connect(path)
        try:
            conn.execute("CREATE TABLE sample(id INTEGER PRIMARY KEY, value TEXT NOT NULL)")
            conn.execute("INSERT INTO sample(value) VALUES ('ok')")
            conn.commit()
        finally:
            conn.close()
        return path

    def _run(self, source: Path, compression: str) -> subprocess.CompletedProcess[bytes]:
        env = os.environ.copy()
        env["GREENVPN_SNAPSHOT_DB_PATH"] = str(source)
        env["GREENVPN_SNAPSHOT_COMPRESSION"] = compression
        return subprocess.run(
            [sys.executable, str(SCRIPT)],
            env=env,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            check=False,
        )

    def _assert_snapshot(self, payload: bytes, root: Path) -> None:
        target = root / "snapshot.db"
        target.write_bytes(payload)
        conn = sqlite3.connect(target)
        try:
            self.assertEqual(conn.execute("PRAGMA quick_check").fetchone()[0], "ok")
            self.assertEqual(conn.execute("SELECT value FROM sample").fetchone()[0], "ok")
        finally:
            conn.close()

    def test_plain_snapshot_is_a_consistent_database(self) -> None:
        with tempfile.TemporaryDirectory(prefix="greenvpn-snapshot-") as temp_dir:
            root = Path(temp_dir)
            result = self._run(self._source_db(root), "none")
            self.assertEqual(result.returncode, 0, result.stderr.decode())
            self._assert_snapshot(result.stdout, root)

    def test_gzip_snapshot_round_trips_to_a_consistent_database(self) -> None:
        with tempfile.TemporaryDirectory(prefix="greenvpn-snapshot-") as temp_dir:
            root = Path(temp_dir)
            result = self._run(self._source_db(root), "gzip")
            self.assertEqual(result.returncode, 0, result.stderr.decode())
            self._assert_snapshot(gzip.decompress(result.stdout), root)

    def test_unknown_compression_is_rejected_without_payload(self) -> None:
        with tempfile.TemporaryDirectory(prefix="greenvpn-snapshot-") as temp_dir:
            root = Path(temp_dir)
            result = self._run(self._source_db(root), "brotli")
            self.assertEqual(result.returncode, 2)
            self.assertEqual(result.stdout, b"")
            self.assertIn(b"unsupported snapshot compression", result.stderr)


if __name__ == "__main__":
    unittest.main()
