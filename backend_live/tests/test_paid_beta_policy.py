import os
import copy
import io
import tempfile
import unittest
import urllib.error
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timedelta
from threading import Event
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
os.environ["GREENVPN_PAID_BETA_INVITE_PEPPER"] = "paid-beta-test-pepper-2026-at-least-24-chars"
os.environ["YOOKASSA_SHOP_ID"] = ""
os.environ["YOOKASSA_SECRET_KEY"] = ""

from backend_live.app import main  # noqa: E402

PAID_BETA_SITE_HTML = """
<html><head><meta name="robots" content="noindex,nofollow"></head><body>
<p>3 дня</p><p>149 ₽</p><p>299 ₽</p><p>до двух устройств</p>
<p>без рекламы и автопродления</p>
<a href="downloads/GreenVPN_Android.apk">Android</a>
<a href="downloads/GreenVPN_Setup.exe">Windows</a>
<a href="terms/">Условия</a><a href="privacy/">Конфиденциальность</a>
</body></html>
"""
PAID_BETA_SITE_FETCH = {
    "status": 200,
    "html": PAID_BETA_SITE_HTML,
    "xRobotsTag": "noindex, nofollow, noarchive",
    "error": "",
}


class PaidBetaPolicyTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        main.init_db()

    @classmethod
    def tearDownClass(cls) -> None:
        _TEST_ROOT.cleanup()

    def setUp(self) -> None:
        main.PAID_BETA_ENABLED = True
        main.PAID_BETA_BILLING_PRIMARY = True
        with main.db() as conn:
            conn.execute("DELETE FROM beta_funnel_events")
            conn.execute("DELETE FROM beta_invite_redemptions")
            conn.execute("DELETE FROM beta_invites")
            conn.execute("DELETE FROM promo_redemptions")
            conn.execute("DELETE FROM ad_challenges")
            conn.execute("DELETE FROM free_access_grants")
            conn.execute("DELETE FROM billing_orders")
            conn.execute("DELETE FROM subscriptions")
            conn.execute("DELETE FROM tokens")
            conn.execute("DELETE FROM device_transport_assignments")
            conn.execute("DELETE FROM client_endpoint_assignments")
            conn.execute("DELETE FROM client_route_events")
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

    def create_invite(self, *, max_uses: int = 1):
        return main.create_paid_beta_invite_batch(
            main.AdminPaidBetaInviteBatchIn(
                count=1,
                labelPrefix="Test invite",
                source="test-invite",
                maxUses=max_uses,
            ),
            created_by="test-suite",
        )[0]

    def claim_invite(self, code: str, *, user_id: int | None = None):
        return main.claim_paid_beta_invite(
            user_id or self.user_id,
            main.PaidBetaInviteClaimIn(
                code=code,
                deviceUid="test-invite-device",
                platform="android",
                appVersion="0.3.0-paid-beta.1",
                clientMarker="green-vpn-paid-beta-v1",
                releaseChannel="paid-beta",
            ),
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

    def test_public_product_requires_exact_marker_and_channel(self) -> None:
        with patch.object(main, "PUBLIC_PRODUCT_ENABLED", True):
            self.assertTrue(
                main.public_product_request_allowed(
                    "green-vpn-public-product-v1",
                    "public-product",
                )
            )
            self.assertFalse(
                main.public_product_request_allowed(
                    "green-vpn-public-product-v1",
                    "stable",
                )
            )
            self.assertFalse(
                main.public_product_request_allowed(
                    "stable-client",
                    "public-product",
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

    def test_default_monitoring_targets_cover_api_fallbacks(self) -> None:
        previous = list(main.SERVER_CATALOG_API_BASE_URLS)
        main.SERVER_CATALOG_API_BASE_URLS = [
            "https://primary.example.test/paid-beta-api",
            "https://fallback.example.test/paid-beta-api",
        ]
        try:
            targets = {
                item["targetId"]: item
                for item in main.default_monitoring_targets()
            }
        finally:
            main.SERVER_CATALOG_API_BASE_URLS = previous

        self.assertEqual(
            targets["green_api_healthz"]["url"],
            "https://primary.example.test/paid-beta-api/healthz",
        )
        self.assertEqual(
            targets["green_api_fallback_1_healthz"]["url"],
            "https://fallback.example.test/paid-beta-api/healthz",
        )
        self.assertIn(
            "fallback",
            targets["green_api_fallback_1_healthz"]["tags"],
        )

    def test_paid_beta_payment_urls_include_public_base_prefix(self) -> None:
        previous = {
            "PUBLIC_BASE_URL": main.PUBLIC_BASE_URL,
            "PUBLIC_SITE_URL": main.PUBLIC_SITE_URL,
            "YOOKASSA_RETURN_URL": main.YOOKASSA_RETURN_URL,
            "YOOKASSA_WEBHOOK_URL": main.YOOKASSA_WEBHOOK_URL,
        }
        main.PUBLIC_BASE_URL = "https://api.example.test/paid-beta-api"
        main.PUBLIC_SITE_URL = "https://example.test/paid-beta"
        main.YOOKASSA_RETURN_URL = (
            "https://api.example.test/paid-beta-api/payment/return"
        )
        main.YOOKASSA_WEBHOOK_URL = (
            "https://api.example.test/paid-beta-api/api/v1/billing/yookassa/webhook"
        )
        try:
            with patch.object(
                main,
                "_fetch_paid_beta_site",
                return_value=PAID_BETA_SITE_FETCH,
            ):
                readiness = main.public_site_readiness()
        finally:
            for key, value in previous.items():
                setattr(main, key, value)

        checks = {item["code"]: item for item in readiness["checks"]}
        urls = checks["yookassa_required_urls"]
        self.assertTrue(urls["ok"])
        self.assertEqual(
            urls["value"]["expectedReturnPath"],
            "/paid-beta-api/payment/return",
        )
        self.assertEqual(
            urls["value"]["expectedWebhookPath"],
            "/paid-beta-api/api/v1/billing/yookassa/webhook",
        )

    def test_paid_beta_site_readiness_does_not_require_ad_markers(self) -> None:
        previous = {
            "PUBLIC_BASE_URL": main.PUBLIC_BASE_URL,
            "PUBLIC_SITE_URL": main.PUBLIC_SITE_URL,
            "YOOKASSA_RETURN_URL": main.YOOKASSA_RETURN_URL,
            "YOOKASSA_WEBHOOK_URL": main.YOOKASSA_WEBHOOK_URL,
            "LEGAL_OWNER_NAME": main.LEGAL_OWNER_NAME,
            "LEGAL_OWNER_INN": main.LEGAL_OWNER_INN,
            "LEGAL_CONTACT_EMAIL": main.LEGAL_CONTACT_EMAIL,
        }
        main.PUBLIC_BASE_URL = "https://api.example.test/paid-beta-api"
        main.PUBLIC_SITE_URL = "https://example.test/paid-beta"
        main.YOOKASSA_RETURN_URL = (
            "https://api.example.test/paid-beta-api/payment/return"
        )
        main.YOOKASSA_WEBHOOK_URL = (
            "https://api.example.test/paid-beta-api/api/v1/billing/yookassa/webhook"
        )
        main.LEGAL_OWNER_NAME = "Test Owner"
        main.LEGAL_OWNER_INN = "123456789012"
        main.LEGAL_CONTACT_EMAIL = "support@example.test"
        try:
            with patch.object(
                main,
                "_fetch_paid_beta_site",
                return_value=PAID_BETA_SITE_FETCH,
            ):
                readiness = main.public_site_readiness()
        finally:
            for key, value in previous.items():
                setattr(main, key, value)

        checks = {item["code"]: item for item in readiness["checks"]}
        self.assertEqual(readiness["mode"], "paid_beta")
        self.assertTrue(readiness["productionReady"])
        self.assertTrue(checks["paid_beta_offer_visible"]["ok"])
        self.assertNotIn("2 рекламы", PAID_BETA_SITE_HTML)

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

    def test_invite_is_hashed_idempotent_and_not_relisted_as_plaintext(self) -> None:
        invite = self.create_invite()
        raw_code = invite["code"]
        self.assertTrue(raw_code.startswith("GREEN-"))
        self.assertNotIn("codeHash", invite)

        claimed = self.claim_invite(raw_code)
        repeated = self.claim_invite(raw_code.lower().replace("-", " "))
        self.assertTrue(claimed["claimed"])
        self.assertFalse(claimed["idempotent"])
        self.assertTrue(repeated["idempotent"])
        self.assertEqual(claimed["accessCohort"], "paid_beta_v1")
        self.assertTrue(claimed["offer"]["firstPeriodEligible"])

        listed = main.list_paid_beta_invites()
        self.assertEqual(len(listed), 1)
        self.assertNotIn("code", listed[0])
        self.assertNotIn("codeHash", listed[0])
        self.assertEqual(listed[0]["usedCount"], 1)
        with main.db() as conn:
            stored = conn.execute(
                "SELECT code_hash, code_hint FROM beta_invites WHERE public_id = ?",
                (invite["inviteId"],),
            ).fetchone()
        self.assertNotEqual(stored["code_hash"], raw_code)
        self.assertNotIn(raw_code, stored["code_hint"])

    def test_single_use_invite_rejects_second_user(self) -> None:
        invite = self.create_invite(max_uses=1)
        self.claim_invite(invite["code"])
        with main.db() as conn:
            conn.execute(
                "INSERT INTO users(email, password_hash, created_at, updated_at) VALUES (?, ?, ?, ?)",
                (
                    "second-beta@example.test",
                    main.hash_password("test-password"),
                    main.utc_now_iso(),
                    main.utc_now_iso(),
                ),
            )
            second_user_id = int(conn.execute("SELECT last_insert_rowid()").fetchone()[0])
            main.create_trial_subscription(conn, second_user_id)
            conn.commit()

        with self.assertRaises(main.HTTPException) as raised:
            self.claim_invite(invite["code"], user_id=second_user_id)
        self.assertEqual(raised.exception.status_code, 409)

    def test_invite_first_order_is_149_then_renewal_is_299(self) -> None:
        invite = self.create_invite()
        self.claim_invite(invite["code"])

        quote_response = main.subscription_quote(
            self.beta_payload(),
            authorization=f"Bearer {self.access_token}",
        )
        self.assertEqual(quote_response["quote"]["monthlyPriceRub"], 149)
        self.assertTrue(quote_response["quote"]["inviteApplied"])

        first = main.create_billing_order_for_user(self.user_id, self.beta_payload())
        duplicate = main.create_billing_order_for_user(self.user_id, self.beta_payload())
        self.assertEqual(first["amountRub"], 149)
        self.assertTrue(first["betaInviteApplied"])
        self.assertEqual(first["orderId"], duplicate["orderId"])

        activated = main.mark_billing_order_paid_and_activate(
            first["orderId"],
            provider_payment_id="invite-payment-1",
        )
        self.assertEqual(activated["subscription"]["monthlyPriceRub"], 149)
        repeated_activation = main.mark_billing_order_paid_and_activate(
            first["orderId"],
            provider_payment_id="invite-payment-1",
        )
        self.assertEqual(
            activated["subscription"]["expiresAt"],
            repeated_activation["subscription"]["expiresAt"],
        )
        self.assertFalse(main.paid_beta_offer_for_user(self.user_id)["firstPeriodEligible"])

        renewal = main.create_billing_order_for_user(self.user_id, self.beta_payload())
        self.assertEqual(renewal["amountRub"], 299)
        self.assertFalse(renewal["betaInviteApplied"])

        funnel = main.paid_beta_funnel_summary()
        self.assertEqual(funnel["stages"]["claimedUsers"], 1)
        self.assertEqual(funnel["stages"]["orderCreatedUsers"], 1)
        self.assertEqual(funnel["stages"]["paymentActivatedUsers"], 1)

    def test_fallback_rejects_beta_order_before_database_mutation(self) -> None:
        invite = self.create_invite()
        self.claim_invite(invite["code"])

        with patch.object(main, "PAID_BETA_BILLING_PRIMARY", False):
            with self.assertRaises(main.HTTPException) as raised:
                main.create_billing_order_for_user(self.user_id, self.beta_payload())

        self.assertEqual(raised.exception.status_code, 503)
        self.assertEqual(
            raised.exception.detail["code"],
            "paid_beta_billing_primary_required",
        )
        with main.db() as conn:
            self.assertEqual(
                conn.execute("SELECT COUNT(*) FROM billing_orders").fetchone()[0],
                0,
            )
            self.assertEqual(
                conn.execute(
                    "SELECT COUNT(*) FROM beta_funnel_events WHERE event_type = 'order_created'"
                ).fetchone()[0],
                0,
            )

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

    def test_concurrent_activation_applies_subscription_once(self) -> None:
        self.enroll_beta()
        order = main.create_billing_order_for_user(self.user_id, self.beta_payload())
        entered = Event()
        release = Event()
        calls = []
        original_apply = main.apply_tariff_for_user

        def slow_apply(*args, **kwargs):
            calls.append(order["orderId"])
            entered.set()
            self.assertTrue(release.wait(timeout=5))
            return original_apply(*args, **kwargs)

        with patch.object(main, "apply_tariff_for_user", side_effect=slow_apply):
            with ThreadPoolExecutor(max_workers=1) as executor:
                first_future = executor.submit(
                    main.mark_billing_order_paid_and_activate,
                    order["orderId"],
                    "concurrent-payment",
                )
                self.assertTrue(entered.wait(timeout=5))
                second = main.mark_billing_order_paid_and_activate(
                    order["orderId"],
                    provider_payment_id="concurrent-payment",
                )
                self.assertTrue(second["activationPending"])
                release.set()
                first = first_future.result(timeout=10)

        self.assertEqual(calls, [order["orderId"]])
        self.assertEqual(first["order"]["status"], "activated")

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

    def test_bootstrap_exposes_safe_auto_replacement_reason(self) -> None:
        self.enroll_beta()
        device_uid = "auto-replaced-windows-device"
        initial = self.bootstrap(paid_beta=True, device_uid=device_uid)
        self.assertTrue(initial["device"]["isEnabled"])

        main.set_device_enabled(
            device_uid,
            enabled=False,
            reason="auto_replaced_by_new_device",
        )
        replaced = self.bootstrap(paid_beta=True, device_uid=device_uid)

        self.assertFalse(replaced["canConnect"])
        self.assertEqual(replaced["reason"], "device_disabled")
        self.assertFalse(replaced["device"]["isEnabled"])
        self.assertEqual(
            replaced["device"]["disabledReason"],
            "auto_replaced_by_new_device",
        )

    def test_managed_current_wg0_peer_removal_uses_remote_profile(self) -> None:
        managed_row = object()
        remote_config = {"serverId": "current_wg0"}
        with (
            patch.object(
                main,
                "get_managed_server_catalog_row_by_server_id",
                return_value=managed_row,
            ),
            patch.object(
                main,
                "server_client_config_readiness",
                return_value={"profile": "remote_ssh_wg0", "ready": True},
            ),
            patch.object(
                main,
                "load_remote_vpn_node_config",
                return_value=remote_config,
            ),
            patch.object(
                main,
                "best_effort_remove_remote_peer_live",
                return_value=True,
            ) as remote_remove,
            patch.object(main, "best_effort_remove_peer_live") as local_remove,
            patch.object(main, "best_effort_remove_peer_block_in_wg0") as local_config_remove,
        ):
            removed = main.best_effort_remove_peer_from_server(
                "current_wg0",
                device_uid="managed-current-device",
                public_key="managed-current-public-key",
            )
            same_as_builtin = main.same_wireguard_target_server_id(
                "intelligent_smew",
                "current_wg0",
            )

        self.assertTrue(removed)
        self.assertFalse(same_as_builtin)
        remote_remove.assert_called_once_with(
            remote_config,
            "managed-current-device",
            "managed-current-public-key",
        )
        local_remove.assert_not_called()
        local_config_remove.assert_not_called()

    def test_legacy_current_wg0_without_catalog_keeps_local_cleanup(self) -> None:
        with (
            patch.object(
                main,
                "get_managed_server_catalog_row_by_server_id",
                return_value=None,
            ),
            patch.object(main, "best_effort_remove_peer_live", return_value=True) as local_remove,
            patch.object(
                main,
                "best_effort_remove_peer_block_in_wg0",
                return_value=True,
            ) as local_config_remove,
        ):
            removed = main.best_effort_remove_peer_from_server(
                "current_wg0",
                device_uid="legacy-current-device",
                public_key="legacy-current-public-key",
            )

        self.assertTrue(removed)
        local_remove.assert_called_once_with("legacy-current-public-key")
        local_config_remove.assert_called_once_with("legacy-current-device")

    def test_fallback_provision_keeps_current_key_on_previous_server(self) -> None:
        selected_server = {
            "id": "fallback-node",
            "endpoint": {"host": "203.0.113.42", "port": 443},
        }
        remote_config = {
            "serverId": "fallback-node",
            "wgPublicKey": "fallback-server-public-key",
            "clientMtu": 1280,
            "interface": "wg0",
            "wgConfig": "/etc/wireguard/wg0.conf",
        }
        with (
            patch.object(
                main,
                "get_managed_server_catalog_row_by_server_id",
                return_value=object(),
            ),
            patch.object(
                main,
                "server_client_config_readiness",
                return_value={"profile": "remote_ssh_wg0", "ready": True},
            ),
            patch.object(
                main,
                "load_remote_vpn_node_config",
                return_value=remote_config,
            ),
            patch.object(main, "apply_remote_peer_live") as apply_remote,
            patch.object(main, "best_effort_remove_remote_peer_live") as remove_selected,
            patch.object(main, "best_effort_remove_peer_from_server") as remove_previous,
        ):
            result = main.provision_wireguard_peer_for_selected_server(
                selected_server,
                device_uid="fallback-device",
                public_key="current-client-public-key",
                psk="current-client-psk",
                ip="10.20.0.8",
                previous_server_id="current_wg0",
            )

        self.assertEqual(result["profile"], "remote_ssh_wg0")
        apply_remote.assert_called_once()
        remove_selected.assert_not_called()
        remove_previous.assert_not_called()

    def test_key_rotation_removes_only_old_key_from_previous_server(self) -> None:
        selected_server = {
            "id": "fallback-node",
            "endpoint": {"host": "203.0.113.42", "port": 443},
        }
        remote_config = {
            "serverId": "fallback-node",
            "wgPublicKey": "fallback-server-public-key",
            "clientMtu": 1280,
            "interface": "wg0",
            "wgConfig": "/etc/wireguard/wg0.conf",
        }
        with (
            patch.object(
                main,
                "get_managed_server_catalog_row_by_server_id",
                return_value=object(),
            ),
            patch.object(
                main,
                "server_client_config_readiness",
                return_value={"profile": "remote_ssh_wg0", "ready": True},
            ),
            patch.object(
                main,
                "load_remote_vpn_node_config",
                return_value=remote_config,
            ),
            patch.object(main, "apply_remote_peer_live"),
            patch.object(main, "best_effort_remove_remote_peer_live") as remove_selected,
            patch.object(main, "best_effort_remove_peer_from_server") as remove_previous,
        ):
            main.provision_wireguard_peer_for_selected_server(
                selected_server,
                device_uid="fallback-device",
                public_key="new-client-public-key",
                psk="new-client-psk",
                ip="10.20.0.8",
                old_public_key="old-client-public-key",
                previous_server_id="current_wg0",
            )

        remove_selected.assert_called_once_with(
            remote_config,
            "fallback-device",
            "old-client-public-key",
        )
        remove_previous.assert_called_once_with(
            "current_wg0",
            device_uid="fallback-device",
            public_key="old-client-public-key",
        )

    def public_product_payload(self, *, plan_code: str = "green_30d", **overrides):
        values = {
            "trafficPack": "custom",
            "trafficGb": 315,
            "unlimitedApps": ["youtube", "telegram"],
            "devices": 2,
            "dedicatedIp": True,
            "autoRenew": True,
            "clientMarker": "green-vpn-public-product-v1",
            "releaseChannel": "public-product",
            "billingPlanCode": plan_code,
        }
        values.update(overrides)
        return main.TariffSelectionIn(**values)

    def test_public_product_catalog_has_three_fixed_terms(self) -> None:
        with patch.object(main, "PUBLIC_PRODUCT_ENABLED", True):
            catalog = main.build_public_product_tariff_catalog()

        self.assertEqual(catalog["pricingModel"], "fixed_term_plans")
        self.assertEqual(
            [(plan["periodDays"], plan["priceRub"]) for plan in catalog["plans"]],
            [(30, 249), (90, 649), (180, 1099)],
        )

    def test_server_provisioning_allows_public_eligible_managed_entries(self) -> None:
        catalog = {
            "defaultServerId": "current_wg0",
            "servers": [
                {
                    "id": "current_wg0",
                    "endpoint": {
                        "host": main.WG_ENDPOINT_HOST,
                        "port": main.WG_ENDPOINT_PORT,
                    },
                },
                {
                    "id": "london-public",
                    "endpoint": {"host": "203.0.113.20", "port": 443},
                },
            ],
        }
        entries = [
            {
                "serverId": "current_wg0",
                "clientConfigReady": True,
                "publicEligible": True,
                "clientConfigProfile": "remote_ssh_wg0",
            },
            {
                "serverId": "london-public",
                "clientConfigReady": True,
                "publicEligible": True,
                "clientConfigProfile": "remote_ssh_wg0",
            },
            {
                "serverId": "hidden-canary",
                "clientConfigReady": True,
                "publicEligible": False,
                "clientConfigProfile": "static_hysteria2_canary",
            },
        ]

        readiness = main.build_server_provisioning_readiness(catalog, entries)

        self.assertTrue(readiness["safeForCurrentClient"])
        self.assertTrue(readiness["multiEndpointProvisioningReady"])
        self.assertTrue(readiness["clientConfigContract"]["managedCatalogClientVisible"])
        current_case = next(
            item
            for item in readiness["selectionCases"]
            if item["requestServerId"] == "current_wg0"
        )
        self.assertTrue(current_case["allowed"])

    def test_server_provisioning_rejects_visible_managed_entry_without_gate(self) -> None:
        catalog = {
            "defaultServerId": "current_wg0",
            "servers": [
                {
                    "id": "current_wg0",
                    "endpoint": {
                        "host": main.WG_ENDPOINT_HOST,
                        "port": main.WG_ENDPOINT_PORT,
                    },
                },
                {
                    "id": "unsafe-public",
                    "endpoint": {"host": "203.0.113.30", "port": 443},
                },
            ],
        }
        entries = [
            {
                "serverId": "current_wg0",
                "clientConfigReady": True,
                "publicEligible": True,
                "clientConfigProfile": "remote_ssh_wg0",
            },
            {
                "serverId": "unsafe-public",
                "clientConfigReady": False,
                "publicEligible": False,
                "clientConfigProfile": "none",
            },
        ]

        readiness = main.build_server_provisioning_readiness(catalog, entries)

        self.assertFalse(readiness["safeForCurrentClient"])
        failed = {
            item["code"]: item
            for item in readiness["checks"]
            if not item["ok"]
        }
        self.assertIn("managed_public_entries_pass_gate", failed)

    def test_public_product_allows_ad_gate_but_paid_beta_stays_ad_free(self) -> None:
        user = main.get_user_access_row(self.user_id)
        sub = main.subscription_status(main.get_subscription_row(self.user_id))

        with patch.object(main, "PUBLIC_PRODUCT_ENABLED", True):
            public_policy = main.client_subscription_access_policy(
                user,
                sub,
                client_marker="green-vpn-public-product-v1",
                release_channel="public-product",
            )

        self.assertTrue(public_policy["publicProductScope"])
        self.assertFalse(public_policy["adsDisabled"])

        self.enroll_beta()
        beta_user = main.get_user_access_row(self.user_id)
        beta_sub = main.subscription_status(main.get_subscription_row(self.user_id))
        beta_policy = main.client_subscription_access_policy(
            beta_user,
            beta_sub,
            client_marker="green-vpn-paid-beta-v1",
            release_channel="paid-beta",
        )
        self.assertTrue(beta_policy["adsDisabled"])

    def test_rewarded_ad_marker_is_a_minimum_client_version(self) -> None:
        with patch.object(main, "FREE_AD_GATE_CLIENT_MARKER", "0.3.5"):
            self.assertFalse(main.free_ad_client_supports_gate("0.3.4"))
            self.assertTrue(main.free_ad_client_supports_gate("0.3.5"))
            self.assertTrue(main.free_ad_client_supports_gate("0.3.6"))
            self.assertTrue(main.free_ad_client_supports_gate("0.4.0"))
            self.assertFalse(main.free_ad_client_supports_gate("legacy-client"))

    def test_reward_grant_is_one_connect_when_session_timer_is_disabled(self) -> None:
        device_uid = "rewarded-ad-single-connect"
        self.bootstrap(paid_beta=False, device_uid=device_uid)

        with (
            patch.object(main, "FREE_AD_GATE_ENABLED", True),
            patch.object(main, "FREE_AD_GATE_PLATFORMS", {"android"}),
            patch.object(main, "FREE_AD_GATE_CLIENT_MARKER", "0.3.5"),
            patch.object(main, "FREE_AD_GRANT_CONNECTS", 1),
            patch.object(main, "FREE_AD_SESSION_TIMER_ENABLED", False),
            patch.object(main, "FREE_AD_SESSION_SECONDS", 0),
            patch.object(main, "FREE_AD_SESSION_MAX_CONNECTS", 1000),
        ):
            started = main.create_free_ad_challenge(
                main.get_user_access_row(self.user_id),
                main.AdChallengeStartIn(
                    deviceUid=device_uid,
                    platform="android",
                    provider="yandex_mobile_ads",
                    appVersion="0.3.5",
                ),
            )
            challenge = started["challenge"]
            token = main.urllib.parse.parse_qs(
                main.urllib.parse.urlparse(challenge["rewardUrl"]).query
            )["t"][0]
            completed = main.complete_ad_challenge(
                challenge["challengeId"],
                token,
            )

            self.assertFalse(completed["grant"]["sessionTimerEnabled"])
            self.assertEqual(completed["grant"]["maxConnects"], 1)
            self.assertEqual(completed["adGate"]["grantMaxConnects"], 1)

            consumed = main.consume_free_access_grant(self.user_id, device_uid)
            self.assertEqual(consumed["connectsRemaining"], 0)
            policy_after_connect = main.free_ad_gate_policy(
                self.user_id,
                device_uid,
                "android",
                main.subscription_status(main.get_subscription_row(self.user_id)),
                app_version="0.3.5",
            )
            self.assertTrue(policy_after_connect["required"])
            self.assertFalse(policy_after_connect["sessionTimerEnabled"])

            with main.db() as conn:
                conn.execute(
                    "UPDATE devices SET client_public_key = ? WHERE user_id = ?",
                    ("account-deletion-test-public-key", self.user_id),
                )
                device = conn.execute(
                    "SELECT device_uid, client_public_key FROM devices WHERE user_id = ?",
                    (self.user_id,),
                ).fetchone()
                now = main.utc_now_iso()
                conn.execute(
                    """
                    INSERT INTO client_endpoint_assignments(
                        user_id, device_uid, server_id, protocol, selected_by,
                        assignment_reason, sticky_until_at, created_at, updated_at
                    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
                    """,
                    (
                        self.user_id,
                        device["device_uid"],
                        "intelligent_smew",
                        "wireguard_udp",
                        "test",
                        "account deletion test",
                        "2099-01-01T00:00:00+00:00",
                        now,
                        now,
                    ),
                )
                conn.execute(
                    """
                    INSERT INTO device_transport_assignments(
                        device_uid, transport_key, assigned_ip, created_at, updated_at
                    ) VALUES (?, ?, ?, ?, ?)
                    """,
                    (device["device_uid"], "amneziawg", "10.202.0.24", now, now),
                )
                conn.execute(
                    """
                    INSERT INTO client_route_events(
                        user_id, device_uid, protocol, stage, ok, created_at
                    ) VALUES (?, ?, ?, ?, ?, ?)
                    """,
                    (self.user_id, device["device_uid"], "wireguard_udp", "smoke", 1, now),
                )
                conn.commit()

            with patch.object(
                main,
                "best_effort_remove_peer_from_server",
                return_value=True,
            ) as peer_remove:
                deleted = main.delete_admin_user_record(
                    self.user_id,
                    main.AdminUserDeleteIn(
                        reason="rewarded advertising smoke cleanup",
                        confirmEmail="beta@example.test",
                    ),
                )
            peer_remove.assert_called_once_with(
                "intelligent_smew",
                device_uid=device["device_uid"],
                public_key=device["client_public_key"],
            )
            self.assertEqual(deleted["peerCleanup"], {"attempted": 1, "removed": 1})
            self.assertEqual(deleted["deleted"]["ad_challenges"], 1)
            self.assertEqual(deleted["deleted"]["free_access_grants"], 1)
            self.assertEqual(deleted["deleted"]["client_endpoint_assignments"], 1)
            self.assertEqual(deleted["deleted"]["device_transport_assignments"], 1)
            self.assertEqual(deleted["deleted"]["client_route_events"], 1)
            with main.db() as conn:
                self.assertEqual(
                    conn.execute(
                        "SELECT COUNT(*) FROM ad_challenges WHERE user_id = ?",
                        (self.user_id,),
                    ).fetchone()[0],
                    0,
                )
                self.assertEqual(
                    conn.execute(
                        "SELECT COUNT(*) FROM client_endpoint_assignments WHERE user_id = ?",
                        (self.user_id,),
                    ).fetchone()[0],
                    0,
                )
                self.assertEqual(
                    conn.execute(
                        "SELECT COUNT(*) FROM device_transport_assignments WHERE device_uid = ?",
                        (device["device_uid"],),
                    ).fetchone()[0],
                    0,
                )
                self.assertEqual(
                    conn.execute(
                        "SELECT COUNT(*) FROM client_route_events WHERE user_id = ?",
                        (self.user_id,),
                    ).fetchone()[0],
                    0,
                )
                for table in (
                    "client_endpoint_assignments",
                    "device_transport_assignments",
                    "devices",
                ):
                    self.assertEqual(
                        conn.execute(
                            """
                            SELECT COUNT(*)
                            FROM replication_tombstones
                            WHERE table_name = ?
                            """,
                            (table,),
                        ).fetchone()[0],
                        1,
                    )
                self.assertEqual(
                    conn.execute(
                        "SELECT COUNT(*) FROM free_access_grants WHERE user_id = ?",
                        (self.user_id,),
                    ).fetchone()[0],
                    0,
                )
                self.assertEqual(
                    conn.execute(
                        """
                        SELECT COUNT(*)
                        FROM replication_tombstones
                        WHERE table_name = 'ad_challenges'
                          AND natural_key_json LIKE ?
                        """,
                        (f'%{challenge["challengeId"]}%',),
                    ).fetchone()[0],
                    1,
                )
                self.assertEqual(
                    conn.execute(
                        """
                        SELECT COUNT(*)
                        FROM replication_tombstones
                        WHERE table_name = 'free_access_grants'
                          AND natural_key_json LIKE ?
                        """,
                        (f'%{completed["grant"]["grantId"]}%',),
                    ).fetchone()[0],
                    1,
                )

    def test_public_product_pricing_overrides_legacy_beta_marker(self) -> None:
        payload = self.beta_payload()
        with patch.object(main, "PUBLIC_PRODUCT_ENABLED", True):
            catalog = main.build_tariff_catalog(paid_beta=True)
            normalized = main.normalize_tariff_selection(payload)
            quote = main.quote_tariff(normalized)

        self.assertEqual(catalog["pricingModel"], "fixed_term_plans")
        self.assertEqual(normalized["policyMode"], "public_product")
        self.assertEqual(normalized["planCode"], "green_30d")
        self.assertEqual(quote["monthlyPriceRub"], 249)
        self.assertTrue(quote["autoRenew"])

    def test_public_product_quotes_selected_term_and_ignores_old_constructor_fields(self) -> None:
        with patch.object(main, "PUBLIC_PRODUCT_ENABLED", True):
            normalized = main.normalize_tariff_selection(
                self.public_product_payload(plan_code="green_90d")
            )
            quote = main.quote_tariff(normalized)

        self.assertEqual(normalized["planCode"], "green_90d")
        self.assertEqual(normalized["trafficGb"], 0)
        self.assertEqual(normalized["devices"], 5)
        self.assertEqual(normalized["unlimitedApps"], [])
        self.assertFalse(normalized["dedicatedIp"])
        self.assertTrue(normalized["autoRenew"])
        self.assertEqual(quote["periodDays"], 90)
        self.assertEqual(quote["monthlyPriceRub"], 649)
        self.assertEqual(quote["effectiveMonthlyRub"], 216)
        self.assertTrue(quote["autoRenew"])

    def test_public_product_rejects_unknown_term(self) -> None:
        with patch.object(main, "PUBLIC_PRODUCT_ENABLED", True):
            with self.assertRaises(main.HTTPException) as raised:
                main.normalize_tariff_selection(
                    self.public_product_payload(plan_code="green_365d")
                )

        self.assertEqual(raised.exception.status_code, 400)
        self.assertEqual(raised.exception.detail["code"], "public_plan_invalid")

    def test_public_product_order_amount_and_activation_match_selected_term(self) -> None:
        payload = self.public_product_payload(plan_code="green_90d")
        with patch.object(main, "PUBLIC_PRODUCT_ENABLED", True):
            first = main.create_billing_order_for_user(self.user_id, payload)
            duplicate = main.create_billing_order_for_user(self.user_id, payload)
            activated = main.mark_billing_order_paid_and_activate(
                first["orderId"],
                provider_payment_id="public-product-payment-1",
            )

        self.assertEqual(first["amountRub"], 649)
        self.assertEqual(first["orderId"], duplicate["orderId"])
        self.assertEqual(activated["subscription"]["planCode"], "green_90d")
        self.assertEqual(activated["subscription"]["monthlyPriceRub"], 649)
        self.assertEqual(activated["subscription"]["maxDevices"], 5)
        self.assertEqual(activated["subscription"]["periodDays"], 90)
        self.assertFalse(activated["subscription"]["autoRenew"])
        self.assertFalse(activated["subscription"]["paymentMethodSaved"])

    def test_beta_user_can_create_public_product_order_from_public_client(self) -> None:
        self.enroll_beta()
        with patch.object(main, "PUBLIC_PRODUCT_ENABLED", True):
            order = main.create_billing_order_for_user(
                self.user_id,
                self.public_product_payload(),
            )

        self.assertEqual(order["amountRub"], 249)

    def test_beta_user_still_rejects_unmarked_legacy_client(self) -> None:
        self.enroll_beta()
        payload = self.public_product_payload(
            clientMarker=None,
            releaseChannel="stable",
        )
        with patch.object(main, "PUBLIC_PRODUCT_ENABLED", True):
            with self.assertRaises(main.HTTPException) as raised:
                main.create_billing_order_for_user(self.user_id, payload)

        self.assertEqual(raised.exception.status_code, 409)
        self.assertEqual(
            raised.exception.detail["code"],
            "paid_beta_client_required",
        )

    def test_public_product_auto_renewal_charges_once_and_extends_term(self) -> None:
        payload = self.public_product_payload(plan_code="green_30d")
        with patch.object(main, "PUBLIC_PRODUCT_ENABLED", True):
            first = main.create_billing_order_for_user(self.user_id, payload)
            activated = main.mark_billing_order_paid_and_activate(
                first["orderId"],
                provider_payment_id="initial-payment",
                provider_payment_method_id="saved-method",
            )
        subscription_id = main.get_subscription_row(self.user_id)["id"]
        due_at = (main.utc_now() + main.timedelta(hours=1)).isoformat()
        with main.db() as conn:
            conn.execute(
                "UPDATE subscriptions SET expires_at = ? WHERE id = ?",
                (due_at, subscription_id),
            )
            conn.commit()

        def successful_payment(path, payment_payload, idempotence_key):
            self.assertEqual(path, "/payments")
            self.assertEqual(payment_payload["payment_method_id"], "saved-method")
            self.assertTrue(idempotence_key.startswith("greenvpn-renew-"))
            return {
                "id": "renewal-payment-1",
                "status": "succeeded",
                "paid": True,
                "amount": payment_payload["amount"],
                "metadata": payment_payload["metadata"],
                "payment_method": {"id": "saved-method", "saved": True},
            }

        with (
            patch.object(main, "PUBLIC_PRODUCT_ENABLED", True),
            patch.object(main, "AUTO_RENEWAL_CHARGES_ENABLED", True),
            patch.object(main, "AUTO_RENEWAL_BILLING_PRIMARY", True),
            patch.object(
                main,
                "yookassa_payment_readiness",
                return_value={"productionReady": True},
            ),
            patch.object(main, "yookassa_request", side_effect=successful_payment),
        ):
            result = main.execute_due_auto_renewals(limit=5)
            second = main.execute_due_auto_renewals(limit=5)

        self.assertTrue(result["ok"])
        self.assertEqual(result["executed"], 1)
        self.assertEqual(result["results"][0]["status"], "activated")
        self.assertEqual(second["executed"], 0)
        renewed = main.subscription_status(main.get_subscription_row(self.user_id))
        self.assertTrue(renewed["autoRenew"])
        self.assertTrue(renewed["paymentMethodSaved"])
        self.assertGreater(
            main.parse_dt(renewed["expiresAt"]),
            main.parse_dt(due_at),
        )
        with main.db() as conn:
            renewal_order = conn.execute(
                "SELECT * FROM billing_orders WHERE order_kind = 'auto_renewal'"
            ).fetchone()
        self.assertIsNotNone(renewal_order)
        self.assertEqual(renewal_order["amount_rub"], 249)
        self.assertIsNone(renewal_order["payment_url"])

    def test_payment_smoke_rejects_activated_order_without_saved_method(self) -> None:
        with patch.object(main, "PUBLIC_PRODUCT_ENABLED", True):
            order = main.create_billing_order_for_user(
                self.user_id,
                self.public_product_payload(plan_code="green_30d"),
            )
            main.mark_billing_order_paid_and_activate(
                order["orderId"],
                provider_payment_id="legacy-payment-without-saved-method",
            )
        with main.db() as conn:
            conn.execute(
                "UPDATE billing_orders SET provider = 'yookassa', payment_url = ? WHERE public_id = ?",
                ("https://yookassa.test/legacy", order["orderId"]),
            )
            conn.commit()

        with (
            patch.object(
                main,
                "yookassa_payment_readiness",
                return_value={"productionReady": True},
            ),
            patch.object(
                main,
                "public_site_readiness",
                return_value={"productionReady": True, "summary": {}},
            ),
        ):
            readiness = main.billing_payment_smoke_readiness_payload()

        self.assertFalse(readiness["smokeCompleted"])
        self.assertFalse(readiness["productionReady"])
        self.assertEqual(readiness["summary"]["successfulSmokeCandidates"], 0)
        self.assertEqual(readiness["summary"]["activatedLegacyOrIncomplete"], 1)

    def test_payment_smoke_accepts_current_saved_method_contract(self) -> None:
        with patch.object(main, "PUBLIC_PRODUCT_ENABLED", True):
            order = main.create_billing_order_for_user(
                self.user_id,
                self.public_product_payload(plan_code="green_30d"),
            )
            main.mark_billing_order_paid_and_activate(
                order["orderId"],
                provider_payment_id="current-public-payment",
                provider_payment_method_id="current-saved-method",
            )
        with main.db() as conn:
            conn.execute(
                "UPDATE billing_orders SET provider = 'yookassa', payment_url = ? WHERE public_id = ?",
                ("https://yookassa.test/current", order["orderId"]),
            )
            conn.commit()

        with (
            patch.object(
                main,
                "yookassa_payment_readiness",
                return_value={"productionReady": True},
            ),
            patch.object(
                main,
                "public_site_readiness",
                return_value={"productionReady": True, "summary": {}},
            ),
        ):
            readiness = main.billing_payment_smoke_readiness_payload()

        self.assertTrue(readiness["smokeCompleted"])
        self.assertTrue(readiness["productionReady"])
        self.assertEqual(readiness["summary"]["successfulSmokeCandidates"], 1)
        self.assertEqual(
            readiness["latestSuccessfulOrder"]["amountRub"],
            249,
        )

    def test_auto_renewal_executor_is_inert_on_fallback(self) -> None:
        with (
            patch.object(main, "AUTO_RENEWAL_CHARGES_ENABLED", True),
            patch.object(main, "AUTO_RENEWAL_BILLING_PRIMARY", False),
        ):
            result = main.execute_due_auto_renewals(limit=5)

        self.assertFalse(result["enabled"])
        self.assertEqual(result["executed"], 0)

    def test_public_product_fallback_rejects_order_before_mutation(self) -> None:
        with (
            patch.object(main, "PUBLIC_PRODUCT_ENABLED", True),
            patch.object(main, "PUBLIC_PRODUCT_BILLING_PRIMARY", False),
        ):
            with self.assertRaises(main.HTTPException) as raised:
                main.create_billing_order_for_user(
                    self.user_id,
                    self.public_product_payload(),
                )

        self.assertEqual(raised.exception.status_code, 503)
        self.assertEqual(raised.exception.detail["code"], "billing_primary_required")
        with main.db() as conn:
            self.assertEqual(
                conn.execute("SELECT COUNT(*) FROM billing_orders").fetchone()[0],
                0,
            )

    def test_public_product_recurring_provider_rejection_cancels_order(self) -> None:
        provider_error = main.HTTPException(
            status_code=503,
            detail={
                "code": "recurring_payments_unavailable",
                "message": "Автопродление пока не подключено платёжным оператором.",
            },
        )
        with (
            patch.object(main, "PUBLIC_PRODUCT_ENABLED", True),
            patch.object(main, "YOOKASSA_SHOP_ID", "shop"),
            patch.object(main, "YOOKASSA_SECRET_KEY", "secret"),
            patch.object(
                main,
                "create_yookassa_payment_for_order",
                side_effect=provider_error,
            ),
        ):
            with self.assertRaises(main.HTTPException) as raised:
                main.create_billing_order_for_user(
                    self.user_id,
                    self.public_product_payload(),
                )

        self.assertEqual(raised.exception.status_code, 503)
        self.assertEqual(
            raised.exception.detail["code"],
            "recurring_payments_unavailable",
        )
        with main.db() as conn:
            row = conn.execute(
                "SELECT status, payment_url FROM billing_orders ORDER BY id DESC LIMIT 1"
            ).fetchone()
        self.assertEqual(row["status"], "canceled")
        self.assertIsNone(row["payment_url"])

    def test_yookassa_recurring_rejection_is_safe_and_actionable(self) -> None:
        body = (
            b'{"type":"error","code":"forbidden",'
            b'"description":"This store can\'t make recurring payments. '
            b'Contact the YooMoney manager to learn more"}'
        )
        provider_error = urllib.error.HTTPError(
            url="https://api.yookassa.ru/v3/payments",
            code=403,
            msg="Forbidden",
            hdrs=None,
            fp=io.BytesIO(body),
        )
        with (
            patch.object(main, "YOOKASSA_SHOP_ID", "shop"),
            patch.object(main, "YOOKASSA_SECRET_KEY", "secret"),
            patch.object(main.urllib.request, "urlopen", side_effect=provider_error),
        ):
            with self.assertRaises(main.HTTPException) as raised:
                main.yookassa_http_request(
                    "POST",
                    "/payments",
                    payload={"save_payment_method": True},
                    idempotence_key="test-recurring-rejection",
                )

        self.assertEqual(raised.exception.status_code, 503)
        self.assertEqual(
            raised.exception.detail["code"],
            "recurring_payments_unavailable",
        )
        self.assertNotIn("This store", str(raised.exception.detail))

    def test_public_product_enforces_trial_then_allows_paid_configuration(self) -> None:
        payload = self.public_product_payload(plan_code="green_180d")
        with (
            patch.object(main, "PUBLIC_PRODUCT_ENABLED", True),
            patch.object(main, "ENFORCE_SUBSCRIPTION_ACCESS", True),
        ):
            trial_bootstrap = self.bootstrap(
                paid_beta=False,
                device_uid="public-product-trial-device",
            )
            with main.db() as conn:
                conn.execute(
                    "UPDATE subscriptions SET expires_at = ?, is_active = 1 WHERE user_id = ?",
                    ("2020-01-01T00:00:00+00:00", self.user_id),
                )
                conn.commit()
            expired_bootstrap = self.bootstrap(
                paid_beta=False,
                device_uid="public-product-expired-device",
            )
            order = main.create_billing_order_for_user(self.user_id, payload)
            main.mark_billing_order_paid_and_activate(
                order["orderId"],
                provider_payment_id="public-product-payment-2",
            )
            paid_bootstrap = self.bootstrap(
                paid_beta=False,
                device_uid="public-product-paid-device",
            )

        self.assertTrue(trial_bootstrap["canConnect"])
        self.assertFalse(expired_bootstrap["canConnect"])
        self.assertEqual(expired_bootstrap["reason"], "subscription_inactive")
        self.assertTrue(paid_bootstrap["canConnect"])
        self.assertEqual(paid_bootstrap["subscription"]["maxDevices"], 5)
        self.assertEqual(paid_bootstrap["subscription"]["periodDays"], 180)
        self.assertFalse(paid_bootstrap["adGate"]["required"])

    def test_admin_user_query_paginates_and_filters_client_platforms(self) -> None:
        main.ensure_device_row(
            self.user_id,
            "admin-android-device",
            "Android test",
            "android",
            "0.3.4",
        )
        with main.db() as conn:
            conn.execute(
                "INSERT INTO users(email, password_hash, created_at) VALUES (?, ?, ?)",
                ("windows@example.test", main.hash_password("test-password"), main.utc_now_iso()),
            )
            windows_user_id = int(conn.execute("SELECT last_insert_rowid()").fetchone()[0])
            main.create_trial_subscription(conn, windows_user_id)
            conn.commit()
        main.ensure_device_row(
            windows_user_id,
            "admin-windows-device",
            "Windows test",
            "windows",
            "0.3.4",
        )

        first_page = main.query_admin_users(limit=1, offset=0, sort="oldest")
        android_only = main.query_admin_users(platform="android", limit=50)
        windows_only = main.query_admin_users(platform="windows", limit=50)

        self.assertEqual(first_page["page"]["total"], 2)
        self.assertTrue(first_page["page"]["hasMore"])
        self.assertEqual(first_page["page"]["nextOffset"], 1)
        self.assertEqual([item["id"] for item in android_only["users"]], [self.user_id])
        self.assertEqual([item["id"] for item in windows_only["users"]], [windows_user_id])
        self.assertEqual(windows_only["users"][0]["platforms"], ["windows"])
        self.assertNotIn("providerPaymentMethodId", windows_only["users"][0]["subscription"])

    def test_admin_analytics_separates_android_and_windows(self) -> None:
        main.ensure_device_row(
            self.user_id,
            "analytics-android-device",
            "Android analytics",
            "android",
            "0.3.4",
        )
        with main.db() as conn:
            conn.execute(
                "UPDATE devices SET last_seen_at = ?, last_config_at = ? WHERE device_uid = ?",
                (main.utc_now_iso(), main.utc_now_iso(), "analytics-android-device"),
            )
            conn.commit()

        analytics = main.build_admin_analytics_summary()

        self.assertIn("clients", analytics)
        self.assertEqual(analytics["clients"]["platforms"]["android"]["users"], 1)
        self.assertEqual(analytics["clients"]["platforms"]["android"]["seen24h"], 1)
        self.assertIn("windows", analytics["clients"]["platforms"])
        self.assertIn("activity", analytics["business"])
        self.assertIn("attention", analytics)

    def test_admin_csv_cells_are_formula_safe(self) -> None:
        self.assertEqual(main.safe_admin_csv_cell("=HYPERLINK('x')"), "'=HYPERLINK('x')")
        self.assertEqual(main.safe_admin_csv_cell("  +SUM(1,2)"), "'  +SUM(1,2)")
        self.assertEqual(main.safe_admin_csv_cell("\t=1+1"), "'\t=1+1")
        self.assertEqual(main.safe_admin_csv_cell("line\nbreak"), "line break")

    def test_admin_page_outside_result_range_has_empty_bounds(self) -> None:
        page = main.admin_page_payload(total=3, limit=50, offset=100)
        self.assertEqual(page["from"], 0)
        self.assertEqual(page["to"], 3)
        self.assertFalse(page["hasMore"])
        self.assertTrue(page["hasPrevious"])

    def test_admin_bulk_device_action_reports_missing_users(self) -> None:
        main.ensure_device_row(
            self.user_id,
            "bulk-android-device",
            "Android bulk",
            "android",
            "0.3.4",
        )
        with main.db() as conn:
            conn.execute(
                "INSERT INTO users(email, password_hash, created_at) VALUES (?, ?, ?)",
                ("bulk-windows@example.test", main.hash_password("test-password"), main.utc_now_iso()),
            )
            second_user_id = int(conn.execute("SELECT last_insert_rowid()").fetchone()[0])
            main.create_trial_subscription(conn, second_user_id)
            conn.commit()
        main.ensure_device_row(
            second_user_id,
            "bulk-windows-device",
            "Windows bulk",
            "windows",
            "0.3.4",
        )

        with patch.object(main, "require_admin", return_value={"actor": "test-suite"}):
            result = main.admin_users_bulk_action(
                main.AdminBulkUserActionIn(
                    userIds=[self.user_id, second_user_id, 999999999],
                    action="disable_all_devices",
                    reason="Пакетная проверка устройств",
                ),
                request=None,
                x_admin_token="test-token",
            )

        self.assertFalse(result["ok"])
        self.assertEqual(result["summary"], {"requested": 3, "succeeded": 2, "failed": 1})
        self.assertFalse(main.list_user_devices(self.user_id)[0]["isEnabled"])
        self.assertFalse(main.list_user_devices(second_user_id)[0]["isEnabled"])
        missing = next(item for item in result["results"] if item["userId"] == 999999999)
        self.assertEqual(missing["status"], "failed")

    def test_admin_subscription_rejects_invalid_limits_and_missing_user(self) -> None:
        invalid_limit = main.AdminSubscriptionIn(
            planCode="green_30d",
            planName="30 дней",
            maxDevices=101,
            reason="Проверка лимита устройств",
        )
        with self.assertRaises(main.HTTPException) as raised_limit:
            main.upsert_subscription_for_user(self.user_id, invalid_limit)
        self.assertEqual(raised_limit.exception.status_code, 400)

        missing_user = main.AdminSubscriptionIn(
            planCode="green_30d",
            planName="30 дней",
            maxDevices=3,
            reason="Проверка отсутствующего аккаунта",
        )
        with self.assertRaises(main.HTTPException) as raised_missing:
            main.upsert_subscription_for_user(999999999, missing_user)
        self.assertEqual(raised_missing.exception.status_code, 404)


class AppReleaseRollbackRegressionTests(unittest.TestCase):
    def test_environment_rollback_is_platform_and_channel_specific(self) -> None:
        paid_beta_config = {
            "android": {
                "rollbackVersion": "0.3.4",
                "rollbackUrl": "https://example.test/beta/android.apk",
                "rollbackSha256": "C" * 64,
            },
            "windows": {
                "rollbackVersion": "0.3.4",
                "rollbackUrl": "https://example.test/beta/windows.exe",
                "rollbackSha256": "D" * 64,
            },
        }
        with patch.object(main, "UPDATE_ROLLBACK_VERSION", "0.3.5"), patch.object(
            main,
            "UPDATE_ROLLBACK_URL",
            "https://example.test/stable/windows.exe",
        ), patch.object(main, "UPDATE_ROLLBACK_SHA256", "A" * 64), patch.object(
            main,
            "ANDROID_UPDATE_ROLLBACK_VERSION",
            "0.3.5",
        ), patch.object(
            main,
            "ANDROID_UPDATE_ROLLBACK_URL",
            "https://example.test/stable/android.apk",
        ), patch.object(
            main,
            "ANDROID_UPDATE_ROLLBACK_SHA256",
            "B" * 64,
        ), patch.object(main, "PAID_BETA_UPDATE_CONFIG", paid_beta_config):
            windows = main.environment_rollback_candidate("windows", "stable")
            android = main.environment_rollback_candidate("android", "stable")
            beta_android = main.environment_rollback_candidate("android", "paid-beta")

        self.assertEqual(windows["downloadUrl"], "https://example.test/stable/windows.exe")
        self.assertEqual(android["downloadUrl"], "https://example.test/stable/android.apk")
        self.assertEqual(beta_android["downloadUrl"], "https://example.test/beta/android.apk")
        self.assertEqual(windows["platform"], "windows")
        self.assertEqual(android["platform"], "android")
        self.assertEqual(beta_android["channel"], "paid-beta")

    def test_android_rollback_does_not_fall_back_to_windows_artifact(self) -> None:
        with patch.object(main, "UPDATE_ROLLBACK_VERSION", "0.3.5"), patch.object(
            main,
            "UPDATE_ROLLBACK_URL",
            "https://example.test/stable/windows.exe",
        ), patch.object(main, "UPDATE_ROLLBACK_SHA256", "A" * 64), patch.object(
            main,
            "ANDROID_UPDATE_ROLLBACK_VERSION",
            "",
        ), patch.object(main, "ANDROID_UPDATE_ROLLBACK_URL", ""), patch.object(
            main,
            "ANDROID_UPDATE_ROLLBACK_SHA256",
            "",
        ):
            candidate = main.environment_rollback_candidate("android", "stable")

        self.assertIsNone(candidate)

    def test_node_local_download_mirror_requires_exact_version_and_hash(self) -> None:
        with patch.object(main, "ANDROID_UPDATE_LATEST_VERSION", "0.3.6"), patch.object(
            main,
            "ANDROID_UPDATE_DOWNLOAD_URL",
            "https://fallback.example.test/downloads/GreenVPN_Android.apk",
        ), patch.object(main, "ANDROID_UPDATE_SHA256", "A" * 64):
            matching = main.node_local_update_artifact(
                platform="android",
                channel="stable",
                version="0.3.6",
                sha256="a" * 64,
            )
            wrong_hash = main.node_local_update_artifact(
                platform="android",
                channel="stable",
                version="0.3.6",
                sha256="B" * 64,
            )
            wrong_version = main.node_local_update_artifact(
                platform="android",
                channel="stable",
                version="0.3.7",
                sha256="A" * 64,
            )

        self.assertEqual(
            matching["downloadUrl"],
            "https://fallback.example.test/downloads/GreenVPN_Android.apk",
        )
        self.assertIsNone(wrong_hash)
        self.assertIsNone(wrong_version)


class OperationalReadinessRegressionTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        main.init_db()

    def setUp(self) -> None:
        main.PAID_BETA_ENABLED = True
        main.PAID_BETA_BILLING_PRIMARY = True
        with main.db() as conn:
            conn.execute("DELETE FROM admin_audit_log")
            conn.execute("DELETE FROM beta_invite_redemptions")
            conn.execute("DELETE FROM beta_invites")
            conn.execute("DELETE FROM billing_orders")
            conn.execute("DELETE FROM subscriptions")
            conn.execute("DELETE FROM tokens")
            conn.execute("DELETE FROM devices")
            conn.execute("DELETE FROM users")
            conn.execute(
                "INSERT INTO users(email, password_hash, created_at) VALUES (?, ?, ?)",
                (
                    "operations@example.test",
                    main.hash_password("test-password"),
                    main.utc_now_iso(),
                ),
            )
            self.user_id = int(conn.execute("SELECT last_insert_rowid()").fetchone()[0])
            main.create_trial_subscription(conn, self.user_id)
            conn.commit()
        main.set_user_paid_beta_cohort(
            self.user_id,
            enabled=True,
            source="test-suite",
        )

    def test_sms_daily_limit_error_is_actionable(self) -> None:
        issue = main.classify_sms_delivery_error(
            "Будет превышен или уже превышен дневной лимит на отправку сообщений"
        )

        self.assertEqual(issue["code"], "daily_limit_required")
        self.assertIn("дневной лимит", issue["message"])

    def test_public_health_and_legal_routes_support_head(self) -> None:
        expected = {
            "/healthz",
            "/",
            "/payment/return",
            "/download/windows",
            "/download/android",
            "/download/ios",
            "/legal/requisites",
            "/legal/offer",
            "/legal/privacy",
            "/legal/acceptable-use",
            "/legal/refunds",
        }
        head_routes = {
            route.path
            for route in main.app.routes
            if "HEAD" in (getattr(route, "methods", set()) or set())
        }

        self.assertTrue(expected.issubset(head_routes))

    def test_admin_can_cancel_only_stale_order_without_payment_markers(self) -> None:
        order = main.create_billing_order_for_user(
            self.user_id,
            main.TariffSelectionIn(
                trafficPack="gb20",
                trafficGb=20,
                unlimitedApps=[],
                devices=1,
                dedicatedIp=False,
                autoRenew=True,
                releaseChannel="paid-beta",
                clientMarker="green-vpn-paid-beta-v1",
            ),
        )
        stale_at = (main.utc_now() - timedelta(days=3)).isoformat()
        with main.db() as conn:
            conn.execute(
                """
                UPDATE billing_orders
                SET provider = 'yookassa', created_at = ?, updated_at = ?,
                    payment_url = NULL, provider_payment_id = NULL,
                    provider_payment_method_id = NULL, paid_at = NULL, activated_at = NULL
                WHERE public_id = ?
                """,
                (stale_at, stale_at, order["orderId"]),
            )
            conn.commit()

        with patch.object(main, "require_admin", return_value={"actor": "test-suite"}), patch.object(
            main,
            "yookassa_configured",
            return_value=True,
        ):
            result = main.admin_cancel_stale_billing_order(
                order["orderId"],
                main.AdminStaleBillingOrderCancelIn(
                    reason="Cleanup of an abandoned pre-provider test order",
                ),
                request=None,
                x_admin_token="test-token",
            )

        self.assertEqual(result["order"]["status"], "canceled")
        self.assertEqual(result["reconciliation"]["summary"]["ordersWithAttention"], 0)
        with main.db() as conn:
            audit = conn.execute(
                "SELECT action FROM admin_audit_log ORDER BY id DESC LIMIT 1"
            ).fetchone()
        self.assertEqual(audit["action"], "billing_stale_order_canceled")


class AdminAuthSecurityTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        main.init_db()

    def setUp(self) -> None:
        with main.db() as conn:
            conn.execute("DELETE FROM admin_2fa_challenges")
            conn.execute("DELETE FROM admin_sessions")
            conn.execute("DELETE FROM admin_staff")
            conn.execute("DELETE FROM admin_audit_log")
            now = main.utc_now_iso()
            conn.execute(
                """
                INSERT INTO admin_staff(
                    email, display_name, role, is_active, created_at, updated_at,
                    password_hash, password_set_at, two_factor_enabled,
                    two_factor_method, two_factor_set_at
                )
                VALUES (?, ?, 'owner', 1, ?, ?, ?, ?, 0, 'email', NULL)
                """,
                (
                    "owner@example.test",
                    "Test owner",
                    now,
                    now,
                    main.admin_password_hash("correct-password"),
                    now,
                ),
            )
            conn.commit()

    @staticmethod
    def request(peer: str, forwarded_for: str = ""):
        headers = [(b"user-agent", b"GreenVPN auth test")]
        if forwarded_for:
            headers.append((b"x-forwarded-for", forwarded_for.encode("ascii")))
        return main.Request(
            {
                "type": "http",
                "asgi": {"version": "3.0"},
                "http_version": "1.1",
                "method": "POST",
                "scheme": "https",
                "path": "/api/v1/admin/auth/login",
                "raw_path": b"/api/v1/admin/auth/login",
                "query_string": b"",
                "headers": headers,
                "client": (peer, 43210),
                "server": ("api.greenvpn.pro", 443),
                "root_path": "",
            }
        )

    def test_request_ip_uses_forwarded_address_only_from_loopback_proxy(self) -> None:
        proxied = self.request("127.0.0.1", "203.0.113.250, 198.51.100.42")
        direct = self.request("203.0.113.8", "198.51.100.99")
        invalid = self.request("127.0.0.1", "not-an-ip, 198.51.100.7")

        self.assertEqual(main.request_ip_and_agent(proxied)[0], "198.51.100.42")
        self.assertEqual(main.request_ip_and_agent(direct)[0], "203.0.113.8")
        self.assertEqual(main.request_ip_and_agent(invalid)[0], "198.51.100.7")

    def test_admin_password_login_is_rate_limited_per_identity_and_ip(self) -> None:
        request = self.request("127.0.0.1", "198.51.100.55")
        payload = main.AdminLoginIn(
            email="owner@example.test",
            password="-".join(("wrong", "password")),
            actor="owner@example.test",
        )
        with patch.object(main, "ADMIN_LOGIN_MAX_ATTEMPTS_PER_IDENTITY", 2), patch.object(
            main,
            "ADMIN_LOGIN_MAX_ATTEMPTS_PER_IP",
            50,
        ):
            for _ in range(2):
                with self.assertRaises(main.HTTPException) as failed:
                    main.login_admin_staff(payload, request)
                self.assertEqual(failed.exception.status_code, 401)

            with self.assertRaises(main.HTTPException) as limited:
                main.login_admin_staff(payload, request)

        self.assertEqual(limited.exception.status_code, 429)
        self.assertEqual(limited.exception.headers.get("Retry-After"), "900")
        with main.db() as conn:
            actions = [
                row[0]
                for row in conn.execute(
                    "SELECT action FROM admin_audit_log ORDER BY id"
                ).fetchall()
            ]
            request_ips = {
                row[0]
                for row in conn.execute(
                    "SELECT request_ip FROM admin_audit_log"
                ).fetchall()
            }
        self.assertEqual(
            actions,
            [
                "admin_staff_login_failed",
                "admin_staff_login_failed",
                "admin_staff_login_rate_limited",
            ],
        )
        self.assertEqual(request_ips, {"198.51.100.55"})

    def test_admin_identity_rate_limit_cannot_be_bypassed_by_changing_ip(self) -> None:
        payload = main.AdminLoginIn(
            email="owner@example.test",
            password="<test-only-placeholder>",
            actor="owner@example.test",
        )
        with patch.object(main, "ADMIN_LOGIN_MAX_ATTEMPTS_PER_IDENTITY", 2), patch.object(
            main,
            "ADMIN_LOGIN_MAX_ATTEMPTS_PER_IP",
            50,
        ):
            for forwarded_for in ("198.51.100.10", "198.51.100.11"):
                with self.assertRaises(main.HTTPException) as failed:
                    main.login_admin_staff(
                        payload,
                        self.request("127.0.0.1", forwarded_for),
                    )
                self.assertEqual(failed.exception.status_code, 401)

            with self.assertRaises(main.HTTPException) as limited:
                main.login_admin_staff(
                    payload,
                    self.request("127.0.0.1", "198.51.100.12"),
                )

        self.assertEqual(limited.exception.status_code, 429)
        with main.db() as conn:
            failed_attempts = conn.execute(
                """
                SELECT COUNT(*)
                FROM admin_audit_log
                WHERE action = 'admin_staff_login_failed'
                """
            ).fetchone()[0]
        self.assertEqual(failed_attempts, 2)

    def test_admin_2fa_email_resend_has_a_cooldown(self) -> None:
        with main.db() as conn:
            conn.execute("UPDATE admin_staff SET two_factor_enabled = 1")
            row = conn.execute("SELECT * FROM admin_staff LIMIT 1").fetchone()
            conn.commit()
        request = self.request("127.0.0.1", "198.51.100.77")

        with patch.object(main, "admin_2fa_email_configured", return_value=True), patch.object(
            main,
            "send_smtp_email",
            return_value=None,
        ):
            first = main.create_admin_2fa_challenge(row, request, "Test owner")
            with self.assertRaises(main.HTTPException) as limited:
                main.create_admin_2fa_challenge(row, request, "Test owner")

        self.assertTrue(first["twoFactorRequired"])
        self.assertEqual(limited.exception.status_code, 429)
        self.assertEqual(
            limited.exception.headers.get("Retry-After"),
            str(main.ADMIN_2FA_RESEND_COOLDOWN_SECONDS),
        )


class ServerHealthReadinessPolicyTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        main.init_db()

    def setUp(self) -> None:
        with main.db() as conn:
            conn.execute("DELETE FROM server_health_observations")
            conn.commit()

    def test_private_transport_previews_do_not_block_public_health_readiness(self) -> None:
        now = main.utc_now_iso()
        with main.db() as conn:
            conn.execute(
                """
                INSERT INTO server_health_observations(
                    endpoint_id, probe_id, probe_region, protocol, transport,
                    target, ok, status, latency_ms, packet_loss_percent,
                    error_code, message, details_json, observed_at, created_at
                )
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                (
                    "public-nl",
                    "external-smoke",
                    "outside",
                    "wireguard_udp",
                    "udp",
                    "public-nl.example.test",
                    1,
                    "healthy",
                    25,
                    0.0,
                    "",
                    "healthy",
                    '{"score": 100}',
                    now,
                    now,
                ),
            )
            conn.commit()

        managed_entries = [
            {
                "serverId": "public-nl",
                "isActive": True,
                "isPublic": True,
                "clientConfigReady": True,
            },
            {
                "serverId": "private-preview",
                "isActive": True,
                "isPublic": False,
                "clientConfigReady": True,
            },
        ]
        summary = {
            "serverHealthProbeAgents": [
                {
                    "probeId": "external-smoke",
                    "isExternal": True,
                    "isStale": False,
                    "problems24h": 0,
                    "lastStatus": "healthy",
                }
            ]
        }

        with patch.object(
            main,
            "list_managed_server_catalog_entries",
            return_value=managed_entries,
        ):
            readiness = main.server_health_external_probe_readiness(summary)

        self.assertTrue(readiness["productionReady"])
        self.assertEqual(readiness["requiredEndpointIds"], ["public-nl"])
        self.assertEqual(readiness["coveredEndpointIds"], ["public-nl"])
        self.assertEqual(readiness["missingEndpointIds"], [])


if __name__ == "__main__":
    unittest.main()
