import importlib.util
import tempfile
import unittest
from pathlib import Path


PROJECT_ROOT = Path(__file__).resolve().parents[2]
PRUNE_SCRIPT = PROJECT_ROOT / "scripts" / "ops" / "greenvpn_prune_release_backups.py"
SPEC = importlib.util.spec_from_file_location("greenvpn_release_backup_retention", PRUNE_SCRIPT)
assert SPEC and SPEC.loader
RETENTION = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(RETENTION)


class ReleaseBackupRetentionTests(unittest.TestCase):
    def test_active_release_backup_roots_are_bounded(self) -> None:
        expected = {
            "/root/greenvpn-public-product-backups",
            "/root/greenvpn-paid-beta-backend-backups",
            "/root/greenvpn-paid-beta-client-release-backups",
            "/root/greenvpn-paid-beta-backups",
            "/root/greenvpn-apk-release-backups",
            "/root/greenvpn-windows-release-backups",
            "/root/greenvpn-main-site-backups",
            "/root/greenvpn-admin-static-backups",
            "/root/greenvpn-release-rollback-backups",
        }
        self.assertEqual(
            {path.as_posix() for path in RETENTION.BACKUP_ROOTS},
            expected,
        )

    def test_prune_keeps_newest_directories_and_ignores_files(self) -> None:
        with tempfile.TemporaryDirectory(
            prefix="greenvpn-release-retention-",
            ignore_cleanup_errors=True,
        ) as root:
            backup_root = Path(root)
            for name in ("20260701T000000Z", "20260702T000000Z", "20260703T000000Z"):
                child = backup_root / name
                child.mkdir()
                (child / "artifact.bin").write_bytes(name.encode("ascii"))
            (backup_root / "manifest.txt").write_text("keep", encoding="ascii")

            dry_run = RETENTION.prune_root(backup_root, keep=2, apply=False)
            self.assertEqual(len(dry_run["removed"]), 1)
            self.assertTrue((backup_root / "20260701T000000Z").exists())

            applied = RETENTION.prune_root(backup_root, keep=2, apply=True)
            self.assertEqual(len(applied["removed"]), 1)
            self.assertFalse((backup_root / "20260701T000000Z").exists())
            self.assertTrue((backup_root / "20260702T000000Z").exists())
            self.assertTrue((backup_root / "20260703T000000Z").exists())
            self.assertTrue((backup_root / "manifest.txt").exists())


if __name__ == "__main__":
    unittest.main()
