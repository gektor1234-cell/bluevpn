import os
import copy
import tempfile
import unittest
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime
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
        with main.db() as conn:
            conn.execute("DELETE FROM beta_funnel_events")
            conn.execute("DELETE FROM beta_invite_redemptions")
            conn.execute("DELETE FROM beta_invites")
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


if __name__ == "__main__":
    unittest.main()
