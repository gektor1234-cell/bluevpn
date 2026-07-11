import os
import tempfile
import unittest
from unittest.mock import patch

from fastapi import HTTPException


_TEST_ROOT = tempfile.TemporaryDirectory(
    prefix="greenvpn-transport-guard-tests-",
    ignore_cleanup_errors=True,
)
os.environ.setdefault("BLUEVPN_BASE_DIR", _TEST_ROOT.name)
os.environ.setdefault("BLUEVPN_DATA_DIR", os.path.join(_TEST_ROOT.name, "data"))

from backend_live.app import main  # noqa: E402


def catalog_server(server_id: str, protocol: str) -> dict:
    return {
        "id": server_id,
        "title": server_id,
        "status": "healthy",
        "available": True,
        "clientConfigReady": True,
        "healthScore": 100,
        "priority": 10,
        "endpoint": {"host": "203.0.113.10", "port": 443},
        "protocols": [
            {
                "code": protocol,
                "transport": "udp",
                "port": 443,
                "primary": True,
            }
        ],
    }


class TransportRolloutGuardTests(unittest.TestCase):
    @classmethod
    def tearDownClass(cls) -> None:
        _TEST_ROOT.cleanup()

    def test_legacy_client_defaults_to_wireguard_udp_only(self) -> None:
        self.assertEqual(
            main.normalize_client_supported_protocols(None),
            {"wireguard_udp"},
        )

    def test_explicit_unsupported_capabilities_fail_closed(self) -> None:
        self.assertEqual(
            main.normalize_client_supported_protocols(
                ["amneziawg", "unknown", "vless_reality"]
            ),
            set(),
        )

    def test_current_client_model_advertises_only_wireguard(self) -> None:
        payload = main.BootstrapIn(
            deviceUid="transport-test-device",
            deviceName="Transport test",
            supportedProtocols=["wireguard_udp"],
        )
        self.assertEqual(payload.supportedProtocols, ["wireguard_udp"])

    def test_planned_protocol_has_non_public_rollout_stage(self) -> None:
        item = main.protocol_catalog_item("amneziawg")
        self.assertEqual(item["rolloutStage"], "canary")
        self.assertFalse(item["clientReady"])
        self.assertFalse(item["publicReady"])

    def test_catalog_drops_injected_non_negotiated_server(self) -> None:
        unsafe = catalog_server("unsafe-awg", "amneziawg")
        stable = catalog_server("safe-wg", "wireguard_udp")
        with patch.object(
            main,
            "builtin_server_catalog_entry",
            return_value=catalog_server("intelligent_smew", "wireguard_udp"),
        ), patch.object(
            main,
            "list_public_client_catalog_servers",
            return_value=[unsafe, stable],
        ), patch.object(
            main,
            "build_resilience_policy",
            return_value={},
        ):
            catalog = main.build_server_catalog(
                client_supported_protocols=["wireguard_udp"]
            )

        ids = {server["id"] for server in catalog["servers"]}
        self.assertIn("safe-wg", ids)
        self.assertNotIn("unsafe-awg", ids)
        self.assertEqual(
            catalog["managedCatalog"]["negotiatedClientProtocols"],
            ["wireguard_udp"],
        )

    def test_catalog_returns_no_endpoint_for_empty_negotiation(self) -> None:
        with patch.object(
            main,
            "builtin_server_catalog_entry",
            return_value=catalog_server("intelligent_smew", "wireguard_udp"),
        ), patch.object(
            main,
            "list_public_client_catalog_servers",
            return_value=[],
        ), patch.object(
            main,
            "build_resilience_policy",
            return_value={},
        ):
            catalog = main.build_server_catalog(
                client_supported_protocols=["amneziawg"]
            )

        self.assertEqual(catalog["servers"], [])
        self.assertEqual(
            catalog["managedCatalog"]["negotiatedClientProtocols"],
            [],
        )
        with self.assertRaises(HTTPException) as raised:
            main.select_fallback_client_server_or_503(catalog)
        self.assertEqual(raised.exception.status_code, 503)
        self.assertEqual(
            raised.exception.detail["code"],
            "no_available_vpn_nodes",
        )


if __name__ == "__main__":
    unittest.main()
