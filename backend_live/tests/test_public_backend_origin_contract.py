import unittest
from pathlib import Path

from backend_live.app import main


REPO_ROOT = Path(__file__).resolve().parents[2]


class PublicBackendOriginContractTests(unittest.TestCase):
    def test_systemd_template_binds_origin_to_loopback(self) -> None:
        service = (
            REPO_ROOT / "backend_live" / "service" / "bluevpn-backend.service"
        ).read_text(encoding="utf-8-sig")

        self.assertIn("--host 127.0.0.1 --port 8000", service)
        self.assertNotIn("--host 0.0.0.0", service)

    def test_windows_admin_client_uses_canonical_https_origin(self) -> None:
        script = (
            REPO_ROOT / "scripts" / "windows" / "bluevpn_admin_api.ps1"
        ).read_text(encoding="utf-8-sig")

        self.assertIn(
            '[string]$ApiBaseUrl = "https://api.greenvpn.pro"',
            script,
        )
        self.assertNotIn("37.220.85.211:8000", script)
        self.assertNotIn("88.218.250.86:8000", script)

    def test_default_api_monitoring_targets_use_tls_port(self) -> None:
        previous = list(main.SERVER_CATALOG_API_BASE_URLS)
        main.SERVER_CATALOG_API_BASE_URLS = [
            "https://api.greenvpn.pro",
            "https://176-113-81-35.sslip.io",
        ]
        try:
            targets = {
                item["targetId"]: item
                for item in main.default_monitoring_targets()
            }
        finally:
            main.SERVER_CATALOG_API_BASE_URLS = previous

        for target_id in (
            "green_api_healthz",
            "production_api_healthz",
            "windows_update_manifest",
            "payment_return_page",
            "green_api_fallback_1_healthz",
        ):
            with self.subTest(target_id=target_id):
                target = targets[target_id]
                self.assertTrue(target["url"].startswith("https://"))
                self.assertEqual(target["port"], 443)


if __name__ == "__main__":
    unittest.main()
