import importlib.util
import json
import tempfile
import unittest
from pathlib import Path


PROJECT_ROOT = Path(__file__).resolve().parents[2]
SCRIPT_PATH = PROJECT_ROOT / "scripts" / "ops" / "create_paid_beta_first20_package.py"
SPEC = importlib.util.spec_from_file_location("create_paid_beta_first20_package", SCRIPT_PATH)
PACKAGE = importlib.util.module_from_spec(SPEC)
assert SPEC.loader is not None
SPEC.loader.exec_module(PACKAGE)


def fake_invites() -> list[dict]:
    return [
        {
            "inviteId": "inv_first20alpha",
            "label": "First 20 1",
            "code": "GREEN-ABCD-EFGH-IJKL",
            "codeHint": "GREEN-****-****-IJKL",
            "expiresAt": "2026-08-09T00:00:00+00:00",
            "maxUses": 1,
        },
        {
            "inviteId": "inv_first20beta",
            "label": "First 20 2",
            "code": "GREEN-MNOP-QRST-UVWX",
            "codeHint": "GREEN-****-****-UVWX",
            "expiresAt": "2026-08-09T00:00:00+00:00",
            "maxUses": 1,
        },
    ]


class First20PackageTests(unittest.TestCase):
    def test_package_keeps_full_codes_out_of_tracker_and_manifest(self) -> None:
        with tempfile.TemporaryDirectory(
            prefix="greenvpn-first20-package-",
            ignore_cleanup_errors=True,
        ) as root:
            output = Path(root) / "owner-package"
            invites = fake_invites()
            PACKAGE.write_package(
                output,
                api_base="http://127.0.0.1:8010",
                source="first20-test-source",
                invites=invites,
            )

            secret = (output / "invites_secret.csv").read_text(encoding="utf-8-sig")
            tracker = (output / "participant_tracker.csv").read_text(encoding="utf-8-sig")
            manifest_text = (output / "manifest.json").read_text(encoding="utf-8")
            manifest = json.loads(manifest_text)
            readme = (output / "README_RU.txt").read_text(encoding="utf-8")

            for invite in invites:
                self.assertIn(invite["code"], secret)
                self.assertNotIn(invite["code"], tracker)
                self.assertNotIn(invite["code"], manifest_text)
            self.assertEqual(manifest["count"], 2)
            self.assertTrue(manifest["containsInviteSecrets"])
            self.assertIn("первых 20 участников", readme)
            self.assertNotIn('"Файл invites_secret', readme)

    def test_invite_batch_validation_rejects_duplicates(self) -> None:
        invites = fake_invites()
        invites[1]["code"] = invites[0]["code"]
        with self.assertRaises(RuntimeError):
            PACKAGE.validate_created_invites(
                {"codesShownOnce": True, "invites": invites},
                2,
            )

    def test_recovery_response_is_removed_only_after_explicit_cleanup(self) -> None:
        with tempfile.TemporaryDirectory(
            prefix="greenvpn-first20-recovery-",
            ignore_cleanup_errors=True,
        ) as root:
            path = Path(root) / ".invite-response.recovery.json"
            response = {"codesShownOnce": True, "invites": fake_invites()}
            PACKAGE.write_recovery_response(path, response)
            self.assertIn(
                fake_invites()[0]["code"],
                path.read_text(encoding="utf-8"),
            )
            PACKAGE.securely_remove(path)
            self.assertFalse(path.exists())


if __name__ == "__main__":
    unittest.main()
