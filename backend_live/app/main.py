import base64
import gzip
import hashlib
import html
import hmac
import ipaddress
import json
import os
import re
import secrets
import smtplib
import socket
import sqlite3
import ssl
import subprocess
import tempfile
import time
import urllib.error
import urllib.parse
import urllib.request
from datetime import datetime, timedelta, timezone
from decimal import Decimal, InvalidOperation
from email.message import EmailMessage
from pathlib import Path
from typing import Any, Optional

from fastapi import FastAPI, Header, HTTPException, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import HTMLResponse, RedirectResponse
from pydantic import BaseModel


APP_TITLE = "Green VPN Backend"
APP_VERSION = "0.9.69"
DEFAULT_PUBLIC_API_BASE_URL = "https://api.greenvpn.pro"


def split_env_list(value: str) -> list[str]:
    return [
        item.strip()
        for item in re.split(r"\r?\n|\s*;\s*|,\s*", value or "")
        if item.strip()
    ]


def clean_base_url(value: str) -> str:
    return (value or "").strip().rstrip("/")


PUBLIC_API_BASE_URL = (
    clean_base_url(os.getenv("GREENVPN_PUBLIC_API_BASE_URL", ""))
    or DEFAULT_PUBLIC_API_BASE_URL
)
ENFORCE_SUBSCRIPTION_ACCESS = (
    os.getenv("BLUEVPN_ENFORCE_SUBSCRIPTION_ACCESS", "").strip().lower()
    in {"1", "true", "yes", "on"}
)
AUTO_REPLACE_OLDEST_DEVICE_ON_LIMIT = (
    os.getenv("BLUEVPN_AUTO_REPLACE_OLDEST_DEVICE_ON_LIMIT", "1").strip().lower()
    in {"1", "true", "yes", "on"}
)
UPDATE_LATEST_VERSION = os.getenv("GREENVPN_LATEST_VERSION", "0.2.2-windows-mvp").strip()
UPDATE_DOWNLOAD_URL = os.getenv("GREENVPN_UPDATE_URL", "").strip()
UPDATE_SHA256 = os.getenv("GREENVPN_UPDATE_SHA256", "").strip()
UPDATE_ROLLBACK_VERSION = os.getenv("GREENVPN_ROLLBACK_VERSION", "").strip()
UPDATE_ROLLBACK_URL = os.getenv("GREENVPN_ROLLBACK_URL", "").strip()
UPDATE_ROLLBACK_SHA256 = os.getenv("GREENVPN_ROLLBACK_SHA256", "").strip()
UPDATE_REQUIRED = (
    os.getenv("GREENVPN_UPDATE_REQUIRED", "").strip().lower()
    in {"1", "true", "yes", "on"}
)
UPDATE_RELEASED_AT = os.getenv("GREENVPN_UPDATE_RELEASED_AT", "").strip()
UPDATE_CHANGELOG = [
    item.strip(" -")
    for item in re.split(
        r"\r?\n|\s*;\s*",
        os.getenv("GREENVPN_UPDATE_CHANGELOG", "Базовая система обновлений Green VPN."),
    )
    if item.strip(" -")
]
SERVER_CATALOG_VERSION = os.getenv(
    "GREENVPN_SERVER_CATALOG_VERSION",
    "2026-04-30-dev1",
).strip()
SERVER_CATALOG_API_BASE_URLS = split_env_list(
    os.getenv("GREENVPN_API_BASE_URLS", PUBLIC_API_BASE_URL)
)
SERVER_CATALOG_EMERGENCY_URL = os.getenv("GREENVPN_EMERGENCY_CATALOG_URL", "").strip()
SERVICE_CHECK_TIMEOUT_SECONDS = float(os.getenv("GREENVPN_SERVICE_CHECK_TIMEOUT", "5"))
SERVICE_CHECK_TARGETS = [
    {
        "code": "youtube",
        "title": "YouTube",
        "host": "www.youtube.com",
        "url": "https://www.youtube.com/generate_204",
    },
    {
        "code": "discord",
        "title": "Discord",
        "host": "discord.com",
        "url": "https://discord.com/api/v10/gateway",
    },
    {
        "code": "telegram",
        "title": "Telegram",
        "host": "api.telegram.org",
        "url": "https://api.telegram.org",
    },
]
ADMIN_ALERTS_ENABLED = (
    os.getenv("GREENVPN_ADMIN_ALERTS_ENABLED", "1").strip().lower()
    in {"1", "true", "yes", "on"}
)
ADMIN_ALERT_MIN_SEVERITY = os.getenv("GREENVPN_ADMIN_ALERT_MIN_SEVERITY", "high").strip().lower()
TELEGRAM_ALERT_BOT_TOKEN = os.getenv("GREENVPN_TELEGRAM_ALERT_BOT_TOKEN", "").strip()
TELEGRAM_ALERT_CHAT_ID = os.getenv("GREENVPN_TELEGRAM_ALERT_CHAT_ID", "").strip()
TELEGRAM_ALERT_TIMEOUT_SECONDS = float(os.getenv("GREENVPN_TELEGRAM_ALERT_TIMEOUT", "10"))
ADMIN_SESSION_TTL_HOURS = int(os.getenv("GREENVPN_ADMIN_SESSION_TTL_HOURS", "12"))
ADMIN_PASSWORD_HASH_ITERATIONS = int(os.getenv("GREENVPN_ADMIN_PASSWORD_HASH_ITERATIONS", "210000"))
ADMIN_2FA_REQUIRED = (
    os.getenv("GREENVPN_ADMIN_2FA_REQUIRED", "").strip().lower()
    in {"1", "true", "yes", "on"}
)
ADMIN_2FA_CODE_TTL_MINUTES = max(
    3,
    int(os.getenv("GREENVPN_ADMIN_2FA_CODE_TTL_MINUTES", "10")),
)
ADMIN_2FA_MAX_ATTEMPTS = max(
    1,
    int(os.getenv("GREENVPN_ADMIN_2FA_MAX_ATTEMPTS", "5")),
)

BASE_DIR = Path(os.getenv("BLUEVPN_BASE_DIR", "/opt/bluevpn/backend")).resolve()
DATA_DIR = Path(os.getenv("BLUEVPN_DATA_DIR", str(BASE_DIR / "data"))).resolve()
DB_PATH = DATA_DIR / "bluevpn.db"
ADMIN_TOKEN_PATH = DATA_DIR / "admin_token.txt"

WG_INTERFACE = os.getenv("BLUEVPN_WG_INTERFACE", "wg0")
WG_CONFIG_PATH = Path(os.getenv("BLUEVPN_WG_CONFIG_PATH", "/etc/wireguard/wg0.conf"))
WG_ENDPOINT_HOST = os.getenv("BLUEVPN_ENDPOINT_HOST", "37.220.85.211")
WG_ENDPOINT_PORT = int(os.getenv("BLUEVPN_ENDPOINT_PORT", "443"))
WG_DNS = os.getenv("BLUEVPN_DNS", "1.1.1.1")
WG_ALLOWED_IPS = os.getenv("BLUEVPN_ALLOWED_IPS", "0.0.0.0/1,128.0.0.0/1")
WG_CLIENT_IP_PREFIX = os.getenv("BLUEVPN_CLIENT_IP_PREFIX", "10.10.0.")
WG_CLIENT_IP_START = int(os.getenv("BLUEVPN_CLIENT_IP_START", "10"))
WG_CLIENT_IP_END = int(os.getenv("BLUEVPN_CLIENT_IP_END", "250"))

DEFAULT_PLAN_NAME = "Trial"
DEFAULT_PLAN_CODE = "trial"
DEFAULT_MAX_DEVICES = int(os.getenv("BLUEVPN_DEFAULT_MAX_DEVICES", "5"))
DEFAULT_TRIAL_DAYS = int(os.getenv("BLUEVPN_DEFAULT_TRIAL_DAYS", "3"))
PAID_PLAN_DAYS = int(os.getenv("BLUEVPN_PAID_PLAN_DAYS", "30"))

YOOKASSA_SHOP_ID = os.getenv("YOOKASSA_SHOP_ID", "").strip()
YOOKASSA_SECRET_KEY = os.getenv("YOOKASSA_SECRET_KEY", "").strip()
YOOKASSA_API_BASE = os.getenv("YOOKASSA_API_BASE", "https://api.yookassa.ru/v3").rstrip("/")
YOOKASSA_RETURN_URL = os.getenv(
    "YOOKASSA_RETURN_URL",
    "https://bluevpn.local/payment/return",
).strip()
PUBLIC_BASE_URL = clean_base_url(os.getenv("GREENVPN_PUBLIC_BASE_URL", PUBLIC_API_BASE_URL))
YOOKASSA_WEBHOOK_URL = os.getenv("YOOKASSA_WEBHOOK_URL", "").strip()
PUBLIC_SITE_URL = clean_base_url(
    os.getenv("GREENVPN_PUBLIC_SITE_URL", PUBLIC_API_BASE_URL)
)
PUBLIC_WINDOWS_DOWNLOAD_URL = os.getenv("GREENVPN_PUBLIC_WINDOWS_DOWNLOAD_URL", UPDATE_DOWNLOAD_URL).strip()
PUBLIC_ANDROID_DOWNLOAD_URL = os.getenv("GREENVPN_PUBLIC_ANDROID_DOWNLOAD_URL", "").strip()
PUBLIC_IOS_DOWNLOAD_URL = os.getenv("GREENVPN_PUBLIC_IOS_DOWNLOAD_URL", "").strip()
LEGAL_OWNER_NAME = os.getenv("GREENVPN_LEGAL_OWNER_NAME", "Владелец Green VPN").strip()
LEGAL_OWNER_INN = os.getenv("GREENVPN_LEGAL_OWNER_INN", "").strip()
LEGAL_CONTACT_EMAIL = os.getenv("GREENVPN_LEGAL_CONTACT_EMAIL", "support@greenvpn.pro").strip()
LEGAL_NOTICE = os.getenv("GREENVPN_LEGAL_NOTICE", "").strip()
PUBLIC_SITE_REQUIRED_PATHS = [
    {"path": "/", "title": "Landing page"},
    {"path": "/download/windows", "title": "Windows download"},
    {"path": "/download/android", "title": "Android download"},
    {"path": "/download/ios", "title": "iOS download"},
    {"path": "/legal/requisites", "title": "Legal requisites"},
    {"path": "/legal/offer", "title": "Public offer"},
    {"path": "/legal/privacy", "title": "Privacy policy"},
    {"path": "/legal/acceptable-use", "title": "Acceptable use"},
    {"path": "/legal/refunds", "title": "Refund policy"},
    {"path": "/payment/return", "title": "YooKassa return page"},
]
PUBLIC_SITE_REQUIRED_LANDING_LINKS = [
    {"code": "download_windows", "label": "Windows download button", "needle": "/download/windows"},
    {"code": "download_android", "label": "Android download card", "needle": "/download/android"},
    {"code": "download_ios", "label": "iOS download card", "needle": "/download/ios"},
    {"code": "pricing_anchor", "label": "Pricing anchor", "needle": "#plans"},
]
PUBLIC_SITE_REQUIRED_PRICING_MARKERS = [
    {"code": "trial_plan", "label": "Trial plan", "needle": "Пробный"},
    {"code": "starter_price", "label": "Starter price", "needle": "149 ₽/мес"},
    {"code": "standard_price", "label": "Standard price", "needle": "299 ₽/мес"},
    {"code": "plus_price", "label": "Plus price", "needle": "449 ₽/мес"},
    {"code": "maximum_price", "label": "Maximum price", "needle": "699 ₽/мес"},
]
PUBLIC_SITE_BANNED_PHRASES = [
    "обход блокировок",
    "обхода блокировок",
    "обойти блокировки",
    "разблокируем",
    "разблокировка",
    "разблокировать",
    "анонимность без следов",
    "невозможно заблокировать",
    "работает всегда и везде",
    "безлимит без ограничений",
    "youtube",
    "instagram",
    "discord",
]
RENEWAL_LOOKAHEAD_DAYS = int(os.getenv("GREENVPN_RENEWAL_LOOKAHEAD_DAYS", "7"))
RENEWAL_DUE_SOON_DAYS = int(os.getenv("GREENVPN_RENEWAL_DUE_SOON_DAYS", "1"))
SUBSCRIPTION_EXPIRY_LOOKAHEAD_DAYS = int(
    os.getenv("GREENVPN_SUBSCRIPTION_EXPIRY_LOOKAHEAD_DAYS", "7")
)

EMAIL_CONFIRMATION_REQUIRED = (
    os.getenv("GREENVPN_EMAIL_CONFIRMATION_REQUIRED", "").strip().lower()
    in {"1", "true", "yes", "on"}
)
EMAIL_CONFIRMATION_TTL_HOURS = int(os.getenv("GREENVPN_EMAIL_CONFIRMATION_TTL_HOURS", "24"))
EMAIL_PUBLIC_BASE_URL = (
    clean_base_url(os.getenv("GREENVPN_EMAIL_PUBLIC_BASE_URL", ""))
    or PUBLIC_BASE_URL
    or PUBLIC_API_BASE_URL
)
SMTP_HOST = os.getenv("GREENVPN_SMTP_HOST", "").strip()
SMTP_PORT = int(os.getenv("GREENVPN_SMTP_PORT", "587"))
SMTP_USERNAME = os.getenv("GREENVPN_SMTP_USERNAME", "").strip()
SMTP_PASSWORD = os.getenv("GREENVPN_SMTP_PASSWORD", "")
SMTP_FROM = os.getenv("GREENVPN_SMTP_FROM", "").strip()
SMTP_USE_TLS = (
    os.getenv("GREENVPN_SMTP_USE_TLS", "1").strip().lower()
    in {"1", "true", "yes", "on"}
)
SMS_PROVIDER = os.getenv("GREENVPN_SMS_PROVIDER", "manual_mvp").strip().lower()
SMS_CONFIRMATION_TTL_MINUTES = int(os.getenv("GREENVPN_SMS_CONFIRMATION_TTL_MINUTES", "10"))
SMS_RESEND_COOLDOWN_SECONDS = int(os.getenv("GREENVPN_SMS_RESEND_COOLDOWN_SECONDS", "60"))
SMS_CODE_PEPPER = os.getenv("GREENVPN_SMS_CODE_PEPPER", "")
SMS_FROM = os.getenv("GREENVPN_SMS_FROM", "").strip()
SMS_RU_API_ID = os.getenv("GREENVPN_SMS_RU_API_ID", "").strip()
SMS_RU_TEST_MODE = (
    os.getenv("GREENVPN_SMS_RU_TEST_MODE", "").strip().lower()
    in {"1", "true", "yes", "on"}
)
AUTH_CODE_TTL_MINUTES = int(os.getenv("GREENVPN_AUTH_CODE_TTL_MINUTES", "10"))
AUTH_CODE_RESEND_COOLDOWN_SECONDS = int(
    os.getenv("GREENVPN_AUTH_CODE_RESEND_COOLDOWN_SECONDS", "60")
)
AUTH_CODE_MAX_VERIFY_ATTEMPTS = int(os.getenv("GREENVPN_AUTH_CODE_MAX_VERIFY_ATTEMPTS", "5"))
AUTH_CODE_LOCKOUT_MINUTES = int(os.getenv("GREENVPN_AUTH_CODE_LOCKOUT_MINUTES", "15"))
AUTH_CODE_PEPPER = (
    os.getenv("GREENVPN_AUTH_CODE_PEPPER", "").strip()
    or SMS_CODE_PEPPER
    or "greenvpn-dev-auth-code-pepper-not-for-production"
)
ADMIN_2FA_CODE_PEPPER = (
    os.getenv("GREENVPN_ADMIN_2FA_CODE_PEPPER", "").strip()
    or AUTH_CODE_PEPPER
)
DEV_AUTH_CODES = (
    os.getenv("GREENVPN_DEV_AUTH_CODES", "").strip().lower()
    in {"1", "true", "yes", "on"}
)
ADMIN_CORS_ORIGINS = [
    item.strip()
    for item in re.split(
        r"\r?\n|\s*;\s*|,\s*",
        os.getenv("GREENVPN_ADMIN_CORS_ORIGINS", "*"),
    )
    if item.strip()
]
APP_RELEASE_PLATFORMS = ["windows"]
APP_RELEASE_CHANNELS = ["stable", "beta", "internal"]
APP_RELEASE_STATUSES = ["draft", "published", "paused", "retired"]
SERVER_CATALOG_STATUSES = ["draft", "healthy", "degraded", "maintenance", "disabled"]
SERVER_CATALOG_PROTOCOLS = [
    "wireguard_udp",
    "wireguard_tcp",
    "openvpn_tcp",
    "shadowsocks",
    "hysteria2",
    "stealth",
]
SERVER_CATALOG_TRANSPORTS = ["udp", "tcp", "tls", "quic", "http3"]
SERVER_CLIENT_CONFIG_PROFILES = ["none", "builtin_wg0"]
SERVER_CLIENT_CONFIG_PROFILE_TITLES = {
    "none": "Не выдавать клиентам",
    "builtin_wg0": "Текущий backend wg0",
}
SERVER_HEALTH_STATUSES = ["healthy", "degraded", "down", "unknown"]
SERVER_PUBLIC_MIN_HEALTH_SCORE = int(os.getenv("GREENVPN_SERVER_PUBLIC_MIN_HEALTH_SCORE", "80"))
SERVER_PUBLIC_OBSERVATION_MAX_AGE_HOURS = int(
    os.getenv("GREENVPN_SERVER_PUBLIC_OBSERVATION_MAX_AGE_HOURS", "24")
)
SERVER_PUBLIC_MIN_HEALTHY_OBSERVATIONS = int(
    os.getenv("GREENVPN_SERVER_PUBLIC_MIN_HEALTHY_OBSERVATIONS", "1")
)
SERVER_PUBLIC_AUTO_PAUSE_ENABLED = (
    os.getenv("GREENVPN_SERVER_PUBLIC_AUTO_PAUSE_ENABLED", "1").strip().lower()
    not in {"0", "false", "no", "off"}
)
MONITORING_TARGET_STATUSES = ["active", "paused", "disabled"]
MONITORING_TARGET_TYPES = [
    "web",
    "api",
    "dns",
    "tcp",
    "tls",
    "telegram",
    "discord",
    "youtube",
    "payment",
    "update",
    "bootstrap",
    "social",
]
SERVICE_AVAILABILITY_STATUSES = ["green", "yellow", "red", "unknown"]
SERVICE_PROBE_STALE_AFTER_SECONDS = max(
    60,
    int(os.getenv("GREENVPN_SERVICE_PROBE_STALE_AFTER_SECONDS", "900")),
)
SERVICE_PROBE_REQUIRED_TARGET_IDS = [
    item.strip().lower()
    for item in re.split(
        r"\r?\n|\s*;\s*|,\s*",
        os.getenv(
            "GREENVPN_SERVICE_PROBE_REQUIRED_TARGET_IDS",
            "green_api_healthz,production_api_healthz,youtube_web,discord_web,telegram_web",
        ),
    )
    if item.strip()
]
FEATURE_FLAG_SCOPES = [
    "global",
    "client",
    "backend",
    "payments",
    "auth",
    "support",
    "updates",
    "monitoring",
    "vpn",
    "experimental",
]
RUNBOOK_CATEGORIES = [
    "vpn",
    "auth",
    "payments",
    "support",
    "updates",
    "monitoring",
    "servers",
    "security",
    "incident",
    "general",
]
RUNBOOK_SEVERITIES = ["low", "normal", "high", "critical"]
SUPPORT_ACTION_TYPES = [
    "reset_user_sessions",
    "request_config_refresh",
    "clear_config_refresh",
    "disable_device",
    "enable_device",
    "add_support_note",
    "grant_support_trial_3d",
]
SUPPORT_ACTION_STATUSES = ["queued", "done", "failed", "noop"]
SUPPORT_ACTIONS_REQUIRING_REASON = {
    "reset_user_sessions",
    "disable_device",
    "grant_support_trial_3d",
}
SUBSCRIPTION_EXPIRY_REVIEW_STATUSES = ["reviewed", "deferred"]
OWNER_ACTION_STATUSES = [
    "todo",
    "in_progress",
    "waiting_owner",
    "waiting_provider",
    "ready_to_apply",
    "done",
    "blocked",
    "not_needed",
]
OWNER_ACTION_STATUS_TITLES = {
    "todo": "Нужно сделать",
    "in_progress": "В работе",
    "waiting_owner": "Ждём владельца",
    "waiting_provider": "Ждём провайдера",
    "ready_to_apply": "Данные готовы",
    "done": "Закрыто",
    "blocked": "Заблокировано",
    "not_needed": "Не требуется",
}
OWNER_ACTION_NOTE_REQUIRED_STATUSES = {
    "waiting_owner",
    "waiting_provider",
    "ready_to_apply",
    "blocked",
    "not_needed",
}

ADMIN_ROLE_MATRIX = {
    "owner": {
        "title": "Главный админ",
        "permissions": [
            "dashboard.read",
            "analytics.read",
            "users.read",
            "users.manage",
            "devices.manage",
            "support.read",
            "support.manage",
            "support_actions.read",
            "support_actions.manage",
            "billing.read",
            "billing.manage",
            "staff.manage",
            "audit.read",
            "readiness.read",
            "readiness.manage",
            "monitoring.read",
            "monitoring.manage",
            "incidents.read",
            "incidents.manage",
            "updates.read",
            "updates.manage",
            "servers.read",
            "servers.manage",
            "flags.read",
            "flags.manage",
            "runbooks.read",
            "runbooks.manage",
        ],
    },
    "admin": {
        "title": "Администратор",
        "permissions": [
            "dashboard.read",
            "analytics.read",
            "users.read",
            "users.manage",
            "devices.manage",
            "support.read",
            "support.manage",
            "support_actions.read",
            "support_actions.manage",
            "billing.read",
            "billing.manage",
            "audit.read",
            "readiness.read",
            "readiness.manage",
            "monitoring.read",
            "monitoring.manage",
            "incidents.read",
            "incidents.manage",
            "updates.read",
            "updates.manage",
            "servers.read",
            "servers.manage",
            "flags.read",
            "flags.manage",
            "runbooks.read",
            "runbooks.manage",
        ],
    },
    "support": {
        "title": "Техподдержка",
        "permissions": [
            "dashboard.read",
            "analytics.read",
            "users.read",
            "devices.manage",
            "support.read",
            "support.manage",
            "support_actions.read",
            "support_actions.manage",
            "readiness.read",
            "monitoring.read",
            "monitoring.manage",
            "incidents.read",
            "incidents.manage",
            "updates.read",
            "servers.read",
            "flags.read",
            "runbooks.read",
        ],
    },
    "finance": {
        "title": "Финансы",
        "permissions": [
            "dashboard.read",
            "analytics.read",
            "users.read",
            "billing.read",
            "billing.manage",
            "readiness.read",
            "incidents.read",
            "updates.read",
            "servers.read",
            "flags.read",
            "runbooks.read",
        ],
    },
    "readonly": {
        "title": "Только просмотр",
        "permissions": [
            "dashboard.read",
            "analytics.read",
            "users.read",
            "support.read",
            "support_actions.read",
            "billing.read",
            "audit.read",
            "readiness.read",
            "monitoring.read",
            "incidents.read",
            "updates.read",
            "servers.read",
            "flags.read",
            "runbooks.read",
        ],
    },
}

SUPPORT_STATUSES = ["new", "triage", "in_progress", "waiting_user", "resolved", "closed"]
SUPPORT_PRIORITIES = {
    "urgent": {"title": "Срочно", "slaHours": 4},
    "high": {"title": "Высокий", "slaHours": 12},
    "normal": {"title": "Обычный", "slaHours": 24},
    "low": {"title": "Низкий", "slaHours": 72},
}
SUPPORT_CATEGORIES = {
    "vpn_connect": {
        "title": "VPN подключение",
        "keywords": [
            "wireguard",
            "handshake",
            "tunnel",
            "туннель",
            "service not running",
            "bluevpndev1",
            "vpn did not start",
            "подключ",
        ],
    },
    "network": {
        "title": "Сеть и доступность",
        "keywords": [
            "dns",
            "route",
            "маршрут",
            "traffic",
            "internet",
            "интернет",
            "youtube",
            "discord",
            "telegram",
            "amnezia",
            "warp",
        ],
    },
    "auth": {
        "title": "Вход и аккаунт",
        "keywords": [
            "auth",
            "login",
            "register",
            "email",
            "phone",
            "password",
            "session",
            "код",
            "почт",
            "телефон",
            "аккаунт",
        ],
    },
    "payment": {
        "title": "Оплата и тариф",
        "keywords": [
            "payment",
            "billing",
            "order",
            "yookassa",
            "subscription",
            "tariff",
            "оплат",
            "тариф",
            "подписк",
        ],
    },
    "installer": {
        "title": "Установка и обновление",
        "keywords": [
            "installer",
            "install",
            "uninstall",
            "uac",
            "administrator",
            "setup",
            "update",
            "установ",
            "администратор",
            "обновлен",
        ],
    },
    "app_ui": {
        "title": "Приложение и интерфейс",
        "keywords": [
            "ui",
            "theme",
            "language",
            "settings",
            "tray",
            "window",
            "dark",
            "язык",
            "тема",
            "настрой",
            "интерфейс",
        ],
    },
    "general": {
        "title": "Общее",
        "keywords": [],
    },
}

INCIDENT_STATUSES = ["open", "investigating", "mitigated", "resolved"]
INCIDENT_SEVERITIES = {
    "critical": {"title": "Критично", "rank": 4},
    "high": {"title": "Высокая", "rank": 3},
    "medium": {"title": "Средняя", "rank": 2},
    "low": {"title": "Низкая", "rank": 1},
}
TRAFFIC_GB_POINTS = [
    (1, 59),
    (5, 79),
    (20, 149),
    (50, 229),
    (100, 329),
    (200, 429),
    (500, 599),
]
TRAFFIC_PACK_BASE = {
    "gb5": {"title": "5 ГБ", "gb": 5, "priceRub": 79},
    "gb20": {"title": "20 ГБ", "gb": 20, "priceRub": 149},
    "gb50": {"title": "50 ГБ", "gb": 50, "priceRub": 229},
    "gb100": {"title": "100 ГБ", "gb": 100, "priceRub": 329},
    "unlimited": {"title": "Безлимит", "gb": None, "priceRub": 549},
}
UNLIMITED_APP_CATALOG = [
    {"code": "youtube", "title": "YouTube"},
    {"code": "telegram", "title": "Telegram"},
    {"code": "tiktok", "title": "TikTok"},
    {"code": "instagram", "title": "Instagram"},
    {"code": "discord", "title": "Discord"},
    {"code": "steam", "title": "Steam"},
    {"code": "netflix", "title": "Netflix"},
]
UNLIMITED_APP_CODES = {item["code"] for item in UNLIMITED_APP_CATALOG}
ADDITIONAL_DEVICE_RUB = 39
DEDICATED_IP_RUB = 149
INCLUDED_FEATURES = [
    "no_ads",
    "smart_routing",
]
PROMO_DISCOUNT_TYPES = {"percent", "fixed"}
PROMO_PLAN_CODES = {"starter", "base", "plus", "unlimited"}
PROMO_LAUNCH_RECOMMENDED_CODE = "START20"
PROMO_LAUNCH_RECOMMENDED_PERCENT = 20
PROMO_LAUNCH_RECOMMENDED_LIMIT = 100
PROMO_LAUNCH_RECOMMENDED_WINDOW_DAYS = 30
PROMO_LAUNCH_MAX_PUBLIC_PERCENT = 30
PROMO_LAUNCH_MAX_FIXED_DISCOUNT_RUB = 200
PROMO_LAUNCH_MAX_WINDOW_DAYS = 60
PROMO_LAUNCH_RECOMMENDED_PLANS = ["starter", "base", "plus"]

app = FastAPI(title=APP_TITLE, version=APP_VERSION)
app.add_middleware(
    CORSMiddleware,
    allow_origins=ADMIN_CORS_ORIGINS or ["*"],
    allow_methods=["GET", "POST", "OPTIONS"],
    allow_headers=["Authorization", "Content-Type", "X-Admin-Token", "X-Admin-Actor"],
)
ADMIN_TOKEN = ""


class RegisterIn(BaseModel):
    email: str
    password: str


class LoginIn(BaseModel):
    email: str
    password: str


class BootstrapIn(BaseModel):
    deviceUid: str
    deviceName: str
    platform: str = "windows"
    appVersion: str = "0.1.0"


class ClientConfigIn(BaseModel):
    deviceUid: str
    mode: str = "full"
    serverId: Optional[str] = None


class AdminDeviceToggleIn(BaseModel):
    reason: Optional[str] = None


class AdminSubscriptionIn(BaseModel):
    planCode: str
    planName: str
    maxDevices: int
    isActive: bool = True
    expiresAt: Optional[str] = None


class TariffSelectionIn(BaseModel):
    trafficPack: str = "gb20"
    trafficGb: int = 20
    unlimitedApps: list[str] = []
    devices: int = 1
    dedicatedIp: bool = False
    autoRenew: bool = True
    promoCode: Optional[str] = None


class AdminMarkOrderPaidIn(BaseModel):
    providerPaymentId: Optional[str] = None


class AdminPromoCodeIn(BaseModel):
    code: str
    title: Optional[str] = None
    discountType: str = "percent"
    discountValue: int = 10
    maxRedemptions: Optional[int] = None
    startsAt: Optional[str] = None
    expiresAt: Optional[str] = None
    isActive: bool = True
    appliesToPlanCodes: list[str] = []
    notes: Optional[str] = None


class AdminSubscriptionExpiryReviewIn(BaseModel):
    status: str = "reviewed"
    reason: str


class EmailVerifyIn(BaseModel):
    token: str


class PhoneStartIn(BaseModel):
    phone: str


class PhoneVerifyIn(BaseModel):
    phone: str
    code: str


class EmailCodeStartIn(BaseModel):
    email: str


class EmailCodeVerifyIn(BaseModel):
    email: str
    code: str
    deviceUid: Optional[str] = None
    deviceName: Optional[str] = None
    platform: Optional[str] = None
    appVersion: Optional[str] = None


class PhoneLoginStartIn(BaseModel):
    phone: str


class PhoneLoginVerifyIn(BaseModel):
    phone: str
    code: str
    deviceUid: Optional[str] = None
    deviceName: Optional[str] = None
    platform: Optional[str] = None
    appVersion: Optional[str] = None


class AuthChallengeStartIn(BaseModel):
    method: Optional[str] = None
    email: Optional[str] = None
    phone: Optional[str] = None


class AuthChallengeVerifyIn(BaseModel):
    method: Optional[str] = None
    email: Optional[str] = None
    phone: Optional[str] = None
    code: str
    deviceUid: Optional[str] = None
    deviceName: Optional[str] = None
    platform: Optional[str] = None
    appVersion: Optional[str] = None


class SupportReportIn(BaseModel):
    report: str
    summary: Optional[str] = None
    appVersion: Optional[str] = None
    deviceUid: Optional[str] = None


class AdminSupportReportStatusIn(BaseModel):
    status: str
    note: Optional[str] = None
    assignedTo: Optional[str] = None
    priority: Optional[str] = None
    category: Optional[str] = None
    slaDueAt: Optional[str] = None


class AdminSupportReportReviewIn(BaseModel):
    note: Optional[str] = None
    assignedTo: Optional[str] = None


class AdminSupportReportCommentIn(BaseModel):
    body: str
    author: Optional[str] = None


class AdminSupportActionIn(BaseModel):
    action: str
    reason: Optional[str] = None
    deviceUid: Optional[str] = None
    note: Optional[str] = None


class AdminStaffIn(BaseModel):
    email: str
    displayName: Optional[str] = None
    role: str = "support"
    isActive: bool = True
    temporaryPassword: Optional[str] = None
    twoFactorEnabled: bool = False


class AdminStaffUpdateIn(BaseModel):
    displayName: Optional[str] = None
    role: Optional[str] = None
    isActive: Optional[bool] = None
    temporaryPassword: Optional[str] = None
    twoFactorEnabled: Optional[bool] = None


class AdminLoginIn(BaseModel):
    email: str
    password: str
    actor: Optional[str] = None


class AdminTwoFactorVerifyIn(BaseModel):
    email: str
    challengeId: str
    code: str
    actor: Optional[str] = None


class AdminPasswordChangeIn(BaseModel):
    currentPassword: str
    newPassword: str


class AdminSessionRevokeIn(BaseModel):
    sessionId: str


class AdminIncidentUpdateIn(BaseModel):
    status: Optional[str] = None
    severity: Optional[str] = None
    assignee: Optional[str] = None
    assigneeStaffId: Optional[int] = None
    clearAssignee: Optional[bool] = None
    note: Optional[str] = None


class AdminAppReleaseIn(BaseModel):
    platform: Optional[str] = "windows"
    channel: Optional[str] = "stable"
    version: Optional[str] = None
    buildNumber: Optional[str] = None
    downloadUrl: Optional[str] = None
    sha256: Optional[str] = None
    sizeBytes: Optional[int] = None
    isRequired: Optional[bool] = None
    minSupportedVersion: Optional[str] = None
    rolloutPercent: Optional[int] = None
    changelog: Optional[list[str]] = None
    status: Optional[str] = None


class AdminServerCatalogEntryIn(BaseModel):
    serverId: Optional[str] = None
    title: Optional[str] = None
    subtitle: Optional[str] = None
    country: Optional[str] = None
    city: Optional[str] = None
    provider: Optional[str] = None
    host: Optional[str] = None
    port: Optional[int] = None
    protocol: Optional[str] = "wireguard_udp"
    transport: Optional[str] = "udp"
    clientConfigProfile: Optional[str] = "none"
    status: Optional[str] = "draft"
    healthScore: Optional[int] = None
    latencyMs: Optional[int] = None
    priority: Optional[int] = None
    isActive: Optional[bool] = None
    isPublic: Optional[bool] = None
    notes: Optional[str] = None


class AdminServerCatalogDraftIn(BaseModel):
    serverId: Optional[str] = None
    title: Optional[str] = None
    subtitle: Optional[str] = None
    country: Optional[str] = None
    city: Optional[str] = None
    provider: Optional[str] = None
    host: Optional[str] = None
    port: Optional[int] = None
    plannedBandwidthMbps: Optional[int] = None
    monthlyCostRub: Optional[int] = None
    notes: Optional[str] = None


class AdminServerHealthObservationIn(BaseModel):
    endpointId: str
    probeId: Optional[str] = None
    probeRegion: Optional[str] = None
    protocol: Optional[str] = None
    transport: Optional[str] = None
    target: Optional[str] = None
    ok: Optional[bool] = None
    status: Optional[str] = None
    latencyMs: Optional[int] = None
    packetLossPercent: Optional[float] = None
    errorCode: Optional[str] = None
    message: Optional[str] = None
    details: Optional[dict] = None
    observedAt: Optional[str] = None


class AdminMonitoringTargetIn(BaseModel):
    targetId: Optional[str] = None
    title: Optional[str] = None
    service: Optional[str] = None
    targetType: Optional[str] = "web"
    url: Optional[str] = None
    host: Optional[str] = None
    port: Optional[int] = None
    path: Optional[str] = None
    expectedStatus: Optional[int] = None
    timeoutSeconds: Optional[int] = None
    intervalSeconds: Optional[int] = None
    status: Optional[str] = "active"
    tags: Optional[list[str]] = None
    notes: Optional[str] = None
    publicImpact: Optional[bool] = True


class AdminServiceAvailabilityObservationIn(BaseModel):
    targetId: str
    probeId: Optional[str] = None
    probeRegion: Optional[str] = None
    ok: Optional[bool] = None
    status: Optional[str] = None
    latencyMs: Optional[int] = None
    errorCode: Optional[str] = None
    message: Optional[str] = None
    details: Optional[dict] = None
    observedAt: Optional[str] = None


class AdminFeatureFlagIn(BaseModel):
    key: Optional[str] = None
    title: Optional[str] = None
    description: Optional[str] = None
    value: Optional[Any] = None
    scope: Optional[str] = "global"
    isEnabled: Optional[bool] = None
    rolloutPercent: Optional[int] = None
    notes: Optional[str] = None


class AdminRunbookIn(BaseModel):
    key: Optional[str] = None
    title: Optional[str] = None
    category: Optional[str] = "general"
    severity: Optional[str] = "normal"
    summary: Optional[str] = None
    steps: Optional[list[str]] = None
    ownerRole: Optional[str] = None
    isActive: Optional[bool] = None


class AdminOwnerActionStatusIn(BaseModel):
    status: Optional[str] = "todo"
    note: Optional[str] = None


def utc_now() -> datetime:
    return datetime.now(timezone.utc)


def utc_now_iso() -> str:
    return utc_now().isoformat()


def parse_dt(value: Optional[str]) -> Optional[datetime]:
    if not value:
        return None
    try:
        return datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError:
        return None


def ensure_dirs() -> None:
    DATA_DIR.mkdir(parents=True, exist_ok=True)


def db() -> sqlite3.Connection:
    conn = sqlite3.connect(DB_PATH)
    conn.row_factory = sqlite3.Row
    return conn


def ensure_column(conn: sqlite3.Connection, table: str, column: str, ddl: str) -> None:
    rows = conn.execute(f"PRAGMA table_info({table})").fetchall()
    columns = {row["name"] if isinstance(row, sqlite3.Row) else row[1] for row in rows}
    if column not in columns:
        conn.execute(f"ALTER TABLE {table} ADD COLUMN {ddl}")


def init_db() -> None:
    ensure_dirs()
    with db() as conn:
        conn.execute(
            """
            CREATE TABLE IF NOT EXISTS users (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                email TEXT NOT NULL UNIQUE,
                password_hash TEXT NOT NULL,
                created_at TEXT NOT NULL
            )
            """
        )
        ensure_column(
            conn,
            "users",
            "email_verified",
            "email_verified INTEGER NOT NULL DEFAULT 0",
        )
        ensure_column(
            conn,
            "users",
            "email_verified_at",
            "email_verified_at TEXT",
        )
        ensure_column(conn, "users", "phone", "phone TEXT")
        ensure_column(
            conn,
            "users",
            "phone_verified",
            "phone_verified INTEGER NOT NULL DEFAULT 0",
        )
        ensure_column(conn, "users", "phone_verified_at", "phone_verified_at TEXT")

        conn.execute(
            """
            CREATE TABLE IF NOT EXISTS tokens (
                token TEXT PRIMARY KEY,
                user_id INTEGER NOT NULL,
                created_at TEXT NOT NULL,
                FOREIGN KEY(user_id) REFERENCES users(id)
            )
            """
        )

        conn.execute(
            """
            CREATE TABLE IF NOT EXISTS email_confirmations (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                user_id INTEGER NOT NULL,
                email TEXT NOT NULL,
                token_hash TEXT NOT NULL UNIQUE,
                status TEXT NOT NULL,
                created_at TEXT NOT NULL,
                expires_at TEXT NOT NULL,
                sent_at TEXT,
                consumed_at TEXT,
                FOREIGN KEY(user_id) REFERENCES users(id)
            )
            """
        )

        conn.execute(
            """
            CREATE TABLE IF NOT EXISTS email_outbox (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                user_id INTEGER NOT NULL,
                email TEXT NOT NULL,
                subject TEXT NOT NULL,
                body TEXT NOT NULL,
                status TEXT NOT NULL,
                error TEXT,
                created_at TEXT NOT NULL,
                sent_at TEXT,
                FOREIGN KEY(user_id) REFERENCES users(id)
            )
            """
        )

        conn.execute(
            """
            CREATE TABLE IF NOT EXISTS phone_confirmations (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                user_id INTEGER NOT NULL,
                phone TEXT NOT NULL,
                code_hash TEXT NOT NULL,
                status TEXT NOT NULL,
                created_at TEXT NOT NULL,
                expires_at TEXT NOT NULL,
                sent_at TEXT,
                consumed_at TEXT,
                FOREIGN KEY(user_id) REFERENCES users(id)
            )
            """
        )
        ensure_column(
            conn,
            "phone_confirmations",
            "attempts_count",
            "attempts_count INTEGER NOT NULL DEFAULT 0",
        )
        ensure_column(conn, "phone_confirmations", "last_attempt_at", "last_attempt_at TEXT")
        ensure_column(conn, "phone_confirmations", "locked_until", "locked_until TEXT")

        conn.execute(
            """
            CREATE TABLE IF NOT EXISTS email_login_codes (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                user_id INTEGER NOT NULL,
                email TEXT NOT NULL,
                code_hash TEXT NOT NULL,
                status TEXT NOT NULL,
                purpose TEXT NOT NULL,
                created_at TEXT NOT NULL,
                expires_at TEXT NOT NULL,
                sent_at TEXT,
                consumed_at TEXT,
                FOREIGN KEY(user_id) REFERENCES users(id)
            )
            """
        )
        ensure_column(
            conn,
            "email_login_codes",
            "attempts_count",
            "attempts_count INTEGER NOT NULL DEFAULT 0",
        )
        ensure_column(conn, "email_login_codes", "last_attempt_at", "last_attempt_at TEXT")
        ensure_column(conn, "email_login_codes", "locked_until", "locked_until TEXT")

        conn.execute(
            """
            CREATE TABLE IF NOT EXISTS sms_outbox (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                user_id INTEGER NOT NULL,
                phone TEXT NOT NULL,
                body TEXT NOT NULL,
                status TEXT NOT NULL,
                error TEXT,
                created_at TEXT NOT NULL,
                sent_at TEXT,
                FOREIGN KEY(user_id) REFERENCES users(id)
            )
            """
        )

        conn.execute(
            """
            CREATE TABLE IF NOT EXISTS auth_events (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                user_id INTEGER,
                email TEXT,
                phone TEXT,
                event_type TEXT NOT NULL,
                status TEXT NOT NULL,
                request_ip TEXT,
                user_agent TEXT,
                details_json TEXT,
                created_at TEXT NOT NULL
            )
            """
        )

        conn.execute(
            """
            CREATE TABLE IF NOT EXISTS support_reports (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                user_id INTEGER NOT NULL,
                email TEXT NOT NULL,
                device_uid TEXT,
                app_version TEXT,
                summary TEXT,
                report_code TEXT NOT NULL,
                status TEXT NOT NULL,
                request_ip TEXT,
                user_agent TEXT,
                created_at TEXT NOT NULL,
                FOREIGN KEY(user_id) REFERENCES users(id)
            )
            """
        )
        ensure_column(conn, "support_reports", "admin_note", "admin_note TEXT")
        ensure_column(conn, "support_reports", "assigned_to", "assigned_to TEXT")
        ensure_column(conn, "support_reports", "updated_at", "updated_at TEXT")
        ensure_column(conn, "support_reports", "handled_at", "handled_at TEXT")
        ensure_column(
            conn,
            "support_reports",
            "priority",
            "priority TEXT NOT NULL DEFAULT 'normal'",
        )
        ensure_column(
            conn,
            "support_reports",
            "category",
            "category TEXT NOT NULL DEFAULT 'general'",
        )
        ensure_column(conn, "support_reports", "triage_reason", "triage_reason TEXT")
        ensure_column(conn, "support_reports", "sla_due_at", "sla_due_at TEXT")
        ensure_column(conn, "support_reports", "first_response_at", "first_response_at TEXT")
        ensure_column(conn, "support_reports", "reviewed_at", "reviewed_at TEXT")
        ensure_column(conn, "support_reports", "reviewed_by", "reviewed_by TEXT")

        conn.execute(
            """
            CREATE TABLE IF NOT EXISTS support_report_comments (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                report_id INTEGER NOT NULL,
                author TEXT NOT NULL,
                body TEXT NOT NULL,
                created_at TEXT NOT NULL,
                request_ip TEXT,
                user_agent TEXT,
                FOREIGN KEY(report_id) REFERENCES support_reports(id)
            )
            """
        )

        conn.execute(
            """
            CREATE TABLE IF NOT EXISTS admin_support_actions (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                user_id INTEGER NOT NULL,
                device_uid TEXT,
                action TEXT NOT NULL,
                status TEXT NOT NULL,
                reason TEXT,
                result_json TEXT NOT NULL,
                requested_by TEXT NOT NULL,
                request_ip TEXT,
                user_agent TEXT,
                created_at TEXT NOT NULL,
                FOREIGN KEY(user_id) REFERENCES users(id)
            )
            """
        )
        conn.execute(
            """
            CREATE INDEX IF NOT EXISTS idx_admin_support_actions_user
            ON admin_support_actions(user_id, id DESC)
            """
        )
        conn.execute(
            """
            CREATE INDEX IF NOT EXISTS idx_admin_support_actions_lookup
            ON admin_support_actions(action, status, created_at)
            """
        )

        conn.execute(
            """
            CREATE TABLE IF NOT EXISTS subscription_expiry_reviews (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                subscription_id INTEGER NOT NULL,
                user_id INTEGER NOT NULL,
                status TEXT NOT NULL,
                reason TEXT NOT NULL,
                reviewed_by TEXT NOT NULL,
                request_ip TEXT,
                user_agent TEXT,
                created_at TEXT NOT NULL,
                FOREIGN KEY(subscription_id) REFERENCES subscriptions(id),
                FOREIGN KEY(user_id) REFERENCES users(id)
            )
            """
        )
        conn.execute(
            """
            CREATE INDEX IF NOT EXISTS idx_subscription_expiry_reviews_subscription
            ON subscription_expiry_reviews(subscription_id, id DESC)
            """
        )
        conn.execute(
            """
            CREATE INDEX IF NOT EXISTS idx_subscription_expiry_reviews_user
            ON subscription_expiry_reviews(user_id, id DESC)
            """
        )

        conn.execute(
            """
            CREATE TABLE IF NOT EXISTS admin_owner_action_statuses (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                action_code TEXT NOT NULL UNIQUE,
                status TEXT NOT NULL,
                note TEXT,
                updated_by TEXT,
                created_at TEXT NOT NULL,
                updated_at TEXT NOT NULL
            )
            """
        )
        conn.execute(
            """
            CREATE INDEX IF NOT EXISTS idx_admin_owner_action_statuses_status
            ON admin_owner_action_statuses(status, updated_at)
            """
        )

        conn.execute(
            """
            CREATE TABLE IF NOT EXISTS admin_audit_log (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                actor TEXT NOT NULL,
                action TEXT NOT NULL,
                target_type TEXT,
                target_id TEXT,
                details_json TEXT,
                request_ip TEXT,
                user_agent TEXT,
                created_at TEXT NOT NULL
            )
            """
        )

        conn.execute(
            """
            CREATE TABLE IF NOT EXISTS admin_staff (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                email TEXT NOT NULL UNIQUE,
                display_name TEXT,
                role TEXT NOT NULL,
                is_active INTEGER NOT NULL DEFAULT 1,
                created_at TEXT NOT NULL,
                updated_at TEXT NOT NULL,
                last_seen_at TEXT
            )
            """
        )
        ensure_column(conn, "admin_staff", "password_hash", "password_hash TEXT")
        ensure_column(conn, "admin_staff", "password_set_at", "password_set_at TEXT")
        ensure_column(conn, "admin_staff", "last_login_at", "last_login_at TEXT")
        ensure_column(conn, "admin_staff", "two_factor_enabled", "two_factor_enabled INTEGER NOT NULL DEFAULT 0")
        ensure_column(conn, "admin_staff", "two_factor_method", "two_factor_method TEXT NOT NULL DEFAULT 'email'")
        ensure_column(conn, "admin_staff", "two_factor_set_at", "two_factor_set_at TEXT")

        conn.execute(
            """
            CREATE TABLE IF NOT EXISTS admin_sessions (
                token_hash TEXT PRIMARY KEY,
                staff_id INTEGER NOT NULL,
                created_at TEXT NOT NULL,
                expires_at TEXT NOT NULL,
                last_seen_at TEXT,
                revoked_at TEXT,
                request_ip TEXT,
                user_agent TEXT,
                FOREIGN KEY(staff_id) REFERENCES admin_staff(id)
            )
            """
        )
        conn.execute(
            """
            CREATE TABLE IF NOT EXISTS admin_2fa_challenges (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                challenge_id TEXT NOT NULL UNIQUE,
                staff_id INTEGER NOT NULL,
                code_hash TEXT NOT NULL,
                status TEXT NOT NULL,
                attempts_count INTEGER NOT NULL DEFAULT 0,
                request_ip TEXT,
                user_agent TEXT,
                created_at TEXT NOT NULL,
                sent_at TEXT,
                expires_at TEXT NOT NULL,
                verified_at TEXT,
                failed_at TEXT,
                locked_until TEXT,
                FOREIGN KEY(staff_id) REFERENCES admin_staff(id)
            )
            """
        )
        conn.execute(
            """
            CREATE INDEX IF NOT EXISTS idx_admin_2fa_challenges_staff
            ON admin_2fa_challenges(staff_id, status, expires_at)
            """
        )
        conn.execute(
            """
            CREATE INDEX IF NOT EXISTS idx_admin_2fa_challenges_lookup
            ON admin_2fa_challenges(challenge_id, status)
            """
        )

        conn.execute(
            """
            CREATE TABLE IF NOT EXISTS admin_incidents (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                incident_key TEXT NOT NULL UNIQUE,
                title TEXT NOT NULL,
                severity TEXT NOT NULL,
                status TEXT NOT NULL,
                source TEXT NOT NULL,
                affected_service TEXT,
                affected_endpoint TEXT,
                first_seen_at TEXT NOT NULL,
                last_seen_at TEXT NOT NULL,
                resolved_at TEXT,
                assignee TEXT,
                assignee_staff_id INTEGER,
                assigned_at TEXT,
                assigned_by TEXT,
                summary TEXT,
                last_alert_at TEXT,
                last_alert_status TEXT,
                last_alert_error TEXT,
                details_json TEXT
            )
            """
        )
        ensure_column(conn, "admin_incidents", "assignee_staff_id", "assignee_staff_id INTEGER")
        ensure_column(conn, "admin_incidents", "assigned_at", "assigned_at TEXT")
        ensure_column(conn, "admin_incidents", "assigned_by", "assigned_by TEXT")
        ensure_column(conn, "admin_incidents", "last_alert_at", "last_alert_at TEXT")
        ensure_column(conn, "admin_incidents", "last_alert_status", "last_alert_status TEXT")
        ensure_column(conn, "admin_incidents", "last_alert_error", "last_alert_error TEXT")

        conn.execute(
            """
            CREATE TABLE IF NOT EXISTS admin_alert_events (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                incident_id INTEGER,
                incident_key TEXT,
                provider TEXT NOT NULL,
                reason TEXT,
                severity TEXT,
                status TEXT NOT NULL,
                error TEXT,
                message_preview TEXT,
                created_at TEXT NOT NULL,
                sent_at TEXT,
                retry_count INTEGER NOT NULL DEFAULT 0
            )
            """
        )

        conn.execute(
            """
            CREATE TABLE IF NOT EXISTS app_releases (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                platform TEXT NOT NULL,
                channel TEXT NOT NULL,
                version TEXT NOT NULL,
                build_number TEXT,
                download_url TEXT,
                sha256 TEXT,
                size_bytes INTEGER,
                is_required INTEGER NOT NULL DEFAULT 0,
                min_supported_version TEXT,
                rollout_percent INTEGER NOT NULL DEFAULT 100,
                changelog_json TEXT NOT NULL,
                status TEXT NOT NULL,
                created_at TEXT NOT NULL,
                updated_at TEXT NOT NULL,
                published_at TEXT,
                retired_at TEXT,
                UNIQUE(platform, channel, version)
            )
            """
        )
        conn.execute(
            """
            CREATE INDEX IF NOT EXISTS idx_app_releases_lookup
            ON app_releases(platform, channel, status, published_at)
            """
        )

        conn.execute(
            """
            CREATE TABLE IF NOT EXISTS server_catalog_entries (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                server_id TEXT NOT NULL UNIQUE,
                title TEXT NOT NULL,
                subtitle TEXT,
                country TEXT NOT NULL,
                city TEXT,
                provider TEXT,
                host TEXT NOT NULL,
                port INTEGER NOT NULL,
                protocol TEXT NOT NULL,
                transport TEXT NOT NULL,
                client_config_profile TEXT NOT NULL DEFAULT 'none',
                status TEXT NOT NULL,
                health_score INTEGER NOT NULL DEFAULT 0,
                latency_ms INTEGER,
                priority INTEGER NOT NULL DEFAULT 100,
                is_active INTEGER NOT NULL DEFAULT 0,
                is_public INTEGER NOT NULL DEFAULT 0,
                notes TEXT,
                created_at TEXT NOT NULL,
                updated_at TEXT NOT NULL
            )
            """
        )
        ensure_column(
            conn,
            "server_catalog_entries",
            "client_config_profile",
            "client_config_profile TEXT NOT NULL DEFAULT 'none'",
        )
        ensure_column(
            conn,
            "server_catalog_entries",
            "publication_paused_at",
            "publication_paused_at TEXT",
        )
        ensure_column(
            conn,
            "server_catalog_entries",
            "publication_paused_reason",
            "publication_paused_reason TEXT",
        )
        ensure_column(
            conn,
            "server_catalog_entries",
            "publication_paused_by",
            "publication_paused_by TEXT",
        )
        conn.execute(
            """
            CREATE INDEX IF NOT EXISTS idx_server_catalog_entries_lookup
            ON server_catalog_entries(is_active, is_public, status, priority)
            """
        )
        conn.execute(
            """
            CREATE TABLE IF NOT EXISTS server_health_observations (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                endpoint_id TEXT NOT NULL,
                probe_id TEXT,
                probe_region TEXT,
                protocol TEXT,
                transport TEXT,
                target TEXT,
                ok INTEGER NOT NULL DEFAULT 0,
                status TEXT NOT NULL,
                latency_ms INTEGER,
                packet_loss_percent REAL,
                error_code TEXT,
                message TEXT,
                details_json TEXT,
                observed_at TEXT NOT NULL,
                created_at TEXT NOT NULL
            )
            """
        )
        conn.execute(
            """
            CREATE INDEX IF NOT EXISTS idx_server_health_observations_endpoint
            ON server_health_observations(endpoint_id, observed_at)
            """
        )
        conn.execute(
            """
            CREATE INDEX IF NOT EXISTS idx_server_health_observations_status
            ON server_health_observations(status, observed_at)
            """
        )
        conn.execute(
            """
            CREATE INDEX IF NOT EXISTS idx_server_health_observations_probe
            ON server_health_observations(probe_region, protocol, observed_at)
            """
        )
        conn.execute(
            """
            CREATE TABLE IF NOT EXISTS monitoring_targets (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                target_id TEXT NOT NULL UNIQUE,
                title TEXT NOT NULL,
                service TEXT NOT NULL,
                target_type TEXT NOT NULL,
                url TEXT,
                host TEXT,
                port INTEGER,
                path TEXT,
                expected_status INTEGER,
                timeout_seconds INTEGER NOT NULL DEFAULT 5,
                interval_seconds INTEGER NOT NULL DEFAULT 300,
                status TEXT NOT NULL,
                tags_json TEXT NOT NULL,
                notes TEXT,
                public_impact INTEGER NOT NULL DEFAULT 1,
                created_at TEXT NOT NULL,
                updated_at TEXT NOT NULL
            )
            """
        )
        conn.execute(
            """
            CREATE INDEX IF NOT EXISTS idx_monitoring_targets_lookup
            ON monitoring_targets(status, service, target_type)
            """
        )
        conn.execute(
            """
            CREATE TABLE IF NOT EXISTS service_availability_observations (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                target_id TEXT NOT NULL,
                probe_id TEXT,
                probe_region TEXT,
                ok INTEGER NOT NULL DEFAULT 0,
                status TEXT NOT NULL,
                latency_ms INTEGER,
                error_code TEXT,
                message TEXT,
                details_json TEXT,
                observed_at TEXT NOT NULL,
                created_at TEXT NOT NULL
            )
            """
        )
        conn.execute(
            """
            CREATE INDEX IF NOT EXISTS idx_service_availability_observations_target
            ON service_availability_observations(target_id, observed_at)
            """
        )
        conn.execute(
            """
            CREATE INDEX IF NOT EXISTS idx_service_availability_observations_status
            ON service_availability_observations(status, observed_at)
            """
        )
        conn.execute(
            """
            CREATE INDEX IF NOT EXISTS idx_service_availability_observations_probe
            ON service_availability_observations(probe_region, observed_at)
            """
        )

        conn.execute(
            """
            CREATE TABLE IF NOT EXISTS admin_feature_flags (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                flag_key TEXT NOT NULL UNIQUE,
                title TEXT NOT NULL,
                description TEXT,
                value_json TEXT NOT NULL,
                scope TEXT NOT NULL,
                is_enabled INTEGER NOT NULL DEFAULT 0,
                rollout_percent INTEGER NOT NULL DEFAULT 0,
                notes TEXT,
                updated_by TEXT,
                created_at TEXT NOT NULL,
                updated_at TEXT NOT NULL
            )
            """
        )
        conn.execute(
            """
            CREATE INDEX IF NOT EXISTS idx_admin_feature_flags_scope
            ON admin_feature_flags(scope, is_enabled, updated_at)
            """
        )

        conn.execute(
            """
            CREATE TABLE IF NOT EXISTS admin_runbooks (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                runbook_key TEXT NOT NULL UNIQUE,
                title TEXT NOT NULL,
                category TEXT NOT NULL,
                severity TEXT NOT NULL,
                summary TEXT,
                steps_json TEXT NOT NULL,
                owner_role TEXT,
                is_active INTEGER NOT NULL DEFAULT 1,
                created_at TEXT NOT NULL,
                updated_at TEXT NOT NULL
            )
            """
        )
        conn.execute(
            """
            CREATE INDEX IF NOT EXISTS idx_admin_runbooks_lookup
            ON admin_runbooks(category, severity, is_active)
            """
        )

        conn.execute(
            """
            CREATE TABLE IF NOT EXISTS devices (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                user_id INTEGER NOT NULL,
                device_uid TEXT NOT NULL UNIQUE,
                device_name TEXT NOT NULL,
                platform TEXT NOT NULL,
                app_version TEXT NOT NULL,
                assigned_ip TEXT,
                client_private_key TEXT,
                client_public_key TEXT,
                preshared_key TEXT,
                created_at TEXT NOT NULL,
                updated_at TEXT NOT NULL,
                FOREIGN KEY(user_id) REFERENCES users(id)
            )
            """
        )

        ensure_column(
            conn,
            "devices",
            "is_enabled",
            "is_enabled INTEGER NOT NULL DEFAULT 1",
        )
        ensure_column(
            conn,
            "devices",
            "disabled_reason",
            "disabled_reason TEXT",
        )
        ensure_column(
            conn,
            "devices",
            "disabled_at",
            "disabled_at TEXT",
        )
        ensure_column(
            conn,
            "devices",
            "last_seen_at",
            "last_seen_at TEXT",
        )
        ensure_column(
            conn,
            "devices",
            "last_config_at",
            "last_config_at TEXT",
        )
        ensure_column(
            conn,
            "devices",
            "support_config_refresh_requested_at",
            "support_config_refresh_requested_at TEXT",
        )
        ensure_column(
            conn,
            "devices",
            "support_config_refresh_reason",
            "support_config_refresh_reason TEXT",
        )
        ensure_column(
            conn,
            "devices",
            "support_config_refresh_requested_by",
            "support_config_refresh_requested_by TEXT",
        )
        ensure_column(
            conn,
            "devices",
            "support_config_refresh_applied_at",
            "support_config_refresh_applied_at TEXT",
        )
        ensure_column(
            conn,
            "devices",
            "support_config_refresh_applied_reason",
            "support_config_refresh_applied_reason TEXT",
        )

        conn.execute(
            """
            CREATE TABLE IF NOT EXISTS subscriptions (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                user_id INTEGER NOT NULL,
                plan_code TEXT NOT NULL,
                plan_name TEXT NOT NULL,
                max_devices INTEGER NOT NULL,
                is_active INTEGER NOT NULL,
                expires_at TEXT,
                created_at TEXT NOT NULL,
                updated_at TEXT NOT NULL,
                FOREIGN KEY(user_id) REFERENCES users(id)
            )
            """
        )

        ensure_column(
            conn,
            "subscriptions",
            "monthly_price_rub",
            "monthly_price_rub INTEGER",
        )
        ensure_column(
            conn,
            "subscriptions",
            "selection_json",
            "selection_json TEXT",
        )
        ensure_column(
            conn,
            "subscriptions",
            "auto_renew",
            "auto_renew INTEGER NOT NULL DEFAULT 0",
        )
        ensure_column(
            conn,
            "subscriptions",
            "provider_payment_method_id",
            "provider_payment_method_id TEXT",
        )

        conn.execute(
            """
            CREATE TABLE IF NOT EXISTS billing_orders (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                public_id TEXT NOT NULL UNIQUE,
                user_id INTEGER NOT NULL,
                status TEXT NOT NULL,
                auto_renew INTEGER NOT NULL DEFAULT 1,
                amount_rub INTEGER NOT NULL,
                currency TEXT NOT NULL,
                selection_json TEXT NOT NULL,
                quote_json TEXT NOT NULL,
                payment_url TEXT,
                provider TEXT,
                provider_payment_id TEXT,
                provider_payment_method_id TEXT,
                paid_at TEXT,
                activated_at TEXT,
                created_at TEXT NOT NULL,
                updated_at TEXT NOT NULL,
                FOREIGN KEY(user_id) REFERENCES users(id)
            )
            """
        )
        ensure_column(
            conn,
            "billing_orders",
            "auto_renew",
            "auto_renew INTEGER NOT NULL DEFAULT 1",
        )
        ensure_column(
            conn,
            "billing_orders",
            "provider_payment_method_id",
            "provider_payment_method_id TEXT",
        )
        ensure_column(
            conn,
            "billing_orders",
            "promo_code",
            "promo_code TEXT",
        )
        ensure_column(
            conn,
            "billing_orders",
            "discount_rub",
            "discount_rub INTEGER NOT NULL DEFAULT 0",
        )
        ensure_column(
            conn,
            "billing_orders",
            "original_amount_rub",
            "original_amount_rub INTEGER",
        )

        conn.execute(
            """
            CREATE TABLE IF NOT EXISTS promo_codes (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                code TEXT NOT NULL UNIQUE,
                title TEXT NOT NULL,
                discount_type TEXT NOT NULL,
                discount_value INTEGER NOT NULL,
                max_redemptions INTEGER,
                redeemed_count INTEGER NOT NULL DEFAULT 0,
                starts_at TEXT,
                expires_at TEXT,
                is_active INTEGER NOT NULL DEFAULT 1,
                applies_to_plan_codes_json TEXT NOT NULL DEFAULT '[]',
                notes TEXT,
                created_at TEXT NOT NULL,
                updated_at TEXT NOT NULL
            )
            """
        )
        conn.execute(
            """
            CREATE TABLE IF NOT EXISTS promo_redemptions (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                promo_code_id INTEGER NOT NULL,
                code TEXT NOT NULL,
                user_id INTEGER NOT NULL,
                order_public_id TEXT NOT NULL,
                discount_rub INTEGER NOT NULL,
                created_at TEXT NOT NULL,
                FOREIGN KEY(promo_code_id) REFERENCES promo_codes(id),
                FOREIGN KEY(user_id) REFERENCES users(id)
            )
            """
        )
        conn.execute(
            "CREATE UNIQUE INDEX IF NOT EXISTS idx_promo_redemptions_order ON promo_redemptions(order_public_id)"
        )
        conn.execute(
            "CREATE INDEX IF NOT EXISTS idx_promo_codes_active_code ON promo_codes(is_active, code)"
        )
        conn.execute(
            "CREATE INDEX IF NOT EXISTS idx_promo_redemptions_code_user ON promo_redemptions(code, user_id)"
        )

        conn.execute("UPDATE devices SET is_enabled = 1 WHERE is_enabled IS NULL")

        conn.execute(
            "CREATE INDEX IF NOT EXISTS idx_email_login_codes_email_status ON email_login_codes(email, status)"
        )
        conn.execute(
            "CREATE INDEX IF NOT EXISTS idx_phone_confirmations_phone_status ON phone_confirmations(phone, status)"
        )
        conn.execute(
            "CREATE INDEX IF NOT EXISTS idx_support_reports_status_created ON support_reports(status, created_at)"
        )
        conn.execute(
            "CREATE INDEX IF NOT EXISTS idx_support_reports_category_priority ON support_reports(category, priority, created_at)"
        )
        conn.execute(
            "CREATE INDEX IF NOT EXISTS idx_admin_incidents_status_severity ON admin_incidents(status, severity, last_seen_at)"
        )
        conn.execute(
            "CREATE INDEX IF NOT EXISTS idx_admin_alert_events_created ON admin_alert_events(created_at, status)"
        )
        conn.execute(
            "CREATE INDEX IF NOT EXISTS idx_auth_events_created ON auth_events(created_at)"
        )

        conn.commit()


def ensure_admin_token() -> str:
    env_value = os.getenv("BLUEVPN_ADMIN_TOKEN", "").strip()
    if env_value:
        return env_value

    ensure_dirs()
    if ADMIN_TOKEN_PATH.exists():
        saved = ADMIN_TOKEN_PATH.read_text(encoding="utf-8").strip()
        if saved:
            return saved

    token = secrets.token_urlsafe(32)
    ADMIN_TOKEN_PATH.write_text(token, encoding="utf-8")
    return token


def ensure_subscription_for_existing_users() -> None:
    with db() as conn:
        users = conn.execute("SELECT id FROM users").fetchall()
        for user in users:
            row = conn.execute(
                "SELECT id FROM subscriptions WHERE user_id = ? ORDER BY id DESC LIMIT 1",
                (user["id"],),
            ).fetchone()
            if row is None:
                create_trial_subscription(conn, user["id"])
        conn.commit()


def backfill_expired_non_paid_subscriptions() -> dict:
    now = utc_now_iso()
    updated = 0
    safe_plan_codes = tuple(dict.fromkeys((DEFAULT_PLAN_CODE, "trial", "support_trial")))
    placeholders = ", ".join("?" for _ in safe_plan_codes)
    with db() as conn:
        updated = conn.execute(
            f"""
            UPDATE subscriptions
            SET is_active = 0,
                updated_at = ?
            WHERE is_active = 1
              AND expires_at IS NOT NULL
              AND expires_at <= ?
              AND plan_code IN ({placeholders})
            """,
            (now, now, *safe_plan_codes),
        ).rowcount
        conn.commit()
    return {
        "updated": int(updated or 0),
        "safePlanCodes": list(safe_plan_codes),
    }


def create_trial_subscription(conn: sqlite3.Connection, user_id: int) -> None:
    now = utc_now()
    expires_at = now + timedelta(days=DEFAULT_TRIAL_DAYS)
    conn.execute(
        """
        INSERT INTO subscriptions(
            user_id, plan_code, plan_name, max_devices, is_active,
            expires_at, created_at, updated_at
        )
        VALUES (?, ?, ?, ?, ?, ?, ?, ?)
        """,
        (
            user_id,
            DEFAULT_PLAN_CODE,
            DEFAULT_PLAN_NAME,
            DEFAULT_MAX_DEVICES,
            1,
            expires_at.isoformat(),
            now.isoformat(),
            now.isoformat(),
        ),
    )


def get_subscription_row(user_id: int):
    with db() as conn:
        row = conn.execute(
            """
            SELECT *
            FROM subscriptions
            WHERE user_id = ?
            ORDER BY id DESC
            LIMIT 1
            """,
            (user_id,),
        ).fetchone()

        if row is None:
            create_trial_subscription(conn, user_id)
            conn.commit()
            row = conn.execute(
                """
                SELECT *
                FROM subscriptions
                WHERE user_id = ?
                ORDER BY id DESC
                LIMIT 1
                """,
                (user_id,),
            ).fetchone()

    return row


def subscription_status(row) -> dict:
    expires_at = parse_dt(row["expires_at"]) if row else None
    is_active = bool(row["is_active"]) if row else False

    if expires_at is not None and utc_now() >= expires_at:
        is_active = False

    selection: Optional[dict] = None
    monthly_price_rub: Optional[int] = None
    auto_renew = False
    payment_method_saved = False
    if row:
        try:
            monthly_price_rub = int(row["monthly_price_rub"]) if row["monthly_price_rub"] is not None else None
        except Exception:
            monthly_price_rub = None
        raw_selection = row["selection_json"] if "selection_json" in row.keys() else None
        if raw_selection:
            try:
                parsed = json.loads(raw_selection)
                if isinstance(parsed, dict):
                    selection = parsed
            except Exception:
                selection = None
        try:
            auto_renew = bool(row["auto_renew"]) if "auto_renew" in row.keys() else bool((selection or {}).get("autoRenew", False))
        except Exception:
            auto_renew = bool((selection or {}).get("autoRenew", False))
        try:
            payment_method_saved = bool(row["provider_payment_method_id"]) if "provider_payment_method_id" in row.keys() else False
        except Exception:
            payment_method_saved = False

    return {
        "planName": row["plan_name"] if row else "None",
        "planCode": row["plan_code"] if row else "none",
        "maxDevices": int(row["max_devices"]) if row else 0,
        "isActive": is_active,
        "expiresAt": expires_at.isoformat() if expires_at else None,
        "monthlyPriceRub": monthly_price_rub,
        "autoRenew": auto_renew,
        "paymentMethodSaved": payment_method_saved,
        "selection": selection,
        "includedFeatures": INCLUDED_FEATURES,
    }


def build_tariff_catalog() -> dict:
    return {
        "trafficPacks": [
            {
                "code": code,
                "title": item["title"],
                "gb": item["gb"],
                "priceRub": item["priceRub"],
            }
            for code, item in TRAFFIC_PACK_BASE.items()
        ],
        "gbSlider": {
            "min": 1,
            "max": 500,
            "presets": [5, 20, 50, 100],
            "points": [
                {"gb": gb, "priceRub": price}
                for gb, price in TRAFFIC_GB_POINTS
            ],
        },
        "unlimitedApps": UNLIMITED_APP_CATALOG,
        "additionalDeviceRub": ADDITIONAL_DEVICE_RUB,
        "dedicatedIpRub": DEDICATED_IP_RUB,
        "includedFeatures": INCLUDED_FEATURES,
        "notes": [
            "Любой платный тариф уже включает отключение рекламы.",
            "Режим Social Only уже входит в подписку и не продаётся отдельно.",
            "Безлимитные приложения можно добавить поверх тарифа по ГБ.",
        ],
    }


def normalize_promo_code(value: Optional[str]) -> str:
    raw = (value or "").strip().upper()
    return re.sub(r"[^A-Z0-9_-]+", "", raw)[:32]


def normalize_promo_plan_codes(values: Optional[list[str]]) -> list[str]:
    normalized = []
    seen = set()
    for raw in values or []:
        code = str(raw or "").strip().lower()
        if code in PROMO_PLAN_CODES and code not in seen:
            normalized.append(code)
            seen.add(code)
    return normalized


def promo_plan_codes_from_row(row) -> list[str]:
    try:
        parsed = json.loads(row["applies_to_plan_codes_json"] or "[]")
    except Exception:
        parsed = []
    return normalize_promo_plan_codes(parsed if isinstance(parsed, list) else [])


def promo_date(value: Optional[str]) -> Optional[datetime]:
    dt = parse_dt(value)
    if dt is not None and dt.tzinfo is None:
        dt = dt.replace(tzinfo=timezone.utc)
    return dt


def promo_is_current(row, plan_code: Optional[str] = None, now: Optional[datetime] = None) -> tuple[bool, str]:
    now = now or utc_now()
    if not bool(row["is_active"]):
        return False, "inactive"
    starts_at = promo_date(row["starts_at"])
    expires_at = promo_date(row["expires_at"])
    if starts_at and starts_at > now:
        return False, "not_started"
    if expires_at and expires_at <= now:
        return False, "expired"
    max_redemptions = row["max_redemptions"]
    if max_redemptions is not None and int(row["redeemed_count"] or 0) >= int(max_redemptions):
        return False, "limit_reached"
    plan_codes = promo_plan_codes_from_row(row)
    if plan_code and plan_codes and plan_code not in plan_codes:
        return False, "plan_not_allowed"
    return True, "active"


def promo_status(row) -> dict:
    plan_codes = promo_plan_codes_from_row(row)
    is_current, reason = promo_is_current(row)
    max_redemptions = row["max_redemptions"]
    redeemed_count = int(row["redeemed_count"] or 0)
    remaining = None
    if max_redemptions is not None:
        remaining = max(0, int(max_redemptions) - redeemed_count)
    return {
        "id": int(row["id"]),
        "code": row["code"],
        "title": row["title"],
        "discountType": row["discount_type"],
        "discountValue": int(row["discount_value"]),
        "maxRedemptions": max_redemptions,
        "redeemedCount": redeemed_count,
        "remainingRedemptions": remaining,
        "startsAt": row["starts_at"],
        "expiresAt": row["expires_at"],
        "isActive": bool(row["is_active"]),
        "isCurrent": is_current,
        "statusReason": reason,
        "appliesToPlanCodes": plan_codes,
        "notes": row["notes"],
        "createdAt": row["created_at"],
        "updatedAt": row["updated_at"],
    }


def get_promo_row(code: str):
    promo_code = normalize_promo_code(code)
    if not promo_code:
        return None
    with db() as conn:
        return conn.execute(
            "SELECT * FROM promo_codes WHERE code = ?",
            (promo_code,),
        ).fetchone()


def promo_discount_rub(row, subtotal_rub: int) -> int:
    subtotal = max(0, int(subtotal_rub or 0))
    if subtotal <= 0:
        return 0
    discount_type = str(row["discount_type"] or "").strip().lower()
    discount_value = max(0, int(row["discount_value"] or 0))
    if discount_type == "percent":
        discount = round(subtotal * min(discount_value, 100) / 100)
    elif discount_type == "fixed":
        discount = discount_value
    else:
        discount = 0
    max_discount = max(0, subtotal - 1)
    return min(max_discount, max(0, int(discount)))


def apply_promo_to_quote(
    quote: dict,
    selection: dict,
    strict: bool = False,
) -> dict:
    code = normalize_promo_code(selection.get("promoCode"))
    base_total = int(quote["monthlyPriceRub"])
    quote["originalMonthlyPriceRub"] = base_total
    quote["discountRub"] = 0
    quote["promo"] = None
    if not code:
        return quote

    row = get_promo_row(code)
    if row is None:
        if strict:
            raise HTTPException(status_code=400, detail="Promo code not found.")
        quote["promo"] = {"code": code, "applied": False, "statusReason": "not_found"}
        return quote

    is_current, reason = promo_is_current(row, plan_code=quote.get("planCode"))
    if not is_current:
        if strict:
            raise HTTPException(status_code=400, detail=f"Promo code is not available: {reason}.")
        quote["promo"] = {"code": code, "applied": False, "statusReason": reason}
        return quote

    discount = promo_discount_rub(row, base_total)
    quote["discountRub"] = discount
    quote["monthlyPriceRub"] = max(1, base_total - discount)
    quote["promo"] = {
        "code": code,
        "title": row["title"],
        "discountType": row["discount_type"],
        "discountValue": int(row["discount_value"]),
        "discountRub": discount,
        "applied": discount > 0,
        "statusReason": "active",
    }
    if discount > 0:
        quote["lineItems"].append(
            {
                "code": "promo",
                "title": f"Промокод {code}",
                "priceRub": -discount,
            }
        )
    return quote


def list_promo_codes() -> list[dict]:
    with db() as conn:
        rows = conn.execute(
            """
            SELECT *
            FROM promo_codes
            ORDER BY is_active DESC, id DESC
            """
        ).fetchall()
    return [promo_status(row) for row in rows]


def promo_readiness_issue(code: str, severity: str, message: str) -> dict:
    return {
        "code": code,
        "severity": severity,
        "message": message,
    }


def build_recommended_launch_promo_payload(now: Optional[datetime] = None) -> dict:
    now = (now or utc_now()).replace(microsecond=0)
    expires_at = (now + timedelta(days=PROMO_LAUNCH_RECOMMENDED_WINDOW_DAYS)).replace(microsecond=0)
    return {
        "code": PROMO_LAUNCH_RECOMMENDED_CODE,
        "title": "Стартовая акция для первых пользователей",
        "discountType": "percent",
        "discountValue": PROMO_LAUNCH_RECOMMENDED_PERCENT,
        "maxRedemptions": PROMO_LAUNCH_RECOMMENDED_LIMIT,
        "startsAt": now.isoformat(),
        "expiresAt": expires_at.isoformat(),
        "isActive": False,
        "appliesToPlanCodes": list(PROMO_LAUNCH_RECOMMENDED_PLANS),
        "notes": "Черновик первой акции: включать только после проверки оплаты, сайта и поддержки.",
    }


def recommended_launch_promo_specs() -> list[dict]:
    payload = build_recommended_launch_promo_payload()
    return [
        {
            "code": payload["code"],
            "title": payload["title"],
            "purpose": "Первая ограниченная акция на старт продаж без поломки экономики.",
            "payload": payload,
            "activationPolicy": "Создать как неактивный черновик; включить вручную только после production-платежей и финального release gate.",
        },
        {
            "code": "FRIEND",
            "title": "Ручные приглашения",
            "purpose": "Небольшая скидка для первых знакомых/тестовой аудитории.",
            "payload": {
                "code": "FRIEND",
                "title": "Ручные приглашения",
                "discountType": "percent",
                "discountValue": 15,
                "maxRedemptions": 50,
                "startsAt": None,
                "expiresAt": None,
                "isActive": False,
                "appliesToPlanCodes": list(PROMO_LAUNCH_RECOMMENDED_PLANS),
                "notes": "Заполнить дату окончания перед включением.",
            },
            "activationPolicy": "Использовать только ограниченно и с датой окончания.",
        },
        {
            "code": "SUPPORT",
            "title": "Компенсация через поддержку",
            "purpose": "Точечная ручная скидка при проблемах, не публичная реклама.",
            "payload": {
                "code": "SUPPORT",
                "title": "Компенсация через поддержку",
                "discountType": "fixed",
                "discountValue": 100,
                "maxRedemptions": 25,
                "startsAt": None,
                "expiresAt": None,
                "isActive": False,
                "appliesToPlanCodes": ["base", "plus"],
                "notes": "Только по решению поддержки с причиной в обращении.",
            },
            "activationPolicy": "Не публиковать как общий промокод.",
        },
    ]


def promo_launch_candidate_payload(promo: dict, now: Optional[datetime] = None) -> dict:
    now = now or utc_now()
    issues = []
    if not promo.get("isActive"):
        issues.append(
            promo_readiness_issue(
                "promo_inactive",
                "low",
                "Промокод выключен и не участвует в публичной акции.",
            )
        )
    if promo.get("isActive") and not promo.get("isCurrent"):
        issues.append(
            promo_readiness_issue(
                "promo_not_current",
                "medium",
                f"Активный промокод сейчас недоступен: {promo.get('statusReason')}.",
            )
        )

    discount_type = str(promo.get("discountType") or "").strip().lower()
    discount_value = int(promo.get("discountValue") or 0)
    if discount_type == "percent" and discount_value > PROMO_LAUNCH_MAX_PUBLIC_PERCENT:
        issues.append(
            promo_readiness_issue(
                "discount_too_high",
                "medium",
                f"Публичная скидка {discount_value}% выше безопасного лимита {PROMO_LAUNCH_MAX_PUBLIC_PERCENT}%.",
            )
        )
    if discount_type == "fixed" and discount_value > PROMO_LAUNCH_MAX_FIXED_DISCOUNT_RUB:
        issues.append(
            promo_readiness_issue(
                "fixed_discount_too_high",
                "medium",
                f"Фиксированная скидка {discount_value} руб выше безопасного лимита {PROMO_LAUNCH_MAX_FIXED_DISCOUNT_RUB} руб.",
            )
        )

    if promo.get("maxRedemptions") is None:
        issues.append(
            promo_readiness_issue(
                "missing_redemption_limit",
                "medium",
                "Для публичной акции нужен лимит использований.",
            )
        )

    expires_at_raw = promo.get("expiresAt")
    expires_at = promo_date(expires_at_raw)
    if expires_at is None:
        issues.append(
            promo_readiness_issue(
                "missing_expiry",
                "medium",
                "Для публичной акции нужна дата окончания.",
            )
        )
    else:
        days_until_expiry = (expires_at - now).total_seconds() / 86400
        if days_until_expiry <= 0:
            issues.append(
                promo_readiness_issue(
                    "already_expired",
                    "medium",
                    "Дата окончания промокода уже прошла.",
                )
            )
        elif days_until_expiry > PROMO_LAUNCH_MAX_WINDOW_DAYS:
            issues.append(
                promo_readiness_issue(
                    "window_too_long",
                    "low",
                    f"Окно акции длиннее {PROMO_LAUNCH_MAX_WINDOW_DAYS} дней; лучше ограничить стартовую кампанию.",
                )
            )

    plans = promo.get("appliesToPlanCodes") or []
    if not plans:
        issues.append(
            promo_readiness_issue(
                "plan_scope_missing",
                "medium",
                "Промокод действует на все тарифы; для старта лучше ограничить тарифы явно.",
            )
        )
    if "unlimited" in plans:
        issues.append(
            promo_readiness_issue(
                "unlimited_plan_discount",
                "low",
                "Скидка затрагивает максимальный/безлимитный тариф; проверить экономику до публикации.",
            )
        )
    if not promo.get("notes"):
        issues.append(
            promo_readiness_issue(
                "notes_missing",
                "low",
                "Нет внутренней заметки о назначении акции.",
            )
        )

    blocking_issue_codes = [
        issue["code"]
        for issue in issues
        if issue.get("severity") in {"high", "medium"}
    ]
    launch_ready = bool(promo.get("isActive")) and bool(promo.get("isCurrent")) and not blocking_issue_codes
    return {
        **promo,
        "launchReady": launch_ready,
        "requiresAttention": bool(blocking_issue_codes),
        "blockingIssueCodes": blocking_issue_codes,
        "issues": issues,
    }


def billing_promo_launch_readiness_payload(limit: int = 25) -> dict:
    safe_limit = max(1, min(int(limit or 25), 100))
    now = utc_now()
    promos = list_promo_codes()
    candidates = [promo_launch_candidate_payload(promo, now=now) for promo in promos]
    launch_ready = [promo for promo in candidates if promo.get("launchReady")]
    active_risky = [
        promo for promo in candidates
        if promo.get("isActive") and promo.get("blockingIssueCodes")
    ]
    issue_counts: dict[str, int] = {}
    severity_counts = {"high": 0, "medium": 0, "low": 0}
    for candidate in candidates:
        for issue in candidate.get("issues") or []:
            code = str(issue.get("code") or "unknown")
            severity = str(issue.get("severity") or "medium")
            issue_counts[code] = issue_counts.get(code, 0) + 1
            severity_counts[severity] = severity_counts.get(severity, 0) + 1

    missing_launch_campaign = not bool(launch_ready)
    requires_attention = bool(active_risky) or missing_launch_campaign
    message = (
        "Есть безопасная ограниченная акция для старта продаж."
        if launch_ready and not active_risky
        else (
            "Перед публичным запуском нужно создать или включить ограниченную стартовую акцию."
            if missing_launch_campaign
            else "Есть активные промокоды с рисками для экономики запуска."
        )
    )
    return {
        "ok": True,
        "version": APP_VERSION,
        "generatedAt": utc_now_iso(),
        "safeToRunLaunchCampaign": bool(launch_ready) and not active_risky,
        "requiresAttention": requires_attention,
        "summary": {
            "total": len(candidates),
            "active": len([promo for promo in candidates if promo.get("isActive")]),
            "current": len([promo for promo in candidates if promo.get("isCurrent")]),
            "launchReady": len(launch_ready),
            "activeRisky": len(active_risky),
            "high": int(severity_counts.get("high") or 0),
            "medium": int(severity_counts.get("medium") or 0),
            "low": int(severity_counts.get("low") or 0),
            "recommendedCode": PROMO_LAUNCH_RECOMMENDED_CODE,
            "message": message,
        },
        "issueCounts": issue_counts,
        "launchReadyPromos": launch_ready[:safe_limit],
        "attentionPromos": active_risky[:safe_limit],
        "promos": candidates[:safe_limit],
        "recommendedCampaigns": recommended_launch_promo_specs(),
        "policy": {
            "mode": "bounded_first_month_discount",
            "recommendedDraftEndpoint": "/api/v1/admin/billing/promos/draft-start-campaign",
            "activation": "manual_only_after_payment_and_release_readiness",
            "recommendedMaxPercent": PROMO_LAUNCH_MAX_PUBLIC_PERCENT,
            "recommendedMaxFixedDiscountRub": PROMO_LAUNCH_MAX_FIXED_DISCOUNT_RUB,
            "recommendedMaxWindowDays": PROMO_LAUNCH_MAX_WINDOW_DAYS,
            "requiresRedemptionLimit": True,
            "requiresExpiry": True,
            "requiresPlanScope": True,
            "avoid": [
                "вечные скидки",
                "скидки выше 30% без причины",
                "lifetime-предложения",
                "обещания обхода блокировок в тексте акции",
            ],
        },
    }


def parse_optional_promo_dt(value: Optional[str], field: str) -> Optional[str]:
    if not value:
        return None
    parsed = parse_dt(value)
    if parsed is None:
        raise HTTPException(status_code=400, detail=f"{field} must be an ISO date/time.")
    if parsed.tzinfo is None:
        parsed = parsed.replace(tzinfo=timezone.utc)
    return parsed.isoformat()


def upsert_promo_code(payload: AdminPromoCodeIn) -> dict:
    code = normalize_promo_code(payload.code)
    if len(code) < 3:
        raise HTTPException(status_code=400, detail="Promo code must contain at least 3 characters.")
    discount_type = str(payload.discountType or "").strip().lower()
    if discount_type not in PROMO_DISCOUNT_TYPES:
        raise HTTPException(status_code=400, detail="discountType must be percent or fixed.")
    discount_value = max(1, int(payload.discountValue or 0))
    if discount_type == "percent":
        discount_value = min(discount_value, 95)
    else:
        discount_value = min(discount_value, 5000)
    max_redemptions = payload.maxRedemptions
    if max_redemptions is not None:
        max_redemptions = max(1, int(max_redemptions))
    starts_at = parse_optional_promo_dt(payload.startsAt, "startsAt")
    expires_at = parse_optional_promo_dt(payload.expiresAt, "expiresAt")
    if starts_at and expires_at and promo_date(starts_at) >= promo_date(expires_at):
        raise HTTPException(status_code=400, detail="expiresAt must be later than startsAt.")

    plan_codes = normalize_promo_plan_codes(payload.appliesToPlanCodes)
    title = clean_limited_text(payload.title, 120) or code
    notes = clean_limited_text(payload.notes, 500) or None
    now = utc_now_iso()
    plan_json = json.dumps(plan_codes, ensure_ascii=False)

    with db() as conn:
        current = conn.execute(
            "SELECT id FROM promo_codes WHERE code = ?",
            (code,),
        ).fetchone()
        if current is None:
            conn.execute(
                """
                INSERT INTO promo_codes(
                    code, title, discount_type, discount_value, max_redemptions,
                    starts_at, expires_at, is_active, applies_to_plan_codes_json,
                    notes, created_at, updated_at
                )
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                (
                    code,
                    title,
                    discount_type,
                    discount_value,
                    max_redemptions,
                    starts_at,
                    expires_at,
                    1 if payload.isActive else 0,
                    plan_json,
                    notes,
                    now,
                    now,
                ),
            )
        else:
            conn.execute(
                """
                UPDATE promo_codes
                SET title = ?, discount_type = ?, discount_value = ?,
                    max_redemptions = ?, starts_at = ?, expires_at = ?,
                    is_active = ?, applies_to_plan_codes_json = ?,
                    notes = ?, updated_at = ?
                WHERE code = ?
                """,
                (
                    title,
                    discount_type,
                    discount_value,
                    max_redemptions,
                    starts_at,
                    expires_at,
                    1 if payload.isActive else 0,
                    plan_json,
                    notes,
                    now,
                    code,
                ),
            )
        conn.commit()
        row = conn.execute(
            "SELECT * FROM promo_codes WHERE code = ?",
            (code,),
        ).fetchone()

    return promo_status(row)


def set_promo_code_active(code: str, is_active: bool) -> dict:
    promo_code = normalize_promo_code(code)
    if not promo_code:
        raise HTTPException(status_code=400, detail="Promo code is empty.")
    with db() as conn:
        conn.execute(
            """
            UPDATE promo_codes
            SET is_active = ?, updated_at = ?
            WHERE code = ?
            """,
            (1 if is_active else 0, utc_now_iso(), promo_code),
        )
        conn.commit()
        row = conn.execute(
            "SELECT * FROM promo_codes WHERE code = ?",
            (promo_code,),
        ).fetchone()
    if row is None:
        raise HTTPException(status_code=404, detail="Promo code not found.")
    return promo_status(row)


def create_launch_promo_draft() -> dict:
    payload = build_recommended_launch_promo_payload()
    existing = get_promo_row(payload["code"])
    if existing is not None and bool(existing["is_active"]):
        raise HTTPException(
            status_code=409,
            detail="START20 already exists and is active. Deactivate or edit it manually before creating a new launch draft.",
        )
    promo = upsert_promo_code(AdminPromoCodeIn(**payload))
    return promo


def record_promo_redemption(order_row, order_status: dict) -> None:
    promo = order_status.get("quote", {}).get("promo") if isinstance(order_status.get("quote"), dict) else None
    if not isinstance(promo, dict) or not promo.get("applied"):
        return
    code = normalize_promo_code(promo.get("code"))
    discount = max(0, int(promo.get("discountRub") or order_status.get("discountRub") or 0))
    if not code or discount <= 0:
        return
    with db() as conn:
        row = conn.execute(
            "SELECT * FROM promo_codes WHERE code = ?",
            (code,),
        ).fetchone()
        if row is None:
            return
        existing = conn.execute(
            "SELECT id FROM promo_redemptions WHERE order_public_id = ?",
            (order_row["public_id"],),
        ).fetchone()
        if existing is not None:
            return
        conn.execute(
            """
            INSERT INTO promo_redemptions(
                promo_code_id, code, user_id, order_public_id, discount_rub, created_at
            )
            VALUES (?, ?, ?, ?, ?, ?)
            """,
            (
                row["id"],
                code,
                int(order_row["user_id"]),
                order_row["public_id"],
                discount,
                utc_now_iso(),
            ),
        )
        conn.execute(
            """
            UPDATE promo_codes
            SET redeemed_count = redeemed_count + 1, updated_at = ?
            WHERE id = ?
            """,
            (utc_now_iso(), row["id"]),
        )
        conn.commit()


def _interpolate_price(gb: int) -> int:
    value = max(1, min(500, int(gb)))
    if value <= TRAFFIC_GB_POINTS[0][0]:
        return TRAFFIC_GB_POINTS[0][1]

    for index in range(len(TRAFFIC_GB_POINTS) - 1):
        a_gb, a_price = TRAFFIC_GB_POINTS[index]
        b_gb, b_price = TRAFFIC_GB_POINTS[index + 1]
        if value <= b_gb:
            ratio = (value - a_gb) / float(b_gb - a_gb)
            return round(a_price + (b_price - a_price) * ratio)

    return TRAFFIC_GB_POINTS[-1][1]


def _apps_price(count: int) -> int:
    if count <= 0:
        return 0
    if count == 1:
        return 15
    if count == 2:
        return 25
    if count == 3:
        return 35
    if count == 4:
        return 45
    if count == 5:
        return 55
    return 65


def normalize_tariff_selection(payload: TariffSelectionIn) -> dict:
    traffic_pack = payload.trafficPack.strip().lower()
    if traffic_pack not in TRAFFIC_PACK_BASE:
        traffic_pack = "gb20"

    traffic_gb = max(1, min(500, int(payload.trafficGb or 20)))
    devices = max(1, min(5, int(payload.devices or 1)))

    apps = []
    seen = set()
    for raw in payload.unlimitedApps:
        code = str(raw).strip().lower()
        if code and code in UNLIMITED_APP_CODES and code not in seen:
            apps.append(code)
            seen.add(code)

    dedicated_ip = bool(payload.dedicatedIp)
    auto_renew = bool(payload.autoRenew)
    promo_code = normalize_promo_code(payload.promoCode)

    return {
        "trafficPack": traffic_pack,
        "trafficGb": traffic_gb,
        "devices": devices,
        "unlimitedApps": apps,
        "dedicatedIp": dedicated_ip,
        "autoRenew": auto_renew,
        "promoCode": promo_code,
        "includedFeatures": INCLUDED_FEATURES,
    }


def quote_tariff(selection: dict, strict_promo: bool = False) -> dict:
    traffic_pack = selection["trafficPack"]
    traffic_gb = int(selection["trafficGb"])
    devices = int(selection["devices"])
    apps = list(selection["unlimitedApps"])
    dedicated_ip = bool(selection["dedicatedIp"])

    if traffic_pack == "unlimited":
        traffic_title = "Безлимит"
        traffic_price = int(TRAFFIC_PACK_BASE["unlimited"]["priceRub"])
    else:
        traffic_title = f"{traffic_gb} ГБ"
        traffic_price = _interpolate_price(traffic_gb)

    apps_price = 0 if traffic_pack == "unlimited" else _apps_price(len(apps))
    devices_price = max(0, devices - 1) * ADDITIONAL_DEVICE_RUB
    dedicated_ip_price = DEDICATED_IP_RUB if dedicated_ip else 0
    total = traffic_price + apps_price + devices_price + dedicated_ip_price

    if traffic_pack == "unlimited":
        plan_code = "unlimited"
        plan_name = "Безлимит"
    elif dedicated_ip or devices >= 3 or traffic_gb >= 100 or len(apps) >= 4:
        plan_code = "plus"
        plan_name = "Plus"
    elif traffic_gb <= 5 and len(apps) == 0 and devices == 1:
        plan_code = "starter"
        plan_name = "Старт"
    else:
        plan_code = "base"
        plan_name = "Base"

    quote = {
        "planCode": plan_code,
        "planName": plan_name,
        "trafficPack": traffic_pack,
        "trafficGb": traffic_gb,
        "devices": devices,
        "unlimitedApps": apps,
        "dedicatedIp": dedicated_ip,
        "autoRenew": bool(selection.get("autoRenew", True)),
        "includedFeatures": INCLUDED_FEATURES,
        "lineItems": [
            {"code": "traffic", "title": "Трафик", "priceRub": traffic_price},
            {
                "code": "apps",
                "title": "Безлимитные приложения",
                "priceRub": apps_price,
            },
            {
                "code": "devices",
                "title": "Доп. устройства",
                "priceRub": devices_price,
            },
            {
                "code": "dedicated_ip",
                "title": "Выделенный IP",
                "priceRub": dedicated_ip_price,
            },
        ],
        "monthlyPriceRub": total,
        "summary": {
            "trafficTitle": traffic_title,
            "appsCount": len(apps),
            "appsIncluded": traffic_pack == "unlimited",
        },
    }
    return apply_promo_to_quote(quote, selection, strict=strict_promo)


def require_active_subscription(user_id: int) -> dict:
    sub = subscription_status(get_subscription_row(user_id))
    if not ENFORCE_SUBSCRIPTION_ACCESS:
        return sub
    if not sub["isActive"]:
        raise HTTPException(
            status_code=403,
            detail="Subscription inactive.",
        )
    return sub


def hash_password(password: str, salt: Optional[str] = None) -> str:
    salt = salt or secrets.token_hex(16)
    dk = hashlib.pbkdf2_hmac(
        "sha256",
        password.encode("utf-8"),
        salt.encode("utf-8"),
        120_000,
    )
    return f"{salt}${base64.b64encode(dk).decode('ascii')}"


def verify_password(password: str, password_hash: str) -> bool:
    try:
        salt, expected = password_hash.split("$", 1)
    except ValueError:
        return False

    actual = hash_password(password, salt).split("$", 1)[1]
    return hmac.compare_digest(actual, expected)


def issue_token(user_id: int) -> str:
    token = secrets.token_urlsafe(32)
    with db() as conn:
        conn.execute(
            "INSERT INTO tokens(token, user_id, created_at) VALUES (?, ?, ?)",
            (token, user_id, utc_now_iso()),
        )
        conn.commit()
    return token


def get_user_by_token(authorization: Optional[str]):
    if not authorization or not authorization.startswith("Bearer "):
        raise HTTPException(status_code=401, detail="Missing bearer token.")

    token = authorization.split(" ", 1)[1].strip()
    if not token:
        raise HTTPException(status_code=401, detail="Empty bearer token.")

    with db() as conn:
        row = conn.execute(
            """
            SELECT
                u.id,
                u.email,
                u.email_verified,
                u.email_verified_at,
                u.phone,
                u.phone_verified,
                u.phone_verified_at
            FROM tokens t
            JOIN users u ON u.id = t.user_id
            WHERE t.token = ?
            """,
            (token,),
        ).fetchone()

    if row is None:
        raise HTTPException(status_code=401, detail="Invalid token.")

    return row


def user_email_verified(user) -> bool:
    try:
        return bool(user["email_verified"])
    except Exception:
        return False


def user_phone_verified(user) -> bool:
    try:
        return bool(user["phone_verified"])
    except Exception:
        return False


def auth_session_payload(user, access_token: str) -> dict:
    return {
        "accessToken": access_token,
        "email": user["email"],
        "emailVerified": user_email_verified(user),
        "emailConfirmationRequired": EMAIL_CONFIRMATION_REQUIRED,
        "phone": user["phone"] if "phone" in user.keys() else None,
        "phoneVerified": user_phone_verified(user),
    }


def email_sender_configured() -> bool:
    return bool(SMTP_HOST and SMTP_FROM)


def email_effective_public_base_url() -> str:
    return EMAIL_PUBLIC_BASE_URL or PUBLIC_API_BASE_URL


def email_confirmation_readiness() -> dict:
    public_base = email_effective_public_base_url()
    public_host = _url_host(public_base)
    checks = [
        {
            "code": "public_base_url",
            "ok": _is_https_url(public_base)
            and public_host not in {"bluevpn.local", "localhost", "127.0.0.1"},
            "message": "Set GREENVPN_EMAIL_PUBLIC_BASE_URL or GREENVPN_PUBLIC_BASE_URL to a real HTTPS origin.",
            "value": public_base,
        },
        {
            "code": "smtp_host",
            "ok": bool(SMTP_HOST),
            "message": "Set GREENVPN_SMTP_HOST.",
        },
        {
            "code": "smtp_from",
            "ok": bool(SMTP_FROM),
            "message": "Set GREENVPN_SMTP_FROM.",
        },
        {
            "code": "smtp_password",
            "ok": not SMTP_USERNAME or bool(SMTP_PASSWORD),
            "message": "Set GREENVPN_SMTP_PASSWORD when GREENVPN_SMTP_USERNAME is used.",
        },
    ]
    production_ready = all(check["ok"] for check in checks)
    return {
        "ok": True,
        "provider": "smtp" if email_sender_configured() else "manual_mvp",
        "required": EMAIL_CONFIRMATION_REQUIRED,
        "productionReady": production_ready,
        "publicBaseUrl": public_base,
        "ttlHours": EMAIL_CONFIRMATION_TTL_HOURS,
        "checks": checks,
        "requiredActions": [
            check["message"] for check in checks if not check["ok"]
        ],
    }


def email_confirmation_token_hash(token: str) -> str:
    return hashlib.sha256(token.encode("utf-8")).hexdigest()


def build_email_confirmation_link(token: str) -> str:
    return (
        f"{email_effective_public_base_url()}/api/v1/auth/email/verify"
        f"?token={urllib.parse.quote(token)}"
    )


def create_email_confirmation(user_id: int, email: str) -> str:
    token = secrets.token_urlsafe(36)
    now = utc_now()
    expires_at = now + timedelta(hours=EMAIL_CONFIRMATION_TTL_HOURS)
    with db() as conn:
        conn.execute(
            """
            UPDATE email_confirmations
            SET status = ?, consumed_at = COALESCE(consumed_at, ?)
            WHERE user_id = ? AND status = ?
            """,
            ("superseded", now.isoformat(), user_id, "pending"),
        )
        conn.execute(
            """
            INSERT INTO email_confirmations(
                user_id, email, token_hash, status, created_at, expires_at
            )
            VALUES (?, ?, ?, ?, ?, ?)
            """,
            (
                user_id,
                email,
                email_confirmation_token_hash(token),
                "pending",
                now.isoformat(),
                expires_at.isoformat(),
            ),
        )
        conn.commit()
    return token


def queue_email_outbox(
    user_id: int,
    email: str,
    subject: str,
    body: str,
    status: str,
    error: Optional[str] = None,
) -> int:
    with db() as conn:
        cursor = conn.execute(
            """
            INSERT INTO email_outbox(
                user_id, email, subject, body, status, error, created_at
            )
            VALUES (?, ?, ?, ?, ?, ?, ?)
            """,
            (user_id, email, subject, body, status, error, utc_now_iso()),
        )
        conn.commit()
        return int(cursor.lastrowid)


def update_email_outbox_status(
    outbox_id: int,
    status: str,
    error: Optional[str] = None,
) -> None:
    with db() as conn:
        conn.execute(
            """
            UPDATE email_outbox
            SET status = ?, error = ?, sent_at = CASE WHEN ? = 'sent' THEN ? ELSE sent_at END
            WHERE id = ?
            """,
            (status, error, status, utc_now_iso(), outbox_id),
        )
        conn.commit()


def send_smtp_email(to_email: str, subject: str, body: str) -> None:
    msg = EmailMessage()
    msg["Subject"] = subject
    msg["From"] = SMTP_FROM
    msg["To"] = to_email
    msg.set_content(body)

    if SMTP_PORT == 465:
        with smtplib.SMTP_SSL(SMTP_HOST, SMTP_PORT, timeout=20) as smtp:
            if SMTP_USERNAME:
                smtp.login(SMTP_USERNAME, SMTP_PASSWORD)
            smtp.send_message(msg)
        return

    with smtplib.SMTP(SMTP_HOST, SMTP_PORT, timeout=20) as smtp:
        if SMTP_USE_TLS:
            smtp.starttls()
        if SMTP_USERNAME:
            smtp.login(SMTP_USERNAME, SMTP_PASSWORD)
        smtp.send_message(msg)


def send_or_queue_email_confirmation(user_id: int, email: str, token: str) -> dict:
    link = build_email_confirmation_link(token)
    subject = "Подтверждение почты Green VPN"
    body = (
        "Привет!\n\n"
        "Чтобы подтвердить почту в Green VPN, открой ссылку:\n"
        f"{link}\n\n"
        f"Ссылка действует {EMAIL_CONFIRMATION_TTL_HOURS} часов. "
        "Если ты не создавал аккаунт Green VPN, просто игнорируй это письмо.\n"
    )
    outbox_id = queue_email_outbox(
        user_id,
        email,
        subject,
        body,
        "queued" if email_sender_configured() else "not_configured",
    )

    if not email_sender_configured():
        return {
            "deliveryStatus": "not_configured",
            "outboxId": outbox_id,
        }

    try:
        send_smtp_email(email, subject, body)
        update_email_outbox_status(outbox_id, "sent")
        with db() as conn:
            conn.execute(
                """
                UPDATE email_confirmations
                SET sent_at = ?
                WHERE token_hash = ?
                """,
                (utc_now_iso(), email_confirmation_token_hash(token)),
            )
            conn.commit()
        return {
            "deliveryStatus": "sent",
            "outboxId": outbox_id,
        }
    except Exception as exc:
        update_email_outbox_status(outbox_id, "failed", str(exc))
        return {
            "deliveryStatus": "failed",
            "outboxId": outbox_id,
        }


def latest_email_confirmation_status(user_id: int) -> Optional[dict]:
    with db() as conn:
        row = conn.execute(
            """
            SELECT status, created_at, expires_at, sent_at, consumed_at
            FROM email_confirmations
            WHERE user_id = ?
            ORDER BY id DESC
            LIMIT 1
            """,
            (user_id,),
        ).fetchone()

    if row is None:
        return None
    return {
        "status": row["status"],
        "createdAt": row["created_at"],
        "expiresAt": row["expires_at"],
        "sentAt": row["sent_at"],
        "consumedAt": row["consumed_at"],
    }


def consume_email_confirmation_token(token: str) -> dict:
    token = token.strip()
    if len(token) < 20:
        return {"ok": False, "status": "invalid"}

    now = utc_now()
    token_hash = email_confirmation_token_hash(token)
    with db() as conn:
        row = conn.execute(
            """
            SELECT *
            FROM email_confirmations
            WHERE token_hash = ?
            """,
            (token_hash,),
        ).fetchone()

        if row is None:
            return {"ok": False, "status": "invalid"}

        if row["status"] != "pending":
            return {"ok": row["status"] == "consumed", "status": row["status"]}

        expires_at = parse_dt(row["expires_at"])
        if expires_at is not None and now >= expires_at:
            conn.execute(
                """
                UPDATE email_confirmations
                SET status = ?, consumed_at = ?
                WHERE id = ?
                """,
                ("expired", now.isoformat(), row["id"]),
            )
            conn.commit()
            return {"ok": False, "status": "expired"}

        conn.execute(
            """
            UPDATE email_confirmations
            SET status = ?, consumed_at = ?
            WHERE id = ?
            """,
            ("consumed", now.isoformat(), row["id"]),
        )
        conn.execute(
            """
            UPDATE users
            SET email_verified = 1, email_verified_at = ?
            WHERE id = ?
            """,
            (now.isoformat(), row["user_id"]),
        )
        conn.commit()

    return {"ok": True, "status": "verified"}


def normalize_phone(phone: str) -> str:
    raw = (phone or "").strip()
    digits = re.sub(r"\D+", "", raw)
    if not digits:
        raise HTTPException(status_code=400, detail="Invalid phone.")

    if digits.startswith("8") and len(digits) == 11:
        digits = "7" + digits[1:]
    elif len(digits) == 10 and digits.startswith("9"):
        digits = "7" + digits

    if len(digits) < 10 or len(digits) > 15:
        raise HTTPException(status_code=400, detail="Invalid phone.")

    return f"+{digits}"


def clean_limited_text(value: Optional[str], limit: int) -> str:
    if not value:
        return ""
    clean = re.sub(r"[\x00-\x08\x0b\x0c\x0e-\x1f]+", " ", str(value)).strip()
    return clean[:limit]


def normalize_email(email: str) -> str:
    value = (email or "").strip().lower()
    if not value or len(value) > 254:
        raise HTTPException(status_code=400, detail="Invalid email.")
    if not re.fullmatch(r"[^@\s]+@[^@\s]+\.[^@\s]+", value):
        raise HTTPException(status_code=400, detail="Invalid email.")
    return value


def validate_support_report_code(report: str) -> str:
    value = (report or "").strip()
    if len(value) < 24 or len(value) > 250_000:
        raise HTTPException(status_code=400, detail="Invalid support report.")
    if not re.fullmatch(r"GVPN1\.[A-Za-z0-9_\-=]+", value):
        raise HTTPException(status_code=400, detail="Invalid support report.")
    return value


SENSITIVE_REPORT_KEYS = {
    "accessToken",
    "adminToken",
    "authorization",
    "clientPrivateKey",
    "config",
    "password",
    "privateKey",
    "presharedKey",
    "secret",
    "token",
}


SENSITIVE_TELEMETRY_KEY_PARTS = {
    "accesstoken",
    "admintoken",
    "apikey",
    "authorization",
    "bearer",
    "clientprivatekey",
    "configtext",
    "cookie",
    "devicetoken",
    "fullconfig",
    "password",
    "privateconfig",
    "privatekey",
    "presharedkey",
    "rawconfig",
    "secret",
    "serverprivatekey",
    "sessiontoken",
    "setcookie",
    "smtppassword",
    "smstoken",
    "token",
    "wgprivatekey",
    "wireguardconfig",
    "wireguardprivatekey",
    "yookassasecret",
}
SENSITIVE_TELEMETRY_VALUE_PATTERNS = [
    re.compile(r"(?i)\b(private\s*key|privatekey|preshared\s*key|presharedkey)\s*="),
    re.compile(r"(?i)\b(authorization|x-admin-token|password|secret|token)\b\s*[:=]"),
    re.compile(r"(?i)\bbearer\s+[A-Za-z0-9._~+/=-]{10,}"),
    re.compile(r"(?is)\[interface\].{0,600}\bprivate\s*key\b"),
]


def redact_support_report_value(value, depth: int = 0):
    if depth > 8:
        return "<truncated>"
    if isinstance(value, dict):
        out = {}
        for key, item in list(value.items())[:120]:
            safe_key = clean_limited_text(str(key), 120)
            if str(key) in SENSITIVE_REPORT_KEYS or is_sensitive_telemetry_key(safe_key):
                out[safe_key] = "<redacted>"
            else:
                out[safe_key] = redact_support_report_value(item, depth + 1)
        return out
    if isinstance(value, list):
        return [redact_support_report_value(item, depth + 1) for item in value[:100]]
    if isinstance(value, str):
        clean = clean_limited_text(value, 2000)
        if any(pattern.search(clean) for pattern in SENSITIVE_TELEMETRY_VALUE_PATTERNS):
            return "<redacted>"
        return clean
    if isinstance(value, (bool, int, float)) or value is None:
        return value
    return value


def normalized_sensitive_key(value: object) -> str:
    return re.sub(r"[^a-z0-9]+", "", str(value or "").lower())


def is_sensitive_telemetry_key(key: object) -> bool:
    normalized = normalized_sensitive_key(key)
    if not normalized:
        return False
    return any(part in normalized for part in SENSITIVE_TELEMETRY_KEY_PARTS)


def sanitize_monitoring_details_value(value, depth: int = 0):
    if depth > 8:
        return "<truncated>"
    if isinstance(value, dict):
        out = {}
        for key, item in list(value.items())[:120]:
            safe_key = clean_limited_text(str(key), 120)
            if is_sensitive_telemetry_key(safe_key):
                out[safe_key] = "<redacted>"
            else:
                out[safe_key] = sanitize_monitoring_details_value(item, depth + 1)
        return out
    if isinstance(value, list):
        return [sanitize_monitoring_details_value(item, depth + 1) for item in value[:120]]
    if isinstance(value, str):
        clean = clean_limited_text(value, 2000)
        if any(pattern.search(clean) for pattern in SENSITIVE_TELEMETRY_VALUE_PATTERNS):
            return "<redacted>"
        return clean
    if isinstance(value, (bool, int, float)) or value is None:
        return value
    return clean_limited_text(str(value), 500)


def sanitize_monitoring_details(details: Optional[dict]) -> dict:
    if not isinstance(details, dict):
        return {}
    sanitized = sanitize_monitoring_details_value(details)
    return sanitized if isinstance(sanitized, dict) else {}


def decode_support_report_code(report: str) -> dict:
    code = validate_support_report_code(report)
    encoded = code.split(".", 1)[1]
    encoded += "=" * ((4 - len(encoded) % 4) % 4)
    try:
        packed = base64.urlsafe_b64decode(encoded.encode("ascii"))
        raw = gzip.decompress(packed).decode("utf-8")
        decoded = json.loads(raw)
    except Exception as exc:
        raise HTTPException(status_code=400, detail="Support report decode failed.") from exc
    if not isinstance(decoded, dict):
        raise HTTPException(status_code=400, detail="Support report payload is invalid.")
    return redact_support_report_value(decoded)


def support_workflow_options() -> dict:
    return {
        "statuses": SUPPORT_STATUSES,
        "priorities": [
            {
                "code": code,
                "title": meta["title"],
                "slaHours": meta["slaHours"],
            }
            for code, meta in SUPPORT_PRIORITIES.items()
        ],
        "categories": [
            {
                "code": code,
                "title": meta["title"],
            }
            for code, meta in SUPPORT_CATEGORIES.items()
        ],
    }


def normalize_support_priority(value: Optional[str], fallback: str = "normal") -> str:
    priority = clean_limited_text(value, 40).strip().lower()
    return priority if priority in SUPPORT_PRIORITIES else fallback


def normalize_support_category(value: Optional[str], fallback: str = "general") -> str:
    category = clean_limited_text(value, 80).strip().lower()
    return category if category in SUPPORT_CATEGORIES else fallback


def support_sla_due_at(priority: str, created_at: Optional[str] = None) -> str:
    start = utc_now()
    if created_at:
        try:
            parsed = datetime.fromisoformat(created_at.replace("Z", "+00:00"))
            start = parsed if parsed.tzinfo else parsed.replace(tzinfo=timezone.utc)
        except Exception:
            start = utc_now()
    hours = SUPPORT_PRIORITIES.get(priority, SUPPORT_PRIORITIES["normal"])["slaHours"]
    return (start + timedelta(hours=hours)).isoformat()


def infer_support_report_workflow(summary: str, report_code: str) -> dict:
    text_parts = [summary or ""]
    try:
        decoded = decode_support_report_code(report_code)
        text_parts.append(json.dumps(decoded, ensure_ascii=False, sort_keys=True))
    except Exception:
        text_parts.append("")
    text = "\n".join(text_parts).lower()

    category = "general"
    matched_keyword = ""
    for code, meta in SUPPORT_CATEGORIES.items():
        if code == "general":
            continue
        for keyword in meta["keywords"]:
            if keyword.lower() in text:
                category = code
                matched_keyword = keyword
                break
        if category != "general":
            break

    priority = "normal"
    if any(
        keyword in text
        for keyword in [
            "нет интернета",
            "internet down",
            "no internet",
            "winsock",
            "маршрут",
            "route broken",
            "service not running",
            "vpn did not start",
            "handshake=нет",
            "handshake no",
        ]
    ):
        priority = "urgent"
    elif category in {"vpn_connect", "payment", "auth", "network"}:
        priority = "high"
    elif category == "app_ui":
        priority = "low"

    reason = "Автотриаж: "
    if category == "general":
        reason += "явных признаков категории не найдено."
    else:
        reason += f"категория {category} по признаку `{matched_keyword}`."
    reason += f" Приоритет {priority}."
    return {
        "category": category,
        "priority": priority,
        "triageReason": reason,
        "slaDueAt": support_sla_due_at(priority),
    }


def request_ip_and_agent(request: Request) -> tuple[str, str]:
    request_ip = request.client.host if request.client else ""
    user_agent = clean_limited_text(request.headers.get("user-agent"), 300)
    return request_ip, user_agent


def log_auth_event(
    event_type: str,
    status: str,
    *,
    request: Optional[Request] = None,
    user_id: Optional[int] = None,
    email: Optional[str] = None,
    phone: Optional[str] = None,
    details: Optional[dict] = None,
) -> None:
    request_ip = ""
    user_agent = ""
    if request is not None:
        request_ip, user_agent = request_ip_and_agent(request)
    try:
        details_json = json.dumps(details or {}, ensure_ascii=False)
    except Exception:
        details_json = "{}"
    with db() as conn:
        conn.execute(
            """
            INSERT INTO auth_events(
                user_id, email, phone, event_type, status,
                request_ip, user_agent, details_json, created_at
            )
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            (
                user_id,
                email,
                phone,
                event_type,
                status,
                request_ip,
                user_agent,
                details_json,
                utc_now_iso(),
            ),
        )
        conn.commit()


def one_time_code_hash(kind: str, target: str, code: str) -> str:
    material = f"{AUTH_CODE_PEPPER}:{kind}:{target}:{code}".encode("utf-8")
    return hashlib.sha256(material).hexdigest()


def auth_code_readiness() -> dict:
    checks = [
        {
            "code": "auth_code_pepper",
            "ok": len(AUTH_CODE_PEPPER) >= 24
            and AUTH_CODE_PEPPER != "greenvpn-dev-auth-code-pepper-not-for-production",
            "message": "Set GREENVPN_AUTH_CODE_PEPPER to a long random secret before production.",
        },
        {
            "code": "email_delivery",
            "ok": email_sender_configured(),
            "message": "Configure SMTP to deliver email login codes.",
        },
        {
            "code": "sms_delivery",
            "ok": sms_sender_configured(),
            "message": "Configure SMS provider to deliver phone login codes.",
        },
    ]
    return {
        "ok": True,
        "ttlMinutes": AUTH_CODE_TTL_MINUTES,
        "resendCooldownSeconds": AUTH_CODE_RESEND_COOLDOWN_SECONDS,
        "maxVerifyAttempts": AUTH_CODE_MAX_VERIFY_ATTEMPTS,
        "lockoutMinutes": AUTH_CODE_LOCKOUT_MINUTES,
        "devCodesEnabled": DEV_AUTH_CODES,
        "productionReady": all(check["ok"] for check in checks),
        "checks": checks,
        "requiredActions": [
            check["message"] for check in checks if not check["ok"]
        ],
    }


def user_auth_flow_readiness(limit: int = 10) -> dict:
    safe_limit = max(1, min(int(limit or 10), 50))
    email = email_confirmation_readiness()
    sms = sms_confirmation_readiness()
    auth_codes = auth_code_readiness()
    phone_available = bool(sms_sender_configured() or DEV_AUTH_CODES)
    email_available = bool(email_sender_configured() or DEV_AUTH_CODES)
    code_policy_ok = (
        3 <= int(AUTH_CODE_TTL_MINUTES or 0) <= 30
        and 30 <= int(AUTH_CODE_RESEND_COOLDOWN_SECONDS or 0) <= 600
        and 3 <= int(AUTH_CODE_MAX_VERIFY_ATTEMPTS or 0) <= 10
        and 5 <= int(AUTH_CODE_LOCKOUT_MINUTES or 0) <= 60
    )
    auth_pepper_ok = any(
        check.get("code") == "auth_code_pepper" and check.get("ok")
        for check in auth_codes.get("checks") or []
    )
    since = (utc_now() - timedelta(hours=24)).isoformat()
    with db() as conn:
        user_counts = conn.execute(
            """
            SELECT
                COUNT(*) AS total,
                SUM(CASE WHEN email_verified = 1 THEN 1 ELSE 0 END) AS email_verified,
                SUM(CASE WHEN phone_verified = 1 THEN 1 ELSE 0 END) AS phone_verified,
                SUM(CASE WHEN phone IS NOT NULL AND phone <> '' THEN 1 ELSE 0 END) AS with_phone,
                SUM(CASE WHEN email LIKE 'phone_%@phone.greenvpn.local' THEN 1 ELSE 0 END) AS phone_only
            FROM users
            """
        ).fetchone()
        event_rows = conn.execute(
            """
            SELECT event_type, status, COUNT(*) AS count
            FROM auth_events
            WHERE created_at >= ?
            GROUP BY event_type, status
            ORDER BY event_type, status
            """,
            (since,),
        ).fetchall()
        recent_problem_rows = conn.execute(
            """
            SELECT id, event_type, status, created_at
            FROM auth_events
            WHERE status NOT IN ('created', 'verified')
            ORDER BY id DESC
            LIMIT ?
            """,
            (safe_limit,),
        ).fetchall()

    event_counts: dict[str, dict[str, int]] = {}
    totals_by_status: dict[str, int] = {}
    for row in event_rows:
        event_type = str(row["event_type"] or "")
        status = str(row["status"] or "")
        count = int(row["count"] or 0)
        event_counts.setdefault(event_type, {})[status] = count
        totals_by_status[status] = totals_by_status.get(status, 0) + count
    starts_24h = sum(
        count
        for event_type, statuses in event_counts.items()
        if event_type.endswith("_start")
        for count in statuses.values()
    )
    verified_24h = int(totals_by_status.get("verified") or 0)
    problem_24h = sum(
        count
        for status, count in totals_by_status.items()
        if status not in {"created", "verified"}
    )

    checks = [
        {
            "code": "primary_phone_code",
            "title": "Primary auth method",
            "ok": True,
            "message": "Windows bootstrap exposes phone_code as the primary login/register method.",
        },
        {
            "code": "phone_code_delivery",
            "title": "Phone-code delivery",
            "ok": phone_available,
            "message": (
                "SMS login codes can be delivered."
                if phone_available
                else "Configure SMS.ru or keep the app on email fallback until SMS is ready."
            ),
        },
        {
            "code": "email_code_fallback",
            "title": "Email-code fallback",
            "ok": email_available,
            "message": (
                "Email login code fallback can be delivered."
                if email_available
                else "Configure SMTP so users have a non-SMS fallback."
            ),
        },
        {
            "code": "code_policy",
            "title": "Code TTL/rate-limit policy",
            "ok": code_policy_ok,
            "message": "One-time code TTL, resend cooldown, attempts and lockout are within safe production bounds.",
            "value": {
                "ttlMinutes": AUTH_CODE_TTL_MINUTES,
                "resendCooldownSeconds": AUTH_CODE_RESEND_COOLDOWN_SECONDS,
                "maxVerifyAttempts": AUTH_CODE_MAX_VERIFY_ATTEMPTS,
                "lockoutMinutes": AUTH_CODE_LOCKOUT_MINUTES,
            },
        },
        {
            "code": "auth_code_pepper",
            "title": "Code hash pepper",
            "ok": auth_pepper_ok,
            "message": "GREENVPN_AUTH_CODE_PEPPER is set to a non-default random secret.",
        },
        {
            "code": "dev_codes_disabled",
            "title": "Development code exposure",
            "ok": not DEV_AUTH_CODES,
            "message": (
                "DEV_AUTH_CODES is disabled; one-time codes are not returned by public auth endpoints."
                if not DEV_AUTH_CODES
                else "Disable GREENVPN_DEV_AUTH_CODES before any public launch."
            ),
        },
        {
            "code": "legacy_password_not_primary",
            "title": "Legacy password path",
            "ok": True,
            "message": "Email/password remains available only as a legacy path; code-first auth is the public contract.",
        },
    ]
    missing = [check for check in checks if not check["ok"]]
    production_ready = not missing
    return {
        "ok": True,
        "version": APP_VERSION,
        "generatedAt": utc_now_iso(),
        "productionReady": production_ready,
        "publicAuthReady": phone_available and code_policy_ok and auth_pepper_ok and not DEV_AUTH_CODES,
        "primaryMethod": "phone_code",
        "fallbackMethod": "email_code",
        "checks": checks,
        "requiredActions": [check["message"] for check in missing],
        "summary": {
            "green": len(checks) - len(missing),
            "yellow": len(missing),
            "red": 0,
            "state": "green" if production_ready else "yellow",
            "message": (
                "Code-first login/register flow is ready."
                if production_ready
                else "Code-first login/register flow is implemented, but delivery/configuration still needs attention."
            ),
            "usersTotal": int(user_counts["total"] or 0),
            "emailVerifiedUsers": int(user_counts["email_verified"] or 0),
            "phoneVerifiedUsers": int(user_counts["phone_verified"] or 0),
            "usersWithPhone": int(user_counts["with_phone"] or 0),
            "phoneOnlyUsers": int(user_counts["phone_only"] or 0),
            "starts24h": starts_24h,
            "verified24h": verified_24h,
            "problem24h": problem_24h,
        },
        "methods": [
            {
                "code": "phone_code",
                "challengeMethod": "phone_sms",
                "primary": True,
                "available": phone_available,
                "deliveryReady": sms_sender_configured(),
                "productionReady": bool(sms.get("productionReady")),
                "provider": sms.get("provider"),
            },
            {
                "code": "email_code",
                "challengeMethod": "email_code",
                "primary": False,
                "available": email_available,
                "deliveryReady": email_sender_configured(),
                "productionReady": bool(email.get("productionReady")),
                "provider": email.get("provider"),
            },
            {
                "code": "email_password",
                "primary": False,
                "legacy": True,
                "available": True,
                "productionReady": True,
            },
        ],
        "bootstrapContract": {
            "publicEndpoint": "/api/v1/bootstrap/windows",
            "primaryMethod": "phone_code",
            "challengeStart": "/api/v1/auth/challenge/start",
            "challengeVerify": "/api/v1/auth/challenge/verify",
            "phoneStart": "/api/v1/auth/phone/login/start",
            "phoneVerify": "/api/v1/auth/phone/login/verify",
            "emailStart": "/api/v1/auth/email/code/start",
            "emailVerify": "/api/v1/auth/email/code/verify",
            "legacyPasswordEndpoints": ["/api/v1/auth/register", "/api/v1/auth/login"],
        },
        "codePolicy": {
            "ttlMinutes": AUTH_CODE_TTL_MINUTES,
            "resendCooldownSeconds": AUTH_CODE_RESEND_COOLDOWN_SECONDS,
            "maxVerifyAttempts": AUTH_CODE_MAX_VERIFY_ATTEMPTS,
            "lockoutMinutes": AUTH_CODE_LOCKOUT_MINUTES,
            "devCodesEnabled": DEV_AUTH_CODES,
        },
        "recentEvents24h": {
            "since": since,
            "byEventType": event_counts,
            "totalsByStatus": totals_by_status,
        },
        "recentProblemEvents": [
            {
                "id": int(row["id"]),
                "eventType": row["event_type"],
                "status": row["status"],
                "createdAt": row["created_at"],
            }
            for row in recent_problem_rows
        ],
        "policy": {
            "mode": "readiness_only_no_codes_sent",
            "secretExposure": "No one-time codes, tokens, password hashes, provider keys or private keys are returned.",
            "publicContract": "Phone code is primary; email code is fallback; email/password is legacy only.",
        },
        "emailReadiness": email,
        "smsReadiness": sms,
        "authCodeReadiness": auth_codes,
    }


def row_text(row, key: str) -> str:
    try:
        value = row[key]
    except Exception:
        return ""
    return str(value or "")


def row_int(row, key: str, fallback: int = 0) -> int:
    try:
        value = row[key]
        return int(value if value is not None else fallback)
    except Exception:
        return fallback


def auth_code_future_lock(row, now: datetime) -> Optional[str]:
    locked_until = parse_dt(row_text(row, "locked_until"))
    if locked_until is None:
        return None
    if locked_until.tzinfo is None:
        locked_until = locked_until.replace(tzinfo=timezone.utc)
    return locked_until.isoformat() if now < locked_until else None


def clear_expired_auth_code_lock(
    conn: sqlite3.Connection,
    table: str,
    row,
    now: datetime,
) -> int:
    locked_until = parse_dt(row_text(row, "locked_until"))
    if locked_until is not None:
        if locked_until.tzinfo is None:
            locked_until = locked_until.replace(tzinfo=timezone.utc)
        if now >= locked_until:
            conn.execute(
                f"UPDATE {table} SET attempts_count = 0, locked_until = NULL WHERE id = ?",
                (row["id"],),
            )
            return 0
    return row_int(row, "attempts_count", 0)


def record_auth_code_failed_attempt(
    conn: sqlite3.Connection,
    table: str,
    row,
    attempts_count: int,
    now: datetime,
) -> dict:
    attempts = max(0, int(attempts_count or 0)) + 1
    status = "invalid_code"
    locked_until: Optional[str] = None
    if AUTH_CODE_MAX_VERIFY_ATTEMPTS > 0 and attempts >= AUTH_CODE_MAX_VERIFY_ATTEMPTS:
        lock_minutes = max(1, AUTH_CODE_LOCKOUT_MINUTES)
        locked_until = (now + timedelta(minutes=lock_minutes)).isoformat()
        status = "too_many_attempts"
    conn.execute(
        f"""
        UPDATE {table}
        SET attempts_count = ?,
            last_attempt_at = ?,
            locked_until = ?
        WHERE id = ?
        """,
        (attempts, now.isoformat(), locked_until, row["id"]),
    )
    return {
        "ok": False,
        "status": status,
        "attempts": attempts,
        "maxAttempts": AUTH_CODE_MAX_VERIFY_ATTEMPTS,
        "retryAt": locked_until,
    }


def ensure_email_code_resend_allowed(email: str) -> None:
    if AUTH_CODE_RESEND_COOLDOWN_SECONDS <= 0:
        return
    with db() as conn:
        row = conn.execute(
            """
            SELECT created_at
            FROM email_login_codes
            WHERE email = ? AND status = ?
            ORDER BY id DESC
            LIMIT 1
            """,
            (email, "pending"),
        ).fetchone()
    if row is None:
        return
    created_at = parse_dt(row["created_at"])
    if created_at is None:
        return
    retry_at = created_at + timedelta(seconds=AUTH_CODE_RESEND_COOLDOWN_SECONDS)
    if utc_now() < retry_at:
        raise HTTPException(status_code=429, detail="Email code resend cooldown.")


def ensure_user_for_email_code(email: str) -> tuple[sqlite3.Row, bool]:
    now = utc_now_iso()
    with db() as conn:
        row = conn.execute(
            """
            SELECT
                id,
                email,
                email_verified,
                email_verified_at,
                phone,
                phone_verified,
                phone_verified_at
            FROM users
            WHERE email = ?
            """,
            (email,),
        ).fetchone()
        if row is not None:
            return row, False

        conn.execute(
            "INSERT INTO users(email, password_hash, created_at) VALUES (?, ?, ?)",
            (email, hash_password(secrets.token_urlsafe(48)), now),
        )
        row = conn.execute(
            """
            SELECT
                id,
                email,
                email_verified,
                email_verified_at,
                phone,
                phone_verified,
                phone_verified_at
            FROM users
            WHERE email = ?
            """,
            (email,),
        ).fetchone()
        create_trial_subscription(conn, int(row["id"]))
        conn.commit()
        return row, True


def create_email_login_code(user_id: int, email: str) -> tuple[int, str]:
    code = f"{secrets.randbelow(1000000):06d}"
    now = utc_now()
    expires_at = now + timedelta(minutes=AUTH_CODE_TTL_MINUTES)
    with db() as conn:
        conn.execute(
            """
            UPDATE email_login_codes
            SET status = ?, consumed_at = COALESCE(consumed_at, ?)
            WHERE email = ? AND status = ?
            """,
            ("superseded", now.isoformat(), email, "pending"),
        )
        cursor = conn.execute(
            """
            INSERT INTO email_login_codes(
                user_id, email, code_hash, status, purpose, created_at, expires_at
            )
            VALUES (?, ?, ?, ?, ?, ?, ?)
            """,
            (
                user_id,
                email,
                one_time_code_hash("email", email, code),
                "pending",
                "login_or_register",
                now.isoformat(),
                expires_at.isoformat(),
            ),
        )
        conn.commit()
        return int(cursor.lastrowid), code


def send_or_queue_email_login_code(
    user_id: int,
    email: str,
    code_id: int,
    code: str,
) -> dict:
    subject = "Код входа Green VPN"
    real_body = (
        "Привет!\n\n"
        f"Код входа в Green VPN: {code}\n\n"
        f"Код действует {AUTH_CODE_TTL_MINUTES} минут. "
        "Если ты не запрашивал вход, просто игнорируй это письмо.\n"
    )
    outbox_body = (
        "Привет!\n\n"
        "Код входа в Green VPN: ******\n\n"
        f"Код действует {AUTH_CODE_TTL_MINUTES} минут. "
        "Если ты не запрашивал вход, просто игнорируй это письмо.\n"
    )
    outbox_id = queue_email_outbox(
        user_id,
        email,
        subject,
        outbox_body,
        "queued" if email_sender_configured() else "not_configured",
    )

    if not email_sender_configured():
        return {"deliveryStatus": "not_configured", "outboxId": outbox_id}

    try:
        send_smtp_email(email, subject, real_body)
        update_email_outbox_status(outbox_id, "sent")
        with db() as conn:
            conn.execute(
                "UPDATE email_login_codes SET sent_at = ? WHERE id = ?",
                (utc_now_iso(), code_id),
            )
            conn.commit()
        return {"deliveryStatus": "sent", "outboxId": outbox_id}
    except Exception as exc:
        update_email_outbox_status(outbox_id, "failed", str(exc))
        return {"deliveryStatus": "failed", "outboxId": outbox_id}


def consume_email_login_code(email: str, code: str) -> dict:
    clean_code = re.sub(r"\D+", "", code or "")
    if len(clean_code) != 6:
        return {"ok": False, "status": "invalid_code"}

    now = utc_now()
    with db() as conn:
        row = conn.execute(
            """
            SELECT *
            FROM email_login_codes
            WHERE email = ?
            ORDER BY id DESC
            LIMIT 1
            """,
            (email,),
        ).fetchone()

        if row is None or row["status"] != "pending":
            return {"ok": False, "status": "not_found"}

        active_lock = auth_code_future_lock(row, now)
        if active_lock:
            return {
                "ok": False,
                "status": "too_many_attempts",
                "retryAt": active_lock,
                "maxAttempts": AUTH_CODE_MAX_VERIFY_ATTEMPTS,
            }
        attempts_count = clear_expired_auth_code_lock(conn, "email_login_codes", row, now)

        expires_at = parse_dt(row["expires_at"])
        if expires_at is not None and now >= expires_at:
            conn.execute(
                """
                UPDATE email_login_codes
                SET status = ?, consumed_at = ?
                WHERE id = ?
                """,
                ("expired", now.isoformat(), row["id"]),
            )
            conn.commit()
            return {"ok": False, "status": "expired"}

        expected = row["code_hash"]
        provided = one_time_code_hash("email", email, clean_code)
        if not hmac.compare_digest(expected, provided):
            result = record_auth_code_failed_attempt(
                conn,
                "email_login_codes",
                row,
                attempts_count,
                now,
            )
            conn.commit()
            return result

        conn.execute(
            """
            UPDATE email_login_codes
            SET status = ?, consumed_at = ?
            WHERE id = ?
            """,
            ("consumed", now.isoformat(), row["id"]),
        )
        conn.execute(
            """
            UPDATE users
            SET email_verified = 1, email_verified_at = ?
            WHERE id = ?
            """,
            (now.isoformat(), row["user_id"]),
        )
        user = conn.execute(
            """
            SELECT
                id,
                email,
                email_verified,
                email_verified_at,
                phone,
                phone_verified,
                phone_verified_at
            FROM users
            WHERE id = ?
            """,
            (row["user_id"],),
        ).fetchone()
        conn.commit()

    return {"ok": True, "status": "verified", "user": user}


def internal_email_for_phone(phone: str) -> str:
    digest = hashlib.sha256(phone.encode("utf-8")).hexdigest()[:24]
    return f"phone_{digest}@phone.greenvpn.local"


def ensure_user_for_phone_code(phone: str) -> tuple[sqlite3.Row, bool]:
    now = utc_now_iso()
    with db() as conn:
        row = conn.execute(
            """
            SELECT
                id,
                email,
                email_verified,
                email_verified_at,
                phone,
                phone_verified,
                phone_verified_at
            FROM users
            WHERE phone = ?
            ORDER BY phone_verified DESC, id DESC
            LIMIT 1
            """,
            (phone,),
        ).fetchone()
        if row is not None:
            return row, False

        synthetic_email = internal_email_for_phone(phone)
        row = conn.execute(
            """
            SELECT
                id,
                email,
                email_verified,
                email_verified_at,
                phone,
                phone_verified,
                phone_verified_at
            FROM users
            WHERE email = ?
            """,
            (synthetic_email,),
        ).fetchone()
        if row is not None:
            return row, False

        conn.execute(
            """
            INSERT INTO users(email, password_hash, phone, phone_verified, created_at)
            VALUES (?, ?, ?, ?, ?)
            """,
            (
                synthetic_email,
                hash_password(secrets.token_urlsafe(48)),
                phone,
                0,
                now,
            ),
        )
        row = conn.execute(
            """
            SELECT
                id,
                email,
                email_verified,
                email_verified_at,
                phone,
                phone_verified,
                phone_verified_at
            FROM users
            WHERE email = ?
            """,
            (synthetic_email,),
        ).fetchone()
        create_trial_subscription(conn, int(row["id"]))
        conn.commit()
        return row, True




def sms_sender_configured() -> bool:
    if SMS_PROVIDER == "smsru":
        return bool(SMS_RU_API_ID)
    return False


def sms_confirmation_readiness() -> dict:
    provider_known = SMS_PROVIDER in {"manual_mvp", "smsru"}
    checks = [
        {
            "code": "provider",
            "ok": provider_known,
            "message": "Set GREENVPN_SMS_PROVIDER to smsru or manual_mvp.",
            "value": SMS_PROVIDER,
        },
        {
            "code": "smsru_api_id",
            "ok": SMS_PROVIDER != "smsru" or bool(SMS_RU_API_ID),
            "message": "Set GREENVPN_SMS_RU_API_ID for SMS.ru delivery.",
        },
        {
            "code": "code_pepper",
            "ok": len(SMS_CODE_PEPPER) >= 24,
            "message": "Set GREENVPN_SMS_CODE_PEPPER to a long random secret before production.",
        },
    ]
    production_ready = provider_known and SMS_PROVIDER != "manual_mvp" and all(
        check["ok"] for check in checks
    )
    return {
        "ok": True,
        "provider": SMS_PROVIDER,
        "deliveryReady": sms_sender_configured(),
        "productionReady": production_ready,
        "ttlMinutes": SMS_CONFIRMATION_TTL_MINUTES,
        "resendCooldownSeconds": SMS_RESEND_COOLDOWN_SECONDS,
        "testMode": SMS_RU_TEST_MODE,
        "checks": checks,
        "requiredActions": [
            check["message"] for check in checks if not check["ok"]
        ],
    }


def phone_code_hash(phone: str, code: str) -> str:
    material = f"{SMS_CODE_PEPPER}:{phone}:{code}".encode("utf-8")
    return hashlib.sha256(material).hexdigest()


def create_phone_confirmation(user_id: int, phone: str) -> str:
    code = f"{secrets.randbelow(1000000):06d}"
    now = utc_now()
    expires_at = now + timedelta(minutes=SMS_CONFIRMATION_TTL_MINUTES)
    with db() as conn:
        conn.execute(
            """
            UPDATE phone_confirmations
            SET status = ?, consumed_at = COALESCE(consumed_at, ?)
            WHERE user_id = ? AND status = ?
            """,
            ("superseded", now.isoformat(), user_id, "pending"),
        )
        conn.execute(
            """
            INSERT INTO phone_confirmations(
                user_id, phone, code_hash, status, created_at, expires_at
            )
            VALUES (?, ?, ?, ?, ?, ?)
            """,
            (
                user_id,
                phone,
                phone_code_hash(phone, code),
                "pending",
                now.isoformat(),
                expires_at.isoformat(),
            ),
        )
        conn.commit()
    return code


def queue_sms_outbox(
    user_id: int,
    phone: str,
    body: str,
    status: str,
    error: Optional[str] = None,
) -> int:
    with db() as conn:
        cursor = conn.execute(
            """
            INSERT INTO sms_outbox(
                user_id, phone, body, status, error, created_at
            )
            VALUES (?, ?, ?, ?, ?, ?)
            """,
            (user_id, phone, body, status, error, utc_now_iso()),
        )
        conn.commit()
        return int(cursor.lastrowid)


def update_sms_outbox_status(
    outbox_id: int,
    status: str,
    error: Optional[str] = None,
) -> None:
    with db() as conn:
        conn.execute(
            """
            UPDATE sms_outbox
            SET status = ?, error = ?, sent_at = CASE WHEN ? = 'sent' THEN ? ELSE sent_at END
            WHERE id = ?
            """,
            (status, error, status, utc_now_iso(), outbox_id),
        )
        conn.commit()


def send_smsru(phone: str, body: str) -> None:
    params = {
        "api_id": SMS_RU_API_ID,
        "to": phone.lstrip("+"),
        "msg": body,
        "json": "1",
    }
    if SMS_FROM:
        params["from"] = SMS_FROM
    if SMS_RU_TEST_MODE:
        params["test"] = "1"

    data = urllib.parse.urlencode(params).encode("utf-8")
    req = urllib.request.Request(
        "https://sms.ru/sms/send",
        data=data,
        method="POST",
    )
    with urllib.request.urlopen(req, timeout=20) as resp:
        payload = json.loads(resp.read().decode("utf-8"))

    if payload.get("status") != "OK":
        raise RuntimeError(payload.get("status_text") or "SMS.ru delivery failed")

    sms_items = payload.get("sms") or {}
    first = next(iter(sms_items.values()), None)
    if isinstance(first, dict) and first.get("status") != "OK":
        raise RuntimeError(first.get("status_text") or "SMS.ru phone delivery failed")


def send_or_queue_phone_confirmation(user_id: int, phone: str, code: str) -> dict:
    body = f"Код Green VPN: {code}. Никому его не сообщайте."
    body_preview = "Код Green VPN: ******. Никому его не сообщайте."
    outbox_id = queue_sms_outbox(
        user_id,
        phone,
        body_preview,
        "queued" if sms_sender_configured() else "not_configured",
    )

    if not sms_sender_configured():
        return {
            "deliveryStatus": "not_configured",
            "outboxId": outbox_id,
        }

    try:
        if SMS_PROVIDER == "smsru":
            send_smsru(phone, body)
        else:
            raise RuntimeError(f"Unsupported SMS provider: {SMS_PROVIDER}")
        update_sms_outbox_status(outbox_id, "sent")
        with db() as conn:
            conn.execute(
                """
                UPDATE phone_confirmations
                SET sent_at = ?
                WHERE user_id = ? AND phone = ? AND status = ?
                """,
                (utc_now_iso(), user_id, phone, "pending"),
            )
            conn.commit()
        return {
            "deliveryStatus": "sent",
            "outboxId": outbox_id,
        }
    except Exception as exc:
        update_sms_outbox_status(outbox_id, "failed", str(exc))
        return {
            "deliveryStatus": "failed",
            "outboxId": outbox_id,
            "error": str(exc),
        }


def latest_phone_confirmation_status(user_id: int) -> Optional[dict]:
    with db() as conn:
        row = conn.execute(
            """
            SELECT phone, status, created_at, expires_at, sent_at, consumed_at
            FROM phone_confirmations
            WHERE user_id = ?
            ORDER BY id DESC
            LIMIT 1
            """,
            (user_id,),
        ).fetchone()

    if row is None:
        return None
    return {
        "phone": row["phone"],
        "status": row["status"],
        "createdAt": row["created_at"],
        "expiresAt": row["expires_at"],
        "sentAt": row["sent_at"],
        "consumedAt": row["consumed_at"],
    }


def ensure_sms_resend_allowed(user_id: int) -> None:
    if SMS_RESEND_COOLDOWN_SECONDS <= 0:
        return
    with db() as conn:
        row = conn.execute(
            """
            SELECT created_at
            FROM phone_confirmations
            WHERE user_id = ? AND status = ?
            ORDER BY id DESC
            LIMIT 1
            """,
            (user_id, "pending"),
        ).fetchone()
    if row is None:
        return
    created_at = parse_dt(row["created_at"])
    if created_at is None:
        return
    retry_at = created_at + timedelta(seconds=SMS_RESEND_COOLDOWN_SECONDS)
    if utc_now() < retry_at:
        raise HTTPException(
            status_code=429,
            detail="SMS resend cooldown.",
        )


def consume_phone_confirmation_code(user_id: int, phone: str, code: str) -> dict:
    code = re.sub(r"\D+", "", code or "")
    if len(code) != 6:
        return {"ok": False, "status": "invalid_code"}

    now = utc_now()
    with db() as conn:
        row = conn.execute(
            """
            SELECT *
            FROM phone_confirmations
            WHERE user_id = ? AND phone = ?
            ORDER BY id DESC
            LIMIT 1
            """,
            (user_id, phone),
        ).fetchone()

        if row is None or row["status"] != "pending":
            return {"ok": False, "status": "not_found"}

        active_lock = auth_code_future_lock(row, now)
        if active_lock:
            return {
                "ok": False,
                "status": "too_many_attempts",
                "retryAt": active_lock,
                "maxAttempts": AUTH_CODE_MAX_VERIFY_ATTEMPTS,
            }
        attempts_count = clear_expired_auth_code_lock(conn, "phone_confirmations", row, now)

        expires_at = parse_dt(row["expires_at"])
        if expires_at is not None and now >= expires_at:
            conn.execute(
                """
                UPDATE phone_confirmations
                SET status = ?, consumed_at = ?
                WHERE id = ?
                """,
                ("expired", now.isoformat(), row["id"]),
            )
            conn.commit()
            return {"ok": False, "status": "expired"}

        expected = row["code_hash"]
        provided = phone_code_hash(phone, code)
        if not hmac.compare_digest(expected, provided):
            result = record_auth_code_failed_attempt(
                conn,
                "phone_confirmations",
                row,
                attempts_count,
                now,
            )
            conn.commit()
            return result

        conn.execute(
            """
            UPDATE phone_confirmations
            SET status = ?, consumed_at = ?
            WHERE id = ?
            """,
            ("consumed", now.isoformat(), row["id"]),
        )
        conn.execute(
            """
            UPDATE users
            SET phone = ?, phone_verified = 1, phone_verified_at = ?
            WHERE id = ?
            """,
            (phone, now.isoformat(), user_id),
        )
        conn.commit()

    return {"ok": True, "status": "verified", "phone": phone}


def admin_password_hash(password: str) -> str:
    raw_password = str(password or "")
    if len(raw_password) < 10:
        raise HTTPException(
            status_code=400,
            detail="Admin password must contain at least 10 characters.",
        )
    salt = secrets.token_bytes(16)
    digest = hashlib.pbkdf2_hmac(
        "sha256",
        raw_password.encode("utf-8"),
        salt,
        ADMIN_PASSWORD_HASH_ITERATIONS,
    )
    return "pbkdf2_sha256${}${}${}".format(
        ADMIN_PASSWORD_HASH_ITERATIONS,
        base64.b64encode(salt).decode("ascii"),
        base64.b64encode(digest).decode("ascii"),
    )


def verify_admin_password(password: str, encoded: Optional[str]) -> bool:
    if not encoded:
        return False
    try:
        algorithm, iterations_raw, salt_raw, digest_raw = encoded.split("$", 3)
        if algorithm != "pbkdf2_sha256":
            return False
        iterations = int(iterations_raw)
        salt = base64.b64decode(salt_raw.encode("ascii"))
        expected = base64.b64decode(digest_raw.encode("ascii"))
        actual = hashlib.pbkdf2_hmac(
            "sha256",
            str(password or "").encode("utf-8"),
            salt,
            iterations,
        )
        return hmac.compare_digest(actual, expected)
    except Exception:
        return False


def clean_admin_password(value: Optional[str]) -> Optional[str]:
    if value is None:
        return None
    raw = str(value)
    if not raw.strip():
        return None
    return raw


def bearer_token(authorization: Optional[str]) -> str:
    raw = (authorization or "").strip()
    if raw.lower().startswith("bearer "):
        return raw.split(" ", 1)[1].strip()
    return ""


def admin_session_token_hash(token: str) -> str:
    return hashlib.sha256(str(token or "").encode("utf-8")).hexdigest()


def admin_2fa_code_hash(staff_id: int, challenge_id: str, code: str) -> str:
    clean_code = re.sub(r"\D+", "", str(code or ""))
    material = f"{ADMIN_2FA_CODE_PEPPER}:{staff_id}:{challenge_id}:{clean_code}".encode("utf-8")
    return hashlib.sha256(material).hexdigest()


def mask_admin_email(email: str) -> str:
    clean = clean_limited_text(email, 180).strip().lower()
    if "@" not in clean:
        return clean
    local, domain = clean.split("@", 1)
    if len(local) <= 2:
        masked_local = f"{local[:1]}*"
    else:
        masked_local = f"{local[:2]}***{local[-1:]}"
    return f"{masked_local}@{domain}"


def admin_staff_requires_2fa(row) -> bool:
    enabled = bool(row["two_factor_enabled"]) if "two_factor_enabled" in row.keys() else False
    return ADMIN_2FA_REQUIRED or enabled


def admin_2fa_email_configured() -> bool:
    return bool(email_sender_configured() and ADMIN_2FA_CODE_PEPPER)


def admin_2fa_readiness() -> dict:
    with db() as conn:
        total_staff = conn.execute("SELECT COUNT(*) AS count FROM admin_staff").fetchone()["count"]
        enabled_staff = conn.execute(
            "SELECT COUNT(*) AS count FROM admin_staff WHERE two_factor_enabled = 1"
        ).fetchone()["count"]
    checks = [
        {
            "code": "smtp_configured",
            "ok": email_sender_configured(),
            "message": "SMTP для отправки staff-кодов настроен." if email_sender_configured()
            else "Для обязательного 2FA нужно настроить SMTP отправку.",
        },
        {
            "code": "code_pepper",
            "ok": len(ADMIN_2FA_CODE_PEPPER) >= 24
            and ADMIN_2FA_CODE_PEPPER != "greenvpn-dev-auth-code-pepper-not-for-production",
            "message": "Секрет хеширования staff-кодов задан." if len(ADMIN_2FA_CODE_PEPPER) >= 24
            else "Перед production задай GREENVPN_ADMIN_2FA_CODE_PEPPER или GREENVPN_AUTH_CODE_PEPPER.",
        },
        {
            "code": "staff_coverage",
            "ok": not ADMIN_2FA_REQUIRED or int(total_staff or 0) > 0,
            "message": "Staff-аккаунты заведены." if int(total_staff or 0) > 0
            else "Перед обязательным 2FA нужен хотя бы один staff-аккаунт.",
        },
    ]
    required_actions = [
        check["message"]
        for check in checks
        if not check["ok"] and (ADMIN_2FA_REQUIRED or int(enabled_staff or 0) > 0)
    ]
    return {
        "ok": True,
        "version": APP_VERSION,
        "generatedAt": utc_now_iso(),
        "productionReady": len(required_actions) == 0,
        "required": ADMIN_2FA_REQUIRED,
        "enabledStaffCount": int(enabled_staff or 0),
        "totalStaffCount": int(total_staff or 0),
        "codeTtlMinutes": ADMIN_2FA_CODE_TTL_MINUTES,
        "maxAttempts": ADMIN_2FA_MAX_ATTEMPTS,
        "checks": checks,
        "requiredActions": required_actions,
    }


def issue_admin_staff_session(row, request: Request, actor: Optional[str] = None) -> dict:
    raw_token = secrets.token_urlsafe(48)
    token_hash = admin_session_token_hash(raw_token)
    now = utc_now()
    expires_at = now + timedelta(hours=max(1, ADMIN_SESSION_TTL_HOURS))
    request_ip, user_agent = request_ip_and_agent(request)
    with db() as conn:
        conn.execute(
            """
            INSERT INTO admin_sessions(
                token_hash, staff_id, created_at, expires_at, last_seen_at,
                request_ip, user_agent
            )
            VALUES (?, ?, ?, ?, ?, ?, ?)
            """,
            (
                token_hash,
                int(row["id"]),
                now.isoformat(),
                expires_at.isoformat(),
                now.isoformat(),
                request_ip,
                user_agent,
            ),
        )
        conn.execute(
            """
            UPDATE admin_staff
            SET last_login_at = ?, last_seen_at = ?, updated_at = updated_at
            WHERE id = ?
            """,
            (now.isoformat(), now.isoformat(), int(row["id"])),
        )
        conn.commit()
        fresh_row = conn.execute(
            "SELECT * FROM admin_staff WHERE id = ?",
            (int(row["id"]),),
        ).fetchone()

    staff = admin_staff_payload(fresh_row)
    write_admin_audit(
        "admin_staff_login_succeeded",
        "admin_staff",
        str(staff["id"]),
        {"email": staff["email"], "role": staff["role"]},
        request=request,
        actor=clean_limited_text(actor, 120).strip() or staff["email"],
    )
    return {
        "ok": True,
        "sessionToken": raw_token,
        "expiresAt": expires_at.isoformat(),
        "staff": staff,
        "role": ADMIN_ROLE_MATRIX.get(staff["role"], {}),
        "authType": "staff_session",
    }


def admin_context_payload(context: dict) -> dict:
    return {
        "authType": context.get("authType"),
        "actor": context.get("actor"),
        "role": context.get("role"),
        "roleTitle": context.get("roleTitle"),
        "permissions": context.get("permissions", []),
        "staff": context.get("staff"),
        "expiresAt": context.get("expiresAt"),
    }


def resolve_admin_context(
    x_admin_token: Optional[str],
    authorization: Optional[str],
    request: Optional[Request] = None,
) -> dict:
    expected = ADMIN_TOKEN or ensure_admin_token()
    header_candidate = (x_admin_token or "").strip()
    bearer_candidate = bearer_token(authorization)
    bootstrap_candidate = header_candidate or bearer_candidate

    if bootstrap_candidate and hmac.compare_digest(bootstrap_candidate, expected):
        actor = admin_actor_from_request(request, "admin_token") if request else "admin_token"
        permissions = ADMIN_ROLE_MATRIX["owner"]["permissions"]
        return {
            "authType": "bootstrap_token",
            "actor": actor,
            "role": "owner",
            "roleTitle": ADMIN_ROLE_MATRIX["owner"]["title"],
            "permissions": permissions,
            "staff": None,
            "expiresAt": None,
            "sessionHash": None,
        }

    if not bearer_candidate:
        raise HTTPException(status_code=401, detail="Admin authorization required.")

    token_hash = admin_session_token_hash(bearer_candidate)
    now = utc_now()
    with db() as conn:
        row = conn.execute(
            """
            SELECT
                s.token_hash,
                s.staff_id,
                s.created_at AS session_created_at,
                s.expires_at,
                s.last_seen_at AS session_last_seen_at,
                s.revoked_at,
                st.email,
                st.display_name,
                st.role,
                st.is_active,
                st.password_set_at,
                st.two_factor_enabled,
                st.two_factor_method,
                st.two_factor_set_at,
                st.last_login_at,
                st.last_seen_at AS staff_last_seen_at
            FROM admin_sessions s
            JOIN admin_staff st ON st.id = s.staff_id
            WHERE s.token_hash = ?
            """,
            (token_hash,),
        ).fetchone()
        if row is None:
            raise HTTPException(status_code=401, detail="Invalid admin session.")
        if row["revoked_at"]:
            raise HTTPException(status_code=401, detail="Admin session revoked.")
        expires_at = parse_dt(row["expires_at"])
        if expires_at is None or expires_at <= now:
            raise HTTPException(status_code=401, detail="Admin session expired.")
        if not bool(row["is_active"]):
            raise HTTPException(status_code=403, detail="Admin staff member is disabled.")

        now_iso = now.isoformat()
        conn.execute(
            "UPDATE admin_sessions SET last_seen_at = ? WHERE token_hash = ?",
            (now_iso, token_hash),
        )
        conn.execute(
            "UPDATE admin_staff SET last_seen_at = ?, updated_at = updated_at WHERE id = ?",
            (now_iso, int(row["staff_id"])),
        )
        conn.commit()

    role = normalize_admin_role(row["role"])
    role_def = ADMIN_ROLE_MATRIX[role]
    staff = {
        "id": int(row["staff_id"]),
        "email": row["email"],
        "displayName": row["display_name"],
        "role": role,
        "roleTitle": role_def["title"],
        "isActive": bool(row["is_active"]),
        "passwordSetAt": row["password_set_at"],
        "twoFactorEnabled": bool(row["two_factor_enabled"]),
        "twoFactorMethod": row["two_factor_method"],
        "twoFactorSetAt": row["two_factor_set_at"],
        "lastLoginAt": row["last_login_at"],
        "lastSeenAt": row["staff_last_seen_at"],
    }
    return {
        "authType": "staff_session",
        "actor": row["display_name"] or row["email"],
        "role": role,
        "roleTitle": role_def["title"],
        "permissions": role_def["permissions"],
        "staff": staff,
        "expiresAt": row["expires_at"],
        "sessionHash": token_hash,
    }


def require_admin(
    x_admin_token: Optional[str],
    authorization: Optional[str],
    permission: Optional[object] = None,
    request: Optional[Request] = None,
) -> dict:
    context = resolve_admin_context(x_admin_token, authorization, request=request)
    if request is not None:
        request.state.admin_context = context
    if isinstance(permission, str):
        required_permissions = [permission]
    else:
        required_permissions = list(permission or [])
    if required_permissions and not any(
        item in context.get("permissions", []) for item in required_permissions
    ):
        raise HTTPException(status_code=403, detail="Admin role lacks required permission.")
    return context


def run_capture(args: list[str], input_text: Optional[str] = None) -> str:
    res = subprocess.run(
        args,
        input=input_text,
        text=True,
        capture_output=True,
        check=True,
    )
    return res.stdout.strip()


def wg_genkeypair() -> tuple[str, str]:
    private_key = run_capture(["wg", "genkey"])
    public_key = run_capture(["wg", "pubkey"], input_text=private_key)
    return private_key, public_key


def wg_genpsk() -> str:
    return run_capture(["wg", "genpsk"])


def get_server_public_key() -> str:
    return run_capture(["wg", "show", WG_INTERFACE, "public-key"])


def builtin_server_catalog_entry() -> dict:
    endpoint = {
        "host": WG_ENDPOINT_HOST,
        "port": WG_ENDPOINT_PORT,
    }
    return {
        "id": "intelligent_smew",
        "title": "Netherlands #1",
        "subtitle": "Основной сервер Green VPN",
        "country": "NL",
        "city": "Amsterdam",
        "provider": "current-dev-provider",
        "status": "healthy",
        "available": True,
        "healthScore": 95,
        "latencyMs": 44,
        "endpoint": endpoint,
        "protocols": [
            {
                "code": "wireguard_udp",
                "title": "WireGuard UDP",
                "transport": "udp",
                "port": WG_ENDPOINT_PORT,
                "primary": True,
            }
        ],
        "managed": False,
        "clientConfigReady": True,
    }


def build_server_catalog() -> dict:
    servers = [builtin_server_catalog_entry()]
    return {
        "version": SERVER_CATALOG_VERSION,
        "generatedAt": utc_now_iso(),
        "defaultServerId": "intelligent_smew",
        "auto": {
            "title": "Авто",
            "subtitle": "Пока выбирает основной стабильный endpoint",
            "strategy": "first_healthy",
        },
        "servers": servers,
        "bootstrap": {
            "apiBaseUrls": SERVER_CATALOG_API_BASE_URLS,
            "emergencyCatalogUrl": SERVER_CATALOG_EMERGENCY_URL,
        },
        "managedCatalog": {
            "enabled": True,
            "mode": "admin_preparation",
            "message": (
                "Дополнительные endpoint управляются в админке, но не выдаются "
                "клиенту до отдельного provisioning-слоя."
            ),
            "clientVisibleManagedEntries": 0,
            "publicationRules": server_publication_requirements(),
        },
    }


def server_publication_requirements() -> dict:
    return {
        "minHealthScore": SERVER_PUBLIC_MIN_HEALTH_SCORE,
        "maxObservationAgeHours": SERVER_PUBLIC_OBSERVATION_MAX_AGE_HOURS,
        "minHealthyObservations24h": SERVER_PUBLIC_MIN_HEALTHY_OBSERVATIONS,
        "requiredProtocol": "wireguard_udp",
        "clientConfigProfiles": list(SERVER_CLIENT_CONFIG_PROFILES),
        "requiresActive": True,
        "requiresPublicCandidate": True,
        "requiresClientConfigReady": True,
        "requiresFreshHealthyObservation": True,
        "autoPausesBadPublicCandidates": SERVER_PUBLIC_AUTO_PAUSE_ENABLED,
    }


def normalize_server_catalog_status(value: Optional[str], fallback: str = "draft") -> str:
    candidate = clean_limited_text(value, 40).strip().lower() or fallback
    if candidate not in SERVER_CATALOG_STATUSES:
        raise HTTPException(status_code=400, detail="Unknown server status.")
    return candidate


def normalize_server_catalog_protocol(value: Optional[str], fallback: str = "wireguard_udp") -> str:
    candidate = clean_limited_text(value, 40).strip().lower() or fallback
    if candidate not in SERVER_CATALOG_PROTOCOLS:
        raise HTTPException(status_code=400, detail="Unknown server protocol.")
    return candidate


def normalize_server_catalog_transport(value: Optional[str], fallback: str = "udp") -> str:
    candidate = clean_limited_text(value, 40).strip().lower() or fallback
    if candidate not in SERVER_CATALOG_TRANSPORTS:
        raise HTTPException(status_code=400, detail="Unknown server transport.")
    return candidate


def normalize_server_client_config_profile(
    value: Optional[str],
    fallback: str = "none",
) -> str:
    candidate = clean_limited_text(value, 60).strip().lower() or fallback
    if candidate not in SERVER_CLIENT_CONFIG_PROFILES:
        raise HTTPException(status_code=400, detail="Unknown client config profile.")
    return candidate


def normalize_server_id(value: Optional[str]) -> str:
    candidate = clean_limited_text(value, 80).strip().lower()
    if not candidate:
        raise HTTPException(status_code=400, detail="serverId is required.")
    if not re.fullmatch(r"[a-z0-9][a-z0-9_-]{2,79}", candidate):
        raise HTTPException(
            status_code=400,
            detail="serverId must contain latin letters, numbers, dash or underscore.",
        )
    if candidate in {"auto", "intelligent_smew"}:
        raise HTTPException(status_code=400, detail="serverId is reserved.")
    return candidate


def normalize_server_host(value: Optional[str]) -> str:
    host = clean_limited_text(value, 250).strip().lower()
    if not host:
        raise HTTPException(status_code=400, detail="host is required.")
    if "/" in host or "\\" in host or " " in host:
        raise HTTPException(status_code=400, detail="host must be a DNS name or IP address.")
    return host


def normalize_server_port(value: Optional[int]) -> int:
    try:
        port = int(value or 0)
    except Exception:
        port = 0
    if port < 1 or port > 65535:
        raise HTTPException(status_code=400, detail="port must be 1..65535.")
    return port


def normalize_percentish(value: Optional[int], fallback: int = 0) -> int:
    try:
        parsed = int(value if value is not None else fallback)
    except Exception:
        parsed = fallback
    return max(0, min(100, parsed))


def normalize_priority(value: Optional[int], fallback: int = 100) -> int:
    try:
        parsed = int(value if value is not None else fallback)
    except Exception:
        parsed = fallback
    return max(0, min(10000, parsed))


def server_observation_age_hours(observed_at: Optional[str]) -> Optional[float]:
    observed_dt = parse_dt(observed_at)
    if observed_dt is None:
        return None
    if observed_dt.tzinfo is None:
        observed_dt = observed_dt.replace(tzinfo=timezone.utc)
    return max(0.0, (utc_now() - observed_dt).total_seconds() / 3600)


def server_health_meta_for_entries(
    conn: sqlite3.Connection,
    endpoint_ids: list[str],
) -> dict[str, dict]:
    unique_ids = sorted({endpoint_id for endpoint_id in endpoint_ids if endpoint_id})
    since_24h = (utc_now() - timedelta(hours=24)).isoformat()
    result: dict[str, dict] = {}
    for endpoint_id in unique_ids:
        latest_row = conn.execute(
            """
            SELECT *
            FROM server_health_observations
            WHERE endpoint_id = ?
            ORDER BY observed_at DESC, id DESC
            LIMIT 1
            """,
            (endpoint_id,),
        ).fetchone()
        healthy_24h = conn.execute(
            """
            SELECT COUNT(*)
            FROM server_health_observations
            WHERE endpoint_id = ? AND observed_at >= ? AND status = 'healthy'
            """,
            (endpoint_id, since_24h),
        ).fetchone()[0]
        failed_24h = conn.execute(
            """
            SELECT COUNT(*)
            FROM server_health_observations
            WHERE endpoint_id = ? AND observed_at >= ? AND status IN ('degraded', 'down')
            """,
            (endpoint_id, since_24h),
        ).fetchone()[0]
        latest = server_health_observation_payload(latest_row) if latest_row is not None else None
        result[endpoint_id] = {
            "latest": latest,
            "latestAgeHours": (
                server_observation_age_hours(latest.get("observedAt")) if latest else None
            ),
            "healthyObservations24h": int(healthy_24h or 0),
            "failedObservations24h": int(failed_24h or 0),
        }
    return result


def server_row_client_config_profile(row: sqlite3.Row) -> str:
    try:
        raw_profile = row["client_config_profile"]
    except Exception:
        raw_profile = "none"
    try:
        return normalize_server_client_config_profile(raw_profile)
    except HTTPException:
        return "none"


def server_client_config_readiness(row: sqlite3.Row) -> dict:
    profile = server_row_client_config_profile(row)
    blockers: list[dict] = []

    def add_blocker(code: str, message: str) -> None:
        blockers.append({"code": code, "message": message})

    if profile == "none":
        add_blocker(
            "client_config_profile_missing",
            "Не выбран профиль выдачи конфига. Endpoint остаётся только внутренней записью.",
        )
    elif profile == "builtin_wg0":
        host = str(row["host"] or "").strip().lower()
        expected_host = WG_ENDPOINT_HOST.strip().lower()
        port = int(row["port"] or 0)
        if row["protocol"] != "wireguard_udp":
            add_blocker(
                "client_config_protocol_mismatch",
                "Профиль builtin_wg0 поддерживает только WireGuard UDP.",
            )
        if row["transport"] != "udp":
            add_blocker(
                "client_config_transport_mismatch",
                "Профиль builtin_wg0 поддерживает только UDP transport.",
            )
        if host != expected_host or port != WG_ENDPOINT_PORT:
            add_blocker(
                "client_config_endpoint_mismatch",
                (
                    "Профиль builtin_wg0 можно включать только для текущего backend "
                    f"endpoint {WG_ENDPOINT_HOST}:{WG_ENDPOINT_PORT}."
                ),
            )
    else:
        add_blocker(
            "client_config_profile_unknown",
            "Неизвестный профиль выдачи конфига. Endpoint заблокирован до ручной проверки.",
        )

    return {
        "ready": not blockers,
        "profile": profile,
        "title": SERVER_CLIENT_CONFIG_PROFILE_TITLES.get(profile, profile),
        "blockers": blockers,
        "managedBy": "backend_wg0" if profile == "builtin_wg0" else "manual",
        "expectedEndpoint": {
            "host": WG_ENDPOINT_HOST,
            "port": WG_ENDPOINT_PORT,
            "interface": WG_INTERFACE,
        },
    }


def server_public_eligibility(row: sqlite3.Row, health_meta: Optional[dict] = None) -> dict:
    meta = health_meta or {}
    latest = meta.get("latest")
    blockers: list[dict] = []

    def add_blocker(code: str, message: str) -> None:
        blockers.append({"code": code, "message": message})

    is_active = bool(row["is_active"])
    is_public = bool(row["is_public"])
    status = row["status"]
    protocol = row["protocol"]
    health_score = int(row["health_score"] or 0)
    healthy_24h = int(meta.get("healthyObservations24h") or 0)
    failed_24h = int(meta.get("failedObservations24h") or 0)
    latest_age_hours = meta.get("latestAgeHours")
    config_readiness = server_client_config_readiness(row)

    if not is_active:
        add_blocker("inactive", "Endpoint выключен в админке.")
    if not is_public:
        add_blocker("not_public_candidate", "Endpoint пока не отмечен кандидатом в публичный catalog.")
    if status != "healthy":
        add_blocker("status_not_healthy", f"Статус endpoint сейчас {status}.")
    if health_score < SERVER_PUBLIC_MIN_HEALTH_SCORE:
        add_blocker(
            "health_score_low",
            f"Health score {health_score}%, нужно минимум {SERVER_PUBLIC_MIN_HEALTH_SCORE}%.",
        )
    if protocol != "wireguard_udp":
        add_blocker(
            "client_protocol_not_ready",
            "Клиентский provisioning сейчас готов только для основного WireGuard UDP слоя.",
        )
    if latest is None:
        add_blocker(
            "no_health_observation",
            "Нет monitoring-наблюдения по endpoint, нельзя выдавать его пользователям.",
        )
    else:
        if latest.get("status") != "healthy":
            add_blocker(
                "latest_health_not_healthy",
                f"Последнее monitoring-наблюдение: {latest.get('status') or 'unknown'}.",
            )
        if latest_age_hours is None:
            add_blocker("latest_health_unparseable", "Не удалось разобрать время последней проверки.")
        elif latest_age_hours > SERVER_PUBLIC_OBSERVATION_MAX_AGE_HOURS:
            add_blocker(
                "latest_health_stale",
                (
                    f"Последняя проверка старше {SERVER_PUBLIC_OBSERVATION_MAX_AGE_HOURS} ч "
                    f"({latest_age_hours:.1f} ч)."
                ),
            )
    if healthy_24h < SERVER_PUBLIC_MIN_HEALTHY_OBSERVATIONS:
        add_blocker(
            "not_enough_healthy_observations",
            (
                f"Healthy-проверок за 24ч: {healthy_24h}, нужно минимум "
                f"{SERVER_PUBLIC_MIN_HEALTHY_OBSERVATIONS}."
            ),
        )
    if failed_24h > 0:
        add_blocker(
            "recent_failures_present",
            f"За последние 24ч есть failed/degraded проверки: {failed_24h}.",
        )

    if not config_readiness["ready"]:
        for blocker in config_readiness["blockers"]:
            add_blocker(blocker["code"], blocker["message"])

    return {
        "eligible": not blockers,
        "blockers": blockers,
        "clientConfigReadiness": config_readiness,
        "requirements": server_publication_requirements(),
        "latestObservationAt": latest.get("observedAt") if latest else None,
        "latestObservationStatus": latest.get("status") if latest else None,
        "latestObservationAgeHours": (
            round(float(latest_age_hours), 2) if latest_age_hours is not None else None
        ),
        "healthyObservations24h": healthy_24h,
        "failedObservations24h": failed_24h,
    }


def server_catalog_workflow_options() -> dict:
    return {
        "statuses": list(SERVER_CATALOG_STATUSES),
        "protocols": list(SERVER_CATALOG_PROTOCOLS),
        "transports": list(SERVER_CATALOG_TRANSPORTS),
        "clientConfigProfiles": [
            {
                "code": profile,
                "title": SERVER_CLIENT_CONFIG_PROFILE_TITLES.get(profile, profile),
                "description": (
                    "Не выдавать клиентам, только inventory"
                    if profile == "none"
                    else "Только текущий backend wg0 endpoint, без новых VPS"
                ),
            }
            for profile in SERVER_CLIENT_CONFIG_PROFILES
        ],
        "publicMode": "admin_preparation",
        "publicSafety": (
            "Managed entries are internal planning records until they have an explicit "
            "client config profile, fresh health checks, and release review."
        ),
        "safeDraftCreation": {
            "endpoint": "/api/v1/admin/server-catalog/draft-from-plan",
            "forcedDefaults": {
                "status": "draft",
                "isActive": False,
                "isPublic": False,
                "clientConfigProfile": "none",
                "protocol": "wireguard_udp",
                "transport": "udp",
                "healthScore": 0,
                "priority": 100,
            },
            "clientImpact": "Новый VPS сохраняется только как внутренний черновик и не попадает в клиентский catalog.",
        },
        "publicRequirements": server_publication_requirements(),
    }


def server_catalog_entry_payload(row: sqlite3.Row, health_meta: Optional[dict] = None) -> dict:
    health_meta = health_meta or {}
    eligibility = server_public_eligibility(row, health_meta)
    config_readiness = eligibility["clientConfigReadiness"]
    return {
        "id": int(row["id"]),
        "serverId": row["server_id"],
        "title": row["title"],
        "subtitle": row["subtitle"] or "",
        "country": row["country"],
        "city": row["city"] or "",
        "provider": row["provider"] or "",
        "host": row["host"],
        "port": int(row["port"]),
        "protocol": row["protocol"],
        "transport": row["transport"],
        "clientConfigProfile": config_readiness["profile"],
        "clientConfigProfileTitle": config_readiness["title"],
        "clientConfigReadiness": config_readiness,
        "status": row["status"],
        "healthScore": int(row["health_score"] or 0),
        "latencyMs": int(row["latency_ms"]) if row["latency_ms"] is not None else None,
        "priority": int(row["priority"] or 100),
        "isActive": bool(row["is_active"]),
        "isPublic": bool(row["is_public"]),
        "publicationPausedAt": row["publication_paused_at"] or "",
        "publicationPausedReason": row["publication_paused_reason"] or "",
        "publicationPausedBy": row["publication_paused_by"] or "",
        "clientConfigReady": bool(config_readiness["ready"]),
        "available": bool(row["is_active"]) and row["status"] == "healthy",
        "publicEligible": bool(eligibility["eligible"]),
        "publicEligibility": eligibility,
        "publicBlockers": eligibility["blockers"],
        "latestObservation": health_meta.get("latest"),
        "latestObservationAt": eligibility["latestObservationAt"],
        "latestObservationStatus": eligibility["latestObservationStatus"],
        "latestObservationAgeHours": eligibility["latestObservationAgeHours"],
        "healthyObservations24h": eligibility["healthyObservations24h"],
        "failedObservations24h": eligibility["failedObservations24h"],
        "notes": row["notes"] or "",
        "createdAt": row["created_at"],
        "updatedAt": row["updated_at"],
    }


def list_managed_server_catalog_entries(
    status: Optional[str] = None,
    active: Optional[str] = None,
    public: Optional[str] = None,
    limit: int = 100,
    offset: int = 0,
) -> list[dict]:
    where = []
    params: list[object] = []
    if status and status != "all":
        where.append("status = ?")
        params.append(normalize_server_catalog_status(status))
    if active not in {None, "", "all"}:
        where.append("is_active = ?")
        params.append(1 if str(active).lower() in {"1", "true", "yes", "active"} else 0)
    if public not in {None, "", "all"}:
        where.append("is_public = ?")
        params.append(1 if str(public).lower() in {"1", "true", "yes", "public"} else 0)
    sql = "SELECT * FROM server_catalog_entries"
    if where:
        sql += " WHERE " + " AND ".join(where)
    sql += " ORDER BY priority ASC, id DESC LIMIT ? OFFSET ?"
    params.extend([max(1, min(int(limit or 100), 500)), max(0, int(offset or 0))])
    with db() as conn:
        rows = conn.execute(sql, tuple(params)).fetchall()
        health_meta = server_health_meta_for_entries(
            conn,
            [row["server_id"] for row in rows],
        )
    return [
        server_catalog_entry_payload(row, health_meta.get(row["server_id"]))
        for row in rows
    ]


def build_server_catalog_admin_summary(
    public_catalog: dict,
    managed_entries: list[dict],
) -> dict:
    blockers_by_code: dict[str, int] = {}
    for entry in managed_entries:
        for blocker in entry.get("publicBlockers") or []:
            code = blocker.get("code") or "unknown"
            blockers_by_code[code] = blockers_by_code.get(code, 0) + 1

    public_servers = public_catalog.get("servers") or []
    return {
        "publicClientServers": len(public_servers),
        "publicDefaultServerId": public_catalog.get("defaultServerId") or "",
        "managedTotal": len(managed_entries),
        "managedActive": sum(1 for entry in managed_entries if entry.get("isActive")),
        "managedPublicCandidates": sum(1 for entry in managed_entries if entry.get("isPublic")),
        "managedHealthy": sum(1 for entry in managed_entries if entry.get("status") == "healthy"),
        "managedClientConfigReady": sum(
            1 for entry in managed_entries if entry.get("clientConfigReady")
        ),
        "managedPublicEligible": sum(
            1 for entry in managed_entries if entry.get("publicEligible")
        ),
        "managedBlocked": sum(
            1 for entry in managed_entries if not entry.get("publicEligible")
        ),
        "blockersByCode": blockers_by_code,
        "mode": "safe_admin_preparation",
        "message": (
            "Публичный клиентский catalog пока намеренно выдаёт только проверенный "
            "builtin endpoint. Managed endpoints будут открыты клиентам после "
            "provisioning, свежих health-проверок и явного допуска."
        ),
    }


def build_server_publication_readiness(
    public_catalog: dict,
    managed_entries: list[dict],
) -> dict:
    summary = build_server_catalog_admin_summary(public_catalog, managed_entries)
    eligible_entries = [
        entry for entry in managed_entries if entry.get("publicEligible")
    ]
    blocked_entries = [
        {
            "serverId": entry.get("serverId"),
            "title": entry.get("title"),
            "status": entry.get("status"),
            "isActive": entry.get("isActive"),
            "isPublic": entry.get("isPublic"),
            "publicationPausedAt": entry.get("publicationPausedAt"),
            "publicationPausedReason": entry.get("publicationPausedReason"),
            "publicationPausedBy": entry.get("publicationPausedBy"),
            "healthScore": entry.get("healthScore"),
            "clientConfigProfile": entry.get("clientConfigProfile"),
            "clientConfigReady": entry.get("clientConfigReady"),
            "blockers": entry.get("publicBlockers") or [],
            "latestObservationAt": entry.get("latestObservationAt"),
            "latestObservationStatus": entry.get("latestObservationStatus"),
        }
        for entry in managed_entries
        if not entry.get("publicEligible")
    ]
    blockers_by_code = summary.get("blockersByCode") or {}
    next_actions: list[dict] = []

    if not managed_entries:
        next_actions.append(
            {
                "code": "add_managed_endpoint",
                "title": "Добавить первый managed endpoint",
                "owner": "admin",
                "detail": (
                    "Занеси новый VPS в Server Catalog как draft/internal. "
                    "Публичный клиент от этого не изменится."
                ),
            }
        )
    if blockers_by_code.get("client_config_profile_missing"):
        next_actions.append(
            {
                "code": "choose_client_config_profile",
                "title": "Выбрать профиль выдачи конфига",
                "owner": "codex",
                "detail": (
                    "Для текущего сервера можно выбрать builtin_wg0, для новых VPS "
                    "профиль остаётся none до отдельного provisioning слоя."
                ),
            }
        )
    if blockers_by_code.get("client_config_endpoint_mismatch"):
        next_actions.append(
            {
                "code": "implement_multi_endpoint_provisioning",
                "title": "Сделать provisioning для внешних VPN endpoint",
                "owner": "codex",
                "detail": (
                    "Новые VPS нельзя отдавать клиентам через текущий wg0-профиль. "
                    "Нужны отдельные peer/config rules, routing и health-gate по serverId."
                ),
            }
        )
    if blockers_by_code.get("no_health_observation") or blockers_by_code.get(
        "not_enough_healthy_observations"
    ):
        next_actions.append(
            {
                "code": "add_monitoring_observations",
                "title": "Накопить health observations",
                "owner": "ops",
                "detail": (
                    "Endpoint должен иметь свежие healthy-проверки за последние 24 часа, "
                    "иначе авто-выбор сервера будет небезопасным."
                ),
            }
        )
    if blockers_by_code.get("not_public_candidate"):
        next_actions.append(
            {
                "code": "mark_public_candidate_after_canary",
                "title": "Отметить endpoint кандидатом только после canary",
                "owner": "admin",
                "detail": (
                    "Флаг public сейчас означает только кандидат на публикацию, "
                    "а не мгновенную выдачу пользователям."
                ),
            }
        )
    if not next_actions:
        next_actions.append(
            {
                "code": "ready_for_manual_review",
                "title": "Готово к ручному release review",
                "owner": "admin",
                "detail": (
                    "Перед публикацией всё равно нужен release gate, staged rollout "
                    "и план rollback."
                ),
            }
        )

    return {
        "ok": True,
        "version": APP_VERSION,
        "mode": "safe_admin_preparation",
        "canPublishManagedEndpoints": bool(eligible_entries),
        "publicCatalogUnchanged": True,
        "publicCatalogServerIds": [
            server.get("id") for server in public_catalog.get("servers") or []
        ],
        "defaultServerId": public_catalog.get("defaultServerId") or "",
        "publicationRules": server_publication_requirements(),
        "summary": summary,
        "eligibleManagedEntries": [
            {
                "serverId": entry.get("serverId"),
                "title": entry.get("title"),
                "healthScore": entry.get("healthScore"),
                "clientConfigProfile": entry.get("clientConfigProfile"),
                "latestObservationAt": entry.get("latestObservationAt"),
            }
            for entry in eligible_entries
        ],
        "blockedManagedEntries": blocked_entries,
        "nextActions": next_actions,
        "clientImpact": (
            "Публичный клиентский server catalog пока остаётся на builtin endpoint "
            "intelligent_smew. Это намеренно защищает работающий VPN от случайной "
            "выдачи неподготовленного сервера."
        ),
    }


def build_new_server_onboarding_plan(
    public_catalog: dict,
    managed_entries: list[dict],
    expected_endpoint: str,
    safe_for_current_client: bool,
) -> dict:
    public_servers = public_catalog.get("servers") or []
    public_server_ids = [str(server.get("id") or "") for server in public_servers]
    default_server_id = str(public_catalog.get("defaultServerId") or "intelligent_smew")
    internal_drafts = [
        entry
        for entry in managed_entries
        if not entry.get("isPublic") and str(entry.get("status") or "") in {"draft", "maintenance"}
    ]
    unsafe_public_candidates = [
        entry
        for entry in managed_entries
        if entry.get("isPublic") or str(entry.get("serverId") or "") in public_server_ids
    ]
    safe_to_create_draft = safe_for_current_client and len(unsafe_public_candidates) == 0

    recommended_examples = [
        {
            "serverId": "nl1",
            "hostname": "nl1.vpn.greenvpn.pro",
            "region": "Amsterdam, Netherlands",
            "country": "NL",
            "city": "Amsterdam",
            "role": "first_foreign_vpn_endpoint",
            "safeDraftPayload": {
                "serverId": "nl1",
                "title": "Netherlands #1",
                "subtitle": "Внутренний черновик нового endpoint Green VPN",
                "country": "NL",
                "city": "Amsterdam",
                "provider": "timeweb-or-next-provider",
                "host": "nl1.vpn.greenvpn.pro",
                "port": WG_ENDPOINT_PORT,
                "plannedBandwidthMbps": 1000,
                "monthlyCostRub": 3890,
            },
        },
        {
            "serverId": "de1",
            "hostname": "de1.vpn.greenvpn.pro",
            "region": "Frankfurt, Germany",
            "country": "DE",
            "city": "Frankfurt",
            "role": "latency_and_fallback_candidate",
            "safeDraftPayload": {
                "serverId": "de1",
                "title": "Germany #1",
                "subtitle": "Внутренний черновик резервного endpoint Green VPN",
                "country": "DE",
                "city": "Frankfurt",
                "provider": "timeweb-or-next-provider",
                "host": "de1.vpn.greenvpn.pro",
                "port": WG_ENDPOINT_PORT,
                "plannedBandwidthMbps": 200,
                "monthlyCostRub": 3240,
            },
        },
        {
            "serverId": "kz1",
            "hostname": "kz1.vpn.greenvpn.pro",
            "region": "Almaty, Kazakhstan",
            "country": "KZ",
            "city": "Almaty",
            "role": "regional_fallback_candidate",
            "safeDraftPayload": {
                "serverId": "kz1",
                "title": "Kazakhstan #1",
                "subtitle": "Внутренний черновик регионального endpoint Green VPN",
                "country": "KZ",
                "city": "Almaty",
                "provider": "timeweb-or-next-provider",
                "host": "kz1.vpn.greenvpn.pro",
                "port": WG_ENDPOINT_PORT,
                "plannedBandwidthMbps": 100,
                "monthlyCostRub": 5420,
            },
        },
    ]

    owner_inputs = [
        {
            "name": "Провайдер и тариф VPS",
            "secret": False,
            "example": "Timeweb / Amsterdam / 1 Gbit/s / monthly cost",
        },
        {
            "name": "Публичный IPv4 нового VPS",
            "secret": False,
            "example": "203.0.113.10",
        },
        {
            "name": "Hostname для VPN endpoint",
            "secret": False,
            "example": "nl1.vpn.greenvpn.pro",
        },
        {
            "name": "WireGuard UDP port",
            "secret": False,
            "example": str(WG_ENDPOINT_PORT),
        },
        {
            "name": "Плановая пропускная способность",
            "secret": False,
            "example": "1000 Mbps provider channel, internal planning cap per node",
        },
        {
            "name": "Публичная подпись региона",
            "secret": False,
            "example": "Нидерланды, Амстердам",
        },
    ]

    phases = [
        {
            "code": "inventory_draft",
            "title": "Завести VPS как внутренний черновик",
            "owner": "codex",
            "status": "ready" if safe_to_create_draft else "blocked",
            "details": (
                "В админском каталоге создать managed entry с isPublic=false, "
                "isActive=false, status=draft, clientConfigProfile=none."
            ),
            "exitCriteria": [
                "serverId уникален",
                "public catalog не изменился",
                "клиент всё ещё получает только default endpoint",
            ],
        },
        {
            "code": "dns_and_network",
            "title": "Привязать DNS и проверить сеть",
            "owner": "owner",
            "status": "blocked_until_vps_exists",
            "details": (
                "Создать A-запись вида nl1.vpn.greenvpn.pro -> новый IPv4, "
                "открыть WireGuard UDP port и убедиться, что API/site IP не смешан с VPN endpoint."
            ),
            "exitCriteria": [
                "hostname резолвится в новый IPv4",
                "UDP порт доступен снаружи",
                "api.greenvpn.pro остаётся отдельным public API/site host",
            ],
        },
        {
            "code": "wireguard_provisioning",
            "title": "Подготовить серверный WireGuard без секретов в repo",
            "owner": "codex",
            "status": "planned",
            "details": (
                "Настроить интерфейс и peer allocation на новом VPS. Private keys и admin tokens "
                "хранятся только на сервере, в чат и repository не попадают."
            ),
            "exitCriteria": [
                "server private key создан только на VPS",
                "peer/config выдача отделена от builtin wg0",
                "rollback-команды задокументированы",
            ],
        },
        {
            "code": "external_probe",
            "title": "Поставить внешний monitoring probe",
            "owner": "codex",
            "status": "blocked_until_probe_host",
            "details": (
                "Проверять новый endpoint с отдельного monitoring VPS, а не только с самого backend."
            ),
            "exitCriteria": [
                "есть свежие healthy observations",
                "нет активных server-health incidents",
                "endpoint покрыт external probe agent",
            ],
        },
        {
            "code": "staged_publication",
            "title": "Публиковать только после отдельной выдачи конфигов",
            "owner": "codex",
            "status": "locked",
            "details": (
                "До готовности multi-endpoint provisioning новый VPS остаётся внутренним. "
                "Публичный catalog для Windows MVP не меняется."
            ),
            "exitCriteria": [
                "clientConfigProfile не builtin_wg0 для чужого VPS",
                "стадии canary/rollback готовы",
                "release gate зелёный кроме сознательных owner blockers",
            ],
        },
    ]

    safety_gates = [
        {
            "code": "public_catalog_unchanged",
            "ok": len(unsafe_public_candidates) == 0,
            "message": "Новый VPS не должен попадать в /api/v1/catalog/servers до готовности rollout.",
        },
        {
            "code": "current_client_safe",
            "ok": safe_for_current_client,
            "message": f"Текущий клиент продолжает получать {default_server_id} -> {expected_endpoint}.",
        },
        {
            "code": "server_specific_config_required",
            "ok": False,
            "warning": True,
            "message": "Для второго VPS нужен отдельный peer/config builder; builtin_wg0 подходит только текущему endpoint.",
        },
        {
            "code": "external_probe_required",
            "ok": False,
            "warning": True,
            "message": "Перед публикацией нужен внешний monitoring probe с отдельной машины.",
        },
    ]

    return {
        "mode": "internal_only_until_provisioning",
        "productionReady": False,
        "safeToCreateInternalDraft": safe_to_create_draft,
        "defaultServerId": default_server_id,
        "currentClientEndpoint": expected_endpoint,
        "draftCreationEndpoint": "/api/v1/admin/server-catalog/draft-from-plan",
        "recommendedExamples": recommended_examples,
        "safeDraftPayloadExample": recommended_examples[0]["safeDraftPayload"],
        "recommendedDraftDefaults": {
            "status": "draft",
            "isActive": False,
            "isPublic": False,
            "clientConfigProfile": "none",
            "protocol": "wireguard_udp",
            "transport": "udp",
            "priority": 100,
        },
        "ownerInputs": owner_inputs,
        "phases": phases,
        "safetyGates": safety_gates,
        "internalDraftsAlreadyPresent": [
            {
                "serverId": entry.get("serverId"),
                "title": entry.get("title"),
                "host": entry.get("host"),
                "status": entry.get("status"),
            }
            for entry in internal_drafts[:20]
        ],
        "blockedUntil": [
            "API/site host and VPN endpoint are split before public launch",
            "new VPS exists and DNS A record points to it",
            "server-specific WireGuard peer/config provisioning is implemented",
            "external monitoring probe has fresh healthy observations",
            "staged rollout and rollback are checked",
        ],
        "verification": [
            {"kind": "admin_api", "path": "/api/v1/admin/server-catalog"},
            {"kind": "admin_api", "path": "/api/v1/admin/server-catalog/publication-readiness"},
            {"kind": "admin_api", "path": "/api/v1/admin/server-catalog/provisioning-readiness"},
            {"kind": "admin_api", "path": "/api/v1/admin/server-health"},
            {"kind": "public_api", "path": "/api/v1/catalog/servers", "expected": "managed endpoints hidden"},
        ],
        "clientImpact": (
            "Можно заранее описывать и проверять новые VPS в админке, но пользователи "
            "Windows MVP не увидят их до отдельной безопасной публикации."
        ),
    }


def build_server_provisioning_readiness(
    public_catalog: Optional[dict] = None,
    managed_entries: Optional[list[dict]] = None,
) -> dict:
    public_catalog = public_catalog or build_server_catalog()
    if managed_entries is None:
        managed_entries = list_managed_server_catalog_entries(
            status="all",
            active="all",
            public="all",
            limit=500,
            offset=0,
        )
    public_servers = public_catalog.get("servers") or []
    public_server_ids = [str(server.get("id") or "") for server in public_servers]
    default_server_id = str(public_catalog.get("defaultServerId") or "intelligent_smew")
    default_server = next(
        (server for server in public_servers if server.get("id") == default_server_id),
        None,
    )
    expected_endpoint = f"{WG_ENDPOINT_HOST}:{WG_ENDPOINT_PORT}"

    def public_endpoint_string(server: Optional[dict]) -> str:
        if not server:
            return ""
        endpoint = server.get("endpoint")
        if isinstance(endpoint, dict):
            host = str(endpoint.get("host") or "").strip()
            port = endpoint.get("port")
            return f"{host}:{port}" if host and port else ""
        return str(endpoint or "").strip()

    default_endpoint = public_endpoint_string(default_server)
    default_endpoint_matches = bool(default_server) and default_endpoint == expected_endpoint
    managed_visible_to_client = [
        entry
        for entry in managed_entries
        if str(entry.get("serverId") or "") in public_server_ids
    ]
    config_ready_managed = [
        entry for entry in managed_entries if entry.get("clientConfigReady")
    ]
    current_wg0 = next(
        (entry for entry in managed_entries if entry.get("serverId") == "current_wg0"),
        None,
    )
    current_wg0_ready = bool(current_wg0 and current_wg0.get("clientConfigReady"))
    checks: list[dict] = []

    def add_check(code: str, title: str, ok: bool, message: str, warning: bool = False) -> None:
        checks.append(
            {
                "code": code,
                "title": title,
                "ok": bool(ok),
                "warning": bool(warning),
                "message": message,
            }
        )

    add_check(
        "public_default_server_present",
        "Default server есть в публичном catalog",
        bool(default_server),
        f"defaultServerId={default_server_id}.",
    )
    add_check(
        "client_config_builder_matches_public_default",
        "Client config builder совпадает с публичным endpoint",
        default_endpoint_matches,
        (
            f"Публичный default endpoint совпадает с backend wg0 {expected_endpoint}."
            if default_endpoint_matches
            else (
                "Публичный default endpoint должен совпадать с backend wg0 "
                f"{expected_endpoint}; сейчас {default_endpoint or 'не задан'}."
            )
        ),
    )
    add_check(
        "client_selection_is_public_catalog_only",
        "Выбор serverId ограничен публичным catalog",
        True,
        "Клиентский /api/v1/client/config принимает только auto/default и public catalog ids.",
    )
    add_check(
        "managed_entries_not_client_visible",
        "Managed endpoints не видны клиенту",
        len(managed_visible_to_client) == 0,
        (
            "Managed entries отсутствуют в публичном catalog."
            if not managed_visible_to_client
            else "Managed entries попали в публичный catalog и требуют ручной проверки."
        ),
    )
    add_check(
        "current_wg0_seeded",
        "current_wg0 есть во внутреннем catalog",
        bool(current_wg0),
        (
            "current_wg0 найден во внутреннем managed catalog."
            if current_wg0
            else "Нужно выполнить seed-current перед проверкой текущего endpoint."
        ),
        warning=not bool(current_wg0),
    )
    add_check(
        "current_wg0_config_ready",
        "current_wg0 готов как builtin_wg0 профиль",
        current_wg0_ready,
        (
            "current_wg0 готов к выдаче через существующий wg0 config builder."
            if current_wg0_ready
            else "current_wg0 пока не прошёл clientConfigReadiness."
        ),
        warning=not current_wg0_ready,
    )
    add_check(
        "multi_endpoint_provisioning_locked",
        "Новые endpoint закрыты до отдельного provisioning",
        True,
        "Внешние managed VPS не выдаются пользователям через текущий builtin_wg0 профиль.",
        warning=True,
    )
    new_server_draft_gate_ready = (
        bool(default_server)
        and default_endpoint_matches
        and len(managed_visible_to_client) == 0
    )
    add_check(
        "new_vps_internal_draft_gate",
        "Новый VPS можно готовить только как внутренний черновик",
        new_server_draft_gate_ready,
        (
            "Безопасно заводить новый VPS в managed catalog как draft/isPublic=false/clientConfigProfile=none."
            if new_server_draft_gate_ready
            else "Перед добавлением нового VPS нужно вернуть public catalog и default endpoint в безопасное состояние."
        ),
        warning=not new_server_draft_gate_ready,
    )

    selection_cases = [
        {
            "requestServerId": "auto",
            "allowed": bool(default_server),
            "selectedServerId": default_server_id if default_server else "",
            "reason": "default_public_catalog",
        },
        {
            "requestServerId": default_server_id,
            "allowed": bool(default_server),
            "selectedServerId": default_server_id if default_server else "",
            "reason": "explicit_public_catalog",
        },
        {
            "requestServerId": "current_wg0",
            "allowed": False,
            "selectedServerId": "",
            "reason": (
                "managed_not_published"
                if current_wg0
                else "unknown_to_public_catalog"
            ),
        },
        {
            "requestServerId": "unknown_server",
            "allowed": False,
            "selectedServerId": "",
            "reason": "unknown_to_public_catalog",
        },
    ]

    failed_required = [
        check
        for check in checks
        if not check["ok"] and check["code"] not in {"current_wg0_seeded", "current_wg0_config_ready"}
    ]
    warnings = [check for check in checks if check.get("warning") or not check["ok"]]
    safe_for_current_client = len(failed_required) == 0
    new_server_onboarding_plan = build_new_server_onboarding_plan(
        public_catalog=public_catalog,
        managed_entries=managed_entries,
        expected_endpoint=expected_endpoint,
        safe_for_current_client=safe_for_current_client,
    )
    return {
        "ok": True,
        "version": APP_VERSION,
        "generatedAt": utc_now_iso(),
        "safeForCurrentClient": safe_for_current_client,
        "currentEndpointConfigReady": current_wg0_ready,
        "multiEndpointProvisioningReady": False,
        "newVpsOnboardingReady": bool(new_server_onboarding_plan["safeToCreateInternalDraft"]),
        "publicCatalogUnchanged": True,
        "clientConfigContract": {
            "route": "/api/v1/client/config",
            "selectionPolicy": "public_catalog_only",
            "acceptedServerIds": ["auto", *public_server_ids],
            "defaultServerId": default_server_id,
            "configProfile": "builtin_wg0",
            "endpoint": expected_endpoint,
            "managedCatalogClientVisible": False,
            "unknownManagedBehavior": "400 Unknown serverId",
        },
        "summary": {
            "green": len(checks) - len(warnings),
            "yellow": len(warnings),
            "red": len(failed_required),
            "message": (
                "Client config выдаётся только через безопасный публичный catalog."
                if safe_for_current_client
                else "Client config serverId gate требует исправления перед публикацией."
            ),
        },
        "checks": checks,
        "selectionCases": selection_cases,
        "managedConfigReadyEntries": [
            {
                "serverId": entry.get("serverId"),
                "title": entry.get("title"),
                "clientConfigProfile": entry.get("clientConfigProfile"),
                "isPublic": entry.get("isPublic"),
                "publicEligible": entry.get("publicEligible"),
            }
            for entry in config_ready_managed
        ],
        "blockedManagedEntries": [
            {
                "serverId": entry.get("serverId"),
                "title": entry.get("title"),
                "clientConfigProfile": entry.get("clientConfigProfile"),
                "clientConfigReady": entry.get("clientConfigReady"),
                "publicBlockers": entry.get("publicBlockers") or [],
            }
            for entry in managed_entries
            if not entry.get("publicEligible")
        ],
        "newServerOnboardingPlan": new_server_onboarding_plan,
        "nextActions": [
            {
                "code": "keep_public_catalog_safe",
                "title": "Не публиковать managed endpoints автоматически",
                "owner": "codex",
                "detail": "Перед multi-endpoint нужны отдельные peer/config rules, probes и staged rollout.",
            },
            {
                "code": "prepare_next_vps_as_internal_draft",
                "title": "Готовить следующий VPS только как внутренний draft",
                "owner": "codex",
                "detail": (
                    "Сначала DNS/health/probe/inventory, затем отдельная выдача конфигов; "
                    "публичный catalog не меняется."
                ),
            }
        ],
    }


def normalize_optional_nonnegative_int(
    value: Optional[int],
    max_value: int = 1_000_000,
) -> Optional[int]:
    if value is None:
        return None
    try:
        parsed = int(value)
    except Exception:
        raise HTTPException(status_code=400, detail="Expected numeric planning value.")
    return max(0, min(parsed, max_value))


def safe_new_server_draft_entry_input(payload: AdminServerCatalogDraftIn) -> AdminServerCatalogEntryIn:
    server_id = normalize_server_id(payload.serverId)
    title = clean_limited_text(payload.title, 120).strip()
    if not title:
        raise HTTPException(status_code=400, detail="title is required.")
    country = clean_limited_text(payload.country, 8).strip().upper()
    if not country:
        raise HTTPException(status_code=400, detail="country is required.")
    host = normalize_server_host(payload.host)
    port = normalize_server_port(payload.port or WG_ENDPOINT_PORT)
    bandwidth_mbps = normalize_optional_nonnegative_int(payload.plannedBandwidthMbps, 100_000)
    monthly_cost_rub = normalize_optional_nonnegative_int(payload.monthlyCostRub, 100_000_000)
    note_parts = []
    base_notes = clean_limited_text(payload.notes, 700).strip()
    if base_notes:
        note_parts.append(base_notes)
    if bandwidth_mbps:
        note_parts.append(f"Planned bandwidth: {bandwidth_mbps} Mbps.")
    if monthly_cost_rub:
        note_parts.append(f"Monthly VPS cost: {monthly_cost_rub} RUB.")
    note_parts.append(
        "Created via safe new VPS draft workflow: internal-only, inactive, not public, clientConfigProfile=none."
    )
    return AdminServerCatalogEntryIn(
        serverId=server_id,
        title=title,
        subtitle=(
            clean_limited_text(payload.subtitle, 180).strip()
            or "Внутренний черновик нового VPN endpoint Green VPN"
        ),
        country=country,
        city=clean_limited_text(payload.city, 80).strip(),
        provider=clean_limited_text(payload.provider, 120).strip(),
        host=host,
        port=port,
        protocol="wireguard_udp",
        transport="udp",
        clientConfigProfile="none",
        status="draft",
        healthScore=0,
        latencyMs=None,
        priority=100,
        isActive=False,
        isPublic=False,
        notes="\n".join(note_parts),
    )


def upsert_managed_server_catalog_entry(
    payload: AdminServerCatalogEntryIn,
    entry_id: Optional[int] = None,
) -> dict:
    now = utc_now_iso()
    server_id = normalize_server_id(payload.serverId)
    title = clean_limited_text(payload.title, 120).strip()
    if not title:
        raise HTTPException(status_code=400, detail="title is required.")
    country = clean_limited_text(payload.country, 8).strip().upper()
    if not country:
        raise HTTPException(status_code=400, detail="country is required.")
    host = normalize_server_host(payload.host)
    port = normalize_server_port(payload.port)
    protocol = normalize_server_catalog_protocol(payload.protocol)
    transport = normalize_server_catalog_transport(payload.transport)
    client_config_profile = normalize_server_client_config_profile(payload.clientConfigProfile)
    status = normalize_server_catalog_status(payload.status)
    health_score = normalize_percentish(payload.healthScore, 0)
    latency_ms = None
    if payload.latencyMs is not None:
        latency_ms = max(0, min(int(payload.latencyMs), 600000))
    priority = normalize_priority(payload.priority, 100)
    is_active = 1 if payload.isActive else 0
    is_public = 1 if payload.isPublic else 0
    publication_reset = is_public == 1

    with db() as conn:
        if entry_id is not None:
            exists = conn.execute(
                "SELECT id FROM server_catalog_entries WHERE id = ?",
                (entry_id,),
            ).fetchone()
            if exists is None:
                raise HTTPException(status_code=404, detail="Server catalog entry not found.")
            duplicate = conn.execute(
                """
                SELECT id FROM server_catalog_entries
                WHERE server_id = ? AND id != ?
                """,
                (server_id, entry_id),
            ).fetchone()
            if duplicate is not None:
                raise HTTPException(status_code=409, detail="serverId already exists.")
            conn.execute(
                """
                UPDATE server_catalog_entries
                SET server_id = ?, title = ?, subtitle = ?, country = ?, city = ?,
                    provider = ?, host = ?, port = ?, protocol = ?, transport = ?,
                    client_config_profile = ?, status = ?, health_score = ?, latency_ms = ?, priority = ?,
                    is_active = ?, is_public = ?, notes = ?,
                    publication_paused_at = CASE WHEN ? THEN NULL ELSE publication_paused_at END,
                    publication_paused_reason = CASE WHEN ? THEN NULL ELSE publication_paused_reason END,
                    publication_paused_by = CASE WHEN ? THEN NULL ELSE publication_paused_by END,
                    updated_at = ?
                WHERE id = ?
                """,
                (
                    server_id,
                    title,
                    clean_limited_text(payload.subtitle, 180).strip(),
                    country,
                    clean_limited_text(payload.city, 80).strip(),
                    clean_limited_text(payload.provider, 120).strip(),
                    host,
                    port,
                    protocol,
                    transport,
                    client_config_profile,
                    status,
                    health_score,
                    latency_ms,
                    priority,
                    is_active,
                    is_public,
                    clean_limited_text(payload.notes, 1000).strip(),
                    1 if publication_reset else 0,
                    1 if publication_reset else 0,
                    1 if publication_reset else 0,
                    now,
                    entry_id,
                ),
            )
            row_id = entry_id
        else:
            existing = conn.execute(
                "SELECT id FROM server_catalog_entries WHERE server_id = ?",
                (server_id,),
            ).fetchone()
            if existing is not None:
                raise HTTPException(status_code=409, detail="serverId already exists.")
            cur = conn.execute(
                """
                INSERT INTO server_catalog_entries(
                    server_id, title, subtitle, country, city, provider, host, port,
                    protocol, transport, client_config_profile, status, health_score, latency_ms, priority,
                    is_active, is_public, notes, created_at, updated_at
                )
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                (
                    server_id,
                    title,
                    clean_limited_text(payload.subtitle, 180).strip(),
                    country,
                    clean_limited_text(payload.city, 80).strip(),
                    clean_limited_text(payload.provider, 120).strip(),
                    host,
                    port,
                    protocol,
                    transport,
                    client_config_profile,
                    status,
                    health_score,
                    latency_ms,
                    priority,
                    is_active,
                    is_public,
                    clean_limited_text(payload.notes, 1000).strip(),
                    now,
                    now,
                ),
            )
            row_id = int(cur.lastrowid)
        conn.commit()
        row = conn.execute(
            "SELECT * FROM server_catalog_entries WHERE id = ?",
            (row_id,),
        ).fetchone()
        health_meta = server_health_meta_for_entries(conn, [row["server_id"]])
    return server_catalog_entry_payload(row, health_meta.get(row["server_id"]))


def current_wireguard_managed_server_payload() -> AdminServerCatalogEntryIn:
    return AdminServerCatalogEntryIn(
        serverId="current_wg0",
        title="Netherlands #1",
        subtitle="Текущий рабочий WireGuard endpoint Green VPN",
        country="NL",
        city="Amsterdam",
        provider="current-dev-provider",
        host=WG_ENDPOINT_HOST,
        port=WG_ENDPOINT_PORT,
        protocol="wireguard_udp",
        transport="udp",
        clientConfigProfile="builtin_wg0",
        status="healthy",
        healthScore=95,
        latencyMs=44,
        priority=10,
        isActive=True,
        isPublic=False,
        notes=(
            "Seeded from backend environment. Safe internal managed entry: "
            "client config profile is ready, but public candidate is intentionally off."
        ),
    )


def upsert_current_wireguard_managed_server() -> dict:
    payload = current_wireguard_managed_server_payload()
    with db() as conn:
        existing = conn.execute(
            "SELECT id FROM server_catalog_entries WHERE server_id = ?",
            (payload.serverId,),
        ).fetchone()
    return upsert_managed_server_catalog_entry(
        payload,
        int(existing["id"]) if existing is not None else None,
    )


def normalize_server_health_endpoint_id(value: Optional[str]) -> str:
    endpoint_id = clean_limited_text(value, 120).strip().lower()
    if not endpoint_id:
        raise HTTPException(status_code=400, detail="endpointId is required.")
    if not re.fullmatch(r"[a-z0-9][a-z0-9_-]{2,119}", endpoint_id):
        raise HTTPException(
            status_code=400,
            detail="endpointId must contain latin letters, numbers, dash or underscore.",
        )
    return endpoint_id


def normalize_server_health_status(value: Optional[str], ok: Optional[bool] = None) -> str:
    candidate = clean_limited_text(value, 40).strip().lower()
    if not candidate:
        if ok is True:
            candidate = "healthy"
        elif ok is False:
            candidate = "down"
        else:
            candidate = "unknown"
    if candidate not in SERVER_HEALTH_STATUSES:
        raise HTTPException(status_code=400, detail="Unknown server health status.")
    return candidate


def normalize_latency_ms(value: Optional[int]) -> Optional[int]:
    if value is None:
        return None
    try:
        parsed = int(value)
    except Exception:
        raise HTTPException(status_code=400, detail="latencyMs must be a number.")
    return max(0, min(parsed, 600000))


def normalize_packet_loss(value: Optional[float]) -> Optional[float]:
    if value is None:
        return None
    try:
        parsed = float(value)
    except Exception:
        raise HTTPException(status_code=400, detail="packetLossPercent must be a number.")
    return max(0.0, min(parsed, 100.0))


def server_health_observation_payload(row: sqlite3.Row) -> dict:
    try:
        details = json.loads(row["details_json"] or "{}")
    except Exception:
        details = {}
    details = sanitize_monitoring_details(details)
    return {
        "id": int(row["id"]),
        "endpointId": row["endpoint_id"],
        "probeId": row["probe_id"] or "",
        "probeRegion": row["probe_region"] or "",
        "protocol": row["protocol"] or "",
        "transport": row["transport"] or "",
        "target": row["target"] or "",
        "ok": bool(row["ok"]),
        "status": row["status"],
        "latencyMs": int(row["latency_ms"]) if row["latency_ms"] is not None else None,
        "packetLossPercent": (
            float(row["packet_loss_percent"])
            if row["packet_loss_percent"] is not None
            else None
        ),
        "errorCode": row["error_code"] or "",
        "message": row["message"] or "",
        "details": details,
        "observedAt": row["observed_at"],
        "createdAt": row["created_at"],
    }


def server_health_score_from_details(details: dict, status: str) -> int:
    raw_score = details.get("score") if isinstance(details, dict) else None
    try:
        score = int(raw_score)
        return max(0, min(score, 100))
    except Exception:
        return 100 if status == "healthy" else 55 if status == "degraded" else 0


def server_catalog_public_pause_reasons(status: str, health_score: int) -> list[str]:
    reasons: list[str] = []
    if status in {"down", "degraded"}:
        reasons.append(f"latest health status is {status}")
    if health_score < SERVER_PUBLIC_MIN_HEALTH_SCORE:
        reasons.append(
            f"health score {health_score}% below {SERVER_PUBLIC_MIN_HEALTH_SCORE}%"
        )
    return reasons


def maybe_pause_public_server_candidate(
    conn: sqlite3.Connection,
    endpoint_id: str,
    status: str,
    health_score: int,
    observed_at: str,
) -> Optional[dict]:
    if not SERVER_PUBLIC_AUTO_PAUSE_ENABLED:
        return None
    reasons = server_catalog_public_pause_reasons(status, health_score)
    if not reasons:
        return None
    row = conn.execute(
        """
        SELECT id, server_id, title, is_public
        FROM server_catalog_entries
        WHERE server_id = ?
        """,
        (endpoint_id,),
    ).fetchone()
    if row is None or not bool(row["is_public"]):
        return None
    reason = "; ".join(reasons)
    now = utc_now_iso()
    conn.execute(
        """
        UPDATE server_catalog_entries
        SET is_public = 0,
            publication_paused_at = ?,
            publication_paused_reason = ?,
            publication_paused_by = 'health_gate',
            updated_at = ?
        WHERE id = ?
        """,
        (now, reason, now, int(row["id"])),
    )
    return {
        "serverId": row["server_id"],
        "title": row["title"],
        "status": status,
        "healthScore": health_score,
        "observedAt": observed_at,
        "reason": reason,
    }


def create_server_health_observation(payload: AdminServerHealthObservationIn) -> dict:
    endpoint_id = normalize_server_health_endpoint_id(payload.endpointId)
    ok = bool(payload.ok) if payload.ok is not None else False
    status = normalize_server_health_status(payload.status, ok)
    protocol = clean_limited_text(payload.protocol, 40).strip().lower()
    transport = clean_limited_text(payload.transport, 40).strip().lower()
    probe_id = clean_limited_text(payload.probeId, 80).strip()
    probe_region = clean_limited_text(payload.probeRegion, 80).strip()
    target = clean_limited_text(payload.target, 250).strip()
    latency_ms = normalize_latency_ms(payload.latencyMs)
    packet_loss_percent = normalize_packet_loss(payload.packetLossPercent)
    message = clean_limited_text(payload.message, 500).strip()
    error_code = clean_limited_text(payload.errorCode, 80).strip()
    observed_at = payload.observedAt.strip() if payload.observedAt else utc_now_iso()
    if parse_dt(observed_at) is None:
        raise HTTPException(status_code=400, detail="observedAt must be an ISO datetime.")
    details = sanitize_monitoring_details(payload.details)
    try:
        details_json = json.dumps(details, ensure_ascii=False)
    except Exception:
        details = {}
        details_json = "{}"
    now = utc_now_iso()

    paused_public_candidate: Optional[dict] = None
    with db() as conn:
        cur = conn.execute(
            """
            INSERT INTO server_health_observations(
                endpoint_id, probe_id, probe_region, protocol, transport, target,
                ok, status, latency_ms, packet_loss_percent, error_code, message,
                details_json, observed_at, created_at
            )
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            (
                endpoint_id,
                probe_id,
                probe_region,
                protocol,
                transport,
                target,
                1 if ok else 0,
                status,
                latency_ms,
                packet_loss_percent,
                error_code,
                message,
                details_json,
                observed_at,
                now,
            ),
        )

        health_score = server_health_score_from_details(details, status)
        conn.execute(
            """
            UPDATE server_catalog_entries
            SET status = CASE
                    WHEN ? = 'down' THEN 'degraded'
                    WHEN ? = 'unknown' THEN status
                    ELSE ?
                END,
                health_score = ?,
                latency_ms = COALESCE(?, latency_ms),
                updated_at = ?
            WHERE server_id = ?
            """,
            (
                status,
                status,
                status if status in {"healthy", "degraded", "maintenance", "disabled"} else "degraded",
                health_score,
                latency_ms,
                now,
                endpoint_id,
            ),
        )
        paused_public_candidate = maybe_pause_public_server_candidate(
            conn,
            endpoint_id,
            status,
            health_score,
            observed_at,
        )
        conn.commit()
        row = conn.execute(
            "SELECT * FROM server_health_observations WHERE id = ?",
            (int(cur.lastrowid),),
        ).fetchone()
    if paused_public_candidate is not None:
        write_admin_audit(
            "server_catalog_public_candidate_auto_paused",
            "server_catalog_entry",
            endpoint_id,
            paused_public_candidate,
            actor="health_gate",
        )
    observation = server_health_observation_payload(row)
    sync_server_health_observation_incident(observation)
    return observation


def run_probe_command(args: list[str], timeout_seconds: float = 3.0) -> dict:
    started = time.monotonic()
    try:
        completed = subprocess.run(
            args,
            text=True,
            capture_output=True,
            check=False,
            timeout=timeout_seconds,
        )
        return {
            "ok": completed.returncode == 0,
            "returnCode": completed.returncode,
            "stdout": clean_limited_text(completed.stdout, 2000),
            "stderr": clean_limited_text(completed.stderr, 2000),
            "elapsedMs": round((time.monotonic() - started) * 1000),
        }
    except FileNotFoundError:
        return {
            "ok": False,
            "error": "command_not_found",
            "elapsedMs": round((time.monotonic() - started) * 1000),
        }
    except subprocess.TimeoutExpired:
        return {
            "ok": False,
            "error": "timeout",
            "elapsedMs": round((time.monotonic() - started) * 1000),
        }
    except Exception as exc:
        return {
            "ok": False,
            "error": exc.__class__.__name__,
            "message": clean_limited_text(str(exc), 300),
            "elapsedMs": round((time.monotonic() - started) * 1000),
        }


def parse_wireguard_latest_handshakes(output: str) -> dict:
    now_ts = int(time.time())
    latest_ts = 0
    peers = 0
    peers_with_handshake = 0
    for line in (output or "").splitlines():
        parts = line.strip().split()
        if len(parts) < 2:
            continue
        peers += 1
        try:
            handshake_ts = int(parts[-1])
        except Exception:
            handshake_ts = 0
        if handshake_ts > 0:
            peers_with_handshake += 1
            latest_ts = max(latest_ts, handshake_ts)
    return {
        "peers": peers,
        "peersWithHandshake": peers_with_handshake,
        "latestHandshakeSecondsAgo": (now_ts - latest_ts) if latest_ts > 0 else None,
    }


def udp_endpoint_socket_probe(host: str, port: int, timeout_seconds: float = 2.0) -> dict:
    started = time.monotonic()
    try:
        with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as sock:
            sock.settimeout(timeout_seconds)
            sock.connect((host, int(port)))
            sock.send(b"")
        return {
            "ok": True,
            "elapsedMs": round((time.monotonic() - started) * 1000),
        }
    except Exception as exc:
        return {
            "ok": False,
            "error": exc.__class__.__name__,
            "message": clean_limited_text(str(exc), 250),
            "elapsedMs": round((time.monotonic() - started) * 1000),
        }


def build_current_wireguard_endpoint_probe() -> dict:
    started = time.monotonic()
    entry = upsert_current_wireguard_managed_server()
    readiness = entry.get("clientConfigReadiness") or {}
    checks: list[dict] = []
    penalty = 0

    def add_check(
        code: str,
        title: str,
        ok: bool,
        message: str,
        penalty_points: int = 0,
        details: Optional[dict] = None,
    ) -> None:
        nonlocal penalty
        if not ok:
            penalty += max(0, int(penalty_points or 0))
        checks.append(
            {
                "code": code,
                "title": title,
                "ok": bool(ok),
                "message": clean_limited_text(message, 400),
                "penalty": max(0, int(penalty_points or 0)) if not ok else 0,
                "details": details or {},
            }
        )

    config_exists = WG_CONFIG_PATH.exists()
    add_check(
        "wg_config_file",
        "Файл WireGuard-конфига",
        config_exists,
        f"{WG_CONFIG_PATH} найден." if config_exists else f"{WG_CONFIG_PATH} не найден.",
        penalty_points=35,
    )

    readiness_ok = bool(readiness.get("ready"))
    add_check(
        "client_config_profile_ready",
        "Профиль выдачи клиентского конфига",
        readiness_ok,
        "Профиль builtin_wg0 готов к выдаче текущего endpoint."
        if readiness_ok
        else "Профиль builtin_wg0 пока не готов к безопасной выдаче клиентам.",
        penalty_points=25,
        details={
            "blockers": readiness.get("blockers") or [],
            "warnings": readiness.get("warnings") or [],
        },
    )

    wg_public_key_check = run_probe_command(["wg", "show", WG_INTERFACE, "public-key"])
    add_check(
        "wg_interface_readable",
        "WireGuard interface читается",
        bool(wg_public_key_check.get("ok")),
        f"{WG_INTERFACE} отвечает на wg show."
        if wg_public_key_check.get("ok")
        else f"Не удалось прочитать {WG_INTERFACE} через wg show.",
        penalty_points=35,
        details={
            "returnCode": wg_public_key_check.get("returnCode"),
            "error": wg_public_key_check.get("error"),
            "stderr": wg_public_key_check.get("stderr"),
            "elapsedMs": wg_public_key_check.get("elapsedMs"),
        },
    )

    ip_link_check = run_probe_command(["ip", "link", "show", WG_INTERFACE])
    add_check(
        "linux_interface_exists",
        "Linux interface существует",
        bool(ip_link_check.get("ok")),
        f"Интерфейс {WG_INTERFACE} есть в ip link."
        if ip_link_check.get("ok")
        else f"ip link не подтвердил интерфейс {WG_INTERFACE}.",
        penalty_points=15,
        details={
            "returnCode": ip_link_check.get("returnCode"),
            "error": ip_link_check.get("error"),
            "stderr": ip_link_check.get("stderr"),
            "elapsedMs": ip_link_check.get("elapsedMs"),
        },
    )

    peers_check = run_probe_command(["wg", "show", WG_INTERFACE, "peers"])
    peers = 0
    if peers_check.get("ok"):
        peers = len([line for line in str(peers_check.get("stdout") or "").splitlines() if line.strip()])
    add_check(
        "wg_peers_present",
        "WireGuard peers",
        peers > 0,
        f"В {WG_INTERFACE} есть peers: {peers}."
        if peers > 0
        else f"В {WG_INTERFACE} нет peers или wg peers недоступен.",
        penalty_points=20,
        details={
            "peers": peers,
            "returnCode": peers_check.get("returnCode"),
            "error": peers_check.get("error"),
            "stderr": peers_check.get("stderr"),
            "elapsedMs": peers_check.get("elapsedMs"),
        },
    )

    latest_handshake_check = run_probe_command(
        ["wg", "show", WG_INTERFACE, "latest-handshakes"]
    )
    handshake_meta = (
        parse_wireguard_latest_handshakes(str(latest_handshake_check.get("stdout") or ""))
        if latest_handshake_check.get("ok")
        else {"peers": 0, "peersWithHandshake": 0, "latestHandshakeSecondsAgo": None}
    )
    latest_handshake_seconds = handshake_meta.get("latestHandshakeSecondsAgo")
    recent_handshake_limit = 15 * 60
    recent_handshake = (
        latest_handshake_seconds is not None
        and int(latest_handshake_seconds) <= recent_handshake_limit
    )
    add_check(
        "recent_handshake",
        "Свежий handshake",
        bool(recent_handshake),
        (
            f"Последний handshake был {latest_handshake_seconds} сек. назад."
            if recent_handshake
            else "Свежего handshake за последние 15 минут не видно."
        ),
        penalty_points=10,
        details={
            **handshake_meta,
            "recentLimitSeconds": recent_handshake_limit,
            "returnCode": latest_handshake_check.get("returnCode"),
            "error": latest_handshake_check.get("error"),
            "stderr": latest_handshake_check.get("stderr"),
            "elapsedMs": latest_handshake_check.get("elapsedMs"),
        },
    )

    udp_probe = udp_endpoint_socket_probe(WG_ENDPOINT_HOST, WG_ENDPOINT_PORT)
    add_check(
        "udp_socket_route",
        "UDP socket до endpoint",
        bool(udp_probe.get("ok")),
        f"Локальный UDP socket до {WG_ENDPOINT_HOST}:{WG_ENDPOINT_PORT} открывается."
        if udp_probe.get("ok")
        else f"Не удалось открыть UDP socket до {WG_ENDPOINT_HOST}:{WG_ENDPOINT_PORT}.",
        penalty_points=10,
        details={
            "error": udp_probe.get("error"),
            "message": udp_probe.get("message"),
            "elapsedMs": udp_probe.get("elapsedMs"),
        },
    )

    score = max(0, min(100, 100 - penalty))
    if score >= 80:
        status = "healthy"
    elif score >= 50:
        status = "degraded"
    else:
        status = "down"
    failed_codes = [item["code"] for item in checks if not item["ok"]]
    if status == "healthy":
        message = f"Текущий endpoint здоров: score={score}, wg0 читается, профиль конфига готов."
        error_code = ""
    elif status == "degraded":
        message = f"Текущий endpoint требует внимания: score={score}, проблемы: {', '.join(failed_codes[:4])}."
        error_code = failed_codes[0] if failed_codes else "degraded"
    else:
        message = f"Текущий endpoint не прошёл проверку: score={score}, проблемы: {', '.join(failed_codes[:4])}."
        error_code = failed_codes[0] if failed_codes else "down"

    latency_ms = round((time.monotonic() - started) * 1000)
    details = {
        "score": score,
        "probeKind": "server_side_local",
        "safeForPublicRouting": False,
        "note": (
            "Это server-side проверка backend/VPN-сервера. Она не заменяет внешний "
            "probe из сети пользователя, но помогает заранее видеть поломки wg0/config."
        ),
        "endpoint": {
            "serverId": entry.get("serverId"),
            "host": WG_ENDPOINT_HOST,
            "port": WG_ENDPOINT_PORT,
            "interface": WG_INTERFACE,
            "clientConfigProfile": entry.get("clientConfigProfile"),
            "clientConfigReady": entry.get("clientConfigReady"),
        },
        "wireguard": {
            "configExists": config_exists,
            "peers": peers,
            "peersWithHandshake": handshake_meta.get("peersWithHandshake"),
            "latestHandshakeSecondsAgo": latest_handshake_seconds,
        },
        "checks": checks,
    }
    observation = create_server_health_observation(
        AdminServerHealthObservationIn(
            endpointId=str(entry.get("serverId") or "current_wg0"),
            probeId="backend-local",
            probeRegion="backend",
            protocol="wireguard_udp",
            transport="udp",
            target=f"{WG_ENDPOINT_HOST}:{WG_ENDPOINT_PORT}",
            ok=status == "healthy",
            status=status,
            latencyMs=latency_ms,
            packetLossPercent=None,
            errorCode=error_code,
            message=message,
            details=details,
            observedAt=utc_now_iso(),
        )
    )
    return {
        "entry": entry,
        "observation": observation,
        "score": score,
        "status": status,
        "checks": checks,
        "message": message,
    }


def list_server_health_observations(
    endpoint_id: Optional[str] = None,
    status: Optional[str] = None,
    limit: int = 120,
) -> list[dict]:
    where = []
    params: list[object] = []
    if endpoint_id:
        where.append("endpoint_id = ?")
        params.append(normalize_server_health_endpoint_id(endpoint_id))
    if status and status != "all":
        where.append("status = ?")
        params.append(normalize_server_health_status(status))
    sql = "SELECT * FROM server_health_observations"
    if where:
        sql += " WHERE " + " AND ".join(where)
    sql += " ORDER BY observed_at DESC, id DESC LIMIT ?"
    params.append(max(1, min(int(limit or 120), 500)))
    with db() as conn:
        rows = conn.execute(sql, tuple(params)).fetchall()
    return [server_health_observation_payload(row) for row in rows]


def is_external_server_health_probe(probe_id: Optional[str], probe_region: Optional[str]) -> bool:
    normalized_id = (probe_id or "").strip().lower()
    normalized_region = (probe_region or "").strip().lower()
    return normalized_id != "backend-local" and normalized_region != "backend"


def list_server_health_probe_agents(limit: int = 100) -> list[dict]:
    since_24h = (utc_now() - timedelta(hours=24)).isoformat()
    stale_cutoff = utc_now() - timedelta(seconds=SERVICE_PROBE_STALE_AFTER_SECONDS)
    safe_limit = max(1, min(int(limit or 100), 500))
    with db() as conn:
        rows = conn.execute(
            """
            SELECT
                COALESCE(NULLIF(probe_id, ''), 'unknown') AS probe_id_norm,
                COALESCE(NULLIF(probe_region, ''), 'unknown') AS probe_region_norm,
                MAX(observed_at) AS last_seen_at,
                COUNT(*) AS total_observations,
                COUNT(DISTINCT endpoint_id) AS endpoints_observed,
                SUM(CASE WHEN observed_at >= ? THEN 1 ELSE 0 END) AS observations_24h,
                SUM(
                    CASE
                        WHEN observed_at >= ? AND status IN ('degraded', 'down')
                        THEN 1 ELSE 0
                    END
                ) AS problems_24h,
                SUM(CASE WHEN status = 'healthy' THEN 1 ELSE 0 END) AS healthy_total,
                SUM(CASE WHEN status = 'degraded' THEN 1 ELSE 0 END) AS degraded_total,
                SUM(CASE WHEN status = 'down' THEN 1 ELSE 0 END) AS down_total,
                SUM(CASE WHEN status = 'unknown' THEN 1 ELSE 0 END) AS unknown_total
            FROM server_health_observations
            GROUP BY probe_id_norm, probe_region_norm
            ORDER BY last_seen_at DESC
            LIMIT ?
            """,
            (since_24h, since_24h, safe_limit),
        ).fetchall()
        latest_rows = conn.execute(
            """
            SELECT *
            FROM server_health_observations
            ORDER BY observed_at DESC, id DESC
            LIMIT 2000
            """
        ).fetchall()

    latest_by_probe: dict[tuple[str, str], dict] = {}
    for row in latest_rows:
        payload = server_health_observation_payload(row)
        key = (
            payload.get("probeId") or "unknown",
            payload.get("probeRegion") or "unknown",
        )
        latest_by_probe.setdefault(key, payload)

    probes: list[dict] = []
    for row in rows:
        probe_id = row["probe_id_norm"] or "unknown"
        probe_region = row["probe_region_norm"] or "unknown"
        latest = latest_by_probe.get((probe_id, probe_region))
        last_seen_at = row["last_seen_at"] or ""
        last_seen_dt = parse_dt(last_seen_at)
        is_stale = True
        if last_seen_dt is not None:
            if last_seen_dt.tzinfo is None:
                last_seen_dt = last_seen_dt.replace(tzinfo=timezone.utc)
            is_stale = last_seen_dt < stale_cutoff
        last_status = (latest or {}).get("status") or "unknown"
        probes.append(
            {
                "probeId": probe_id,
                "probeRegion": probe_region,
                "isExternal": is_external_server_health_probe(probe_id, probe_region),
                "lastSeenAt": last_seen_at,
                "isStale": is_stale,
                "staleAfterSeconds": SERVICE_PROBE_STALE_AFTER_SECONDS,
                "totalObservations": int(row["total_observations"] or 0),
                "endpointsObserved": int(row["endpoints_observed"] or 0),
                "observations24h": int(row["observations_24h"] or 0),
                "problems24h": int(row["problems_24h"] or 0),
                "healthyTotal": int(row["healthy_total"] or 0),
                "degradedTotal": int(row["degraded_total"] or 0),
                "downTotal": int(row["down_total"] or 0),
                "unknownTotal": int(row["unknown_total"] or 0),
                "lastStatus": last_status,
                "lastEndpointId": (latest or {}).get("endpointId") or "",
                "lastMessage": (latest or {}).get("message") or "",
                "lastLatencyMs": (latest or {}).get("latencyMs"),
            }
        )
    return probes


def build_server_health_external_probe_operator_plan(
    required_endpoint_ids: list[str],
    missing_endpoint_ids: list[str],
    stale_endpoint_ids: list[str],
    failed_endpoint_ids: list[str],
) -> dict:
    windows_run_once = (
        "powershell -NoProfile -ExecutionPolicy Bypass "
        "-File .\\scripts\\windows\\run_monitoring_probe_once.ps1 "
        "-ApiBase https://api.greenvpn.pro "
        "-ProbeId windows-external-check "
        "-ProbeRegion local-windows "
        "-ServerHealth "
        "-AdminTokenFromStdin"
    )
    linux_run_once = (
        "python3 scripts/monitoring/service_probe.py "
        "--api-base https://api.greenvpn.pro "
        "--probe-id probe-eu-1 "
        "--probe-region eu "
        "--server-health "
        "--admin-token-stdin"
    )
    install_command = (
        "bash scripts/monitoring/install_probe_systemd.sh "
        "--api-base https://api.greenvpn.pro "
        "--probe-id probe-eu-1 "
        "--probe-region eu "
        "--interval 300 "
        "--server-health "
        "--token-stdin"
    )
    endpoints_needing_action = sorted(
        set(missing_endpoint_ids) | set(stale_endpoint_ids) | set(failed_endpoint_ids)
    )
    return {
        "mode": "safe_external_probe_operation",
        "productionRecommendation": "Use a separate monitoring VPS outside the main backend/VPN server.",
        "tokenPolicy": (
            "Admin token must be supplied through stdin or a 600-permission token file on the probe host. "
            "Never pass it in command arguments, repo files, docs, shell history, screenshots, or chat."
        ),
        "windowsRunOnceCommand": windows_run_once,
        "linuxRunOnceCommand": linux_run_once,
        "systemdInstallCommand": install_command,
        "runOnceCommands": [
            {
                "platform": "windows",
                "purpose": "Manual one-off external check from this PC/network.",
                "command": windows_run_once,
                "safeForPublicRelease": False,
            },
            {
                "platform": "linux",
                "purpose": "Manual one-off check from a monitoring VPS before installing timer.",
                "command": linux_run_once,
                "safeForPublicRelease": False,
            },
        ],
        "installBundle": {
            "platform": "linux-systemd",
            "command": install_command,
            "intervalSeconds": 300,
            "sourceFiles": [
                "scripts/monitoring/service_probe.py",
                "scripts/monitoring/install_probe_systemd.sh",
            ],
            "tokenPath": "/etc/greenvpn-monitoring/admin_token",
        },
        "requiredEndpointIds": required_endpoint_ids,
        "endpointsNeedingAction": endpoints_needing_action,
        "missingCoverageActions": [
            {
                "endpointId": endpoint_id,
                "action": "Run the external probe with --server-health until this endpoint has a fresh healthy observation.",
            }
            for endpoint_id in endpoints_needing_action
        ],
        "verifySteps": [
            "Run the command from a network outside the main backend/VPN host.",
            "Confirm GET /api/v1/admin/server-health shows the endpoint under coveredEndpointIds.",
            "Confirm the observation is healthy, fresh and has probeRegion not equal to backend.",
            "Confirm GET /api/v1/admin/monitoring/readiness still has --server-health in installCommand.",
        ],
        "safeToRunWithoutOwner": False,
        "blockedUntilOwnerProvides": [
            "admin token entered only via stdin/file",
            "separate monitoring VPS for production-grade signal",
        ],
    }


def server_health_external_probe_readiness(summary: dict) -> dict:
    managed_entries = list_managed_server_catalog_entries(
        status="all",
        active="all",
        public="all",
        limit=500,
        offset=0,
    )
    required_endpoint_ids = sorted(
        {
            entry.get("serverId")
            for entry in managed_entries
            if entry.get("serverId")
            and entry.get("isActive")
            and entry.get("clientConfigReady")
        }
    )
    max_age_hours = SERVICE_PROBE_STALE_AFTER_SECONDS / 3600.0
    probe_agents = summary.get("serverHealthProbeAgents") or []
    external_probe_agents = [item for item in probe_agents if item.get("isExternal")]
    stale_external_probe_agents = [
        item for item in external_probe_agents if item.get("isStale")
    ]
    problem_external_probe_agents = [
        item
        for item in external_probe_agents
        if int(item.get("problems24h") or 0) > 0
        or item.get("lastStatus") in {"degraded", "down"}
    ]
    since_24h = (utc_now() - timedelta(hours=24)).isoformat()
    with db() as conn:
        latest_rows = conn.execute(
            """
            SELECT *
            FROM server_health_observations
            WHERE COALESCE(NULLIF(probe_id, ''), 'unknown') != 'backend-local'
              AND COALESCE(NULLIF(probe_region, ''), 'unknown') != 'backend'
            ORDER BY observed_at DESC, id DESC
            LIMIT 2000
            """
        ).fetchall()
        external_failed_24h = int(
            conn.execute(
                """
                SELECT COUNT(*) AS cnt
                FROM server_health_observations
                WHERE observed_at >= ?
                  AND status IN ('degraded', 'down')
                  AND COALESCE(NULLIF(probe_id, ''), 'unknown') != 'backend-local'
                  AND COALESCE(NULLIF(probe_region, ''), 'unknown') != 'backend'
                """,
                (since_24h,),
            ).fetchone()["cnt"]
        )

    latest_external_by_endpoint: dict[str, dict] = {}
    for row in latest_rows:
        payload = server_health_observation_payload(row)
        latest_external_by_endpoint.setdefault(payload["endpointId"], payload)

    covered_endpoint_ids: list[str] = []
    missing_endpoint_ids: list[str] = []
    stale_endpoint_ids: list[str] = []
    failed_endpoint_ids: list[str] = []
    endpoint_snapshots: list[dict] = []

    for endpoint_id in required_endpoint_ids:
        latest = latest_external_by_endpoint.get(endpoint_id)
        if latest is None:
            missing_endpoint_ids.append(endpoint_id)
            endpoint_snapshots.append(
                {
                    "endpointId": endpoint_id,
                    "covered": False,
                    "status": "missing",
                    "observedAt": "",
                    "ageHours": None,
                    "probeId": "",
                    "probeRegion": "",
                    "score": None,
                }
            )
            continue
        covered_endpoint_ids.append(endpoint_id)
        age_hours = server_observation_age_hours(latest.get("observedAt"))
        score = None
        details = latest.get("details") if isinstance(latest.get("details"), dict) else {}
        try:
            score = int(details.get("score"))
        except Exception:
            score = None
        if age_hours is None or age_hours > max_age_hours:
            stale_endpoint_ids.append(endpoint_id)
        if latest.get("status") != "healthy" or latest.get("ok") is False:
            failed_endpoint_ids.append(endpoint_id)
        endpoint_snapshots.append(
            {
                "endpointId": endpoint_id,
                "covered": True,
                "status": latest.get("status") or "unknown",
                "observedAt": latest.get("observedAt") or "",
                "ageHours": round(float(age_hours), 2) if age_hours is not None else None,
                "probeId": latest.get("probeId") or "",
                "probeRegion": latest.get("probeRegion") or "",
                "score": score,
            }
        )

    checks: list[dict] = []

    def add_check(code: str, title: str, ok: bool, message: str, details: Optional[dict] = None) -> None:
        checks.append(
            {
                "code": code,
                "title": title,
                "ok": bool(ok),
                "message": message,
                "details": details or {},
            }
        )

    add_check(
        "required_endpoints_configured",
        "Config-ready endpoints",
        bool(required_endpoint_ids),
        "Есть config-ready endpoint для внешних server-health probes."
        if required_endpoint_ids
        else "Нет активных config-ready managed endpoint для внешней проверки.",
        {"requiredEndpointIds": required_endpoint_ids},
    )
    add_check(
        "external_probe_seen",
        "External endpoint probe",
        bool(external_probe_agents),
        "Backend уже видел внешний server-health probe."
        if external_probe_agents
        else "Нужен отдельный monitoring VPS, который присылает server-health observations.",
        {"externalProbeAgentsTotal": len(external_probe_agents)},
    )
    add_check(
        "external_probe_fresh",
        "Fresh external endpoint signal",
        bool(external_probe_agents) and not stale_external_probe_agents,
        "Внешние endpoint probes свежие."
        if external_probe_agents and not stale_external_probe_agents
        else "Внешний endpoint probe ещё не установлен или давно молчит.",
        {
            "staleAfterSeconds": SERVICE_PROBE_STALE_AFTER_SECONDS,
            "staleProbeAgents": [
                item.get("probeId") for item in stale_external_probe_agents[:10]
            ],
        },
    )
    add_check(
        "required_endpoints_covered",
        "Required endpoint coverage",
        bool(required_endpoint_ids) and not missing_endpoint_ids,
        "Все обязательные config-ready endpoint покрыты внешними observations."
        if required_endpoint_ids and not missing_endpoint_ids
        else "Не все обязательные endpoint ещё проверялись внешним probe.",
        {
            "coveredEndpointIds": covered_endpoint_ids,
            "missingEndpointIds": missing_endpoint_ids,
        },
    )
    add_check(
        "required_endpoints_fresh",
        "Required endpoint freshness",
        bool(required_endpoint_ids) and not missing_endpoint_ids and not stale_endpoint_ids,
        "Внешние endpoint observations свежие."
        if required_endpoint_ids and not missing_endpoint_ids and not stale_endpoint_ids
        else "Часть внешних endpoint observations устарела или отсутствует.",
        {"staleEndpointIds": stale_endpoint_ids},
    )
    add_check(
        "required_endpoints_healthy",
        "Required endpoint status",
        bool(required_endpoint_ids) and not missing_endpoint_ids and not failed_endpoint_ids,
        "Обязательные endpoint сейчас healthy по внешним probes."
        if required_endpoint_ids and not missing_endpoint_ids and not failed_endpoint_ids
        else "Часть обязательных endpoint не healthy или ещё не проверялась внешним probe.",
        {"failedEndpointIds": failed_endpoint_ids},
    )
    add_check(
        "external_probe_clean_24h",
        "External endpoint probe 24h",
        external_failed_24h == 0 and not problem_external_probe_agents,
        "За последние 24 часа внешний endpoint probe не видел degraded/down."
        if external_failed_24h == 0 and not problem_external_probe_agents
        else "За последние 24 часа есть внешние degraded/down endpoint observations.",
        {
            "failed24h": external_failed_24h,
            "problemProbeAgents": [
                item.get("probeId") for item in problem_external_probe_agents[:10]
            ],
        },
    )

    missing = [check for check in checks if not check["ok"]]
    operator_plan = build_server_health_external_probe_operator_plan(
        required_endpoint_ids,
        missing_endpoint_ids,
        stale_endpoint_ids,
        failed_endpoint_ids,
    )
    return {
        "productionReady": len(missing) == 0,
        "mode": "external_endpoint_probe_readiness",
        "staleAfterSeconds": SERVICE_PROBE_STALE_AFTER_SECONDS,
        "requiredEndpointIds": required_endpoint_ids,
        "coveredEndpointIds": covered_endpoint_ids,
        "missingEndpointIds": missing_endpoint_ids,
        "staleEndpointIds": stale_endpoint_ids,
        "failedEndpointIds": failed_endpoint_ids,
        "endpointSnapshots": endpoint_snapshots,
        "externalProbeAgentsTotal": len(external_probe_agents),
        "activeExternalProbeAgents": len(external_probe_agents) - len(stale_external_probe_agents),
        "staleExternalProbeAgents": len(stale_external_probe_agents),
        "problemExternalProbeAgents": len(problem_external_probe_agents),
        "externalFailed24h": external_failed_24h,
        "checks": checks,
        "operatorPlan": operator_plan,
        "runOnceCommands": operator_plan["runOnceCommands"],
        "missingCoverageActions": operator_plan["missingCoverageActions"],
        "tokenPolicy": operator_plan["tokenPolicy"],
        "summary": {
            "green": len(checks) - len(missing),
            "yellow": len(missing),
            "red": 0,
            "message": (
                "Внешние endpoint probes готовы."
                if not missing
                else "Нужен внешний endpoint probe и свежие healthy observations."
            ),
        },
        "ownerAction": (
            "Поставить обновлённый scripts/monitoring/service_probe.py на отдельный VPS; "
            "он будет присылать и service availability, и server-health observations."
        ),
    }


def build_server_health_summary() -> dict:
    since_24h = (utc_now() - timedelta(hours=24)).isoformat()
    with db() as conn:
        total = db_count(conn, "server_health_observations")
        failed_24h = db_count(
            conn,
            "server_health_observations",
            "observed_at >= ? AND status IN ('degraded', 'down')",
            (since_24h,),
        )
        latest_rows = conn.execute(
            """
            SELECT *
            FROM server_health_observations
            ORDER BY observed_at DESC, id DESC
            LIMIT 1000
            """
        ).fetchall()
        by_status = db_group_counts(conn, "server_health_observations", "status")
        by_region = db_group_counts(conn, "server_health_observations", "probe_region")
        by_protocol = db_group_counts(conn, "server_health_observations", "protocol")

    latest_by_endpoint: dict[str, dict] = {}
    for row in latest_rows:
        payload = server_health_observation_payload(row)
        latest_by_endpoint.setdefault(payload["endpointId"], payload)

    latest = list(latest_by_endpoint.values())
    bad_latest = [
        item
        for item in latest
        if item["status"] in {"degraded", "down"} or item["ok"] is False
    ]
    healthy_latest = [item for item in latest if item["status"] == "healthy" and item["ok"]]
    avg_latency_values = [
        item["latencyMs"]
        for item in latest
        if item["latencyMs"] is not None and item["status"] == "healthy"
    ]
    avg_latency = (
        round(sum(avg_latency_values) / len(avg_latency_values))
        if avg_latency_values
        else None
    )
    probe_agents = list_server_health_probe_agents(limit=100)

    summary = {
        "totalObservations": int(total),
        "endpointsObserved": len(latest),
        "healthyEndpoints": len(healthy_latest),
        "problemEndpoints": len(bad_latest),
        "failed24h": int(failed_24h),
        "averageHealthyLatencyMs": avg_latency,
        "latestByEndpoint": latest,
        "problemLatest": bad_latest,
        "byStatus": by_status,
        "byRegion": by_region,
        "byProtocol": by_protocol,
        "serverHealthProbeAgents": probe_agents,
        "serverHealthProbeAgentsTotal": len(probe_agents),
        "externalServerHealthProbeAgents": len(
            [item for item in probe_agents if item.get("isExternal")]
        ),
        "workflow": {
            "statuses": list(SERVER_HEALTH_STATUSES),
            "agentMode": "admin_internal",
            "publicSafety": (
                "Наблюдения здоровья являются внутренними данными мониторинга. Они не меняют "
                "маршрутизацию клиентов, пока не добавлены правила авто-выбора и безопасного rollout."
            ),
        },
    }
    summary["externalProbeReadiness"] = server_health_external_probe_readiness(summary)
    return summary


def sync_server_health_observation_incident(observation: dict) -> None:
    endpoint_id = clean_limited_text(observation.get("endpointId"), 120).strip()
    if not endpoint_id:
        return
    key = f"server-health:{endpoint_id}"
    status = str(observation.get("status") or "unknown").strip().lower()
    if status in {"degraded", "down"} or observation.get("ok") is False:
        severity = "high" if status == "down" else "medium"
        upsert_admin_incident(
            key,
            f"Server endpoint {endpoint_id}: {status}",
            severity,
            "server_health_observation",
            affected_service="server_catalog",
            affected_endpoint=endpoint_id,
            summary=(
                observation.get("message")
                or f"Latest server health observation is {status}."
            ),
            details={"observation": observation},
        )
    elif status == "healthy":
        resolve_admin_incident_by_key(
            key,
            f"Server endpoint {endpoint_id} снова healthy.",
        )


def normalize_monitoring_target_id(value: Optional[str]) -> str:
    target_id = clean_limited_text(value, 120).strip().lower()
    if not target_id:
        raise HTTPException(status_code=400, detail="targetId is required.")
    if not re.fullmatch(r"[a-z0-9][a-z0-9_-]{2,119}", target_id):
        raise HTTPException(
            status_code=400,
            detail="targetId must contain latin letters, numbers, dash or underscore.",
        )
    return target_id


def normalize_monitoring_target_status(value: Optional[str], fallback: str = "active") -> str:
    candidate = clean_limited_text(value, 40).strip().lower() or fallback
    if candidate not in MONITORING_TARGET_STATUSES:
        raise HTTPException(status_code=400, detail="Unknown monitoring target status.")
    return candidate


def normalize_monitoring_target_type(value: Optional[str], fallback: str = "web") -> str:
    candidate = clean_limited_text(value, 40).strip().lower() or fallback
    if candidate not in MONITORING_TARGET_TYPES:
        raise HTTPException(status_code=400, detail="Unknown monitoring target type.")
    return candidate


def normalize_service_availability_status(value: Optional[str], ok: Optional[bool] = None) -> str:
    candidate = clean_limited_text(value, 40).strip().lower()
    if not candidate:
        if ok is True:
            candidate = "green"
        elif ok is False:
            candidate = "red"
        else:
            candidate = "unknown"
    if candidate not in SERVICE_AVAILABILITY_STATUSES:
        raise HTTPException(status_code=400, detail="Unknown service availability status.")
    return candidate


def normalize_monitoring_port(value: Optional[int]) -> Optional[int]:
    if value is None:
        return None
    try:
        port = int(value)
    except Exception:
        raise HTTPException(status_code=400, detail="port must be a number.")
    if port < 1 or port > 65535:
        raise HTTPException(status_code=400, detail="port must be between 1 and 65535.")
    return port


def normalize_monitoring_timeout(value: Optional[int]) -> int:
    if value is None:
        return int(SERVICE_CHECK_TIMEOUT_SECONDS)
    try:
        parsed = int(value)
    except Exception:
        raise HTTPException(status_code=400, detail="timeoutSeconds must be a number.")
    return max(1, min(parsed, 60))


def normalize_monitoring_interval(value: Optional[int]) -> int:
    if value is None:
        return 300
    try:
        parsed = int(value)
    except Exception:
        raise HTTPException(status_code=400, detail="intervalSeconds must be a number.")
    return max(30, min(parsed, 86400))


def sanitize_monitoring_tags(value: Optional[list[str]]) -> list[str]:
    if not value:
        return []
    tags: list[str] = []
    for item in value:
        tag = clean_limited_text(str(item), 40).strip().lower()
        if tag and re.fullmatch(r"[a-z0-9а-яё_.:-]{1,40}", tag, flags=re.IGNORECASE):
            tags.append(tag)
        if len(tags) >= 20:
            break
    return sorted(set(tags))


def monitoring_target_payload(row: sqlite3.Row) -> dict:
    try:
        tags = json.loads(row["tags_json"] or "[]")
    except Exception:
        tags = []
    if not isinstance(tags, list):
        tags = []
    return {
        "id": int(row["id"]),
        "targetId": row["target_id"],
        "title": row["title"],
        "service": row["service"],
        "targetType": row["target_type"],
        "url": row["url"] or "",
        "host": row["host"] or "",
        "port": int(row["port"]) if row["port"] is not None else None,
        "path": row["path"] or "",
        "expectedStatus": (
            int(row["expected_status"]) if row["expected_status"] is not None else None
        ),
        "timeoutSeconds": int(row["timeout_seconds"]),
        "intervalSeconds": int(row["interval_seconds"]),
        "status": row["status"],
        "tags": tags,
        "notes": row["notes"] or "",
        "publicImpact": bool(row["public_impact"]),
        "createdAt": row["created_at"],
        "updatedAt": row["updated_at"],
    }


def service_availability_observation_payload(row: sqlite3.Row) -> dict:
    try:
        details = json.loads(row["details_json"] or "{}")
    except Exception:
        details = {}
    details = sanitize_monitoring_details(details)
    return {
        "id": int(row["id"]),
        "targetId": row["target_id"],
        "probeId": row["probe_id"] or "",
        "probeRegion": row["probe_region"] or "",
        "ok": bool(row["ok"]),
        "status": row["status"],
        "latencyMs": int(row["latency_ms"]) if row["latency_ms"] is not None else None,
        "errorCode": row["error_code"] or "",
        "message": row["message"] or "",
        "details": details,
        "observedAt": row["observed_at"],
        "createdAt": row["created_at"],
    }


def list_monitoring_targets(
    status: Optional[str] = None,
    service: Optional[str] = None,
    limit: int = 200,
) -> list[dict]:
    where = []
    params: list[object] = []
    if status and status != "all":
        where.append("status = ?")
        params.append(normalize_monitoring_target_status(status))
    if service and service != "all":
        where.append("service = ?")
        params.append(clean_limited_text(service, 80).strip().lower())
    sql = "SELECT * FROM monitoring_targets"
    if where:
        sql += " WHERE " + " AND ".join(where)
    sql += " ORDER BY status ASC, service ASC, target_id ASC LIMIT ?"
    params.append(max(1, min(int(limit or 200), 500)))
    with db() as conn:
        rows = conn.execute(sql, tuple(params)).fetchall()
    return [monitoring_target_payload(row) for row in rows]


def upsert_monitoring_target(
    payload: AdminMonitoringTargetIn,
    target_id_override: Optional[str] = None,
) -> dict:
    target_id = normalize_monitoring_target_id(target_id_override or payload.targetId)
    title = clean_limited_text(payload.title, 160).strip() or target_id.replace("_", " ").title()
    service = clean_limited_text(payload.service, 80).strip().lower() or target_id.split("_", 1)[0]
    target_type = normalize_monitoring_target_type(payload.targetType)
    url = clean_limited_text(payload.url, 500).strip()
    host = clean_limited_text(payload.host, 250).strip().lower()
    if url and not host:
        parsed = urllib.parse.urlparse(url)
        host = (parsed.hostname or "").strip().lower()
    port = normalize_monitoring_port(payload.port)
    if port is None and url:
        parsed = urllib.parse.urlparse(url)
        if parsed.port:
            port = int(parsed.port)
        elif parsed.scheme == "https":
            port = 443
        elif parsed.scheme == "http":
            port = 80
    path = clean_limited_text(payload.path, 250).strip()
    expected_status = payload.expectedStatus
    if expected_status is not None:
        expected_status = max(100, min(int(expected_status), 599))
    timeout_seconds = normalize_monitoring_timeout(payload.timeoutSeconds)
    interval_seconds = normalize_monitoring_interval(payload.intervalSeconds)
    status = normalize_monitoring_target_status(payload.status)
    tags_json = json.dumps(sanitize_monitoring_tags(payload.tags), ensure_ascii=False)
    notes = clean_limited_text(payload.notes, 1000).strip()
    public_impact = 1 if payload.publicImpact is not False else 0
    now = utc_now_iso()

    if not url and not host:
        raise HTTPException(status_code=400, detail="url or host is required.")

    with db() as conn:
        existing = conn.execute(
            "SELECT id FROM monitoring_targets WHERE target_id = ?",
            (target_id,),
        ).fetchone()
        if existing:
            row_id = int(existing["id"])
            conn.execute(
                """
                UPDATE monitoring_targets
                SET title = ?, service = ?, target_type = ?, url = ?, host = ?,
                    port = ?, path = ?, expected_status = ?, timeout_seconds = ?,
                    interval_seconds = ?, status = ?, tags_json = ?, notes = ?,
                    public_impact = ?, updated_at = ?
                WHERE id = ?
                """,
                (
                    title,
                    service,
                    target_type,
                    url or None,
                    host or None,
                    port,
                    path or None,
                    expected_status,
                    timeout_seconds,
                    interval_seconds,
                    status,
                    tags_json,
                    notes or None,
                    public_impact,
                    now,
                    row_id,
                ),
            )
        else:
            cursor = conn.execute(
                """
                INSERT INTO monitoring_targets(
                    target_id, title, service, target_type, url, host, port, path,
                    expected_status, timeout_seconds, interval_seconds, status,
                    tags_json, notes, public_impact, created_at, updated_at
                )
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                (
                    target_id,
                    title,
                    service,
                    target_type,
                    url or None,
                    host or None,
                    port,
                    path or None,
                    expected_status,
                    timeout_seconds,
                    interval_seconds,
                    status,
                    tags_json,
                    notes or None,
                    public_impact,
                    now,
                    now,
                ),
            )
            row_id = int(cursor.lastrowid)
        conn.commit()
        row = conn.execute(
            "SELECT * FROM monitoring_targets WHERE id = ?",
            (row_id,),
        ).fetchone()
    return monitoring_target_payload(row)


def default_monitoring_targets() -> list[dict]:
    service_targets = [
        {
            "targetId": f"{target['code']}_web",
            "title": target["title"],
            "service": target["code"],
            "targetType": target["code"] if target["code"] in MONITORING_TARGET_TYPES else "web",
            "url": target["url"],
            "host": target["host"],
            "expectedStatus": 204 if target["code"] == "youtube" else None,
            "tags": ["blocked-service", "social-only"],
            "notes": "Built-in important service target. Real probes will write observations here.",
        }
        for target in SERVICE_CHECK_TARGETS
    ]
    api_url = SERVER_CATALOG_API_BASE_URLS[0] if SERVER_CATALOG_API_BASE_URLS else PUBLIC_API_BASE_URL
    service_targets.extend(
        [
            {
                "targetId": "green_api_healthz",
                "title": "Green VPN API healthz",
                "service": "api",
                "targetType": "api",
                "url": f"{api_url.rstrip('/')}/healthz",
                "host": urllib.parse.urlparse(api_url).hostname or WG_ENDPOINT_HOST,
                "expectedStatus": 200,
                "tags": ["api", "bootstrap"],
                "notes": "Primary API health endpoint for internal monitoring.",
            },
            {
                "targetId": "production_api_healthz",
                "title": "Production API domain",
                "service": "api",
                "targetType": "bootstrap",
                "url": "https://api.greenvpn.pro/healthz",
                "host": "api.greenvpn.pro",
                "expectedStatus": 200,
                "tags": ["api", "domain", "bootstrap"],
                "notes": "Public DNS/HTTPS domain target. Keep paused if DNS is still propagating.",
                "status": "active",
            },
            {
                "targetId": "windows_update_manifest",
                "title": "Windows update manifest",
                "service": "updates",
                "targetType": "update",
                "url": f"{api_url.rstrip('/')}/api/v1/updates/windows",
                "host": urllib.parse.urlparse(api_url).hostname or WG_ENDPOINT_HOST,
                "expectedStatus": 200,
                "tags": ["updates", "windows"],
                "notes": "Update manifest endpoint used by future client updater.",
            },
            {
                "targetId": "payment_return_page",
                "title": "Payment return page",
                "service": "payments",
                "targetType": "payment",
                "url": f"{api_url.rstrip('/')}/payment/return",
                "host": urllib.parse.urlparse(api_url).hostname or WG_ENDPOINT_HOST,
                "expectedStatus": 200,
                "tags": ["payments", "yookassa"],
                "notes": "Payment return page until production YooKassa is enabled.",
            },
        ]
    )
    return service_targets


def seed_default_monitoring_targets(refresh_existing: bool = False) -> list[dict]:
    with db() as conn:
        existing = int(
            conn.execute("SELECT COUNT(*) AS cnt FROM monitoring_targets").fetchone()["cnt"]
        )
    if existing > 0 and not refresh_existing:
        return []
    seeded: list[dict] = []
    for item in default_monitoring_targets():
        try:
            seeded.append(upsert_monitoring_target(AdminMonitoringTargetIn(**item)))
        except Exception:
            continue
    return seeded


def create_service_availability_observation(
    payload: AdminServiceAvailabilityObservationIn,
) -> dict:
    target_id = normalize_monitoring_target_id(payload.targetId)
    ok = bool(payload.ok) if payload.ok is not None else False
    status = normalize_service_availability_status(payload.status, ok)
    probe_id = clean_limited_text(payload.probeId, 80).strip()
    probe_region = clean_limited_text(payload.probeRegion, 80).strip()
    latency_ms = normalize_latency_ms(payload.latencyMs)
    error_code = clean_limited_text(payload.errorCode, 80).strip()
    message = clean_limited_text(payload.message, 600).strip()
    observed_at = payload.observedAt.strip() if payload.observedAt else utc_now_iso()
    if parse_dt(observed_at) is None:
        raise HTTPException(status_code=400, detail="observedAt must be an ISO datetime.")
    details = sanitize_monitoring_details(payload.details)
    try:
        details_json = json.dumps(details, ensure_ascii=False)
    except Exception:
        details_json = "{}"
    now = utc_now_iso()

    with db() as conn:
        target = conn.execute(
            "SELECT target_id FROM monitoring_targets WHERE target_id = ?",
            (target_id,),
        ).fetchone()
        if target is None:
            raise HTTPException(status_code=404, detail="Monitoring target not found.")
        cursor = conn.execute(
            """
            INSERT INTO service_availability_observations(
                target_id, probe_id, probe_region, ok, status, latency_ms,
                error_code, message, details_json, observed_at, created_at
            )
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            (
                target_id,
                probe_id,
                probe_region,
                1 if ok else 0,
                status,
                latency_ms,
                error_code,
                message,
                details_json,
                observed_at,
                now,
            ),
        )
        conn.commit()
        row = conn.execute(
            "SELECT * FROM service_availability_observations WHERE id = ?",
            (int(cursor.lastrowid),),
        ).fetchone()

    observation = service_availability_observation_payload(row)
    sync_service_availability_observation_incident(observation)
    return observation


def list_service_availability_observations(
    target_id: Optional[str] = None,
    status: Optional[str] = None,
    limit: int = 160,
) -> list[dict]:
    where = []
    params: list[object] = []
    if target_id:
        where.append("target_id = ?")
        params.append(normalize_monitoring_target_id(target_id))
    if status and status != "all":
        where.append("status = ?")
        params.append(normalize_service_availability_status(status))
    sql = "SELECT * FROM service_availability_observations"
    if where:
        sql += " WHERE " + " AND ".join(where)
    sql += " ORDER BY observed_at DESC, id DESC LIMIT ?"
    params.append(max(1, min(int(limit or 160), 500)))
    with db() as conn:
        rows = conn.execute(sql, tuple(params)).fetchall()
    return [service_availability_observation_payload(row) for row in rows]


def list_service_monitoring_probes(limit: int = 100) -> list[dict]:
    since_24h = (utc_now() - timedelta(hours=24)).isoformat()
    stale_cutoff = utc_now() - timedelta(seconds=SERVICE_PROBE_STALE_AFTER_SECONDS)
    safe_limit = max(1, min(int(limit or 100), 500))
    with db() as conn:
        rows = conn.execute(
            """
            SELECT
                COALESCE(NULLIF(probe_id, ''), 'unknown') AS probe_id_norm,
                COALESCE(NULLIF(probe_region, ''), 'unknown') AS probe_region_norm,
                MAX(observed_at) AS last_seen_at,
                COUNT(*) AS total_observations,
                COUNT(DISTINCT target_id) AS targets_observed,
                SUM(CASE WHEN observed_at >= ? THEN 1 ELSE 0 END) AS observations_24h,
                SUM(
                    CASE
                        WHEN observed_at >= ? AND status IN ('yellow', 'red')
                        THEN 1 ELSE 0
                    END
                ) AS problems_24h,
                SUM(CASE WHEN status = 'green' THEN 1 ELSE 0 END) AS green_total,
                SUM(CASE WHEN status = 'yellow' THEN 1 ELSE 0 END) AS yellow_total,
                SUM(CASE WHEN status = 'red' THEN 1 ELSE 0 END) AS red_total,
                SUM(CASE WHEN status = 'unknown' THEN 1 ELSE 0 END) AS unknown_total
            FROM service_availability_observations
            GROUP BY probe_id_norm, probe_region_norm
            ORDER BY last_seen_at DESC
            LIMIT ?
            """,
            (since_24h, since_24h, safe_limit),
        ).fetchall()
        latest_rows = conn.execute(
            """
            SELECT *
            FROM service_availability_observations
            ORDER BY observed_at DESC, id DESC
            LIMIT 2000
            """
        ).fetchall()

    latest_by_probe: dict[tuple[str, str], dict] = {}
    for row in latest_rows:
        payload = service_availability_observation_payload(row)
        key = (
            payload.get("probeId") or "unknown",
            payload.get("probeRegion") or "unknown",
        )
        latest_by_probe.setdefault(key, payload)

    probes: list[dict] = []
    for row in rows:
        probe_id = row["probe_id_norm"] or "unknown"
        probe_region = row["probe_region_norm"] or "unknown"
        latest = latest_by_probe.get((probe_id, probe_region))
        last_seen_at = row["last_seen_at"] or ""
        last_seen_dt = parse_dt(last_seen_at)
        is_stale = True
        if last_seen_dt is not None:
            if last_seen_dt.tzinfo is None:
                last_seen_dt = last_seen_dt.replace(tzinfo=timezone.utc)
            is_stale = last_seen_dt < stale_cutoff
        last_status = (latest or {}).get("status") or "unknown"
        probes.append(
            {
                "probeId": probe_id,
                "probeRegion": probe_region,
                "lastSeenAt": last_seen_at,
                "isStale": is_stale,
                "staleAfterSeconds": SERVICE_PROBE_STALE_AFTER_SECONDS,
                "totalObservations": int(row["total_observations"] or 0),
                "targetsObserved": int(row["targets_observed"] or 0),
                "observations24h": int(row["observations_24h"] or 0),
                "problems24h": int(row["problems_24h"] or 0),
                "greenTotal": int(row["green_total"] or 0),
                "yellowTotal": int(row["yellow_total"] or 0),
                "redTotal": int(row["red_total"] or 0),
                "unknownTotal": int(row["unknown_total"] or 0),
                "lastStatus": last_status,
                "lastTargetId": (latest or {}).get("targetId") or "",
                "lastMessage": (latest or {}).get("message") or "",
                "lastLatencyMs": (latest or {}).get("latencyMs"),
            }
        )
    return probes


def service_monitoring_probe_readiness(summary: dict) -> dict:
    required_target_ids = list(SERVICE_PROBE_REQUIRED_TARGET_IDS)
    latest_by_target = {
        item.get("targetId"): item
        for item in summary.get("latestByTarget") or []
        if item.get("targetId")
    }
    probe_agents = summary.get("probeAgents") or []
    stale_probe_agents = [item for item in probe_agents if item.get("isStale")]
    problem_probe_agents = [
        item
        for item in probe_agents
        if int(item.get("problems24h") or 0) > 0
        or item.get("lastStatus") in {"yellow", "red"}
    ]
    max_age_hours = SERVICE_PROBE_STALE_AFTER_SECONDS / 3600.0
    missing_targets: list[str] = []
    stale_targets: list[str] = []
    failed_targets: list[str] = []
    covered_targets: list[str] = []

    for target_id in required_target_ids:
        latest = latest_by_target.get(target_id)
        if latest is None:
            missing_targets.append(target_id)
            continue
        covered_targets.append(target_id)
        age_hours = server_observation_age_hours(latest.get("observedAt"))
        if age_hours is None or age_hours > max_age_hours:
            stale_targets.append(target_id)
        if latest.get("status") != "green" or latest.get("ok") is False:
            failed_targets.append(target_id)

    checks: list[dict] = []

    def add_check(code: str, title: str, ok: bool, message: str, details: Optional[dict] = None) -> None:
        checks.append(
            {
                "code": code,
                "title": title,
                "ok": bool(ok),
                "message": message,
                "details": details or {},
            }
        )

    add_check(
        "targets_configured",
        "Monitoring targets",
        int(summary.get("activeTargets") or 0) > 0,
        "Есть активные цели мониторинга."
        if int(summary.get("activeTargets") or 0) > 0
        else "Нет активных целей мониторинга для probes.",
        {
            "targetTotal": int(summary.get("targetTotal") or 0),
            "activeTargets": int(summary.get("activeTargets") or 0),
        },
    )
    add_check(
        "probe_agent_seen",
        "Probe agent",
        len(probe_agents) > 0,
        "Backend уже видел controlled monitoring probe."
        if probe_agents
        else "Нужен отдельный monitoring VPS/probe agent.",
        {"probeAgentsTotal": len(probe_agents)},
    )
    add_check(
        "probe_agent_fresh",
        "Fresh probe signal",
        len(probe_agents) > 0 and len(stale_probe_agents) == 0,
        "Все известные probe agents присылали свежие observations."
        if probe_agents and not stale_probe_agents
        else "Один или несколько probe agents молчат или ещё не установлены.",
        {
            "staleAfterSeconds": SERVICE_PROBE_STALE_AFTER_SECONDS,
            "staleProbeAgents": [
                item.get("probeId") for item in stale_probe_agents[:10]
            ],
        },
    )
    add_check(
        "probe_agent_clean_24h",
        "Probe health 24h",
        len(problem_probe_agents) == 0,
        "За последние 24 часа у probe agents нет жёлтых/красных наблюдений."
        if not problem_probe_agents
        else "Есть жёлтые/красные observations за последние 24 часа.",
        {
            "problemProbeAgents": [
                item.get("probeId") for item in problem_probe_agents[:10]
            ],
        },
    )
    add_check(
        "required_targets_covered",
        "Required target coverage",
        not missing_targets,
        "Обязательные сервисы покрыты observations."
        if not missing_targets
        else "Не все обязательные сервисы ещё проверялись controlled probe.",
        {
            "requiredTargetIds": required_target_ids,
            "coveredTargetIds": covered_targets,
            "missingTargetIds": missing_targets,
        },
    )
    add_check(
        "required_targets_fresh",
        "Required target freshness",
        not stale_targets and not missing_targets,
        "Обязательные observations свежие."
        if not stale_targets and not missing_targets
        else "Часть обязательных observations устарела или отсутствует.",
        {"staleTargetIds": stale_targets},
    )
    add_check(
        "required_targets_green",
        "Required target status",
        not failed_targets and not missing_targets,
        "Обязательные сервисы зелёные."
        if not failed_targets and not missing_targets
        else "Часть обязательных сервисов сейчас не зелёная или ещё не проверялась.",
        {"failedTargetIds": failed_targets},
    )

    missing = [check for check in checks if not check["ok"]]
    return {
        "productionReady": len(missing) == 0,
        "staleAfterSeconds": SERVICE_PROBE_STALE_AFTER_SECONDS,
        "requiredTargetIds": required_target_ids,
        "coveredRequiredTargets": len(covered_targets),
        "missingRequiredTargets": missing_targets,
        "staleRequiredTargets": stale_targets,
        "failedRequiredTargets": failed_targets,
        "probeAgentsTotal": len(probe_agents),
        "activeProbeAgents": len(probe_agents) - len(stale_probe_agents),
        "staleProbeAgents": len(stale_probe_agents),
        "problemProbeAgents": len(problem_probe_agents),
        "checks": checks,
        "installBundle": service_monitoring_probe_install_bundle(summary),
        "summary": {
            "green": len(checks) - len(missing),
            "yellow": len(missing),
            "red": 0,
            "message": (
                "Controlled monitoring probes готовы."
                if not missing
                else "Нужен внешний monitoring probe и свежие зелёные observations."
            ),
        },
        "ownerAction": (
            "Поставить scripts/monitoring/service_probe.py на отдельный VPS через "
            "install_probe_systemd.sh и передать admin token только через stdin/file вне repo."
        ),
    }


def service_monitoring_probe_install_bundle(summary: dict) -> dict:
    required_target_ids = list(SERVICE_PROBE_REQUIRED_TARGET_IDS)
    interval_seconds = 300
    return {
        "mode": "external_vps_systemd",
        "apiBase": "https://api.greenvpn.pro",
        "defaultProbeId": "probe-eu-1",
        "defaultProbeRegion": "eu",
        "intervalSeconds": interval_seconds,
        "staleAfterSeconds": SERVICE_PROBE_STALE_AFTER_SECONDS,
        "requiredTargetIds": required_target_ids,
        "sourceFiles": [
            "scripts/monitoring/service_probe.py",
            "scripts/monitoring/install_probe_systemd.sh",
        ],
        "installCommand": (
            "bash scripts/monitoring/install_probe_systemd.sh "
            "--api-base https://api.greenvpn.pro "
            "--probe-id probe-eu-1 "
            "--probe-region eu "
            f"--interval {interval_seconds} "
            "--server-health "
            "--token-stdin"
        ),
        "tokenPath": "/etc/greenvpn-monitoring/admin_token",
        "tokenPolicy": (
            "Admin token is entered only on the monitoring VPS through stdin/file and stored "
            "at /etc/greenvpn-monitoring/admin_token with mode 600. Do not put it in repo, "
            "systemd unit text, shell history, docs, or chat."
        ),
        "ownerInputs": [
            {"name": "Monitoring VPS host/IP", "secret": False},
            {"name": "SSH user/access method", "secret": True},
            {"name": "Probe id", "secret": False, "example": "probe-eu-1"},
            {"name": "Probe region", "secret": False, "example": "eu"},
            {"name": "Admin token handoff method", "secret": True, "example": "--token-stdin"},
        ],
        "applySteps": [
            "Copy service_probe.py and install_probe_systemd.sh to the monitoring VPS.",
            "Run install_probe_systemd.sh as root with --token-stdin or --token-file.",
            "Leave --server-health enabled so the probe sends endpoint health observations too.",
            "Keep the probe VPS separate from the main backend/VPN server.",
            "Do not change user VPN routing or Windows installer while installing the probe.",
        ],
        "verifySteps": [
            "systemctl status greenvpn-service-probe.timer --no-pager",
            "journalctl -u greenvpn-service-probe.service -n 80 --no-pager",
            "GET /api/v1/admin/monitoring/probes",
            "GET /api/v1/admin/server-health",
            "GET /api/v1/admin/monitoring/readiness",
            "Confirm required targets and current_wg0 have fresh green/healthy observations.",
        ],
        "safeToRunWithoutOwner": False,
        "blockedUntilOwnerProvides": [
            "monitoring VPS host/IP",
            "SSH access to that VPS",
            "admin token entered only into the probe host",
        ],
        "currentState": {
            "activeTargets": int(summary.get("activeTargets") or 0),
            "probeAgentsTotal": int(summary.get("probeAgentsTotal") or 0),
            "coveredRequiredTargets": len(
                set(required_target_ids)
                & {
                    item.get("targetId")
                    for item in summary.get("latestByTarget") or []
                    if item.get("targetId")
                }
            ),
        },
    }


def build_service_availability_observation_summary() -> dict:
    since_24h = (utc_now() - timedelta(hours=24)).isoformat()
    with db() as conn:
        target_total = int(
            conn.execute("SELECT COUNT(*) AS cnt FROM monitoring_targets").fetchone()["cnt"]
        )
        active_targets = int(
            conn.execute(
                "SELECT COUNT(*) AS cnt FROM monitoring_targets WHERE status = 'active'"
            ).fetchone()["cnt"]
        )
        total = int(
            conn.execute(
                "SELECT COUNT(*) AS cnt FROM service_availability_observations"
            ).fetchone()["cnt"]
        )
        failed_24h = int(
            conn.execute(
                """
                SELECT COUNT(*) AS cnt
                FROM service_availability_observations
                WHERE observed_at >= ? AND status IN ('yellow', 'red')
                """,
                (since_24h,),
            ).fetchone()["cnt"]
        )
        latest_rows = conn.execute(
            """
            SELECT *
            FROM service_availability_observations
            ORDER BY observed_at DESC, id DESC
            LIMIT 1000
            """
        ).fetchall()
        by_status = db_group_counts(conn, "service_availability_observations", "status")
        by_target_status = db_group_counts(conn, "monitoring_targets", "status")
        by_service = db_group_counts(conn, "monitoring_targets", "service")

    latest_by_target: dict[str, dict] = {}
    for row in latest_rows:
        payload = service_availability_observation_payload(row)
        latest_by_target.setdefault(payload["targetId"], payload)

    latest = list(latest_by_target.values())
    problem_latest = [
        item
        for item in latest
        if item["status"] in {"yellow", "red"} or item["ok"] is False
    ]
    green_latest = [item for item in latest if item["status"] == "green" and item["ok"]]
    avg_latency_values = [
        item["latencyMs"]
        for item in latest
        if item["latencyMs"] is not None and item["status"] == "green"
    ]
    avg_latency = (
        round(sum(avg_latency_values) / len(avg_latency_values))
        if avg_latency_values
        else None
    )
    probe_agents = list_service_monitoring_probes(limit=100)
    stale_probe_agents = [item for item in probe_agents if item["isStale"]]
    problem_probe_agents = [
        item
        for item in probe_agents
        if item["problems24h"] > 0 or item["lastStatus"] in {"yellow", "red"}
    ]

    summary = {
        "targetTotal": target_total,
        "activeTargets": active_targets,
        "totalObservations": total,
        "targetsObserved": len(latest),
        "greenTargets": len(green_latest),
        "problemTargets": len(problem_latest),
        "failed24h": failed_24h,
        "averageGreenLatencyMs": avg_latency,
        "latestByTarget": latest,
        "problemLatest": problem_latest,
        "byStatus": by_status,
        "byTargetStatus": by_target_status,
        "byService": by_service,
        "probeAgents": probe_agents,
        "probeAgentsTotal": len(probe_agents),
        "activeProbeAgents": len(probe_agents) - len(stale_probe_agents),
        "staleProbeAgents": len(stale_probe_agents),
        "problemProbeAgents": len(problem_probe_agents),
        "workflow": {
            "targetStatuses": list(MONITORING_TARGET_STATUSES),
            "targetTypes": list(MONITORING_TARGET_TYPES),
            "observationStatuses": list(SERVICE_AVAILABILITY_STATUSES),
            "probeStaleAfterSeconds": 900,
            "agentMode": "admin_internal",
            "publicSafety": (
                "Managed service observations are internal support/ops data. "
                "They are not shown in the user client."
            ),
        },
    }
    summary["probeReadiness"] = service_monitoring_probe_readiness(summary)
    return summary


def sync_service_availability_observation_incident(observation: dict) -> None:
    key = f"service-observation:{observation['targetId']}"
    status = observation.get("status")
    if status in {"red", "yellow"}:
        upsert_admin_incident(
            key,
            f"Service target {observation['targetId']}: {status}",
            "high" if status == "red" else "medium",
            "service_availability_observation",
            affected_service=observation["targetId"],
            affected_endpoint=observation.get("probeRegion") or observation.get("probeId"),
            summary=observation.get("message") or f"Latest observation is {status}.",
            details={"observation": observation},
        )
    elif status == "green":
        resolve_admin_incident_by_key(
            key,
            f"Service target {observation['targetId']} снова зелёный.",
        )


def normalize_control_key(value: Optional[str], field_name: str) -> str:
    key = clean_limited_text(value, 120).strip().lower()
    if not key:
        raise HTTPException(status_code=400, detail=f"{field_name} is required.")
    if not re.fullmatch(r"[a-z0-9][a-z0-9_.:-]{2,119}", key):
        raise HTTPException(
            status_code=400,
            detail=f"{field_name} must contain latin letters, numbers, dot, colon, dash or underscore.",
        )
    return key


def normalize_feature_flag_scope(value: Optional[str], fallback: str = "global") -> str:
    scope = clean_limited_text(value, 40).strip().lower() or fallback
    if scope not in FEATURE_FLAG_SCOPES:
        raise HTTPException(status_code=400, detail="Unknown feature flag scope.")
    return scope


def normalize_runbook_category(value: Optional[str], fallback: str = "general") -> str:
    category = clean_limited_text(value, 40).strip().lower() or fallback
    if category not in RUNBOOK_CATEGORIES:
        raise HTTPException(status_code=400, detail="Unknown runbook category.")
    return category


def normalize_runbook_severity(value: Optional[str], fallback: str = "normal") -> str:
    severity = clean_limited_text(value, 40).strip().lower() or fallback
    if severity not in RUNBOOK_SEVERITIES:
        raise HTTPException(status_code=400, detail="Unknown runbook severity.")
    return severity


def safe_control_json(value: Any, default: Any = None, max_len: int = 12000) -> str:
    if value is None:
        value = default
    try:
        encoded = json.dumps(value, ensure_ascii=False, sort_keys=True)
    except Exception:
        raise HTTPException(status_code=400, detail="value must be JSON serializable.")
    if len(encoded) > max_len:
        raise HTTPException(status_code=400, detail="value JSON is too large.")
    return encoded


def feature_flag_workflow_options() -> dict:
    return {
        "scopes": list(FEATURE_FLAG_SCOPES),
        "valueExamples": {
            "bool": True,
            "number": 25,
            "string": "enabled",
            "object": {"mode": "manual_mvp"},
        },
        "publicSafety": (
            "Feature flags are internal controls. Client-facing use must be added "
            "explicitly through signed bootstrap/catalog logic."
        ),
    }


def runbook_workflow_options() -> dict:
    return {
        "categories": list(RUNBOOK_CATEGORIES),
        "severities": list(RUNBOOK_SEVERITIES),
        "publicSafety": (
            "Runbooks are internal support/ops instructions and are never returned "
            "to the public client."
        ),
    }


def feature_flag_payload(row: sqlite3.Row) -> dict:
    try:
        value = json.loads(row["value_json"] or "null")
    except Exception:
        value = None
    return {
        "id": int(row["id"]),
        "key": row["flag_key"],
        "title": row["title"],
        "description": row["description"] or "",
        "value": value,
        "scope": row["scope"],
        "isEnabled": bool(row["is_enabled"]),
        "rolloutPercent": int(row["rollout_percent"] or 0),
        "notes": row["notes"] or "",
        "updatedBy": row["updated_by"] or "",
        "createdAt": row["created_at"],
        "updatedAt": row["updated_at"],
    }


def runbook_payload(row: sqlite3.Row) -> dict:
    try:
        steps = json.loads(row["steps_json"] or "[]")
    except Exception:
        steps = []
    if not isinstance(steps, list):
        steps = []
    return {
        "id": int(row["id"]),
        "key": row["runbook_key"],
        "title": row["title"],
        "category": row["category"],
        "severity": row["severity"],
        "summary": row["summary"] or "",
        "steps": [str(item) for item in steps],
        "ownerRole": row["owner_role"] or "",
        "isActive": bool(row["is_active"]),
        "createdAt": row["created_at"],
        "updatedAt": row["updated_at"],
    }


def list_admin_feature_flags(
    scope: Optional[str] = None,
    enabled: Optional[str] = None,
    limit: int = 200,
    offset: int = 0,
) -> list[dict]:
    where = []
    params: list[object] = []
    if scope and scope != "all":
        where.append("scope = ?")
        params.append(normalize_feature_flag_scope(scope))
    if enabled not in {None, "", "all"}:
        where.append("is_enabled = ?")
        params.append(1 if str(enabled).strip().lower() in {"1", "true", "yes", "enabled"} else 0)
    sql = "SELECT * FROM admin_feature_flags"
    if where:
        sql += " WHERE " + " AND ".join(where)
    sql += " ORDER BY scope ASC, flag_key ASC LIMIT ? OFFSET ?"
    params.extend([max(1, min(int(limit or 200), 500)), max(0, int(offset or 0))])
    with db() as conn:
        rows = conn.execute(sql, tuple(params)).fetchall()
    return [feature_flag_payload(row) for row in rows]


def upsert_admin_feature_flag(
    payload: AdminFeatureFlagIn,
    flag_id: Optional[int] = None,
    actor: Optional[str] = None,
) -> dict:
    now = utc_now_iso()
    flag_key = normalize_control_key(payload.key, "key")
    title = clean_limited_text(payload.title, 160).strip()
    if not title:
        raise HTTPException(status_code=400, detail="title is required.")
    scope = normalize_feature_flag_scope(payload.scope)
    rollout_percent = normalize_percentish(payload.rolloutPercent, 0)
    is_enabled = 1 if payload.isEnabled else 0
    value_json = safe_control_json(payload.value, default=False)
    description = clean_limited_text(payload.description, 1200).strip()
    notes = clean_limited_text(payload.notes, 1500).strip()
    updated_by = clean_limited_text(actor, 160).strip()

    with db() as conn:
        if flag_id is not None:
            row = conn.execute(
                "SELECT id FROM admin_feature_flags WHERE id = ?",
                (flag_id,),
            ).fetchone()
            if row is None:
                raise HTTPException(status_code=404, detail="Feature flag not found.")
            duplicate = conn.execute(
                "SELECT id FROM admin_feature_flags WHERE flag_key = ? AND id != ?",
                (flag_key, flag_id),
            ).fetchone()
            if duplicate is not None:
                raise HTTPException(status_code=409, detail="Feature flag key already exists.")
            conn.execute(
                """
                UPDATE admin_feature_flags
                SET flag_key = ?, title = ?, description = ?, value_json = ?, scope = ?,
                    is_enabled = ?, rollout_percent = ?, notes = ?, updated_by = ?,
                    updated_at = ?
                WHERE id = ?
                """,
                (
                    flag_key,
                    title,
                    description or None,
                    value_json,
                    scope,
                    is_enabled,
                    rollout_percent,
                    notes or None,
                    updated_by or None,
                    now,
                    flag_id,
                ),
            )
            row_id = flag_id
        else:
            existing = conn.execute(
                "SELECT id FROM admin_feature_flags WHERE flag_key = ?",
                (flag_key,),
            ).fetchone()
            if existing is not None:
                raise HTTPException(status_code=409, detail="Feature flag key already exists.")
            cursor = conn.execute(
                """
                INSERT INTO admin_feature_flags(
                    flag_key, title, description, value_json, scope, is_enabled,
                    rollout_percent, notes, updated_by, created_at, updated_at
                )
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                (
                    flag_key,
                    title,
                    description or None,
                    value_json,
                    scope,
                    is_enabled,
                    rollout_percent,
                    notes or None,
                    updated_by or None,
                    now,
                    now,
                ),
            )
            row_id = int(cursor.lastrowid)
        conn.commit()
        row = conn.execute(
            "SELECT * FROM admin_feature_flags WHERE id = ?",
            (row_id,),
        ).fetchone()
    return feature_flag_payload(row)


def sanitize_runbook_steps(value: Optional[list[str]]) -> list[str]:
    if not value:
        return []
    steps = []
    for item in value:
        clean = clean_limited_text(str(item), 1200).strip(" \r\n\t-")
        if clean:
            steps.append(clean)
        if len(steps) >= 40:
            break
    return steps


def list_admin_runbooks(
    category: Optional[str] = None,
    active: Optional[str] = None,
    limit: int = 200,
    offset: int = 0,
) -> list[dict]:
    where = []
    params: list[object] = []
    if category and category != "all":
        where.append("category = ?")
        params.append(normalize_runbook_category(category))
    if active not in {None, "", "all"}:
        where.append("is_active = ?")
        params.append(1 if str(active).strip().lower() in {"1", "true", "yes", "active"} else 0)
    sql = "SELECT * FROM admin_runbooks"
    if where:
        sql += " WHERE " + " AND ".join(where)
    sql += " ORDER BY is_active DESC, severity DESC, category ASC, runbook_key ASC LIMIT ? OFFSET ?"
    params.extend([max(1, min(int(limit or 200), 500)), max(0, int(offset or 0))])
    with db() as conn:
        rows = conn.execute(sql, tuple(params)).fetchall()
    return [runbook_payload(row) for row in rows]


def upsert_admin_runbook(
    payload: AdminRunbookIn,
    runbook_id: Optional[int] = None,
) -> dict:
    now = utc_now_iso()
    runbook_key = normalize_control_key(payload.key, "key")
    title = clean_limited_text(payload.title, 180).strip()
    if not title:
        raise HTTPException(status_code=400, detail="title is required.")
    category = normalize_runbook_category(payload.category)
    severity = normalize_runbook_severity(payload.severity)
    summary = clean_limited_text(payload.summary, 1800).strip()
    steps = sanitize_runbook_steps(payload.steps)
    if not steps:
        raise HTTPException(status_code=400, detail="at least one step is required.")
    owner_role = clean_limited_text(payload.ownerRole, 80).strip().lower()
    if owner_role and owner_role not in ADMIN_ROLE_MATRIX:
        raise HTTPException(status_code=400, detail="Unknown ownerRole.")
    is_active = 1 if payload.isActive is not False else 0
    steps_json = json.dumps(steps, ensure_ascii=False)

    with db() as conn:
        if runbook_id is not None:
            row = conn.execute(
                "SELECT id FROM admin_runbooks WHERE id = ?",
                (runbook_id,),
            ).fetchone()
            if row is None:
                raise HTTPException(status_code=404, detail="Runbook not found.")
            duplicate = conn.execute(
                "SELECT id FROM admin_runbooks WHERE runbook_key = ? AND id != ?",
                (runbook_key, runbook_id),
            ).fetchone()
            if duplicate is not None:
                raise HTTPException(status_code=409, detail="Runbook key already exists.")
            conn.execute(
                """
                UPDATE admin_runbooks
                SET runbook_key = ?, title = ?, category = ?, severity = ?, summary = ?,
                    steps_json = ?, owner_role = ?, is_active = ?, updated_at = ?
                WHERE id = ?
                """,
                (
                    runbook_key,
                    title,
                    category,
                    severity,
                    summary or None,
                    steps_json,
                    owner_role or None,
                    is_active,
                    now,
                    runbook_id,
                ),
            )
            row_id = runbook_id
        else:
            existing = conn.execute(
                "SELECT id FROM admin_runbooks WHERE runbook_key = ?",
                (runbook_key,),
            ).fetchone()
            if existing is not None:
                raise HTTPException(status_code=409, detail="Runbook key already exists.")
            cursor = conn.execute(
                """
                INSERT INTO admin_runbooks(
                    runbook_key, title, category, severity, summary, steps_json,
                    owner_role, is_active, created_at, updated_at
                )
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                (
                    runbook_key,
                    title,
                    category,
                    severity,
                    summary or None,
                    steps_json,
                    owner_role or None,
                    is_active,
                    now,
                    now,
                ),
            )
            row_id = int(cursor.lastrowid)
        conn.commit()
        row = conn.execute(
            "SELECT * FROM admin_runbooks WHERE id = ?",
            (row_id,),
        ).fetchone()
    return runbook_payload(row)


def seed_default_feature_flags_and_runbooks() -> None:
    now = utc_now_iso()
    default_flags = [
        {
            "key": "payments.production_enabled",
            "title": "Production payments",
            "description": "Включение production-платежей после домена, HTTPS и YooKassa keys.",
            "value": {"provider": "yookassa", "mode": "manual_until_keys"},
            "scope": "payments",
            "enabled": False,
            "rollout": 0,
        },
        {
            "key": "auth.email_codes_enabled",
            "title": "Email code login",
            "description": "Одноразовые коды на email как запасной вход и регистрация.",
            "value": True,
            "scope": "auth",
            "enabled": True,
            "rollout": 100,
        },
        {
            "key": "auth.sms_codes_enabled",
            "title": "SMS code login",
            "description": "Вход и регистрация по телефону после подключения SMS provider.",
            "value": {"provider": "sms.ru", "ready": False},
            "scope": "auth",
            "enabled": False,
            "rollout": 0,
        },
        {
            "key": "support.auto_triage_enabled",
            "title": "Support auto triage",
            "description": "Автоматическая категоризация отчётов поддержки.",
            "value": True,
            "scope": "support",
            "enabled": True,
            "rollout": 100,
        },
        {
            "key": "updates.required_updates_enabled",
            "title": "Required updates",
            "description": "Принудительные обновления клиента перед подключением.",
            "value": False,
            "scope": "updates",
            "enabled": False,
            "rollout": 0,
        },
        {
            "key": "catalog.managed_endpoints_enabled",
            "title": "Managed endpoint catalog",
            "description": "Выдача управляемых endpoint клиенту после provisioning и safe rollout.",
            "value": {"mode": "admin_preparation"},
            "scope": "vpn",
            "enabled": False,
            "rollout": 0,
        },
        {
            "key": "vpn.guard_other_vpn_enabled",
            "title": "Other VPN guard",
            "description": "Пользовательский клиент предупреждает/не конфликтует с Amnezia/WARP/WireGuard.",
            "value": True,
            "scope": "vpn",
            "enabled": True,
            "rollout": 100,
        },
        {
            "key": "monitoring.service_alerts_enabled",
            "title": "Service availability alerts",
            "description": "Инциденты и alert hooks по YouTube/Discord/Telegram/API/update targets.",
            "value": True,
            "scope": "monitoring",
            "enabled": True,
            "rollout": 100,
        },
    ]
    default_runbooks = [
        {
            "key": "vpn_connect_failed",
            "title": "VPN не подключается у пользователя",
            "category": "vpn",
            "severity": "high",
            "summary": "Проверить сервис, конфликтующие VPN, конфиг, handshake и endpoint.",
            "steps": [
                "Открыть support report пользователя и проверить status/service/handshake/traffic.",
                "Проверить, нет ли активных Amnezia/WARP/WireGuard-сервисов, конфликтующих с BlueVPNDev1.",
                "Проверить server catalog и последние health observations по endpoint.",
                "Если конфиг протух или устройство сломано, перевыпустить конфиг после проверки лимита устройств.",
                "Если проблема массовая, создать incident и убрать плохой endpoint из авто-выбора.",
            ],
            "ownerRole": "support",
        },
        {
            "key": "payment_not_activated",
            "title": "Оплата не активировала тариф",
            "category": "payments",
            "severity": "high",
            "summary": "Сверить order, YooKassa payment id, webhook и статус подписки.",
            "steps": [
                "Найти пользователя по email/phone и открыть его заказы.",
                "Проверить, есть ли pending/paid order и привязан ли paymentProviderId.",
                "Проверить webhook readiness и последние ошибки backend.",
                "Если деньги точно получены, активировать заказ админ-действием и оставить audit note.",
            ],
            "ownerRole": "finance",
        },
        {
            "key": "external_service_down",
            "title": "YouTube/Discord/Telegram не открывается через VPN",
            "category": "monitoring",
            "severity": "critical",
            "summary": "Сначала определить масштаб: один endpoint, протокол, страна или массовая деградация.",
            "steps": [
                "Открыть Monitoring и Incidents, проверить latest observations по сервису.",
                "Сравнить результаты по probeRegion и endpoint.",
                "Если проблема только на одном endpoint, пометить его degraded/maintenance.",
                "Если проблема массовая, включить fallback-инцидент и подготовить update/server catalog hotfix.",
            ],
            "ownerRole": "admin",
        },
        {
            "key": "api_unavailable",
            "title": "Backend/API недоступен",
            "category": "servers",
            "severity": "critical",
            "summary": "Проверить healthz, systemd, DNS api.greenvpn.pro и server 37.220.85.211.",
            "steps": [
                "Проверить /healthz по IP и домену.",
                "Проверить systemd-сервис backend на сервере.",
                "Проверить DNS A api.greenvpn.pro -> 37.220.85.211.",
                "Если домен недоступен, временно использовать IP bootstrap и открыть incident.",
            ],
            "ownerRole": "admin",
        },
        {
            "key": "new_server_rollout",
            "title": "Ввод нового VPN endpoint",
            "category": "servers",
            "severity": "normal",
            "summary": "Новый сервер сначала проходит internal catalog, health, canary, потом public rollout.",
            "steps": [
                "Добавить endpoint в server catalog со status=draft и isPublic=false.",
                "Проверить WireGuard/OpenVPN provisioning вне пользовательского клиента.",
                "Записать несколько health observations с разных probes.",
                "Перевести status=healthy, isActive=true, затем делать rollout малыми процентами.",
            ],
            "ownerRole": "admin",
        },
        {
            "key": "server_catalog_publication_gate",
            "title": "Проверка перед публикацией managed endpoint",
            "category": "servers",
            "severity": "high",
            "summary": (
                "Managed endpoint нельзя отдавать пользователям, пока не готовы "
                "provisioning, health observations, staged rollout и rollback."
            ),
            "steps": [
                "Открыть Server Catalog и проверить publication readiness.",
                "Убедиться, что публичный /api/v1/catalog/servers всё ещё выдаёт только безопасные endpoint.",
                "Проверить fresh healthy observations за 24 часа и отсутствие recent failures.",
                "Проверить, что для endpoint есть безопасная выдача WireGuard peer/config по serverId.",
                "Запустить staged rollout на малый процент и держать rollback installer/server catalog под рукой.",
            ],
            "ownerRole": "admin",
        },
        {
            "key": "email_sms_not_delivered",
            "title": "Код входа не приходит",
            "category": "auth",
            "severity": "normal",
            "summary": "Проверить SMTP/SMS provider readiness, outbox, rate limit и корректность контакта.",
            "steps": [
                "Проверить email/sms readiness в Readiness.",
                "Проверить auth events и outbox по email/phone пользователя.",
                "Проверить cooldown/rate limit и формат контакта.",
                "Если provider не настроен, объяснить пользователю запасной способ входа.",
            ],
            "ownerRole": "support",
        },
        {
            "key": "critical_update_publish",
            "title": "Публикация критического обновления Windows",
            "category": "updates",
            "severity": "critical",
            "summary": "Сначала signed installer + hash + canary, потом required update.",
            "steps": [
                "Собрать установщик и проверить SHA256.",
                "Создать release в draft/internal channel.",
                "Проверить установку на тестовой машине и rollback path.",
                "Опубликовать stable с rolloutPercent < 100, затем включить required при необходимости.",
            ],
            "ownerRole": "admin",
        },
    ]
    with db() as conn:
        for flag in default_flags:
            conn.execute(
                """
                INSERT OR IGNORE INTO admin_feature_flags(
                    flag_key, title, description, value_json, scope, is_enabled,
                    rollout_percent, notes, updated_by, created_at, updated_at
                )
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                (
                    flag["key"],
                    flag["title"],
                    flag["description"],
                    safe_control_json(flag["value"], default=False),
                    flag["scope"],
                    1 if flag["enabled"] else 0,
                    flag["rollout"],
                    "Seeded default. Safe to edit from admin app.",
                    "system",
                    now,
                    now,
                ),
            )
        for runbook in default_runbooks:
            conn.execute(
                """
                INSERT OR IGNORE INTO admin_runbooks(
                    runbook_key, title, category, severity, summary, steps_json,
                    owner_role, is_active, created_at, updated_at
                )
                VALUES (?, ?, ?, ?, ?, ?, ?, 1, ?, ?)
                """,
                (
                    runbook["key"],
                    runbook["title"],
                    runbook["category"],
                    runbook["severity"],
                    runbook["summary"],
                    json.dumps(runbook["steps"], ensure_ascii=False),
                    runbook["ownerRole"],
                    now,
                    now,
                ),
            )
        conn.commit()


def normalize_app_release_platform(value: Optional[str], fallback: str = "windows") -> str:
    candidate = clean_limited_text(value, 40).strip().lower() or fallback
    if candidate not in APP_RELEASE_PLATFORMS:
        raise HTTPException(status_code=400, detail="Unknown release platform.")
    return candidate


def normalize_app_release_channel(value: Optional[str], fallback: str = "stable") -> str:
    candidate = clean_limited_text(value, 40).strip().lower() or fallback
    if candidate not in APP_RELEASE_CHANNELS:
        raise HTTPException(status_code=400, detail="Unknown release channel.")
    return candidate


def normalize_app_release_status(value: Optional[str], fallback: str = "draft") -> str:
    candidate = clean_limited_text(value, 40).strip().lower() or fallback
    if candidate not in APP_RELEASE_STATUSES:
        raise HTTPException(status_code=400, detail="Unknown release status.")
    return candidate


def sanitize_release_changelog(value: Optional[list[str]]) -> list[str]:
    if not value:
        return []
    items = []
    for item in value:
        clean = clean_limited_text(str(item), 500).strip(" -")
        if clean:
            items.append(clean)
        if len(items) >= 30:
            break
    return items


def parse_release_changelog(value: Optional[str]) -> list[str]:
    if not value:
        return []
    try:
        decoded = json.loads(value)
    except Exception:
        decoded = []
    if not isinstance(decoded, list):
        return []
    return sanitize_release_changelog([str(item) for item in decoded])


def validate_release_download_url(value: Optional[str]) -> str:
    url = clean_limited_text(value, 500).strip()
    if not url:
        return ""
    parsed = urllib.parse.urlparse(url)
    if parsed.scheme not in {"http", "https"} or not parsed.netloc:
        raise HTTPException(status_code=400, detail="downloadUrl must be http or https URL.")
    return url


def validate_release_sha256(value: Optional[str]) -> str:
    sha = clean_limited_text(value, 80).strip().lower()
    if not sha:
        return ""
    if not re.fullmatch(r"[0-9a-f]{64}", sha):
        raise HTTPException(status_code=400, detail="sha256 must be 64 hex characters.")
    return sha.upper()


def update_artifact_readiness(
    download_url: Optional[str],
    sha256: Optional[str],
) -> dict:
    url = clean_limited_text(download_url, 500).strip()
    sha = clean_limited_text(sha256, 80).strip()
    parsed = urllib.parse.urlparse(url) if url else None
    scheme = (parsed.scheme or "").lower() if parsed else ""
    host = ((parsed.hostname or "").lower() if parsed else "")
    local_hosts = {"", "localhost", "127.0.0.1", "::1", "0.0.0.0"}
    url_ready = bool(parsed and scheme in {"http", "https"} and parsed.netloc)
    public_https_ready = bool(
        url_ready
        and scheme == "https"
        and host not in local_hosts
        and not host.endswith(".local")
    )
    sha256_ready = bool(re.fullmatch(r"[0-9A-Fa-f]{64}", sha))
    return {
        "downloadUrlReady": url_ready,
        "sha256Ready": sha256_ready,
        "fileReady": bool(url_ready and sha256_ready),
        "publicHttpsReady": bool(public_https_ready and sha256_ready),
    }


def app_release_snapshot_from_row(row) -> Optional[dict]:
    if row is None:
        return None
    return {
        "id": int(row["id"]),
        "platform": row["platform"],
        "channel": row["channel"],
        "version": row["version"],
        "buildNumber": row["build_number"] or "",
        "downloadUrl": row["download_url"] or "",
        "sha256": row["sha256"] or "",
        "sizeBytes": row["size_bytes"],
        "isRequired": bool(row["is_required"]),
        "minSupportedVersion": row["min_supported_version"] or "",
        "rolloutPercent": int(row["rollout_percent"] or 0),
        "status": row["status"],
        "publishedAt": row["published_at"],
        "updatedAt": row["updated_at"],
    }


def published_app_release_rollback_candidate(
    *,
    platform: str,
    channel: str,
    version: str = "",
    exclude_id: Optional[int] = None,
) -> Optional[dict]:
    filters = ["platform = ?", "channel = ?", "status = 'published'"]
    args: list[Any] = [platform, channel]
    if exclude_id is not None:
        filters.append("id != ?")
        args.append(int(exclude_id))
    with db() as conn:
        rows = conn.execute(
            f"""
            SELECT *
            FROM app_releases
            WHERE {" AND ".join(filters)}
            ORDER BY published_at DESC, id DESC
            LIMIT 50
            """,
            tuple(args),
        ).fetchall()
    snapshots = [app_release_snapshot_from_row(row) for row in rows]
    snapshots = [item for item in snapshots if item]
    if version:
        older = [
            item
            for item in snapshots
            if compare_versions(item.get("version"), version) < 0
        ]
        if older:
            return older[0]
    return snapshots[0] if snapshots else None


def environment_rollback_candidate() -> Optional[dict]:
    if not (UPDATE_ROLLBACK_VERSION or UPDATE_ROLLBACK_URL or UPDATE_ROLLBACK_SHA256):
        return None
    return {
        "id": None,
        "platform": "windows",
        "channel": "stable",
        "version": UPDATE_ROLLBACK_VERSION,
        "buildNumber": "",
        "downloadUrl": UPDATE_ROLLBACK_URL,
        "sha256": UPDATE_ROLLBACK_SHA256,
        "sizeBytes": None,
        "isRequired": False,
        "minSupportedVersion": "",
        "rolloutPercent": 100,
        "status": "published",
        "publishedAt": "",
        "updatedAt": "",
    }


def rollback_candidate_with_readiness(candidate: Optional[dict], source: str) -> Optional[dict]:
    if not candidate:
        return None
    artifact = update_artifact_readiness(
        candidate.get("downloadUrl") or candidate.get("download_url"),
        candidate.get("sha256"),
    )
    return {
        "source": source,
        "candidate": candidate,
        "artifact": artifact,
        "ready": bool(artifact.get("publicHttpsReady")),
    }


def app_release_rollback_readiness(release: dict) -> dict:
    platform = normalize_app_release_platform(release.get("platform"), "windows")
    channel = normalize_app_release_channel(release.get("channel"), "stable")
    status = normalize_app_release_status(release.get("status"), "draft")
    version = clean_limited_text(release.get("version"), 120).strip()
    release_id_value = release.get("id")
    try:
        release_id = int(release_id_value) if release_id_value is not None else None
    except (TypeError, ValueError):
        release_id = None
    rollout_percent = normalize_release_rollout_percent(
        release.get("rolloutPercent") if "rolloutPercent" in release else release.get("rollout_percent"),
        100,
    )
    is_required = bool(release.get("isRequired") if "isRequired" in release else release.get("is_required"))
    stable_public_candidate = channel == "stable" and status != "retired"
    required_for_full_rollout = bool(
        stable_public_candidate
        and (is_required or rollout_percent >= 100)
    )

    previous_candidate = rollback_candidate_with_readiness(
        published_app_release_rollback_candidate(
            platform=platform,
            channel=channel,
            version=version,
            exclude_id=release_id,
        ),
        "previous_published_release",
    )
    env_candidate = rollback_candidate_with_readiness(
        environment_rollback_candidate(),
        "environment",
    )
    candidates = [item for item in [previous_candidate, env_candidate] if item]
    selected = next((item for item in candidates if item["ready"]), None)
    if selected is None and candidates:
        selected = candidates[0]

    ready = bool(selected and selected["ready"])
    blockers: list[str] = []
    warnings: list[str] = []
    if required_for_full_rollout and not ready:
        blockers.append("rollback_artifact_missing")
    elif stable_public_candidate and not ready:
        warnings.append("rollback_missing_for_staged_rollout")
    if selected and version and selected.get("candidate", {}).get("version"):
        if compare_versions(selected["candidate"]["version"], version) >= 0:
            warnings.append("rollback_candidate_not_older")

    return {
        "rollbackReady": ready,
        "requiredForPublication": required_for_full_rollout,
        "requiredForFullRollout": required_for_full_rollout,
        "source": selected["source"] if selected else "none",
        "candidate": selected["candidate"] if selected else None,
        "artifact": selected["artifact"] if selected else update_artifact_readiness("", ""),
        "blockers": blockers,
        "warnings": warnings,
        "steps": [
            "Pause or retire the broken published release in admin updates.",
            "Publish the previous stable release or configured rollback artifact with public HTTPS URL and SHA256.",
            "Lower rolloutPercent before retrying required or 100% stable rollout.",
            "Run bluevpn_release_gate.ps1 -StrictPaymentGate and admin updates readiness after rollback.",
        ],
        "summary": (
            "Rollback artifact is ready for full/required rollout."
            if ready
            else "Rollback artifact is missing; keep stable rollout staged until a public HTTPS rollback artifact and SHA256 exist."
        ),
    }


def app_release_publication_readiness(release: dict) -> dict:
    artifact = update_artifact_readiness(
        release.get("downloadUrl") or release.get("download_url"),
        release.get("sha256"),
    )
    channel = normalize_app_release_channel(release.get("channel"), "stable")
    status = normalize_app_release_status(release.get("status"), "draft")
    rollout_percent = normalize_release_rollout_percent(
        release.get("rolloutPercent") if "rolloutPercent" in release else release.get("rollout_percent"),
        100,
    )
    is_required = bool(release.get("isRequired") if "isRequired" in release else release.get("is_required"))
    rollback = app_release_rollback_readiness(release)
    blockers: list[str] = []
    warnings: list[str] = []

    if not clean_limited_text(release.get("version"), 120).strip():
        blockers.append("version_missing")
    if not artifact["fileReady"]:
        blockers.append("artifact_missing")
    if channel == "stable" and not artifact["publicHttpsReady"]:
        blockers.append("stable_requires_public_https")
    if is_required and not artifact["fileReady"]:
        blockers.append("required_update_without_artifact")
    if status == "published" and rollout_percent <= 0:
        warnings.append("published_rollout_zero")
    if channel == "stable" and rollout_percent >= 100 and status != "retired":
        warnings.append("stable_full_rollout")
    blockers.extend(rollback.get("blockers") or [])
    warnings.extend(rollback.get("warnings") or [])

    return {
        **artifact,
        "canPublish": not blockers,
        "blockers": blockers,
        "warnings": warnings,
        "rollbackReadiness": rollback,
        "summary": (
            "Release can be published."
            if not blockers
            else "Release is blocked until artifact/publication requirements are fixed."
        ),
    }


def normalize_release_rollout_percent(value: Optional[int], fallback: int = 100) -> int:
    if value is None:
        value = fallback
    return max(0, min(100, int(value)))


def compare_versions(left: Optional[str], right: Optional[str]) -> int:
    left_clean = clean_limited_text(left, 120).strip()
    right_clean = clean_limited_text(right, 120).strip()
    if left_clean == right_clean:
        return 0
    if not left_clean:
        return -1
    if not right_clean:
        return 1
    left_tokens = re.findall(r"\d+|[A-Za-z]+", left_clean.lower())
    right_tokens = re.findall(r"\d+|[A-Za-z]+", right_clean.lower())
    max_len = max(len(left_tokens), len(right_tokens))
    for index in range(max_len):
        left_part = left_tokens[index] if index < len(left_tokens) else "0"
        right_part = right_tokens[index] if index < len(right_tokens) else "0"
        if left_part == right_part:
            continue
        if left_part.isdigit() and right_part.isdigit():
            left_int = int(left_part)
            right_int = int(right_part)
            if left_int == right_int:
                continue
            return 1 if left_int > right_int else -1
        return 1 if left_part > right_part else -1
    return 0


def rollout_bucket(seed: Optional[str]) -> Optional[int]:
    clean = clean_limited_text(seed, 240).strip()
    if not clean:
        return None
    digest = hashlib.sha256(clean.encode("utf-8")).hexdigest()
    return int(digest[:8], 16) % 100


def release_rollout_decision(
    *,
    current_version: Optional[str],
    latest_version: Optional[str],
    rollout_percent: int,
    required: bool,
    client_id: Optional[str],
) -> dict:
    current = clean_limited_text(current_version, 120).strip()
    latest = clean_limited_text(latest_version, 120).strip()
    base_update_available = bool(current) and bool(latest) and compare_versions(current, latest) < 0
    safe_rollout = normalize_release_rollout_percent(rollout_percent)
    if not base_update_available:
        return {
            "baseUpdateAvailable": False,
            "rolloutEligible": False,
            "rolloutBucket": None,
            "rolloutReason": "current_or_newer",
        }
    if required:
        return {
            "baseUpdateAvailable": True,
            "rolloutEligible": True,
            "rolloutBucket": None,
            "rolloutReason": "required",
        }
    if safe_rollout >= 100:
        return {
            "baseUpdateAvailable": True,
            "rolloutEligible": True,
            "rolloutBucket": None,
            "rolloutReason": "full_rollout",
        }
    if safe_rollout <= 0:
        return {
            "baseUpdateAvailable": True,
            "rolloutEligible": False,
            "rolloutBucket": None,
            "rolloutReason": "rollout_zero",
        }

    bucket = rollout_bucket(client_id)
    if bucket is None:
        return {
            "baseUpdateAvailable": True,
            "rolloutEligible": False,
            "rolloutBucket": None,
            "rolloutReason": "client_id_missing",
        }

    eligible = bucket < safe_rollout
    return {
        "baseUpdateAvailable": True,
        "rolloutEligible": eligible,
        "rolloutBucket": bucket,
        "rolloutReason": "bucket_match" if eligible else "bucket_holdback",
    }


def app_release_workflow_options() -> dict:
    return {
        "platforms": list(APP_RELEASE_PLATFORMS),
        "channels": list(APP_RELEASE_CHANNELS),
        "statuses": list(APP_RELEASE_STATUSES),
    }


def app_release_payload(row) -> dict:
    payload = {
        "id": row["id"],
        "platform": row["platform"],
        "channel": row["channel"],
        "version": row["version"],
        "buildNumber": row["build_number"],
        "downloadUrl": row["download_url"] or "",
        "sha256": row["sha256"] or "",
        "sizeBytes": row["size_bytes"],
        "isRequired": bool(row["is_required"]),
        "minSupportedVersion": row["min_supported_version"],
        "rolloutPercent": int(row["rollout_percent"]),
        "changelog": parse_release_changelog(row["changelog_json"]),
        "status": row["status"],
        "createdAt": row["created_at"],
        "updatedAt": row["updated_at"],
        "publishedAt": row["published_at"],
        "retiredAt": row["retired_at"],
    }
    payload["releaseReadiness"] = app_release_publication_readiness(payload)
    return payload


def list_app_releases(
    platform: Optional[str] = "windows",
    channel: Optional[str] = None,
    status: Optional[str] = None,
    limit: int = 100,
    offset: int = 0,
) -> list[dict]:
    safe_limit = max(1, min(300, int(limit or 100)))
    safe_offset = max(0, int(offset or 0))
    filters = []
    args: list = []
    if platform and platform != "all":
        filters.append("platform = ?")
        args.append(normalize_app_release_platform(platform))
    if channel and channel != "all":
        filters.append("channel = ?")
        args.append(normalize_app_release_channel(channel))
    if status and status != "all":
        filters.append("status = ?")
        args.append(normalize_app_release_status(status))

    query = "SELECT * FROM app_releases"
    if filters:
        query += " WHERE " + " AND ".join(filters)
    query += " ORDER BY id DESC LIMIT ? OFFSET ?"
    args.extend([safe_limit, safe_offset])

    with db() as conn:
        rows = conn.execute(query, tuple(args)).fetchall()
    return [app_release_payload(row) for row in rows]


def latest_published_app_release(platform: str = "windows", channel: str = "stable"):
    with db() as conn:
        return conn.execute(
            """
            SELECT *
            FROM app_releases
            WHERE platform = ? AND channel = ? AND status = 'published'
            ORDER BY published_at DESC, id DESC
            LIMIT 1
            """,
            (platform, channel),
        ).fetchone()


def upsert_app_release(payload: AdminAppReleaseIn, release_id: Optional[int] = None) -> dict:
    now = utc_now_iso()
    with db() as conn:
        existing = None
        if release_id is not None:
            existing = conn.execute(
                "SELECT * FROM app_releases WHERE id = ?",
                (release_id,),
            ).fetchone()
            if not existing:
                raise HTTPException(status_code=404, detail="Release not found.")

        platform = normalize_app_release_platform(
            payload.platform if payload.platform is not None else (existing["platform"] if existing else "windows")
        )
        channel = normalize_app_release_channel(
            payload.channel if payload.channel is not None else (existing["channel"] if existing else "stable")
        )
        version = clean_limited_text(
            payload.version if payload.version is not None else (existing["version"] if existing else ""),
            120,
        ).strip()
        if not version:
            raise HTTPException(status_code=400, detail="Release version is required.")
        build_number = clean_limited_text(
            payload.buildNumber if payload.buildNumber is not None else (existing["build_number"] if existing else ""),
            120,
        ).strip()
        download_url = validate_release_download_url(
            payload.downloadUrl if payload.downloadUrl is not None else (existing["download_url"] if existing else "")
        )
        sha256 = validate_release_sha256(
            payload.sha256 if payload.sha256 is not None else (existing["sha256"] if existing else "")
        )
        size_bytes = payload.sizeBytes if payload.sizeBytes is not None else (existing["size_bytes"] if existing else None)
        if size_bytes is not None:
            size_bytes = max(0, int(size_bytes))
        is_required = (
            1 if payload.isRequired else 0
        ) if payload.isRequired is not None else (int(existing["is_required"]) if existing else 0)
        min_supported_version = clean_limited_text(
            payload.minSupportedVersion
            if payload.minSupportedVersion is not None
            else (existing["min_supported_version"] if existing else ""),
            120,
        ).strip()
        rollout_percent = normalize_release_rollout_percent(
            payload.rolloutPercent,
            int(existing["rollout_percent"]) if existing else 100,
        )
        changelog = sanitize_release_changelog(
            payload.changelog
            if payload.changelog is not None
            else parse_release_changelog(existing["changelog_json"] if existing else "")
        )
        changelog_json = json.dumps(changelog, ensure_ascii=False)
        status = normalize_app_release_status(
            payload.status if payload.status is not None else (existing["status"] if existing else "draft")
        )
        publication_gate = app_release_publication_readiness(
            {
                "id": existing["id"] if existing else None,
                "platform": platform,
                "channel": channel,
                "version": version,
                "downloadUrl": download_url,
                "sha256": sha256,
                "isRequired": bool(is_required),
                "rolloutPercent": rollout_percent,
                "status": status,
            }
        )
        if status == "published" and not publication_gate["canPublish"]:
            raise HTTPException(
                status_code=400,
                detail=f"Published release blocked: {', '.join(publication_gate['blockers'])}.",
            )
        published_at = existing["published_at"] if existing else None
        retired_at = existing["retired_at"] if existing else None
        if status == "published" and not published_at:
            published_at = now
        if status == "retired" and not retired_at:
            retired_at = now

        try:
            if existing:
                conn.execute(
                    """
                    UPDATE app_releases
                    SET platform = ?, channel = ?, version = ?, build_number = ?,
                        download_url = ?, sha256 = ?, size_bytes = ?, is_required = ?,
                        min_supported_version = ?, rollout_percent = ?, changelog_json = ?,
                        status = ?, updated_at = ?, published_at = ?, retired_at = ?
                    WHERE id = ?
                    """,
                    (
                        platform,
                        channel,
                        version,
                        build_number,
                        download_url,
                        sha256,
                        size_bytes,
                        is_required,
                        min_supported_version,
                        rollout_percent,
                        changelog_json,
                        status,
                        now,
                        published_at,
                        retired_at,
                        existing["id"],
                    ),
                )
                release_pk = existing["id"]
            else:
                duplicate = conn.execute(
                    """
                    SELECT * FROM app_releases
                    WHERE platform = ? AND channel = ? AND version = ?
                    """,
                    (platform, channel, version),
                ).fetchone()
                if duplicate:
                    return upsert_app_release(payload, duplicate["id"])
                cursor = conn.execute(
                    """
                    INSERT INTO app_releases(
                        platform, channel, version, build_number, download_url, sha256,
                        size_bytes, is_required, min_supported_version, rollout_percent,
                        changelog_json, status, created_at, updated_at, published_at, retired_at
                    )
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    """,
                    (
                        platform,
                        channel,
                        version,
                        build_number,
                        download_url,
                        sha256,
                        size_bytes,
                        is_required,
                        min_supported_version,
                        rollout_percent,
                        changelog_json,
                        status,
                        now,
                        now,
                        published_at,
                        retired_at,
                    ),
                )
                release_pk = cursor.lastrowid
            conn.commit()
            row = conn.execute("SELECT * FROM app_releases WHERE id = ?", (release_pk,)).fetchone()
        except sqlite3.IntegrityError:
            raise HTTPException(status_code=409, detail="Release with this platform/channel/version already exists.")

    return app_release_payload(row)


def apply_update_artifact_guard(manifest: dict, configured_required: bool) -> dict:
    artifact = update_artifact_readiness(
        manifest.get("downloadUrl"),
        manifest.get("sha256"),
    )
    base_update_available = bool(manifest.get("baseUpdateAvailable"))
    rollout_eligible = bool(manifest.get("rolloutEligible"))
    if base_update_available and not artifact["fileReady"]:
        rollout_eligible = False
        manifest["rolloutEligible"] = False
        manifest["rolloutReason"] = "artifact_missing"

    effective_required = bool(configured_required and artifact["fileReady"])
    manifest["required"] = effective_required
    manifest["configuredRequired"] = bool(configured_required)
    manifest["updateAvailable"] = bool(
        base_update_available
        and rollout_eligible
        and artifact["fileReady"]
    )
    manifest["releaseBlocked"] = bool(configured_required and not artifact["fileReady"])
    manifest["blockingReason"] = (
        "required_update_without_artifact"
        if manifest["releaseBlocked"]
        else ""
    )
    manifest.update(artifact)
    return manifest


def build_update_manifest(
    *,
    platform: str = "windows",
    channel: str = "stable",
    current_version: Optional[str] = None,
    client_id: Optional[str] = None,
) -> dict:
    platform = normalize_app_release_platform(platform)
    channel = normalize_app_release_channel(channel)
    current = clean_limited_text(current_version, 120).strip()
    row = latest_published_app_release(platform, channel)
    if row:
        release = app_release_payload(row)
        min_supported = release.get("minSupportedVersion") or ""
        configured_required = bool(release.get("isRequired")) or (
            bool(current)
            and bool(min_supported)
            and compare_versions(current, min_supported) < 0
        )
        rollout_percent = normalize_release_rollout_percent(release.get("rolloutPercent", 100))
        rollout = release_rollout_decision(
            current_version=current,
            latest_version=release["version"],
            rollout_percent=rollout_percent,
            required=configured_required,
            client_id=client_id,
        )
        manifest = {
            "platform": platform,
            "channel": channel,
            "currentVersion": current,
            "latestVersion": release["version"],
            "buildNumber": release.get("buildNumber"),
            "downloadUrl": release.get("downloadUrl") or "",
            "sha256": release.get("sha256") or "",
            "sizeBytes": release.get("sizeBytes"),
            "required": configured_required,
            "minSupportedVersion": min_supported,
            "rolloutPercent": rollout_percent,
            "updateAvailable": bool(rollout["baseUpdateAvailable"]) and bool(rollout["rolloutEligible"]),
            **rollout,
            "releasedAt": release.get("publishedAt") or release.get("updatedAt") or "",
            "changelog": release.get("changelog") or [],
            "source": "database",
        }
        return apply_update_artifact_guard(manifest, configured_required)

    latest = UPDATE_LATEST_VERSION or (current or "0.2.1-windows-mvp")
    rollout = release_rollout_decision(
        current_version=current,
        latest_version=latest,
        rollout_percent=100,
        required=UPDATE_REQUIRED,
        client_id=client_id,
    )
    manifest = {
        "platform": platform,
        "channel": channel,
        "currentVersion": current,
        "latestVersion": latest,
        "buildNumber": "",
        "downloadUrl": UPDATE_DOWNLOAD_URL,
        "sha256": UPDATE_SHA256,
        "sizeBytes": None,
        "required": UPDATE_REQUIRED,
        "minSupportedVersion": "",
        "rolloutPercent": 100,
        "updateAvailable": bool(rollout["baseUpdateAvailable"]) and bool(rollout["rolloutEligible"]),
        **rollout,
        "releasedAt": UPDATE_RELEASED_AT,
        "changelog": UPDATE_CHANGELOG,
        "source": "environment",
    }
    return apply_update_artifact_guard(manifest, UPDATE_REQUIRED)


def build_windows_update_manifest(
    current_version: Optional[str] = None,
    client_id: Optional[str] = None,
) -> dict:
    return build_update_manifest(
        platform="windows",
        channel="stable",
        current_version=current_version,
        client_id=client_id,
    )


def build_update_release_readiness(
    platform: str = "windows",
    channel: str = "stable",
) -> dict:
    platform = normalize_app_release_platform(platform)
    channel = normalize_app_release_channel(channel)
    manifest = build_update_manifest(
        platform=platform,
        channel=channel,
        current_version=APP_VERSION,
        client_id="admin-readiness",
    )
    latest_row = latest_published_app_release(platform, channel)
    latest_release = app_release_payload(latest_row) if latest_row else None
    latest_release_readiness = (latest_release or {}).get("releaseReadiness") or {}
    rollback_readiness = latest_release_readiness.get("rollbackReadiness") or {
        "rollbackReady": False,
        "requiredForPublication": False,
        "requiredForFullRollout": False,
        "source": "none",
        "candidate": None,
        "artifact": update_artifact_readiness("", ""),
        "blockers": ["published_release_missing"],
        "warnings": [],
        "steps": [
            "Create a published database release after the final installer artifact exists.",
            "Configure a previous published release or GREENVPN_ROLLBACK_* artifact before full/required stable rollout.",
        ],
        "summary": "No published release exists yet, so rollback readiness cannot be proven.",
    }
    checks = [
        {
            "code": "published_release",
            "title": "Published release record",
            "ok": latest_release is not None,
            "message": (
                "Updater uses a controlled database release record."
                if latest_release
                else "No published database release; manifest falls back to environment defaults."
            ),
        },
        {
            "code": "download_artifact",
            "title": "Download artifact",
            "ok": bool(manifest.get("fileReady")),
            "message": (
                "downloadUrl and SHA256 are both present and parseable."
                if manifest.get("fileReady")
                else "Publish a final installer URL and 64-character SHA256 before user rollout."
            ),
        },
        {
            "code": "public_https_download",
            "title": "Public HTTPS download",
            "ok": bool(manifest.get("publicHttpsReady")),
            "message": (
                "Release download is served over public HTTPS."
                if manifest.get("publicHttpsReady")
                else "Stable public releases must use an HTTPS download URL, not localhost or plain HTTP."
            ),
        },
        {
            "code": "required_update_guard",
            "title": "Required update guard",
            "ok": not bool(manifest.get("releaseBlocked")),
            "message": (
                "Required-update flag is safe for the current artifact state."
                if not manifest.get("releaseBlocked")
                else "Required update was configured without a ready artifact and is suppressed in the client manifest."
            ),
        },
        {
            "code": "release_publication_gate",
            "title": "Release publication gate",
            "ok": bool(latest_release_readiness.get("canPublish")) if latest_release else False,
            "message": (
                latest_release_readiness.get("summary")
                if latest_release
                else "No published release is available for publication gate checks."
            ),
        },
        {
            "code": "rollback_plan",
            "title": "Rollback plan",
            "ok": bool(rollback_readiness.get("rollbackReady")) if latest_release else False,
            "message": (
                rollback_readiness.get("summary")
                if latest_release
                else "No published release is available for rollback readiness checks."
            ),
        },
        {
            "code": "installer_cadence",
            "title": "Final-only installer cadence",
            "ok": True,
            "message": "Do not rebuild or clean-install Green VPN until the final handoff/test installer.",
        },
    ]
    missing = [check for check in checks if not check["ok"]]
    return {
        "ok": True,
        "version": APP_VERSION,
        "generatedAt": utc_now_iso(),
        "platform": platform,
        "channel": channel,
        "productionReady": len(missing) == 0,
        "summary": {
            "green": len(checks) - len(missing),
            "yellow": len(missing),
            "red": 0,
            "message": (
                "Windows updater release path is ready."
                if not missing
                else "Windows updater is staged but needs final artifact/release data."
            ),
        },
        "checks": checks,
        "requiredActions": [check["message"] for check in missing],
        "manifest": manifest,
        "latestPublishedRelease": latest_release,
        "latestReleaseReadiness": latest_release_readiness,
        "rollbackReadiness": rollback_readiness,
    }


def find_catalog_server(server_id: Optional[str]) -> Optional[dict]:
    if not server_id or server_id == "auto":
        return None
    catalog = build_server_catalog()
    for item in catalog["servers"]:
        if item["id"] == server_id:
            return item
    return None


def allocate_ip() -> str:
    with db() as conn:
        rows = conn.execute(
            "SELECT assigned_ip FROM devices WHERE assigned_ip IS NOT NULL"
        ).fetchall()

    used = {row["assigned_ip"] for row in rows if row["assigned_ip"]}
    used.add("10.10.0.1")
    used.add("10.10.0.3")

    for host in range(WG_CLIENT_IP_START, WG_CLIENT_IP_END + 1):
        ip = f"{WG_CLIENT_IP_PREFIX}{host}"
        if ip not in used:
            return ip

    raise HTTPException(status_code=500, detail="No free client IPs left.")


def device_status(device_row) -> dict:
    return {
        "deviceUid": device_row["device_uid"],
        "deviceName": device_row["device_name"],
        "platform": device_row["platform"],
        "appVersion": device_row["app_version"],
        "assignedIp": device_row["assigned_ip"],
        "isEnabled": bool(device_row["is_enabled"]),
        "disabledReason": device_row["disabled_reason"],
        "disabledAt": device_row["disabled_at"],
        "lastSeenAt": device_row["last_seen_at"],
        "lastConfigAt": device_row["last_config_at"],
        "supportConfigRefreshRequestedAt": device_row[
            "support_config_refresh_requested_at"
        ],
        "supportConfigRefreshReason": device_row["support_config_refresh_reason"],
        "supportConfigRefreshRequestedBy": device_row[
            "support_config_refresh_requested_by"
        ],
        "supportConfigRefreshAppliedAt": device_row[
            "support_config_refresh_applied_at"
        ],
        "supportConfigRefreshAppliedReason": device_row[
            "support_config_refresh_applied_reason"
        ],
        "createdAt": device_row["created_at"],
        "updatedAt": device_row["updated_at"],
    }


def touch_device(device_uid: str, *, config_issued: bool) -> None:
    now = utc_now_iso()
    with db() as conn:
        if config_issued:
            conn.execute(
                """
                UPDATE devices
                SET last_seen_at = ?, last_config_at = ?, updated_at = ?
                WHERE device_uid = ?
                """,
                (now, now, now, device_uid),
            )
        else:
            conn.execute(
                """
                UPDATE devices
                SET last_seen_at = ?, updated_at = ?
                WHERE device_uid = ?
                """,
                (now, now, device_uid),
            )
        conn.commit()


def set_device_enabled(device_uid: str, enabled: bool, reason: Optional[str]) -> dict:
    now = utc_now_iso()
    with db() as conn:
        row = conn.execute(
            "SELECT * FROM devices WHERE device_uid = ?",
            (device_uid,),
        ).fetchone()
        if row is None:
            raise HTTPException(status_code=404, detail="Device not found.")

        conn.execute(
            """
            UPDATE devices
            SET is_enabled = ?, disabled_reason = ?, disabled_at = ?, updated_at = ?
            WHERE device_uid = ?
            """,
            (
                1 if enabled else 0,
                None if enabled else (reason or "disabled_by_admin"),
                None if enabled else now,
                now,
                device_uid,
            ),
        )
        conn.commit()

        row = conn.execute(
            "SELECT * FROM devices WHERE device_uid = ?",
            (device_uid,),
        ).fetchone()

    return device_status(row)


def list_user_devices(user_id: int) -> list[dict]:
    with db() as conn:
        rows = conn.execute(
            """
            SELECT *
            FROM devices
            WHERE user_id = ?
            ORDER BY updated_at DESC, id DESC
            """,
            (user_id,),
        ).fetchall()
    return [device_status(row) for row in rows]


def enabled_device_count(conn: sqlite3.Connection, user_id: int) -> int:
    row = conn.execute(
        "SELECT COUNT(*) AS cnt FROM devices WHERE user_id = ? AND is_enabled = 1",
        (user_id,),
    ).fetchone()
    return int(row["cnt"]) if row else 0


def enforce_device_limit_for_current_device(
    conn: sqlite3.Connection,
    *,
    user_id: int,
    current_device_uid: str,
    max_devices: int,
) -> int:
    max_devices = max(1, int(max_devices or 1))
    count = enabled_device_count(conn, user_id)
    if count <= max_devices:
        return count

    if not AUTO_REPLACE_OLDEST_DEVICE_ON_LIMIT:
        return count

    now = utc_now_iso()
    rows = conn.execute(
        """
        SELECT *
        FROM devices
        WHERE user_id = ? AND is_enabled = 1 AND device_uid != ?
        ORDER BY
            COALESCE(last_config_at, last_seen_at, updated_at, created_at) ASC,
            id ASC
        """,
        (user_id, current_device_uid),
    ).fetchall()

    for row in rows:
        if count <= max_devices:
            break
        conn.execute(
            """
            UPDATE devices
            SET is_enabled = 0,
                disabled_reason = ?,
                disabled_at = ?,
                updated_at = ?
            WHERE id = ?
            """,
            ("auto_replaced_by_new_device", now, now, row["id"]),
        )
        count -= 1

    return enabled_device_count(conn, user_id)


def list_admin_users(q: Optional[str] = None, limit: int = 100) -> list[dict]:
    out: list[dict] = []
    safe_limit = max(1, min(500, int(limit or 100)))
    q_clean = clean_limited_text(q, 180).strip().lower() if q else ""
    filters = []
    args: list = []
    if q_clean:
        pattern = f"%{q_clean}%"
        filters.append(
            """
            (
                LOWER(u.email) LIKE ?
                OR LOWER(COALESCE(u.phone, '')) LIKE ?
                OR EXISTS (
                    SELECT 1
                    FROM devices sd
                    WHERE sd.user_id = u.id
                      AND LOWER(sd.device_uid) LIKE ?
                )
            )
            """
        )
        args.extend([pattern, pattern, pattern])

    query = """
        SELECT
            u.id,
            u.email,
            u.email_verified,
            u.phone,
            u.phone_verified,
            u.created_at,
            COUNT(d.id) AS device_count,
            COALESCE(SUM(CASE WHEN d.is_enabled = 1 THEN 1 ELSE 0 END), 0) AS enabled_device_count,
            MAX(d.last_seen_at) AS last_seen_at,
            MAX(d.last_config_at) AS last_config_at
        FROM users u
        LEFT JOIN devices d ON d.user_id = u.id
    """
    if filters:
        query += " WHERE " + " AND ".join(filters)
    query += """
        GROUP BY u.id, u.email, u.email_verified, u.phone, u.phone_verified, u.created_at
        ORDER BY u.id ASC
        LIMIT ?
    """
    args.append(safe_limit)

    with db() as conn:
        rows = conn.execute(query, tuple(args)).fetchall()

    for row in rows:
        sub = subscription_status(get_subscription_row(row["id"]))
        out.append(
            {
                "id": row["id"],
                "email": row["email"],
                "emailVerified": bool(row["email_verified"]),
                "phone": row["phone"],
                "phoneVerified": bool(row["phone_verified"]),
                "createdAt": row["created_at"],
                "deviceCount": int(row["device_count"]),
                "enabledDeviceCount": int(row["enabled_device_count"]),
                "disabledDeviceCount": max(
                    0,
                    int(row["device_count"]) - int(row["enabled_device_count"]),
                ),
                "lastSeenAt": row["last_seen_at"],
                "lastConfigAt": row["last_config_at"],
                "subscription": sub,
            }
        )
    return out


def get_admin_user_detail(user_id: int) -> dict:
    with db() as conn:
        row = conn.execute(
            """
            SELECT
                u.id,
                u.email,
                u.email_verified,
                u.phone,
                u.phone_verified,
                u.created_at,
                COUNT(d.id) AS device_count,
                COALESCE(SUM(CASE WHEN d.is_enabled = 1 THEN 1 ELSE 0 END), 0) AS enabled_device_count,
                MAX(d.last_seen_at) AS last_seen_at,
                MAX(d.last_config_at) AS last_config_at
            FROM users u
            LEFT JOIN devices d ON d.user_id = u.id
            WHERE u.id = ?
            GROUP BY u.id, u.email, u.email_verified, u.phone, u.phone_verified, u.created_at
            """,
            (int(user_id),),
        ).fetchone()
    if row is None:
        raise HTTPException(status_code=404, detail="User not found.")
    user = {
        "id": row["id"],
        "email": row["email"],
        "emailVerified": bool(row["email_verified"]),
        "phone": row["phone"],
        "phoneVerified": bool(row["phone_verified"]),
        "createdAt": row["created_at"],
        "deviceCount": int(row["device_count"]),
        "enabledDeviceCount": int(row["enabled_device_count"]),
        "disabledDeviceCount": max(
            0,
            int(row["device_count"]) - int(row["enabled_device_count"]),
        ),
        "lastSeenAt": row["last_seen_at"],
        "lastConfigAt": row["last_config_at"],
        "subscription": subscription_status(get_subscription_row(user_id)),
    }
    return {
        "user": user,
        "devices": list_user_devices(user_id),
        "orders": list_billing_orders_for_user(user_id),
        "supportReports": list_support_reports(user_id=user_id, limit=50),
        "supportActions": list_admin_support_actions(user_id=user_id, limit=50),
        "subscription": subscription_status(get_subscription_row(user_id)),
    }


def upsert_subscription_for_user(user_id: int, payload: AdminSubscriptionIn) -> dict:
    expires_at: Optional[str] = None
    if payload.expiresAt:
        expires_at = parse_dt(payload.expiresAt).isoformat()

    now = utc_now_iso()
    with db() as conn:
        current = conn.execute(
            """
            SELECT id
            FROM subscriptions
            WHERE user_id = ?
            ORDER BY id DESC
            LIMIT 1
            """,
            (user_id,),
        ).fetchone()

        if current is None:
            conn.execute(
                """
                INSERT INTO subscriptions(
                    user_id, plan_code, plan_name, max_devices, is_active,
                    expires_at, created_at, updated_at
                )
                VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                """,
                (
                    user_id,
                    payload.planCode.strip(),
                    payload.planName.strip(),
                    payload.maxDevices,
                    1 if payload.isActive else 0,
                    expires_at,
                    now,
                    now,
                ),
            )
        else:
            conn.execute(
                """
                UPDATE subscriptions
                SET plan_code = ?, plan_name = ?, max_devices = ?, is_active = ?,
                    expires_at = ?, updated_at = ?
                WHERE id = ?
                """,
                (
                    payload.planCode.strip(),
                    payload.planName.strip(),
                    payload.maxDevices,
                    1 if payload.isActive else 0,
                    expires_at,
                    now,
                    current["id"],
                ),
            )

        conn.commit()

    return subscription_status(get_subscription_row(user_id))


def apply_tariff_for_user(
    user_id: int,
    payload: TariffSelectionIn,
    provider_payment_method_id: Optional[str] = None,
    quote_override: Optional[dict] = None,
) -> dict:
    normalized = normalize_tariff_selection(payload)
    quote = quote_override or quote_tariff(
        normalized,
        strict_promo=bool(normalized.get("promoCode")),
    )
    now = utc_now()
    expires_at = (now + timedelta(days=PAID_PLAN_DAYS)).isoformat()
    selection_json = json.dumps(normalized, ensure_ascii=False)
    auto_renew = bool(normalized.get("autoRenew", False))
    saved_payment_method_id = provider_payment_method_id if auto_renew else None

    with db() as conn:
        current = conn.execute(
            """
            SELECT id
            FROM subscriptions
            WHERE user_id = ?
            ORDER BY id DESC
            LIMIT 1
            """,
            (user_id,),
        ).fetchone()

        if current is None:
            conn.execute(
                """
                INSERT INTO subscriptions(
                    user_id, plan_code, plan_name, max_devices, is_active,
                    expires_at, created_at, updated_at, monthly_price_rub,
                    selection_json, auto_renew, provider_payment_method_id
                )
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                (
                    user_id,
                    quote["planCode"],
                    quote["planName"],
                    normalized["devices"],
                    1,
                    expires_at,
                    now.isoformat(),
                    now.isoformat(),
                    int(quote["monthlyPriceRub"]),
                    selection_json,
                    1 if auto_renew else 0,
                    saved_payment_method_id,
                ),
            )
        else:
            conn.execute(
                """
                UPDATE subscriptions
                SET plan_code = ?, plan_name = ?, max_devices = ?, is_active = ?,
                    expires_at = ?, updated_at = ?, monthly_price_rub = ?,
                    selection_json = ?, auto_renew = ?,
                    provider_payment_method_id = CASE
                        WHEN ? = 1 THEN COALESCE(?, provider_payment_method_id)
                        ELSE NULL
                    END
                WHERE id = ?
                """,
                (
                    quote["planCode"],
                    quote["planName"],
                    normalized["devices"],
                    1,
                    expires_at,
                    now.isoformat(),
                    int(quote["monthlyPriceRub"]),
                    selection_json,
                    1 if auto_renew else 0,
                    1 if auto_renew else 0,
                    saved_payment_method_id,
                    current["id"],
                ),
            )
        conn.commit()

    saved = subscription_status(get_subscription_row(user_id))
    return {
        "selection": normalized,
        "quote": quote,
        "subscription": saved,
    }


def billing_order_status(row) -> dict:
    selection = {}
    quote = {}
    try:
        selection = json.loads(row["selection_json"])
    except Exception:
        selection = {}
    try:
        quote = json.loads(row["quote_json"])
    except Exception:
        quote = {}

    return {
        "orderId": row["public_id"],
        "userId": row["user_id"],
        "status": row["status"],
        "autoRenew": bool(row["auto_renew"]) if "auto_renew" in row.keys() else bool(selection.get("autoRenew", True)),
        "amountRub": int(row["amount_rub"]),
        "originalAmountRub": (
            int(row["original_amount_rub"] or 0)
            if "original_amount_rub" in row.keys()
            else int(quote.get("originalMonthlyPriceRub") or row["amount_rub"])
        ),
        "discountRub": (
            int(row["discount_rub"] or 0)
            if "discount_rub" in row.keys()
            else int(quote.get("discountRub") or 0)
        ),
        "promoCode": (
            row["promo_code"]
            if "promo_code" in row.keys()
            else (
                quote.get("promo", {}).get("code")
                if isinstance(quote.get("promo"), dict)
                else selection.get("promoCode")
            )
        ),
        "currency": row["currency"],
        "selection": selection,
        "quote": quote,
        "paymentUrl": row["payment_url"],
        "provider": row["provider"],
        "providerPaymentId": row["provider_payment_id"],
        "providerPaymentMethodId": row["provider_payment_method_id"] if "provider_payment_method_id" in row.keys() else None,
        "paidAt": row["paid_at"],
        "activatedAt": row["activated_at"],
        "createdAt": row["created_at"],
        "updatedAt": row["updated_at"],
    }


def public_billing_order_status(order: dict) -> dict:
    public_order = dict(order)
    public_order.pop("providerPaymentId", None)
    public_order.pop("providerPaymentMethodId", None)
    return public_order


def yookassa_configured() -> bool:
    return bool(YOOKASSA_SHOP_ID and YOOKASSA_SECRET_KEY)


def _is_https_url(url: str) -> bool:
    try:
        parsed = urllib.parse.urlparse(url)
    except Exception:
        return False
    return parsed.scheme == "https" and bool(parsed.netloc)


def _url_host(url: str) -> str:
    try:
        return urllib.parse.urlparse(url).hostname or ""
    except Exception:
        return ""


def _normalize_ip(value: str) -> str:
    try:
        return str(ipaddress.ip_address((value or "").strip("[] ")))
    except Exception:
        return ""


def _resolve_host_ips(host: str) -> list[str]:
    normalized_host = (host or "").strip().strip("[]")
    if not normalized_host:
        return []
    direct_ip = _normalize_ip(normalized_host)
    if direct_ip:
        return [direct_ip]
    ips: set[str] = set()
    try:
        for item in socket.getaddrinfo(normalized_host, None):
            sockaddr = item[4]
            if sockaddr:
                ip = _normalize_ip(str(sockaddr[0]))
                if ip:
                    ips.add(ip)
    except Exception:
        return []
    return sorted(ips)


def _configured_public_api_urls() -> list[str]:
    urls: list[str] = []
    for value in [PUBLIC_API_BASE_URL, PUBLIC_BASE_URL, PUBLIC_SITE_URL, *SERVER_CATALOG_API_BASE_URLS]:
        cleaned = clean_base_url(str(value or ""))
        if cleaned and cleaned not in urls:
            urls.append(cleaned)
    return urls


def build_api_vpn_split_migration_plan(
    api_urls: list[str],
    api_hosts: list[str],
    api_host_ips: dict[str, list[str]],
    vpn_host: str,
    vpn_ips: list[str],
    overlap: list[str],
    unresolved_hosts: list[str],
    production_ready: bool,
) -> dict:
    api_host = "api.greenvpn.pro"
    if api_host not in api_hosts and api_hosts:
        api_host = api_hosts[0]
    vpn_target_host = "nl1.vpn.greenvpn.pro"
    current_vpn_target = vpn_ips[0] if vpn_ips else vpn_host
    needs_split = bool(overlap) or not production_ready
    api_current_ips = sorted({
        ip
        for host in api_hosts
        for ip in api_host_ips.get(host, [])
    })

    phases = [
        {
            "code": "prepare_api_site_ip",
            "title": "Подготовить отдельный IP для сайта/API",
            "owner": "owner_or_ops",
            "status": "done" if production_ready else "pending",
            "details": (
                "Нужен отдельный VPS/reverse proxy для api.greenvpn.pro и публичного сайта. "
                "Этот IP не должен совпадать с VPN endpoint."
            ),
            "secret": False,
        },
        {
            "code": "publish_vpn_hostname",
            "title": "Выделить DNS-имя для VPN-сервера",
            "owner": "owner_or_ops",
            "status": "pending" if needs_split else "done",
            "details": (
                f"Создать A-запись {vpn_target_host} -> {current_vpn_target}. "
                "Клиентские конфиги должны получать DNS-имя VPN, а не адрес API."
            ),
            "secret": False,
        },
        {
            "code": "move_api_dns",
            "title": "Перенести api.greenvpn.pro на отдельный IP",
            "owner": "owner_or_ops",
            "status": "blocked" if overlap else ("pending" if unresolved_hosts else "done"),
            "details": (
                f"DNS {api_host} должен смотреть на отдельный API/site IP. "
                "После переноса HTTPS /healthz должен отвечать с нового IP."
            ),
            "secret": False,
        },
        {
            "code": "apply_backend_env",
            "title": "Применить серверные env после DNS",
            "owner": "ops",
            "status": "pending" if needs_split else "done",
            "details": (
                "Через configure_backend_env_wsl.ps1 закрепить публичные URL и endpoint: "
                "GREENVPN_PUBLIC_API_BASE_URL, GREENVPN_PUBLIC_BASE_URL, "
                "GREENVPN_EMAIL_PUBLIC_BASE_URL, GREENVPN_API_BASE_URLS, BLUEVPN_ENDPOINT_HOST."
            ),
            "secret": False,
        },
        {
            "code": "verify_full_tunnel",
            "title": "Проверить доступ при включенном VPN",
            "owner": "ops",
            "status": "pending" if needs_split else "done",
            "details": (
                "Проверить https://api.greenvpn.pro/healthz и админку с выключенным и включенным "
                "Green VPN. ERR_NETWORK_ACCESS_DENIED не должен повторяться."
            ),
            "secret": False,
        },
    ]

    dns_records = [
        {
            "type": "A",
            "name": api_host,
            "target": "new-api-site-ip",
            "current": api_host_ips.get(api_host, api_current_ips),
            "status": "needs_change" if overlap else "ok",
            "note": "Публичный API/сайт. Не использовать IP VPN endpoint.",
        },
        {
            "type": "A",
            "name": vpn_target_host,
            "target": current_vpn_target,
            "current": _resolve_host_ips(vpn_target_host),
            "status": "needs_create" if needs_split else "ok",
            "note": "Публичный WireGuard endpoint. Можно оставить текущий IP VPN-сервера.",
        },
    ]
    preflight_script = (
        r"C:\Users\gekto\projects\bluevpn\scripts\windows\check_api_vpn_split_preflight.ps1"
    )
    preflight_command = (
        r"powershell -NoProfile -ExecutionPolicy Bypass -File "
        + preflight_script
        + rf" -ApiBase https://{api_host}"
        + rf" -VpnEndpointHost {vpn_target_host}"
        + rf" -ExpectedVpnIp {current_vpn_target}"
        + r" -ExpectedApiIp <new-api-site-ip> -Json"
    )

    return {
        "ok": True,
        "ready": production_ready,
        "requiresOwnerAction": needs_split,
        "targetArchitecture": {
            "publicApiHost": api_host,
            "publicApiUrls": api_urls,
            "publicApiRole": "site_api_reverse_proxy",
            "vpnEndpointHost": vpn_target_host,
            "vpnEndpointTarget": current_vpn_target,
            "currentVpnEndpointHost": vpn_host,
            "currentOverlapIps": overlap,
        },
        "safeEnvKeys": [
            {"envKey": "GREENVPN_PUBLIC_API_BASE_URL", "value": "https://api.greenvpn.pro"},
            {"envKey": "GREENVPN_PUBLIC_BASE_URL", "value": "https://api.greenvpn.pro"},
            {"envKey": "GREENVPN_EMAIL_PUBLIC_BASE_URL", "value": "https://api.greenvpn.pro"},
            {"envKey": "GREENVPN_API_BASE_URLS", "value": "https://api.greenvpn.pro"},
            {"envKey": "BLUEVPN_ENDPOINT_HOST", "value": vpn_target_host},
        ],
        "dnsRecords": dns_records,
        "phases": phases,
        "preflight": {
            "script": preflight_script,
            "command": preflight_command,
            "when": "Run after the candidate API/site IP or reverse proxy and VPN endpoint DNS record are prepared.",
            "secret": False,
            "mutationFree": True,
            "checks": [
                "API base is HTTPS",
                "api.greenvpn.pro resolves to the expected API/site IP",
                f"{vpn_target_host} resolves to the expected VPN endpoint IP",
                "API/site and VPN endpoint IPs do not overlap",
                "GET /healthz responds on the public API base",
            ],
        },
        "verification": [
            preflight_command,
            "GET https://api.greenvpn.pro/healthz без VPN",
            "GET https://api.greenvpn.pro/healthz через Green VPN",
            "GET /api/v1/admin/network/readiness",
            "GET /api/v1/admin/network/split-plan",
            "check_external_services_readiness.ps1 -ServerAdminSelfCheck",
        ],
        "notes": [
            "План не содержит секретов и не меняет DNS сам.",
            "Публичный Windows installer не пересобирать до финальной проверки релиза.",
            "Внутренние имена BlueVPN/WireGuardTunnel$BlueVPNDev1 не переименовывать.",
        ],
    }


def api_vpn_endpoint_separation_readiness() -> dict:
    api_urls = _configured_public_api_urls()
    api_hosts = sorted({host for host in (_url_host(url) for url in api_urls) if host})
    vpn_host = WG_ENDPOINT_HOST.strip()
    api_host_ips = {host: _resolve_host_ips(host) for host in api_hosts}
    vpn_ips = _resolve_host_ips(vpn_host)
    api_ip_set = {
        ip
        for ips in api_host_ips.values()
        for ip in ips
    }
    overlap = sorted(api_ip_set.intersection(set(vpn_ips)))
    unresolved_hosts = [
        host for host, ips in api_host_ips.items() if not ips and _normalize_ip(host) == ""
    ]
    checks = [
        {
            "code": "public_api_https",
            "ok": bool(api_urls) and all(_is_https_url(url) for url in api_urls),
            "message": "All public API/site URLs must be HTTPS.",
            "value": api_urls,
        },
        {
            "code": "public_api_dns_resolves",
            "ok": bool(api_hosts) and not unresolved_hosts,
            "message": "Public API/site hostnames must resolve in DNS.",
            "value": api_host_ips,
            "unresolvedHosts": unresolved_hosts,
        },
        {
            "code": "vpn_endpoint_resolves",
            "ok": bool(vpn_ips),
            "message": "VPN endpoint host must resolve before public rollout.",
            "value": vpn_ips,
        },
        {
            "code": "api_vpn_ip_split",
            "ok": bool(api_ip_set) and bool(vpn_ips) and not overlap,
            "message": (
                "Public API/site must not share an IP with the VPN endpoint; full-tunnel "
                "clients can block access to their own control plane."
            ),
            "overlap": overlap,
        },
    ]
    production_ready = all(check["ok"] for check in checks)
    migration_plan = build_api_vpn_split_migration_plan(
        api_urls,
        api_hosts,
        api_host_ips,
        vpn_host,
        vpn_ips,
        overlap,
        unresolved_hosts,
        production_ready,
    )
    return {
        "ok": True,
        "productionReady": production_ready,
        "mode": "api_site_and_vpn_endpoint_split",
        "publicApiUrls": api_urls,
        "publicApiHosts": api_hosts,
        "publicApiHostIps": api_host_ips,
        "vpnEndpointHost": vpn_host,
        "vpnEndpointIps": vpn_ips,
        "overlapIps": overlap,
        "checks": checks,
        "migrationPlan": migration_plan,
        "requiredActions": [check["message"] for check in checks if not check["ok"]],
    }


def yookassa_effective_webhook_url() -> str:
    if YOOKASSA_WEBHOOK_URL:
        return YOOKASSA_WEBHOOK_URL
    if PUBLIC_BASE_URL:
        return f"{PUBLIC_BASE_URL}/api/v1/billing/yookassa/webhook"
    return ""


def yookassa_payment_readiness() -> dict:
    webhook_url = yookassa_effective_webhook_url()
    return_host = _url_host(YOOKASSA_RETURN_URL)
    webhook_host = _url_host(webhook_url)
    public_host = _url_host(PUBLIC_BASE_URL)

    checks = [
        {
            "code": "yookassa_keys",
            "ok": yookassa_configured(),
            "message": (
                "YOOKASSA_SHOP_ID and YOOKASSA_SECRET_KEY are configured."
                if yookassa_configured()
                else "Set YOOKASSA_SHOP_ID and YOOKASSA_SECRET_KEY."
            ),
        },
        {
            "code": "return_url_https",
            "ok": _is_https_url(YOOKASSA_RETURN_URL)
            and return_host not in {"bluevpn.local", "localhost", "127.0.0.1"},
            "message": "YOOKASSA_RETURN_URL must be a real HTTPS URL.",
            "value": YOOKASSA_RETURN_URL,
        },
        {
            "code": "webhook_url_https",
            "ok": _is_https_url(webhook_url)
            and webhook_host not in {"bluevpn.local", "localhost", "127.0.0.1"},
            "message": "YOOKASSA_WEBHOOK_URL or GREENVPN_PUBLIC_BASE_URL must point to real HTTPS.",
            "value": webhook_url,
        },
        {
            "code": "public_base_url_https",
            "ok": _is_https_url(PUBLIC_BASE_URL)
            and public_host not in {"bluevpn.local", "localhost", "127.0.0.1"},
            "message": "Set GREENVPN_PUBLIC_BASE_URL to the production HTTPS API origin.",
            "value": PUBLIC_BASE_URL,
        },
        {
            "code": "yookassa_api_https",
            "ok": _is_https_url(YOOKASSA_API_BASE),
            "message": "YOOKASSA_API_BASE must use HTTPS.",
            "value": YOOKASSA_API_BASE,
        },
    ]
    production_ready = all(check["ok"] for check in checks)
    return {
        "ok": True,
        "provider": "yookassa" if yookassa_configured() else "manual_mvp",
        "productionReady": production_ready,
        "webhookUrl": webhook_url,
        "returnUrl": YOOKASSA_RETURN_URL,
        "checks": checks,
        "requiredActions": [
            check["message"] for check in checks if not check["ok"]
        ],
    }


def _public_site_url_path(url: str) -> str:
    try:
        return urllib.parse.urlparse(url).path.rstrip("/") or "/"
    except Exception:
        return ""


def _public_site_html_from_result(value: Any) -> str:
    if isinstance(value, HTMLResponse):
        return value.body.decode("utf-8", errors="replace")
    return str(value or "")


def _public_site_rendered_pages() -> tuple[dict[str, str], list[dict]]:
    pages: dict[str, str] = {}
    errors: list[dict] = []
    generators = [
        ("/", public_landing_page),
        ("/payment/return", payment_return_page),
        ("/legal/requisites", legal_requisites_page),
        ("/legal/offer", legal_offer_page),
        ("/legal/privacy", legal_privacy_page),
        ("/legal/acceptable-use", legal_acceptable_use_page),
        ("/legal/refunds", legal_refunds_page),
    ]
    for path, generator in generators:
        try:
            pages[path] = _public_site_html_from_result(generator())
        except Exception as exc:
            errors.append(
                {
                    "path": path,
                    "error": clean_limited_text(str(exc), 240),
                }
            )
    return pages, errors


def public_site_readiness() -> dict:
    route_paths = {str(getattr(route, "path", "")) for route in app.routes}
    missing_routes = [
        item for item in PUBLIC_SITE_REQUIRED_PATHS if item["path"] not in route_paths
    ]
    rendered_pages, render_errors = _public_site_rendered_pages()
    landing_html = rendered_pages.get("/", "")

    missing_landing_links = [
        item
        for item in PUBLIC_SITE_REQUIRED_LANDING_LINKS
        if item["needle"] not in landing_html
    ]
    missing_pricing_markers = [
        item
        for item in PUBLIC_SITE_REQUIRED_PRICING_MARKERS
        if item["needle"] not in landing_html
    ]

    banned_matches = []
    for path, page_html in rendered_pages.items():
        searchable = re.sub(r"<[^>]+>", " ", page_html).lower()
        for phrase in PUBLIC_SITE_BANNED_PHRASES:
            if phrase in searchable:
                banned_matches.append({"path": path, "phrase": phrase})

    webhook_url = yookassa_effective_webhook_url()
    return_host = _url_host(YOOKASSA_RETURN_URL)
    webhook_host = _url_host(webhook_url)
    public_base_host = _url_host(PUBLIC_BASE_URL)
    local_hosts = {"", "bluevpn.local", "localhost", "127.0.0.1"}
    expected_return_path = "/payment/return"
    expected_webhook_path = "/api/v1/billing/yookassa/webhook"

    legal_configured = (
        bool(LEGAL_OWNER_NAME)
        and LEGAL_OWNER_NAME != "Владелец Green VPN"
        and bool(LEGAL_OWNER_INN)
        and bool(LEGAL_CONTACT_EMAIL)
        and "@" in LEGAL_CONTACT_EMAIL
    )

    checks = [
        {
            "code": "public_routes_registered",
            "title": "Public routes",
            "ok": not missing_routes and not render_errors,
            "message": "Public site, download, legal and payment return routes must exist and render.",
            "missingPaths": [item["path"] for item in missing_routes],
            "renderErrors": render_errors,
        },
        {
            "code": "public_site_https",
            "title": "Public site HTTPS",
            "ok": _is_https_url(PUBLIC_SITE_URL)
            and _url_host(PUBLIC_SITE_URL) not in local_hosts,
            "message": "GREENVPN_PUBLIC_SITE_URL must point to a real HTTPS public origin.",
            "value": PUBLIC_SITE_URL,
        },
        {
            "code": "legal_requisites_configured",
            "title": "Legal requisites",
            "ok": legal_configured,
            "message": "Owner name, INN and support email must be configured server-side for requisites.",
            "value": {
                "ownerNameConfigured": bool(LEGAL_OWNER_NAME)
                and LEGAL_OWNER_NAME != "Владелец Green VPN",
                "ownerInnConfigured": bool(LEGAL_OWNER_INN),
                "contactEmailConfigured": bool(LEGAL_CONTACT_EMAIL)
                and "@" in LEGAL_CONTACT_EMAIL,
            },
        },
        {
            "code": "download_buttons",
            "title": "Download buttons",
            "ok": not missing_landing_links,
            "message": "Landing must expose Windows, Android, iOS download cards and pricing navigation.",
            "missing": [
                {"code": item["code"], "label": item["label"]}
                for item in missing_landing_links
            ],
        },
        {
            "code": "pricing_visible",
            "title": "Pricing",
            "ok": not missing_pricing_markers,
            "message": "Landing must show current public pricing and trial plan.",
            "missing": [
                {"code": item["code"], "label": item["label"]}
                for item in missing_pricing_markers
            ],
        },
        {
            "code": "safe_public_wording",
            "title": "Safe public wording",
            "ok": not banned_matches,
            "message": "Public pages must not use banned VPN marketing phrases.",
            "bannedMatches": banned_matches,
        },
        {
            "code": "yookassa_required_urls",
            "title": "YooKassa URLs",
            "ok": (
                _is_https_url(YOOKASSA_RETURN_URL)
                and _is_https_url(webhook_url)
                and return_host not in local_hosts
                and webhook_host not in local_hosts
                and _public_site_url_path(YOOKASSA_RETURN_URL) == expected_return_path
                and _public_site_url_path(webhook_url) == expected_webhook_path
                and (
                    not public_base_host
                    or return_host == public_base_host
                    or return_host == _url_host(PUBLIC_SITE_URL)
                )
            ),
            "message": "YooKassa return and webhook URLs must be public HTTPS Green VPN URLs.",
            "value": {
                "returnUrl": YOOKASSA_RETURN_URL,
                "webhookUrl": webhook_url,
                "expectedReturnPath": expected_return_path,
                "expectedWebhookPath": expected_webhook_path,
            },
        },
    ]

    failed = [check for check in checks if not check["ok"]]
    return {
        "ok": True,
        "version": APP_VERSION,
        "generatedAt": utc_now_iso(),
        "productionReady": not failed,
        "publicSiteReady": not failed,
        "summary": {
            "green": len(checks) - len(failed),
            "yellow": len(failed),
            "red": 0,
            "message": (
                "Public site readiness is green."
                if not failed
                else "Public site still has launch/review blockers."
            ),
        },
        "siteUrl": PUBLIC_SITE_URL,
        "requiredPaths": PUBLIC_SITE_REQUIRED_PATHS,
        "downloadTargets": {
            "windowsConfigured": bool(_public_download_target(PUBLIC_WINDOWS_DOWNLOAD_URL)),
            "androidConfigured": bool(_public_download_target(PUBLIC_ANDROID_DOWNLOAD_URL)),
            "iosConfigured": bool(_public_download_target(PUBLIC_IOS_DOWNLOAD_URL)),
        },
        "yookassaUrls": {
            "returnUrl": YOOKASSA_RETURN_URL,
            "webhookUrl": webhook_url,
        },
        "bannedPhraseMatches": banned_matches,
        "checks": checks,
        "requiredActions": [check["message"] for check in failed],
    }


def yookassa_http_request(
    method: str,
    path: str,
    payload: Optional[dict] = None,
    idempotence_key: Optional[str] = None,
) -> dict:
    auth_raw = f"{YOOKASSA_SHOP_ID}:{YOOKASSA_SECRET_KEY}".encode("utf-8")
    auth = base64.b64encode(auth_raw).decode("ascii")
    data = None if payload is None else json.dumps(payload, ensure_ascii=False).encode("utf-8")
    headers = {"Authorization": f"Basic {auth}"}
    if payload is not None:
        headers["Content-Type"] = "application/json"
    if idempotence_key:
        headers["Idempotence-Key"] = idempotence_key
    req = urllib.request.Request(
        f"{YOOKASSA_API_BASE}{path}",
        data=data,
        method=method,
        headers=headers,
    )
    try:
        with urllib.request.urlopen(req, timeout=20) as res:
            body = res.read().decode("utf-8")
            return json.loads(body) if body else {}
    except urllib.error.HTTPError as exc:
        body = exc.read().decode("utf-8", errors="replace")
        raise HTTPException(
            status_code=502,
            detail=f"YooKassa error ({exc.code}): {body}",
        )
    except Exception as exc:
        raise HTTPException(status_code=502, detail=f"YooKassa request failed: {exc}")


def yookassa_request(path: str, payload: dict, idempotence_key: str) -> dict:
    return yookassa_http_request(
        "POST",
        path,
        payload=payload,
        idempotence_key=idempotence_key,
    )


def yookassa_get_payment(payment_id: str) -> dict:
    payment_id = payment_id.strip()
    if not payment_id:
        raise HTTPException(status_code=400, detail="YooKassa payment id is empty.")
    return yookassa_http_request("GET", f"/payments/{payment_id}")


def yookassa_order_id_from_payment(payment: dict) -> str:
    metadata = payment.get("metadata") if isinstance(payment.get("metadata"), dict) else {}
    return str(
        metadata.get("bluevpn_order_id") or metadata.get("orderId") or ""
    ).strip()


def authoritative_yookassa_payment_for_webhook(payment: dict) -> dict:
    if not yookassa_configured():
        return payment

    payment_id = str(payment.get("id") or "").strip()
    if not payment_id:
        raise HTTPException(status_code=400, detail="YooKassa payment id is missing.")

    # Webhook payloads are treated as a signal only. In production mode the
    # payment state used for tariff activation must come from YooKassa API.
    return yookassa_get_payment(payment_id)


def create_yookassa_payment_for_order(row, user_email: str) -> dict:
    order = billing_order_status(row)
    quote = order["quote"] if isinstance(order["quote"], dict) else {}
    plan_name = str(quote.get("planName") or "BlueVPN")
    public_id = order["orderId"]
    amount = f"{int(order['amountRub'])}.00"

    payload = {
        "amount": {"value": amount, "currency": order["currency"]},
        "capture": True,
        "confirmation": {
            "type": "redirect",
            "return_url": YOOKASSA_RETURN_URL,
        },
        "description": f"Green VPN {plan_name} ({public_id})",
        "metadata": {
            "bluevpn_order_id": public_id,
            "orderId": public_id,
            "userId": str(order["userId"]),
            "email": user_email,
        },
        "save_payment_method": bool(order["autoRenew"]),
    }

    payment = yookassa_request(
        "/payments",
        payload,
        idempotence_key=f"bluevpn-{public_id}",
    )
    payment_id = str(payment.get("id") or "")
    confirmation = payment.get("confirmation") if isinstance(payment.get("confirmation"), dict) else {}
    payment_url = str(confirmation.get("confirmation_url") or "")
    payment_method = payment.get("payment_method") if isinstance(payment.get("payment_method"), dict) else {}
    payment_method_id = str(payment_method.get("id") or "") or None

    with db() as conn:
        conn.execute(
            """
            UPDATE billing_orders
            SET provider = ?, provider_payment_id = ?, provider_payment_method_id = ?,
                payment_url = ?, updated_at = ?
            WHERE public_id = ?
            """,
            (
                "yookassa",
                payment_id,
                payment_method_id,
                payment_url,
                utc_now_iso(),
                public_id,
            ),
        )
        conn.commit()
        updated = conn.execute(
            "SELECT * FROM billing_orders WHERE public_id = ?",
            (public_id,),
        ).fetchone()

    return billing_order_status(updated)


def create_billing_order_for_user(user_id: int, payload: TariffSelectionIn) -> dict:
    normalized = normalize_tariff_selection(payload)
    quote = quote_tariff(
        normalized,
        strict_promo=bool(normalized.get("promoCode")),
    )
    now = utc_now_iso()
    public_id = "ord_" + secrets.token_urlsafe(18).replace("-", "").replace("_", "")[:24]
    selection_json = json.dumps(normalized, ensure_ascii=False)
    quote_json = json.dumps(quote, ensure_ascii=False)

    with db() as conn:
        user = conn.execute("SELECT email FROM users WHERE id = ?", (user_id,)).fetchone()
        user_email = user["email"] if user else ""
        conn.execute(
            """
            INSERT INTO billing_orders(
                public_id, user_id, status, auto_renew, amount_rub, currency,
                selection_json, quote_json, promo_code, discount_rub,
                original_amount_rub, payment_url, provider,
                created_at, updated_at
            )
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            (
                public_id,
                user_id,
                "pending",
                1 if normalized.get("autoRenew", True) else 0,
                int(quote["monthlyPriceRub"]),
                "RUB",
                selection_json,
                quote_json,
                normalized.get("promoCode") or None,
                int(quote.get("discountRub") or 0),
                int(quote.get("originalMonthlyPriceRub") or quote["monthlyPriceRub"]),
                None,
                "yookassa" if yookassa_configured() else "manual_mvp",
                now,
                now,
            ),
        )
        conn.commit()
        row = conn.execute(
            "SELECT * FROM billing_orders WHERE public_id = ?",
            (public_id,),
        ).fetchone()

    if yookassa_configured():
        return create_yookassa_payment_for_order(row, user_email=user_email)

    return billing_order_status(row)


def get_billing_order_row(public_id: str, user_id: Optional[int] = None):
    query = "SELECT * FROM billing_orders WHERE public_id = ?"
    args: tuple = (public_id,)
    if user_id is not None:
        query += " AND user_id = ?"
        args = (public_id, user_id)
    with db() as conn:
        return conn.execute(query, args).fetchone()


def _payment_amount_rub(payment: dict) -> Optional[int]:
    amount = payment.get("amount") if isinstance(payment.get("amount"), dict) else {}
    value = str(amount.get("value") or "").strip()
    if not value:
        return None
    try:
        return int(Decimal(value))
    except (InvalidOperation, ValueError):
        return None


def validate_yookassa_payment_for_order(row, payment: dict) -> None:
    public_id = row["public_id"]
    payment_id = str(payment.get("id") or "").strip()
    saved_payment_id = str(row["provider_payment_id"] or "").strip()
    if saved_payment_id and payment_id and payment_id != saved_payment_id:
        raise HTTPException(status_code=409, detail="YooKassa payment id mismatch.")

    metadata = payment.get("metadata") if isinstance(payment.get("metadata"), dict) else {}
    metadata_order_id = str(
        metadata.get("bluevpn_order_id") or metadata.get("orderId") or ""
    ).strip()
    if metadata_order_id and metadata_order_id != public_id:
        raise HTTPException(status_code=409, detail="YooKassa order metadata mismatch.")

    amount = payment.get("amount") if isinstance(payment.get("amount"), dict) else {}
    currency = str(amount.get("currency") or "").upper()
    actual_amount_rub = _payment_amount_rub(payment)
    if currency and currency != str(row["currency"]).upper():
        raise HTTPException(status_code=409, detail="YooKassa payment currency mismatch.")
    if actual_amount_rub is not None and actual_amount_rub != int(row["amount_rub"]):
        raise HTTPException(status_code=409, detail="YooKassa payment amount mismatch.")


def mark_billing_order_canceled(public_id: str, provider_payment_id: Optional[str] = None) -> dict:
    with db() as conn:
        conn.execute(
            """
            UPDATE billing_orders
            SET status = ?, provider_payment_id = COALESCE(?, provider_payment_id),
                updated_at = ?
            WHERE public_id = ? AND status = 'pending'
            """,
            ("canceled", provider_payment_id or None, utc_now_iso(), public_id),
        )
        conn.commit()
        row = conn.execute(
            "SELECT * FROM billing_orders WHERE public_id = ?",
            (public_id,),
        ).fetchone()
    if row is None:
        raise HTTPException(status_code=404, detail="Billing order not found.")
    return {"order": billing_order_status(row)}


def apply_yookassa_payment_update(
    public_id: str,
    payment: dict,
    user_id: Optional[int] = None,
) -> dict:
    row = get_billing_order_row(public_id, user_id=user_id)
    if row is None:
        raise HTTPException(status_code=404, detail="Billing order not found.")

    validate_yookassa_payment_for_order(row, payment)

    payment_id = str(payment.get("id") or "").strip() or None
    payment_method = payment.get("payment_method") if isinstance(payment.get("payment_method"), dict) else {}
    payment_method_id = str(payment_method.get("id") or "").strip() or None
    status = str(payment.get("status") or "").strip().lower()
    paid = payment.get("paid") is True

    if paid or status == "succeeded":
        amount = payment.get("amount") if isinstance(payment.get("amount"), dict) else {}
        if not amount or _payment_amount_rub(payment) is None:
            raise HTTPException(status_code=409, detail="YooKassa payment amount is missing.")
        return mark_billing_order_paid_and_activate(
            public_id,
            provider_payment_id=payment_id,
            provider_payment_method_id=payment_method_id,
        )

    if status == "canceled":
        return mark_billing_order_canceled(public_id, provider_payment_id=payment_id)

    with db() as conn:
        conn.execute(
            """
            UPDATE billing_orders
            SET provider_payment_id = COALESCE(?, provider_payment_id),
                provider_payment_method_id = COALESCE(?, provider_payment_method_id),
                updated_at = ?
            WHERE public_id = ?
            """,
            (payment_id, payment_method_id, utc_now_iso(), public_id),
        )
        conn.commit()
        updated = conn.execute(
            "SELECT * FROM billing_orders WHERE public_id = ?",
            (public_id,),
        ).fetchone()
    return {"order": billing_order_status(updated)}


def sync_billing_order_with_provider_for_user(user_id: int, public_id: str) -> dict:
    row = get_billing_order_row(public_id, user_id=user_id)
    if row is None:
        raise HTTPException(status_code=404, detail="Billing order not found.")

    provider = str(row["provider"] or "")
    payment_id = str(row["provider_payment_id"] or "")
    if (
        row["status"] == "pending"
        and provider == "yookassa"
        and payment_id
        and yookassa_configured()
    ):
        payment = yookassa_get_payment(payment_id)
        result = apply_yookassa_payment_update(public_id, payment, user_id=user_id)
        order = result.get("order") if isinstance(result, dict) else None
        if isinstance(order, dict):
            return public_billing_order_status(order)

    return public_billing_order_status(billing_order_status(row))


def get_billing_order_for_user(user_id: int, public_id: str) -> dict:
    return sync_billing_order_with_provider_for_user(user_id, public_id)


def list_billing_orders(status: Optional[str] = None) -> list[dict]:
    query = """
        SELECT *
        FROM billing_orders
    """
    args: tuple = ()
    if status and status != "all":
        query += " WHERE status = ?"
        args = (status,)
    query += " ORDER BY id DESC LIMIT 200"

    with db() as conn:
        rows = conn.execute(query, args).fetchall()
    return [
        public_billing_order_status(billing_order_status(row))
        for row in rows
    ]


def billing_order_age_hours(row, now: datetime) -> Optional[float]:
    created_at = parse_dt(row["created_at"] if "created_at" in row.keys() else None)
    if created_at is None:
        return None
    if created_at.tzinfo is None:
        created_at = created_at.replace(tzinfo=timezone.utc)
    return max(0.0, (now - created_at).total_seconds() / 3600.0)


def billing_order_requires_attention(row, now: datetime) -> list[dict]:
    status = str(row["status"] or "").strip().lower()
    provider = str(row["provider"] or "").strip().lower()
    paid_at = row["paid_at"] if "paid_at" in row.keys() else None
    activated_at = row["activated_at"] if "activated_at" in row.keys() else None
    payment_url = row["payment_url"] if "payment_url" in row.keys() else None
    provider_payment_id = row["provider_payment_id"] if "provider_payment_id" in row.keys() else None
    age_hours = billing_order_age_hours(row, now)
    issues: list[dict] = []

    def add_issue(code: str, severity: str, message: str) -> None:
        issues.append({"code": code, "severity": severity, "message": message})

    if status == "paid" and not activated_at:
        add_issue(
            "paid_not_activated",
            "high",
            "Order is marked paid but tariff activation is not recorded.",
        )
    if paid_at and status != "activated" and not activated_at:
        add_issue(
            "paid_at_without_activation",
            "high",
            "paid_at exists but activated_at is still empty.",
        )
    if status == "activated" and not activated_at:
        add_issue(
            "activated_status_without_timestamp",
            "medium",
            "Order status is activated but activated_at is empty.",
        )
    if activated_at and status != "activated":
        add_issue(
            "activation_timestamp_status_mismatch",
            "medium",
            "activated_at exists but order status is not activated.",
        )
    if status == "pending" and age_hours is not None and age_hours >= 24:
        add_issue(
            "stale_pending_order",
            "medium",
            "Pending order is older than 24 hours.",
        )
    if (
        status == "pending"
        and provider == "yookassa"
        and yookassa_configured()
        and not provider_payment_id
        and not payment_url
    ):
        add_issue(
            "yookassa_payment_not_created",
            "high",
            "YooKassa is configured, but this pending order has no provider payment id or payment URL.",
        )
    if status in {"failed", "canceled", "cancelled"} and (paid_at or activated_at):
        add_issue(
            "terminal_order_has_payment_markers",
            "high",
            "Failed/canceled order has paid or activated markers and needs manual review.",
        )
    return issues


def billing_reconciliation_payload(limit: int = 25) -> dict:
    now = utc_now()
    safe_limit = max(1, min(int(limit or 25), 100))
    with db() as conn:
        rows = conn.execute(
            """
            SELECT *
            FROM billing_orders
            ORDER BY id DESC
            LIMIT 500
            """
        ).fetchall()
        by_status = db_group_counts(conn, "billing_orders", "status")
        total = db_count(conn, "billing_orders")

    attention_orders = []
    issue_counts: dict[str, int] = {}
    severity_counts = {"high": 0, "medium": 0, "low": 0}
    for row in rows:
        issues = billing_order_requires_attention(row, now)
        if not issues:
            continue
        for issue in issues:
            issue_counts[issue["code"]] = issue_counts.get(issue["code"], 0) + 1
            severity = issue.get("severity") or "medium"
            severity_counts[severity] = severity_counts.get(severity, 0) + 1
        if len(attention_orders) < safe_limit:
            order = public_billing_order_status(billing_order_status(row))
            order["issues"] = issues
            order["ageHours"] = billing_order_age_hours(row, now)
            attention_orders.append(order)

    return {
        "ok": True,
        "generatedAt": utc_now_iso(),
        "provider": "yookassa" if yookassa_configured() else "manual_mvp",
        "productionPaymentReady": yookassa_payment_readiness()["productionReady"],
        "requiresAttention": len(attention_orders) > 0,
        "summary": {
            "total": int(total),
            "byStatus": by_status,
            "attention": sum(issue_counts.values()),
            "ordersWithAttention": len(
                [
                    row
                    for row in rows
                    if billing_order_requires_attention(row, now)
                ]
            ),
            "high": int(severity_counts.get("high") or 0),
            "medium": int(severity_counts.get("medium") or 0),
            "low": int(severity_counts.get("low") or 0),
            "message": (
                "Billing reconciliation has no current attention items."
                if not issue_counts
                else "Billing reconciliation has orders that need review."
            ),
        },
        "issueCounts": issue_counts,
        "attentionOrders": attention_orders,
        "manualActivationPolicy": (
            "Manual mark-paid remains admin-only and audited. Failed or canceled orders "
            "cannot be manually activated without creating a fresh order."
        ),
    }


def billing_payment_smoke_order_snapshot(row: sqlite3.Row) -> dict:
    order = public_billing_order_status(billing_order_status(row))
    order["paymentUrlReady"] = bool(row["payment_url"])
    order["providerPaymentIdSaved"] = bool(row["provider_payment_id"])
    order["providerPaymentMethodSaved"] = bool(
        row["provider_payment_method_id"]
        if "provider_payment_method_id" in row.keys()
        else None
    )
    order["paidAt"] = row["paid_at"] if "paid_at" in row.keys() else None
    order["activatedAt"] = row["activated_at"] if "activated_at" in row.keys() else None
    return order


def billing_payment_smoke_readiness_payload(limit: int = 10) -> dict:
    safe_limit = max(1, min(int(limit or 10), 50))
    payment = yookassa_payment_readiness()
    site = public_site_readiness()
    webhook_url = yookassa_effective_webhook_url()
    with db() as conn:
        rows = conn.execute(
            """
            SELECT *
            FROM billing_orders
            WHERE provider = 'yookassa'
            ORDER BY id DESC
            LIMIT ?
            """,
            (safe_limit,),
        ).fetchall()
        yookassa_orders_total = db_count(conn, "billing_orders", "provider = 'yookassa'")
        yookassa_activated_total = db_count(
            conn,
            "billing_orders",
            "provider = 'yookassa' AND status = 'activated'",
        )

    recent_orders = [billing_payment_smoke_order_snapshot(row) for row in rows]
    successful_orders = [
        order
        for order in recent_orders
        if order.get("status") == "activated"
        and order.get("providerPaymentIdSaved")
        and order.get("paymentUrlReady")
    ]
    pending_orders_with_url = [
        order
        for order in recent_orders
        if order.get("status") == "pending" and order.get("paymentUrlReady")
    ]
    canceled_orders = [
        order
        for order in recent_orders
        if str(order.get("status") or "").lower() in {"canceled", "cancelled", "failed"}
    ]

    checks = [
        {
            "code": "payment_production_ready",
            "title": "YooKassa production readiness",
            "ok": bool(payment.get("productionReady")),
            "message": (
                "YooKassa keys and production URLs are configured."
                if payment.get("productionReady")
                else "Apply YOOKASSA_SHOP_ID and YOOKASSA_SECRET_KEY through the safe server env script first."
            ),
        },
        {
            "code": "site_payment_urls_ready",
            "title": "Return/webhook public URLs",
            "ok": bool(site.get("productionReady")),
            "message": (
                "Public site and YooKassa URLs are green."
                if site.get("productionReady")
                else "Public site readiness must be green before payment smoke."
            ),
        },
        {
            "code": "manual_activation_guard",
            "title": "Manual activation guard",
            "ok": True,
            "message": (
                "Direct tariff activation is disabled; admin mark-paid is audited and must stay manual-only."
            ),
        },
        {
            "code": "hosted_payment_url_observed",
            "title": "Hosted payment URL observed",
            "ok": bool(pending_orders_with_url or successful_orders),
            "message": (
                "At least one YooKassa order has a hosted payment URL."
                if pending_orders_with_url or successful_orders
                else "Create a minimal owner-approved order after YooKassa keys are configured."
            ),
        },
        {
            "code": "confirmed_payment_activation_observed",
            "title": "Confirmed payment activation observed",
            "ok": bool(successful_orders),
            "message": (
                "At least one YooKassa order was activated after provider confirmation."
                if successful_orders
                else "Complete a smoke payment and confirm the tariff activates only after provider confirmation."
            ),
        },
    ]
    blocking_codes = [
        check["code"]
        for check in checks
        if not check["ok"] and check["code"] in {
            "payment_production_ready",
            "site_payment_urls_ready",
        }
    ]
    smoke_complete = bool(successful_orders)
    safe_to_run_smoke = bool(payment.get("productionReady")) and bool(site.get("productionReady"))
    smoke_steps = [
        {
            "code": "apply_yookassa_env",
            "title": "Apply YooKassa env",
            "actor": "owner_or_ops",
            "status": "done" if payment.get("productionReady") else "blocked",
            "details": (
                r"Run scripts\windows\configure_backend_env_wsl.ps1 and enter "
                "YOOKASSA_SHOP_ID plus YOOKASSA_SECRET_KEY only in the terminal."
            ),
            "secret": True,
        },
        {
            "code": "verify_urls",
            "title": "Verify return and webhook URLs",
            "actor": "ops",
            "status": "done" if site.get("productionReady") else "pending",
            "details": (
                f"Return: {YOOKASSA_RETURN_URL}; webhook: {webhook_url}; "
                "events: payment.succeeded and payment.canceled."
            ),
            "secret": False,
        },
        {
            "code": "create_minimal_order",
            "title": "Create a minimal owner-approved order",
            "actor": "owner_or_ops",
            "status": "pending" if safe_to_run_smoke else "blocked",
            "details": (
                "Use an owner test account and the lowest practical paid tariff. "
                "Do not use admin mark-paid for the provider smoke."
            ),
            "secret": False,
        },
        {
            "code": "open_hosted_payment_url",
            "title": "Open hosted YooKassa payment URL",
            "actor": "owner",
            "status": "done" if pending_orders_with_url or successful_orders else "pending",
            "details": (
                "The order should stay pending until YooKassa confirms payment; "
                "Green VPN must not activate the tariff from local return alone."
            ),
            "secret": False,
        },
        {
            "code": "confirm_activation",
            "title": "Confirm provider-backed activation",
            "actor": "ops",
            "status": "done" if smoke_complete else "pending",
            "details": (
                "Verify order status/subscription only changes after YooKassa confirmation "
                "via webhook or authoritative payment fetch."
            ),
            "secret": False,
        },
    ]

    return {
        "ok": True,
        "version": APP_VERSION,
        "generatedAt": utc_now_iso(),
        "provider": "yookassa" if yookassa_configured() else "manual_mvp",
        "productionPaymentReady": bool(payment.get("productionReady")),
        "publicSiteReady": bool(site.get("productionReady")),
        "safeToRunSmoke": safe_to_run_smoke,
        "smokeCompleted": smoke_complete,
        "productionReady": safe_to_run_smoke and smoke_complete,
        "requiresOwnerAction": not safe_to_run_smoke,
        "summary": {
            "state": (
                "green"
                if safe_to_run_smoke and smoke_complete
                else ("yellow" if safe_to_run_smoke else "blocked")
            ),
            "message": (
                "Payment smoke is complete."
                if smoke_complete
                else (
                    "YooKassa is configured; run an owner-approved minimal payment smoke."
                    if safe_to_run_smoke
                    else "Payment smoke is blocked until YooKassa production env is configured."
                )
            ),
            "yookassaOrdersTotal": int(yookassa_orders_total),
            "yookassaActivatedTotal": int(yookassa_activated_total),
            "recentYookassaOrders": len(recent_orders),
            "pendingWithPaymentUrl": len(pending_orders_with_url),
            "successfulSmokeCandidates": len(successful_orders),
            "canceledOrFailedRecent": len(canceled_orders),
        },
        "paymentReadiness": payment,
        "siteReadinessSummary": site.get("summary") or {},
        "checks": checks,
        "blockingCodes": blocking_codes,
        "requiredActions": [check["message"] for check in checks if not check["ok"]],
        "smokeSteps": smoke_steps,
        "recentYookassaOrders": recent_orders,
        "latestSuccessfulOrder": successful_orders[0] if successful_orders else None,
        "policy": {
            "noSecrets": "YooKassa secret key must only be entered into server-side env and is never returned by this endpoint.",
            "noSyntheticActivation": "Provider smoke must not use admin mark-paid or direct subscription apply.",
            "activationSource": "Tariff activation must follow YooKassa provider confirmation through webhook or authoritative API fetch.",
            "returnUrl": YOOKASSA_RETURN_URL,
            "webhookUrl": webhook_url,
            "webhookEvents": ["payment.succeeded", "payment.canceled"],
        },
    }


def renewal_days_until(expires_at_raw: Optional[str], now: datetime) -> Optional[float]:
    expires_at = parse_dt(expires_at_raw)
    if expires_at is None:
        return None
    if expires_at.tzinfo is None:
        expires_at = expires_at.replace(tzinfo=timezone.utc)
    return (expires_at - now).total_seconds() / 86400.0


def renewal_issue(code: str, severity: str, message: str) -> dict:
    return {
        "code": code,
        "severity": severity,
        "message": message,
    }


def renewal_pending_order_snapshot(row: Optional[sqlite3.Row]) -> Optional[dict]:
    if row is None:
        return None
    return {
        "orderId": row["public_id"],
        "createdAt": row["created_at"],
    }


def renewal_candidate_payload(
    row: sqlite3.Row,
    now: datetime,
    payment_readiness: dict,
    pending_order: Optional[sqlite3.Row],
) -> dict:
    selection = {}
    if row["selection_json"]:
        try:
            parsed = json.loads(row["selection_json"])
            if isinstance(parsed, dict):
                selection = parsed
        except Exception:
            selection = {}

    monthly_price = row["monthly_price_rub"]
    if monthly_price is None:
        try:
            monthly_price = int(selection.get("monthlyPriceRub") or 0)
        except Exception:
            monthly_price = 0
    amount_rub = int(monthly_price or 0)
    days_until = renewal_days_until(row["expires_at"], now)
    is_active_flag = bool(row["is_active"])
    has_payment_method = bool(row["provider_payment_method_id"])
    has_pending_order = pending_order is not None
    due_within_window = days_until is not None and days_until <= RENEWAL_LOOKAHEAD_DAYS
    due_soon = days_until is not None and 0 <= days_until <= RENEWAL_DUE_SOON_DAYS
    expired = days_until is not None and days_until < 0
    billable = amount_rub > 0 and str(row["plan_code"] or "").strip().lower() != "trial"

    issues = []
    if not is_active_flag:
        issues.append(
            renewal_issue(
                "subscription_inactive",
                "medium",
                "Auto-renew is enabled on an inactive subscription.",
            )
        )
    if days_until is None:
        issues.append(
            renewal_issue(
                "expiry_missing",
                "medium",
                "Auto-renew subscription has no expires_at value.",
            )
        )
    elif expired:
        issues.append(
            renewal_issue(
                "subscription_expired",
                "high",
                "Subscription is already expired; review before any automatic renewal.",
            )
        )
    if not billable:
        issues.append(
            renewal_issue(
                "non_billable_auto_renew",
                "low",
                "Auto-renew is enabled on a trial/free or zero-price subscription.",
            )
        )
    elif not has_payment_method:
        issues.append(
            renewal_issue(
                "provider_payment_method_missing",
                "high" if due_within_window else "medium",
                "Auto-renew is enabled but no saved provider payment method is available.",
            )
        )
    if has_pending_order:
        issues.append(
            renewal_issue(
                "pending_billing_order_exists",
                "medium",
                "User already has a pending auto-renew billing order; avoid duplicate renewal attempts.",
            )
        )
    if not payment_readiness.get("productionReady"):
        issues.append(
            renewal_issue(
                "payments_not_production_ready",
                "high" if due_within_window else "medium",
                "YooKassa production payment readiness is not green yet.",
            )
        )

    blocking_issue_codes = [
        issue["code"]
        for issue in issues
        if issue.get("severity") in {"high", "medium"}
    ]
    charge_eligible_dry_run = (
        is_active_flag
        and due_within_window
        and not expired
        and billable
        and has_payment_method
        and not has_pending_order
        and bool(payment_readiness.get("productionReady"))
    )

    return {
        "subscriptionId": row["id"],
        "userId": row["user_id"],
        "email": row["user_email"],
        "planCode": row["plan_code"],
        "planName": row["plan_name"],
        "monthlyPriceRub": amount_rub,
        "expiresAt": row["expires_at"],
        "daysUntilExpiry": None if days_until is None else round(days_until, 2),
        "dueWithinWindow": due_within_window,
        "dueSoon": due_soon,
        "expired": expired,
        "hasProviderPaymentMethod": has_payment_method,
        "hasPendingAutoRenewOrder": has_pending_order,
        "pendingAutoRenewOrder": renewal_pending_order_snapshot(pending_order),
        "chargeEligibleDryRun": charge_eligible_dry_run,
        "requiresManualReview": bool(blocking_issue_codes),
        "blockingIssueCodes": blocking_issue_codes,
        "issues": issues,
    }


def billing_renewal_readiness_payload(limit: int = 25) -> dict:
    now = utc_now()
    safe_limit = max(1, min(int(limit or 25), 100))
    payment_readiness = yookassa_payment_readiness()
    payment_smoke = billing_payment_smoke_readiness_payload(limit=5)
    payment_smoke_ready = bool(payment_smoke.get("productionReady"))
    payment_smoke_summary = payment_smoke.get("summary") or {}

    with db() as conn:
        rows = conn.execute(
            """
            SELECT s.*, u.email AS user_email
            FROM subscriptions s
            JOIN (
                SELECT user_id, MAX(id) AS latest_subscription_id
                FROM subscriptions
                GROUP BY user_id
            ) latest ON latest.latest_subscription_id = s.id
            LEFT JOIN users u ON u.id = s.user_id
            WHERE s.auto_renew = 1
            ORDER BY
                CASE WHEN s.expires_at IS NULL THEN 1 ELSE 0 END,
                s.expires_at ASC,
                s.id DESC
            LIMIT 500
            """
        ).fetchall()
        pending_rows = conn.execute(
            """
            SELECT *
            FROM billing_orders
            WHERE auto_renew = 1 AND status = 'pending'
            ORDER BY id DESC
            """
        ).fetchall()

    pending_by_user: dict[int, sqlite3.Row] = {}
    for order in pending_rows:
        user_id = int(order["user_id"])
        if user_id not in pending_by_user:
            pending_by_user[user_id] = order

    all_candidates = [
        renewal_candidate_payload(
            row,
            now,
            payment_readiness,
            pending_by_user.get(int(row["user_id"])),
        )
        for row in rows
    ]

    issue_counts: dict[str, int] = {}
    severity_counts = {"high": 0, "medium": 0, "low": 0}
    for candidate in all_candidates:
        for issue in candidate["issues"]:
            code = issue["code"]
            severity = issue.get("severity") or "medium"
            issue_counts[code] = issue_counts.get(code, 0) + 1
            severity_counts[severity] = severity_counts.get(severity, 0) + 1

    due_or_attention = [
        candidate
        for candidate in all_candidates
        if candidate["dueWithinWindow"] or candidate["requiresManualReview"]
    ]
    due_within_window = [candidate for candidate in all_candidates if candidate["dueWithinWindow"]]
    due_blocked = [
        candidate
        for candidate in due_within_window
        if candidate["requiresManualReview"]
    ]
    charge_eligible = [
        candidate
        for candidate in all_candidates
        if candidate["chargeEligibleDryRun"]
    ]
    missing_method = [
        candidate
        for candidate in all_candidates
        if "provider_payment_method_missing" in candidate["blockingIssueCodes"]
    ]
    pending_conflicts = [
        candidate
        for candidate in all_candidates
        if candidate["hasPendingAutoRenewOrder"]
    ]
    expired = [candidate for candidate in all_candidates if candidate["expired"]]
    safe_to_enable_charges = (
        bool(payment_readiness.get("productionReady"))
        and payment_smoke_ready
        and not due_blocked
        and not pending_conflicts
    )
    requires_payment_smoke = not payment_smoke_ready

    return {
        "ok": True,
        "generatedAt": utc_now_iso(),
        "provider": "yookassa" if yookassa_configured() else "manual_mvp",
        "productionPaymentReady": bool(payment_readiness.get("productionReady")),
        "paymentSmokeCompleted": bool(payment_smoke.get("smokeCompleted")),
        "paymentSmokeReady": payment_smoke_ready,
        "safeToEnableAutoRenewalCharges": safe_to_enable_charges,
        "requiresAttention": bool(
            due_blocked or expired or pending_conflicts or requires_payment_smoke
        ),
        "summary": {
            "autoRenewSubscriptions": len(all_candidates),
            "dueWithinWindow": len(due_within_window),
            "dueSoon": len([c for c in all_candidates if c["dueSoon"]]),
            "expired": len(expired),
            "chargeEligibleDryRun": len(charge_eligible),
            "missingPaymentMethod": len(missing_method),
            "pendingOrderConflicts": len(pending_conflicts),
            "dueBlocked": len(due_blocked),
            "paymentSmokeCompleted": bool(payment_smoke.get("smokeCompleted")),
            "paymentSmokeReady": payment_smoke_ready,
            "paymentSmokeState": payment_smoke_summary.get("state"),
            "high": int(severity_counts.get("high") or 0),
            "medium": int(severity_counts.get("medium") or 0),
            "low": int(severity_counts.get("low") or 0),
            "message": (
                "Auto-renewal readiness is clean for the current due window."
                if safe_to_enable_charges
                else (
                    "Auto-renewal charges must stay disabled until payment smoke is clean."
                    if requires_payment_smoke
                    else "Auto-renewal charges must stay disabled until blockers are cleared."
                )
            ),
        },
        "issueCounts": issue_counts,
        "candidates": due_or_attention[:safe_limit],
        "policy": {
            "mode": "dry_run_readiness_only",
            "renewalLookaheadDays": RENEWAL_LOOKAHEAD_DAYS,
            "renewalDueSoonDays": RENEWAL_DUE_SOON_DAYS,
            "automaticChargeExecution": "disabled_in_this_backend_version",
            "requiresPaymentSmoke": True,
            "safePaymentMethodExposure": "Only boolean hasProviderPaymentMethod is returned; provider payment method ids are not exposed.",
        },
    }


def normalize_subscription_expiry_review_status(value: Optional[str]) -> str:
    status = clean_limited_text(value, 40).strip().lower() or "reviewed"
    if status not in SUBSCRIPTION_EXPIRY_REVIEW_STATUSES:
        raise HTTPException(status_code=400, detail="Invalid subscription expiry review status.")
    return status


def subscription_expiry_review_payload(row: Optional[sqlite3.Row]) -> Optional[dict]:
    if row is None:
        return None
    return {
        "id": int(row["id"]),
        "subscriptionId": int(row["subscription_id"]),
        "userId": int(row["user_id"]),
        "status": normalize_subscription_expiry_review_status(row["status"]),
        "reason": row["reason"],
        "reviewedBy": row["reviewed_by"],
        "createdAt": row["created_at"],
    }


def latest_subscription_expiry_reviews(subscription_ids: list[int]) -> dict[int, sqlite3.Row]:
    ids = sorted({int(item) for item in subscription_ids if item is not None})
    if not ids:
        return {}
    placeholders = ",".join(["?"] * len(ids))
    with db() as conn:
        rows = conn.execute(
            f"""
            SELECT r.*
            FROM subscription_expiry_reviews r
            JOIN (
                SELECT subscription_id, MAX(id) AS latest_review_id
                FROM subscription_expiry_reviews
                WHERE subscription_id IN ({placeholders})
                GROUP BY subscription_id
            ) latest ON latest.latest_review_id = r.id
            """,
            tuple(ids),
        ).fetchall()
    return {int(row["subscription_id"]): row for row in rows}


def create_subscription_expiry_review(
    subscription_id: int,
    payload: AdminSubscriptionExpiryReviewIn,
    request: Optional[Request] = None,
) -> dict:
    status = normalize_subscription_expiry_review_status(payload.status)
    reason = clean_limited_text(payload.reason, 2000).strip()
    if len(reason) < 8:
        raise HTTPException(status_code=400, detail="reason is required for expiry review.")
    secret_findings = owner_action_note_secret_findings(reason)
    if secret_findings:
        raise HTTPException(
            status_code=400,
            detail=(
                "Expiry review reason appears to contain secret material "
                f"({', '.join(secret_findings[:5])}). Remove secret values and keep only the review note."
            ),
        )
    actor = admin_actor_from_context(request)
    request_ip = ""
    user_agent = ""
    if request is not None:
        request_ip, user_agent = request_ip_and_agent(request)
    now = utc_now_iso()
    with db() as conn:
        subscription = conn.execute(
            """
            SELECT s.*, u.email AS user_email
            FROM subscriptions s
            LEFT JOIN users u ON u.id = s.user_id
            WHERE s.id = ?
            """,
            (int(subscription_id),),
        ).fetchone()
        if subscription is None:
            raise HTTPException(status_code=404, detail="Subscription not found.")
        cursor = conn.execute(
            """
            INSERT INTO subscription_expiry_reviews(
                subscription_id, user_id, status, reason, reviewed_by,
                request_ip, user_agent, created_at
            )
            VALUES (?, ?, ?, ?, ?, ?, ?, ?)
            """,
            (
                int(subscription["id"]),
                int(subscription["user_id"]),
                status,
                reason,
                actor,
                request_ip or None,
                user_agent or None,
                now,
            ),
        )
        conn.commit()
        row = conn.execute(
            "SELECT * FROM subscription_expiry_reviews WHERE id = ?",
            (int(cursor.lastrowid),),
        ).fetchone()
    return subscription_expiry_review_payload(row)


def subscription_expiry_candidate_payload(
    row: sqlite3.Row,
    now: datetime,
    payment_readiness: dict,
    pending_order: Optional[sqlite3.Row],
    expiry_review: Optional[sqlite3.Row] = None,
) -> dict:
    selection = {}
    if row["selection_json"]:
        try:
            parsed = json.loads(row["selection_json"])
            if isinstance(parsed, dict):
                selection = parsed
        except Exception:
            selection = {}

    monthly_price = row["monthly_price_rub"]
    if monthly_price is None:
        try:
            monthly_price = int(selection.get("monthlyPriceRub") or 0)
        except Exception:
            monthly_price = 0
    amount_rub = int(monthly_price or 0)
    plan_code = str(row["plan_code"] or "").strip().lower()
    days_until = renewal_days_until(row["expires_at"], now)
    is_active_flag = bool(row["is_active"])
    expired = days_until is not None and days_until < 0
    expired_active = is_active_flag and expired
    expiring_within_window = (
        days_until is not None
        and 0 <= days_until <= SUBSCRIPTION_EXPIRY_LOOKAHEAD_DAYS
    )
    active_now = is_active_flag and (days_until is None or days_until > 0)
    billable = amount_rub > 0 and plan_code not in {"trial", DEFAULT_PLAN_CODE, "support_trial"}
    trial_like = plan_code in {"trial", DEFAULT_PLAN_CODE, "support_trial"} or amount_rub <= 0
    auto_renew = bool(row["auto_renew"])
    has_payment_method = bool(row["provider_payment_method_id"])
    has_pending_order = pending_order is not None
    contactable = bool(row["email_verified"]) or bool(row["phone_verified"])
    expiry_review_payload = subscription_expiry_review_payload(expiry_review)
    reviewed_for_expiry = bool(
        expiry_review_payload and expiry_review_payload.get("status") == "reviewed"
    )
    review_clears_missing_contact = reviewed_for_expiry and trial_like and not billable
    cleared_issue_codes = []

    issues = []
    if expired_active:
        issues.append(
            renewal_issue(
                "active_subscription_already_expired",
                "high",
                "Subscription has is_active=1 but expires_at is already in the past.",
            )
        )
    if expiring_within_window and trial_like:
        issues.append(
            renewal_issue(
                "trial_or_free_expiring",
                "low",
                "Trial/free subscription is expiring soon; support may need conversion follow-up.",
            )
        )
    if expiring_within_window and billable and not auto_renew:
        issues.append(
            renewal_issue(
                "paid_subscription_expiring_without_auto_renew",
                "medium",
                "Paid subscription is expiring soon and auto-renew is off.",
            )
        )
    if expiring_within_window and not contactable:
        issues.append(
            renewal_issue(
                "retention_contact_unverified",
                "medium",
                "No verified email or phone is available for expiry/retention contact.",
            )
        )
    if expiring_within_window and billable and auto_renew and not has_payment_method:
        issues.append(
            renewal_issue(
                "auto_renew_payment_method_missing",
                "high",
                "Auto-renew is on for an expiring paid subscription, but no saved payment method is available.",
            )
        )
    if expiring_within_window and billable and auto_renew and has_pending_order:
        issues.append(
            renewal_issue(
                "auto_renew_pending_order_conflict",
                "medium",
                "A pending auto-renew order already exists for this user.",
            )
        )
    if expiring_within_window and billable and auto_renew and not payment_readiness.get("productionReady"):
        issues.append(
            renewal_issue(
                "auto_renew_payments_not_production_ready",
                "high",
                "YooKassa production payment readiness is not green for auto-renewal.",
            )
        )

    if review_clears_missing_contact:
        before_count = len(issues)
        issues = [
            issue
            for issue in issues
            if issue.get("code") != "retention_contact_unverified"
        ]
        if len(issues) != before_count:
            cleared_issue_codes.append("retention_contact_unverified")

    blocking_issue_codes = [
        issue["code"]
        for issue in issues
        if issue.get("severity") in {"high", "medium"}
    ]

    return {
        "subscriptionId": row["id"],
        "userId": row["user_id"],
        "email": row["user_email"],
        "planCode": row["plan_code"],
        "planName": row["plan_name"],
        "monthlyPriceRub": amount_rub,
        "expiresAt": row["expires_at"],
        "daysUntilExpiry": None if days_until is None else round(days_until, 2),
        "activeNow": active_now,
        "isActiveFlag": is_active_flag,
        "expired": expired,
        "expiredActive": expired_active,
        "expiringWithinWindow": expiring_within_window,
        "trialLike": trial_like,
        "billable": billable,
        "autoRenew": auto_renew,
        "hasProviderPaymentMethod": has_payment_method,
        "hasPendingAutoRenewOrder": has_pending_order,
        "pendingAutoRenewOrder": renewal_pending_order_snapshot(pending_order),
        "contactable": contactable,
        "emailVerified": bool(row["email_verified"]),
        "phoneVerified": bool(row["phone_verified"]),
        "reviewedForExpiry": reviewed_for_expiry,
        "expiryReview": expiry_review_payload,
        "clearedIssueCodes": cleared_issue_codes,
        "requiresManualReview": bool(blocking_issue_codes),
        "blockingIssueCodes": blocking_issue_codes,
        "issues": issues,
    }


def subscription_expiry_readiness_payload(limit: int = 25) -> dict:
    now = utc_now()
    safe_limit = max(1, min(int(limit or 25), 100))
    payment_readiness = yookassa_payment_readiness()
    payment_smoke = billing_payment_smoke_readiness_payload(limit=5)
    payment_smoke_ready = bool(payment_smoke.get("productionReady"))
    payment_smoke_summary = payment_smoke.get("summary") or {}

    with db() as conn:
        rows = conn.execute(
            """
            SELECT
                s.*,
                u.email AS user_email,
                u.email_verified,
                u.phone_verified
            FROM subscriptions s
            JOIN (
                SELECT user_id, MAX(id) AS latest_subscription_id
                FROM subscriptions
                GROUP BY user_id
            ) latest ON latest.latest_subscription_id = s.id
            LEFT JOIN users u ON u.id = s.user_id
            ORDER BY
                CASE WHEN s.expires_at IS NULL THEN 1 ELSE 0 END,
                s.expires_at ASC,
                s.id DESC
            LIMIT 1000
            """
        ).fetchall()
        pending_rows = conn.execute(
            """
            SELECT *
            FROM billing_orders
            WHERE auto_renew = 1 AND status = 'pending'
            ORDER BY id DESC
            """
        ).fetchall()

    pending_by_user: dict[int, sqlite3.Row] = {}
    for order in pending_rows:
        user_id = int(order["user_id"])
        if user_id not in pending_by_user:
            pending_by_user[user_id] = order
    review_by_subscription = latest_subscription_expiry_reviews(
        [int(row["id"]) for row in rows]
    )

    candidates = [
        subscription_expiry_candidate_payload(
            row,
            now,
            payment_readiness,
            pending_by_user.get(int(row["user_id"])),
            review_by_subscription.get(int(row["id"])),
        )
        for row in rows
    ]

    issue_counts: dict[str, int] = {}
    severity_counts = {"high": 0, "medium": 0, "low": 0}
    for candidate in candidates:
        for issue in candidate["issues"]:
            code = issue["code"]
            severity = issue.get("severity") or "medium"
            issue_counts[code] = issue_counts.get(code, 0) + 1
            severity_counts[severity] = severity_counts.get(severity, 0) + 1

    attention = [
        candidate
        for candidate in candidates
        if candidate["expiredActive"]
        or candidate["expiringWithinWindow"]
        or candidate["requiresManualReview"]
    ]
    expired_total = [candidate for candidate in candidates if candidate["expired"]]
    expired_active = [candidate for candidate in candidates if candidate["expiredActive"]]
    expiring = [candidate for candidate in candidates if candidate["expiringWithinWindow"]]
    paid_expiring_manual = [
        candidate
        for candidate in expiring
        if candidate["billable"] and not candidate["autoRenew"]
    ]
    trial_expiring = [candidate for candidate in expiring if candidate["trialLike"]]
    auto_renew_expiring = [
        candidate
        for candidate in expiring
        if candidate["billable"] and candidate["autoRenew"]
    ]
    missing_contact = [
        candidate
        for candidate in expiring
        if not candidate["contactable"] and not candidate["reviewedForExpiry"]
    ]
    reviewed_missing_contact = [
        candidate
        for candidate in expiring
        if not candidate["contactable"] and candidate["reviewedForExpiry"]
    ]
    blocked_expiring = [
        candidate
        for candidate in expiring
        if candidate["requiresManualReview"]
    ]
    safe_to_enable_expiry_enforcement = (
        not expired_active
        and not blocked_expiring
        and bool(payment_readiness.get("productionReady"))
        and payment_smoke_ready
    )
    requires_payment_smoke = not payment_smoke_ready

    return {
        "ok": True,
        "generatedAt": utc_now_iso(),
        "subscriptionEnforcementCurrentlyEnabled": ENFORCE_SUBSCRIPTION_ACCESS,
        "safeToEnableExpiryEnforcement": safe_to_enable_expiry_enforcement,
        "productionPaymentReady": bool(payment_readiness.get("productionReady")),
        "paymentSmokeCompleted": bool(payment_smoke.get("smokeCompleted")),
        "paymentSmokeReady": payment_smoke_ready,
        "requiresAttention": bool(
            expired_active or blocked_expiring or missing_contact or requires_payment_smoke
        ),
        "summary": {
            "latestSubscriptions": len(candidates),
            "activeNow": len([candidate for candidate in candidates if candidate["activeNow"]]),
            "expiringWithinWindow": len(expiring),
            "expired": len(expired_active),
            "expiredTotal": len(expired_total),
            "paidExpiringWithoutAutoRenew": len(paid_expiring_manual),
            "trialExpiring": len(trial_expiring),
            "autoRenewExpiring": len(auto_renew_expiring),
            "missingRetentionContact": len(missing_contact),
            "reviewedMissingRetentionContact": len(reviewed_missing_contact),
            "blockedExpiring": len(blocked_expiring),
            "paymentSmokeCompleted": bool(payment_smoke.get("smokeCompleted")),
            "paymentSmokeReady": payment_smoke_ready,
            "paymentSmokeState": payment_smoke_summary.get("state"),
            "high": int(severity_counts.get("high") or 0),
            "medium": int(severity_counts.get("medium") or 0),
            "low": int(severity_counts.get("low") or 0),
            "message": (
                "Subscription expiry readiness is clean for the current window."
                if safe_to_enable_expiry_enforcement
                else (
                    "Subscription expiry enforcement should stay off until payment smoke is clean."
                    if requires_payment_smoke
                    else "Subscription expiry enforcement should stay off until blockers are cleared."
                )
            ),
        },
        "issueCounts": issue_counts,
        "candidates": attention[:safe_limit],
        "policy": {
            "mode": "expiry_readiness_only",
            "expiryLookaheadDays": SUBSCRIPTION_EXPIRY_LOOKAHEAD_DAYS,
            "subscriptionEnforcementEnv": "BLUEVPN_ENFORCE_SUBSCRIPTION_ACCESS",
            "requiresPaymentSmoke": True,
            "safePaymentMethodExposure": "Only boolean hasProviderPaymentMethod is returned; provider payment method ids are not exposed.",
        },
    }


def list_billing_orders_for_user(
    user_id: int,
    status: Optional[str] = None,
) -> list[dict]:
    query = """
        SELECT *
        FROM billing_orders
        WHERE user_id = ?
    """
    args: tuple = (user_id,)
    if status and status != "all":
        query += " AND status = ?"
        args = (user_id, status)
    query += " ORDER BY id DESC LIMIT 50"

    with db() as conn:
        rows = conn.execute(query, args).fetchall()
    return [billing_order_status(row) for row in rows]


def cancel_auto_renew_for_user(user_id: int) -> dict:
    row = get_subscription_row(user_id)
    selection = {}
    if row and row["selection_json"]:
        try:
            parsed = json.loads(row["selection_json"])
            if isinstance(parsed, dict):
                selection = parsed
        except Exception:
            selection = {}

    if selection:
        selection["autoRenew"] = False
        selection_json = json.dumps(selection, ensure_ascii=False)
    else:
        selection_json = row["selection_json"] if row else None

    with db() as conn:
        conn.execute(
            """
            UPDATE subscriptions
            SET auto_renew = 0,
                provider_payment_method_id = NULL,
                selection_json = ?,
                updated_at = ?
            WHERE id = ?
            """,
            (selection_json, utc_now_iso(), row["id"]),
        )
        conn.commit()

    return subscription_status(get_subscription_row(user_id))


def mark_billing_order_paid_and_activate(
    public_id: str,
    provider_payment_id: Optional[str] = None,
    provider_payment_method_id: Optional[str] = None,
) -> dict:
    with db() as conn:
        row = conn.execute(
            "SELECT * FROM billing_orders WHERE public_id = ?",
            (public_id,),
        ).fetchone()

    if row is None:
        raise HTTPException(status_code=404, detail="Billing order not found.")

    if row["status"] == "activated":
        return {
            "order": billing_order_status(row),
            "subscription": subscription_status(get_subscription_row(row["user_id"])),
        }
    if str(row["status"] or "").strip().lower() in {"failed", "canceled", "cancelled"}:
        raise HTTPException(
            status_code=409,
            detail="Failed or canceled billing order cannot be activated manually.",
        )

    try:
        selection = json.loads(row["selection_json"])
    except Exception:
        raise HTTPException(status_code=500, detail="Billing order selection is broken.")
    try:
        order_quote = json.loads(row["quote_json"])
    except Exception:
        order_quote = {}

    payload = TariffSelectionIn(
        trafficPack=str(selection.get("trafficPack") or "gb20"),
        trafficGb=int(selection.get("trafficGb") or 20),
        unlimitedApps=list(selection.get("unlimitedApps") or []),
        devices=int(selection.get("devices") or 1),
        dedicatedIp=bool(selection.get("dedicatedIp")),
        autoRenew=bool(selection.get("autoRenew", True)),
        promoCode=selection.get("promoCode"),
    )
    effective_payment_method_id = (
        provider_payment_method_id
        or (
            row["provider_payment_method_id"]
            if "provider_payment_method_id" in row.keys()
            else None
        )
    )
    result = apply_tariff_for_user(
        int(row["user_id"]),
        payload,
        provider_payment_method_id=effective_payment_method_id,
        quote_override=order_quote if isinstance(order_quote, dict) and order_quote else None,
    )
    now = utc_now_iso()

    with db() as conn:
        conn.execute(
            """
            UPDATE billing_orders
            SET status = ?, provider_payment_id = ?, paid_at = COALESCE(paid_at, ?),
                provider_payment_method_id = COALESCE(?, provider_payment_method_id),
                activated_at = ?, updated_at = ?
            WHERE public_id = ?
            """,
            (
                "activated",
                provider_payment_id or row["provider_payment_id"],
                now,
                provider_payment_method_id,
                now,
                now,
                public_id,
            ),
        )
        conn.commit()
        updated = conn.execute(
            "SELECT * FROM billing_orders WHERE public_id = ?",
            (public_id,),
        ).fetchone()

    updated_status = billing_order_status(updated)
    record_promo_redemption(updated, updated_status)

    return {
        "order": updated_status,
        "selection": result["selection"],
        "quote": result["quote"],
        "subscription": result["subscription"],
    }


def ensure_device_row(
    user_id: int,
    device_uid: str,
    device_name: str,
    platform: str,
    app_version: str,
):
    with db() as conn:
        existing = conn.execute(
            "SELECT * FROM devices WHERE device_uid = ?",
            (device_uid,),
        ).fetchone()

        if existing is not None and existing["user_id"] != user_id:
            raise HTTPException(
                status_code=409,
                detail="This device is already attached to another user.",
            )

        now = utc_now_iso()

        if existing is None:
            conn.execute(
                """
                INSERT INTO devices(
                    user_id, device_uid, device_name, platform, app_version,
                    created_at, updated_at
                )
                VALUES (?, ?, ?, ?, ?, ?, ?)
                """,
                (user_id, device_uid, device_name, platform, app_version, now, now),
            )
            conn.commit()
        else:
            conn.execute(
                """
                UPDATE devices
                SET device_name = ?, platform = ?, app_version = ?, updated_at = ?
                WHERE device_uid = ?
                """,
                (device_name, platform, app_version, now, device_uid),
            )
            conn.commit()

        row = conn.execute(
            "SELECT * FROM devices WHERE device_uid = ?",
            (device_uid,),
        ).fetchone()

    return row


def ensure_device_keys_and_ip(device_uid: str):
    with db() as conn:
        row = conn.execute(
            "SELECT * FROM devices WHERE device_uid = ?",
            (device_uid,),
        ).fetchone()

        if row is None:
            raise HTTPException(status_code=404, detail="Device not found.")

        assigned_ip = row["assigned_ip"]
        client_private_key = row["client_private_key"]
        client_public_key = row["client_public_key"]
        preshared_key = row["preshared_key"]

        changed = False

        if not assigned_ip:
            assigned_ip = allocate_ip()
            changed = True

        if not client_private_key or not client_public_key:
            client_private_key, client_public_key = wg_genkeypair()
            changed = True

        if not preshared_key:
            preshared_key = wg_genpsk()
            changed = True

        if changed:
            conn.execute(
                """
                UPDATE devices
                SET assigned_ip = ?, client_private_key = ?, client_public_key = ?,
                    preshared_key = ?, updated_at = ?
                WHERE device_uid = ?
                """,
                (
                    assigned_ip,
                    client_private_key,
                    client_public_key,
                    preshared_key,
                    utc_now_iso(),
                    device_uid,
                ),
            )
            conn.commit()

        row = conn.execute(
            "SELECT * FROM devices WHERE device_uid = ?",
            (device_uid,),
        ).fetchone()

    return row


def reissue_device_keys_and_ip(device_uid: str) -> dict:
    with db() as conn:
        row = conn.execute(
            "SELECT * FROM devices WHERE device_uid = ?",
            (device_uid,),
        ).fetchone()
        if row is None:
            raise HTTPException(status_code=404, detail="Device not found.")

        assigned_ip = row["assigned_ip"] or allocate_ip()
        old_public_key = row["client_public_key"] or ""
        client_private_key, client_public_key = wg_genkeypair()
        preshared_key = wg_genpsk()
        now = utc_now_iso()

        conn.execute(
            """
            UPDATE devices
            SET assigned_ip = ?,
                client_private_key = ?,
                client_public_key = ?,
                preshared_key = ?,
                updated_at = ?
            WHERE device_uid = ?
            """,
            (
                assigned_ip,
                client_private_key,
                client_public_key,
                preshared_key,
                now,
                device_uid,
            ),
        )
        conn.commit()
        updated = conn.execute(
            "SELECT * FROM devices WHERE device_uid = ?",
            (device_uid,),
        ).fetchone()

    return {
        "device": updated,
        "oldPublicKey": old_public_key,
        "requestedAt": row["support_config_refresh_requested_at"],
        "requestedBy": row["support_config_refresh_requested_by"],
        "reason": row["support_config_refresh_reason"]
        or "support_requested_config_refresh",
    }


def clear_support_config_refresh_after_issue(device_uid: str, reason: str) -> None:
    now = utc_now_iso()
    with db() as conn:
        conn.execute(
            """
            UPDATE devices
            SET support_config_refresh_requested_at = NULL,
                support_config_refresh_reason = NULL,
                support_config_refresh_requested_by = NULL,
                support_config_refresh_applied_at = ?,
                support_config_refresh_applied_reason = ?,
                updated_at = ?
            WHERE device_uid = ?
            """,
            (
                now,
                clean_limited_text(reason, 500).strip()
                or "support_requested_config_refresh",
                now,
                device_uid,
            ),
        )
        conn.commit()


def upsert_peer_block_in_wg0(device_uid: str, public_key: str, psk: str, ip: str) -> None:
    begin = f"# BEGIN BLUEVPN MANAGED PEER {device_uid}"
    end = f"# END BLUEVPN MANAGED PEER {device_uid}"
    block = (
        f"{begin}\n"
        f"[Peer]\n"
        f"PublicKey = {public_key}\n"
        f"PresharedKey = {psk}\n"
        f"AllowedIPs = {ip}/32\n"
        f"{end}\n"
    )

    if not WG_CONFIG_PATH.exists():
        raise HTTPException(status_code=500, detail=f"{WG_CONFIG_PATH} not found.")

    text = WG_CONFIG_PATH.read_text(encoding="utf-8")
    pattern = re.compile(
        rf"{re.escape(begin)}.*?{re.escape(end)}\n?",
        flags=re.DOTALL,
    )

    if pattern.search(text):
        text = pattern.sub(block, text)
    else:
        if not text.endswith("\n"):
            text += "\n"
        text += "\n" + block

    WG_CONFIG_PATH.write_text(text, encoding="utf-8")


def apply_peer_live(public_key: str, psk: str, ip: str) -> None:
    with tempfile.NamedTemporaryFile("w", delete=False, encoding="utf-8") as tmp:
        tmp.write(psk)
        tmp_path = tmp.name

    try:
        subprocess.run(
            [
                "wg",
                "set",
                WG_INTERFACE,
                "peer",
                public_key,
                "preshared-key",
                tmp_path,
                "allowed-ips",
                f"{ip}/32",
            ],
            check=True,
            capture_output=True,
            text=True,
        )
    finally:
        try:
            os.unlink(tmp_path)
        except FileNotFoundError:
            pass


def best_effort_remove_peer_live(public_key: str) -> bool:
    public_key = clean_limited_text(public_key, 120).strip()
    if not public_key:
        return False
    try:
        subprocess.run(
            ["wg", "set", WG_INTERFACE, "peer", public_key, "remove"],
            check=True,
            capture_output=True,
            text=True,
            timeout=3,
        )
        return True
    except Exception:
        return False


def build_client_config(
    client_private_key: str,
    preshared_key: str,
    server_public_key: str,
    client_ip: str,
) -> str:
    return (
        "[Interface]\n"
        f"PrivateKey = {client_private_key}\n"
        f"Address = {client_ip}/32\n"
        f"DNS = {WG_DNS}\n\n"
        "[Peer]\n"
        f"PublicKey = {server_public_key}\n"
        f"PresharedKey = {preshared_key}\n"
        f"Endpoint = {WG_ENDPOINT_HOST}:{WG_ENDPOINT_PORT}\n"
        f"AllowedIPs = {WG_ALLOWED_IPS}\n"
        "PersistentKeepalive = 25\n"
    )


def monitoring_check(code: str, title: str, status: str, message: str, **extra) -> dict:
    out = {
        "code": code,
        "title": title,
        "status": status,
        "message": message,
    }
    out.update(extra)
    return out


def probe_public_service(target: dict) -> dict:
    code = str(target["code"])
    title = str(target["title"])
    host = str(target["host"])
    url = str(target["url"])
    started = time.monotonic()
    dns_ok = False
    tcp_ok = False
    tls_ok = False
    http_ok = False
    ip = ""
    http_status: Optional[int] = None
    errors: list[str] = []

    try:
        infos = socket.getaddrinfo(host, 443, type=socket.SOCK_STREAM)
        ip = infos[0][4][0] if infos else ""
        dns_ok = bool(ip)
    except Exception as exc:
        errors.append(f"dns: {exc}")

    if dns_ok:
        sock = None
        try:
            sock = socket.create_connection(
                (host, 443),
                timeout=SERVICE_CHECK_TIMEOUT_SECONDS,
            )
            tcp_ok = True
            context = ssl.create_default_context()
            with context.wrap_socket(sock, server_hostname=host) as tls_sock:
                tls_ok = True
                tls_sock.version()
                sock = None
        except Exception as exc:
            errors.append(f"tls/tcp: {exc}")
        finally:
            if sock is not None:
                try:
                    sock.close()
                except Exception:
                    pass

    if tls_ok:
        try:
            req = urllib.request.Request(
                url,
                headers={"User-Agent": "GreenVPN-Monitor/0.1"},
                method="GET",
            )
            with urllib.request.urlopen(
                req,
                timeout=SERVICE_CHECK_TIMEOUT_SECONDS,
            ) as res:
                http_status = int(res.status)
                http_ok = http_status < 500
        except urllib.error.HTTPError as exc:
            http_status = int(exc.code)
            http_ok = http_status < 500
        except Exception as exc:
            errors.append(f"http: {exc}")

    status = "green" if dns_ok and tcp_ok and tls_ok and http_ok else "red"
    if dns_ok and tcp_ok and tls_ok and not http_ok:
        status = "yellow"

    elapsed_ms = int((time.monotonic() - started) * 1000)
    message = (
        "DNS, TCP, TLS и HTTP доступны с VPN-сервера."
        if status == "green"
        else (
            "TLS доступен, но HTTP-проверка дала предупреждение."
            if status == "yellow"
            else "Сервис недоступен с VPN-сервера."
        )
    )
    return monitoring_check(
        code,
        title,
        status,
        message,
        host=host,
        url=url,
        resolvedIp=ip,
        dns=dns_ok,
        tcp=tcp_ok,
        tls=tls_ok,
        http=http_ok,
        httpStatus=http_status,
        latencyMs=elapsed_ms,
        errors=errors,
    )


def build_service_availability_status() -> dict:
    checks = [probe_public_service(target) for target in SERVICE_CHECK_TARGETS]
    red_count = len([c for c in checks if c["status"] == "red"])
    yellow_count = len([c for c in checks if c["status"] == "yellow"])
    state = "red" if red_count else ("yellow" if yellow_count else "green")
    message = (
        "Один или несколько важных сервисов недоступны с VPN-сервера."
        if state == "red"
        else (
            "Есть предупреждения по важным сервисам."
            if state == "yellow"
            else "YouTube, Discord и Telegram доступны с VPN-сервера."
        )
    )
    return {
        "ok": red_count == 0,
        "generatedAt": utc_now_iso(),
        "probeLocation": {
            "type": "vpn_server_egress",
            "serverId": "intelligent_smew",
            "endpoint": f"{WG_ENDPOINT_HOST}:{WG_ENDPOINT_PORT}",
            "note": "MVP-проверка идёт с backend/VPN-сервера. Позже добавим agents, которые подключаются через Green VPN как реальные клиенты.",
        },
        "summary": {
            "state": state,
            "message": message,
            "red": red_count,
            "yellow": yellow_count,
            "green": len(checks) - red_count - yellow_count,
        },
        "checks": checks,
    }


def build_monitoring_status() -> dict:
    checks: list[dict] = []

    checks.append(
        monitoring_check(
            "backend",
            "Backend API",
            "green",
            f"{APP_TITLE} {APP_VERSION} отвечает.",
            version=APP_VERSION,
        )
    )

    try:
        with db() as conn:
            user_count = conn.execute("SELECT COUNT(*) AS cnt FROM users").fetchone()["cnt"]
            device_count = conn.execute("SELECT COUNT(*) AS cnt FROM devices").fetchone()["cnt"]
        checks.append(
            monitoring_check(
                "database",
                "Database",
                "green",
                "SQLite доступна.",
                users=int(user_count),
                devices=int(device_count),
            )
        )
    except Exception as exc:
        checks.append(
            monitoring_check(
                "database",
                "Database",
                "red",
                f"Ошибка БД: {exc}",
            )
        )

    try:
        public_key = get_server_public_key()
        checks.append(
            monitoring_check(
                "wireguard",
                "WireGuard",
                "green",
                f"{WG_INTERFACE} отвечает, endpoint {WG_ENDPOINT_HOST}:{WG_ENDPOINT_PORT}.",
                interface=WG_INTERFACE,
                endpoint=f"{WG_ENDPOINT_HOST}:{WG_ENDPOINT_PORT}",
                publicKeyPrefix=public_key[:10],
            )
        )
    except Exception as exc:
        checks.append(
            monitoring_check(
                "wireguard",
                "WireGuard",
                "red",
                f"Не удалось прочитать WireGuard: {exc}",
                interface=WG_INTERFACE,
                endpoint=f"{WG_ENDPOINT_HOST}:{WG_ENDPOINT_PORT}",
            )
        )

    catalog = build_server_catalog()
    healthy_servers = [
        s
        for s in catalog["servers"]
        if s.get("available") is True and s.get("status") == "healthy"
    ]
    checks.append(
        monitoring_check(
            "server_catalog",
            "Server Catalog",
            "green" if healthy_servers else "yellow",
            f"Доступно endpoint: {len(healthy_servers)} из {len(catalog['servers'])}.",
            version=catalog["version"],
            healthy=len(healthy_servers),
            total=len(catalog["servers"]),
        )
    )

    update_manifest = build_windows_update_manifest()
    checks.append(
        monitoring_check(
            "updates",
            "Updates",
            "green" if update_manifest.get("latestVersion") else "yellow",
            (
                "Update manifest настроен."
                if update_manifest.get("latestVersion")
                else "latestVersion не задан."
            ),
            latestVersion=update_manifest.get("latestVersion"),
            source=update_manifest.get("source"),
            hasDownloadUrl=bool(update_manifest.get("downloadUrl")),
            hasSha256=bool(update_manifest.get("sha256")),
            required=bool(update_manifest.get("required")),
        )
    )

    payment_readiness = yookassa_payment_readiness()
    checks.append(
        monitoring_check(
            "payments",
            "Payments",
            "green" if payment_readiness["productionReady"] else "yellow",
            "Production-платежи готовы."
            if payment_readiness["productionReady"]
            else "Пока ручной MVP-режим оплаты или не настроен production HTTPS/YooKassa.",
            provider=payment_readiness["provider"],
            productionReady=payment_readiness["productionReady"],
        )
    )

    red_count = len([c for c in checks if c["status"] == "red"])
    yellow_count = len([c for c in checks if c["status"] == "yellow"])
    state = "red" if red_count else ("yellow" if yellow_count else "green")
    message = (
        "Есть критичные проблемы."
        if state == "red"
        else (
            "Есть предупреждения MVP-режима."
            if state == "yellow"
            else "Все базовые проверки зелёные."
        )
    )

    return {
        "ok": red_count == 0,
        "generatedAt": utc_now_iso(),
        "summary": {
            "state": state,
            "message": message,
            "red": red_count,
            "yellow": yellow_count,
            "green": len(checks) - red_count - yellow_count,
        },
        "checks": checks,
    }


def build_product_readiness() -> dict:
    public_site = public_site_readiness()
    payment = yookassa_payment_readiness()
    email = email_confirmation_readiness()
    sms = sms_confirmation_readiness()
    auth_codes = auth_code_readiness()
    user_auth_flow = user_auth_flow_readiness()
    alerts = admin_alert_readiness()
    admin_2fa = admin_2fa_readiness()
    api_split = api_vpn_endpoint_separation_readiness()
    update_manifest = build_windows_update_manifest()
    update_readiness = build_update_release_readiness()
    catalog = build_server_catalog()
    catalog_provisioning = build_server_provisioning_readiness(catalog)
    monitoring = build_monitoring_status()
    service_monitoring = build_service_availability_observation_summary()
    monitoring_probes = service_monitoring.get("probeReadiness") or {}

    checks = [
        {
            "code": "public_api",
            "title": "Production API",
            "ok": _is_https_url(PUBLIC_API_BASE_URL)
            and _url_host(PUBLIC_API_BASE_URL) not in {"localhost", "127.0.0.1", ""},
            "message": "GREENVPN_PUBLIC_API_BASE_URL/GREENVPN_PUBLIC_BASE_URL should point to https://api.greenvpn.pro.",
            "value": PUBLIC_API_BASE_URL,
        },
        {
            "code": "public_site",
            "title": "Public site and legal pages",
            "ok": bool(public_site.get("productionReady")),
            "message": "Public site must expose legal pages, pricing/download buttons, safe wording and YooKassa URLs.",
            "value": {
                "siteUrl": public_site.get("siteUrl"),
                "summary": public_site.get("summary"),
            },
        },
        {
            "code": "api_vpn_endpoint_split",
            "title": "API and VPN endpoint split",
            "ok": bool(api_split.get("productionReady")),
            "message": (
                "Move public API/site to an IP that is not used as a VPN endpoint before "
                "public rollout."
            ),
            "value": {
                "publicApiUrls": api_split.get("publicApiUrls"),
                "vpnEndpointHost": api_split.get("vpnEndpointHost"),
                "overlapIps": api_split.get("overlapIps"),
            },
        },
        {
            "code": "email",
            "title": "Email delivery",
            "ok": bool(email.get("productionReady")),
            "message": "SMTP/Yandex 360 must be configured for real email codes.",
        },
        {
            "code": "sms",
            "title": "SMS delivery",
            "ok": bool(sms.get("productionReady")),
            "message": "SMS.ru must be configured for phone login codes.",
        },
        {
            "code": "user_auth_flow",
            "title": "User auth flow",
            "ok": bool(user_auth_flow.get("productionReady")),
            "message": "Code-first login/register contract should be ready: phone primary, email fallback, safe code policy and no dev-code exposure.",
        },
        {
            "code": "payments",
            "title": "Payments",
            "ok": bool(payment.get("productionReady")),
            "message": "YooKassa production keys and HTTPS webhook must be configured.",
        },
        {
            "code": "updates",
            "title": "Updates",
            "ok": bool(update_readiness.get("productionReady")),
            "message": "Publish final HTTPS installer artifact, SHA256 and database release before public rollout.",
        },
        {
            "code": "server_catalog",
            "title": "Server catalog",
            "ok": bool(catalog.get("servers"))
            and bool(catalog_provisioning.get("safeForCurrentClient")),
            "message": "Public catalog and client config serverId gate must stay safe.",
        },
        {
            "code": "monitoring",
            "title": "Monitoring",
            "ok": bool(monitoring.get("ok")),
            "message": "Backend/WireGuard monitoring should be green.",
        },
        {
            "code": "monitoring_probes",
            "title": "Controlled service probes",
            "ok": bool(monitoring_probes.get("productionReady")),
            "message": "Install a separate monitoring VPS probe for YouTube/Discord/Telegram/API checks.",
        },
        {
            "code": "admin_alerts",
            "title": "Admin alerts",
            "ok": bool(alerts.get("productionReady")),
            "message": "Telegram incident alerts should be configured for support/ops.",
        },
        {
            "code": "admin_2fa",
            "title": "Staff 2FA",
            "ok": bool(admin_2fa.get("productionReady")),
            "message": "Email 2FA for staff sessions is ready when enabled or required.",
        },
    ]
    missing = [check for check in checks if not check["ok"]]
    return {
        "ok": True,
        "generatedAt": utc_now_iso(),
        "productionReady": len(missing) == 0,
        "summary": {
            "green": len(checks) - len(missing),
            "yellow": len(missing),
            "red": 0,
            "message": (
                "Production контур готов."
                if not missing
                else "Есть внешние действия перед production-запуском."
            ),
        },
        "checks": checks,
        "requiredActions": [check["message"] for check in missing],
        "publicSiteReadiness": public_site,
        "paymentReadiness": payment,
        "emailReadiness": email,
        "smsReadiness": sms,
        "authCodeReadiness": auth_codes,
        "userAuthFlowReadiness": user_auth_flow,
        "alertReadiness": alerts,
        "adminTwoFactorReadiness": admin_2fa,
        "apiVpnEndpointSeparationReadiness": api_split,
        "updateReadiness": update_readiness,
        "monitoringProbeReadiness": monitoring_probes,
        "serviceMonitoring": service_monitoring,
        "updateManifest": update_manifest,
        "serverCatalog": catalog,
        "serverProvisioningReadiness": catalog_provisioning,
    }


LAUNCH_GATE_SEVERITY = {
    "public_api": "critical",
    "public_site": "critical",
    "api_vpn_endpoint_split": "critical",
    "server_catalog": "critical",
    "payments": "critical",
    "updates": "critical",
    "sms": "warning",
    "email": "warning",
    "user_auth_flow": "warning",
    "monitoring": "warning",
    "monitoring_probes": "warning",
    "admin_alerts": "warning",
    "admin_2fa": "warning",
}


LAUNCH_GATE_TITLES_RU = {
    "public_api": "Публичный API и сайт",
    "public_site": "Публичный сайт, legal и YooKassa URL",
    "api_vpn_endpoint_split": "Разделение сайта/API и VPN endpoint",
    "server_catalog": "Каталог серверов",
    "payments": "Платежи",
    "updates": "Финальный установщик и обновления",
    "sms": "SMS-коды",
    "email": "Email-коды",
    "user_auth_flow": "Пользовательский вход",
    "monitoring": "Мониторинг backend/VPN",
    "monitoring_probes": "Внешние проверки доступности",
    "admin_alerts": "Оповещения админов",
    "admin_2fa": "2FA сотрудников админки",
}


LAUNCH_GATE_NEXT_ACTION_RU = {
    "public_api": "Оставить публичные URL на HTTPS-домене api.greenvpn.pro.",
    "public_site": "Проверить legal-страницы, тарифы/кнопки скачивания, безопасные формулировки и URL для ЮKassa.",
    "api_vpn_endpoint_split": "Разнести публичный сайт/API и VPN endpoint по разным IP перед публичным запуском.",
    "server_catalog": "Не публиковать новые managed-серверы, пока каталог безопасен для текущего Windows-клиента.",
    "payments": "Дождаться активного статуса самозанятого/ЮKassa и применить production-ключи только через серверный env.",
    "updates": "Собрать финальный Windows-установщик только в конце, опубликовать HTTPS-ссылку, SHA256 и rollback.",
    "sms": "Держать SMS.ru в рабочем режиме или явно оставить email как основной канал входа.",
    "email": "Держать Yandex 360 SMTP рабочим для кодов входа, уведомлений и 2FA админки.",
    "user_auth_flow": "Держать вход code-first: телефон как основной канал, email как запасной, dev-коды выключены.",
    "monitoring": "Держать backend/WireGuard monitoring зелёным перед тестами и релизом.",
    "monitoring_probes": "Поставить отдельный внешний probe, чтобы проверять сайт/API и пользовательские сервисы не с того же сервера.",
    "admin_alerts": "Подключить Telegram incident alerts, когда владелец даст bot token/chat id.",
    "admin_2fa": "Включить 2FA минимум для владельца и ключевых staff-аккаунтов перед публичным запуском.",
}


def launch_gate_payload(
    code: str,
    ready: bool,
    message: str,
    *,
    severity: Optional[str] = None,
    title: Optional[str] = None,
    next_action: Optional[str] = None,
    details: Optional[dict] = None,
) -> dict:
    safe_severity = severity or LAUNCH_GATE_SEVERITY.get(code, "warning")
    return {
        "code": code,
        "title": title or LAUNCH_GATE_TITLES_RU.get(code, code),
        "ready": bool(ready),
        "severity": safe_severity,
        "message": clean_limited_text(message, 1000),
        "nextAction": clean_limited_text(
            next_action or LAUNCH_GATE_NEXT_ACTION_RU.get(code, ""),
            1200,
        ),
        "details": details or {},
    }


def build_launch_readiness() -> dict:
    product = build_product_readiness()
    product_checks = {
        clean_limited_text(check.get("code"), 80): check
        for check in product.get("checks", [])
    }
    external_actions = build_external_actions_checklist()
    renewal = billing_renewal_readiness_payload(limit=10)
    expiry = subscription_expiry_readiness_payload(limit=10)
    promo_readiness = billing_promo_launch_readiness_payload(limit=10)
    support_sla = build_support_sla_dashboard(limit=10)

    gates = []
    for code in [
        "public_api",
        "public_site",
        "api_vpn_endpoint_split",
        "server_catalog",
        "payments",
        "updates",
        "sms",
        "email",
        "user_auth_flow",
        "monitoring",
        "monitoring_probes",
        "admin_alerts",
        "admin_2fa",
    ]:
        check = product_checks.get(code, {})
        gates.append(
            launch_gate_payload(
                code,
                bool(check.get("ok")),
                check.get("message") or LAUNCH_GATE_NEXT_ACTION_RU.get(code, ""),
                details={"value": check.get("value")} if "value" in check else {},
            )
        )

    renewal_summary = renewal.get("summary") or {}
    gates.append(
        launch_gate_payload(
            "billing_renewals",
            not bool(renewal.get("requiresAttention")),
            renewal_summary.get("message")
            or "Автопродление пока работает в режиме проверки готовности.",
            severity="warning",
            title="Автопродления подписок",
            next_action=(
                "Автоматические списания не включать, пока нет production-платежей, "
                "чистого payment smoke и чистого dry-run по автопродлениям."
            ),
            details={
                "requiresAttention": renewal.get("requiresAttention"),
                "safeToEnableAutoRenewalCharges": renewal.get("safeToEnableAutoRenewalCharges"),
                "paymentSmokeCompleted": renewal.get("paymentSmokeCompleted"),
                "paymentSmokeReady": renewal.get("paymentSmokeReady"),
                "dueWithinWindow": renewal_summary.get("dueWithinWindow"),
                "expired": renewal_summary.get("expired"),
                "pendingOrderConflicts": renewal_summary.get("pendingOrderConflicts"),
            },
        )
    )

    expiry_summary = expiry.get("summary") or {}
    gates.append(
        launch_gate_payload(
            "subscription_expiry",
            not bool(expiry.get("requiresAttention")),
            expiry_summary.get("message")
            or "Контроль истечения подписок пока работает в режиме проверки готовности.",
            severity="warning",
            title="Истечение подписок",
            next_action=(
                "Не включать жёсткое ограничение доступа до чистой проверки истекающих "
                "подписок, production-платежей и payment smoke."
            ),
            details={
                "requiresAttention": expiry.get("requiresAttention"),
                "safeToEnableExpiryEnforcement": expiry.get("safeToEnableExpiryEnforcement"),
                "paymentSmokeCompleted": expiry.get("paymentSmokeCompleted"),
                "paymentSmokeReady": expiry.get("paymentSmokeReady"),
                "activeNow": expiry_summary.get("activeNow"),
                "expiringWithinWindow": expiry_summary.get("expiringWithinWindow"),
                "expired": expiry_summary.get("expired"),
                "blockedExpiring": expiry_summary.get("blockedExpiring"),
            },
        )
    )

    promo_summary = promo_readiness.get("summary") or {}
    gates.append(
        launch_gate_payload(
            "promo_campaign",
            bool(promo_readiness.get("safeToRunLaunchCampaign")),
            promo_summary.get("message")
            or "Стартовая акция пока не готова к публичному запуску.",
            severity="warning",
            title="Акции и промокоды",
            next_action=(
                "Подготовить ограниченный промокод START20: скидка до 20%, лимит 50-100 "
                "использований, дата окончания и явные тарифы."
            ),
            details={
                "safeToRunLaunchCampaign": promo_readiness.get("safeToRunLaunchCampaign"),
                "requiresAttention": promo_readiness.get("requiresAttention"),
                "total": promo_summary.get("total"),
                "active": promo_summary.get("active"),
                "launchReady": promo_summary.get("launchReady"),
                "activeRisky": promo_summary.get("activeRisky"),
                "recommendedCode": promo_summary.get("recommendedCode"),
            },
        )
    )

    support_summary = support_sla.get("summary") or {}
    gates.append(
        launch_gate_payload(
            "support_sla",
            not bool(support_sla.get("attentionRequired")),
            (
                "Очередь поддержки чистая."
                if not support_sla.get("attentionRequired")
                else "Есть обращения поддержки, которые требуют внимания перед релизом."
            ),
            severity="warning",
            title="Поддержка и SLA",
            next_action="Закрыть просроченные/ожидающие ответа обращения перед публичным запуском.",
            details={
                "attentionRequired": support_sla.get("attentionRequired"),
                "open": support_summary.get("open"),
                "overdue": support_summary.get("overdue"),
                "dueSoon": support_summary.get("dueSoon"),
                "firstResponseMissing": support_summary.get("firstResponseMissing"),
                "reviewPending": support_summary.get("reviewPending"),
            },
        )
    )

    blocking_summary = external_actions.get("blockingSummary") or {}
    gates.append(
        launch_gate_payload(
            "owner_actions",
            bool(blocking_summary.get("safeToProceed")) and bool(external_actions.get("productionReady")),
            (external_actions.get("summary") or {}).get("message")
            or "Внешние действия владельца сверяются отдельным чеклистом.",
            severity="warning",
            title="Внешние действия владельца",
            next_action="Держать чеклист внешних сервисов актуальным: DNS, YooKassa, SMS, SMTP, Telegram alerts.",
            details={
                "pendingCodes": blocking_summary.get("pendingCodes") or [],
                "waitingCodes": blocking_summary.get("waitingCodes") or [],
                "blockedCodes": blocking_summary.get("blockedCodes") or [],
                "doneButBackendNotReadyCodes": blocking_summary.get("doneButBackendNotReadyCodes") or [],
                "missingOwnerNoteCodes": blocking_summary.get("missingOwnerNoteCodes") or [],
            },
        )
    )

    critical_blockers = [
        gate for gate in gates if not gate["ready"] and gate["severity"] == "critical"
    ]
    warnings = [
        gate for gate in gates if not gate["ready"] and gate["severity"] != "critical"
    ]
    ready_count = len([gate for gate in gates if gate["ready"]])
    state_code = "green" if not critical_blockers and not warnings else (
        "red" if critical_blockers else "yellow"
    )
    message = (
        "Публичный запуск готов."
        if state_code == "green"
        else (
            "Есть критичные блокеры публичного запуска."
            if state_code == "red"
            else "Критичных блокеров нет, но остались предупреждения перед запуском."
        )
    )

    return {
        "ok": True,
        "version": APP_VERSION,
        "generatedAt": utc_now_iso(),
        "state": state_code,
        "publicLaunchReady": not critical_blockers,
        "productionReady": not critical_blockers and not warnings,
        "summary": {
            "state": state_code,
            "ready": ready_count,
            "total": len(gates),
            "critical": len(critical_blockers),
            "warnings": len(warnings),
            "message": message,
            "nextCriticalAction": (
                critical_blockers[0]["nextAction"] or critical_blockers[0]["message"]
                if critical_blockers
                else ""
            ),
            "nextWarningAction": (
                warnings[0]["nextAction"] or warnings[0]["message"]
                if warnings
                else ""
            ),
        },
        "gates": gates,
        "criticalBlockers": critical_blockers,
        "warnings": warnings,
        "nextOwnerActions": external_actions.get("nextOwnerBatch") or [],
        "externalBlockingSummary": blocking_summary,
        "productReadinessSummary": product.get("summary") or {},
        "manualModes": {
            "subscriptionEnforcement": ENFORCE_SUBSCRIPTION_ACCESS,
            "autoRenewalCharges": (renewal.get("policy") or {}).get("automaticChargeExecution"),
            "expiryMode": (expiry.get("policy") or {}).get("mode"),
        },
    }


LAUNCH_CLOSURE_ACTION_SPECS = {
    "public_api": {
        "category": "network",
        "ownerRequired": False,
        "autonomousCodeWork": False,
        "operatorAction": "Keep public API URLs on HTTPS greenvpn.pro origins.",
    },
    "public_site": {
        "category": "public_site",
        "ownerRequired": False,
        "autonomousCodeWork": False,
        "operatorAction": "Keep public site, legal, download and YooKassa public URLs green.",
    },
    "api_vpn_endpoint_split": {
        "category": "network",
        "ownerRequired": True,
        "autonomousCodeWork": False,
        "ownerInput": "Separate public API/site IP or reverse proxy target, plus DNS decision for api.greenvpn.pro and VPN endpoint host.",
        "secret": False,
        "safeWithoutOwner": False,
    },
    "server_catalog": {
        "category": "servers",
        "ownerRequired": False,
        "autonomousCodeWork": True,
        "operatorAction": "Keep future VPN endpoints as internal drafts until provisioning/health/canary gates are green.",
    },
    "payments": {
        "category": "payments",
        "ownerRequired": True,
        "autonomousCodeWork": False,
        "ownerInput": "YOOKASSA_SHOP_ID and YOOKASSA_SECRET_KEY through scripts\\windows\\configure_backend_env_wsl.ps1 only.",
        "secret": True,
        "safeWithoutOwner": False,
    },
    "updates": {
        "category": "release",
        "ownerRequired": False,
        "autonomousCodeWork": False,
        "finalHandoffOnly": True,
        "operatorAction": "Build final installer and publish update/rollback metadata only at final handoff or explicit owner stop-and-test request.",
    },
    "sms": {
        "category": "auth",
        "ownerRequired": True,
        "autonomousCodeWork": False,
        "ownerInput": "SMS.ru api_id and sender decision through server-only env when SMS readiness is not green.",
        "secret": True,
    },
    "email": {
        "category": "auth",
        "ownerRequired": True,
        "autonomousCodeWork": False,
        "ownerInput": "SMTP mailbox/app password and DNS mail records through server-only env/provider panels when email readiness is not green.",
        "secret": True,
    },
    "user_auth_flow": {
        "category": "auth",
        "ownerRequired": False,
        "autonomousCodeWork": False,
        "operatorAction": "Watch auth events for real-world UX errors; backend readiness is code-first.",
    },
    "monitoring": {
        "category": "monitoring",
        "ownerRequired": False,
        "autonomousCodeWork": True,
        "operatorAction": "Keep backend/WireGuard monitoring green and incidents synced.",
    },
    "monitoring_probes": {
        "category": "monitoring",
        "ownerRequired": True,
        "autonomousCodeWork": False,
        "ownerInput": "Separate monitoring VPS/probe host and token placement through controlled probe install flow.",
        "secret": True,
    },
    "admin_alerts": {
        "category": "ops",
        "ownerRequired": True,
        "autonomousCodeWork": False,
        "ownerInput": "Telegram bot token and chat id through server-only env.",
        "secret": True,
    },
    "admin_2fa": {
        "category": "staff",
        "ownerRequired": False,
        "autonomousCodeWork": False,
        "operationalReview": True,
        "operatorAction": "Enable/verify 2FA for owner and key staff before public launch.",
    },
    "billing_renewals": {
        "category": "payments",
        "ownerRequired": False,
        "autonomousCodeWork": True,
        "operationalReview": True,
        "dependsOn": ["payments"],
        "operatorAction": "Keep auto-renewal charges disabled until payment production smoke is clean.",
    },
    "subscription_expiry": {
        "category": "billing",
        "ownerRequired": False,
        "autonomousCodeWork": True,
        "operationalReview": True,
        "dependsOn": ["payments"],
        "operatorAction": "Review expiring users and missing retention contacts before enabling strict expiry enforcement.",
    },
    "promo_campaign": {
        "category": "growth",
        "ownerRequired": False,
        "autonomousCodeWork": False,
        "operationalReview": True,
        "operatorAction": "Create an inactive START20 draft if missing; activate it only after payment/release readiness is green.",
    },
    "support_sla": {
        "category": "support",
        "ownerRequired": False,
        "autonomousCodeWork": True,
        "operationalReview": True,
        "operatorAction": "Clear support queue items that are overdue, review-pending or missing first response.",
    },
    "owner_actions": {
        "category": "owner_actions",
        "ownerRequired": True,
        "autonomousCodeWork": False,
        "ownerInput": "Complete the pending external-service owner actions without pasting secrets into repo/docs/chat.",
        "secret": True,
    },
}


def launch_closure_action_payload(gate: dict, owner_action_by_code: dict) -> dict:
    code = clean_limited_text(gate.get("code"), 80)
    spec = LAUNCH_CLOSURE_ACTION_SPECS.get(code, {})
    owner_action = owner_action_by_code.get(code) or {}
    details = gate.get("details") or {}
    operator_action = spec.get("operatorAction") or ""
    depends_on = list(spec.get("dependsOn") or [])
    draft_prepared = False
    if code == "promo_campaign" and not gate.get("ready"):
        draft_prepared = int(details.get("total") or 0) > 0
        if draft_prepared:
            depends_on = ["payments", "updates"]
            operator_action = (
                "Inactive START20 draft exists; wait for payment/release readiness "
                "before manual activation."
            )
        else:
            operator_action = "Create an inactive START20 draft; do not activate it yet."
    ready = bool(gate.get("ready"))
    owner_required = bool(spec.get("ownerRequired")) and not ready
    final_handoff_only = bool(spec.get("finalHandoffOnly")) and not ready
    operational_review = bool(spec.get("operationalReview")) and not ready
    code_owned = (
        bool(spec.get("autonomousCodeWork"))
        and not ready
        and not owner_required
        and not final_handoff_only
    )
    return {
        "code": code,
        "title": gate.get("title") or code,
        "ready": ready,
        "severity": gate.get("severity") or "warning",
        "category": spec.get("category") or "general",
        "message": gate.get("message") or "",
        "nextAction": gate.get("nextAction") or "",
        "ownerRequired": owner_required,
        "ownerInput": spec.get("ownerInput") or "",
        "secretInputExpected": bool(spec.get("secret")),
        "finalHandoffOnly": final_handoff_only,
        "operationalReview": operational_review,
        "autonomousCodeWork": code_owned,
        "safeWithoutOwner": bool(spec.get("safeWithoutOwner", not owner_required)),
        "dependsOn": depends_on,
        "operatorAction": operator_action,
        "draftPrepared": draft_prepared,
        "ownerStatus": owner_action.get("ownerStatus"),
        "ownerStatusTitle": owner_action.get("ownerStatusTitle"),
        "ownerStatusRecorded": bool(owner_action.get("ownerStatusRecorded")),
        "details": details,
    }


def build_launch_closure_plan() -> dict:
    launch = build_launch_readiness()
    external_actions = build_external_actions_checklist()
    owner_action_by_code = {
        clean_limited_text(action.get("code"), 80): action
        for action in external_actions.get("actions") or []
    }
    actions = [
        launch_closure_action_payload(gate, owner_action_by_code)
        for gate in launch.get("gates") or []
    ]
    pending = [action for action in actions if not action["ready"]]
    owner_blocked = [action for action in pending if action["ownerRequired"]]
    final_handoff = [action for action in pending if action["finalHandoffOnly"]]
    code_owned = [action for action in pending if action["autonomousCodeWork"]]
    operational = [
        action
        for action in pending
        if action["operationalReview"] and not action["ownerRequired"]
    ]
    ready = [action for action in actions if action["ready"]]
    owner_blocked_codes = {action["code"] for action in owner_blocked}

    owner_inputs_needed = [
        {
            "code": action["code"],
            "title": action["title"],
            "ownerInput": action["ownerInput"],
            "secretInputExpected": action["secretInputExpected"],
            "ownerStatus": action.get("ownerStatus"),
            "safeHandling": (
                "Enter secrets only through server-side env/provider dashboards; never paste into repo, docs, owner notes or chat."
                if action["secretInputExpected"]
                else "Non-secret value may be discussed, but prefer provider/admin panels for authoritative changes."
            ),
        }
        for action in owner_blocked
    ]

    unblocked_code_owned = [
        action
        for action in code_owned
        if not action.get("dependsOn")
        or all(dep not in owner_blocked_codes for dep in action.get("dependsOn") or [])
    ]
    unblocked_operational = [
        action
        for action in operational
        if not action.get("dependsOn")
        or all(dep not in owner_blocked_codes for dep in action.get("dependsOn") or [])
    ]
    actionable_operational = [
        action
        for action in unblocked_operational
        if not (
            action["code"] == "promo_campaign"
            and action.get("draftPrepared")
            and final_handoff
        )
    ]
    next_autonomous = unblocked_code_owned or actionable_operational
    state = (
        "green"
        if not pending
        else (
            "owner_blocked"
            if owner_blocked and not code_owned
            else "work_remaining"
        )
    )
    return {
        "ok": True,
        "version": APP_VERSION,
        "generatedAt": utc_now_iso(),
        "state": state,
        "productionReady": bool(launch.get("productionReady")),
        "publicLaunchReady": bool(launch.get("publicLaunchReady")),
        "canContinueAutonomously": bool(next_autonomous),
        "safeNoSecretExposure": True,
        "summary": {
            "state": state,
            "total": len(actions),
            "ready": len(ready),
            "pending": len(pending),
            "ownerBlocked": len(owner_blocked),
            "finalHandoffOnly": len(final_handoff),
            "codeOwned": len(code_owned),
            "operationalReview": len(operational),
            "critical": len([action for action in pending if action["severity"] == "critical"]),
            "warnings": len([action for action in pending if action["severity"] != "critical"]),
            "message": (
                "Launch closure plan is complete."
                if not pending
                else (
                    "Remaining launch items are separated into owner inputs, final-handoff hold and autonomous/operational work."
                )
            ),
            "nextAutonomousAction": (
                next_autonomous[0]["operatorAction"]
                or next_autonomous[0]["nextAction"]
                if next_autonomous
                else ""
            ),
            "nextOwnerInput": (
                owner_inputs_needed[0]["ownerInput"]
                if owner_inputs_needed
                else ""
            ),
        },
        "actions": actions,
        "ownerInputsNeeded": owner_inputs_needed,
        "ownerBlockedActions": owner_blocked,
        "finalHandoffOnlyActions": final_handoff,
        "codeOwnedActions": code_owned,
        "operationalReviewActions": operational,
        "nextAutonomousActions": next_autonomous[:5],
        "readyActions": ready,
        "externalBlockingSummary": external_actions.get("blockingSummary") or {},
        "manualModes": launch.get("manualModes") or {},
        "policy": {
            "mode": "closure_plan_readiness_only",
            "secretPolicy": "Secret values are never returned. This endpoint may name required env keys, but not their values.",
            "installerPolicy": "Do not build a new public Windows installer until final handoff or explicit owner stop-and-test request.",
            "ownerBlockedMeans": "Work is prepared in code, but applying it requires owner/provider input outside the repository.",
        },
    }


def owner_launch_packet_action_item(action: dict) -> dict:
    owner_inputs = [
        {
            "name": item.get("name") or item.get("envKey") or "input",
            "envKey": item.get("envKey"),
            "secret": bool(item.get("secret")),
            "optional": bool(item.get("optional")),
            "example": item.get("example") if not item.get("secret") else None,
        }
        for item in action.get("ownerInputs") or []
    ]
    secret_expected = bool(action.get("secret")) or any(
        bool(item.get("secret")) for item in owner_inputs
    )
    return {
        "code": action.get("code"),
        "title": action.get("title") or action.get("code"),
        "ready": bool(action.get("ready")),
        "status": action.get("status") or ("ready" if action.get("ready") else "pending"),
        "ownerStatus": action.get("ownerStatus"),
        "ownerStatusTitle": action.get("ownerStatusTitle"),
        "ownerAction": action.get("ownerAction"),
        "message": action.get("message"),
        "secretInputExpected": secret_expected,
        "envKeys": list(action.get("envKeys") or []),
        "ownerInputs": owner_inputs,
        "applySteps": list(action.get("applySteps") or []),
        "verifySteps": list(action.get("verifySteps") or []),
        "blocks": list(action.get("blocks") or []),
        "safeHandling": (
            "Enter secret values only through server-side env/provider dashboards; never paste them into repo, docs, owner notes or chat."
            if secret_expected
            else "Non-secret values may be discussed, but provider/admin panels stay authoritative."
        ),
    }


def owner_launch_packet_commands(setup_bundle: dict, split_plan: dict) -> list[dict]:
    commands = []
    apply_command = setup_bundle.get("applyCommand")
    if apply_command:
        commands.append(
            {
                "code": "apply_server_env",
                "title": "Apply server-only env",
                "command": apply_command,
                "secret": True,
                "mutationFree": False,
                "when": "Run only when the owner is ready to enter YooKassa/SMTP/SMS/Telegram secrets into the terminal.",
            }
        )
    preflight = (
        split_plan.get("preflight")
        or setup_bundle.get("splitPreflight")
        or {}
    )
    if preflight.get("command"):
        commands.append(
            {
                "code": "api_vpn_split_preflight",
                "title": "API/VPN split preflight",
                "command": preflight.get("command"),
                "secret": False,
                "mutationFree": True,
                "when": preflight.get("when")
                or "Run after the candidate API/site IP or reverse proxy exists.",
            }
        )
    commands.append(
        {
            "code": "payment_launch_safety",
            "title": "Payment launch safety",
            "command": (
                r"powershell -NoProfile -ExecutionPolicy Bypass -File "
                r"C:\Users\gekto\projects\bluevpn\scripts\windows\check_payment_launch_safety.ps1"
            ),
            "secret": False,
            "mutationFree": True,
            "when": "Run after YooKassa env changes and before enabling auto-renewal or strict expiry enforcement.",
        }
    )
    commands.append(
        {
            "code": "monitoring_probe_plan",
            "title": "Monitoring probe plan",
            "command": (
                r"powershell -NoProfile -ExecutionPolicy Bypass -File "
                r"C:\Users\gekto\projects\bluevpn\scripts\windows\get_monitoring_probe_plan.ps1"
            ),
            "secret": False,
            "mutationFree": True,
            "when": "Run before installing the external monitoring probe; admin token still belongs only on the probe host.",
        }
    )
    readiness_command = setup_bundle.get("readinessCommand")
    if readiness_command:
        commands.append(
            {
                "code": "readiness_self_check",
                "title": "Protected readiness self-check",
                "command": readiness_command,
                "secret": False,
                "mutationFree": True,
                "when": "Run after env/DNS/provider changes to verify launch readiness.",
            }
        )
    return commands


def build_owner_launch_packet() -> dict:
    closure_plan = build_launch_closure_plan()
    external_actions = build_external_actions_checklist()
    network = api_vpn_endpoint_separation_readiness()
    split_plan = network.get("migrationPlan") or {}
    setup_bundle = external_actions.get("setupBundle") or external_owner_setup_bundle()
    owner_actions = [
        owner_launch_packet_action_item(action)
        for action in external_actions.get("actions") or []
    ]
    pending_owner_actions = [
        action for action in owner_actions if not action.get("ready")
    ]
    commands = owner_launch_packet_commands(setup_bundle, split_plan)
    dns_records = [
        record
        for record in (setup_bundle.get("dnsRecords") or [])
        if not record.get("secret")
    ]
    safe_defaults = [
        item for item in (setup_bundle.get("safeDefaults") or []) if "value" in item
    ]

    return {
        "ok": True,
        "version": APP_VERSION,
        "generatedAt": utc_now_iso(),
        "productionReady": bool(closure_plan.get("productionReady")),
        "publicLaunchReady": bool(closure_plan.get("publicLaunchReady")),
        "canContinueAutonomously": bool(closure_plan.get("canContinueAutonomously")),
        "safeNoSecretExposure": True,
        "summary": {
            "message": "Owner launch packet is ready. It names required inputs and commands without returning secret values.",
            "state": closure_plan.get("state"),
            "ready": (closure_plan.get("summary") or {}).get("ready"),
            "pending": (closure_plan.get("summary") or {}).get("pending"),
            "ownerBlocked": (closure_plan.get("summary") or {}).get("ownerBlocked"),
            "commands": len(commands),
            "pendingOwnerActions": len(pending_owner_actions),
            "dnsRecords": len(dns_records),
            "safeDefaults": len(safe_defaults),
        },
        "ownerBlockers": closure_plan.get("ownerInputsNeeded") or [],
        "ownerActions": pending_owner_actions,
        "allOwnerActions": owner_actions,
        "commands": commands,
        "dnsRecords": dns_records,
        "safeDefaults": safe_defaults,
        "splitPreflight": split_plan.get("preflight")
        or setup_bundle.get("splitPreflight")
        or {},
        "afterApplyChecks": list(setup_bundle.get("afterApplyChecks") or []),
        "networkSplit": {
            "productionReady": network.get("productionReady"),
            "publicApiHosts": network.get("publicApiHosts"),
            "vpnEndpointHost": network.get("vpnEndpointHost"),
            "overlapIps": network.get("overlapIps"),
            "migrationPlanReady": bool(split_plan),
        },
        "policy": {
            "mode": "owner_launch_packet_readiness_only",
            "noSecretValues": True,
            "secretPolicy": "This endpoint may name secret env keys and provider fields, but never returns their values.",
            "mutationPolicy": "Commands are labelled with mutationFree. The env apply command is intentionally not mutation-free and must be run only with the owner present.",
            "installerPolicy": "Do not build a new public Windows installer until final handoff or an explicit owner stop-and-test request.",
        },
    }


def external_owner_setup_bundle() -> dict:
    return {
        "applyScript": r"C:\Users\gekto\projects\bluevpn\scripts\windows\configure_backend_env_wsl.ps1",
        "applyCommand": r"powershell -NoProfile -ExecutionPolicy Bypass -File C:\Users\gekto\projects\bluevpn\scripts\windows\configure_backend_env_wsl.ps1",
        "readinessCommand": r"powershell -NoProfile -ExecutionPolicy Bypass -File C:\Users\gekto\projects\bluevpn\scripts\windows\check_external_services_readiness.ps1 -ServerAdminSelfCheck",
        "serverOnlyEnvFile": "/etc/bluevpn/backend.env",
        "serverHost": "37.220.85.211",
        "apiBase": "https://api.greenvpn.pro",
        "vpnEndpointHost": "37.220.85.211",
        "secretPolicy": "Secrets are entered only into the server env or provider dashboards; never into repo docs, owner notes, audit text, or chat transcripts.",
        "dnsRecords": [
            {
                "code": "api_a",
                "type": "A",
                "host": "api.greenvpn.pro",
                "valueHint": "Public API/site IP. Before production it must be different from VPN endpoint 37.220.85.211.",
                "secret": False,
                "verifyWith": "check_external_services_readiness.ps1",
            },
            {
                "code": "mail_mx",
                "type": "MX",
                "host": "greenvpn.pro",
                "value": "mx.yandex.net.",
                "secret": False,
                "verifyWith": "check_external_services_readiness.ps1",
            },
            {
                "code": "mail_spf",
                "type": "TXT",
                "host": "greenvpn.pro",
                "value": "v=spf1 redirect=_spf.yandex.net",
                "secret": False,
                "verifyWith": "check_external_services_readiness.ps1",
            },
            {
                "code": "mail_dmarc",
                "type": "TXT",
                "host": "_dmarc.greenvpn.pro",
                "value": "v=DMARC1; p=none; rua=mailto:postmaster@greenvpn.pro; adkim=s; aspf=s",
                "secret": False,
                "verifyWith": "check_external_services_readiness.ps1",
            },
            {
                "code": "mail_dkim",
                "type": "TXT",
                "host": "mail._domainkey.greenvpn.pro",
                "valueHint": "DKIM value from Yandex 360",
                "secret": False,
                "verifyWith": "check_external_services_readiness.ps1",
            },
        ],
        "safeDefaults": [
            {"envKey": "GREENVPN_PUBLIC_API_BASE_URL", "value": "https://api.greenvpn.pro"},
            {"envKey": "GREENVPN_PUBLIC_BASE_URL", "value": "https://api.greenvpn.pro"},
            {"envKey": "GREENVPN_EMAIL_PUBLIC_BASE_URL", "value": "https://api.greenvpn.pro"},
            {"envKey": "GREENVPN_API_BASE_URLS", "value": "https://api.greenvpn.pro"},
            {"envKey": "YOOKASSA_RETURN_URL", "value": "https://api.greenvpn.pro/payment/return"},
            {"envKey": "YOOKASSA_WEBHOOK_URL", "value": "https://api.greenvpn.pro/api/v1/billing/yookassa/webhook"},
            {"envKey": "GREENVPN_AUTH_CODE_TTL_MINUTES", "value": "10"},
            {"envKey": "GREENVPN_AUTH_CODE_RESEND_COOLDOWN_SECONDS", "value": "60"},
            {"envKey": "GREENVPN_AUTH_CODE_MAX_VERIFY_ATTEMPTS", "value": "5"},
            {"envKey": "GREENVPN_AUTH_CODE_LOCKOUT_MINUTES", "value": "15"},
            {"envKey": "GREENVPN_DEV_AUTH_CODES", "value": "0"},
        ],
        "splitPreflight": {
            "script": r"C:\Users\gekto\projects\bluevpn\scripts\windows\check_api_vpn_split_preflight.ps1",
            "command": (
                r"powershell -NoProfile -ExecutionPolicy Bypass -File "
                r"C:\Users\gekto\projects\bluevpn\scripts\windows\check_api_vpn_split_preflight.ps1 "
                r"-ApiBase https://api.greenvpn.pro -VpnEndpointHost nl1.vpn.greenvpn.pro "
                r"-ExpectedVpnIp 37.220.85.211 -ExpectedApiIp <new-api-site-ip> -Json"
            ),
            "secret": False,
            "mutationFree": True,
        },
        "afterApplyChecks": [
            "/healthz",
            "/api/v1/admin/readiness",
            "/api/v1/admin/site/readiness",
            "/api/v1/admin/launch/closure-plan",
            "/api/v1/admin/auth/user-flow/readiness",
            "/api/v1/admin/network/readiness",
            "/api/v1/admin/network/split-plan",
            "/api/v1/admin/external-actions",
            "/api/v1/admin/email/readiness",
            "/api/v1/admin/sms/readiness",
            "/api/v1/admin/billing/readiness",
            "/api/v1/admin/billing/payment-smoke/readiness",
            "/api/v1/admin/alerts/readiness",
            "/api/v1/admin/monitoring/readiness",
            "/api/v1/admin/updates/readiness",
            "/api/v1/admin/server-catalog/publication-readiness",
            "/api/v1/admin/server-catalog/provisioning-readiness",
        ],
    }


def external_action_specs() -> list[dict]:
    return [
        {
            "code": "public_api",
            "title": "Домен и HTTPS для backend",
            "ownerAction": "Направить api.greenvpn.pro на публичный API/site reverse proxy, не совпадающий по IP с VPN endpoint, и задать HTTPS public base URLs.",
            "envKeys": ["GREENVPN_PUBLIC_API_BASE_URL", "GREENVPN_PUBLIC_BASE_URL", "GREENVPN_EMAIL_PUBLIC_BASE_URL", "GREENVPN_API_BASE_URLS", "BLUEVPN_ENDPOINT_HOST"],
            "ownerInputs": [
                {"name": "api.greenvpn.pro DNS A", "secret": False, "example": "separate public API/site IP, not 37.220.85.211 for production"},
                {"name": "VPN endpoint host/IP", "secret": False, "example": "37.220.85.211"},
                {"name": "HTTPS certificate/reverse proxy", "secret": False, "example": "api.greenvpn.pro"},
            ],
            "applySteps": [
                "DNS/proxy changes are made in provider panels; backend env is applied with configure_backend_env_wsl.ps1.",
                "Keep GREENVPN_API_BASE_URLS on HTTPS public origins only; do not publish the raw VPN endpoint IP as a client bootstrap URL.",
            ],
            "verifySteps": [
                "Run check_api_vpn_split_preflight.ps1 with the candidate API/site IP.",
                "GET https://api.greenvpn.pro/healthz",
                "GET /api/v1/admin/network/readiness",
                "GET /api/v1/admin/network/split-plan",
                "check_external_services_readiness.ps1 -ServerAdminSelfCheck",
            ],
            "secret": False,
            "blocks": ["email_links", "yookassa_webhook", "updates", "public_api"],
        },
        {
            "code": "email",
            "title": "Почта Green VPN",
            "ownerAction": "Создать no-reply@greenvpn.pro/support@greenvpn.pro, включить SMTP/app password, настроить MX/SPF/DKIM/DMARC.",
            "envKeys": [
                "GREENVPN_SMTP_HOST",
                "GREENVPN_SMTP_PORT",
                "GREENVPN_SMTP_USERNAME",
                "GREENVPN_SMTP_PASSWORD",
                "GREENVPN_SMTP_FROM",
            ],
            "ownerInputs": [
                {"name": "SMTP mailbox", "envKey": "GREENVPN_SMTP_USERNAME", "secret": False, "example": "no-reply@greenvpn.pro"},
                {"name": "SMTP app password", "envKey": "GREENVPN_SMTP_PASSWORD", "secret": True},
                {"name": "Support mailbox/alias", "secret": False, "example": "support@greenvpn.pro"},
                {"name": "Postmaster mailbox/alias", "secret": False, "example": "postmaster@greenvpn.pro"},
                {"name": "DMARC TXT", "secret": False, "example": "v=DMARC1; p=none; rua=mailto:postmaster@greenvpn.pro; adkim=s; aspf=s"},
            ],
            "applySteps": [
                "Run configure_backend_env_wsl.ps1 and answer the Yandex 360 SMTP prompts.",
                "Add or verify MX/SPF/DKIM/DMARC records in DNS provider panel.",
            ],
            "verifySteps": [
                "GET /api/v1/admin/email/readiness",
                "Start and verify an email-code login after SMTP is configured.",
                "check_external_services_readiness.ps1 -ServerAdminSelfCheck",
            ],
            "secret": True,
            "blocks": ["email_login_codes", "support_mail"],
        },
        {
            "code": "sms",
            "title": "SMS.ru для входа по телефону",
            "ownerAction": "Получить SMS.ru api_id и, если нужен брендированный отправитель, согласовать GREENVPN_SMS_FROM.",
            "envKeys": ["GREENVPN_SMS_PROVIDER", "GREENVPN_SMS_RU_API_ID", "GREENVPN_SMS_FROM"],
            "ownerInputs": [
                {"name": "SMS.ru api_id", "envKey": "GREENVPN_SMS_RU_API_ID", "secret": True},
                {"name": "Approved sender name", "envKey": "GREENVPN_SMS_FROM", "secret": False, "optional": True, "example": "GreenVPN"},
                {"name": "Test-mode decision", "envKey": "GREENVPN_SMS_RU_TEST_MODE", "secret": False, "example": "0"},
            ],
            "applySteps": [
                "Run configure_backend_env_wsl.ps1 and answer the SMS.ru prompts.",
                "Keep GREENVPN_SMS_RU_TEST_MODE=1 only for provider sandbox checks; production needs 0.",
            ],
            "verifySteps": [
                "GET /api/v1/admin/sms/readiness",
                "Start and verify a phone-code login on an owner-approved test number.",
            ],
            "secret": True,
            "blocks": ["phone_login_codes"],
        },
        {
            "code": "payments",
            "title": "ЮKassa production",
            "ownerAction": "Получить shop_id/secret_key, указать returnUrl/webhook URL в кабинете ЮKassa и передать ключи только в серверный env.",
            "envKeys": ["YOOKASSA_SHOP_ID", "YOOKASSA_SECRET_KEY", "YOOKASSA_RETURN_URL", "YOOKASSA_WEBHOOK_URL"],
            "ownerInputs": [
                {"name": "YOOKASSA_SHOP_ID", "envKey": "YOOKASSA_SHOP_ID", "secret": False},
                {"name": "YOOKASSA_SECRET_KEY", "envKey": "YOOKASSA_SECRET_KEY", "secret": True},
                {"name": "Webhook URL", "envKey": "YOOKASSA_WEBHOOK_URL", "secret": False, "example": "https://api.greenvpn.pro/api/v1/billing/yookassa/webhook"},
                {"name": "Return URL", "envKey": "YOOKASSA_RETURN_URL", "secret": False, "example": "https://api.greenvpn.pro/payment/return"},
            ],
            "applySteps": [
                "Run configure_backend_env_wsl.ps1 and answer the YooKassa prompts.",
                "Enable payment.succeeded and payment.canceled webhook events in YooKassa dashboard.",
            ],
            "verifySteps": [
                "GET /api/v1/admin/billing/readiness",
                "GET /api/v1/admin/billing/payment-smoke/readiness",
                "Create a test/production order only when owner confirms provider mode.",
                "Confirm tariff activation happens only after YooKassa confirmation.",
            ],
            "secret": True,
            "blocks": ["paid_activation", "auto_renew"],
        },
        {
            "code": "updates",
            "title": "Файлы обновлений",
            "ownerAction": "Опубликовать GreenVPN_Setup.exe на updates.greenvpn.pro или другом storage, прописать downloadUrl, SHA256 и rollback artifact.",
            "envKeys": [
                "GREENVPN_UPDATE_URL",
                "GREENVPN_UPDATE_SHA256",
                "GREENVPN_LATEST_VERSION",
                "GREENVPN_ROLLBACK_URL",
                "GREENVPN_ROLLBACK_SHA256",
                "GREENVPN_ROLLBACK_VERSION",
            ],
            "ownerInputs": [
                {"name": "Final installer HTTPS URL", "envKey": "GREENVPN_UPDATE_URL", "secret": False},
                {"name": "Final installer SHA256", "envKey": "GREENVPN_UPDATE_SHA256", "secret": False},
                {"name": "Latest version", "envKey": "GREENVPN_LATEST_VERSION", "secret": False},
                {"name": "Rollback installer HTTPS URL", "envKey": "GREENVPN_ROLLBACK_URL", "secret": False},
                {"name": "Rollback installer SHA256", "envKey": "GREENVPN_ROLLBACK_SHA256", "secret": False},
                {"name": "Rollback version", "envKey": "GREENVPN_ROLLBACK_VERSION", "secret": False},
            ],
            "applySteps": [
                "Do not build a new installer until final handoff or explicit test request.",
                "Create or update an admin release record only after the final artifact exists.",
                "Keep stable full rollout or required update disabled until rollback readiness is green.",
            ],
            "verifySteps": [
                "GET /api/v1/admin/updates/readiness",
                "GET /api/v1/updates/windows",
                "bluevpn_release_gate.ps1 -StrictPaymentGate",
            ],
            "secret": False,
            "blocks": ["client_updates"],
        },
        {
            "code": "server_catalog",
            "title": "Server catalog",
            "ownerAction": "Готовить будущие VPN endpoints только как внутренние draft-записи; публичная выдача включается позже после отдельного provisioning/health/canary gate.",
            "envKeys": ["GREENVPN_SERVER_CATALOG_VERSION", "GREENVPN_API_BASE_URLS", "GREENVPN_EMERGENCY_CATALOG_URL"],
            "ownerInputs": [
                {"name": "Provider and tariff", "secret": False, "example": "Timeweb Amsterdam 1 Gbit/s"},
                {"name": "Production endpoint host/IP", "secret": False, "example": "nl1.vpn.greenvpn.pro / public IPv4"},
                {"name": "WireGuard public endpoint port", "secret": False, "example": "51820"},
                {"name": "Planned bandwidth and monthly cost", "secret": False, "example": "1000 Mbps / monthly RUB cost"},
                {"name": "Client config profile decision", "secret": False, "example": "none until server-specific provisioning is ready"},
            ],
            "applySteps": [
                "Use newServerOnboardingPlan from /api/v1/admin/server-catalog/provisioning-readiness.",
                "Prepare managed endpoints through /api/v1/admin/server-catalog/draft-from-plan so draft/isPublic=false/clientConfigProfile=none is enforced.",
                "Do not publish them before DNS, health, external probe, server-specific config provisioning, canary and rollback gates are green.",
            ],
            "verifySteps": [
                "GET /api/v1/admin/server-catalog/publication-readiness",
                "GET /api/v1/admin/server-catalog/provisioning-readiness",
                "POST /api/v1/admin/server-catalog/draft-from-plan only for internal non-secret drafts.",
                "Check newServerOnboardingPlan.safeToCreateInternalDraft before adding a new VPS.",
                "GET /api/v1/catalog/servers must keep internal endpoints hidden until rollout.",
            ],
            "secret": False,
            "blocks": ["auto_server_selection", "fallback"],
        },
        {
            "code": "monitoring",
            "title": "Monitoring probes",
            "ownerAction": "Поставить controlled probe-agent на отдельный VPS и выдать ему admin token через /etc/greenvpn-monitoring/admin_token.",
            "envKeys": ["GREENVPN_SERVICE_CHECK_TIMEOUT"],
            "ownerInputs": [
                {"name": "Monitoring VPS host/IP", "secret": False},
                {"name": "SSH user/access method", "secret": True},
                {"name": "Probe id", "secret": False, "example": "probe-eu-1"},
                {"name": "Probe region", "secret": False, "example": "eu"},
            ],
            "applySteps": [
                "Install scripts/monitoring/service_probe.py on a separate VPS via install_probe_systemd.sh.",
                "Store admin token only on the probe host in /etc/greenvpn-monitoring/admin_token with mode 600.",
            ],
            "verifySteps": [
                "GET /api/v1/admin/monitoring/readiness",
                "GET /api/v1/admin/monitoring/service-observations",
                "Confirm required targets are fresh and covered by the external probe.",
            ],
            "secret": True,
            "blocks": ["service_availability_alerts", "server_health_score"],
        },
        {
            "code": "admin_alerts",
            "title": "Telegram алерты для админов",
            "ownerAction": "Создать Telegram bot, добавить его в support/admin чат и задать bot token/chat id в backend env.",
            "envKeys": [
                "GREENVPN_ADMIN_ALERTS_ENABLED",
                "GREENVPN_ADMIN_ALERT_MIN_SEVERITY",
                "GREENVPN_TELEGRAM_ALERT_BOT_TOKEN",
                "GREENVPN_TELEGRAM_ALERT_CHAT_ID",
            ],
            "ownerInputs": [
                {"name": "Telegram bot token", "envKey": "GREENVPN_TELEGRAM_ALERT_BOT_TOKEN", "secret": True},
                {"name": "Telegram chat id", "envKey": "GREENVPN_TELEGRAM_ALERT_CHAT_ID", "secret": True},
                {"name": "Minimum alert severity", "envKey": "GREENVPN_ADMIN_ALERT_MIN_SEVERITY", "secret": False, "example": "high"},
            ],
            "applySteps": [
                "Run configure_backend_env_wsl.ps1 and answer the Telegram alert prompts.",
                "Keep the bot token only in backend server env.",
            ],
            "verifySteps": [
                "GET /api/v1/admin/alerts/readiness",
                "POST /api/v1/admin/alerts/test from the admin app.",
                "Review /api/v1/admin/alerts/events for sent/failed/skipped history.",
            ],
            "secret": True,
            "blocks": ["incident_notifications"],
        },
    ]


def normalize_owner_action_status(value: Optional[str], fallback: str = "todo") -> str:
    normalized = clean_limited_text(value, 80).strip().lower()
    if not normalized:
        normalized = fallback
    if normalized not in OWNER_ACTION_STATUSES:
        raise HTTPException(status_code=400, detail="Invalid owner action status.")
    return normalized


def owner_action_workflow_options() -> dict:
    return {
        "statuses": [
            {"code": code, "title": OWNER_ACTION_STATUS_TITLES.get(code, code)}
            for code in OWNER_ACTION_STATUSES
        ],
        "statusTitles": OWNER_ACTION_STATUS_TITLES,
        "policy": {
            "noteRequiredStatuses": sorted(OWNER_ACTION_NOTE_REQUIRED_STATUSES),
            "noteRequiredWhenDoneBeforeReady": True,
            "noteMaxLength": 3000,
            "secretPolicy": "Owner notes must describe status and next step only; never paste secrets, admin tokens, passwords or provider keys.",
            "serverEnforced": True,
            "blockedNotePatternCodes": [
                code for code, _pattern in OWNER_ACTION_NOTE_SECRET_PATTERNS
            ],
        },
    }


OWNER_ACTION_NOTE_SECRET_PATTERNS = [
    (
        "private_key_block",
        re.compile(r"(?i)-----BEGIN [A-Z ]*PRIVATE KEY-----"),
    ),
    (
        "wireguard_private_key_assignment",
        re.compile(r"(?is)\[interface\].{0,800}\bprivate\s*key\b\s*="),
    ),
    (
        "key_assignment",
        re.compile(r"(?i)\b(private\s*key|preshared\s*key|wireguard\s*private\s*key)\b\s*[:=]"),
    ),
    (
        "auth_header",
        re.compile(r"(?i)\bbearer\s+[A-Za-z0-9._~+/=-]{10,}"),
    ),
    (
        "sensitive_assignment",
        re.compile(
            r"(?i)\b(?:authorization|x-admin-token|password|secret|token|api[_-]?key|api[_-]?id|chat[_-]?id)\b\s*[:=]\s*\S+"
        ),
    ),
    (
        "sensitive_env_assignment",
        re.compile(
            r"\b[A-Z0-9_]*(?:SECRET|TOKEN|PASSWORD|PRIVATE_KEY|PRESHARED_KEY|BOT_TOKEN|API_KEY|API_ID|CHAT_ID)[A-Z0-9_]*\s*[:=]\s*\S+"
        ),
    ),
]


def owner_action_note_secret_findings(note: str) -> list[str]:
    clean = clean_limited_text(note, 3000)
    if not clean:
        return []
    return [code for code, pattern in OWNER_ACTION_NOTE_SECRET_PATTERNS if pattern.search(clean)]


def owner_action_status_payload(row) -> dict:
    status = normalize_owner_action_status(row["status"])
    return {
        "id": int(row["id"]),
        "actionCode": row["action_code"],
        "status": status,
        "statusTitle": OWNER_ACTION_STATUS_TITLES.get(status, status),
        "note": row["note"],
        "updatedBy": row["updated_by"],
        "createdAt": row["created_at"],
        "updatedAt": row["updated_at"],
    }


def list_owner_action_statuses() -> dict[str, dict]:
    with db() as conn:
        rows = conn.execute(
            """
            SELECT *
            FROM admin_owner_action_statuses
            ORDER BY updated_at DESC, id DESC
            """
        ).fetchall()
    return {row["action_code"]: owner_action_status_payload(row) for row in rows}


def upsert_owner_action_status(
    action_code: str,
    payload: AdminOwnerActionStatusIn,
    actor: Optional[str] = None,
) -> dict:
    code = clean_limited_text(action_code, 80).strip().lower()
    known_codes = {item["code"] for item in external_action_specs()}
    if code not in known_codes:
        raise HTTPException(status_code=404, detail="External owner action not found.")
    status = normalize_owner_action_status(payload.status)
    note = clean_limited_text(payload.note, 3000).strip()
    secret_findings = owner_action_note_secret_findings(note)
    if secret_findings:
        raise HTTPException(
            status_code=400,
            detail=(
                "Owner note appears to contain secret material "
                f"({', '.join(secret_findings[:5])}). Remove secret values and describe status only."
            ),
        )
    readiness = build_product_readiness()
    check = {item["code"]: item for item in readiness.get("checks", [])}.get(code, {})
    backend_ready = bool(check.get("ok"))
    note_required = status in OWNER_ACTION_NOTE_REQUIRED_STATUSES or (
        status == "done" and not backend_ready
    )
    if note_required and not note:
        raise HTTPException(
            status_code=400,
            detail="Owner note is required for this external action status. Do not include secrets.",
        )
    updated_by = clean_limited_text(actor, 160).strip()
    now = utc_now_iso()
    with db() as conn:
        row = conn.execute(
            "SELECT id FROM admin_owner_action_statuses WHERE action_code = ?",
            (code,),
        ).fetchone()
        if row is None:
            cursor = conn.execute(
                """
                INSERT INTO admin_owner_action_statuses(
                    action_code, status, note, updated_by, created_at, updated_at
                )
                VALUES (?, ?, ?, ?, ?, ?)
                """,
                (code, status, note or None, updated_by or None, now, now),
            )
            row_id = int(cursor.lastrowid)
        else:
            row_id = int(row["id"])
            conn.execute(
                """
                UPDATE admin_owner_action_statuses
                SET status = ?, note = ?, updated_by = ?, updated_at = ?
                WHERE id = ?
                """,
                (status, note or None, updated_by or None, now, row_id),
            )
        conn.commit()
        saved = conn.execute(
            "SELECT * FROM admin_owner_action_statuses WHERE id = ?",
            (row_id,),
        ).fetchone()
    return owner_action_status_payload(saved)


def build_external_actions_checklist() -> dict:
    readiness = build_product_readiness()
    check_by_code = {item["code"]: item for item in readiness.get("checks", [])}
    saved_statuses = list_owner_action_statuses()
    actions = []
    for spec in external_action_specs():
        check = check_by_code.get(spec["code"], {})
        ready = bool(check.get("ok"))
        saved = saved_statuses.get(spec["code"])
        owner_status = saved.get("status") if saved else ("done" if ready else "todo")
        actions.append(
            {
                **spec,
                "ready": ready,
                "status": "ready" if ready else "needs_owner_action",
                "message": check.get("message") or "",
                "ownerStatus": owner_status,
                "ownerStatusTitle": OWNER_ACTION_STATUS_TITLES.get(owner_status, owner_status),
                "ownerNote": saved.get("note") if saved else None,
                "ownerUpdatedBy": saved.get("updatedBy") if saved else None,
                "ownerUpdatedAt": saved.get("updatedAt") if saved else None,
                "ownerStatusRecorded": bool(saved),
            }
        )

    pending = [item for item in actions if not item["ready"]]
    owner_done = [
        item
        for item in actions
        if item["ownerStatus"] in {"done", "not_needed"} or item["ready"]
    ]
    owner_blocked = [item for item in actions if item["ownerStatus"] == "blocked"]
    done_but_backend_not_ready = [
        item
        for item in actions
        if item["ownerStatus"] in {"done", "not_needed"} and not item["ready"]
    ]
    ready_to_apply = [item for item in actions if item["ownerStatus"] == "ready_to_apply"]
    waiting = [
        item
        for item in actions
        if item["ownerStatus"] in {"waiting_owner", "waiting_provider"}
    ]
    missing_owner_notes = [
        item
        for item in actions
        if (
            item["ownerStatus"] in OWNER_ACTION_NOTE_REQUIRED_STATUSES
            or (item["ownerStatus"] == "done" and not item["ready"])
        )
        and not clean_limited_text(item.get("ownerNote"), 3000).strip()
    ]
    blocking_summary = {
        "pendingCodes": [item["code"] for item in pending],
        "blockedCodes": [item["code"] for item in owner_blocked],
        "readyToApplyCodes": [item["code"] for item in ready_to_apply],
        "waitingCodes": [item["code"] for item in waiting],
        "doneButBackendNotReadyCodes": [item["code"] for item in done_but_backend_not_ready],
        "missingOwnerNoteCodes": [item["code"] for item in missing_owner_notes],
        "secretInputCodes": [item["code"] for item in actions if item.get("secret")],
        "safeToProceed": bool(
            len(pending) == 0
            and not owner_blocked
            and not done_but_backend_not_ready
            and not missing_owner_notes
        ),
    }
    return {
        "ok": True,
        "version": APP_VERSION,
        "generatedAt": utc_now_iso(),
        "productionReady": len(pending) == 0,
        "setupBundle": external_owner_setup_bundle(),
        "workflow": owner_action_workflow_options(),
        "summary": {
            "ready": len(actions) - len(pending),
            "pending": len(pending),
            "ownerDone": len(owner_done),
            "ownerBlocked": len(owner_blocked),
            "readyToApply": len(ready_to_apply),
            "doneButBackendNotReady": len(done_but_backend_not_ready),
            "missingOwnerNotes": len(missing_owner_notes),
            "message": (
                "Все внешние действия закрыты."
                if not pending
                else "Есть внешние действия владельца, код уже подготовлен к подключению."
            ),
        },
        "ownerActionPolicy": owner_action_workflow_options().get("policy"),
        "blockingSummary": blocking_summary,
        "actions": actions,
        "nextOwnerBatch": pending[:5],
        "secretPolicy": "Секреты вводятся только в серверный env/закрытые файлы на машине; в репозиторий их не записывать.",
    }


def support_report_sla_status(report: dict, now: Optional[datetime] = None) -> str:
    status = clean_limited_text(report.get("status"), 40).strip().lower()
    if status in {"resolved", "closed"}:
        return "closed"
    due_at = parse_dt(report.get("slaDueAt"))
    if due_at is None:
        return "missing"
    if due_at.tzinfo is None:
        due_at = due_at.replace(tzinfo=timezone.utc)
    safe_now = now or utc_now()
    if due_at < safe_now:
        return "overdue"
    if due_at <= safe_now + timedelta(hours=6):
        return "due_soon"
    return "ok"


def support_report_payload(row, include_report: bool = False) -> dict:
    out = {
        "id": int(row["id"]),
        "userId": int(row["user_id"]),
        "email": row["email"],
        "deviceUid": row["device_uid"],
        "appVersion": row["app_version"],
        "summary": row["summary"],
        "status": row["status"],
        "priority": row["priority"] if "priority" in row.keys() else "normal",
        "category": row["category"] if "category" in row.keys() else "general",
        "triageReason": row["triage_reason"] if "triage_reason" in row.keys() else None,
        "slaDueAt": row["sla_due_at"] if "sla_due_at" in row.keys() else None,
        "firstResponseAt": row["first_response_at"] if "first_response_at" in row.keys() else None,
        "reviewedAt": row["reviewed_at"] if "reviewed_at" in row.keys() else None,
        "reviewedBy": row["reviewed_by"] if "reviewed_by" in row.keys() else None,
        "assignedTo": row["assigned_to"] if "assigned_to" in row.keys() else None,
        "adminNote": row["admin_note"] if "admin_note" in row.keys() else None,
        "requestIp": row["request_ip"],
        "userAgent": row["user_agent"],
        "createdAt": row["created_at"],
        "updatedAt": row["updated_at"] if "updated_at" in row.keys() else None,
        "handledAt": row["handled_at"] if "handled_at" in row.keys() else None,
    }
    out["reviewPending"] = not out["reviewedAt"] and out["status"] in {"new", "triage"}
    out["slaStatus"] = support_report_sla_status(out)
    out["firstResponseMissing"] = bool(
        not out["firstResponseAt"]
        and out["status"] not in {"resolved", "closed"}
    )
    if include_report:
        out["report"] = row["report_code"]
    else:
        report_code = str(row["report_code"] or "")
        out["reportPrefix"] = report_code[:18]
        out["reportSize"] = len(report_code)
    return out


def list_support_reports(
    status: Optional[str] = None,
    user_id: Optional[int] = None,
    email: Optional[str] = None,
    device_uid: Optional[str] = None,
    category: Optional[str] = None,
    priority: Optional[str] = None,
    assigned_to: Optional[str] = None,
    limit: int = 100,
    offset: int = 0,
) -> list[dict]:
    safe_limit = max(1, min(300, int(limit or 100)))
    safe_offset = max(0, int(offset or 0))
    query = "SELECT * FROM support_reports"
    filters = []
    args: list = []
    if status and status != "all":
        filters.append("status = ?")
        args.append(status)
    if user_id is not None:
        filters.append("user_id = ?")
        args.append(int(user_id))
    if email:
        filters.append("LOWER(email) = LOWER(?)")
        args.append(clean_limited_text(email, 254))
    if device_uid:
        filters.append("device_uid = ?")
        args.append(clean_limited_text(device_uid, 128))
    if category and category != "all":
        filters.append("category = ?")
        args.append(normalize_support_category(category))
    if priority and priority != "all":
        filters.append("priority = ?")
        args.append(normalize_support_priority(priority))
    if assigned_to:
        filters.append("LOWER(assigned_to) = LOWER(?)")
        args.append(clean_limited_text(assigned_to, 120))
    if filters:
        query += " WHERE " + " AND ".join(filters)
    query += " ORDER BY id DESC LIMIT ? OFFSET ?"
    args.extend([safe_limit, safe_offset])
    with db() as conn:
        rows = conn.execute(query, tuple(args)).fetchall()
    return [support_report_payload(row) for row in rows]


def build_support_sla_dashboard(limit: int = 25) -> dict:
    safe_limit = max(1, min(100, int(limit or 25)))
    with db() as conn:
        rows = conn.execute(
            """
            SELECT *
            FROM support_reports
            WHERE status NOT IN ('resolved', 'closed')
            ORDER BY
                CASE WHEN sla_due_at IS NULL THEN 1 ELSE 0 END ASC,
                sla_due_at ASC,
                id DESC
            LIMIT ?
            """,
            (safe_limit,),
        ).fetchall()
    reports = [support_report_payload(row) for row in rows]
    counts = {
        "open": len(reports),
        "overdue": 0,
        "dueSoon": 0,
        "ok": 0,
        "missingSla": 0,
        "firstResponseMissing": 0,
        "reviewPending": 0,
    }
    for report in reports:
        sla_status = report.get("slaStatus")
        if sla_status == "overdue":
            counts["overdue"] += 1
        elif sla_status == "due_soon":
            counts["dueSoon"] += 1
        elif sla_status == "missing":
            counts["missingSla"] += 1
        elif sla_status == "ok":
            counts["ok"] += 1
        if report.get("firstResponseMissing"):
            counts["firstResponseMissing"] += 1
        if report.get("reviewPending"):
            counts["reviewPending"] += 1
    attention = [
        report
        for report in reports
        if report.get("slaStatus") in {"overdue", "due_soon", "missing"}
        or report.get("firstResponseMissing")
        or report.get("reviewPending")
    ]
    return {
        "ok": True,
        "version": APP_VERSION,
        "generatedAt": utc_now_iso(),
        "attentionRequired": bool(
            counts["overdue"]
            or counts["dueSoon"]
            or counts["missingSla"]
            or counts["firstResponseMissing"]
            or counts["reviewPending"]
        ),
        "summary": counts,
        "queue": reports,
        "attentionQueue": attention[:safe_limit],
        "policy": {
            "dueSoonHours": 6,
            "firstResponseRequiredBeforeStatuses": ["resolved", "closed"],
            "closedStatuses": ["resolved", "closed"],
        },
    }


def backfill_support_report_workflow_fields() -> dict:
    now = utc_now_iso()
    updated = 0
    with db() as conn:
        rows = conn.execute(
            """
            SELECT *
            FROM support_reports
            WHERE
                priority IS NULL
                OR priority = ''
                OR category IS NULL
                OR category = ''
                OR sla_due_at IS NULL
                OR sla_due_at = ''
            """
        ).fetchall()
        for row in rows:
            workflow = infer_support_report_workflow(row["summary"] or "", row["report_code"] or "")
            priority = row["priority"] if "priority" in row.keys() and row["priority"] else workflow["priority"]
            category = row["category"] if "category" in row.keys() and row["category"] else workflow["category"]
            triage_reason = (
                row["triage_reason"]
                if "triage_reason" in row.keys() and row["triage_reason"]
                else workflow.get("triageReason")
            )
            sla_due_at = (
                row["sla_due_at"]
                if "sla_due_at" in row.keys() and row["sla_due_at"]
                else support_sla_due_at(priority, row["created_at"])
            )
            conn.execute(
                """
                UPDATE support_reports
                SET priority = ?, category = ?, triage_reason = COALESCE(triage_reason, ?),
                    sla_due_at = ?, updated_at = COALESCE(updated_at, ?)
                WHERE id = ?
                """,
                (
                    normalize_support_priority(priority),
                    normalize_support_category(category),
                    triage_reason,
                    sla_due_at,
                    now,
                    int(row["id"]),
                ),
            )
            updated += 1
        conn.commit()
    return {
        "updated": updated,
        "generatedAt": now,
    }


def get_support_report(report_id: int) -> dict:
    with db() as conn:
        row = conn.execute(
            "SELECT * FROM support_reports WHERE id = ?",
            (report_id,),
        ).fetchone()
    if row is None:
        raise HTTPException(status_code=404, detail="Support report not found.")
    return support_report_payload(row, include_report=True)


def update_support_report_status(
    report_id: int,
    payload: AdminSupportReportStatusIn,
    request: Optional[Request] = None,
) -> dict:
    existing = get_support_report(report_id)
    status = clean_limited_text(payload.status, 40).strip().lower()
    if status not in SUPPORT_STATUSES:
        raise HTTPException(status_code=400, detail="Invalid support report status.")
    note = (
        existing.get("adminNote") or ""
        if payload.note is None
        else clean_limited_text(payload.note, 4000)
    )
    assigned_to = (
        existing.get("assignedTo") or ""
        if payload.assignedTo is None
        else clean_limited_text(payload.assignedTo, 120)
    )
    priority = normalize_support_priority(
        payload.priority,
        existing.get("priority") or "normal",
    )
    category = normalize_support_category(
        payload.category,
        existing.get("category") or "general",
    )
    sla_due_at = clean_limited_text(payload.slaDueAt, 80).strip()
    if not sla_due_at:
        sla_due_at = existing.get("slaDueAt") or support_sla_due_at(
            priority,
            existing.get("createdAt"),
        )
    actor = admin_actor_from_context(request)
    first_response_at = utc_now_iso() if status not in {"new", "triage"} else None
    reviewed_at = utc_now_iso() if status not in {"new", "triage"} else None
    reviewed_by = actor if reviewed_at else None
    handled_at = utc_now_iso() if status in {"resolved", "closed"} else None
    with db() as conn:
        conn.execute(
            """
            UPDATE support_reports
            SET status = ?, admin_note = ?, assigned_to = ?,
                priority = ?, category = ?, sla_due_at = ?,
                updated_at = ?, handled_at = COALESCE(?, handled_at),
                first_response_at = COALESCE(first_response_at, ?),
                reviewed_at = COALESCE(reviewed_at, ?),
                reviewed_by = COALESCE(reviewed_by, ?)
            WHERE id = ?
            """,
            (
                status,
                note or None,
                assigned_to or None,
                priority,
                category,
                sla_due_at,
                utc_now_iso(),
                handled_at,
                first_response_at,
                reviewed_at,
                reviewed_by,
                report_id,
            ),
        )
        conn.commit()
    return get_support_report(report_id)


def review_support_report(
    report_id: int,
    payload: Optional[AdminSupportReportReviewIn] = None,
    request: Optional[Request] = None,
) -> dict:
    existing = get_support_report(report_id)
    if existing.get("status") in {"resolved", "closed"}:
        raise HTTPException(status_code=409, detail="Support report is already closed.")
    actor = admin_actor_from_context(request)
    assigned_to = clean_limited_text(
        payload.assignedTo if payload is not None else None,
        120,
    ).strip()
    if not assigned_to:
        assigned_to = clean_limited_text(existing.get("assignedTo"), 120).strip() or actor
    note = clean_limited_text(payload.note if payload is not None else None, 4000)
    if not note:
        note = existing.get("adminNote") or ""
    status = existing.get("status") or "new"
    if status in {"new", "triage"}:
        status = "in_progress"
    now = utc_now_iso()
    with db() as conn:
        conn.execute(
            """
            UPDATE support_reports
            SET status = ?, admin_note = ?, assigned_to = ?,
                updated_at = ?, first_response_at = COALESCE(first_response_at, ?),
                reviewed_at = COALESCE(reviewed_at, ?),
                reviewed_by = COALESCE(reviewed_by, ?)
            WHERE id = ?
            """,
            (
                status,
                note or None,
                assigned_to or None,
                now,
                now,
                now,
                actor,
                report_id,
            ),
        )
        conn.commit()
    return get_support_report(report_id)


def support_report_comment_payload(row) -> dict:
    return {
        "id": int(row["id"]),
        "reportId": int(row["report_id"]),
        "author": row["author"],
        "body": row["body"],
        "createdAt": row["created_at"],
        "requestIp": row["request_ip"],
        "userAgent": row["user_agent"],
    }


def list_support_report_comments(report_id: int) -> list[dict]:
    get_support_report(report_id)
    with db() as conn:
        rows = conn.execute(
            """
            SELECT *
            FROM support_report_comments
            WHERE report_id = ?
            ORDER BY id ASC
            """,
            (report_id,),
        ).fetchall()
    return [support_report_comment_payload(row) for row in rows]


def add_support_report_comment(
    report_id: int,
    payload: AdminSupportReportCommentIn,
    request: Optional[Request] = None,
) -> dict:
    get_support_report(report_id)
    body = clean_limited_text(payload.body, 4000).strip()
    if not body:
        raise HTTPException(status_code=400, detail="Comment body is required.")
    author = clean_limited_text(payload.author, 120).strip() or "support"
    request_ip = ""
    user_agent = ""
    if request is not None:
        request_ip, user_agent = request_ip_and_agent(request)
    with db() as conn:
        cursor = conn.execute(
            """
            INSERT INTO support_report_comments(
                report_id, author, body, created_at, request_ip, user_agent
            )
            VALUES (?, ?, ?, ?, ?, ?)
            """,
            (report_id, author, body, utc_now_iso(), request_ip, user_agent),
        )
        conn.execute(
            """
            UPDATE support_reports
            SET updated_at = ?,
                first_response_at = COALESCE(first_response_at, ?)
            WHERE id = ?
            """,
            (utc_now_iso(), utc_now_iso(), report_id),
        )
        conn.commit()
        row = conn.execute(
            "SELECT * FROM support_report_comments WHERE id = ?",
            (int(cursor.lastrowid),),
        ).fetchone()
    return support_report_comment_payload(row)


def normalize_support_action(action: Optional[str]) -> str:
    normalized = clean_limited_text(action, 80).strip().lower()
    if normalized not in SUPPORT_ACTION_TYPES:
        raise HTTPException(status_code=400, detail="Unknown support action.")
    return normalized


def support_action_workflow_options() -> dict:
    return {
        "actions": [
            {
                "code": "reset_user_sessions",
                "title": "Сбросить сессии пользователя",
                "requiresDevice": False,
                "requiresReason": True,
                "danger": True,
                "confirmationText": "Сбросить все сессии пользователя? Он войдёт заново.",
                "description": "Удаляет пользовательские session tokens. Пользователь войдёт заново.",
            },
            {
                "code": "request_config_refresh",
                "title": "Запросить обновление конфига",
                "requiresDevice": False,
                "requiresReason": False,
                "danger": False,
                "description": "Помечает устройство или все устройства пользователя для проверки/перевыдачи конфига саппортом.",
            },
            {
                "code": "clear_config_refresh",
                "title": "Снять запрос обновления конфига",
                "requiresDevice": False,
                "requiresReason": False,
                "danger": False,
                "description": "Очищает саппортную пометку обновления конфига.",
            },
            {
                "code": "disable_device",
                "title": "Отключить устройство",
                "requiresDevice": True,
                "requiresReason": True,
                "danger": True,
                "confirmationText": "Отключить выбранное устройство пользователя?",
                "description": "Отключает конкретное устройство пользователя без удаления аккаунта.",
            },
            {
                "code": "enable_device",
                "title": "Включить устройство",
                "requiresDevice": True,
                "requiresReason": False,
                "danger": False,
                "description": "Возвращает конкретное устройство в активное состояние.",
            },
            {
                "code": "add_support_note",
                "title": "Добавить внутреннюю заметку",
                "requiresDevice": False,
                "requiresReason": True,
                "danger": False,
                "description": "Фиксирует заметку в истории действий без изменения аккаунта.",
            },
            {
                "code": "grant_support_trial_3d",
                "title": "Выдать support trial на 3 дня",
                "requiresDevice": False,
                "requiresReason": True,
                "danger": False,
                "confirmationText": "Выдать пользователю временный support trial на 3 дня?",
                "description": "Продлевает trial/support_trial на 3 дня, но не перезаписывает активную платную подписку.",
            },
        ],
        "statuses": list(SUPPORT_ACTION_STATUSES),
        "secretPolicy": "Support actions never expose passwords, tokens or WireGuard private keys.",
    }


def support_action_payload(row: sqlite3.Row) -> dict:
    try:
        result = json.loads(row["result_json"] or "{}")
    except Exception:
        result = {}
    return {
        "id": int(row["id"]),
        "userId": int(row["user_id"]),
        "deviceUid": row["device_uid"],
        "action": row["action"],
        "status": row["status"],
        "reason": row["reason"],
        "result": result if isinstance(result, dict) else {"value": result},
        "requestedBy": row["requested_by"],
        "requestIp": row["request_ip"],
        "userAgent": row["user_agent"],
        "createdAt": row["created_at"],
    }


def list_admin_support_actions(
    user_id: Optional[int] = None,
    action: Optional[str] = None,
    status: Optional[str] = None,
    limit: int = 100,
    offset: int = 0,
) -> list[dict]:
    safe_limit = max(1, min(300, int(limit or 100)))
    safe_offset = max(0, int(offset or 0))
    query = "SELECT * FROM admin_support_actions"
    filters = []
    args: list = []
    if user_id is not None:
        filters.append("user_id = ?")
        args.append(int(user_id))
    if action and action != "all":
        filters.append("action = ?")
        args.append(normalize_support_action(action))
    if status and status != "all":
        normalized_status = clean_limited_text(status, 40).strip().lower()
        if normalized_status not in SUPPORT_ACTION_STATUSES:
            raise HTTPException(status_code=400, detail="Unknown support action status.")
        filters.append("status = ?")
        args.append(normalized_status)
    if filters:
        query += " WHERE " + " AND ".join(filters)
    query += " ORDER BY id DESC LIMIT ? OFFSET ?"
    args.extend([safe_limit, safe_offset])
    with db() as conn:
        rows = conn.execute(query, tuple(args)).fetchall()
    return [support_action_payload(row) for row in rows]


def admin_actor_from_context(request: Optional[Request]) -> str:
    if request is None:
        return "support"
    context = getattr(request.state, "admin_context", None)
    if isinstance(context, dict) and context.get("actor"):
        return clean_limited_text(str(context.get("actor")), 120) or "support"
    return admin_actor_from_request(request, "support")


def grant_support_trial_subscription(
    conn: sqlite3.Connection,
    user_id: int,
    *,
    days: int = 3,
    actor: str = "support",
    reason: str = "",
) -> dict:
    safe_days = max(1, min(int(days or 3), 14))
    now = utc_now()
    now_iso = now.isoformat()
    current = conn.execute(
        """
        SELECT *
        FROM subscriptions
        WHERE user_id = ?
        ORDER BY id DESC
        LIMIT 1
        """,
        (int(user_id),),
    ).fetchone()
    if current is not None:
        current_public = subscription_status(current)
        current_plan = str(current["plan_code"] or "")
        if current_public["isActive"] and current_plan not in {DEFAULT_PLAN_CODE, "support_trial"}:
            return {
                "changed": False,
                "paidSubscriptionPreserved": True,
                "planCode": current_plan,
                "subscription": current_public,
            }
        current_expires_at = parse_dt(current["expires_at"])
        base_dt = (
            current_expires_at
            if current_expires_at is not None and current_expires_at > now
            else now
        )
        expires_at = (base_dt + timedelta(days=safe_days)).isoformat()
        max_devices = max(DEFAULT_MAX_DEVICES, int(current["max_devices"] or 0))
        selection = {
            "source": "support_action",
            "daysGranted": safe_days,
            "requestedBy": clean_limited_text(actor, 120),
            "reason": clean_limited_text(reason, 300),
        }
        conn.execute(
            """
            UPDATE subscriptions
            SET plan_code = ?, plan_name = ?, max_devices = ?, is_active = ?,
                expires_at = ?, updated_at = ?, monthly_price_rub = ?,
                selection_json = ?, auto_renew = ?, provider_payment_method_id = NULL
            WHERE id = ?
            """,
            (
                "support_trial",
                "Support trial",
                max_devices,
                1,
                expires_at,
                now_iso,
                0,
                json.dumps(selection, ensure_ascii=False, sort_keys=True),
                0,
                int(current["id"]),
            ),
        )
        previous_plan = current_plan
    else:
        expires_at = (now + timedelta(days=safe_days)).isoformat()
        selection = {
            "source": "support_action",
            "daysGranted": safe_days,
            "requestedBy": clean_limited_text(actor, 120),
            "reason": clean_limited_text(reason, 300),
        }
        conn.execute(
            """
            INSERT INTO subscriptions(
                user_id, plan_code, plan_name, max_devices, is_active,
                expires_at, created_at, updated_at, monthly_price_rub,
                selection_json, auto_renew, provider_payment_method_id
            )
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            (
                int(user_id),
                "support_trial",
                "Support trial",
                DEFAULT_MAX_DEVICES,
                1,
                expires_at,
                now_iso,
                now_iso,
                0,
                json.dumps(selection, ensure_ascii=False, sort_keys=True),
                0,
                None,
            ),
        )
        previous_plan = ""

    saved = conn.execute(
        """
        SELECT *
        FROM subscriptions
        WHERE user_id = ?
        ORDER BY id DESC
        LIMIT 1
        """,
        (int(user_id),),
    ).fetchone()
    return {
        "changed": True,
        "daysGranted": safe_days,
        "expiresAt": expires_at,
        "previousPlanCode": previous_plan,
        "subscription": subscription_status(saved),
    }


def perform_admin_support_action(
    user_id: int,
    payload: AdminSupportActionIn,
    request: Optional[Request] = None,
) -> dict:
    action = normalize_support_action(payload.action)
    reason = clean_limited_text(payload.reason or payload.note, 2000).strip()
    device_uid = clean_limited_text(payload.deviceUid, 128).strip() or None
    actor = admin_actor_from_context(request)
    request_ip = ""
    user_agent = ""
    if request is not None:
        request_ip, user_agent = request_ip_and_agent(request)

    now = utc_now_iso()
    status = "done"
    result: dict[str, Any] = {}

    with db() as conn:
        user_row = conn.execute(
            "SELECT id, email, phone FROM users WHERE id = ?",
            (int(user_id),),
        ).fetchone()
        if user_row is None:
            raise HTTPException(status_code=404, detail="User not found.")

        device_row = None
        if device_uid:
            device_row = conn.execute(
                """
                SELECT *
                FROM devices
                WHERE user_id = ? AND device_uid = ?
                """,
                (int(user_id), device_uid),
            ).fetchone()
            if device_row is None:
                raise HTTPException(status_code=404, detail="Device not found for user.")

        if action in {"disable_device", "enable_device"} and not device_uid:
            raise HTTPException(status_code=400, detail="deviceUid is required for this action.")

        if action in SUPPORT_ACTIONS_REQUIRING_REASON and len(reason) < 8:
            raise HTTPException(
                status_code=400,
                detail="reason is required for this support action.",
            )

        if action == "reset_user_sessions":
            cursor = conn.execute("DELETE FROM tokens WHERE user_id = ?", (int(user_id),))
            result = {
                "sessionsRevoked": max(0, int(cursor.rowcount or 0)),
                "userEmail": user_row["email"],
            }
            if result["sessionsRevoked"] == 0:
                status = "noop"
        elif action == "request_config_refresh":
            if device_uid:
                cursor = conn.execute(
                    """
                    UPDATE devices
                    SET support_config_refresh_requested_at = ?,
                        support_config_refresh_reason = ?,
                        support_config_refresh_requested_by = ?,
                        updated_at = ?
                    WHERE user_id = ? AND device_uid = ?
                    """,
                    (
                        now,
                        reason or "support_requested_config_refresh",
                        actor,
                        now,
                        int(user_id),
                        device_uid,
                    ),
                )
            else:
                cursor = conn.execute(
                    """
                    UPDATE devices
                    SET support_config_refresh_requested_at = ?,
                        support_config_refresh_reason = ?,
                        support_config_refresh_requested_by = ?,
                        updated_at = ?
                    WHERE user_id = ?
                    """,
                    (
                        now,
                        reason or "support_requested_config_refresh",
                        actor,
                        now,
                        int(user_id),
                    ),
                )
            result = {"devicesMarked": max(0, int(cursor.rowcount or 0))}
            if result["devicesMarked"] == 0:
                status = "noop"
        elif action == "clear_config_refresh":
            if device_uid:
                cursor = conn.execute(
                    """
                    UPDATE devices
                    SET support_config_refresh_requested_at = NULL,
                        support_config_refresh_reason = NULL,
                        support_config_refresh_requested_by = NULL,
                        updated_at = ?
                    WHERE user_id = ? AND device_uid = ?
                    """,
                    (now, int(user_id), device_uid),
                )
            else:
                cursor = conn.execute(
                    """
                    UPDATE devices
                    SET support_config_refresh_requested_at = NULL,
                        support_config_refresh_reason = NULL,
                        support_config_refresh_requested_by = NULL,
                        updated_at = ?
                    WHERE user_id = ?
                    """,
                    (now, int(user_id)),
                )
            result = {"devicesCleared": max(0, int(cursor.rowcount or 0))}
            if result["devicesCleared"] == 0:
                status = "noop"
        elif action == "disable_device":
            if device_row and not bool(device_row["is_enabled"]):
                status = "noop"
                result = {"deviceUid": device_uid, "alreadyDisabled": True}
            else:
                conn.execute(
                    """
                    UPDATE devices
                    SET is_enabled = 0,
                        disabled_reason = ?,
                        disabled_at = ?,
                        updated_at = ?
                    WHERE user_id = ? AND device_uid = ?
                    """,
                    (
                        reason or "disabled_by_support_action",
                        now,
                        now,
                        int(user_id),
                        device_uid,
                    ),
                )
                result = {"deviceUid": device_uid, "enabled": False}
        elif action == "enable_device":
            if device_row and bool(device_row["is_enabled"]):
                status = "noop"
                result = {"deviceUid": device_uid, "alreadyEnabled": True}
            else:
                conn.execute(
                    """
                    UPDATE devices
                    SET is_enabled = 1,
                        disabled_reason = NULL,
                        disabled_at = NULL,
                        updated_at = ?
                    WHERE user_id = ? AND device_uid = ?
                    """,
                    (now, int(user_id), device_uid),
                )
                result = {"deviceUid": device_uid, "enabled": True}
        elif action == "add_support_note":
            if not reason:
                raise HTTPException(status_code=400, detail="note or reason is required.")
            result = {"noteStored": True}
        elif action == "grant_support_trial_3d":
            trial_result = grant_support_trial_subscription(
                conn,
                int(user_id),
                days=3,
                actor=actor,
                reason=reason,
            )
            result = trial_result
            if not trial_result.get("changed"):
                status = "noop"

        cursor = conn.execute(
            """
            INSERT INTO admin_support_actions(
                user_id, device_uid, action, status, reason, result_json,
                requested_by, request_ip, user_agent, created_at
            )
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            (
                int(user_id),
                device_uid,
                action,
                status,
                reason or None,
                json.dumps(result, ensure_ascii=False, sort_keys=True),
                actor,
                request_ip,
                user_agent,
                now,
            ),
        )
        conn.commit()
        row = conn.execute(
            "SELECT * FROM admin_support_actions WHERE id = ?",
            (int(cursor.lastrowid),),
        ).fetchone()

    action_payload = support_action_payload(row)
    write_admin_audit(
        "support_action_performed",
        "user",
        str(user_id),
        {
            "action": action,
            "status": status,
            "deviceUid": device_uid,
            "supportActionId": action_payload["id"],
            "result": result,
        },
        request=request,
        actor=actor,
    )
    return action_payload


def audit_log_payload(row) -> dict:
    details = {}
    try:
        details = json.loads(row["details_json"] or "{}")
    except Exception:
        details = {}
    return {
        "id": int(row["id"]),
        "actor": row["actor"],
        "action": row["action"],
        "targetType": row["target_type"],
        "targetId": row["target_id"],
        "details": details,
        "requestIp": row["request_ip"],
        "userAgent": row["user_agent"],
        "createdAt": row["created_at"],
    }


def normalize_admin_role(role: Optional[str]) -> str:
    candidate = clean_limited_text(role, 40).strip().lower()
    if candidate not in ADMIN_ROLE_MATRIX:
        raise HTTPException(status_code=400, detail="Unknown admin role.")
    return candidate


def admin_role_payload(code: str, meta: dict) -> dict:
    return {
        "code": code,
        "title": meta["title"],
        "permissions": list(meta["permissions"]),
    }


def admin_actor_from_request(
    request: Optional[Request],
    fallback: str = "admin_token",
) -> str:
    if request is None:
        return fallback
    raw = request.headers.get("x-admin-actor", "")
    actor = clean_limited_text(raw, 120).strip()
    return actor or fallback


def write_admin_audit(
    action: str,
    target_type: Optional[str] = None,
    target_id: Optional[str] = None,
    details: Optional[dict] = None,
    request: Optional[Request] = None,
    actor: str = "admin_token",
) -> None:
    request_ip = ""
    user_agent = ""
    if request is not None:
        request_ip, user_agent = request_ip_and_agent(request)
        if actor == "admin_token":
            context = getattr(request.state, "admin_context", None)
            if isinstance(context, dict) and context.get("actor"):
                actor = str(context.get("actor"))
            else:
                actor = admin_actor_from_request(request, actor)
    try:
        details_json = json.dumps(details or {}, ensure_ascii=False)
    except Exception:
        details_json = "{}"
    with db() as conn:
        conn.execute(
            """
            INSERT INTO admin_audit_log(
                actor, action, target_type, target_id, details_json,
                request_ip, user_agent, created_at
            )
            VALUES (?, ?, ?, ?, ?, ?, ?, ?)
            """,
            (
                clean_limited_text(actor, 120) or "admin_token",
                clean_limited_text(action, 120),
                clean_limited_text(target_type, 80),
                clean_limited_text(target_id, 180),
                details_json,
                request_ip,
                user_agent,
                utc_now_iso(),
            ),
        )
        conn.commit()


def list_admin_audit(limit: int = 100, offset: int = 0) -> list[dict]:
    safe_limit = max(1, min(300, int(limit or 100)))
    safe_offset = max(0, int(offset or 0))
    with db() as conn:
        rows = conn.execute(
            """
            SELECT *
            FROM admin_audit_log
            ORDER BY id DESC
            LIMIT ? OFFSET ?
            """,
            (safe_limit, safe_offset),
        ).fetchall()
    return [audit_log_payload(row) for row in rows]


def normalize_incident_status(value: Optional[str], fallback: str = "open") -> str:
    candidate = clean_limited_text(value, 40).strip().lower()
    if candidate in INCIDENT_STATUSES:
        return candidate
    return fallback if fallback in INCIDENT_STATUSES else "open"


def normalize_incident_severity(value: Optional[str], fallback: str = "medium") -> str:
    candidate = clean_limited_text(value, 40).strip().lower()
    if candidate in INCIDENT_SEVERITIES:
        return candidate
    return fallback if fallback in INCIDENT_SEVERITIES else "medium"


def incident_severity_rank(severity: str) -> int:
    return int(INCIDENT_SEVERITIES.get(severity, INCIDENT_SEVERITIES["medium"])["rank"])


def incident_workflow_options() -> dict:
    return {
        "statuses": INCIDENT_STATUSES,
        "severities": [
            {
                "code": code,
                "title": meta["title"],
                "rank": meta["rank"],
            }
            for code, meta in INCIDENT_SEVERITIES.items()
        ],
    }


def admin_alert_min_severity() -> str:
    return normalize_incident_severity(ADMIN_ALERT_MIN_SEVERITY, "high")


def admin_alerts_configured() -> bool:
    return bool(ADMIN_ALERTS_ENABLED and TELEGRAM_ALERT_BOT_TOKEN and TELEGRAM_ALERT_CHAT_ID)


def admin_alert_readiness() -> dict:
    min_severity = admin_alert_min_severity()
    checks = [
        {
            "code": "alerts_enabled",
            "ok": bool(ADMIN_ALERTS_ENABLED),
            "message": "Set GREENVPN_ADMIN_ALERTS_ENABLED=1 for incident notifications.",
        },
        {
            "code": "telegram_bot_token",
            "ok": bool(TELEGRAM_ALERT_BOT_TOKEN),
            "message": "Set GREENVPN_TELEGRAM_ALERT_BOT_TOKEN on the backend host.",
        },
        {
            "code": "telegram_chat_id",
            "ok": bool(TELEGRAM_ALERT_CHAT_ID),
            "message": "Set GREENVPN_TELEGRAM_ALERT_CHAT_ID for the admin/support chat.",
        },
    ]
    production_ready = all(check["ok"] for check in checks)
    return {
        "ok": True,
        "provider": "telegram" if production_ready else "manual_mvp",
        "productionReady": production_ready,
        "minSeverity": min_severity,
        "checks": checks,
        "summary": {
            "green": sum(1 for check in checks if check["ok"]),
            "yellow": sum(1 for check in checks if not check["ok"]),
            "message": (
                "Admin alerts are ready."
                if production_ready
                else "Configure Telegram bot token and chat id for automatic incident alerts."
            ),
        },
    }


def should_send_admin_alert(severity: str) -> bool:
    if not admin_alerts_configured():
        return False
    return incident_severity_rank(severity) >= incident_severity_rank(admin_alert_min_severity())


def format_admin_incident_alert(incident: dict, reason: str) -> str:
    endpoint = incident.get("affectedEndpoint") or incident.get("key") or "endpoint unknown"
    service = incident.get("affectedService") or incident.get("source") or "monitoring"
    return "\n".join(
        [
            "Green VPN incident",
            f"Reason: {reason}",
            f"Severity: {incident.get('severityTitle') or incident.get('severity')}",
            f"Service: {service}",
            f"Endpoint: {endpoint}",
            f"Title: {incident.get('title')}",
            f"Summary: {incident.get('summary') or 'No summary'}",
            f"Last seen: {incident.get('lastSeenAt')}",
        ]
    )


def send_telegram_admin_alert(message: str) -> dict:
    if not admin_alerts_configured():
        return {"ok": False, "error": "telegram_alerts_not_configured"}
    payload = urllib.parse.urlencode(
        {
            "chat_id": TELEGRAM_ALERT_CHAT_ID,
            "text": message,
            "disable_web_page_preview": "1",
        }
    ).encode("utf-8")
    req = urllib.request.Request(
        f"https://api.telegram.org/bot{TELEGRAM_ALERT_BOT_TOKEN}/sendMessage",
        data=payload,
        headers={
            "Content-Type": "application/x-www-form-urlencoded",
            "User-Agent": "GreenVPN-Backend-Alerts/0.1",
        },
    )
    try:
        with urllib.request.urlopen(req, timeout=TELEGRAM_ALERT_TIMEOUT_SECONDS) as response:
            body = response.read().decode("utf-8", errors="replace")
            data = json.loads(body) if body else {}
        return {"ok": bool(data.get("ok", True)), "error": None if data.get("ok", True) else "telegram_api_rejected"}
    except urllib.error.HTTPError as exc:
        return {"ok": False, "error": f"telegram_http_{exc.code}"}
    except Exception as exc:
        return {"ok": False, "error": f"{type(exc).__name__}: {str(exc)[:160]}"}


def record_admin_incident_alert_attempt(
    incident_id: int,
    result: dict,
    reason: Optional[str] = None,
    message: Optional[str] = None,
    incident: Optional[dict] = None,
) -> str:
    now = utc_now_iso()
    status = clean_limited_text(result.get("status"), 40).strip() or ("sent" if result.get("ok") else "failed")
    error = clean_limited_text(result.get("error"), 240) or None
    provider = clean_limited_text(result.get("provider"), 40).strip() or (
        "telegram" if admin_alerts_configured() else "manual_mvp"
    )
    message_preview = clean_limited_text(message, 500) or None
    incident_key = clean_limited_text((incident or {}).get("key"), 160) or None
    severity = clean_limited_text((incident or {}).get("severity"), 40) or None
    with db() as conn:
        row = conn.execute(
            "SELECT incident_key, severity FROM admin_incidents WHERE id = ?",
            (int(incident_id),),
        ).fetchone()
        if row:
            incident_key = incident_key or row["incident_key"]
            severity = severity or row["severity"]
        conn.execute(
            """
            UPDATE admin_incidents
            SET last_alert_at = ?, last_alert_status = ?, last_alert_error = ?
            WHERE id = ?
            """,
            (now, status, error, int(incident_id)),
        )
        conn.execute(
            """
            INSERT INTO admin_alert_events(
                incident_id, incident_key, provider, reason, severity, status,
                error, message_preview, created_at, sent_at, retry_count
            )
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 0)
            """,
            (
                int(incident_id),
                incident_key,
                provider,
                clean_limited_text(reason, 80) or None,
                severity,
                status,
                error,
                message_preview,
                now,
                now if status == "sent" else None,
            ),
        )
        conn.commit()
    return now


def admin_alert_event_payload(row) -> dict:
    return {
        "id": int(row["id"]),
        "incidentId": int(row["incident_id"]) if row["incident_id"] else None,
        "incidentKey": row["incident_key"],
        "provider": row["provider"],
        "reason": row["reason"],
        "severity": row["severity"],
        "status": row["status"],
        "error": row["error"],
        "messagePreview": row["message_preview"],
        "createdAt": row["created_at"],
        "sentAt": row["sent_at"],
        "retryCount": int(row["retry_count"] or 0),
    }


def list_admin_alert_events(
    status: Optional[str] = None,
    limit: int = 80,
    offset: int = 0,
) -> list[dict]:
    safe_limit = max(1, min(300, int(limit or 80)))
    safe_offset = max(0, int(offset or 0))
    query = "SELECT * FROM admin_alert_events"
    args: list[object] = []
    status_filter = clean_limited_text(status, 40).strip()
    if status_filter and status_filter != "all":
        query += " WHERE status = ?"
        args.append(status_filter)
    query += " ORDER BY created_at DESC, id DESC LIMIT ? OFFSET ?"
    args.extend([safe_limit, safe_offset])
    with db() as conn:
        rows = conn.execute(query, tuple(args)).fetchall()
    return [admin_alert_event_payload(row) for row in rows]


def incident_runbook_categories(incident: dict) -> list[str]:
    text = " ".join(
        str(incident.get(key) or "")
        for key in ("source", "affectedService", "affectedEndpoint", "title", "summary")
    ).lower()
    categories: list[str] = []

    def add(category: str) -> None:
        if category in RUNBOOK_CATEGORIES and category not in categories:
            categories.append(category)

    if any(marker in text for marker in ("payment", "billing", "yookassa", "order", "оплат")):
        add("payments")
    if any(marker in text for marker in ("auth", "login", "email", "sms", "phone", "код")):
        add("auth")
    if any(marker in text for marker in ("wireguard", "wg0", "vpn", "peer", "handshake")):
        add("vpn")
    if any(marker in text for marker in ("server", "catalog", "endpoint", "api", "healthz")):
        add("servers")
    if any(marker in text for marker in ("youtube", "discord", "telegram", "service", "probe", "monitoring")):
        add("monitoring")
    if any(marker in text for marker in ("update", "manifest", "installer", "sha256")):
        add("updates")
    if not categories:
        add("incident")
        add("general")
    return categories[:4]


def suggest_incident_runbooks(incident: dict, limit: int = 3) -> list[dict]:
    suggestions: list[dict] = []
    seen: set[str] = set()
    categories = incident_runbook_categories(incident)
    for category in categories:
        for runbook in list_admin_runbooks(category=category, active="active", limit=20):
            key = runbook.get("key") or str(runbook.get("id"))
            if key in seen:
                continue
            seen.add(key)
            suggestions.append(
                {
                    **runbook,
                    "matchCategory": category,
                    "matchReason": f"incident category match: {category}",
                }
            )
            if len(suggestions) >= limit:
                return suggestions
    return suggestions


def incident_payload(row) -> dict:
    details = {}
    try:
        details = json.loads(row["details_json"] or "{}")
    except Exception:
        details = {}
    severity = normalize_incident_severity(row["severity"])
    payload = {
        "id": int(row["id"]),
        "key": row["incident_key"],
        "title": row["title"],
        "severity": severity,
        "severityTitle": INCIDENT_SEVERITIES[severity]["title"],
        "status": normalize_incident_status(row["status"]),
        "source": row["source"],
        "affectedService": row["affected_service"],
        "affectedEndpoint": row["affected_endpoint"],
        "firstSeenAt": row["first_seen_at"],
        "lastSeenAt": row["last_seen_at"],
        "resolvedAt": row["resolved_at"],
        "assignee": row["assignee"],
        "assigneeStaffId": int(row["assignee_staff_id"]) if "assignee_staff_id" in row.keys() and row["assignee_staff_id"] else None,
        "assignedAt": row["assigned_at"] if "assigned_at" in row.keys() else None,
        "assignedBy": row["assigned_by"] if "assigned_by" in row.keys() else None,
        "summary": row["summary"],
        "lastAlertAt": row["last_alert_at"] if "last_alert_at" in row.keys() else None,
        "lastAlertStatus": row["last_alert_status"] if "last_alert_status" in row.keys() else None,
        "lastAlertError": row["last_alert_error"] if "last_alert_error" in row.keys() else None,
        "details": details,
    }
    payload["suggestedRunbooks"] = suggest_incident_runbooks(payload)
    return payload


def upsert_admin_incident(
    incident_key: str,
    title: str,
    severity: str,
    source: str,
    affected_service: Optional[str] = None,
    affected_endpoint: Optional[str] = None,
    summary: Optional[str] = None,
    details: Optional[dict] = None,
) -> dict:
    key = clean_limited_text(incident_key, 160).strip()
    if not key:
        raise HTTPException(status_code=400, detail="Incident key is required.")
    now = utc_now_iso()
    severity = normalize_incident_severity(severity)
    title = clean_limited_text(title, 240).strip() or key
    source = clean_limited_text(source, 80).strip() or "monitoring"
    affected_service = clean_limited_text(affected_service, 120)
    affected_endpoint = clean_limited_text(affected_endpoint, 240)
    summary = clean_limited_text(summary, 1000)
    try:
        details_json = json.dumps(details or {}, ensure_ascii=False)
    except Exception:
        details_json = "{}"

    should_alert = False
    alert_reason = "new"
    with db() as conn:
        existing = conn.execute(
            "SELECT * FROM admin_incidents WHERE incident_key = ?",
            (key,),
        ).fetchone()
        if existing:
            existing_severity = normalize_incident_severity(existing["severity"])
            existing_rank = incident_severity_rank(existing_severity)
            incoming_rank = incident_severity_rank(severity)
            if existing_rank > incoming_rank:
                severity = existing_severity
            elif incoming_rank > existing_rank:
                should_alert = True
                alert_reason = "severity_escalated"
            status = normalize_incident_status(existing["status"])
            resolved_at = existing["resolved_at"]
            if status == "resolved":
                status = "open"
                resolved_at = None
                should_alert = True
                alert_reason = "reopened"
            conn.execute(
                """
                UPDATE admin_incidents
                SET title = ?, severity = ?, status = ?, source = ?,
                    affected_service = ?, affected_endpoint = ?,
                    last_seen_at = ?, resolved_at = ?, summary = ?, details_json = ?
                WHERE incident_key = ?
                """,
                (
                    title,
                    severity,
                    status,
                    source,
                    affected_service or None,
                    affected_endpoint or None,
                    now,
                    resolved_at,
                    summary or None,
                    details_json,
                    key,
                ),
            )
        else:
            should_alert = True
            alert_reason = "new"
            conn.execute(
                """
                INSERT INTO admin_incidents(
                    incident_key, title, severity, status, source,
                    affected_service, affected_endpoint, first_seen_at, last_seen_at,
                    summary, details_json
                )
                VALUES (?, ?, ?, 'open', ?, ?, ?, ?, ?, ?, ?)
                """,
                (
                    key,
                    title,
                    severity,
                    source,
                    affected_service or None,
                    affected_endpoint or None,
                    now,
                    now,
                    summary or None,
                    details_json,
                ),
            )
        conn.commit()
        row = conn.execute(
            "SELECT * FROM admin_incidents WHERE incident_key = ?",
            (key,),
        ).fetchone()
    payload = incident_payload(row)
    if should_alert and incident_severity_rank(payload["severity"]) >= incident_severity_rank(admin_alert_min_severity()):
        message = format_admin_incident_alert(payload, alert_reason)
        if should_send_admin_alert(payload["severity"]):
            result = send_telegram_admin_alert(message)
            result["provider"] = "telegram"
        else:
            result = {
                "ok": False,
                "status": "skipped",
                "provider": "manual_mvp",
                "error": "telegram_alerts_not_configured",
            }
        payload["lastAlertAt"] = record_admin_incident_alert_attempt(
            payload["id"],
            result,
            reason=alert_reason,
            message=message,
            incident=payload,
        )
        payload["lastAlertStatus"] = "sent" if result.get("ok") else "failed"
        if result.get("status"):
            payload["lastAlertStatus"] = result["status"]
        payload["lastAlertError"] = result.get("error")
    return payload


def resolve_admin_incident_by_key(incident_key: str, summary: str) -> None:
    key = clean_limited_text(incident_key, 160).strip()
    if not key:
        return
    now = utc_now_iso()
    with db() as conn:
        conn.execute(
            """
            UPDATE admin_incidents
            SET status = 'resolved', resolved_at = ?, last_seen_at = ?,
                summary = COALESCE(?, summary)
            WHERE incident_key = ? AND status != 'resolved'
            """,
            (now, now, clean_limited_text(summary, 1000) or None, key),
        )
        conn.commit()


def list_admin_incidents(
    status: Optional[str] = None,
    severity: Optional[str] = None,
    assignee: Optional[str] = None,
    limit: int = 100,
    offset: int = 0,
) -> list[dict]:
    safe_limit = max(1, min(300, int(limit or 100)))
    safe_offset = max(0, int(offset or 0))
    query = "SELECT * FROM admin_incidents"
    filters = []
    args: list = []
    if status and status != "all":
        filters.append("status = ?")
        args.append(normalize_incident_status(status))
    if severity and severity != "all":
        filters.append("severity = ?")
        args.append(normalize_incident_severity(severity))
    assignee_filter = clean_limited_text(assignee, 120).strip()
    if assignee_filter and assignee_filter != "all":
        if assignee_filter == "unassigned":
            filters.append("(assignee IS NULL OR assignee = '')")
        elif assignee_filter.isdigit():
            filters.append("assignee_staff_id = ?")
            args.append(int(assignee_filter))
        else:
            filters.append("assignee LIKE ?")
            args.append(f"%{assignee_filter}%")
    if filters:
        query += " WHERE " + " AND ".join(filters)
    query += """
        ORDER BY
            CASE WHEN status = 'resolved' THEN 1 ELSE 0 END ASC,
            CASE severity
                WHEN 'critical' THEN 4
                WHEN 'high' THEN 3
                WHEN 'medium' THEN 2
                ELSE 1
            END DESC,
            last_seen_at DESC
        LIMIT ? OFFSET ?
    """
    args.extend([safe_limit, safe_offset])
    with db() as conn:
        rows = conn.execute(query, tuple(args)).fetchall()
    return [incident_payload(row) for row in rows]


def update_admin_incident(
    incident_id: int,
    payload: AdminIncidentUpdateIn,
    actor: Optional[str] = None,
) -> dict:
    with db() as conn:
        row = conn.execute(
            "SELECT * FROM admin_incidents WHERE id = ?",
            (incident_id,),
        ).fetchone()
        if row is None:
            raise HTTPException(status_code=404, detail="Incident not found.")

        status = (
            normalize_incident_status(payload.status, row["status"])
            if payload.status is not None
            else normalize_incident_status(row["status"])
        )
        severity = (
            normalize_incident_severity(payload.severity, row["severity"])
            if payload.severity is not None
            else normalize_incident_severity(row["severity"])
        )
        assignee = row["assignee"]
        assignee_staff_id = (
            int(row["assignee_staff_id"])
            if "assignee_staff_id" in row.keys() and row["assignee_staff_id"]
            else None
        )
        assigned_at = row["assigned_at"] if "assigned_at" in row.keys() else None
        assigned_by = row["assigned_by"] if "assigned_by" in row.keys() else None
        assignee_changed = False
        actor_label = clean_limited_text(actor, 120).strip() or "admin"
        if payload.clearAssignee:
            assignee = None
            assignee_staff_id = None
            assigned_at = None
            assigned_by = None
            assignee_changed = True
        elif payload.assigneeStaffId is not None:
            staff_row = get_incident_assignee_staff(int(payload.assigneeStaffId))
            assignee = incident_assignee_label(staff_row)
            assignee_staff_id = int(staff_row["id"])
            assigned_at = utc_now_iso()
            assigned_by = actor_label
            assignee_changed = True
        elif payload.assignee is not None:
            assignee = clean_limited_text(payload.assignee, 120).strip() or None
            assignee_staff_id = None
            assigned_at = utc_now_iso() if assignee else None
            assigned_by = actor_label if assignee else None
            assignee_changed = True
        resolved_at = utc_now_iso() if status == "resolved" else None
        if status != "resolved" and row["status"] == "resolved":
            resolved_at = None
        elif status == "resolved" and row["resolved_at"]:
            resolved_at = row["resolved_at"]

        details = {}
        try:
            details = json.loads(row["details_json"] or "{}")
        except Exception:
            details = {}
        note = clean_limited_text(payload.note, 1000).strip()
        if note:
            notes = details.get("adminNotes")
            if not isinstance(notes, list):
                notes = []
            notes.append({"at": utc_now_iso(), "body": note})
            details["adminNotes"] = notes[-20:]

        conn.execute(
            """
            UPDATE admin_incidents
            SET status = ?, severity = ?, assignee = ?, resolved_at = ?,
                last_seen_at = ?, details_json = ?,
                assignee_staff_id = ?, assigned_at = ?, assigned_by = ?
            WHERE id = ?
            """,
            (
                status,
                severity,
                assignee or None,
                resolved_at,
                utc_now_iso(),
                json.dumps(details, ensure_ascii=False),
                assignee_staff_id,
                assigned_at,
                assigned_by,
                incident_id,
            ),
        )
        if assignee_changed:
            details["assignmentHistory"] = (details.get("assignmentHistory") or [])[-19:] + [
                {
                    "at": utc_now_iso(),
                    "assignee": assignee,
                    "assigneeStaffId": assignee_staff_id,
                    "actor": actor_label,
                    "cleared": bool(not assignee),
                }
            ]
            conn.execute(
                """
                UPDATE admin_incidents
                SET details_json = ?
                WHERE id = ?
                """,
                (json.dumps(details, ensure_ascii=False), incident_id),
            )
        conn.commit()
        row = conn.execute(
            "SELECT * FROM admin_incidents WHERE id = ?",
            (incident_id,),
        ).fetchone()
    return incident_payload(row)


def sync_monitoring_incidents(
    monitoring: Optional[dict] = None,
    services: Optional[dict] = None,
) -> list[dict]:
    monitoring = monitoring or build_monitoring_status()
    services = services or build_service_availability_status()
    incidents: list[dict] = []

    for check in monitoring.get("checks", []):
        code = clean_limited_text(check.get("code"), 80)
        key = f"infra:{code}"
        status = check.get("status")
        if status in {"red", "yellow"}:
            severity = "critical" if status == "red" and code in {"backend", "database", "wireguard"} else (
                "high" if status == "red" else "medium"
            )
            incidents.append(
                upsert_admin_incident(
                    key,
                    f"{check.get('title') or code}: {check.get('status')}",
                    severity,
                    "infrastructure_monitoring",
                    affected_service=check.get("title") or code,
                    affected_endpoint=check.get("endpoint"),
                    summary=check.get("message"),
                    details={"check": check},
                )
            )
        elif status == "green":
            resolve_admin_incident_by_key(key, f"{check.get('title') or code} снова зелёный.")

    for check in services.get("checks", []):
        code = clean_limited_text(check.get("code"), 80)
        key = f"service:{code}"
        status = check.get("status")
        if status in {"red", "yellow"}:
            incidents.append(
                upsert_admin_incident(
                    key,
                    f"Доступность сервиса: {check.get('title') or code}",
                    "high" if status == "red" else "medium",
                    "service_availability_monitoring",
                    affected_service=check.get("title") or code,
                    affected_endpoint=check.get("url") or check.get("host"),
                    summary=check.get("message"),
                    details={"check": check, "probe": services.get("probeLocation")},
                )
            )
        elif status == "green":
            resolve_admin_incident_by_key(key, f"{check.get('title') or code} снова доступен.")

    return incidents


def admin_staff_payload(row) -> dict:
    has_password = bool(row["password_hash"]) if "password_hash" in row.keys() else False
    return {
        "id": int(row["id"]),
        "email": row["email"],
        "displayName": row["display_name"],
        "role": row["role"],
        "roleTitle": ADMIN_ROLE_MATRIX.get(row["role"], {}).get("title", row["role"]),
        "permissions": ADMIN_ROLE_MATRIX.get(row["role"], {}).get("permissions", []),
        "isActive": bool(row["is_active"]),
        "hasPassword": has_password,
        "passwordSetAt": row["password_set_at"] if "password_set_at" in row.keys() else None,
        "twoFactorEnabled": bool(row["two_factor_enabled"])
        if "two_factor_enabled" in row.keys()
        else False,
        "twoFactorMethod": row["two_factor_method"]
        if "two_factor_method" in row.keys()
        else "email",
        "twoFactorSetAt": row["two_factor_set_at"]
        if "two_factor_set_at" in row.keys()
        else None,
        "createdAt": row["created_at"],
        "updatedAt": row["updated_at"],
        "lastLoginAt": row["last_login_at"] if "last_login_at" in row.keys() else None,
        "lastSeenAt": row["last_seen_at"],
        "activeSessionCount": int(row["active_session_count"] or 0)
        if "active_session_count" in row.keys()
        else 0,
        "revokedSessionCount": int(row["revoked_session_count"] or 0)
        if "revoked_session_count" in row.keys()
        else 0,
        "expiredSessionCount": int(row["expired_session_count"] or 0)
        if "expired_session_count" in row.keys()
        else 0,
        "lastSessionSeenAt": row["last_session_seen_at"]
        if "last_session_seen_at" in row.keys()
        else None,
    }


def list_admin_roles() -> list[dict]:
    order = ["owner", "admin", "support", "finance", "readonly"]
    return [
        admin_role_payload(code, ADMIN_ROLE_MATRIX[code])
        for code in order
        if code in ADMIN_ROLE_MATRIX
    ]


def list_admin_staff() -> list[dict]:
    now = utc_now_iso()
    with db() as conn:
        rows = conn.execute(
            """
            SELECT
                st.*,
                COALESCE(SUM(
                    CASE
                        WHEN s.token_hash IS NOT NULL
                         AND s.revoked_at IS NULL
                         AND s.expires_at > ?
                        THEN 1 ELSE 0
                    END
                ), 0) AS active_session_count,
                COALESCE(SUM(
                    CASE
                        WHEN s.revoked_at IS NOT NULL
                        THEN 1 ELSE 0
                    END
                ), 0) AS revoked_session_count,
                COALESCE(SUM(
                    CASE
                        WHEN s.token_hash IS NOT NULL
                         AND s.revoked_at IS NULL
                         AND s.expires_at <= ?
                        THEN 1 ELSE 0
                    END
                ), 0) AS expired_session_count,
                MAX(s.last_seen_at) AS last_session_seen_at
            FROM admin_staff st
            LEFT JOIN admin_sessions s ON s.staff_id = st.id
            GROUP BY st.id
            ORDER BY st.is_active DESC, st.role ASC, st.email ASC
            """,
            (now, now),
        ).fetchall()
    return [admin_staff_payload(row) for row in rows]


def staff_can_handle_incidents(row) -> bool:
    role = normalize_admin_role(row["role"])
    permissions = ADMIN_ROLE_MATRIX.get(role, {}).get("permissions", [])
    return bool(row["is_active"]) and "incidents.manage" in permissions


def incident_assignee_payload(row) -> dict:
    role = normalize_admin_role(row["role"])
    display_name = clean_limited_text(row["display_name"], 120).strip()
    email = clean_limited_text(row["email"], 180).strip().lower()
    label = display_name or email
    return {
        "id": int(row["id"]),
        "email": email,
        "displayName": display_name,
        "label": label,
        "role": role,
        "roleTitle": ADMIN_ROLE_MATRIX.get(role, {}).get("title", role),
        "isActive": bool(row["is_active"]),
    }


def list_incident_assignees() -> list[dict]:
    with db() as conn:
        rows = conn.execute(
            """
            SELECT id, email, display_name, role, is_active
            FROM admin_staff
            WHERE is_active = 1
            ORDER BY role ASC, email ASC
            """
        ).fetchall()
    return [incident_assignee_payload(row) for row in rows if staff_can_handle_incidents(row)]


def get_incident_assignee_staff(staff_id: int):
    with db() as conn:
        row = conn.execute(
            """
            SELECT id, email, display_name, role, is_active
            FROM admin_staff
            WHERE id = ?
            """,
            (int(staff_id),),
        ).fetchone()
    if row is None:
        raise HTTPException(status_code=404, detail="Incident assignee staff member not found.")
    if not staff_can_handle_incidents(row):
        raise HTTPException(status_code=400, detail="Incident assignee must be active and allowed to manage incidents.")
    return row


def incident_assignee_label(row) -> str:
    payload = incident_assignee_payload(row)
    return payload.get("label") or payload.get("email") or f"staff:{payload['id']}"


def upsert_admin_staff(payload: AdminStaffIn) -> dict:
    email = clean_limited_text(payload.email, 180).strip().lower()
    if not email or "@" not in email or "." not in email.rsplit("@", 1)[-1]:
        raise HTTPException(status_code=400, detail="Valid staff email is required.")
    role = normalize_admin_role(payload.role)
    display_name = clean_limited_text(payload.displayName, 120).strip() or email.split("@", 1)[0]
    is_active = 1 if payload.isActive else 0
    two_factor_enabled = 1 if payload.twoFactorEnabled else 0
    two_factor_set_at = utc_now_iso() if two_factor_enabled else None
    temporary_password = clean_admin_password(payload.temporaryPassword)
    password_hash = admin_password_hash(temporary_password) if temporary_password else None
    password_set_at = utc_now_iso() if password_hash else None
    now = utc_now_iso()
    with db() as conn:
        existing = conn.execute(
            "SELECT id FROM admin_staff WHERE email = ?",
            (email,),
        ).fetchone()
        if existing:
            staff_id = int(existing["id"])
            if password_hash:
                conn.execute(
                    """
                    UPDATE admin_staff
                    SET display_name = ?, role = ?, is_active = ?, password_hash = ?,
                        password_set_at = ?, two_factor_enabled = ?, two_factor_set_at = ?,
                        updated_at = ?
                    WHERE id = ?
                    """,
                    (
                        display_name,
                        role,
                        is_active,
                        password_hash,
                        password_set_at,
                        two_factor_enabled,
                        two_factor_set_at,
                        now,
                        staff_id,
                    ),
                )
            else:
                conn.execute(
                    """
                    UPDATE admin_staff
                    SET display_name = ?, role = ?, is_active = ?, two_factor_enabled = ?,
                        two_factor_set_at = ?, updated_at = ?
                    WHERE id = ?
                    """,
                    (
                        display_name,
                        role,
                        is_active,
                        two_factor_enabled,
                        two_factor_set_at,
                        now,
                        staff_id,
                    ),
                )
        else:
            cursor = conn.execute(
                """
                INSERT INTO admin_staff(
                    email, display_name, role, is_active, password_hash, password_set_at,
                    two_factor_enabled, two_factor_method, two_factor_set_at,
                    created_at, updated_at
                )
                VALUES (?, ?, ?, ?, ?, ?, ?, 'email', ?, ?, ?)
                """,
                (
                    email,
                    display_name,
                    role,
                    is_active,
                    password_hash,
                    password_set_at,
                    two_factor_enabled,
                    two_factor_set_at,
                    now,
                    now,
                ),
            )
            staff_id = int(cursor.lastrowid)
        conn.commit()
        row = conn.execute(
            "SELECT * FROM admin_staff WHERE id = ?",
            (staff_id,),
        ).fetchone()
    return admin_staff_payload(row)


def update_admin_staff(staff_id: int, payload: AdminStaffUpdateIn) -> dict:
    with db() as conn:
        row = conn.execute(
            "SELECT * FROM admin_staff WHERE id = ?",
            (staff_id,),
        ).fetchone()
        if row is None:
            raise HTTPException(status_code=404, detail="Staff member not found.")

        display_name = (
            clean_limited_text(payload.displayName, 120).strip()
            if payload.displayName is not None
            else row["display_name"]
        )
        role = normalize_admin_role(payload.role) if payload.role is not None else row["role"]
        is_active = (
            1 if payload.isActive else 0
        ) if payload.isActive is not None else int(row["is_active"])
        if payload.twoFactorEnabled is None:
            two_factor_enabled = int(row["two_factor_enabled"]) if "two_factor_enabled" in row.keys() else 0
            two_factor_set_at = row["two_factor_set_at"] if "two_factor_set_at" in row.keys() else None
        else:
            two_factor_enabled = 1 if payload.twoFactorEnabled else 0
            was_enabled = bool(row["two_factor_enabled"]) if "two_factor_enabled" in row.keys() else False
            two_factor_set_at = utc_now_iso() if two_factor_enabled and not was_enabled else (
                row["two_factor_set_at"] if two_factor_enabled else None
            )
        temporary_password = clean_admin_password(payload.temporaryPassword)
        password_hash = admin_password_hash(temporary_password) if temporary_password else None
        password_set_at = utc_now_iso() if password_hash else None

        if password_hash:
            conn.execute(
                """
                UPDATE admin_staff
                SET display_name = ?, role = ?, is_active = ?, password_hash = ?,
                    password_set_at = ?, two_factor_enabled = ?, two_factor_set_at = ?,
                    updated_at = ?
                WHERE id = ?
                """,
                (
                    display_name,
                    role,
                    is_active,
                    password_hash,
                    password_set_at,
                    two_factor_enabled,
                    two_factor_set_at,
                    utc_now_iso(),
                    staff_id,
                ),
            )
        else:
            conn.execute(
                """
                UPDATE admin_staff
                SET display_name = ?, role = ?, is_active = ?, two_factor_enabled = ?,
                    two_factor_set_at = ?, updated_at = ?
                WHERE id = ?
                """,
                (
                    display_name,
                    role,
                    is_active,
                    two_factor_enabled,
                    two_factor_set_at,
                    utc_now_iso(),
                    staff_id,
                ),
            )
        conn.commit()
        row = conn.execute(
            "SELECT * FROM admin_staff WHERE id = ?",
            (staff_id,),
        ).fetchone()
    return admin_staff_payload(row)


def create_admin_2fa_challenge(row, request: Request, actor: Optional[str] = None) -> dict:
    if not admin_2fa_email_configured():
        write_admin_audit(
            "admin_staff_2fa_unavailable",
            "admin_staff",
            str(row["id"]),
            {"email": row["email"], "reason": "smtp_or_pepper_not_configured"},
            request=request,
            actor=clean_limited_text(actor, 120).strip() or row["email"],
        )
        raise HTTPException(
            status_code=503,
            detail="Admin email code delivery is not configured.",
        )

    code = f"{secrets.randbelow(1000000):06d}"
    challenge_id = secrets.token_urlsafe(24)
    now = utc_now()
    expires_at = now + timedelta(minutes=ADMIN_2FA_CODE_TTL_MINUTES)
    request_ip, user_agent = request_ip_and_agent(request)
    with db() as conn:
        conn.execute(
            """
            UPDATE admin_2fa_challenges
            SET status = 'superseded', failed_at = ?
            WHERE staff_id = ? AND status = 'pending'
            """,
            (now.isoformat(), int(row["id"])),
        )
        conn.execute(
            """
            INSERT INTO admin_2fa_challenges(
                challenge_id, staff_id, code_hash, status, attempts_count,
                request_ip, user_agent, created_at, expires_at
            )
            VALUES (?, ?, ?, 'pending', 0, ?, ?, ?, ?)
            """,
            (
                challenge_id,
                int(row["id"]),
                admin_2fa_code_hash(int(row["id"]), challenge_id, code),
                request_ip,
                user_agent,
                now.isoformat(),
                expires_at.isoformat(),
            ),
        )
        conn.commit()

    subject = "Код входа в Green VPN Admin"
    body = (
        "Код входа в Green VPN Admin:\n\n"
        f"{code}\n\n"
        f"Код действует {ADMIN_2FA_CODE_TTL_MINUTES} минут. "
        "Если вход выполняли не вы, смените пароль и сбросьте активные сессии.\n"
    )
    try:
        send_smtp_email(row["email"], subject, body)
        sent_at = utc_now_iso()
        with db() as conn:
            conn.execute(
                """
                UPDATE admin_2fa_challenges
                SET sent_at = ?
                WHERE challenge_id = ?
                """,
                (sent_at, challenge_id),
            )
            conn.commit()
    except Exception as exc:
        with db() as conn:
            conn.execute(
                """
                UPDATE admin_2fa_challenges
                SET status = 'failed', failed_at = ?
                WHERE challenge_id = ?
                """,
                (utc_now_iso(), challenge_id),
            )
            conn.commit()
        write_admin_audit(
            "admin_staff_2fa_delivery_failed",
            "admin_staff",
            str(row["id"]),
            {"email": row["email"], "errorType": exc.__class__.__name__},
            request=request,
            actor=clean_limited_text(actor, 120).strip() or row["email"],
        )
        raise HTTPException(status_code=503, detail="Admin email code could not be sent.")

    write_admin_audit(
        "admin_staff_2fa_challenge_created",
        "admin_staff",
        str(row["id"]),
        {"email": row["email"], "expiresAt": expires_at.isoformat()},
        request=request,
        actor=clean_limited_text(actor, 120).strip() or row["email"],
    )
    return {
        "ok": True,
        "twoFactorRequired": True,
        "authType": "staff_2fa_pending",
        "challengeId": challenge_id,
        "expiresAt": expires_at.isoformat(),
        "deliveryStatus": "sent",
        "email": mask_admin_email(row["email"]),
    }


def verify_admin_2fa_challenge(payload: AdminTwoFactorVerifyIn, request: Request) -> dict:
    email = clean_limited_text(payload.email, 180).strip().lower()
    challenge_id = clean_limited_text(payload.challengeId, 120).strip()
    clean_code = re.sub(r"\D+", "", str(payload.code or ""))
    if not email or not challenge_id or len(clean_code) != 6:
        raise HTTPException(status_code=400, detail="Email, challenge and 6-digit code are required.")

    now = utc_now()
    with db() as conn:
        row = conn.execute(
            """
            SELECT ch.*, st.email, st.display_name, st.role, st.is_active,
                   st.password_hash, st.password_set_at, st.last_login_at,
                   st.last_seen_at, st.two_factor_enabled, st.two_factor_method,
                   st.two_factor_set_at, st.created_at AS staff_created_at,
                   st.updated_at AS staff_updated_at
            FROM admin_2fa_challenges ch
            JOIN admin_staff st ON st.id = ch.staff_id
            WHERE ch.challenge_id = ? AND st.email = ?
            """,
            (challenge_id, email),
        ).fetchone()
        if row is None or row["status"] != "pending" or not bool(row["is_active"]):
            write_admin_audit(
                "admin_staff_2fa_verify_failed",
                "admin_staff",
                email or "unknown_admin_2fa",
                {"reason": "challenge_missing_or_inactive"},
                request=request,
                actor=email or "unknown_admin_2fa",
            )
            raise HTTPException(status_code=401, detail="Invalid admin email code.")

        expires_at = parse_dt(row["expires_at"])
        locked_until = parse_dt(row["locked_until"]) if row["locked_until"] else None
        if locked_until and locked_until > now:
            raise HTTPException(status_code=429, detail="Too many attempts. Try later.")
        if expires_at is None or expires_at <= now:
            conn.execute(
                "UPDATE admin_2fa_challenges SET status = 'expired', failed_at = ? WHERE id = ?",
                (now.isoformat(), int(row["id"])),
            )
            conn.commit()
            raise HTTPException(status_code=401, detail="Admin email code expired.")

        expected = row["code_hash"]
        provided = admin_2fa_code_hash(int(row["staff_id"]), challenge_id, clean_code)
        if not hmac.compare_digest(expected, provided):
            attempts = int(row["attempts_count"] or 0) + 1
            status = "pending"
            failed_at = None
            next_locked_until = None
            if attempts >= ADMIN_2FA_MAX_ATTEMPTS:
                status = "failed"
                failed_at = now.isoformat()
                next_locked_until = (now + timedelta(minutes=15)).isoformat()
            conn.execute(
                """
                UPDATE admin_2fa_challenges
                SET attempts_count = ?, status = ?, failed_at = ?, locked_until = ?
                WHERE id = ?
                """,
                (attempts, status, failed_at, next_locked_until, int(row["id"])),
            )
            conn.commit()
            write_admin_audit(
                "admin_staff_2fa_verify_failed",
                "admin_staff",
                str(row["staff_id"]),
                {"email": row["email"], "attempts": attempts, "locked": bool(next_locked_until)},
                request=request,
                actor=clean_limited_text(payload.actor, 120).strip() or row["email"],
            )
            raise HTTPException(status_code=401, detail="Invalid admin email code.")

        conn.execute(
            """
            UPDATE admin_2fa_challenges
            SET status = 'verified', verified_at = ?
            WHERE id = ?
            """,
            (now.isoformat(), int(row["id"])),
        )
        conn.commit()

        staff_row = conn.execute(
            "SELECT * FROM admin_staff WHERE id = ?",
            (int(row["staff_id"]),),
        ).fetchone()

    write_admin_audit(
        "admin_staff_2fa_verify_succeeded",
        "admin_staff",
        str(staff_row["id"]),
        {"email": staff_row["email"]},
        request=request,
        actor=clean_limited_text(payload.actor, 120).strip() or staff_row["email"],
    )
    return issue_admin_staff_session(staff_row, request, payload.actor)


def login_admin_staff(payload: AdminLoginIn, request: Request) -> dict:
    email = clean_limited_text(payload.email, 180).strip().lower()
    password = str(payload.password or "")
    if not email or not password:
        raise HTTPException(status_code=400, detail="Email and password are required.")

    with db() as conn:
        row = conn.execute(
            """
            SELECT *
            FROM admin_staff
            WHERE email = ?
            """,
            (email,),
        ).fetchone()

    if row is None or not bool(row["is_active"]) or not verify_admin_password(password, row["password_hash"]):
        write_admin_audit(
            "admin_staff_login_failed",
            "admin_staff",
            email,
            {"reason": "invalid_credentials_or_disabled"},
            request=request,
            actor=email or "unknown_admin_login",
        )
        raise HTTPException(status_code=401, detail="Invalid admin credentials.")

    actor = clean_limited_text(payload.actor, 120).strip() or row["email"]
    if admin_staff_requires_2fa(row):
        return create_admin_2fa_challenge(row, request, actor)

    return issue_admin_staff_session(row, request, actor)


def revoke_admin_session(token_hash: Optional[str]) -> bool:
    if not token_hash:
        return False
    with db() as conn:
        cursor = conn.execute(
            """
            UPDATE admin_sessions
            SET revoked_at = ?
            WHERE token_hash = ? AND revoked_at IS NULL
            """,
            (utc_now_iso(), token_hash),
        )
        changed = cursor.rowcount > 0
        conn.commit()
    return changed


def require_staff_session_context(context: dict) -> dict:
    if context.get("authType") != "staff_session" or not context.get("staff"):
        raise HTTPException(status_code=403, detail="Staff session required.")
    return context


def admin_session_public_id(token_hash: str) -> str:
    return clean_limited_text(token_hash, 64)[:16]


def admin_session_payload(row, current_session_hash: Optional[str]) -> dict:
    token_hash = row["token_hash"]
    return {
        "sessionId": admin_session_public_id(token_hash),
        "isCurrent": bool(current_session_hash and token_hash == current_session_hash),
        "createdAt": row["created_at"],
        "expiresAt": row["expires_at"],
        "lastSeenAt": row["last_seen_at"],
        "revokedAt": row["revoked_at"],
        "requestIp": row["request_ip"],
        "userAgent": clean_limited_text(row["user_agent"], 240),
    }


def list_current_admin_sessions(context: dict) -> list[dict]:
    context = require_staff_session_context(context)
    staff_id = int(context["staff"]["id"])
    current_hash = context.get("sessionHash")
    with db() as conn:
        rows = conn.execute(
            """
            SELECT *
            FROM admin_sessions
            WHERE staff_id = ?
            ORDER BY revoked_at IS NOT NULL ASC, last_seen_at DESC, created_at DESC
            LIMIT 50
            """,
            (staff_id,),
        ).fetchall()
    return [admin_session_payload(row, current_hash) for row in rows]


def get_admin_staff_row(staff_id: int):
    with db() as conn:
        row = conn.execute(
            "SELECT * FROM admin_staff WHERE id = ?",
            (int(staff_id),),
        ).fetchone()
    if row is None:
        raise HTTPException(status_code=404, detail="Staff member not found.")
    return row


def list_staff_admin_sessions(staff_id: int, context: Optional[dict] = None) -> list[dict]:
    get_admin_staff_row(staff_id)
    current_hash = (context or {}).get("sessionHash")
    with db() as conn:
        rows = conn.execute(
            """
            SELECT *
            FROM admin_sessions
            WHERE staff_id = ?
            ORDER BY revoked_at IS NULL DESC, last_seen_at DESC, created_at DESC
            LIMIT 100
            """,
            (int(staff_id),),
        ).fetchall()
    return [admin_session_payload(row, current_hash) for row in rows]


def revoke_staff_admin_session_by_public_id(
    staff_id: int,
    context: dict,
    payload: AdminSessionRevokeIn,
    request: Request,
) -> dict:
    staff = get_admin_staff_row(staff_id)
    session_id = clean_limited_text(payload.sessionId, 64).strip().lower()
    if len(session_id) < 8 or any(char not in "0123456789abcdef" for char in session_id):
        raise HTTPException(status_code=400, detail="Invalid session id.")

    with db() as conn:
        rows = conn.execute(
            """
            SELECT *
            FROM admin_sessions
            WHERE staff_id = ? AND lower(substr(token_hash, 1, ?)) = ?
            """,
            (int(staff_id), len(session_id), session_id),
        ).fetchall()
        active_rows = [row for row in rows if not row["revoked_at"]]
        if not active_rows:
            raise HTTPException(status_code=404, detail="Active staff session not found.")
        if len(active_rows) > 1:
            raise HTTPException(status_code=409, detail="Session id is ambiguous.")
        row = active_rows[0]
        if row["token_hash"] == context.get("sessionHash"):
            raise HTTPException(status_code=400, detail="Use logout to revoke the current session.")
        revoked_at = utc_now_iso()
        cursor = conn.execute(
            """
            UPDATE admin_sessions
            SET revoked_at = ?
            WHERE token_hash = ? AND revoked_at IS NULL
            """,
            (revoked_at, row["token_hash"]),
        )
        conn.commit()

    write_admin_audit(
        "admin_staff_session_revoked",
        "admin_staff",
        str(staff_id),
        {
            "sessionId": session_id,
            "staffEmail": staff["email"],
            "revoked": cursor.rowcount > 0,
        },
        request=request,
        actor=context.get("actor") or "admin_token",
    )
    return {
        "ok": True,
        "staffId": int(staff_id),
        "sessionId": session_id,
        "revoked": cursor.rowcount > 0,
    }


def revoke_all_staff_admin_sessions(
    staff_id: int,
    context: dict,
    request: Request,
) -> dict:
    staff = get_admin_staff_row(staff_id)
    now = utc_now_iso()
    current_hash = context.get("sessionHash")
    current_staff = context.get("staff") or {}
    preserve_current = (
        current_hash
        and current_staff
        and int(current_staff.get("id") or 0) == int(staff_id)
    )
    with db() as conn:
        if preserve_current:
            cursor = conn.execute(
                """
                UPDATE admin_sessions
                SET revoked_at = ?
                WHERE staff_id = ?
                  AND token_hash <> ?
                  AND revoked_at IS NULL
                """,
                (now, int(staff_id), current_hash),
            )
        else:
            cursor = conn.execute(
                """
                UPDATE admin_sessions
                SET revoked_at = ?
                WHERE staff_id = ?
                  AND revoked_at IS NULL
                """,
                (now, int(staff_id)),
            )
        conn.commit()

    write_admin_audit(
        "admin_staff_sessions_revoked",
        "admin_staff",
        str(staff_id),
        {
            "staffEmail": staff["email"],
            "revokedSessions": cursor.rowcount,
            "preservedCurrentSession": bool(preserve_current),
        },
        request=request,
        actor=context.get("actor") or "admin_token",
    )
    return {
        "ok": True,
        "staffId": int(staff_id),
        "revokedSessions": cursor.rowcount,
        "preservedCurrentSession": bool(preserve_current),
    }


def change_current_admin_password(
    context: dict,
    payload: AdminPasswordChangeIn,
    request: Request,
) -> dict:
    context = require_staff_session_context(context)
    staff_id = int(context["staff"]["id"])
    current_password = str(payload.currentPassword or "")
    new_password = str(payload.newPassword or "")
    if not current_password or not new_password:
        raise HTTPException(status_code=400, detail="Current and new password are required.")
    if hmac.compare_digest(current_password, new_password):
        raise HTTPException(status_code=400, detail="New password must be different.")

    with db() as conn:
        row = conn.execute(
            "SELECT * FROM admin_staff WHERE id = ?",
            (staff_id,),
        ).fetchone()
        if row is None or not bool(row["is_active"]):
            raise HTTPException(status_code=403, detail="Admin staff member is disabled.")
        if not verify_admin_password(current_password, row["password_hash"]):
            write_admin_audit(
                "admin_password_change_failed",
                "admin_staff",
                str(staff_id),
                {"reason": "invalid_current_password"},
                request=request,
                actor=context.get("actor") or row["email"],
            )
            raise HTTPException(status_code=401, detail="Current password is invalid.")

        password_hash = admin_password_hash(new_password)
        password_set_at = utc_now_iso()
        conn.execute(
            """
            UPDATE admin_staff
            SET password_hash = ?, password_set_at = ?, updated_at = ?
            WHERE id = ?
            """,
            (password_hash, password_set_at, password_set_at, staff_id),
        )
        cursor = conn.execute(
            """
            UPDATE admin_sessions
            SET revoked_at = ?
            WHERE staff_id = ? AND token_hash <> ? AND revoked_at IS NULL
            """,
            (password_set_at, staff_id, context.get("sessionHash")),
        )
        revoked_other_sessions = cursor.rowcount
        conn.commit()

    write_admin_audit(
        "admin_password_changed",
        "admin_staff",
        str(staff_id),
        {"revokedOtherSessions": revoked_other_sessions},
        request=request,
        actor=context.get("actor") or context["staff"].get("email"),
    )
    return {
        "ok": True,
        "passwordSetAt": password_set_at,
        "revokedOtherSessions": revoked_other_sessions,
    }


def revoke_current_admin_session_by_public_id(
    context: dict,
    payload: AdminSessionRevokeIn,
    request: Request,
) -> dict:
    context = require_staff_session_context(context)
    staff_id = int(context["staff"]["id"])
    session_id = clean_limited_text(payload.sessionId, 64).strip().lower()
    if len(session_id) < 8 or any(char not in "0123456789abcdef" for char in session_id):
        raise HTTPException(status_code=400, detail="Invalid session id.")

    with db() as conn:
        rows = conn.execute(
            """
            SELECT *
            FROM admin_sessions
            WHERE staff_id = ? AND lower(substr(token_hash, 1, ?)) = ?
            """,
            (staff_id, len(session_id), session_id),
        ).fetchall()
        active_rows = [row for row in rows if not row["revoked_at"]]
        if not active_rows:
            raise HTTPException(status_code=404, detail="Active session not found.")
        if len(active_rows) > 1:
            raise HTTPException(status_code=409, detail="Session id is ambiguous.")
        row = active_rows[0]
        if row["token_hash"] == context.get("sessionHash"):
            raise HTTPException(status_code=400, detail="Use logout to revoke the current session.")
        revoked_at = utc_now_iso()
        cursor = conn.execute(
            """
            UPDATE admin_sessions
            SET revoked_at = ?
            WHERE token_hash = ? AND revoked_at IS NULL
            """,
            (revoked_at, row["token_hash"]),
        )
        revoked = cursor.rowcount > 0
        conn.commit()

    write_admin_audit(
        "admin_session_revoked",
        "admin_session",
        session_id,
        {"staffId": staff_id, "revoked": revoked},
        request=request,
        actor=context.get("actor") or context["staff"].get("email"),
    )
    return {
        "ok": True,
        "revoked": revoked,
        "sessionId": session_id,
    }


def revoke_other_admin_sessions(context: dict, request: Request) -> dict:
    context = require_staff_session_context(context)
    staff_id = int(context["staff"]["id"])
    now = utc_now_iso()
    with db() as conn:
        cursor = conn.execute(
            """
            UPDATE admin_sessions
            SET revoked_at = ?
            WHERE staff_id = ? AND token_hash <> ? AND revoked_at IS NULL
            """,
            (now, staff_id, context.get("sessionHash")),
        )
        conn.commit()
    write_admin_audit(
        "admin_other_sessions_revoked",
        "admin_staff",
        str(staff_id),
        {"revokedOtherSessions": cursor.rowcount},
        request=request,
        actor=context.get("actor") or context["staff"].get("email"),
    )
    return {
        "ok": True,
        "revokedOtherSessions": cursor.rowcount,
    }


def list_auth_events(
    limit: int = 100,
    offset: int = 0,
    event_type: Optional[str] = None,
    status: Optional[str] = None,
    contact: Optional[str] = None,
) -> list[dict]:
    safe_limit = max(1, min(300, int(limit or 100)))
    safe_offset = max(0, int(offset or 0))
    safe_event_type = clean_limited_text(event_type, 80).strip()
    safe_status = clean_limited_text(status, 80).strip()
    safe_contact = clean_limited_text(contact, 160).strip().lower()
    where: list[str] = []
    params: list[Any] = []
    if safe_event_type and safe_event_type != "all":
        where.append("event_type = ?")
        params.append(safe_event_type)
    if safe_status and safe_status != "all":
        where.append("status = ?")
        params.append(safe_status)
    if safe_contact:
        where.append(
            """
            (
                LOWER(COALESCE(email, '')) LIKE ?
                OR LOWER(COALESCE(phone, '')) LIKE ?
                OR CAST(COALESCE(user_id, '') AS TEXT) = ?
            )
            """
        )
        params.extend([f"%{safe_contact}%", f"%{safe_contact}%", safe_contact])
    where_sql = ("WHERE " + " AND ".join(where)) if where else ""
    with db() as conn:
        rows = conn.execute(
            f"""
            SELECT *
            FROM auth_events
            {where_sql}
            ORDER BY id DESC
            LIMIT ? OFFSET ?
            """,
            (*params, safe_limit, safe_offset),
        ).fetchall()
    events = []
    for row in rows:
        details = {}
        try:
            details = json.loads(row["details_json"] or "{}")
        except Exception:
            details = {}
        events.append(
            {
                "id": int(row["id"]),
                "userId": row["user_id"],
                "email": row["email"],
                "phone": row["phone"],
                "eventType": row["event_type"],
                "status": row["status"],
                "requestIp": row["request_ip"],
                "userAgent": row["user_agent"],
                "details": sanitize_monitoring_details(details),
                "createdAt": row["created_at"],
            }
        )
    return events


@app.on_event("startup")
def on_startup() -> None:
    global ADMIN_TOKEN
    init_db()
    seed_default_monitoring_targets()
    seed_default_feature_flags_and_runbooks()
    backfill_support_report_workflow_fields()
    backfill_expired_non_paid_subscriptions()
    ensure_subscription_for_existing_users()
    ADMIN_TOKEN = ensure_admin_token()


@app.get("/healthz")
def healthz():
    payment_ready = yookassa_payment_readiness()["productionReady"]
    email_ready = email_confirmation_readiness()["productionReady"]
    sms_ready = sms_confirmation_readiness()["productionReady"]
    auth_code_ready = auth_code_readiness()["productionReady"]
    user_auth_ready = user_auth_flow_readiness()["productionReady"]
    return {
        "ok": True,
        "service": APP_TITLE,
        "version": APP_VERSION,
        "subscriptionEnforced": ENFORCE_SUBSCRIPTION_ACCESS,
        "autoReplaceOldestDeviceOnLimit": AUTO_REPLACE_OLDEST_DEVICE_ON_LIMIT,
        "paymentsProductionReady": payment_ready,
        "emailConfirmationRequired": EMAIL_CONFIRMATION_REQUIRED,
        "emailProductionReady": email_ready,
        "smsProductionReady": sms_ready,
        "authCodeProductionReady": auth_code_ready,
        "userAuthFlowProductionReady": user_auth_ready,
    }


@app.get("/api/v1/meta")
def api_meta():
    return {
        "ok": True,
        "serverTime": utc_now_iso(),
        "apiVersion": APP_VERSION,
        "defaultServer": {
            "id": "intelligent_smew",
            "name": "Netherlands #1",
            "country": "NL",
            "endpoint": f"{WG_ENDPOINT_HOST}:{WG_ENDPOINT_PORT}",
        },
    }


@app.get("/api/v1/bootstrap/windows")
def windows_public_bootstrap(currentVersion: Optional[str] = None):
    catalog = build_server_catalog()
    update_manifest = build_windows_update_manifest(currentVersion)
    auth_codes = auth_code_readiness()
    return {
        "ok": True,
        "serverTime": utc_now_iso(),
        "apiVersion": APP_VERSION,
        "brand": {
            "name": "Green VPN",
            "platform": "windows",
        },
        "auth": {
            "primaryMethod": "phone_code",
            "fallbackMethod": "email_code",
            "challengeEndpoints": {
                "start": "/api/v1/auth/challenge/start",
                "verify": "/api/v1/auth/challenge/verify",
            },
            "methods": [
                {
                    "code": "phone_code",
                    "title": "Телефон",
                    "subtitle": "Вход или регистрация по одноразовому SMS-коду.",
                    "available": sms_sender_configured() or DEV_AUTH_CODES,
                    "productionReady": sms_confirmation_readiness()["productionReady"],
                },
                {
                    "code": "email_code",
                    "title": "Email",
                    "subtitle": "Запасной вход или регистрация по одноразовому коду из письма.",
                    "available": email_sender_configured() or DEV_AUTH_CODES,
                    "productionReady": email_confirmation_readiness()["productionReady"],
                },
                {
                    "code": "email_password",
                    "title": "Email и пароль",
                    "subtitle": "Legacy-вход для существующих аккаунтов.",
                    "available": True,
                    "productionReady": True,
                },
            ],
            "codeTtlMinutes": auth_codes["ttlMinutes"],
            "resendCooldownSeconds": auth_codes["resendCooldownSeconds"],
        },
        "update": update_manifest,
        "serverCatalog": catalog,
        "support": {
            "reportUploadEnabled": True,
            "reportFormat": "GVPN1",
        },
        "apiBaseUrls": SERVER_CATALOG_API_BASE_URLS,
    }


@app.get("/payment/return", response_class=HTMLResponse)
def payment_return_page():
    return """
<!doctype html>
<html lang="ru">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Green VPN - оплата</title>
  <style>
    :root { color-scheme: light; font-family: "Segoe UI", Arial, sans-serif; }
    body {
      margin: 0;
      min-height: 100vh;
      display: grid;
      place-items: center;
      background: linear-gradient(135deg, #f7fbf8, #e9f8f0);
      color: #101828;
    }
    .card {
      width: min(520px, calc(100vw - 32px));
      box-sizing: border-box;
      padding: 28px;
      border: 1px solid rgba(18, 163, 111, .18);
      border-radius: 28px;
      background: rgba(255, 255, 255, .92);
      box-shadow: 0 22px 54px rgba(8, 120, 93, .13);
    }
    .mark {
      width: 54px;
      height: 54px;
      border-radius: 18px;
      display: grid;
      place-items: center;
      background: #e7f7ef;
      color: #12a36f;
      font-size: 28px;
      font-weight: 900;
    }
    h1 { margin: 18px 0 8px; font-size: 28px; }
    p { margin: 0 0 14px; color: #667085; line-height: 1.5; font-weight: 600; }
    .hint {
      margin-top: 18px;
      padding: 14px;
      border-radius: 16px;
      background: #e7f7ef;
      color: #08785d;
      font-weight: 800;
    }
  </style>
</head>
<body>
  <main class="card">
    <div class="mark">●</div>
    <h1>Оплата обрабатывается</h1>
    <p>Можно вернуться в Green VPN. Приложение само проверит статус заказа и активирует тариф после подтверждения оплаты.</p>
    <p>Если тариф не активировался сразу, подожди несколько секунд или нажми "Проверить оплату" в приложении.</p>
    <div class="hint">Окно браузера можно закрыть.</div>
  </main>
</body>
</html>
"""


def _legal_escape(value: Any) -> str:
    return html.escape(str(value or ""), quote=True)


def _legal_owner_inn_text() -> str:
    return LEGAL_OWNER_INN if LEGAL_OWNER_INN else "будет указан владельцем перед отправкой анкеты"


def _legal_shell(title: str, body: str, description: str = "") -> str:
    safe_title = _legal_escape(title)
    safe_description = _legal_escape(description or title)
    site_url = _legal_escape(PUBLIC_SITE_URL or "https://api.greenvpn.pro")
    contact_email = _legal_escape(LEGAL_CONTACT_EMAIL or "support@greenvpn.pro")
    return f"""<!doctype html>
<html lang="ru">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>{safe_title} - Green VPN</title>
  <meta name="description" content="{safe_description}">
  <style>
    :root {{
      color-scheme: light;
      --green: #16a36f;
      --green-dark: #08785d;
      --ink: #10201b;
      --muted: #60716b;
      --line: #d9e7df;
      --soft: #effaf4;
      --blue: #2563eb;
      font-family: "Segoe UI", Arial, sans-serif;
    }}
    * {{ box-sizing: border-box; }}
    body {{
      margin: 0;
      background: #f7fbf8;
      color: var(--ink);
      line-height: 1.55;
    }}
    a {{ color: var(--green-dark); font-weight: 700; text-decoration: none; }}
    header {{
      border-bottom: 1px solid var(--line);
      background: #ffffff;
    }}
    .wrap {{
      width: min(1080px, calc(100vw - 32px));
      margin: 0 auto;
    }}
    .nav {{
      min-height: 68px;
      display: flex;
      align-items: center;
      justify-content: space-between;
      gap: 20px;
    }}
    .brand {{
      display: flex;
      align-items: center;
      gap: 12px;
      font-size: 21px;
      font-weight: 900;
      letter-spacing: 0;
    }}
    .mark {{
      width: 38px;
      height: 38px;
      border-radius: 12px;
      background: var(--green);
      color: #fff;
      display: grid;
      place-items: center;
      font-size: 18px;
      font-weight: 900;
    }}
    nav {{
      display: flex;
      align-items: center;
      gap: 14px;
      flex-wrap: wrap;
      font-size: 14px;
    }}
    main {{ padding: 38px 0 54px; }}
    h1 {{
      margin: 0 0 14px;
      font-size: clamp(32px, 4vw, 52px);
      line-height: 1.04;
      letter-spacing: 0;
    }}
    h2 {{
      margin: 34px 0 14px;
      font-size: 26px;
      letter-spacing: 0;
    }}
    h3 {{ margin: 24px 0 8px; font-size: 18px; }}
    p {{ margin: 0 0 12px; color: var(--muted); }}
    ul {{ margin: 0 0 18px; padding-left: 20px; color: var(--muted); }}
    li {{ margin: 6px 0; }}
    .hero {{
      padding: 44px 0 28px;
      border-bottom: 1px solid var(--line);
      background: linear-gradient(135deg, #ffffff, #effaf4);
    }}
    .hero p {{ max-width: 760px; font-size: 18px; }}
    .badges {{
      display: flex;
      gap: 10px;
      flex-wrap: wrap;
      margin-top: 22px;
    }}
    .badge {{
      padding: 8px 12px;
      border-radius: 999px;
      background: #ffffff;
      border: 1px solid var(--line);
      color: var(--green-dark);
      font-weight: 800;
      font-size: 14px;
    }}
    .actions {{
      display: flex;
      flex-wrap: wrap;
      gap: 12px;
      margin: 24px 0 4px;
    }}
    .button {{
      display: inline-flex;
      align-items: center;
      justify-content: center;
      min-height: 44px;
      padding: 10px 16px;
      border-radius: 8px;
      background: var(--green);
      color: #ffffff;
      border: 1px solid var(--green);
      font-weight: 900;
    }}
    .button.secondary {{
      background: #ffffff;
      color: var(--green-dark);
      border-color: var(--line);
    }}
    .button.disabled {{
      background: #e8f0ec;
      color: #74847e;
      border-color: #d4e0da;
      cursor: default;
    }}
    .grid {{
      display: grid;
      grid-template-columns: repeat(auto-fit, minmax(220px, 1fr));
      gap: 14px;
      margin: 18px 0 24px;
    }}
    .card {{
      padding: 20px;
      border: 1px solid var(--line);
      border-radius: 8px;
      background: #ffffff;
    }}
    .price {{
      margin: 12px 0 6px;
      color: var(--green-dark);
      font-size: 30px;
      line-height: 1;
      font-weight: 900;
    }}
    .note {{
      padding: 16px;
      border: 1px solid #bfe8d2;
      border-radius: 8px;
      background: var(--soft);
      color: var(--green-dark);
      font-weight: 700;
    }}
    .legal-table {{
      width: 100%;
      border-collapse: collapse;
      margin: 12px 0 22px;
      background: #fff;
      border: 1px solid var(--line);
      border-radius: 8px;
      overflow: hidden;
    }}
    .legal-table th, .legal-table td {{
      padding: 12px 14px;
      border-bottom: 1px solid var(--line);
      text-align: left;
      vertical-align: top;
    }}
    .legal-table th {{
      width: 260px;
      color: var(--ink);
      background: #f2f8f5;
    }}
    footer {{
      padding: 24px 0;
      border-top: 1px solid var(--line);
      color: var(--muted);
      background: #ffffff;
      font-size: 14px;
    }}
    @media (max-width: 720px) {{
      .nav {{ align-items: flex-start; flex-direction: column; padding: 16px 0; }}
      .legal-table th, .legal-table td {{ display: block; width: 100%; }}
    }}
  </style>
</head>
<body>
  <header>
    <div class="wrap nav">
      <a class="brand" href="/">
        <span class="mark">G</span>
        <span>Green VPN</span>
      </a>
      <nav>
        <a href="/#download">Скачать</a>
        <a href="/#plans">Тарифы</a>
        <a href="/legal/requisites">Реквизиты</a>
        <a href="/legal/offer">Оферта</a>
        <a href="/legal/privacy">Конфиденциальность</a>
        <a href="/legal/refunds">Возвраты</a>
      </nav>
    </div>
  </header>
  {body}
  <footer>
    <div class="wrap">
      Green VPN. Сайт: <a href="{site_url}">{site_url}</a>. Поддержка: <a href="mailto:{contact_email}">{contact_email}</a>.
    </div>
  </footer>
</body>
</html>"""


def _public_download_target(value: str) -> str:
    url = (value or "").strip()
    if not url:
        return ""
    parsed = urllib.parse.urlparse(url)
    if parsed.scheme not in {"http", "https"} or not parsed.netloc:
        return ""
    return url


def _download_card(platform: str, title: str, text: str, href: str, ready: bool) -> str:
    safe_platform = _legal_escape(platform)
    safe_title = _legal_escape(title)
    safe_text = _legal_escape(text)
    safe_href = _legal_escape(href)
    button_class = "button" if ready else "button secondary"
    return f"""
        <div class="card">
          <h3>{safe_title}</h3>
          <p>{safe_text}</p>
          <p><a class="{button_class}" href="{safe_href}">{safe_platform}</a></p>
        </div>
"""


def _public_download_cards() -> str:
    windows_ready = bool(_public_download_target(PUBLIC_WINDOWS_DOWNLOAD_URL))
    android_ready = bool(_public_download_target(PUBLIC_ANDROID_DOWNLOAD_URL))
    ios_ready = bool(_public_download_target(PUBLIC_IOS_DOWNLOAD_URL))
    return "".join(
        [
            _download_card(
                "Скачать для Windows",
                "Windows",
                (
                    "Основное приложение Green VPN для компьютера."
                    if windows_ready
                    else "Windows-приложение будет опубликовано на этой странице для первых пользователей."
                ),
                "/download/windows",
                True,
            ),
            _download_card(
                "Скачать для Android",
                "Android",
                (
                    "Мобильное приложение подключается к той же учетной записи Green VPN."
                    if android_ready
                    else "Android-версия запланирована и будет опубликована на этой странице."
                ),
                "/download/android",
                android_ready,
            ),
            _download_card(
                "Скачать для iPhone и iPad",
                "iPhone и iPad",
                (
                    "Версия для iPhone и iPad подключается к той же учетной записи Green VPN."
                    if ios_ready
                    else "Версия для iPhone и iPad запланирована и будет опубликована на этой странице."
                ),
                "/download/ios",
                ios_ready,
            ),
        ]
    )


@app.get("/", response_class=HTMLResponse)
def public_landing_page():
    body = f"""
  <section class="hero">
    <div class="wrap">
      <h1>Green VPN</h1>
      <p>Приложение для защищенного и стабильного сетевого подключения. Green VPN шифрует соединение, помогает защищать данные в публичных сетях и повышать стабильность маршрута до поддерживаемых онлайн-сервисов, когда обычный путь провайдера работает нестабильно.</p>
      <div class="badges">
        <span class="badge">Защищенное подключение</span>
        <span class="badge">Windows-приложение</span>
        <span class="badge">Подписка от 149 ₽/мес</span>
        <span class="badge">Поддержка внутри сервиса</span>
      </div>
      <div class="actions">
        <a class="button" href="/download/windows">Скачать для Windows</a>
        <a class="button secondary" href="/#plans">Посмотреть тарифы</a>
      </div>
    </div>
  </section>
  <main class="wrap">
    <section id="download">
      <h2>Скачать приложение</h2>
      <div class="grid">
        {_public_download_cards()}
      </div>
      <p class="note">Ссылки на загрузку обновляются здесь по мере публикации версий приложения.</p>
    </section>
    <section>
      <h2>Что получает пользователь</h2>
      <div class="grid">
        <div class="card"><h3>Защита соединения</h3><p>Шифрование трафика между устройством пользователя и инфраструктурой Green VPN.</p></div>
        <div class="card"><h3>Стабильный маршрут</h3><p>Маршрутизация через выбранный сервер, когда прямое соединение провайдера нестабильно.</p></div>
        <div class="card"><h3>Простая установка</h3><p>Windows-приложение устанавливается одним файлом, вход выполняется по телефону, email-коду или паролю.</p></div>
        <div class="card"><h3>Поддержка</h3><p>Пользователь может отправить отчет в поддержку без раскрытия приватных ключей и технических секретов.</p></div>
      </div>
    </section>
    <section id="plans">
      <h2>Тарифы</h2>
      <div class="grid">
        <div class="card"><h3>Пробный</h3><div class="price">0 ₽</div><p>1-3 дня или небольшой лимит трафика для проверки установки и подключения.</p></div>
        <div class="card"><h3>Старт</h3><div class="price">149 ₽/мес</div><p>20 ГБ, 1 устройство. Для редкого использования и проверки сервиса.</p></div>
        <div class="card"><h3>Стандарт</h3><div class="price">299 ₽/мес</div><p>100 ГБ, 1 устройство. Основной тариф для повседневной защиты и стабильности подключения.</p></div>
        <div class="card"><h3>Плюс</h3><div class="price">449 ₽/мес</div><p>250 ГБ, 2 устройства. Для активного использования.</p></div>
        <div class="card"><h3>Максимум</h3><div class="price">699 ₽/мес</div><p>500 ГБ по правилам добросовестного использования, до 3 устройств.</p></div>
      </div>
      <p class="note">Платежи обрабатываются через подключенный платежный провайдер. После успешной оплаты тариф активируется автоматически по подтверждению платежа. Банковские карты не хранятся в Green VPN.</p>
    </section>
    <section>
      <h2>Как пользователь получает услугу</h2>
      <ul>
        <li>Скачивает и устанавливает приложение Green VPN.</li>
        <li>Регистрируется или входит в аккаунт.</li>
        <li>Выбирает тариф и оплачивает подписку.</li>
        <li>После подтверждения оплаты приложение получает рабочую конфигурацию и пользователь подключается к защищенному соединению.</li>
      </ul>
    </section>
    <section>
      <h2>Ограничения использования</h2>
      <p>Сервис не предназначен для нарушения законодательства, мошенничества, спама, атак, распространения вредоносного ПО или доступа к запрещенным материалам.</p>
    </section>
  </main>
"""
    return _legal_shell(
        "Green VPN - защищенное и стабильное подключение",
        body,
        "Green VPN - цифровая подписка на приложение для защищенного и стабильного сетевого подключения.",
    )


def _download_pending_page(title: str, body_text: str) -> HTMLResponse:
    body = f"""
  <main class="wrap">
    <section>
      <h1>{_legal_escape(title)}</h1>
      <p>{_legal_escape(body_text)}</p>
      <div class="actions">
        <a class="button secondary" href="/">Вернуться на сайт</a>
        <a class="button secondary" href="mailto:{_legal_escape(LEGAL_CONTACT_EMAIL)}">Написать в поддержку</a>
      </div>
      <p class="note">Мы обновляем эту страницу и сообщаем о публикации через поддержку Green VPN.</p>
    </section>
  </main>
"""
    return HTMLResponse(
        _legal_shell(title, body, f"{title} Green VPN"),
        status_code=200,
    )


@app.get("/download/windows")
def download_windows_page():
    url = _public_download_target(PUBLIC_WINDOWS_DOWNLOAD_URL)
    if url:
        return RedirectResponse(url, status_code=302)
    return _download_pending_page(
        "Green VPN для Windows",
        "Windows-приложение будет опубликовано на этой странице. Если вы хотите получить доступ одним из первых, напишите в поддержку Green VPN.",
    )


@app.get("/download/android")
def download_android_page():
    url = _public_download_target(PUBLIC_ANDROID_DOWNLOAD_URL)
    if url:
        return RedirectResponse(url, status_code=302)
    return _download_pending_page(
        "Green VPN для Android",
        "Android-версия запланирована. Она будет работать с той же учетной записью Green VPN, что и Windows-приложение.",
    )


@app.get("/download/ios")
def download_ios_page():
    url = _public_download_target(PUBLIC_IOS_DOWNLOAD_URL)
    if url:
        return RedirectResponse(url, status_code=302)
    return _download_pending_page(
        "Green VPN для iPhone и iPad",
        "Версия для iPhone и iPad запланирована. Она будет работать с той же учетной записью Green VPN.",
    )


@app.get("/legal/requisites", response_class=HTMLResponse)
def legal_requisites_page():
    owner = _legal_escape(LEGAL_OWNER_NAME)
    inn = _legal_escape(_legal_owner_inn_text())
    email = _legal_escape(LEGAL_CONTACT_EMAIL)
    notice = f"<p class=\"note\">{_legal_escape(LEGAL_NOTICE)}</p>" if LEGAL_NOTICE else ""
    body = f"""
  <main class="wrap">
    <h1>Реквизиты</h1>
    <p>Информация о владельце сервиса Green VPN для пользователей и платежного провайдера.</p>
    {notice}
    <table class="legal-table">
      <tr><th>Сервис</th><td>Green VPN</td></tr>
      <tr><th>Правовая форма</th><td>Самозанятый, плательщик налога на профессиональный доход</td></tr>
      <tr><th>Владелец</th><td>{owner}</td></tr>
      <tr><th>ИНН самозанятого</th><td>{inn}</td></tr>
      <tr><th>Email поддержки</th><td><a href="mailto:{email}">{email}</a></td></tr>
      <tr><th>Сайт</th><td><a href="{_legal_escape(PUBLIC_SITE_URL)}">{_legal_escape(PUBLIC_SITE_URL)}</a></td></tr>
      <tr><th>Услуга</th><td>Цифровая подписка на приложение Green VPN для защищенного сетевого подключения, шифрования интернет-трафика, защиты данных в публичных сетях и повышения стабильности соединения с поддерживаемыми онлайн-сервисами.</td></tr>
    </table>
    <p>Банковские карты и платежные данные пользователей обрабатываются платежным провайдером. Green VPN хранит только технический статус заказа, сумму, тариф и идентификаторы платежа, необходимые для активации подписки и поддержки.</p>
  </main>
"""
    return _legal_shell("Реквизиты", body, "Реквизиты Green VPN")


@app.get("/legal/offer", response_class=HTMLResponse)
def legal_offer_page():
    body = f"""
  <main class="wrap">
    <h1>Публичная оферта</h1>
    <p>Этот документ определяет условия подключения цифровой подписки Green VPN и использования сервиса пользователями.</p>
    <h2>1. Предмет</h2>
    <p>Владелец сервиса предоставляет пользователю доступ к приложению Green VPN и серверной инфраструктуре для защищенного и стабильного сетевого подключения в рамках выбранного тарифа.</p>
    <h2>2. Тарифы и оплата</h2>
    <p>Стоимость подписки указывается на сайте и в приложении до оплаты. Подписка активируется после успешного подтверждения платежа платежным провайдером.</p>
    <h2>3. Получение услуги</h2>
    <p>После оплаты пользователь входит в приложение, получает доступ к тарифу и может подключиться к защищенному соединению в пределах выбранных лимитов.</p>
    <h2>4. Ограничения</h2>
    <p>Пользователь обязуется не использовать сервис для незаконной деятельности, атак, спама, мошенничества, распространения вредоносного ПО или доступа к запрещенным материалам.</p>
    <h2>5. Качество услуги</h2>
    <p>Green VPN стремится поддерживать стабильность подключения, но не гарантирует доступность любого отдельного сайта, сервиса, маршрута, страны, провайдера или скорости в каждый момент времени.</p>
    <h2>6. Поддержка</h2>
    <p>Обращения принимаются по адресу <a href="mailto:{_legal_escape(LEGAL_CONTACT_EMAIL)}">{_legal_escape(LEGAL_CONTACT_EMAIL)}</a>.</p>
  </main>
"""
    return _legal_shell("Публичная оферта", body, "Публичная оферта Green VPN")


@app.get("/legal/privacy", response_class=HTMLResponse)
def legal_privacy_page():
    body = f"""
  <main class="wrap">
    <h1>Политика конфиденциальности</h1>
    <p>Green VPN обрабатывает данные, необходимые для регистрации, входа, оплаты, поддержки, безопасности и технической работы сервиса.</p>
    <h2>Какие данные используются</h2>
    <ul>
      <li>email, телефон или иной идентификатор аккаунта;</li>
      <li>статус подписки, тариф, платежный статус и сумма заказа;</li>
      <li>технические данные устройства и приложения, необходимые для подключения и поддержки;</li>
      <li>сообщения в поддержку и диагностические отчеты, если пользователь отправляет их добровольно.</li>
    </ul>
    <h2>Что не хранится</h2>
    <ul>
      <li>Green VPN не хранит номера банковских карт и CVV;</li>
      <li>Green VPN не хранит пароли в открытом виде;</li>
      <li>Green VPN не публикует приватные WireGuard-ключи и не записывает их в репозиторий.</li>
    </ul>
    <h2>Платежи</h2>
    <p>Платежные данные обрабатываются YooKassa или другим подключенным платежным провайдером. Green VPN получает только статус платежа, сумму, валюту и технические идентификаторы, необходимые для активации тарифа.</p>
  </main>
"""
    return _legal_shell("Политика конфиденциальности", body, "Политика конфиденциальности Green VPN")


@app.get("/legal/acceptable-use", response_class=HTMLResponse)
def legal_acceptable_use_page():
    body = """
  <main class="wrap">
    <h1>Правила использования</h1>
    <p>Green VPN предназначен для защищенного и стабильного сетевого подключения. Пользователь обязан соблюдать законодательство и правила выбранного тарифа.</p>
    <h2>Запрещено</h2>
    <ul>
      <li>использовать сервис для спама, мошенничества, атак или вредоносного ПО;</li>
      <li>нарушать права третьих лиц;</li>
      <li>перепродавать доступ без письменного разрешения владельца сервиса;</li>
      <li>создавать чрезмерную нагрузку на инфраструктуру в обход правил тарифа;</li>
      <li>использовать сервис для доступа к запрещенным материалам или иной незаконной деятельности.</li>
    </ul>
    <h2>Правила добросовестного использования</h2>
    <p>На тарифах с большим лимитом трафика Green VPN может применять fair-use правила, чтобы один пользователь не ухудшал качество сервиса для остальных.</p>
  </main>
"""
    return _legal_shell("Правила использования", body, "Правила использования Green VPN")


@app.get("/legal/refunds", response_class=HTMLResponse)
def legal_refunds_page():
    body = f"""
  <main class="wrap">
    <h1>Возвраты</h1>
    <p>Пользователь может обратиться за возвратом, если оплата прошла ошибочно, тариф не активировался или сервис технически недоступен по причинам на стороне Green VPN.</p>
    <h2>Как запросить возврат</h2>
    <p>Напишите в поддержку: <a href="mailto:{_legal_escape(LEGAL_CONTACT_EMAIL)}">{_legal_escape(LEGAL_CONTACT_EMAIL)}</a>. Укажите email/телефон аккаунта, дату платежа и краткое описание проблемы. Не отправляйте данные банковской карты.</p>
    <h2>Сроки</h2>
    <p>Обращение рассматривается в разумный срок. Если возврат одобрен, деньги возвращаются через платежного провайдера тем способом, которым была выполнена оплата, если это технически возможно.</p>
  </main>
"""
    return _legal_shell("Возвраты", body, "Правила возврата Green VPN")


@app.get("/api/v1/updates/windows")
def windows_update_manifest(
    currentVersion: Optional[str] = None,
    clientId: Optional[str] = None,
):
    return {
        "ok": True,
        "manifest": build_windows_update_manifest(
            current_version=currentVersion,
            client_id=clientId,
        ),
    }


@app.get("/api/v1/updates/manifest")
def update_manifest(
    platform: str = "windows",
    channel: str = "stable",
    currentVersion: Optional[str] = None,
    clientId: Optional[str] = None,
):
    return {
        "ok": True,
        "manifest": build_update_manifest(
            platform=platform,
            channel=channel,
            current_version=currentVersion,
            client_id=clientId,
        ),
    }


@app.get("/api/v1/catalog/servers")
def server_catalog():
    return {
        "ok": True,
        "catalog": build_server_catalog(),
    }


@app.get("/api/v1/monitoring/status")
def monitoring_status():
    return build_monitoring_status()


@app.get("/api/v1/monitoring/services")
def monitoring_services():
    return build_service_availability_status()


@app.get("/api/v1/catalog/tariffs")
def tariff_catalog():
    return {
        "ok": True,
        "catalog": build_tariff_catalog(),
    }


@app.post("/api/v1/auth/register")
def auth_register(payload: RegisterIn):
    email = payload.email.strip().lower()
    password = payload.password

    if "@" not in email:
        raise HTTPException(status_code=400, detail="Invalid email.")
    if len(password) < 6:
        raise HTTPException(status_code=400, detail="Password too short.")

    with db() as conn:
        exists = conn.execute(
            "SELECT id FROM users WHERE email = ?",
            (email,),
        ).fetchone()

        if exists is not None:
            raise HTTPException(status_code=409, detail="User already exists.")

        conn.execute(
            "INSERT INTO users(email, password_hash, created_at) VALUES (?, ?, ?)",
            (email, hash_password(password), utc_now_iso()),
        )
        user = conn.execute(
            """
            SELECT
                id,
                email,
                email_verified,
                email_verified_at,
                phone,
                phone_verified,
                phone_verified_at
            FROM users
            WHERE email = ?
            """,
            (email,),
        ).fetchone()

        create_trial_subscription(conn, user["id"])
        conn.commit()

    confirmation_token = create_email_confirmation(int(user["id"]), user["email"])
    delivery = send_or_queue_email_confirmation(
        int(user["id"]),
        user["email"],
        confirmation_token,
    )
    token = issue_token(user["id"])
    response = auth_session_payload(user, token)
    response["emailConfirmationDeliveryStatus"] = delivery["deliveryStatus"]
    return response


@app.post("/api/v1/auth/login")
def auth_login(payload: LoginIn):
    email = payload.email.strip().lower()
    password = payload.password

    with db() as conn:
        user = conn.execute(
            """
            SELECT
                id,
                email,
                password_hash,
                email_verified,
                email_verified_at,
                phone,
                phone_verified,
                phone_verified_at
            FROM users
            WHERE email = ?
            """,
            (email,),
        ).fetchone()

    if user is None or not verify_password(password, user["password_hash"]):
        raise HTTPException(status_code=401, detail="Invalid credentials.")

    token = issue_token(user["id"])
    return auth_session_payload(user, token)


def normalize_auth_challenge_method(
    method: Optional[str],
    email: Optional[str],
    phone: Optional[str],
) -> str:
    candidate = clean_limited_text(method, 40).strip().lower().replace("-", "_")
    if candidate in {"phone", "sms", "phone_sms", "phone_code"}:
        return "phone_sms"
    if candidate in {"email", "email_code", "mail"}:
        return "email_code"
    if phone and str(phone).strip():
        return "phone_sms"
    if email and str(email).strip():
        return "email_code"
    raise HTTPException(status_code=400, detail="Challenge method is required.")


@app.post("/api/v1/auth/challenge/start")
def auth_challenge_start(payload: AuthChallengeStartIn, request: Request):
    method = normalize_auth_challenge_method(payload.method, payload.email, payload.phone)
    if method == "phone_sms":
        result = auth_phone_login_start(
            PhoneLoginStartIn(phone=payload.phone or ""),
            request,
        )
        result["challengeMethod"] = "phone_sms"
        result["primary"] = True
        result["channel"] = "sms"
        return result

    result = auth_email_code_start(
        EmailCodeStartIn(email=payload.email or ""),
        request,
    )
    result["challengeMethod"] = "email_code"
    result["primary"] = False
    result["channel"] = "email"
    return result


@app.post("/api/v1/auth/challenge/verify")
def auth_challenge_verify(payload: AuthChallengeVerifyIn, request: Request):
    method = normalize_auth_challenge_method(payload.method, payload.email, payload.phone)
    if method == "phone_sms":
        result = auth_phone_login_verify(
            PhoneLoginVerifyIn(
                phone=payload.phone or "",
                code=payload.code,
                deviceUid=payload.deviceUid,
                deviceName=payload.deviceName,
                platform=payload.platform,
                appVersion=payload.appVersion,
            ),
            request,
        )
        result["challengeMethod"] = "phone_sms"
        result["primary"] = True
        return result

    result = auth_email_code_verify(
        EmailCodeVerifyIn(
            email=payload.email or "",
            code=payload.code,
            deviceUid=payload.deviceUid,
            deviceName=payload.deviceName,
            platform=payload.platform,
            appVersion=payload.appVersion,
        ),
        request,
    )
    result["challengeMethod"] = "email_code"
    result["primary"] = False
    return result


@app.post("/api/v1/auth/email/code/start")
def auth_email_code_start(payload: EmailCodeStartIn, request: Request):
    email = normalize_email(payload.email)
    user, created = ensure_user_for_email_code(email)
    ensure_email_code_resend_allowed(email)
    code_id, code = create_email_login_code(int(user["id"]), email)
    delivery = send_or_queue_email_login_code(int(user["id"]), email, code_id, code)
    log_auth_event(
        "email_code_start",
        "created",
        request=request,
        user_id=int(user["id"]),
        email=email,
        details={
            "createdUser": created,
            "deliveryStatus": delivery["deliveryStatus"],
            "outboxId": delivery.get("outboxId"),
        },
    )
    response = {
        "ok": True,
        "email": email,
        "createdUser": created,
        "deliveryStatus": delivery["deliveryStatus"],
        "deliveryReady": email_sender_configured(),
        "ttlMinutes": AUTH_CODE_TTL_MINUTES,
        "resendCooldownSeconds": AUTH_CODE_RESEND_COOLDOWN_SECONDS,
        "message": "Код входа отправлен на email.",
    }
    if DEV_AUTH_CODES:
        response["devCode"] = code
    return response


@app.post("/api/v1/auth/email/code/verify")
def auth_email_code_verify(payload: EmailCodeVerifyIn, request: Request):
    email = normalize_email(payload.email)
    result = consume_email_login_code(email, payload.code)
    if not result.get("ok"):
        status = str(result.get("status") or "failed")
        log_auth_event(
            "email_code_verify",
            status,
            request=request,
            email=email,
        )
        raise HTTPException(
            status_code=429 if status == "too_many_attempts" else 401,
            detail=status or "Invalid code.",
        )

    user = result["user"]
    token = issue_token(int(user["id"]))
    log_auth_event(
        "email_code_verify",
        "verified",
        request=request,
        user_id=int(user["id"]),
        email=email,
        details={
            "deviceUid": payload.deviceUid,
            "platform": payload.platform,
            "appVersion": payload.appVersion,
        },
    )
    response = auth_session_payload(user, token)
    response["loginMethod"] = "email_code"
    response["message"] = "Вход выполнен по коду из письма."
    return response


@app.post("/api/v1/auth/phone/login/start")
def auth_phone_login_start(payload: PhoneLoginStartIn, request: Request):
    phone = normalize_phone(payload.phone)
    user, created = ensure_user_for_phone_code(phone)
    ensure_sms_resend_allowed(int(user["id"]))
    code = create_phone_confirmation(int(user["id"]), phone)
    delivery = send_or_queue_phone_confirmation(int(user["id"]), phone, code)
    log_auth_event(
        "phone_code_start",
        "created",
        request=request,
        user_id=int(user["id"]),
        phone=phone,
        details={
            "createdUser": created,
            "deliveryStatus": delivery["deliveryStatus"],
            "outboxId": delivery.get("outboxId"),
        },
    )
    response = {
        "ok": True,
        "phone": phone,
        "createdUser": created,
        "deliveryStatus": delivery["deliveryStatus"],
        "deliveryReady": sms_sender_configured(),
        "provider": SMS_PROVIDER,
        "ttlMinutes": SMS_CONFIRMATION_TTL_MINUTES,
        "resendCooldownSeconds": SMS_RESEND_COOLDOWN_SECONDS,
        "message": "Код входа отправлен на телефон.",
    }
    if DEV_AUTH_CODES:
        response["devCode"] = code
    return response


@app.post("/api/v1/auth/phone/login/verify")
def auth_phone_login_verify(payload: PhoneLoginVerifyIn, request: Request):
    phone = normalize_phone(payload.phone)
    user, _ = ensure_user_for_phone_code(phone)
    result = consume_phone_confirmation_code(int(user["id"]), phone, payload.code)
    if not result.get("ok"):
        status = str(result.get("status") or "failed")
        log_auth_event(
            "phone_code_verify",
            status,
            request=request,
            user_id=int(user["id"]),
            phone=phone,
        )
        raise HTTPException(
            status_code=429 if status == "too_many_attempts" else 401,
            detail=status or "Invalid code.",
        )

    with db() as conn:
        fresh_user = conn.execute(
            """
            SELECT
                id,
                email,
                email_verified,
                email_verified_at,
                phone,
                phone_verified,
                phone_verified_at
            FROM users
            WHERE id = ?
            """,
            (int(user["id"]),),
        ).fetchone()
    token = issue_token(int(fresh_user["id"]))
    log_auth_event(
        "phone_code_verify",
        "verified",
        request=request,
        user_id=int(fresh_user["id"]),
        phone=phone,
        details={
            "deviceUid": payload.deviceUid,
            "platform": payload.platform,
            "appVersion": payload.appVersion,
        },
    )
    response = auth_session_payload(fresh_user, token)
    response["loginMethod"] = "phone_code"
    response["message"] = "Вход выполнен по коду из SMS."
    return response


@app.get("/api/v1/me")
def me(authorization: Optional[str] = Header(default=None)):
    user = get_user_by_token(authorization)
    return {
        "id": user["id"],
        "email": user["email"],
        "emailVerified": user_email_verified(user),
        "emailConfirmationRequired": EMAIL_CONFIRMATION_REQUIRED,
        "phone": user["phone"],
        "phoneVerified": user_phone_verified(user),
        "phoneVerifiedAt": user["phone_verified_at"],
    }


@app.get("/api/v1/auth/email/status")
def auth_email_status(authorization: Optional[str] = Header(default=None)):
    user = get_user_by_token(authorization)
    return {
        "ok": True,
        "email": user["email"],
        "emailVerified": user_email_verified(user),
        "emailVerifiedAt": user["email_verified_at"],
        "emailConfirmationRequired": EMAIL_CONFIRMATION_REQUIRED,
        "deliveryReady": email_sender_configured(),
        "latestConfirmation": latest_email_confirmation_status(int(user["id"])),
    }


@app.post("/api/v1/auth/email/resend")
def auth_email_resend(authorization: Optional[str] = Header(default=None)):
    user = get_user_by_token(authorization)
    if user_email_verified(user):
        return {
            "ok": True,
            "email": user["email"],
            "emailVerified": True,
            "emailConfirmationRequired": EMAIL_CONFIRMATION_REQUIRED,
            "deliveryStatus": "already_verified",
        }

    confirmation_token = create_email_confirmation(int(user["id"]), user["email"])
    delivery = send_or_queue_email_confirmation(
        int(user["id"]),
        user["email"],
        confirmation_token,
    )
    return {
        "ok": True,
        "email": user["email"],
        "emailVerified": False,
        "emailConfirmationRequired": EMAIL_CONFIRMATION_REQUIRED,
        "deliveryStatus": delivery["deliveryStatus"],
        "latestConfirmation": latest_email_confirmation_status(int(user["id"])),
    }


def email_verify_html(title: str, message: str, ok: bool) -> str:
    color = "#12a36f" if ok else "#d94141"
    bg = "#e7f7ef" if ok else "#ffe8e8"
    return f"""
<!doctype html>
<html lang="ru">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <title>{title}</title>
  <style>
    body {{
      margin: 0;
      min-height: 100vh;
      display: grid;
      place-items: center;
      font-family: Arial, sans-serif;
      background: linear-gradient(135deg, #f4fbf7, #eef7ff);
      color: #101828;
    }}
    .card {{
      width: min(520px, calc(100vw - 32px));
      padding: 34px;
      border-radius: 28px;
      border: 1px solid rgba(18, 163, 111, .18);
      background: rgba(255, 255, 255, .94);
      box-shadow: 0 22px 54px rgba(8, 120, 93, .13);
    }}
    .mark {{
      width: 54px;
      height: 54px;
      border-radius: 18px;
      display: grid;
      place-items: center;
      background: {bg};
      color: {color};
      font-size: 28px;
      font-weight: 900;
    }}
    h1 {{ margin: 18px 0 8px; font-size: 28px; }}
    p {{ margin: 0 0 14px; color: #667085; line-height: 1.5; font-weight: 600; }}
    .hint {{
      margin-top: 18px;
      padding: 14px;
      border-radius: 16px;
      background: #e7f7ef;
      color: #08785d;
      font-weight: 800;
    }}
  </style>
</head>
<body>
  <main class="card">
    <div class="mark">●</div>
    <h1>{title}</h1>
    <p>{message}</p>
    <div class="hint">Можно вернуться в Green VPN.</div>
  </main>
</body>
</html>
"""


@app.get("/api/v1/auth/email/verify", response_class=HTMLResponse)
def auth_email_verify_get(token: str = ""):
    result = consume_email_confirmation_token(token)
    status = result.get("status")
    if result.get("ok"):
        return email_verify_html(
            "Почта подтверждена",
            "Аккаунт Green VPN теперь привязан к подтверждённому email.",
            True,
        )
    if status == "expired":
        return email_verify_html(
            "Ссылка истекла",
            "Открой Green VPN и запроси новое письмо подтверждения.",
            False,
        )
    return email_verify_html(
        "Ссылка недействительна",
        "Открой Green VPN и запроси новое письмо подтверждения.",
        False,
    )


@app.post("/api/v1/auth/email/verify")
def auth_email_verify_post(payload: EmailVerifyIn):
    result = consume_email_confirmation_token(payload.token)
    return result


@app.get("/api/v1/auth/phone/status")
def auth_phone_status(authorization: Optional[str] = Header(default=None)):
    user = get_user_by_token(authorization)
    return {
        "ok": True,
        "phone": user["phone"],
        "phoneVerified": user_phone_verified(user),
        "phoneVerifiedAt": user["phone_verified_at"],
        "deliveryReady": sms_sender_configured(),
        "provider": SMS_PROVIDER,
        "latestConfirmation": latest_phone_confirmation_status(int(user["id"])),
    }


@app.post("/api/v1/auth/phone/start")
def auth_phone_start(
    payload: PhoneStartIn,
    authorization: Optional[str] = Header(default=None),
):
    user = get_user_by_token(authorization)
    phone = normalize_phone(payload.phone)
    if user_phone_verified(user) and user["phone"] == phone:
        return {
            "ok": True,
            "phone": phone,
            "phoneVerified": True,
            "deliveryStatus": "already_verified",
        }

    ensure_sms_resend_allowed(int(user["id"]))
    code = create_phone_confirmation(int(user["id"]), phone)
    delivery = send_or_queue_phone_confirmation(int(user["id"]), phone, code)
    return {
        "ok": True,
        "phone": phone,
        "phoneVerified": False,
        "deliveryStatus": delivery["deliveryStatus"],
        "deliveryReady": sms_sender_configured(),
        "latestConfirmation": latest_phone_confirmation_status(int(user["id"])),
    }


@app.post("/api/v1/auth/phone/verify")
def auth_phone_verify(
    payload: PhoneVerifyIn,
    authorization: Optional[str] = Header(default=None),
):
    user = get_user_by_token(authorization)
    phone = normalize_phone(payload.phone)
    result = consume_phone_confirmation_code(int(user["id"]), phone, payload.code)
    return {
        **result,
        "phoneVerified": bool(result.get("ok")),
    }


@app.get("/api/v1/subscription/me")
def subscription_me(authorization: Optional[str] = Header(default=None)):
    user = get_user_by_token(authorization)
    sub = subscription_status(get_subscription_row(user["id"]))

    return {
        "email": user["email"],
        "planName": sub["planName"],
        "planCode": sub["planCode"],
        "maxDevices": sub["maxDevices"],
        "isActive": sub["isActive"],
        "expiresAt": sub["expiresAt"],
        "monthlyPriceRub": sub["monthlyPriceRub"],
        "autoRenew": sub["autoRenew"],
        "paymentMethodSaved": sub["paymentMethodSaved"],
        "selection": sub["selection"],
        "includedFeatures": sub["includedFeatures"],
    }


@app.post("/api/v1/subscription/quote")
def subscription_quote(payload: TariffSelectionIn):
    normalized = normalize_tariff_selection(payload)
    quote = quote_tariff(normalized)
    return {
        "ok": True,
        "catalog": build_tariff_catalog(),
        "selection": normalized,
        "quote": quote,
    }


@app.post("/api/v1/billing/orders")
def billing_create_order(
    payload: TariffSelectionIn,
    authorization: Optional[str] = Header(default=None),
):
    user = get_user_by_token(authorization)
    order = create_billing_order_for_user(user["id"], payload)
    return {
        "ok": True,
        "email": user["email"],
        "order": public_billing_order_status(order),
        "message": "Order created. Payment provider is not connected yet; activate it after payment confirmation.",
    }


@app.get("/api/v1/billing/orders")
def billing_list_my_orders(
    status: Optional[str] = None,
    authorization: Optional[str] = Header(default=None),
):
    user = get_user_by_token(authorization)
    return {
        "ok": True,
        "orders": list_billing_orders_for_user(user["id"], status=status),
    }


@app.get("/api/v1/billing/orders/{order_id}")
def billing_get_order(
    order_id: str,
    authorization: Optional[str] = Header(default=None),
):
    user = get_user_by_token(authorization)
    return {
        "ok": True,
        "order": get_billing_order_for_user(user["id"], order_id),
    }


@app.post("/api/v1/subscription/auto-renew/cancel")
def subscription_cancel_auto_renew(
    authorization: Optional[str] = Header(default=None),
):
    user = get_user_by_token(authorization)
    sub = cancel_auto_renew_for_user(user["id"])
    return {
        "ok": True,
        "subscription": sub,
        "message": "Auto-renewal disabled for this account.",
    }


@app.post("/api/v1/billing/yookassa/webhook")
async def billing_yookassa_webhook(request: Request):
    payload = await request.json()
    event = str(payload.get("event") or "")
    incoming = payload.get("object") if isinstance(payload.get("object"), dict) else {}
    payment = authoritative_yookassa_payment_for_webhook(incoming)
    order_id = yookassa_order_id_from_payment(payment) or yookassa_order_id_from_payment(incoming)

    if not order_id:
        return {"ok": True, "ignored": True, "reason": "missing_order_id"}

    payment_id = str(payment.get("id") or "")
    status = str(payment.get("status") or "")
    paid = payment.get("paid") is True

    if event == "payment.succeeded" or status == "succeeded" or paid:
        result = apply_yookassa_payment_update(order_id, payment)
        return {"ok": True, "event": event, **result}

    if event == "payment.canceled" or status == "canceled":
        result = apply_yookassa_payment_update(order_id, payment)
        return {"ok": True, "event": event, "orderId": order_id, **result}

    if payment_id:
        result = apply_yookassa_payment_update(order_id, payment)
        return {"ok": True, "event": event, "orderId": order_id, **result}

    return {"ok": True, "ignored": True, "event": event, "orderId": order_id}


@app.post("/api/v1/subscription/apply")
def subscription_apply(
    payload: TariffSelectionIn,
    authorization: Optional[str] = Header(default=None),
):
    get_user_by_token(authorization)
    raise HTTPException(
        status_code=402,
        detail="Direct tariff activation is disabled. Create a billing order and activate it after payment confirmation.",
    )


@app.post("/api/v1/client/bootstrap")
def client_bootstrap(
    payload: BootstrapIn,
    authorization: Optional[str] = Header(default=None),
):
    user = get_user_by_token(authorization)

    device = ensure_device_row(
        user_id=user["id"],
        device_uid=payload.deviceUid.strip(),
        device_name=payload.deviceName.strip() or "Windows device",
        platform=payload.platform.strip() or "windows",
        app_version=payload.appVersion.strip() or "0.1.0",
    )
    touch_device(device["device_uid"], config_issued=False)

    sub = subscription_status(get_subscription_row(user["id"]))

    with db() as conn:
        count = enforce_device_limit_for_current_device(
            conn,
            user_id=user["id"],
            current_device_uid=device["device_uid"],
            max_devices=sub["maxDevices"],
        )
        conn.commit()

    device_enabled = bool(device["is_enabled"])
    subscription_ok = sub["isActive"] or not ENFORCE_SUBSCRIPTION_ACCESS
    can_connect = subscription_ok and count <= sub["maxDevices"] and device_enabled

    reason = None
    if not subscription_ok:
        reason = "subscription_inactive"
    elif count > sub["maxDevices"]:
        reason = "device_limit_exceeded"
    elif not device_enabled:
        reason = "device_disabled"

    return {
        "ok": True,
        "canConnect": can_connect,
        "reason": reason,
        "device": {
            "deviceUid": device["device_uid"],
            "deviceName": device["device_name"],
            "platform": device["platform"],
            "appVersion": device["app_version"],
        },
        "subscription": sub,
        "server": {
            "id": "ams-1",
            "name": "Amsterdam #1",
            "endpoint": f"{WG_ENDPOINT_HOST}:{WG_ENDPOINT_PORT}",
        },
    }


@app.post("/api/v1/client/config")
def client_config(
    payload: ClientConfigIn,
    authorization: Optional[str] = Header(default=None),
):
    user = get_user_by_token(authorization)
    sub = require_active_subscription(user["id"])

    with db() as conn:
        device = conn.execute(
            "SELECT * FROM devices WHERE device_uid = ?",
            (payload.deviceUid.strip(),),
        ).fetchone()

    if device is None:
        raise HTTPException(status_code=404, detail="Device not found. Call bootstrap first.")

    if device["user_id"] != user["id"]:
        raise HTTPException(status_code=403, detail="Device belongs to another user.")

    if not bool(device["is_enabled"]):
        raise HTTPException(status_code=403, detail="Device disabled by admin.")

    with db() as conn:
        count = enforce_device_limit_for_current_device(
            conn,
            user_id=user["id"],
            current_device_uid=payload.deviceUid.strip(),
            max_devices=sub["maxDevices"],
        )
        conn.commit()

    if count > sub["maxDevices"]:
        raise HTTPException(status_code=403, detail="Device limit exceeded.")

    selected_server = find_catalog_server(payload.serverId)
    if payload.serverId and payload.serverId != "auto":
        if selected_server is None:
            raise HTTPException(status_code=400, detail="Unknown serverId.")
        if selected_server.get("available") is not True:
            raise HTTPException(status_code=409, detail="Selected server is unavailable.")

    support_refresh_requested = bool(device["support_config_refresh_requested_at"])
    refresh_result: Optional[dict] = None
    if support_refresh_requested:
        refresh_result = reissue_device_keys_and_ip(payload.deviceUid.strip())
        device = refresh_result["device"]
    else:
        device = ensure_device_keys_and_ip(payload.deviceUid.strip())

    client_public_key = device["client_public_key"]
    client_private_key = device["client_private_key"]
    preshared_key = device["preshared_key"]
    assigned_ip = device["assigned_ip"]

    upsert_peer_block_in_wg0(
        device_uid=device["device_uid"],
        public_key=client_public_key,
        psk=preshared_key,
        ip=assigned_ip,
    )
    apply_peer_live(
        public_key=client_public_key,
        psk=preshared_key,
        ip=assigned_ip,
    )
    support_refresh_applied = refresh_result is not None
    if support_refresh_applied:
        old_public_key = clean_limited_text(refresh_result.get("oldPublicKey"), 120).strip()
        if old_public_key and old_public_key != client_public_key:
            best_effort_remove_peer_live(old_public_key)
        refresh_reason = clean_limited_text(refresh_result.get("reason"), 500).strip()
        clear_support_config_refresh_after_issue(device["device_uid"], refresh_reason)
        write_admin_audit(
            "support_config_refresh_applied",
            "device",
            device["device_uid"],
            {
                "deviceUid": device["device_uid"],
                "requestedAt": refresh_result.get("requestedAt"),
                "requestedBy": refresh_result.get("requestedBy"),
                "reason": refresh_reason or "support_requested_config_refresh",
                "rotatedClientKeys": True,
            },
            actor="backend_config_fetch",
        )

    server_public_key = get_server_public_key()
    config_text = build_client_config(
        client_private_key=client_private_key,
        preshared_key=preshared_key,
        server_public_key=server_public_key,
        client_ip=assigned_ip,
    )
    touch_device(device["device_uid"], config_issued=True)

    return {
        "ok": True,
        "configText": config_text,
        "deviceUid": device["device_uid"],
        "assignedIp": assigned_ip,
        "endpoint": f"{WG_ENDPOINT_HOST}:{WG_ENDPOINT_PORT}",
        "serverId": selected_server["id"] if selected_server else "intelligent_smew",
        "supportConfigRefreshApplied": support_refresh_applied,
        "subscription": sub,
    }


@app.get("/api/v1/me/devices")
def me_devices(authorization: Optional[str] = Header(default=None)):
    user = get_user_by_token(authorization)
    return {
        "ok": True,
        "devices": list_user_devices(user["id"]),
    }


@app.post("/api/v1/support/reports")
def support_reports(
    payload: SupportReportIn,
    request: Request,
    authorization: Optional[str] = Header(default=None),
):
    user = get_user_by_token(authorization)
    report_code = validate_support_report_code(payload.report)
    summary = clean_limited_text(payload.summary, 1000)
    app_version = clean_limited_text(payload.appVersion, 80)
    device_uid = clean_limited_text(payload.deviceUid, 128)
    request_ip = request.client.host if request.client else ""
    user_agent = clean_limited_text(request.headers.get("user-agent"), 300)
    workflow = infer_support_report_workflow(summary, report_code)
    now = utc_now_iso()

    with db() as conn:
        cursor = conn.execute(
            """
            INSERT INTO support_reports(
                user_id, email, device_uid, app_version, summary, report_code,
                status, priority, category, triage_reason, sla_due_at,
                request_ip, user_agent, created_at, updated_at
            )
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            (
                int(user["id"]),
                user["email"],
                device_uid,
                app_version,
                summary,
                report_code,
                "new",
                workflow["priority"],
                workflow["category"],
                workflow["triageReason"],
                workflow["slaDueAt"],
                request_ip,
                user_agent,
                now,
                now,
            ),
        )
        conn.commit()
        report_id = int(cursor.lastrowid)

    return {
        "ok": True,
        "reportId": report_id,
        "status": "received",
        "message": "Отчёт отправлен в поддержку.",
    }


def db_scalar(
    conn: sqlite3.Connection,
    query: str,
    args: tuple = (),
    default=0,
):
    row = conn.execute(query, args).fetchone()
    if row is None:
        return default
    value = row[0] if not isinstance(row, sqlite3.Row) else row[0]
    return default if value is None else value


def db_count(
    conn: sqlite3.Connection,
    table: str,
    where: str = "",
    args: tuple = (),
) -> int:
    suffix = f" WHERE {where}" if where else ""
    return int(db_scalar(conn, f"SELECT COUNT(*) FROM {table}{suffix}", args, 0))


def db_sum(
    conn: sqlite3.Connection,
    table: str,
    column: str,
    where: str = "",
    args: tuple = (),
) -> int:
    suffix = f" WHERE {where}" if where else ""
    return int(db_scalar(conn, f"SELECT COALESCE(SUM({column}), 0) FROM {table}{suffix}", args, 0))


def db_group_counts(
    conn: sqlite3.Connection,
    table: str,
    column: str,
    where: str = "",
    args: tuple = (),
) -> dict:
    suffix = f" WHERE {where}" if where else ""
    rows = conn.execute(
        f"""
        SELECT COALESCE({column}, 'unknown') AS bucket, COUNT(*) AS cnt
        FROM {table}
        {suffix}
        GROUP BY COALESCE({column}, 'unknown')
        ORDER BY cnt DESC, bucket ASC
        """,
        args,
    ).fetchall()
    return {str(row["bucket"]): int(row["cnt"]) for row in rows}


def analytics_days(days: int = 14) -> list[str]:
    today = utc_now().date()
    return [
        (today - timedelta(days=offset)).isoformat()
        for offset in range(days - 1, -1, -1)
    ]


def daily_count_series(
    conn: sqlite3.Connection,
    table: str,
    created_column: str,
    *,
    days: int = 14,
    where: str = "",
    args: tuple = (),
) -> list[dict]:
    labels = analytics_days(days)
    suffix = f" AND {where}" if where else ""
    rows = conn.execute(
        f"""
        SELECT substr({created_column}, 1, 10) AS day, COUNT(*) AS cnt
        FROM {table}
        WHERE substr({created_column}, 1, 10) >= ?{suffix}
        GROUP BY substr({created_column}, 1, 10)
        """,
        (labels[0], *args),
    ).fetchall()
    values = {str(row["day"]): int(row["cnt"]) for row in rows}
    return [{"day": day, "value": values.get(day, 0)} for day in labels]


def daily_sum_series(
    conn: sqlite3.Connection,
    table: str,
    created_column: str,
    amount_column: str,
    *,
    days: int = 14,
    where: str = "",
    args: tuple = (),
) -> list[dict]:
    labels = analytics_days(days)
    suffix = f" AND {where}" if where else ""
    rows = conn.execute(
        f"""
        SELECT substr({created_column}, 1, 10) AS day, COALESCE(SUM({amount_column}), 0) AS total
        FROM {table}
        WHERE substr({created_column}, 1, 10) >= ?{suffix}
        GROUP BY substr({created_column}, 1, 10)
        """,
        (labels[0], *args),
    ).fetchall()
    values = {str(row["day"]): int(row["total"]) for row in rows}
    return [{"day": day, "value": values.get(day, 0)} for day in labels]


def analytics_percent(part: int, total: int) -> float:
    if total <= 0:
        return 0.0
    return round((part / total) * 100, 1)


def readiness_signal(readiness: dict) -> dict:
    summary = readiness.get("summary") or {}
    return {
        "ready": bool(readiness.get("ready") or readiness.get("productionReady")),
        "green": int(summary.get("green") or 0),
        "yellow": int(summary.get("yellow") or 0),
        "message": summary.get("message") or "",
    }


def build_admin_analytics_summary() -> dict:
    now = utc_now()
    now_iso = now.isoformat()
    since_24h = (now - timedelta(hours=24)).isoformat()
    since_7d = (now - timedelta(days=7)).isoformat()
    since_30d = (now - timedelta(days=30)).isoformat()
    expires_7d = (now + timedelta(days=7)).isoformat()

    readiness = build_product_readiness()
    with db() as conn:
        users_total = db_count(conn, "users")
        users_email_verified = db_count(conn, "users", "email_verified = 1")
        users_phone_verified = db_count(conn, "users", "phone_verified = 1")
        users_created_7d = db_count(conn, "users", "created_at >= ?", (since_7d,))
        users_created_30d = db_count(conn, "users", "created_at >= ?", (since_30d,))

        devices_total = db_count(conn, "devices")
        devices_enabled = db_count(conn, "devices", "is_enabled = 1")
        devices_disabled = max(0, devices_total - devices_enabled)
        devices_config_issued = db_count(conn, "devices", "last_config_at IS NOT NULL")
        devices_seen_7d = db_count(conn, "devices", "last_seen_at >= ?", (since_7d,))

        active_sub_where = "is_active = 1 AND (expires_at IS NULL OR expires_at > ?)"
        subs_total = db_count(conn, "subscriptions")
        subs_active = db_count(conn, "subscriptions", active_sub_where, (now_iso,))
        subs_trial = db_count(
            conn,
            "subscriptions",
            f"{active_sub_where} AND plan_code = 'trial'",
            (now_iso,),
        )
        subs_paid = db_count(
            conn,
            "subscriptions",
            f"{active_sub_where} AND plan_code != 'trial'",
            (now_iso,),
        )
        subs_inactive = max(0, subs_total - subs_active)
        subs_expires_7d = db_count(
            conn,
            "subscriptions",
            f"{active_sub_where} AND expires_at <= ?",
            (now_iso, expires_7d),
        )

        orders_total = db_count(conn, "billing_orders")
        orders_pending = db_count(conn, "billing_orders", "status = 'pending'")
        orders_paid = db_count(conn, "billing_orders", "status = 'paid'")
        orders_activated = db_count(conn, "billing_orders", "status = 'activated'")
        orders_failed = db_count(conn, "billing_orders", "status = 'failed'")
        orders_cancelled = db_count(conn, "billing_orders", "status = 'cancelled'")
        paid_status_where = "status IN ('paid', 'activated')"
        gross_revenue = db_sum(conn, "billing_orders", "amount_rub", paid_status_where)
        pending_revenue = db_sum(conn, "billing_orders", "amount_rub", "status = 'pending'")
        paid_30d = db_sum(
            conn,
            "billing_orders",
            "amount_rub",
            f"{paid_status_where} AND COALESCE(paid_at, activated_at, updated_at, created_at) >= ?",
            (since_30d,),
        )
        paid_orders_count = orders_paid + orders_activated
        avg_paid_order = round(gross_revenue / paid_orders_count, 2) if paid_orders_count else 0
        users_with_paid_orders = int(
            db_scalar(
                conn,
                f"SELECT COUNT(DISTINCT user_id) FROM billing_orders WHERE {paid_status_where}",
                (),
                0,
            )
        )

        support_total = db_count(conn, "support_reports")
        support_open = db_count(conn, "support_reports", "status NOT IN ('resolved', 'closed')")
        support_overdue = db_count(
            conn,
            "support_reports",
            "status NOT IN ('resolved', 'closed') AND sla_due_at IS NOT NULL AND sla_due_at < ?",
            (now_iso,),
        )
        support_first_response_missing = db_count(
            conn,
            "support_reports",
            "status NOT IN ('resolved', 'closed') AND first_response_at IS NULL",
        )
        support_created_7d = db_count(conn, "support_reports", "created_at >= ?", (since_7d,))
        support_resolved_7d = db_count(
            conn,
            "support_reports",
            "handled_at >= ? OR (updated_at >= ? AND status IN ('resolved', 'closed'))",
            (since_7d, since_7d),
        )

        incidents_total = db_count(conn, "admin_incidents")
        incidents_open = db_count(conn, "admin_incidents", "status != 'resolved'")
        incidents_critical_open = db_count(
            conn,
            "admin_incidents",
            "status != 'resolved' AND severity = 'critical'",
        )
        incidents_warning_open = db_count(
            conn,
            "admin_incidents",
            "status != 'resolved' AND severity IN ('high', 'medium')",
        )

        releases_total = db_count(conn, "app_releases")
        releases_published = db_count(conn, "app_releases", "status = 'published'")
        releases_draft = db_count(conn, "app_releases", "status = 'draft'")

        managed_servers_total = db_count(conn, "server_catalog_entries")
        managed_servers_active = db_count(conn, "server_catalog_entries", "is_active = 1")
        managed_servers_public_ready = db_count(
            conn,
            "server_catalog_entries",
            "is_active = 1 AND is_public = 1 AND status = 'healthy' AND client_config_profile != 'none'",
        )
        public_catalog = build_server_catalog()
        public_servers = public_catalog.get("servers") or []
        builtin_servers = [
            item for item in public_servers if not bool(item.get("managed"))
        ]
        health_observations_total = db_count(conn, "server_health_observations")
        health_observations_failed_24h = db_count(
            conn,
            "server_health_observations",
            "observed_at >= ? AND status IN ('degraded', 'down')",
            (since_24h,),
        )
        health_endpoints_observed = int(
            db_scalar(
                conn,
                "SELECT COUNT(DISTINCT endpoint_id) FROM server_health_observations",
                (),
                0,
            )
        )

        auth_events_24h = db_count(conn, "auth_events", "created_at >= ?", (since_24h,))
        auth_success_24h = db_count(
            conn,
            "auth_events",
            "created_at >= ? AND status IN ('success', 'sent', 'verified')",
            (since_24h,),
        )
        auth_failed_24h = db_count(
            conn,
            "auth_events",
            """
            created_at >= ?
            AND status NOT IN (
                'success',
                'sent',
                'verified',
                'created',
                'queued',
                'already_verified'
            )
            """,
            (since_24h,),
        )

        return {
            "ok": True,
            "version": APP_VERSION,
            "generatedAt": now_iso,
            "business": {
                "users": {
                    "total": users_total,
                    "emailVerified": users_email_verified,
                    "phoneVerified": users_phone_verified,
                    "created7d": users_created_7d,
                    "created30d": users_created_30d,
                    "emailVerifiedSharePercent": analytics_percent(users_email_verified, users_total),
                    "phoneVerifiedSharePercent": analytics_percent(users_phone_verified, users_total),
                },
                "devices": {
                    "total": devices_total,
                    "enabled": devices_enabled,
                    "disabled": devices_disabled,
                    "configIssued": devices_config_issued,
                    "seen7d": devices_seen_7d,
                },
                "subscriptions": {
                    "total": subs_total,
                    "active": subs_active,
                    "trial": subs_trial,
                    "paid": subs_paid,
                    "inactive": subs_inactive,
                    "expires7d": subs_expires_7d,
                    "paidSharePercent": analytics_percent(subs_paid, subs_active),
                },
                "orders": {
                    "total": orders_total,
                    "pending": orders_pending,
                    "paid": orders_paid,
                    "activated": orders_activated,
                    "failed": orders_failed,
                    "cancelled": orders_cancelled,
                    "grossRevenueRub": gross_revenue,
                    "pendingRevenueRub": pending_revenue,
                    "paid30dRub": paid_30d,
                    "averagePaidOrderRub": avg_paid_order,
                },
                "conversion": {
                    "usersWithPaidOrders": users_with_paid_orders,
                    "paidUserSharePercent": analytics_percent(users_with_paid_orders, users_total),
                },
            },
            "support": {
                "total": support_total,
                "openTotal": support_open,
                "overdueSla": support_overdue,
                "firstResponseMissing": support_first_response_missing,
                "created7d": support_created_7d,
                "resolved7d": support_resolved_7d,
                "byStatus": db_group_counts(conn, "support_reports", "status"),
                "byPriority": db_group_counts(conn, "support_reports", "priority"),
                "byCategory": db_group_counts(conn, "support_reports", "category"),
            },
            "incidents": {
                "total": incidents_total,
                "openTotal": incidents_open,
                "criticalOpen": incidents_critical_open,
                "warningOpen": incidents_warning_open,
                "byStatus": db_group_counts(conn, "admin_incidents", "status"),
                "bySeverity": db_group_counts(conn, "admin_incidents", "severity"),
                "bySource": db_group_counts(conn, "admin_incidents", "source"),
            },
            "updates": {
                "total": releases_total,
                "published": releases_published,
                "draft": releases_draft,
                "byChannel": db_group_counts(conn, "app_releases", "channel"),
                "byStatus": db_group_counts(conn, "app_releases", "status"),
            },
            "servers": {
                "publicServers": len(public_servers),
                "builtinServers": len(builtin_servers),
                "managedTotal": managed_servers_total,
                "managedActive": managed_servers_active,
                "managedPublicReady": managed_servers_public_ready,
                "healthObservationsTotal": health_observations_total,
                "healthFailures24h": health_observations_failed_24h,
                "healthEndpointsObserved": health_endpoints_observed,
                "byStatus": db_group_counts(conn, "server_catalog_entries", "status"),
                "byProtocol": db_group_counts(conn, "server_catalog_entries", "protocol"),
                "healthByStatus": db_group_counts(conn, "server_health_observations", "status"),
            },
            "auth": {
                "events24h": auth_events_24h,
                "success24h": auth_success_24h,
                "failed24h": auth_failed_24h,
                "byType": db_group_counts(conn, "auth_events", "event_type"),
                "byStatus": db_group_counts(conn, "auth_events", "status"),
                "phoneVerified": users_phone_verified,
                "emailVerified": users_email_verified,
            },
            "readiness": {
                "payment": readiness_signal(yookassa_payment_readiness()),
                "email": readiness_signal(email_confirmation_readiness()),
                "sms": readiness_signal(sms_confirmation_readiness()),
                "authCode": readiness_signal(auth_code_readiness()),
                "alerts": readiness_signal(admin_alert_readiness()),
                "apiVpnSplit": readiness_signal(api_vpn_endpoint_separation_readiness()),
                "product": {
                    "productionReady": bool(readiness.get("productionReady")),
                    "summary": readiness.get("summary") or {},
                },
            },
            "timeseries": {
                "users": daily_count_series(conn, "users", "created_at"),
                "ordersCount": daily_count_series(conn, "billing_orders", "created_at"),
                "ordersRevenue": daily_sum_series(
                    conn,
                    "billing_orders",
                    "created_at",
                    "amount_rub",
                    where=paid_status_where,
                ),
                "supportReports": daily_count_series(conn, "support_reports", "created_at"),
            },
        }


@app.get("/api/v1/admin/analytics/summary")
def admin_analytics_summary(
    x_admin_token: Optional[str] = Header(default=None),
    authorization: Optional[str] = Header(default=None),
):
    require_admin(x_admin_token, authorization, "analytics.read")
    sync_monitoring_incidents(
        monitoring=build_monitoring_status(),
        services=build_service_availability_status(),
    )
    return build_admin_analytics_summary()


@app.get("/api/v1/admin/overview")
def admin_overview(
    x_admin_token: Optional[str] = Header(default=None),
    authorization: Optional[str] = Header(default=None),
):
    require_admin(x_admin_token, authorization, "dashboard.read")
    sync_monitoring_incidents(
        monitoring=build_monitoring_status(),
        services=build_service_availability_status(),
    )

    with db() as conn:
        users_count = conn.execute("SELECT COUNT(*) AS cnt FROM users").fetchone()["cnt"]
        devices_count = conn.execute("SELECT COUNT(*) AS cnt FROM devices").fetchone()["cnt"]
        enabled_devices_count = conn.execute(
            "SELECT COUNT(*) AS cnt FROM devices WHERE is_enabled = 1"
        ).fetchone()["cnt"]
        active_subs_count = conn.execute(
            "SELECT COUNT(*) AS cnt FROM subscriptions WHERE is_active = 1"
        ).fetchone()["cnt"]
        pending_orders_count = conn.execute(
            "SELECT COUNT(*) AS cnt FROM billing_orders WHERE status = 'pending'"
        ).fetchone()["cnt"]
        support_reports_count = conn.execute(
            "SELECT COUNT(*) AS cnt FROM support_reports WHERE status = 'new'"
        ).fetchone()["cnt"]
        support_actions_count = conn.execute(
            "SELECT COUNT(*) AS cnt FROM admin_support_actions"
        ).fetchone()["cnt"]
        support_actions_24h_count = conn.execute(
            """
            SELECT COUNT(*) AS cnt
            FROM admin_support_actions
            WHERE created_at >= ?
            """,
            ((utc_now() - timedelta(hours=24)).isoformat(),),
        ).fetchone()["cnt"]
        open_incidents_count = conn.execute(
            "SELECT COUNT(*) AS cnt FROM admin_incidents WHERE status != 'resolved'"
        ).fetchone()["cnt"]
        feature_flags_count = conn.execute(
            "SELECT COUNT(*) AS cnt FROM admin_feature_flags"
        ).fetchone()["cnt"]
        active_feature_flags_count = conn.execute(
            "SELECT COUNT(*) AS cnt FROM admin_feature_flags WHERE is_enabled = 1"
        ).fetchone()["cnt"]
        runbooks_count = conn.execute(
            "SELECT COUNT(*) AS cnt FROM admin_runbooks"
        ).fetchone()["cnt"]
        active_runbooks_count = conn.execute(
            "SELECT COUNT(*) AS cnt FROM admin_runbooks WHERE is_active = 1"
        ).fetchone()["cnt"]

    return {
        "ok": True,
        "service": APP_TITLE,
        "version": APP_VERSION,
        "usersCount": int(users_count),
        "devicesCount": int(devices_count),
        "enabledDevicesCount": int(enabled_devices_count),
        "activeSubscriptionsCount": int(active_subs_count),
        "pendingBillingOrdersCount": int(pending_orders_count),
        "openSupportReportsCount": int(support_reports_count),
        "supportActionsCount": int(support_actions_count),
        "supportActions24hCount": int(support_actions_24h_count),
        "openIncidentsCount": int(open_incidents_count),
        "featureFlagsCount": int(feature_flags_count),
        "activeFeatureFlagsCount": int(active_feature_flags_count),
        "runbooksCount": int(runbooks_count),
        "activeRunbooksCount": int(active_runbooks_count),
        "defaultServer": f"{WG_ENDPOINT_HOST}:{WG_ENDPOINT_PORT}",
        "paymentReadiness": yookassa_payment_readiness(),
        "emailReadiness": email_confirmation_readiness(),
        "smsReadiness": sms_confirmation_readiness(),
        "authCodeReadiness": auth_code_readiness(),
        "userAuthFlowReadiness": user_auth_flow_readiness(),
        "alertReadiness": admin_alert_readiness(),
        "publicSiteReadiness": public_site_readiness(),
        "apiVpnEndpointSeparationReadiness": api_vpn_endpoint_separation_readiness(),
        "productReadiness": build_product_readiness()["summary"],
        "launchClosurePlan": build_launch_closure_plan(),
    }


@app.get("/api/v1/admin/readiness")
def admin_readiness(
    x_admin_token: Optional[str] = Header(default=None),
    authorization: Optional[str] = Header(default=None),
):
    require_admin(x_admin_token, authorization, "readiness.read")
    return build_product_readiness()


@app.get("/api/v1/admin/launch/readiness")
def admin_launch_readiness(
    x_admin_token: Optional[str] = Header(default=None),
    authorization: Optional[str] = Header(default=None),
):
    require_admin(x_admin_token, authorization, "readiness.read")
    return build_launch_readiness()


@app.get("/api/v1/admin/launch/closure-plan")
def admin_launch_closure_plan(
    x_admin_token: Optional[str] = Header(default=None),
    authorization: Optional[str] = Header(default=None),
):
    require_admin(x_admin_token, authorization, "readiness.read")
    return build_launch_closure_plan()


@app.get("/api/v1/admin/launch/owner-packet")
def admin_launch_owner_packet(
    x_admin_token: Optional[str] = Header(default=None),
    authorization: Optional[str] = Header(default=None),
):
    require_admin(x_admin_token, authorization, "readiness.read")
    return build_owner_launch_packet()


@app.get("/api/v1/admin/site/readiness")
def admin_site_readiness(
    x_admin_token: Optional[str] = Header(default=None),
    authorization: Optional[str] = Header(default=None),
):
    require_admin(x_admin_token, authorization, "readiness.read")
    return public_site_readiness()


@app.get("/api/v1/admin/auth/user-flow/readiness")
def admin_user_auth_flow_readiness(
    limit: int = 10,
    x_admin_token: Optional[str] = Header(default=None),
    authorization: Optional[str] = Header(default=None),
):
    require_admin(x_admin_token, authorization, "readiness.read")
    return user_auth_flow_readiness(limit=limit)


@app.get("/api/v1/admin/network/readiness")
def admin_network_readiness(
    x_admin_token: Optional[str] = Header(default=None),
    authorization: Optional[str] = Header(default=None),
):
    require_admin(x_admin_token, authorization, "readiness.read")
    return api_vpn_endpoint_separation_readiness()


@app.get("/api/v1/admin/network/split-plan")
def admin_network_split_plan(
    x_admin_token: Optional[str] = Header(default=None),
    authorization: Optional[str] = Header(default=None),
):
    require_admin(x_admin_token, authorization, "readiness.read")
    readiness = api_vpn_endpoint_separation_readiness()
    return {
        "ok": True,
        "version": APP_VERSION,
        "productionReady": readiness.get("productionReady"),
        "migrationPlan": readiness.get("migrationPlan"),
        "networkReadiness": readiness,
    }


@app.get("/api/v1/admin/external-actions")
def admin_external_actions(
    x_admin_token: Optional[str] = Header(default=None),
    authorization: Optional[str] = Header(default=None),
):
    require_admin(x_admin_token, authorization, "readiness.read")
    return build_external_actions_checklist()


@app.post("/api/v1/admin/external-actions/{action_code}")
def admin_external_action_status_update(
    action_code: str,
    payload: AdminOwnerActionStatusIn,
    request: Request,
    x_admin_token: Optional[str] = Header(default=None),
    authorization: Optional[str] = Header(default=None),
):
    context = require_admin(
        x_admin_token,
        authorization,
        "readiness.manage",
        request=request,
    )
    record = upsert_owner_action_status(
        action_code,
        payload,
        actor=context.get("actor"),
    )
    write_admin_audit(
        "owner_action_status_updated",
        "owner_action",
        record["actionCode"],
        {
            "status": record["status"],
            "hasNote": bool(record.get("note")),
        },
        request=request,
        actor=context.get("actor") or "admin_token",
    )
    return {
        "ok": True,
        "version": APP_VERSION,
        "record": record,
        "checklist": build_external_actions_checklist(),
    }


@app.get("/api/v1/admin/feature-flags")
def admin_feature_flags(
    scope: Optional[str] = None,
    enabled: Optional[str] = None,
    limit: int = 200,
    offset: int = 0,
    x_admin_token: Optional[str] = Header(default=None),
    authorization: Optional[str] = Header(default=None),
):
    require_admin(x_admin_token, authorization, "flags.read")
    return {
        "ok": True,
        "version": APP_VERSION,
        "workflow": feature_flag_workflow_options(),
        "flags": list_admin_feature_flags(
            scope=scope,
            enabled=enabled,
            limit=limit,
            offset=offset,
        ),
    }


@app.post("/api/v1/admin/feature-flags")
def admin_feature_flag_upsert(
    payload: AdminFeatureFlagIn,
    request: Request,
    x_admin_token: Optional[str] = Header(default=None),
    authorization: Optional[str] = Header(default=None),
):
    context = require_admin(x_admin_token, authorization, "flags.manage", request=request)
    flag = upsert_admin_feature_flag(payload, actor=context.get("actor"))
    write_admin_audit(
        "feature_flag_upserted",
        "feature_flag",
        str(flag["id"]),
        {
            "key": flag["key"],
            "scope": flag["scope"],
            "isEnabled": flag["isEnabled"],
            "rolloutPercent": flag["rolloutPercent"],
        },
        request=request,
        actor=context.get("actor") or "admin_token",
    )
    return {"ok": True, "version": APP_VERSION, "flag": flag}


@app.post("/api/v1/admin/feature-flags/{flag_id}")
def admin_feature_flag_update(
    flag_id: int,
    payload: AdminFeatureFlagIn,
    request: Request,
    x_admin_token: Optional[str] = Header(default=None),
    authorization: Optional[str] = Header(default=None),
):
    context = require_admin(x_admin_token, authorization, "flags.manage", request=request)
    flag = upsert_admin_feature_flag(payload, flag_id=flag_id, actor=context.get("actor"))
    write_admin_audit(
        "feature_flag_updated",
        "feature_flag",
        str(flag["id"]),
        {
            "key": flag["key"],
            "scope": flag["scope"],
            "isEnabled": flag["isEnabled"],
            "rolloutPercent": flag["rolloutPercent"],
        },
        request=request,
        actor=context.get("actor") or "admin_token",
    )
    return {"ok": True, "version": APP_VERSION, "flag": flag}


@app.get("/api/v1/admin/runbooks")
def admin_runbooks(
    category: Optional[str] = None,
    active: Optional[str] = None,
    limit: int = 200,
    offset: int = 0,
    x_admin_token: Optional[str] = Header(default=None),
    authorization: Optional[str] = Header(default=None),
):
    require_admin(x_admin_token, authorization, "runbooks.read")
    return {
        "ok": True,
        "version": APP_VERSION,
        "workflow": runbook_workflow_options(),
        "runbooks": list_admin_runbooks(
            category=category,
            active=active,
            limit=limit,
            offset=offset,
        ),
    }


@app.post("/api/v1/admin/runbooks")
def admin_runbook_upsert(
    payload: AdminRunbookIn,
    request: Request,
    x_admin_token: Optional[str] = Header(default=None),
    authorization: Optional[str] = Header(default=None),
):
    context = require_admin(x_admin_token, authorization, "runbooks.manage", request=request)
    runbook = upsert_admin_runbook(payload)
    write_admin_audit(
        "runbook_upserted",
        "runbook",
        str(runbook["id"]),
        {
            "key": runbook["key"],
            "category": runbook["category"],
            "severity": runbook["severity"],
            "isActive": runbook["isActive"],
        },
        request=request,
        actor=context.get("actor") or "admin_token",
    )
    return {"ok": True, "version": APP_VERSION, "runbook": runbook}


@app.post("/api/v1/admin/runbooks/{runbook_id}")
def admin_runbook_update(
    runbook_id: int,
    payload: AdminRunbookIn,
    request: Request,
    x_admin_token: Optional[str] = Header(default=None),
    authorization: Optional[str] = Header(default=None),
):
    context = require_admin(x_admin_token, authorization, "runbooks.manage", request=request)
    runbook = upsert_admin_runbook(payload, runbook_id=runbook_id)
    write_admin_audit(
        "runbook_updated",
        "runbook",
        str(runbook["id"]),
        {
            "key": runbook["key"],
            "category": runbook["category"],
            "severity": runbook["severity"],
            "isActive": runbook["isActive"],
        },
        request=request,
        actor=context.get("actor") or "admin_token",
    )
    return {"ok": True, "version": APP_VERSION, "runbook": runbook}


@app.get("/api/v1/admin/server-catalog")
def admin_server_catalog(
    status: Optional[str] = None,
    active: Optional[str] = None,
    public: Optional[str] = None,
    limit: int = 100,
    offset: int = 0,
    x_admin_token: Optional[str] = Header(default=None),
    authorization: Optional[str] = Header(default=None),
):
    require_admin(x_admin_token, authorization, "servers.read")
    public_catalog = build_server_catalog()
    managed_entries = list_managed_server_catalog_entries(
        status=status,
        active=active,
        public=public,
        limit=limit,
        offset=offset,
    )
    return {
        "ok": True,
        "version": APP_VERSION,
        "workflow": server_catalog_workflow_options(),
        "publicCatalog": public_catalog,
        "managedEntries": managed_entries,
        "summary": build_server_catalog_admin_summary(public_catalog, managed_entries),
    }


@app.get("/api/v1/admin/server-catalog/publication-readiness")
def admin_server_catalog_publication_readiness(
    x_admin_token: Optional[str] = Header(default=None),
    authorization: Optional[str] = Header(default=None),
):
    require_admin(x_admin_token, authorization, "servers.read")
    public_catalog = build_server_catalog()
    managed_entries = list_managed_server_catalog_entries(
        status="all",
        active="all",
        public="all",
        limit=500,
        offset=0,
    )
    return build_server_publication_readiness(public_catalog, managed_entries)


@app.get("/api/v1/admin/server-catalog/provisioning-readiness")
def admin_server_catalog_provisioning_readiness(
    x_admin_token: Optional[str] = Header(default=None),
    authorization: Optional[str] = Header(default=None),
):
    require_admin(x_admin_token, authorization, "servers.read")
    public_catalog = build_server_catalog()
    managed_entries = list_managed_server_catalog_entries(
        status="all",
        active="all",
        public="all",
        limit=500,
        offset=0,
    )
    return build_server_provisioning_readiness(public_catalog, managed_entries)


@app.post("/api/v1/admin/server-catalog")
def admin_server_catalog_upsert(
    payload: AdminServerCatalogEntryIn,
    request: Request,
    x_admin_token: Optional[str] = Header(default=None),
    authorization: Optional[str] = Header(default=None),
):
    require_admin(x_admin_token, authorization, "servers.manage", request=request)
    entry = upsert_managed_server_catalog_entry(payload)
    write_admin_audit(
        "server_catalog_entry_upserted",
        "server_catalog_entry",
        str(entry["id"]),
        {
            "serverId": entry["serverId"],
            "status": entry["status"],
            "protocol": entry["protocol"],
            "host": entry["host"],
            "port": entry["port"],
            "clientConfigReady": entry["clientConfigReady"],
        },
        request=request,
    )
    public_catalog = build_server_catalog()
    managed_entries = list_managed_server_catalog_entries()
    return {
        "ok": True,
        "version": APP_VERSION,
        "entry": entry,
        "publicCatalog": public_catalog,
        "summary": build_server_catalog_admin_summary(public_catalog, managed_entries),
    }


@app.post("/api/v1/admin/server-catalog/draft-from-plan")
def admin_server_catalog_create_draft_from_plan(
    payload: AdminServerCatalogDraftIn,
    request: Request,
    x_admin_token: Optional[str] = Header(default=None),
    authorization: Optional[str] = Header(default=None),
):
    require_admin(x_admin_token, authorization, "servers.manage", request=request)
    public_catalog = build_server_catalog()
    managed_entries = list_managed_server_catalog_entries(
        status="all",
        active="all",
        public="all",
        limit=500,
        offset=0,
    )
    provisioning = build_server_provisioning_readiness(public_catalog, managed_entries)
    onboarding_plan = provisioning.get("newServerOnboardingPlan") or {}
    if not onboarding_plan.get("safeToCreateInternalDraft"):
        raise HTTPException(
            status_code=409,
            detail="New VPS draft creation is blocked until the current public catalog is safe.",
        )

    entry_input = safe_new_server_draft_entry_input(payload)
    entry = upsert_managed_server_catalog_entry(entry_input)
    write_admin_audit(
        "server_catalog_new_vps_draft_created",
        "server_catalog_entry",
        str(entry["id"]),
        {
            "serverId": entry["serverId"],
            "host": entry["host"],
            "port": entry["port"],
            "status": entry["status"],
            "isActive": entry["isActive"],
            "isPublic": entry["isPublic"],
            "clientConfigProfile": entry["clientConfigProfile"],
        },
        request=request,
    )
    managed_entries = list_managed_server_catalog_entries(
        status="all",
        active="all",
        public="all",
        limit=500,
        offset=0,
    )
    provisioning = build_server_provisioning_readiness(public_catalog, managed_entries)
    return {
        "ok": True,
        "version": APP_VERSION,
        "draft": entry,
        "entry": entry,
        "publicCatalog": public_catalog,
        "summary": build_server_catalog_admin_summary(public_catalog, managed_entries),
        "provisioningReadiness": provisioning,
        "onboardingPlan": provisioning.get("newServerOnboardingPlan"),
        "message": (
            "Новый VPS создан как внутренний черновик. "
            "Он выключен, не публичный и не выдаёт клиентские конфиги."
        ),
    }


@app.post("/api/v1/admin/server-catalog/seed-current")
def admin_server_catalog_seed_current(
    request: Request,
    x_admin_token: Optional[str] = Header(default=None),
    authorization: Optional[str] = Header(default=None),
):
    require_admin(x_admin_token, authorization, "servers.manage", request=request)
    entry = upsert_current_wireguard_managed_server()
    write_admin_audit(
        "server_catalog_current_endpoint_seeded",
        "server_catalog_entry",
        str(entry["id"]),
        {
            "serverId": entry["serverId"],
            "host": entry["host"],
            "port": entry["port"],
            "clientConfigProfile": entry["clientConfigProfile"],
            "clientConfigReady": entry["clientConfigReady"],
            "isPublic": entry["isPublic"],
        },
        request=request,
    )
    public_catalog = build_server_catalog()
    managed_entries = list_managed_server_catalog_entries()
    return {
        "ok": True,
        "version": APP_VERSION,
        "entry": entry,
        "publicCatalog": public_catalog,
        "summary": build_server_catalog_admin_summary(public_catalog, managed_entries),
        "message": (
            "Текущий WireGuard endpoint добавлен во внутренний managed catalog. "
            "Клиентская выдача не изменилась."
        ),
    }


@app.post("/api/v1/admin/server-catalog/{entry_id}")
def admin_server_catalog_update(
    entry_id: int,
    payload: AdminServerCatalogEntryIn,
    request: Request,
    x_admin_token: Optional[str] = Header(default=None),
    authorization: Optional[str] = Header(default=None),
):
    require_admin(x_admin_token, authorization, "servers.manage", request=request)
    entry = upsert_managed_server_catalog_entry(payload, entry_id)
    write_admin_audit(
        "server_catalog_entry_updated",
        "server_catalog_entry",
        str(entry["id"]),
        {
            "serverId": entry["serverId"],
            "status": entry["status"],
            "protocol": entry["protocol"],
            "host": entry["host"],
            "port": entry["port"],
            "clientConfigReady": entry["clientConfigReady"],
        },
        request=request,
    )
    public_catalog = build_server_catalog()
    managed_entries = list_managed_server_catalog_entries()
    return {
        "ok": True,
        "version": APP_VERSION,
        "entry": entry,
        "publicCatalog": public_catalog,
        "summary": build_server_catalog_admin_summary(public_catalog, managed_entries),
    }


@app.get("/api/v1/admin/server-health")
def admin_server_health(
    endpointId: Optional[str] = None,
    status: Optional[str] = None,
    limit: int = 120,
    x_admin_token: Optional[str] = Header(default=None),
    authorization: Optional[str] = Header(default=None),
):
    require_admin(x_admin_token, authorization, "monitoring.read")
    return {
        "ok": True,
        "version": APP_VERSION,
        "summary": build_server_health_summary(),
        "observations": list_server_health_observations(
            endpoint_id=endpointId,
            status=status,
            limit=limit,
        ),
    }


@app.post("/api/v1/admin/server-health/observations")
def admin_server_health_observation_create(
    payload: AdminServerHealthObservationIn,
    request: Request,
    x_admin_token: Optional[str] = Header(default=None),
    authorization: Optional[str] = Header(default=None),
):
    require_admin(x_admin_token, authorization, "monitoring.manage", request=request)
    observation = create_server_health_observation(payload)
    write_admin_audit(
        "server_health_observation_created",
        "server_health_observation",
        str(observation["id"]),
        {
            "endpointId": observation["endpointId"],
            "probeId": observation["probeId"],
            "probeRegion": observation["probeRegion"],
            "status": observation["status"],
            "latencyMs": observation["latencyMs"],
            "target": observation["target"],
        },
        request=request,
    )
    return {
        "ok": True,
        "version": APP_VERSION,
        "observation": observation,
        "summary": build_server_health_summary(),
    }


@app.post("/api/v1/admin/server-health/probe-current")
def admin_server_health_probe_current(
    request: Request,
    x_admin_token: Optional[str] = Header(default=None),
    authorization: Optional[str] = Header(default=None),
):
    require_admin(x_admin_token, authorization, "monitoring.manage", request=request)
    result = build_current_wireguard_endpoint_probe()
    observation = result["observation"]
    write_admin_audit(
        "server_health_current_endpoint_probed",
        "server_health_observation",
        str(observation["id"]),
        {
            "endpointId": observation["endpointId"],
            "status": observation["status"],
            "score": result["score"],
            "target": observation["target"],
        },
        request=request,
    )
    public_catalog = build_server_catalog()
    managed_entries = list_managed_server_catalog_entries()
    return {
        "ok": True,
        "version": APP_VERSION,
        "message": result["message"],
        "observation": observation,
        "entry": result["entry"],
        "summary": build_server_health_summary(),
        "publicCatalog": public_catalog,
        "serverCatalogSummary": build_server_catalog_admin_summary(
            public_catalog,
            managed_entries,
        ),
        "publicationReadiness": build_server_publication_readiness(
            public_catalog,
            managed_entries,
        ),
    }


@app.get("/api/v1/admin/monitoring/targets")
def admin_monitoring_targets(
    status: Optional[str] = None,
    service: Optional[str] = None,
    limit: int = 200,
    x_admin_token: Optional[str] = Header(default=None),
    authorization: Optional[str] = Header(default=None),
):
    require_admin(x_admin_token, authorization, "monitoring.read")
    return {
        "ok": True,
        "version": APP_VERSION,
        "workflow": build_service_availability_observation_summary()["workflow"],
        "summary": build_service_availability_observation_summary(),
        "targets": list_monitoring_targets(status=status, service=service, limit=limit),
    }


@app.post("/api/v1/admin/monitoring/targets")
def admin_monitoring_target_upsert(
    payload: AdminMonitoringTargetIn,
    request: Request,
    x_admin_token: Optional[str] = Header(default=None),
    authorization: Optional[str] = Header(default=None),
):
    require_admin(x_admin_token, authorization, "monitoring.manage", request=request)
    target = upsert_monitoring_target(payload)
    write_admin_audit(
        "monitoring_target_upserted",
        "monitoring_target",
        target["targetId"],
        {
            "service": target["service"],
            "targetType": target["targetType"],
            "status": target["status"],
            "host": target["host"],
            "url": target["url"],
        },
        request=request,
    )
    return {
        "ok": True,
        "version": APP_VERSION,
        "target": target,
        "summary": build_service_availability_observation_summary(),
    }


@app.post("/api/v1/admin/monitoring/targets/seed-defaults")
def admin_monitoring_targets_seed_defaults(
    request: Request,
    x_admin_token: Optional[str] = Header(default=None),
    authorization: Optional[str] = Header(default=None),
):
    require_admin(x_admin_token, authorization, "monitoring.manage", request=request)
    seeded = seed_default_monitoring_targets(refresh_existing=True)
    write_admin_audit(
        "monitoring_default_targets_seeded",
        "monitoring_targets",
        "default",
        {
            "targets": len(seeded),
            "targetIds": [item.get("targetId") for item in seeded[:20]],
        },
        request=request,
    )
    return {
        "ok": True,
        "version": APP_VERSION,
        "targets": list_monitoring_targets(status="all", service="all", limit=200),
        "seededTargets": seeded,
        "summary": build_service_availability_observation_summary(),
    }


@app.post("/api/v1/admin/monitoring/targets/{target_id}")
def admin_monitoring_target_update(
    target_id: str,
    payload: AdminMonitoringTargetIn,
    request: Request,
    x_admin_token: Optional[str] = Header(default=None),
    authorization: Optional[str] = Header(default=None),
):
    require_admin(x_admin_token, authorization, "monitoring.manage", request=request)
    target = upsert_monitoring_target(payload, target_id_override=target_id)
    write_admin_audit(
        "monitoring_target_updated",
        "monitoring_target",
        target["targetId"],
        {
            "service": target["service"],
            "targetType": target["targetType"],
            "status": target["status"],
            "host": target["host"],
            "url": target["url"],
        },
        request=request,
    )
    return {
        "ok": True,
        "version": APP_VERSION,
        "target": target,
        "summary": build_service_availability_observation_summary(),
    }


@app.get("/api/v1/admin/monitoring/service-observations")
def admin_service_availability_observations(
    targetId: Optional[str] = None,
    status: Optional[str] = None,
    limit: int = 160,
    x_admin_token: Optional[str] = Header(default=None),
    authorization: Optional[str] = Header(default=None),
):
    require_admin(x_admin_token, authorization, "monitoring.read")
    return {
        "ok": True,
        "version": APP_VERSION,
        "summary": build_service_availability_observation_summary(),
        "observations": list_service_availability_observations(
            target_id=targetId,
            status=status,
            limit=limit,
        ),
    }


@app.get("/api/v1/admin/monitoring/probes")
def admin_service_monitoring_probes(
    limit: int = 100,
    x_admin_token: Optional[str] = Header(default=None),
    authorization: Optional[str] = Header(default=None),
):
    require_admin(x_admin_token, authorization, "monitoring.read")
    return {
        "ok": True,
        "version": APP_VERSION,
        "summary": build_service_availability_observation_summary(),
        "probes": list_service_monitoring_probes(limit=limit),
    }


@app.get("/api/v1/admin/monitoring/readiness")
def admin_service_monitoring_readiness(
    x_admin_token: Optional[str] = Header(default=None),
    authorization: Optional[str] = Header(default=None),
):
    require_admin(x_admin_token, authorization, "monitoring.read")
    summary = build_service_availability_observation_summary()
    return {
        "ok": True,
        "version": APP_VERSION,
        "readiness": summary.get("probeReadiness"),
        "summary": summary,
    }


@app.post("/api/v1/admin/monitoring/service-observations")
def admin_service_availability_observation_create(
    payload: AdminServiceAvailabilityObservationIn,
    request: Request,
    x_admin_token: Optional[str] = Header(default=None),
    authorization: Optional[str] = Header(default=None),
):
    require_admin(x_admin_token, authorization, "monitoring.manage", request=request)
    observation = create_service_availability_observation(payload)
    write_admin_audit(
        "service_availability_observation_created",
        "service_availability_observation",
        str(observation["id"]),
        {
            "targetId": observation["targetId"],
            "probeId": observation["probeId"],
            "probeRegion": observation["probeRegion"],
            "status": observation["status"],
            "latencyMs": observation["latencyMs"],
        },
        request=request,
    )
    return {
        "ok": True,
        "version": APP_VERSION,
        "observation": observation,
        "summary": build_service_availability_observation_summary(),
    }


@app.get("/api/v1/admin/updates/readiness")
def admin_update_release_readiness(
    platform: Optional[str] = "windows",
    channel: Optional[str] = "stable",
    x_admin_token: Optional[str] = Header(default=None),
    authorization: Optional[str] = Header(default=None),
):
    require_admin(x_admin_token, authorization, "updates.read")
    return build_update_release_readiness(
        platform=platform or "windows",
        channel=channel or "stable",
    )


@app.get("/api/v1/admin/updates/releases")
def admin_update_releases(
    platform: Optional[str] = "windows",
    channel: Optional[str] = None,
    status: Optional[str] = None,
    limit: int = 100,
    offset: int = 0,
    x_admin_token: Optional[str] = Header(default=None),
    authorization: Optional[str] = Header(default=None),
):
    require_admin(x_admin_token, authorization, "updates.read")
    manifest_platform = platform if platform not in {None, "all"} else "windows"
    manifest_channel = channel if channel not in {None, "all"} else "stable"
    return {
        "ok": True,
        "workflow": app_release_workflow_options(),
        "manifest": build_update_manifest(
            platform=manifest_platform,
            channel=manifest_channel,
            current_version=APP_VERSION,
            client_id="admin-preview",
        ),
        "readiness": build_update_release_readiness(
            platform=manifest_platform,
            channel=manifest_channel,
        ),
        "releases": list_app_releases(
            platform=platform,
            channel=channel,
            status=status,
            limit=limit,
            offset=offset,
        ),
    }


@app.post("/api/v1/admin/updates/releases")
def admin_update_release_upsert(
    payload: AdminAppReleaseIn,
    request: Request,
    x_admin_token: Optional[str] = Header(default=None),
    authorization: Optional[str] = Header(default=None),
):
    require_admin(x_admin_token, authorization, "updates.manage", request=request)
    release = upsert_app_release(payload)
    write_admin_audit(
        "app_release_upserted",
        "app_release",
        str(release["id"]),
        {
            "platform": release["platform"],
            "channel": release["channel"],
            "version": release["version"],
            "status": release["status"],
            "required": release["isRequired"],
            "rolloutPercent": release["rolloutPercent"],
        },
        request=request,
    )
    return {
        "ok": True,
        "release": release,
        "manifest": build_update_manifest(
            platform=release["platform"],
            channel=release["channel"],
            current_version=APP_VERSION,
            client_id="admin-preview",
        ),
    }


@app.post("/api/v1/admin/updates/releases/{release_id}")
def admin_update_release_update(
    release_id: int,
    payload: AdminAppReleaseIn,
    request: Request,
    x_admin_token: Optional[str] = Header(default=None),
    authorization: Optional[str] = Header(default=None),
):
    require_admin(x_admin_token, authorization, "updates.manage", request=request)
    release = upsert_app_release(payload, release_id)
    write_admin_audit(
        "app_release_updated",
        "app_release",
        str(release["id"]),
        {
            "platform": release["platform"],
            "channel": release["channel"],
            "version": release["version"],
            "status": release["status"],
            "required": release["isRequired"],
            "rolloutPercent": release["rolloutPercent"],
        },
        request=request,
    )
    return {
        "ok": True,
        "release": release,
        "manifest": build_update_manifest(
            platform=release["platform"],
            channel=release["channel"],
            current_version=APP_VERSION,
            client_id="admin-preview",
        ),
    }


@app.get("/api/v1/admin/incidents")
def admin_incidents(
    status: Optional[str] = None,
    severity: Optional[str] = None,
    assignee: Optional[str] = None,
    refresh: bool = True,
    limit: int = 100,
    offset: int = 0,
    x_admin_token: Optional[str] = Header(default=None),
    authorization: Optional[str] = Header(default=None),
):
    require_admin(x_admin_token, authorization, "incidents.read")
    monitoring = None
    services = None
    if refresh:
        monitoring = build_monitoring_status()
        services = build_service_availability_status()
        sync_monitoring_incidents(monitoring=monitoring, services=services)
    return {
        "ok": True,
        "workflow": incident_workflow_options(),
        "generatedAt": utc_now_iso(),
        "monitoringSummary": monitoring.get("summary") if monitoring else None,
        "servicesSummary": services.get("summary") if services else None,
        "incidents": list_admin_incidents(
            status=status,
            severity=severity,
            assignee=assignee,
            limit=limit,
            offset=offset,
        ),
        "assignees": list_incident_assignees(),
    }


@app.get("/api/v1/admin/incidents/assignees")
def admin_incident_assignees(
    x_admin_token: Optional[str] = Header(default=None),
    authorization: Optional[str] = Header(default=None),
):
    require_admin(x_admin_token, authorization, "incidents.read")
    return {
        "ok": True,
        "version": APP_VERSION,
        "assignees": list_incident_assignees(),
    }


@app.post("/api/v1/admin/incidents/{incident_id}")
def admin_incident_update(
    incident_id: int,
    payload: AdminIncidentUpdateIn,
    request: Request,
    x_admin_token: Optional[str] = Header(default=None),
    authorization: Optional[str] = Header(default=None),
):
    context = require_admin(x_admin_token, authorization, "incidents.manage", request=request)
    incident = update_admin_incident(
        incident_id,
        payload,
        actor=context.get("actor") or "admin",
    )
    write_admin_audit(
        "admin_incident_updated",
        "admin_incident",
        str(incident["id"]),
        {
            "status": incident.get("status"),
            "severity": incident.get("severity"),
            "assignee": incident.get("assignee"),
            "assigneeStaffId": incident.get("assigneeStaffId"),
        },
        request=request,
    )
    return {
        "ok": True,
        "incident": incident,
    }


@app.get("/api/v1/admin/support/reports")
def admin_support_reports(
    status: Optional[str] = None,
    userId: Optional[int] = None,
    email: Optional[str] = None,
    deviceUid: Optional[str] = None,
    category: Optional[str] = None,
    priority: Optional[str] = None,
    assignedTo: Optional[str] = None,
    limit: int = 100,
    offset: int = 0,
    x_admin_token: Optional[str] = Header(default=None),
    authorization: Optional[str] = Header(default=None),
):
    require_admin(x_admin_token, authorization, "support.read")
    return {
        "ok": True,
        "reports": list_support_reports(
            status=status,
            user_id=userId,
            email=email,
            device_uid=deviceUid,
            category=category,
            priority=priority,
            assigned_to=assignedTo,
            limit=limit,
            offset=offset,
        ),
    }


@app.get("/api/v1/admin/support/sla")
def admin_support_sla(
    limit: int = 25,
    x_admin_token: Optional[str] = Header(default=None),
    authorization: Optional[str] = Header(default=None),
):
    require_admin(x_admin_token, authorization, "support.read")
    return build_support_sla_dashboard(limit=limit)


@app.get("/api/v1/admin/support/workflow")
def admin_support_workflow(
    x_admin_token: Optional[str] = Header(default=None),
    authorization: Optional[str] = Header(default=None),
):
    require_admin(x_admin_token, authorization, "support.read")
    return {
        "ok": True,
        **support_workflow_options(),
    }


@app.get("/api/v1/admin/support/actions/workflow")
def admin_support_actions_workflow(
    x_admin_token: Optional[str] = Header(default=None),
    authorization: Optional[str] = Header(default=None),
):
    require_admin(x_admin_token, authorization, "support_actions.read")
    return {
        "ok": True,
        "version": APP_VERSION,
        **support_action_workflow_options(),
    }


@app.get("/api/v1/admin/support/actions")
def admin_support_actions(
    userId: Optional[int] = None,
    action: Optional[str] = None,
    status: Optional[str] = None,
    limit: int = 100,
    offset: int = 0,
    x_admin_token: Optional[str] = Header(default=None),
    authorization: Optional[str] = Header(default=None),
):
    require_admin(x_admin_token, authorization, "support_actions.read")
    return {
        "ok": True,
        "version": APP_VERSION,
        "actions": list_admin_support_actions(
            user_id=userId,
            action=action,
            status=status,
            limit=limit,
            offset=offset,
        ),
        "workflow": support_action_workflow_options(),
    }


@app.get("/api/v1/admin/support/reports/{report_id}")
def admin_support_report_get(
    report_id: int,
    x_admin_token: Optional[str] = Header(default=None),
    authorization: Optional[str] = Header(default=None),
):
    require_admin(x_admin_token, authorization, "support.read")
    return {
        "ok": True,
        "report": get_support_report(report_id),
    }


@app.get("/api/v1/admin/support/reports/{report_id}/comments")
def admin_support_report_comments(
    report_id: int,
    x_admin_token: Optional[str] = Header(default=None),
    authorization: Optional[str] = Header(default=None),
):
    require_admin(x_admin_token, authorization, "support.read")
    return {
        "ok": True,
        "comments": list_support_report_comments(report_id),
    }


@app.post("/api/v1/admin/support/reports/{report_id}/comments")
def admin_support_report_add_comment(
    report_id: int,
    payload: AdminSupportReportCommentIn,
    request: Request,
    x_admin_token: Optional[str] = Header(default=None),
    authorization: Optional[str] = Header(default=None),
):
    require_admin(x_admin_token, authorization, "support.manage", request=request)
    comment = add_support_report_comment(report_id, payload, request=request)
    write_admin_audit(
        "support_report_comment_added",
        "support_report",
        str(report_id),
        {"commentId": comment["id"]},
        request=request,
    )
    return {
        "ok": True,
        "comment": comment,
    }


@app.get("/api/v1/admin/support/reports/{report_id}/decoded")
def admin_support_report_decoded(
    report_id: int,
    x_admin_token: Optional[str] = Header(default=None),
    authorization: Optional[str] = Header(default=None),
):
    require_admin(x_admin_token, authorization, "support.read")
    report = get_support_report(report_id)
    return {
        "ok": True,
        "reportId": report["id"],
        "decoded": decode_support_report_code(report["report"]),
    }


@app.post("/api/v1/admin/support/reports/{report_id}/review")
def admin_support_report_review(
    report_id: int,
    payload: AdminSupportReportReviewIn,
    request: Request,
    x_admin_token: Optional[str] = Header(default=None),
    authorization: Optional[str] = Header(default=None),
):
    require_admin(x_admin_token, authorization, "support.manage", request=request)
    report = review_support_report(report_id, payload, request=request)
    write_admin_audit(
        "support_report_reviewed",
        "support_report",
        str(report_id),
        {
            "status": report.get("status"),
            "assignedTo": report.get("assignedTo"),
            "reviewedAt": report.get("reviewedAt"),
            "reviewedBy": report.get("reviewedBy"),
            "firstResponseAt": report.get("firstResponseAt"),
        },
        request=request,
    )
    return {
        "ok": True,
        "report": report,
    }


@app.post("/api/v1/admin/support/reports/{report_id}/status")
def admin_support_report_status(
    report_id: int,
    payload: AdminSupportReportStatusIn,
    request: Request,
    x_admin_token: Optional[str] = Header(default=None),
    authorization: Optional[str] = Header(default=None),
):
    require_admin(x_admin_token, authorization, "support.manage", request=request)
    report = update_support_report_status(report_id, payload, request=request)
    write_admin_audit(
        "support_report_status_updated",
        "support_report",
        str(report_id),
        {
            "status": report.get("status"),
            "priority": report.get("priority"),
            "category": report.get("category"),
            "assignedTo": report.get("assignedTo"),
            "slaDueAt": report.get("slaDueAt"),
            "reviewedAt": report.get("reviewedAt"),
            "reviewedBy": report.get("reviewedBy"),
        },
        request=request,
    )
    return {
        "ok": True,
        "report": report,
    }


@app.get("/api/v1/admin/audit")
def admin_audit(
    limit: int = 100,
    offset: int = 0,
    x_admin_token: Optional[str] = Header(default=None),
    authorization: Optional[str] = Header(default=None),
):
    require_admin(x_admin_token, authorization, "audit.read")
    return {
        "ok": True,
        "events": list_admin_audit(limit=limit, offset=offset),
    }


@app.post("/api/v1/admin/auth/login")
def admin_auth_login(payload: AdminLoginIn, request: Request):
    return login_admin_staff(payload, request)


@app.post("/api/v1/admin/auth/2fa/verify")
def admin_auth_2fa_verify(payload: AdminTwoFactorVerifyIn, request: Request):
    return verify_admin_2fa_challenge(payload, request)


@app.get("/api/v1/admin/auth/2fa/readiness")
def admin_auth_2fa_readiness(
    x_admin_token: Optional[str] = Header(default=None),
    authorization: Optional[str] = Header(default=None),
):
    require_admin(x_admin_token, authorization, "staff.manage")
    return admin_2fa_readiness()


@app.get("/api/v1/admin/auth/me")
def admin_auth_me(
    request: Request,
    x_admin_token: Optional[str] = Header(default=None),
    authorization: Optional[str] = Header(default=None),
):
    context = require_admin(x_admin_token, authorization, request=request)
    return {
        "ok": True,
        "version": APP_VERSION,
        "auth": admin_context_payload(context),
        "roles": list_admin_roles(),
    }


@app.post("/api/v1/admin/auth/logout")
def admin_auth_logout(
    request: Request,
    x_admin_token: Optional[str] = Header(default=None),
    authorization: Optional[str] = Header(default=None),
):
    context = require_admin(x_admin_token, authorization, request=request)
    revoked = revoke_admin_session(context.get("sessionHash"))
    write_admin_audit(
        "admin_staff_logout",
        "admin_session",
        context.get("sessionHash") or "bootstrap_token",
        {"authType": context.get("authType"), "revoked": revoked},
        request=request,
        actor=context.get("actor") or "admin_token",
    )
    return {
        "ok": True,
        "revoked": revoked,
    }


@app.get("/api/v1/admin/auth/sessions")
def admin_auth_sessions(
    request: Request,
    x_admin_token: Optional[str] = Header(default=None),
    authorization: Optional[str] = Header(default=None),
):
    context = require_admin(x_admin_token, authorization, request=request)
    return {
        "ok": True,
        "sessions": list_current_admin_sessions(context),
    }


@app.post("/api/v1/admin/auth/password/change")
def admin_auth_password_change(
    payload: AdminPasswordChangeIn,
    request: Request,
    x_admin_token: Optional[str] = Header(default=None),
    authorization: Optional[str] = Header(default=None),
):
    context = require_admin(x_admin_token, authorization, request=request)
    return change_current_admin_password(context, payload, request)


@app.post("/api/v1/admin/auth/sessions/revoke")
def admin_auth_session_revoke(
    payload: AdminSessionRevokeIn,
    request: Request,
    x_admin_token: Optional[str] = Header(default=None),
    authorization: Optional[str] = Header(default=None),
):
    context = require_admin(x_admin_token, authorization, request=request)
    return revoke_current_admin_session_by_public_id(context, payload, request)


@app.post("/api/v1/admin/auth/sessions/revoke-others")
def admin_auth_sessions_revoke_others(
    request: Request,
    x_admin_token: Optional[str] = Header(default=None),
    authorization: Optional[str] = Header(default=None),
):
    context = require_admin(x_admin_token, authorization, request=request)
    return revoke_other_admin_sessions(context, request)


@app.get("/api/v1/admin/roles")
def admin_roles(
    x_admin_token: Optional[str] = Header(default=None),
    authorization: Optional[str] = Header(default=None),
):
    require_admin(x_admin_token, authorization, "staff.manage")
    return {
        "ok": True,
        "roles": list_admin_roles(),
        "enforcement": "session_auth_ready_bootstrap_token_allowed",
    }


@app.get("/api/v1/admin/staff")
def admin_staff(
    x_admin_token: Optional[str] = Header(default=None),
    authorization: Optional[str] = Header(default=None),
):
    require_admin(x_admin_token, authorization, "staff.manage")
    return {
        "ok": True,
        "staff": list_admin_staff(),
    }


@app.post("/api/v1/admin/staff")
def admin_staff_upsert(
    payload: AdminStaffIn,
    request: Request,
    x_admin_token: Optional[str] = Header(default=None),
    authorization: Optional[str] = Header(default=None),
):
    require_admin(x_admin_token, authorization, "staff.manage", request=request)
    staff = upsert_admin_staff(payload)
    write_admin_audit(
        "admin_staff_upserted",
        "admin_staff",
        str(staff["id"]),
        {
            "email": staff["email"],
            "role": staff["role"],
            "isActive": staff["isActive"],
            "twoFactorEnabled": staff["twoFactorEnabled"],
            "passwordUpdated": bool(clean_admin_password(payload.temporaryPassword)),
        },
        request=request,
    )
    return {
        "ok": True,
        "staff": staff,
    }


@app.post("/api/v1/admin/staff/{staff_id}")
def admin_staff_update(
    staff_id: int,
    payload: AdminStaffUpdateIn,
    request: Request,
    x_admin_token: Optional[str] = Header(default=None),
    authorization: Optional[str] = Header(default=None),
):
    require_admin(x_admin_token, authorization, "staff.manage", request=request)
    staff = update_admin_staff(staff_id, payload)
    write_admin_audit(
        "admin_staff_updated",
        "admin_staff",
        str(staff["id"]),
        {
            "email": staff["email"],
            "role": staff["role"],
            "isActive": staff["isActive"],
            "twoFactorEnabled": staff["twoFactorEnabled"],
            "passwordUpdated": bool(clean_admin_password(payload.temporaryPassword)),
        },
        request=request,
    )
    return {
        "ok": True,
        "staff": staff,
    }


@app.get("/api/v1/admin/staff/{staff_id}/sessions")
def admin_staff_sessions(
    staff_id: int,
    request: Request,
    x_admin_token: Optional[str] = Header(default=None),
    authorization: Optional[str] = Header(default=None),
):
    context = require_admin(x_admin_token, authorization, "staff.manage", request=request)
    staff = admin_staff_payload(get_admin_staff_row(staff_id))
    return {
        "ok": True,
        "version": APP_VERSION,
        "staff": staff,
        "sessions": list_staff_admin_sessions(staff_id, context=context),
    }


@app.post("/api/v1/admin/staff/{staff_id}/sessions/revoke")
def admin_staff_session_revoke(
    staff_id: int,
    payload: AdminSessionRevokeIn,
    request: Request,
    x_admin_token: Optional[str] = Header(default=None),
    authorization: Optional[str] = Header(default=None),
):
    context = require_admin(x_admin_token, authorization, "staff.manage", request=request)
    return revoke_staff_admin_session_by_public_id(staff_id, context, payload, request)


@app.post("/api/v1/admin/staff/{staff_id}/sessions/revoke-all")
def admin_staff_sessions_revoke_all(
    staff_id: int,
    request: Request,
    x_admin_token: Optional[str] = Header(default=None),
    authorization: Optional[str] = Header(default=None),
):
    context = require_admin(x_admin_token, authorization, "staff.manage", request=request)
    return revoke_all_staff_admin_sessions(staff_id, context, request)


@app.get("/api/v1/admin/auth/events")
def admin_auth_events(
    limit: int = 100,
    offset: int = 0,
    eventType: Optional[str] = None,
    status: Optional[str] = None,
    contact: Optional[str] = None,
    x_admin_token: Optional[str] = Header(default=None),
    authorization: Optional[str] = Header(default=None),
):
    require_admin(x_admin_token, authorization, "audit.read")
    return {
        "ok": True,
        "filters": {
            "eventType": eventType or "all",
            "status": status or "all",
            "contact": contact or "",
        },
        "events": list_auth_events(
            limit=limit,
            offset=offset,
            event_type=eventType,
            status=status,
            contact=contact,
        ),
    }


@app.get("/api/v1/admin/billing/readiness")
def admin_billing_readiness(
    x_admin_token: Optional[str] = Header(default=None),
    authorization: Optional[str] = Header(default=None),
):
    require_admin(x_admin_token, authorization, "readiness.read")
    return yookassa_payment_readiness()


@app.get("/api/v1/admin/email/readiness")
def admin_email_readiness(
    x_admin_token: Optional[str] = Header(default=None),
    authorization: Optional[str] = Header(default=None),
):
    require_admin(x_admin_token, authorization, "readiness.read")
    return email_confirmation_readiness()


@app.get("/api/v1/admin/sms/readiness")
def admin_sms_readiness(
    x_admin_token: Optional[str] = Header(default=None),
    authorization: Optional[str] = Header(default=None),
):
    require_admin(x_admin_token, authorization, "readiness.read")
    return sms_confirmation_readiness()


@app.get("/api/v1/admin/alerts/readiness")
def admin_alerts_readiness(
    x_admin_token: Optional[str] = Header(default=None),
    authorization: Optional[str] = Header(default=None),
):
    require_admin(x_admin_token, authorization, "readiness.read")
    return admin_alert_readiness()


@app.get("/api/v1/admin/alerts/events")
def admin_alerts_events(
    status: Optional[str] = None,
    limit: int = 80,
    offset: int = 0,
    x_admin_token: Optional[str] = Header(default=None),
    authorization: Optional[str] = Header(default=None),
):
    require_admin(x_admin_token, authorization, "incidents.read")
    return {
        "ok": True,
        "version": APP_VERSION,
        "events": list_admin_alert_events(status=status, limit=limit, offset=offset),
    }


@app.post("/api/v1/admin/alerts/test")
def admin_alerts_test(
    request: Request,
    x_admin_token: Optional[str] = Header(default=None),
    authorization: Optional[str] = Header(default=None),
):
    require_admin(x_admin_token, authorization, "incidents.manage", request=request)
    readiness = admin_alert_readiness()
    if not readiness.get("productionReady"):
        raise HTTPException(
            status_code=409,
            detail=readiness.get("message") or "Admin alerts are not configured.",
        )

    result = send_telegram_admin_alert(
        "Green VPN admin alert test: Telegram delivery is configured."
    )
    write_admin_audit(
        "admin_alert_test_sent",
        "admin_alert",
        "telegram",
        {
            "ok": bool(result.get("ok")),
            "status": result.get("status"),
            "error": result.get("error"),
        },
        request=request,
    )
    if not result.get("ok"):
        raise HTTPException(
            status_code=502,
            detail=result.get("error") or "Telegram alert delivery failed.",
        )
    return {
        "ok": True,
        "result": {
            "status": result.get("status"),
            "deliveredAt": utc_now_iso(),
        },
    }


@app.get("/api/v1/admin/users")
def admin_users(
    q: Optional[str] = None,
    limit: int = 100,
    x_admin_token: Optional[str] = Header(default=None),
    authorization: Optional[str] = Header(default=None),
):
    require_admin(x_admin_token, authorization, "users.read")
    return {
        "ok": True,
        "users": list_admin_users(q=q, limit=limit),
    }


@app.get("/api/v1/admin/users/{user_id}")
def admin_user_get(
    user_id: int,
    x_admin_token: Optional[str] = Header(default=None),
    authorization: Optional[str] = Header(default=None),
):
    require_admin(x_admin_token, authorization, "users.read")
    return {
        "ok": True,
        **get_admin_user_detail(user_id),
    }


@app.post("/api/v1/admin/users/{user_id}/support-actions")
def admin_user_support_action(
    user_id: int,
    payload: AdminSupportActionIn,
    request: Request,
    x_admin_token: Optional[str] = Header(default=None),
    authorization: Optional[str] = Header(default=None),
):
    require_admin(x_admin_token, authorization, "support_actions.manage", request=request)
    action = perform_admin_support_action(user_id, payload, request=request)
    return {
        "ok": True,
        "version": APP_VERSION,
        "action": action,
        **get_admin_user_detail(user_id),
    }


@app.get("/api/v1/admin/billing/orders")
def admin_billing_orders(
    status: Optional[str] = None,
    x_admin_token: Optional[str] = Header(default=None),
    authorization: Optional[str] = Header(default=None),
):
    require_admin(x_admin_token, authorization, "billing.read")
    return {
        "ok": True,
        "orders": list_billing_orders(status=status),
        "reconciliation": billing_reconciliation_payload(),
        "promos": list_promo_codes(),
    }


@app.get("/api/v1/admin/billing/promos")
def admin_billing_promos(
    x_admin_token: Optional[str] = Header(default=None),
    authorization: Optional[str] = Header(default=None),
):
    require_admin(x_admin_token, authorization, "billing.read")
    return {
        "ok": True,
        "promos": list_promo_codes(),
    }


@app.get("/api/v1/admin/billing/promos/readiness")
def admin_billing_promos_readiness(
    limit: int = 25,
    x_admin_token: Optional[str] = Header(default=None),
    authorization: Optional[str] = Header(default=None),
):
    require_admin(x_admin_token, authorization, "billing.read")
    return billing_promo_launch_readiness_payload(limit=limit)


@app.post("/api/v1/admin/billing/promos")
def admin_upsert_billing_promo(
    payload: AdminPromoCodeIn,
    request: Request,
    x_admin_token: Optional[str] = Header(default=None),
    authorization: Optional[str] = Header(default=None),
):
    require_admin(x_admin_token, authorization, "billing.manage", request=request)
    promo = upsert_promo_code(payload)
    write_admin_audit(
        "billing_promo_saved",
        "billing_promo",
        promo["code"],
        {
            "discountType": promo["discountType"],
            "discountValue": promo["discountValue"],
            "isActive": promo["isActive"],
            "appliesToPlanCodes": promo["appliesToPlanCodes"],
        },
        request=request,
    )
    return {
        "ok": True,
        "promo": promo,
        "promos": list_promo_codes(),
    }


@app.post("/api/v1/admin/billing/promos/draft-start-campaign")
def admin_create_launch_promo_draft(
    request: Request,
    x_admin_token: Optional[str] = Header(default=None),
    authorization: Optional[str] = Header(default=None),
):
    require_admin(x_admin_token, authorization, "billing.manage", request=request)
    promo = create_launch_promo_draft()
    write_admin_audit(
        "billing_promo_launch_draft_created",
        "billing_promo",
        promo["code"],
        {
            "discountType": promo["discountType"],
            "discountValue": promo["discountValue"],
            "isActive": promo["isActive"],
            "maxRedemptions": promo["maxRedemptions"],
            "appliesToPlanCodes": promo["appliesToPlanCodes"],
        },
        request=request,
    )
    return {
        "ok": True,
        "promo": promo,
        "promos": list_promo_codes(),
        "readiness": billing_promo_launch_readiness_payload(),
        "message": "START20 draft was created inactive. Review and activate it manually only after release/payment readiness is green.",
    }


@app.post("/api/v1/admin/billing/promos/{code}/activate")
def admin_activate_billing_promo(
    code: str,
    request: Request,
    x_admin_token: Optional[str] = Header(default=None),
    authorization: Optional[str] = Header(default=None),
):
    require_admin(x_admin_token, authorization, "billing.manage", request=request)
    promo = set_promo_code_active(code, True)
    write_admin_audit(
        "billing_promo_activated",
        "billing_promo",
        promo["code"],
        {"isActive": True},
        request=request,
    )
    return {
        "ok": True,
        "promo": promo,
        "promos": list_promo_codes(),
    }


@app.post("/api/v1/admin/billing/promos/{code}/deactivate")
def admin_deactivate_billing_promo(
    code: str,
    request: Request,
    x_admin_token: Optional[str] = Header(default=None),
    authorization: Optional[str] = Header(default=None),
):
    require_admin(x_admin_token, authorization, "billing.manage", request=request)
    promo = set_promo_code_active(code, False)
    write_admin_audit(
        "billing_promo_deactivated",
        "billing_promo",
        promo["code"],
        {"isActive": False},
        request=request,
    )
    return {
        "ok": True,
        "promo": promo,
        "promos": list_promo_codes(),
    }


@app.get("/api/v1/admin/billing/reconciliation")
def admin_billing_reconciliation(
    limit: int = 25,
    x_admin_token: Optional[str] = Header(default=None),
    authorization: Optional[str] = Header(default=None),
):
    require_admin(x_admin_token, authorization, "billing.read")
    return billing_reconciliation_payload(limit=limit)


@app.get("/api/v1/admin/billing/renewals/readiness")
def admin_billing_renewals_readiness(
    limit: int = 25,
    x_admin_token: Optional[str] = Header(default=None),
    authorization: Optional[str] = Header(default=None),
):
    require_admin(x_admin_token, authorization, "billing.read")
    return billing_renewal_readiness_payload(limit=limit)


@app.get("/api/v1/admin/billing/payment-smoke/readiness")
def admin_billing_payment_smoke_readiness(
    limit: int = 10,
    x_admin_token: Optional[str] = Header(default=None),
    authorization: Optional[str] = Header(default=None),
):
    require_admin(x_admin_token, authorization, "billing.read")
    return billing_payment_smoke_readiness_payload(limit=limit)


@app.get("/api/v1/admin/subscriptions/expiry-readiness")
def admin_subscriptions_expiry_readiness(
    limit: int = 25,
    x_admin_token: Optional[str] = Header(default=None),
    authorization: Optional[str] = Header(default=None),
):
    require_admin(x_admin_token, authorization, "billing.read")
    return subscription_expiry_readiness_payload(limit=limit)


@app.post("/api/v1/admin/subscriptions/{subscription_id}/expiry-review")
def admin_subscription_expiry_review(
    subscription_id: int,
    payload: AdminSubscriptionExpiryReviewIn,
    request: Request,
    x_admin_token: Optional[str] = Header(default=None),
    authorization: Optional[str] = Header(default=None),
):
    require_admin(x_admin_token, authorization, "billing.manage", request=request)
    review = create_subscription_expiry_review(subscription_id, payload, request=request)
    write_admin_audit(
        "subscription_expiry_reviewed",
        "subscription",
        str(subscription_id),
        {
            "status": review.get("status"),
            "reviewId": review.get("id"),
            "userId": review.get("userId"),
        },
        request=request,
    )
    return {
        "ok": True,
        "version": APP_VERSION,
        "review": review,
        "readiness": subscription_expiry_readiness_payload(limit=25),
    }


@app.post("/api/v1/admin/billing/orders/{order_id}/mark-paid")
def admin_mark_billing_order_paid(
    order_id: str,
    request: Request,
    payload: Optional[AdminMarkOrderPaidIn] = None,
    x_admin_token: Optional[str] = Header(default=None),
    authorization: Optional[str] = Header(default=None),
):
    require_admin(x_admin_token, authorization, "billing.manage", request=request)
    result = mark_billing_order_paid_and_activate(
        order_id,
        provider_payment_id=payload.providerPaymentId if payload else None,
    )
    write_admin_audit(
        "billing_order_marked_paid",
        "billing_order",
        order_id,
        {"providerPaymentId": payload.providerPaymentId if payload else None},
        request=request,
    )
    return {
        "ok": True,
        **result,
    }


@app.get("/api/v1/admin/users/{user_id}/devices")
def admin_user_devices(
    user_id: int,
    x_admin_token: Optional[str] = Header(default=None),
    authorization: Optional[str] = Header(default=None),
):
    require_admin(x_admin_token, authorization, "users.read")
    return {
        "ok": True,
        "userId": user_id,
        "devices": list_user_devices(user_id),
    }


@app.post("/api/v1/admin/devices/{device_uid}/disable")
def admin_disable_device(
    device_uid: str,
    payload: AdminDeviceToggleIn,
    request: Request,
    x_admin_token: Optional[str] = Header(default=None),
    authorization: Optional[str] = Header(default=None),
):
    require_admin(x_admin_token, authorization, "devices.manage", request=request)
    device = set_device_enabled(device_uid, enabled=False, reason=payload.reason)
    write_admin_audit(
        "device_disabled",
        "device",
        device_uid,
        {"reason": payload.reason},
        request=request,
    )
    return {
        "ok": True,
        "device": device,
    }


@app.post("/api/v1/admin/devices/{device_uid}/enable")
def admin_enable_device(
    device_uid: str,
    request: Request,
    payload: Optional[AdminDeviceToggleIn] = None,
    x_admin_token: Optional[str] = Header(default=None),
    authorization: Optional[str] = Header(default=None),
):
    require_admin(x_admin_token, authorization, "devices.manage", request=request)
    device = set_device_enabled(device_uid, enabled=True, reason=None)
    write_admin_audit(
        "device_enabled",
        "device",
        device_uid,
        {},
        request=request,
    )
    return {
        "ok": True,
        "device": device,
    }


@app.post("/api/v1/admin/users/{user_id}/subscription")
def admin_set_subscription(
    user_id: int,
    payload: AdminSubscriptionIn,
    request: Request,
    x_admin_token: Optional[str] = Header(default=None),
    authorization: Optional[str] = Header(default=None),
):
    require_admin(x_admin_token, authorization, "billing.manage", request=request)
    if payload.maxDevices < 1:
        raise HTTPException(status_code=400, detail="maxDevices must be >= 1.")
    subscription = upsert_subscription_for_user(user_id, payload)
    write_admin_audit(
        "subscription_updated",
        "user",
        str(user_id),
        {
            "planCode": payload.planCode,
            "planName": payload.planName,
            "maxDevices": payload.maxDevices,
            "isActive": payload.isActive,
            "expiresAt": payload.expiresAt,
        },
        request=request,
    )
    return {
        "ok": True,
        "userId": user_id,
        "subscription": subscription,
    }


@app.post("/api/v1/admin/users/{user_id}/tariff/apply")
def admin_apply_tariff_for_user(
    user_id: int,
    payload: TariffSelectionIn,
    request: Request,
    x_admin_token: Optional[str] = Header(default=None),
    authorization: Optional[str] = Header(default=None),
):
    require_admin(x_admin_token, authorization, "billing.manage", request=request)
    result = apply_tariff_for_user(user_id, payload)
    write_admin_audit(
        "tariff_applied",
        "user",
        str(user_id),
        {
            "trafficPack": payload.trafficPack,
            "trafficGb": payload.trafficGb,
            "unlimitedApps": payload.unlimitedApps,
            "devices": payload.devices,
            "autoRenew": payload.autoRenew,
        },
        request=request,
    )
    return {
        "ok": True,
        "userId": user_id,
        **result,
    }
