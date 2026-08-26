#!/usr/bin/env bash
set -euo pipefail

APPLY=0
ROLE=""
BUNDLE_DIR=""
BACKEND_VERSION=""
SELECT_PRODAMUS_FAIL_CLOSED=0

APP_ROOT="/opt/bluevpn/backend"
DATA_DIR="${APP_ROOT}/data"
ENV_FILE="/etc/bluevpn/backend.env"
BETA_ENV_FILE="/etc/bluevpn/paid-beta.env"
SERVICE="bluevpn-backend.service"
SYNC_SERVICE="greenvpn-db-sync.service"
SYNC_TIMER="greenvpn-db-sync.timer"
SYNC_SCRIPT="/usr/local/sbin/greenvpn_db_sync_from_peer.sh"
SYNC_SNAPSHOT_SCRIPT="/usr/local/sbin/greenvpn_sqlite_snapshot_stdout.py"
SYNC_STATE_SCRIPT="/usr/local/sbin/greenvpn_sqlite_state_sync.py"

usage() {
  cat <<'EOF'
Install the public-product backend on one production control plane.

Usage:
  install_public_product_backend_release.sh \
    --role timeweb|ruvds \
    --bundle-dir PATH \
    --backend-version VERSION \
    [--select-prodamus-fail-closed] \
    [--apply]

The default is a dry run. Apply mode creates a root-only
code/env/SQLite/sync backup, updates one node, and restores code, env and sync
scripts automatically on error.
Database content is never replaced from the paid-beta contour.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --role) ROLE="${2:?missing role}"; shift 2 ;;
    --bundle-dir) BUNDLE_DIR="${2:?missing bundle dir}"; shift 2 ;;
    --backend-version) BACKEND_VERSION="${2:?missing backend version}"; shift 2 ;;
    --select-prodamus-fail-closed) SELECT_PRODAMUS_FAIL_CLOSED=1; shift ;;
    --apply) APPLY=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
done

case "$ROLE" in
  timeweb) BILLING_PRIMARY=1 ;;
  ruvds) BILLING_PRIMARY=0 ;;
  *) echo "--role must be timeweb or ruvds" >&2; exit 2 ;;
esac

[[ "$BACKEND_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+[A-Za-z0-9._-]*$ ]] || {
  echo "Invalid backend version" >&2
  exit 2
}
[[ -d "$BUNDLE_DIR" ]] || { echo "Bundle directory not found" >&2; exit 2; }
for relative in \
  backend/app/main.py \
  backend/requirements.txt \
  ops/greenvpn_db_sync_from_peer.sh \
  ops/greenvpn_sqlite_snapshot_stdout.py \
  ops/greenvpn_sqlite_state_sync.py \
  ops/greenvpn_prune_operational_history.py \
  ops/install_operational_retention_timer.sh; do
  [[ -f "$BUNDLE_DIR/$relative" && ! -L "$BUNDLE_DIR/$relative" ]] || {
    echo "Required bundle file is missing or unsafe: $relative" >&2
    exit 2
  }
done
[[ -f "$ENV_FILE" && ! -L "$ENV_FILE" ]] || { echo "Production env is missing or unsafe" >&2; exit 2; }
[[ -f "$BETA_ENV_FILE" && ! -L "$BETA_ENV_FILE" ]] || { echo "Paid-beta env is missing or unsafe" >&2; exit 2; }

echo "mode=$([[ $APPLY -eq 1 ]] && echo apply || echo dry-run)"
echo "role=$ROLE"
echo "backend_version=$BACKEND_VERSION"
echo "billing_primary=$BILLING_PRIMARY"
echo "select_prodamus_fail_closed=$SELECT_PRODAMUS_FAIL_CLOSED"
echo "source_main_sha256=$(sha256sum "$BUNDLE_DIR/backend/app/main.py" | awk '{print $1}')"
echo "database_source=production_only"

[[ $APPLY -eq 1 ]] || exit 0
[[ $EUID -eq 0 ]] || { echo "Run apply mode as root" >&2; exit 1; }
for command in curl gzip python3 sha256sum systemctl; do
  command -v "$command" >/dev/null 2>&1 || { echo "Required command missing: $command" >&2; exit 1; }
done

timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
backup_dir="/root/greenvpn-public-product-backups/${timestamp}-${ROLE}-${BACKEND_VERSION}"
install -d -m 700 "$backup_dir"
cp -a "$APP_ROOT/app/main.py" "$backup_dir/main.py"
cp -a "$APP_ROOT/requirements.txt" "$backup_dir/requirements.txt"
cp -a "$ENV_FILE" "$backup_dir/backend.env"
cp -a /etc/systemd/system/bluevpn-backend.service "$backup_dir/bluevpn-backend.service"
cp -a "$SYNC_SCRIPT" "$backup_dir/greenvpn_db_sync_from_peer.sh"
cp -a "$SYNC_SNAPSHOT_SCRIPT" "$backup_dir/greenvpn_sqlite_snapshot_stdout.py"
cp -a "$SYNC_STATE_SCRIPT" "$backup_dir/greenvpn_sqlite_state_sync.py"
chmod 600 "$backup_dir"/*

python3 - "$DATA_DIR/bluevpn.db" "$backup_dir/bluevpn.db" <<'PY'
import pathlib
import sqlite3
import sys

source_path = pathlib.Path(sys.argv[1])
target_path = pathlib.Path(sys.argv[2])
source = sqlite3.connect(f"file:{source_path}?mode=ro", uri=True, timeout=60)
target = sqlite3.connect(target_path, timeout=60)
try:
    source.backup(target)
    result = target.execute("PRAGMA quick_check").fetchone()[0]
finally:
    target.close()
    source.close()
if result != "ok":
    raise SystemExit(f"backup quick_check failed: {result}")
target_path.chmod(0o600)
PY
gzip -1 -c "$backup_dir/bluevpn.db" >"$backup_dir/bluevpn.db.gz"
gzip -t "$backup_dir/bluevpn.db.gz"
chmod 600 "$backup_dir/bluevpn.db.gz"

sync_was_active=0
env_modified=0
code_modified=0
sync_scripts_modified=0
if systemctl is-active --quiet "$SYNC_TIMER"; then sync_was_active=1; fi

rollback_on_error() {
  code=$?
  trap - ERR
  if [[ $code_modified -eq 1 ]]; then
    cp -a "$backup_dir/main.py" "$APP_ROOT/app/main.py"
    cp -a "$backup_dir/requirements.txt" "$APP_ROOT/requirements.txt"
  fi
  if [[ $sync_scripts_modified -eq 1 ]]; then
    install -m 755 "$backup_dir/greenvpn_db_sync_from_peer.sh" "$SYNC_SCRIPT"
    install -m 755 "$backup_dir/greenvpn_sqlite_snapshot_stdout.py" "$SYNC_SNAPSHOT_SCRIPT"
    install -m 755 "$backup_dir/greenvpn_sqlite_state_sync.py" "$SYNC_STATE_SCRIPT"
  fi
  if [[ $env_modified -eq 1 ]]; then cp -a "$backup_dir/backend.env" "$ENV_FILE"; fi
  systemctl restart "$SERVICE" >/dev/null 2>&1 || true
  if [[ $sync_was_active -eq 1 ]]; then systemctl restart "$SYNC_TIMER" >/dev/null 2>&1 || true; fi
  exit "$code"
}
trap rollback_on_error ERR

systemctl stop "$SYNC_TIMER" >/dev/null 2>&1 || true
systemctl stop "$SYNC_SERVICE" >/dev/null 2>&1 || true

"$APP_ROOT/.venv/bin/pip" install --disable-pip-version-check \
  -r "$BUNDLE_DIR/backend/requirements.txt" >/dev/null
install -m 644 "$BUNDLE_DIR/backend/requirements.txt" "$APP_ROOT/requirements.txt"
install -m 644 "$BUNDLE_DIR/backend/app/main.py" "$APP_ROOT/app/main.py"
code_modified=1
"$APP_ROOT/.venv/bin/python" -m py_compile "$APP_ROOT/app/main.py"
sync_scripts_modified=1
install -m 755 "$BUNDLE_DIR/ops/greenvpn_db_sync_from_peer.sh" "$SYNC_SCRIPT"
install -m 755 "$BUNDLE_DIR/ops/greenvpn_sqlite_snapshot_stdout.py" "$SYNC_SNAPSHOT_SCRIPT"
install -m 755 "$BUNDLE_DIR/ops/greenvpn_sqlite_state_sync.py" "$SYNC_STATE_SCRIPT"
python3 -m py_compile "$SYNC_SNAPSHOT_SCRIPT" "$SYNC_STATE_SCRIPT"
python3 -m py_compile "$BUNDLE_DIR/ops/greenvpn_prune_operational_history.py"

python3 - "$ENV_FILE" "$BETA_ENV_FILE" "$BACKEND_VERSION" "$BILLING_PRIMARY" \
  "$SELECT_PRODAMUS_FAIL_CLOSED" <<'PY'
import os
import pathlib
import re
import sys

target_path = pathlib.Path(sys.argv[1])
source_path = pathlib.Path(sys.argv[2])
backend_version = sys.argv[3]
billing_primary = sys.argv[4]
select_prodamus_fail_closed = sys.argv[5] == "1"
assignment = re.compile(r"^(?:export\s+)?([A-Za-z_][A-Za-z0-9_]*)\s*=(.*)$")

transport_keys = {
    "GREENVPN_AMNEZIAWG_CLIENT_CONFIG_ENABLED",
    "GREENVPN_HYSTERIA2_CANARY_SERVER_IDS",
    "GREENVPN_HYSTERIA2_CANARY_SNI",
    "GREENVPN_HYSTERIA2_CANARY_SNIS",
    "GREENVPN_HYSTERIA2_CLIENT_CONFIG_ENABLED",
    "GREENVPN_HYSTERIA2_CLIENT_CONFIG_ROOT",
    "GREENVPN_VLESS_REALITY_CANARY_SERVER_IDS",
    "GREENVPN_VLESS_REALITY_CANARY_SNI",
    "GREENVPN_VLESS_REALITY_CLIENT_CONFIG_ENABLED",
    "GREENVPN_VLESS_REALITY_CLIENT_CONFIG_ROOT",
    "GREENVPN_NAIVE_HTTPS_CANARY_HOST",
    "GREENVPN_NAIVE_HTTPS_CANARY_IP",
    "GREENVPN_NAIVE_HTTPS_CANARY_ENDPOINTS",
    "GREENVPN_NAIVE_HTTPS_CANARY_SERVER_IDS",
    "GREENVPN_NAIVE_HTTPS_CLIENT_CONFIG_ENABLED",
    "GREENVPN_NAIVE_HTTPS_CLIENT_CONFIG_ROOT",
    "GREENVPN_DNSTT_CANARY_IP",
    "GREENVPN_DNSTT_CANARY_SERVER_IDS",
    "GREENVPN_DNSTT_CANARY_ZONE",
    "GREENVPN_DNSTT_CLIENT_CONFIG_ENABLED",
    "GREENVPN_DNSTT_CLIENT_CONFIG_ROOT",
}
source_values = {}
for raw in source_path.read_text(encoding="utf-8").splitlines():
    match = assignment.match(raw.strip())
    if match and match.group(1) in transport_keys:
        source_values[match.group(1)] = match.group(2)
missing = sorted(transport_keys.difference(source_values))
if missing:
    raise SystemExit("paid-beta env lacks required transport keys: " + ",".join(missing))

target_values = {}
for raw in target_path.read_text(encoding="utf-8").splitlines():
    match = assignment.match(raw.strip())
    if match:
        target_values[match.group(1)] = match.group(2).strip().strip("\"'")

policy_defaults = {
    "GREENVPN_FREE_TIER_ENABLED": "1",
    "GREENVPN_FREE_TIER_QUOTA_ENFORCED": "0",
    "GREENVPN_FREE_TIER_RATE_LIMIT_ENFORCED": "0",
    "GREENVPN_FREE_TIER_MONTHLY_LIMIT_GB": "3",
    "GREENVPN_FREE_TIER_MAX_DEVICES": "1",
    "GREENVPN_FREE_TIER_SPEED_MBPS": "10",
    "GREENVPN_FREE_TIER_BURST_MBPS": "20",
    "GREENVPN_PAID_SALES_ENABLED": "0",
    "GREENVPN_PAYMENT_PROVIDER": "prodamus",
    "PRODAMUS_RETURN_URL": "https://api.greenvpn.pro/payment/return",
    "PRODAMUS_SUCCESS_URL": "https://api.greenvpn.pro/payment/return",
    "PRODAMUS_NOTIFICATION_URL": "https://api.greenvpn.pro/api/v1/billing/prodamus/notification",
    "PRODAMUS_NPD_PARTNER_CONFIRMED": "0",
    "PRODAMUS_LIVE_MODE_CONFIRMED": "0",
    "PRODAMUS_REFUND_SMOKE_CONFIRMED": "0",
    "PRODAMUS_RECURRING_ENABLED": "0",
    "GREENVPN_TAX_RECEIPT_MODE": "disabled",
    "GREENVPN_TAX_RECEIPT_WORKFLOW_CONFIRMED": "0",
    "GREENVPN_TAX_RECEIPT_VAT_CODE": "0",
    "GREENVPN_REFUND_WORKFLOW_CONFIRMED": "0",
    "GREENVPN_REFUND_EXECUTION_ENABLED": "0",
    "GREENVPN_REFUND_BILLING_PRIMARY": "0",
    "GREENVPN_AUTO_RENEWAL_CHARGES_ENABLED": "0",
    "GREENVPN_AUTO_RENEWAL_BILLING_PRIMARY": "0",
}

updates = {
    **source_values,
    **{
        key: target_values.get(key, default)
        for key, default in policy_defaults.items()
    },
    "GREENVPN_BACKEND_VERSION": backend_version,
    "GREENVPN_PUBLIC_SITE_URL": "https://greenvpn.pro",
    "GREENVPN_PUBLIC_PRODUCT_ENABLED": "1",
    "GREENVPN_PUBLIC_PRODUCT_CLIENT_MARKER": "green-vpn-public-product-v1",
    "GREENVPN_PUBLIC_PRODUCT_RELEASE_CHANNEL": "public-product",
    "GREENVPN_PUBLIC_PRODUCT_BILLING_PRIMARY": billing_primary,
    "GREENVPN_PAID_BETA_BILLING_PRIMARY": billing_primary,
    "GREENVPN_REFUND_BILLING_PRIMARY": billing_primary,
    "GREENVPN_AUTO_RENEWAL_BILLING_PRIMARY": billing_primary,
    "GREENVPN_PUBLIC_PRODUCT_TRANSPORT_SERVER_IDS": (
        "nl1-awg2-canary,nl1-hysteria2-canary,nl1-vless-reality-xhttp-canary,"
        "nl1-naive-https-canary,nl2-awg2-canary,nl2-hysteria2-canary,"
        "nl2-vless-reality-xhttp-canary,nl2-naive-https-canary,nl2-dnstt-canary,"
        "gb1-awg2-canary,gb1-hysteria2-canary,"
        "gb1-vless-reality-xhttp-canary,gb1-naive-https-canary"
    ),
}
if select_prodamus_fail_closed:
    updates.update(
        {
            "GREENVPN_PAYMENT_PROVIDER": "prodamus",
            "GREENVPN_PAID_SALES_ENABLED": "0",
            "PRODAMUS_RETURN_URL": "https://api.greenvpn.pro/payment/return",
            "PRODAMUS_SUCCESS_URL": "https://api.greenvpn.pro/payment/return",
            "PRODAMUS_NOTIFICATION_URL": (
                "https://api.greenvpn.pro/api/v1/billing/prodamus/notification"
            ),
            "PRODAMUS_NPD_PARTNER_CONFIRMED": "0",
            "PRODAMUS_LIVE_MODE_CONFIRMED": "0",
            "PRODAMUS_REFUND_SMOKE_CONFIRMED": "0",
            "PRODAMUS_RECURRING_ENABLED": "0",
            "GREENVPN_TAX_RECEIPT_MODE": "disabled",
            "GREENVPN_TAX_RECEIPT_WORKFLOW_CONFIRMED": "0",
            "GREENVPN_REFUND_WORKFLOW_CONFIRMED": "0",
            "GREENVPN_REFUND_EXECUTION_ENABLED": "0",
            "GREENVPN_AUTO_RENEWAL_CHARGES_ENABLED": "0",
        }
    )
out = []
for raw in target_path.read_text(encoding="utf-8").splitlines():
    match = assignment.match(raw.strip())
    if match and match.group(1) in updates:
        continue
    out.append(raw)
for key, value in updates.items():
    out.append(f"{key}={value}")
temporary = target_path.with_name(target_path.name + ".public-product.tmp")
temporary.write_text("\n".join(out) + "\n", encoding="utf-8")
os.chmod(temporary, 0o600)
os.replace(temporary, target_path)
PY
env_modified=1
chown root:root "$ENV_FILE"
chmod 600 "$ENV_FILE"

systemctl restart "$SERVICE"
for _ in $(seq 1 90); do
  curl -fsS --max-time 3 http://127.0.0.1:8000/healthz >/dev/null && break
  sleep 1
done
health="$(curl -fsS --max-time 5 http://127.0.0.1:8000/healthz)"
python3 - "$BACKEND_VERSION" "$BILLING_PRIMARY" "$health" <<'PY'
import json
import sys

expected_version, expected_writer, raw = sys.argv[1:]
value = json.loads(raw)
if value.get("ok") is not True or value.get("version") != expected_version:
    raise SystemExit("health version mismatch")
if value.get("paidSalesEnabled") is True:
    if value.get("paymentsProductionReady") is not True:
        raise SystemExit("enabled paid sales are not production ready")
else:
    if value.get("paymentsProductionReady") is not False:
        raise SystemExit("disabled paid sales unexpectedly report ready")
print("health_ok=true")
print("backend_version=" + str(value.get("version")))
print("paid_sales_enabled=" + str(value.get("paidSalesEnabled")).lower())
PY

python3 - "$DATA_DIR/bluevpn.db" <<'PY'
import sqlite3
import sys

conn = sqlite3.connect(f"file:{sys.argv[1]}?mode=ro", uri=True, timeout=30)
try:
    result = conn.execute("PRAGMA quick_check").fetchone()[0]
    users = conn.execute("SELECT COUNT(*) FROM users").fetchone()[0]
    subscriptions = conn.execute("SELECT COUNT(*) FROM subscriptions").fetchone()[0]
finally:
    conn.close()
if result != "ok" or users < 1 or subscriptions < 1:
    raise SystemExit("production database readiness failed")
print("database_quick_check=" + result)
print("users_present=true")
print("subscriptions_present=true")
PY

if [[ $sync_was_active -eq 1 ]]; then systemctl restart "$SYNC_TIMER"; fi
bash "$BUNDLE_DIR/ops/install_operational_retention_timer.sh" \
  --source-script "$BUNDLE_DIR/ops/greenvpn_prune_operational_history.py" \
  --apply
trap - ERR
echo "public_product_backend_status=ok"
echo "backup_dir=$backup_dir"
echo "sync_timer=$(systemctl is-active "$SYNC_TIMER" 2>/dev/null || true)"
