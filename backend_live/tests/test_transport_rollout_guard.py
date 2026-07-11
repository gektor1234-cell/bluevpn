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

    def test_awg_capability_is_accepted_only_when_server_gate_is_enabled(self) -> None:
        self.assertEqual(
            main.normalize_client_supported_protocols(["amneziawg"]),
            set(),
        )
        with patch.object(
            main,
            "SERVER_CLIENT_READY_PROTOCOLS",
            {"wireguard_udp", "amneziawg"},
        ):
            self.assertEqual(
                main.normalize_client_supported_protocols(["amneziawg"]),
                {"amneziawg"},
            )

    def test_awg_config_contains_obfuscation_fields(self) -> None:
        config = main.build_client_config(
            client_private_key="client-private",
            preshared_key="client-psk",
            server_public_key="server-public",
            client_ip="10.202.0.2",
            endpoint_host="203.0.113.42",
            endpoint_port=1443,
            interface_fields={
                "Jc": "6",
                "Jmin": "32",
                "Jmax": "96",
                "S1": "64",
                "S2": "96",
                "H1": "1234-5678",
                "H2": "2234-6678",
                "H3": "3234-7678",
                "H4": "4234-8678",
                "unsupported": "must-not-leak",
            },
        )

        self.assertIn("Jc = 6", config)
        self.assertIn("H4 = 4234-8678", config)
        self.assertIn("Endpoint = 203.0.113.42:1443", config)
        self.assertNotIn("unsupported", config)
        self.assertLess(config.index("H4 = 4234-8678"), config.index("[Peer]"))

    def test_awg_profile_requires_awg_tool_and_matching_fields(self) -> None:
        row = {
            "server_id": "nl2-awg2",
            "client_config_profile": "remote_ssh_awg2",
            "protocol": "amneziawg",
            "transport": "udp",
            "host": "203.0.113.42",
            "port": 1443,
        }
        remote = {
            "publicHost": "203.0.113.42",
            "publicPort": 1443,
            "interface": "awgcanary0",
            "path": "/etc/bluevpn/vpn-nodes/nl2-awg2.env",
            "wgTool": "wg",
            "clientSubnet": "10.10.0.0/24",
            "awgInterfaceFields": {
                "S1": "64",
                "S2": "96",
                "H1": "1001",
                "H2": "1002",
                "H3": "1003",
            },
        }
        with patch.object(
            main,
            "remote_vpn_node_config_check",
            return_value=(remote, []),
        ):
            readiness = main.server_client_config_readiness(row)

        blocker_codes = {item["code"] for item in readiness["blockers"]}
        self.assertFalse(readiness["ready"])
        self.assertIn("remote_node_awg_fields_missing", blocker_codes)
        self.assertIn("remote_node_awg_tool_missing", blocker_codes)
        self.assertIn("remote_node_client_subnet_overlap", blocker_codes)

    def test_awg_transport_ip_is_separate_and_sticky(self) -> None:
        main.init_db()
        device_uid = "transport-awg-address-test"
        now = main.utc_now_iso()
        with main.db() as conn:
            conn.execute("DELETE FROM device_transport_assignments WHERE device_uid = ?", (device_uid,))
            conn.execute("DELETE FROM devices WHERE device_uid = ?", (device_uid,))
            user = conn.execute("SELECT id FROM users ORDER BY id LIMIT 1").fetchone()
            if user is None:
                cursor = conn.execute(
                    "INSERT INTO users(email, password_hash, created_at) VALUES (?, ?, ?)",
                    ("transport-address-test@example.com", "test-only", now),
                )
                user_id = int(cursor.lastrowid)
            else:
                user_id = int(user["id"])
            conn.execute(
                """
                INSERT INTO devices(
                    user_id, device_uid, device_name, platform, app_version,
                    assigned_ip, created_at, updated_at
                )
                VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                """,
                (user_id, device_uid, "AWG address test", "android", "test", "10.10.0.50", now, now),
            )
            conn.commit()

        first = main.ensure_device_transport_ip(
            device_uid,
            transport_key="amneziawg",
            client_subnet="10.202.0.0/24",
        )
        second = main.ensure_device_transport_ip(
            device_uid,
            transport_key="amneziawg",
            client_subnet="10.202.0.0/24",
        )
        self.assertEqual(first, "10.202.0.50")
        self.assertEqual(second, first)
        with self.assertRaises(HTTPException) as raised:
            main.ensure_device_transport_ip(
                device_uid,
                transport_key="amneziawg-overlap",
                client_subnet="10.10.0.0/24",
            )
        self.assertEqual(raised.exception.status_code, 409)


if __name__ == "__main__":
    unittest.main()
