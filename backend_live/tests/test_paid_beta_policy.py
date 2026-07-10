import os
import copy
import tempfile
import unittest
from datetime import datetime
from unittest.mock import patch


_TEST_ROOT = tempfile.TemporaryDirectory(
    prefix="greenvpn-paid-beta-tests-",
    ignore_cleanup_errors=True,
)
os.environ["BLUEVPN_BASE_DIR"] = _TEST_ROOT.name
os.environ["BLUEVPN_DATA_DIR"] = os.path.join(_TEST_ROOT.name, "data")
os.environ["GREENVPN_PAID_BETA_ENABLED"] = "1"
os.environ["GREENVPN_PAID_BETA_CLIENT_MARKER"] = "green-vpn-paid-beta-v1"
os.environ["GREENVPN_PAID_BETA_RELEASE_CHANNEL"] = "paid-beta"
os.environ["YOOKASSA_SHOP_ID"] = ""
os.environ["YOOKASSA_SECRET_KEY"] = ""

from backend_live.app import main  # noqa: E402


class PaidBetaPolicyTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        main.init_db()

    @classmethod
    def tearDownClass(cls) -> None:
        _TEST_ROOT.cleanup()

    def setUp(self) -> None:
        main.PAID_BETA_ENABLED = True
        with main.db() as conn:
            conn.execute("DELETE FROM promo_redemptions")
            conn.execute("DELETE FROM billing_orders")
            conn.execute("DELETE FROM subscriptions")
            conn.execute("DELETE FROM tokens")
            conn.execute("DELETE FROM devices")
            conn.execute("DELETE FROM users")
            conn.execute(
                "INSERT INTO users(email, password_hash, created_at) VALUES (?, ?, ?)",
                ("beta@example.test", main.hash_password("test-password"), main.utc_now_iso()),
            )
            self.user_id = int(conn.execute("SELECT last_insert_rowid()").fetchone()[0])
            main.create_trial_subscription(conn, self.user_id)
            conn.commit()
        self.access_token = main.issue_token(self.user_id)

    def enroll_beta(self):
        return main.set_user_paid_beta_cohort(
            self.user_id,
            enabled=True,
            source="test-suite",
        )

    def bootstrap(self, *, paid_beta: bool, device_uid: str):
        server = {
            "id": "test-nl",
            "title": "Netherlands #1",
            "endpoint": {"host": "203.0.113.10", "port": 443},
        }
        catalog = {
            "servers": [server],
            "resilience": {
                "routeDecision": {"selected": {"protocol": "wireguard_udp"}},
            },
        }
        assignment = {
            "serverId": "test-nl",
            "previousServerId": None,
            "selectedBy": "test",
        }
        with patch.object(main, "build_server_catalog", return_value=catalog), patch.object(
            main,
            "select_client_server_for_device",
            return_value=(server, assignment),
        ):
            return main.client_bootstrap(
                main.BootstrapIn(
                    deviceUid=device_uid,
                    deviceName="Test device",
                    platform="android",
                    appVersion="0.3.0-paid-beta" if paid_beta else "0.2.44",
                    releaseChannel="paid-beta" if paid_beta else "stable",
                    clientMarker=("green-vpn-paid-beta-v1" if paid_beta else None),
                ),
                authorization=f"Bearer {self.access_token}",
            )

    def beta_payload(self, **overrides):
        values = {
            "trafficPack": "unlimited",
            "trafficGb": 800,
            "unlimitedApps": ["youtube", "telegram"],
            "devices": 5,
            "dedicatedIp": True,
            "autoRenew": True,
            "clientMarker": "green-vpn-paid-beta-v1",
            "releaseChannel": "paid-beta",
        }
        values.update(overrides)
        return main.TariffSelectionIn(**values)

    def test_beta_requires_exact_marker_and_channel(self) -> None:
        self.assertTrue(
            main.paid_beta_request_allowed(
                "green-vpn-paid-beta-v1",
                "paid-beta",
            )
        )
        self.assertFalse(
            main.paid_beta_request_allowed(
                "green-vpn-paid-beta-v1",
                "stable",
            )
        )
        self.assertFalse(
            main.paid_beta_request_allowed(
                "stable-client",
                "paid-beta",
            )
        )

    def test_paid_beta_update_channel_uses_isolated_artifact(self) -> None:
        previous = copy.deepcopy(main.PAID_BETA_UPDATE_CONFIG["android"])
        main.PAID_BETA_UPDATE_CONFIG["android"] = {
            "latestVersion": "0.3.0-paid-beta.1",
            "downloadUrl": "https://example.test/private/GreenVPN_Beta.apk",
            "sha256": "A" * 64,
            "required": False,
            "releasedAt": "2026-07-10T00:00:00+00:00",
            "changelog": ["Beta"],
        }
        try:
            manifest = main.build_update_manifest(
                platform="android",
                channel="paid-beta",
                current_version="0.2.99-paid-beta",
                client_id="beta-test-device",
            )
        finally:
            main.PAID_BETA_UPDATE_CONFIG["android"] = previous

        self.assertEqual(manifest["channel"], "paid-beta")
        self.assertEqual(manifest["latestVersion"], "0.3.0-paid-beta.1")
        self.assertEqual(
            manifest["downloadUrl"],
            "https://example.test/private/GreenVPN_Beta.apk",
        )
        self.assertTrue(manifest["fileReady"])

    def test_beta_quote_ignores_unsupported_options(self) -> None:
        selection = main.normalize_tariff_selection(self.beta_payload())
        quote = main.quote_tariff(selection)

        self.assertEqual(selection["policyMode"], "paid_beta")
        self.assertEqual(selection["devices"], 2)
        self.assertEqual(selection["unlimitedApps"], [])
        self.assertFalse(selection["dedicatedIp"])
        self.assertFalse(selection["autoRenew"])
        self.assertEqual(quote["planCode"], "paid_beta_30d")
        self.assertEqual(quote["monthlyPriceRub"], 299)
        self.assertEqual(quote["periodDays"], 30)
        self.assertEqual(quote["includedDevices"], 2)
        self.assertFalse(quote["adsEnabled"])
        self.assertNotIn("speedSustainedMbps", quote)
        self.assertNotIn("trafficLimitGb", quote)

    def test_stable_marker_keeps_legacy_policy(self) -> None:
        selection = main.normalize_tariff_selection(
            self.beta_payload(clientMarker="stable-client")
        )
        self.assertNotEqual(selection.get("policyMode"), "paid_beta")
        self.assertTrue(selection["autoRenew"])
        self.assertTrue(selection["dedicatedIp"])

    def test_paid_order_activates_fixed_beta_subscription(self) -> None:
        self.enroll_beta()
        order = main.create_billing_order_for_user(self.user_id, self.beta_payload())
        self.assertEqual(order["amountRub"], 299)
        self.assertFalse(order["autoRenew"])
        self.assertEqual(order["provider"], "manual_mvp")

        activated = main.mark_billing_order_paid_and_activate(
            order["orderId"],
            provider_payment_id="test-payment-1",
        )
        subscription = activated["subscription"]
        self.assertEqual(subscription["planCode"], "paid_beta_30d")
        self.assertEqual(subscription["maxDevices"], 2)
        self.assertEqual(subscription["monthlyPriceRub"], 299)
        self.assertFalse(subscription["autoRenew"])
        self.assertEqual(subscription["pricingModel"], "fixed_paid_beta")

    def test_order_terms_survive_beta_flag_change_before_activation(self) -> None:
        self.enroll_beta()
        order = main.create_billing_order_for_user(self.user_id, self.beta_payload())
        previous = main.PAID_BETA_ENABLED
        main.PAID_BETA_ENABLED = False
        try:
            activated = main.mark_billing_order_paid_and_activate(
                order["orderId"],
                provider_payment_id="test-payment-after-flag-change",
            )
        finally:
            main.PAID_BETA_ENABLED = previous

        subscription = activated["subscription"]
        self.assertEqual(subscription["planCode"], "paid_beta_30d")
        self.assertEqual(subscription["maxDevices"], 2)
        self.assertEqual(subscription["pricingModel"], "fixed_paid_beta")

    def test_second_payment_extends_existing_beta_period(self) -> None:
        self.enroll_beta()
        first = main.create_billing_order_for_user(self.user_id, self.beta_payload())
        first_result = main.mark_billing_order_paid_and_activate(
            first["orderId"],
            provider_payment_id="test-payment-1",
        )
        first_expiry = datetime.fromisoformat(first_result["subscription"]["expiresAt"])

        second = main.create_billing_order_for_user(self.user_id, self.beta_payload())
        second_result = main.mark_billing_order_paid_and_activate(
            second["orderId"],
            provider_payment_id="test-payment-2",
        )
        second_expiry = datetime.fromisoformat(second_result["subscription"]["expiresAt"])

        self.assertAlmostEqual(
            (second_expiry - first_expiry).total_seconds(),
            30 * 24 * 60 * 60,
            delta=2,
        )

    def test_beta_enrollment_grants_one_idempotent_three_day_trial(self) -> None:
        first = self.enroll_beta()
        second = main.set_user_paid_beta_cohort(
            self.user_id,
            enabled=True,
            source="second-attempt",
        )

        self.assertEqual(first["accessCohort"], "paid_beta_v1")
        self.assertEqual(first["subscription"]["planCode"], "paid_beta_trial")
        self.assertEqual(first["subscription"]["maxDevices"], 2)
        self.assertEqual(first["subscription"]["periodDays"], 3)
        self.assertEqual(
            first["subscription"]["expiresAt"],
            second["subscription"]["expiresAt"],
        )
        with main.db() as conn:
            count = conn.execute(
                "SELECT COUNT(*) FROM subscriptions WHERE user_id = ? AND plan_code = ?",
                (self.user_id, "paid_beta_trial"),
            ).fetchone()[0]
        self.assertEqual(count, 1)

    def test_beta_enrollment_preserves_active_paid_subscription(self) -> None:
        paid_expiry = "2030-01-01T00:00:00+00:00"
        with main.db() as conn:
            conn.execute(
                """
                UPDATE subscriptions
                SET plan_code = ?, plan_name = ?, monthly_price_rub = ?,
                    is_active = 1, expires_at = ?, updated_at = ?
                WHERE user_id = ?
                """,
                (
                    "legacy_paid",
                    "Legacy paid",
                    299,
                    paid_expiry,
                    main.utc_now_iso(),
                    self.user_id,
                ),
            )
            conn.commit()

        enrolled = self.enroll_beta()
        self.assertEqual(enrolled["accessCohort"], "paid_beta_v1")
        self.assertEqual(enrolled["subscription"]["planCode"], "legacy_paid")
        self.assertEqual(enrolled["subscription"]["expiresAt"], paid_expiry)
        with main.db() as conn:
            count = conn.execute(
                "SELECT COUNT(*) FROM subscriptions WHERE user_id = ?",
                (self.user_id,),
            ).fetchone()[0]
        self.assertEqual(count, 1)

    def test_beta_client_without_cohort_cannot_connect_or_pay(self) -> None:
        user = main.get_user_access_row(self.user_id)
        sub = main.subscription_status(main.get_subscription_row(self.user_id))
        policy = main.client_subscription_access_policy(
            user,
            sub,
            client_marker="green-vpn-paid-beta-v1",
            release_channel="paid-beta",
        )
        self.assertFalse(policy["allowed"])
        self.assertEqual(policy["reason"], "beta_cohort_required")
        with self.assertRaises(main.HTTPException) as raised:
            main.create_billing_order_for_user(self.user_id, self.beta_payload())
        self.assertEqual(raised.exception.status_code, 403)
        self.assertEqual(raised.exception.detail["code"], "beta_cohort_required")

        bootstrap = self.bootstrap(
            paid_beta=True,
            device_uid="beta-without-cohort",
        )
        self.assertFalse(bootstrap["canConnect"])
        self.assertEqual(bootstrap["reason"], "beta_cohort_required")
        self.assertFalse(bootstrap["adGate"]["enabled"])
        with self.assertRaises(main.HTTPException) as config_denied:
            main.client_config(
                main.ClientConfigIn(
                    deviceUid="beta-without-cohort",
                    releaseChannel="paid-beta",
                    clientMarker="green-vpn-paid-beta-v1",
                ),
                authorization=f"Bearer {self.access_token}",
            )
        self.assertEqual(config_denied.exception.status_code, 403)
        self.assertEqual(config_denied.exception.detail["code"], "beta_cohort_required")

    def test_stable_user_remains_allowed_when_beta_is_enabled(self) -> None:
        with main.db() as conn:
            conn.execute(
                "UPDATE subscriptions SET expires_at = ?, is_active = 1 WHERE user_id = ?",
                ("2020-01-01T00:00:00+00:00", self.user_id),
            )
            conn.commit()
        user = main.get_user_access_row(self.user_id)
        sub = main.subscription_status(main.get_subscription_row(self.user_id))
        previous = main.ENFORCE_SUBSCRIPTION_ACCESS
        main.ENFORCE_SUBSCRIPTION_ACCESS = True
        try:
            policy = main.client_subscription_access_policy(
                user,
                sub,
                client_marker=None,
                release_channel="stable",
            )
        finally:
            main.ENFORCE_SUBSCRIPTION_ACCESS = previous
        self.assertTrue(policy["allowed"])
        self.assertFalse(policy["enforced"])
        self.assertFalse(policy["paidBetaUser"])
        bootstrap = self.bootstrap(
            paid_beta=False,
            device_uid="stable-expired-trial",
        )
        self.assertTrue(bootstrap["canConnect"])
        self.assertFalse(bootstrap["accessPolicy"]["enforced"])

    def test_beta_user_cannot_bypass_expiry_with_stable_client(self) -> None:
        self.enroll_beta()
        with main.db() as conn:
            conn.execute(
                "UPDATE subscriptions SET expires_at = ?, is_active = 1 WHERE user_id = ?",
                ("2020-01-01T00:00:00+00:00", self.user_id),
            )
            conn.commit()
        user = main.get_user_access_row(self.user_id)
        sub = main.subscription_status(main.get_subscription_row(self.user_id))
        policy = main.client_subscription_access_policy(
            user,
            sub,
            client_marker=None,
            release_channel="stable",
        )
        self.assertFalse(policy["allowed"])
        self.assertTrue(policy["enforced"])
        self.assertTrue(policy["paidBetaUser"])
        self.assertTrue(policy["adsDisabled"])
        self.assertEqual(policy["maxDevices"], 2)
        bootstrap = self.bootstrap(
            paid_beta=False,
            device_uid="beta-user-stable-client",
        )
        self.assertFalse(bootstrap["canConnect"])
        self.assertEqual(bootstrap["reason"], "subscription_inactive")
        with self.assertRaises(main.HTTPException) as config_denied:
            main.client_config(
                main.ClientConfigIn(
                    deviceUid="beta-user-stable-client",
                    releaseChannel="stable",
                ),
                authorization=f"Bearer {self.access_token}",
            )
        self.assertEqual(config_denied.exception.status_code, 403)
        self.assertEqual(config_denied.exception.detail["code"], "subscription_inactive")

    def test_active_beta_bootstrap_is_no_ads_and_two_devices(self) -> None:
        self.enroll_beta()
        bootstrap = self.bootstrap(
            paid_beta=True,
            device_uid="active-beta-device",
        )
        self.assertTrue(bootstrap["canConnect"])
        self.assertTrue(bootstrap["accessPolicy"]["paidBetaUser"])
        self.assertEqual(bootstrap["subscription"]["maxDevices"], 2)
        self.assertFalse(bootstrap["adGate"]["enabled"])
        self.assertFalse(bootstrap["adGate"]["sessionTimerEnabled"])


if __name__ == "__main__":
    unittest.main()
