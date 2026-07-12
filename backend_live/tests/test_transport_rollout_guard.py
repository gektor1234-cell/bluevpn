import json
import os
import tempfile
import unittest
from pathlib import Path
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

    def test_control_plane_route_signal_cannot_unlock_automatic_fallback(self) -> None:
        self.assertFalse(
            main.route_observation_automation_eligible(
                {
                    "details": {
                        "routeSignalKind": "control_plane_reachability",
                        "automationEligible": False,
                        "egressVerified": False,
                    }
                }
            )
        )

    def test_verified_data_plane_route_signal_is_automation_eligible(self) -> None:
        self.assertTrue(
            main.route_observation_automation_eligible(
                {
                    "details": {
                        "routeSignalKind": "proxy_data_plane",
                        "automationEligible": True,
                        "egressVerified": True,
                    }
                }
            )
        )
        self.assertFalse(
            main.route_observation_automation_eligible(
                {
                    "details": {
                        "routeSignalKind": "proxy_data_plane",
                        "automationEligible": True,
                        "egressVerified": False,
                    }
                }
            )
        )

    def test_planned_protocol_has_non_public_rollout_stage(self) -> None:
        item = main.protocol_catalog_item("amneziawg")
        self.assertEqual(item["rolloutStage"], "canary")
        self.assertFalse(item["clientReady"])
        self.assertFalse(item["publicReady"])

    def test_hysteria_server_canary_stays_hidden_without_client_engine(self) -> None:
        item = main.protocol_catalog_item("hysteria2")
        self.assertEqual(item["rolloutStage"], "canary")
        self.assertFalse(item["clientReady"])
        self.assertFalse(item["serverReady"])
        self.assertFalse(item["publicReady"])

    def test_hysteria_capability_is_accepted_only_when_server_gate_is_enabled(self) -> None:
        self.assertEqual(
            main.normalize_client_supported_protocols(["hysteria2"]),
            set(),
        )
        with patch.object(
            main,
            "SERVER_CLIENT_READY_PROTOCOLS",
            {"wireguard_udp", "hysteria2"},
        ):
            self.assertEqual(
                main.normalize_client_supported_protocols(["hysteria2"]),
                {"hysteria2"},
            )

    def test_vless_reality_canary_requires_explicit_server_and_client_gates(self) -> None:
        item = main.protocol_catalog_item("vless_reality")
        self.assertEqual(item["rolloutStage"], "canary")
        self.assertFalse(item["clientReady"])
        self.assertFalse(item["serverReady"])
        self.assertFalse(item["publicReady"])
        self.assertEqual(
            main.normalize_client_supported_protocols(["vless_reality"]),
            set(),
        )
        with patch.object(
            main,
            "SERVER_CLIENT_READY_PROTOCOLS",
            {"wireguard_udp", "vless_reality"},
        ):
            self.assertEqual(
                main.normalize_client_supported_protocols(["vless_reality"]),
                {"vless_reality"},
            )

    @staticmethod
    def _vless_reality_base_config(
        *,
        host: str = "203.0.113.42",
        server_name: str = "www.amazon.com",
        inbounds: list | None = None,
    ) -> dict:
        return {
            "log": {"loglevel": "warning"},
            "inbounds": [] if inbounds is None else inbounds,
            "outbounds": [
                {
                    "tag": "proxy",
                    "protocol": "vless",
                    "settings": {
                        "vnext": [
                            {
                                "address": host,
                                "port": 443,
                                "users": [
                                    {
                                        "id": "11111111-2222-4333-8444-555555555555",
                                        "encryption": "none",
                                    }
                                ],
                            }
                        ]
                    },
                    "streamSettings": {
                        "network": "xhttp",
                        "security": "reality",
                        "realitySettings": {
                            "serverName": server_name,
                            "fingerprint": "chrome",
                            "password": "test-public-key-material",
                            "shortId": "a1b2c3d4",
                        },
                        "xhttpSettings": {
                            "path": "/transport-preview",
                            "mode": "auto",
                        },
                    },
                },
                {"tag": "direct", "protocol": "freedom"},
            ],
        }

    def test_vless_static_profile_loads_only_allowlisted_listener_free_base_config(self) -> None:
        with tempfile.TemporaryDirectory(prefix="greenvpn-vless-config-") as config_root:
            server_id = "nl2-vless-reality-xhttp-canary"
            config_path = Path(config_root) / f"{server_id}.vless-reality.json"
            config_path.write_text(
                json.dumps(self._vless_reality_base_config()),
                encoding="utf-8",
            )
            os.chmod(config_path, 0o600)
            row = {
                "server_id": server_id,
                "client_config_profile": "static_vless_reality_canary",
                "protocol": "vless_reality",
                "transport": "reality",
                "host": "203.0.113.42",
                "port": 443,
            }
            with (
                patch.object(main, "VLESS_REALITY_CLIENT_CONFIG_ROOT", Path(config_root)),
                patch.object(main, "VLESS_REALITY_CANARY_SERVER_IDS", {server_id}),
                patch.object(main, "VLESS_REALITY_CANARY_SNI", "www.amazon.com"),
            ):
                readiness = main.server_client_config_readiness(row)
                loaded = main.load_vless_reality_client_config(
                    server_id,
                    row_host="203.0.113.42",
                    row_port=443,
                )

            issued = json.loads(loaded["configText"])
            self.assertTrue(readiness["ready"], readiness["blockers"])
            self.assertEqual(readiness["managedBy"], "static_vless_reality_canary")
            self.assertEqual(loaded["host"], "203.0.113.42")
            self.assertEqual(loaded["port"], 443)
            self.assertEqual(issued["inbounds"][0]["listen"], "127.0.0.1")
            self.assertEqual(issued["inbounds"][0]["port"], 1981)

    def test_vless_static_profile_rejects_listener_private_material_sni_and_endpoint_drift(self) -> None:
        with tempfile.TemporaryDirectory(prefix="greenvpn-vless-unsafe-") as config_root:
            server_id = "nl2-vless-reality-xhttp-canary"
            config = self._vless_reality_base_config(
                host="203.0.113.99",
                server_name="wrong.example",
                inbounds=[{"listen": "0.0.0.0", "port": 1080, "protocol": "socks"}],
            )
            config["outbounds"][0]["streamSettings"]["realitySettings"]["privateKey"] = "refuse-me"
            config_path = Path(config_root) / f"{server_id}.vless-reality.json"
            config_path.write_text(json.dumps(config), encoding="utf-8")
            os.chmod(config_path, 0o600)
            with (
                patch.object(main, "VLESS_REALITY_CLIENT_CONFIG_ROOT", Path(config_root)),
                patch.object(main, "VLESS_REALITY_CANARY_SERVER_IDS", {server_id}),
                patch.object(main, "VLESS_REALITY_CANARY_SNI", "www.amazon.com"),
            ):
                _, blockers = main.vless_reality_client_config_check(
                    server_id,
                    row_host="203.0.113.42",
                    row_port=443,
                )

            blocker_codes = {item["code"] for item in blockers}
            self.assertIn("vless_reality_base_config_contains_local_listener", blocker_codes)
            self.assertIn("vless_reality_private_material_refused", blocker_codes)
            self.assertIn("vless_reality_sni_not_allowlisted", blocker_codes)
            self.assertIn("vless_reality_endpoint_host_mismatch", blocker_codes)

    def test_hysteria_static_profile_requires_root_only_allowlisted_base_config(self) -> None:
        with tempfile.TemporaryDirectory(prefix="greenvpn-hysteria-config-") as config_root:
            server_id = "nl2-hysteria2-canary"
            config_path = Path(config_root) / f"{server_id}.hysteria2.yaml"
            config_path.write_text(
                "\n".join(
                    [
                        "server: 203.0.113.42:2443",
                        "auth: test-auth-secret",
                        "tls:",
                        "  sni: nl2.vpn.greenvpn.pro",
                        "  insecure: false",
                        "obfs:",
                        "  type: salamander",
                        "  salamander:",
                        "    password: test-obfs-secret",
                        "",
                    ]
                ),
                encoding="utf-8",
            )
            os.chmod(config_path, 0o600)
            row = {
                "server_id": server_id,
                "client_config_profile": "static_hysteria2_canary",
                "protocol": "hysteria2",
                "transport": "quic",
                "host": "203.0.113.42",
                "port": 2443,
            }
            with (
                patch.object(main, "HYSTERIA2_CLIENT_CONFIG_ROOT", Path(config_root)),
                patch.object(main, "HYSTERIA2_CANARY_SERVER_IDS", {server_id}),
                patch.object(main, "HYSTERIA2_CANARY_SNI", "nl2.vpn.greenvpn.pro"),
            ):
                readiness = main.server_client_config_readiness(row)
                loaded = main.load_hysteria2_client_config(
                    server_id,
                    row_host="203.0.113.42",
                    row_port=2443,
                )

            self.assertTrue(readiness["ready"], readiness["blockers"])
            self.assertEqual(readiness["managedBy"], "static_hysteria2_canary")
            self.assertEqual(loaded["host"], "203.0.113.42")
            self.assertEqual(loaded["port"], 2443)
            self.assertIn("auth: test-auth-secret", loaded["configText"])

    def test_hysteria_static_profile_rejects_insecure_or_local_mode_config(self) -> None:
        with tempfile.TemporaryDirectory(prefix="greenvpn-hysteria-unsafe-") as config_root:
            server_id = "nl2-hysteria2-canary"
            config_path = Path(config_root) / f"{server_id}.hysteria2.yaml"
            config_path.write_text(
                "\n".join(
                    [
                        "server: 203.0.113.42:2443",
                        "auth: test-auth-secret",
                        "tls:",
                        "  sni: nl2.vpn.greenvpn.pro",
                        "  insecure: true",
                        "obfs:",
                        "  type: salamander",
                        "  salamander:",
                        "    password: test-obfs-secret",
                        "socks5:",
                        "  listen: 127.0.0.1:1980",
                        "",
                    ]
                ),
                encoding="utf-8",
            )
            os.chmod(config_path, 0o600)
            with (
                patch.object(main, "HYSTERIA2_CLIENT_CONFIG_ROOT", Path(config_root)),
                patch.object(main, "HYSTERIA2_CANARY_SERVER_IDS", {server_id}),
                patch.object(main, "HYSTERIA2_CANARY_SNI", "nl2.vpn.greenvpn.pro"),
            ):
                _, blockers = main.hysteria2_client_config_check(
                    server_id,
                    row_host="203.0.113.42",
                    row_port=2443,
                )

            blocker_codes = {item["code"] for item in blockers}
            self.assertIn("hysteria2_tls_verification_missing", blocker_codes)
            self.assertIn("hysteria2_insecure_tls_refused", blocker_codes)
            self.assertIn("hysteria2_base_config_contains_local_mode", blocker_codes)

    def test_hysteria_config_issue_never_invokes_wireguard_provisioning(self) -> None:
        main.init_db()
        device_uid = "transport-hysteria-no-wireguard"
        now = main.utc_now_iso()
        with main.db() as conn:
            conn.execute("DELETE FROM devices WHERE device_uid = ?", (device_uid,))
            user = conn.execute("SELECT id FROM users ORDER BY id LIMIT 1").fetchone()
            if user is None:
                cursor = conn.execute(
                    "INSERT INTO users(email, password_hash, created_at) VALUES (?, ?, ?)",
                    ("hysteria-contract-test@example.com", "test-only", now),
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
                (
                    user_id,
                    device_uid,
                    "Hysteria contract test",
                    "windows",
                    "0.3.0-transport-preview.2",
                    "10.10.0.90",
                    now,
                    now,
                ),
            )
            conn.commit()

        server_id = "nl2-hysteria2-canary"
        server = {
            "id": server_id,
            "endpoint": {"host": "203.0.113.42", "port": 2443},
            "protocols": [
                {
                    "code": "hysteria2",
                    "transport": "quic",
                    "port": 2443,
                    "primary": True,
                }
            ],
        }
        access_policy = {
            "allowed": True,
            "reason": None,
            "maxDevices": 10,
            "paidBetaUser": True,
            "adsDisabled": True,
        }
        ad_gate = {"required": False, "enabled": False}
        with (
            patch.object(main, "get_user_by_token", return_value={"id": user_id}),
            patch.object(main, "get_subscription_row", return_value={}),
            patch.object(main, "subscription_status", return_value={"maxDevices": 10}),
            patch.object(main, "client_subscription_access_policy", return_value=access_policy),
            patch.object(main, "subscription_traffic_usage_status", return_value={}),
            patch.object(main, "enforce_device_limit_for_current_device", return_value=1),
            patch.object(main, "disabled_ad_gate_policy", return_value=ad_gate),
            patch.object(
                main,
                "build_server_catalog",
                return_value={
                    "servers": [server],
                    "resilience": {
                        "routeDecision": {"selected": {"protocol": "hysteria2"}}
                    },
                },
            ),
            patch.object(
                main,
                "select_client_server_for_device",
                return_value=(server, {"selectedBy": "preview_test"}),
            ),
            patch.object(main, "get_managed_server_catalog_row_by_server_id", return_value={}),
            patch.object(
                main,
                "server_row_client_config_profile",
                return_value="static_hysteria2_canary",
            ),
            patch.object(
                main,
                "load_hysteria2_client_config",
                return_value={
                    "host": "203.0.113.42",
                    "port": 2443,
                    "configText": "server: 203.0.113.42:2443\nauth: hidden\n",
                },
            ),
            patch.object(main, "touch_device"),
            patch.object(main, "client_route_probe_safe_resilience", side_effect=lambda value, **_: value),
            patch.object(main, "ensure_device_keys_and_ip") as ensure_wg_keys,
            patch.object(main, "provision_wireguard_peer_for_selected_server") as provision_wg,
        ):
            response = main.client_config(
                main.ClientConfigIn(
                    deviceUid=device_uid,
                    serverId=server_id,
                    releaseChannel="preview",
                    supportedProtocols=["hysteria2"],
                ),
                authorization="Bearer test-only",
            )

        self.assertEqual(response["protocol"], "hysteria2")
        self.assertEqual(response["configFormat"], "hysteria2-yaml")
        self.assertEqual(response["clientConfigProfile"], "static_hysteria2_canary")
        self.assertIsNone(response["assignedIp"])
        ensure_wg_keys.assert_not_called()
        provision_wg.assert_not_called()

    def test_vless_config_issue_never_invokes_wireguard_provisioning(self) -> None:
        main.init_db()
        device_uid = "transport-vless-no-wireguard"
        now = main.utc_now_iso()
        with main.db() as conn:
            conn.execute("DELETE FROM devices WHERE device_uid = ?", (device_uid,))
            user = conn.execute("SELECT id FROM users ORDER BY id LIMIT 1").fetchone()
            if user is None:
                cursor = conn.execute(
                    "INSERT INTO users(email, password_hash, created_at) VALUES (?, ?, ?)",
                    ("vless-contract-test@example.com", "test-only", now),
                )
                user_id = int(cursor.lastrowid)
            else:
                user_id = int(user["id"])
            conn.execute(
                """
                INSERT INTO devices(
                    user_id, device_uid, device_name, platform, app_version,
                    assigned_ip, created_at, updated_at
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                """,
                (
                    user_id,
                    device_uid,
                    "VLESS contract test",
                    "windows",
                    "0.3.0-transport-preview.2",
                    "10.10.0.91",
                    now,
                    now,
                ),
            )
            conn.commit()

        server_id = "nl2-vless-reality-xhttp-canary"
        server = {
            "id": server_id,
            "endpoint": {"host": "203.0.113.42", "port": 443},
            "protocols": [
                {
                    "code": "vless_reality",
                    "transport": "reality",
                    "port": 443,
                    "primary": True,
                }
            ],
        }
        access_policy = {
            "allowed": True,
            "reason": None,
            "maxDevices": 10,
            "paidBetaUser": True,
            "adsDisabled": True,
        }
        ad_gate = {"required": False, "enabled": False}
        with (
            patch.object(main, "get_user_by_token", return_value={"id": user_id}),
            patch.object(main, "get_subscription_row", return_value={}),
            patch.object(main, "subscription_status", return_value={"maxDevices": 10}),
            patch.object(main, "client_subscription_access_policy", return_value=access_policy),
            patch.object(main, "subscription_traffic_usage_status", return_value={}),
            patch.object(main, "enforce_device_limit_for_current_device", return_value=1),
            patch.object(main, "disabled_ad_gate_policy", return_value=ad_gate),
            patch.object(
                main,
                "build_server_catalog",
                return_value={
                    "servers": [server],
                    "resilience": {
                        "routeDecision": {"selected": {"protocol": "vless_reality"}}
                    },
                },
            ),
            patch.object(
                main,
                "select_client_server_for_device",
                return_value=(server, {"selectedBy": "preview_test"}),
            ),
            patch.object(main, "get_managed_server_catalog_row_by_server_id", return_value={}),
            patch.object(
                main,
                "server_row_client_config_profile",
                return_value="static_vless_reality_canary",
            ),
            patch.object(
                main,
                "load_vless_reality_client_config",
                return_value={
                    "host": "203.0.113.42",
                    "port": 443,
                    "configText": '{"inbounds":[],"outbounds":[]}',
                },
            ),
            patch.object(main, "touch_device"),
            patch.object(main, "client_route_probe_safe_resilience", side_effect=lambda value, **_: value),
            patch.object(main, "ensure_device_keys_and_ip") as ensure_wg_keys,
            patch.object(main, "provision_wireguard_peer_for_selected_server") as provision_wg,
        ):
            response = main.client_config(
                main.ClientConfigIn(
                    deviceUid=device_uid,
                    serverId=server_id,
                    releaseChannel="preview",
                    supportedProtocols=["vless_reality"],
                ),
                authorization="Bearer test-only",
            )

        self.assertEqual(response["protocol"], "vless_reality")
        self.assertEqual(response["configFormat"], "xray-json")
        self.assertEqual(response["clientConfigProfile"], "static_vless_reality_canary")
        self.assertIsNone(response["assignedIp"])
        ensure_wg_keys.assert_not_called()
        provision_wg.assert_not_called()

    def test_auto_selector_prefers_lighter_protocol_before_higher_score(self) -> None:
        wireguard = catalog_server("wg-light", "wireguard_udp")
        wireguard.update(
            {
                "selectionScore": 10,
                "capacity": {"capacityStatus": "green", "capacityScore": 10},
            }
        )
        hysteria = catalog_server("hy-heavy", "hysteria2")
        hysteria.update(
            {
                "selectionScore": 100,
                "capacity": {"capacityStatus": "green", "capacityScore": 100},
            }
        )

        selected = main.select_best_capacity_server(
            {"servers": [hysteria, wireguard]}
        )

        self.assertEqual(selected["id"], "wg-light")

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
