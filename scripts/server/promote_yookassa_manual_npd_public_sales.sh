#!/usr/bin/env bash
set -euo pipefail

APPLY=0
DISABLE=0
EXPECTED_BACKEND_VERSION=""

ENV_FILE="/etc/bluevpn/backend.env"
SERVICE="bluevpn-backend.service"
ADMIN_TOKEN_FILE="/opt/bluevpn/backend/data/admin_token.txt"

usage() {
  cat <<'EOF'
Enable or disable public YooKassa sales on the primary billing node.

Usage:
  promote_yookassa_manual_npd_public_sales.sh \
    --expected-backend-version VERSION [--disable] [--apply]

Enable mode requires a completed payment, official NPD sale receipt, full
refund, entitlement rollback, official cancellation receipt, and clean
reconciliation. Automatic renewal charges always remain disabled.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --expected-backend-version)
      EXPECTED_BACKEND_VERSION="${2:?missing backend version}"
      shift 2
      ;;
    --disable) DISABLE=1; shift ;;
    --apply) APPLY=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
done

[[ "$EXPECTED_BACKEND_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+[A-Za-z0-9._-]*$ ]] || {
  echo "--expected-backend-version is required" >&2
  exit 2
}
for path in "$ENV_FILE" "$ADMIN_TOKEN_FILE"; do
  [[ -f "$path" && ! -L "$path" ]] || {
    echo "Required production file is missing or unsafe: $path" >&2
    exit 2
  }
done

python3 - "$ENV_FILE" "$EXPECTED_BACKEND_VERSION" <<'PY'
import pathlib
import re
import sys

path = pathlib.Path(sys.argv[1])
expected_version = sys.argv[2]
assignment = re.compile(r"^(?:export\s+)?([A-Za-z_][A-Za-z0-9_]*)\s*=(.*)$")
values = {}
for raw in path.read_text(encoding="utf-8").splitlines():
    match = assignment.match(raw.strip())
    if match:
        values[match.group(1)] = match.group(2).strip().strip("\"'")

required = {
    "GREENVPN_BACKEND_VERSION": expected_version,
    "GREENVPN_PAYMENT_PROVIDER": "yookassa",
    "GREENVPN_TAX_RECEIPT_MODE": "yookassa_npd_manual",
    "GREENVPN_TAX_RECEIPT_WORKFLOW_CONFIRMED": "1",
    "GREENVPN_NPD_RECEIPT_MANUAL_OPERATOR_CONFIRMED": "1",
    "GREENVPN_PUBLIC_PRODUCT_BILLING_PRIMARY": "1",
    "GREENVPN_REFUND_WORKFLOW_CONFIRMED": "1",
    "GREENVPN_REFUND_EXECUTION_ENABLED": "1",
    "GREENVPN_REFUND_BILLING_PRIMARY": "1",
    "GREENVPN_AUTO_RENEWAL_CHARGES_ENABLED": "0",
}
bad = [key for key, expected in required.items() if values.get(key) != expected]
if bad:
    raise SystemExit("public sales preflight mismatch: " + ",".join(sorted(bad)))

print("preflight_ok=true")
print("backend_version=" + expected_version)
print("billing_primary=true")
print("manual_npd_operator_confirmed=true")
print("automatic_charges_enabled=false")
PY

python3 - "$EXPECTED_BACKEND_VERSION" "$DISABLE" "$ADMIN_TOKEN_FILE" <<'PY'
import json
import pathlib
import sys
import urllib.request

expected_version = sys.argv[1]
disable = sys.argv[2] == "1"
token = pathlib.Path(sys.argv[3]).read_text(encoding="utf-8").strip()
base = "http://127.0.0.1:8000"

def get(path, *, admin=False):
    headers = {"Accept": "application/json"}
    if admin:
        headers["X-Admin-Token"] = token
    request = urllib.request.Request(base + path, headers=headers)
    with urllib.request.urlopen(request, timeout=30) as response:
        return json.loads(response.read().decode("utf-8"))

health = get("/healthz")
refunds = get("/api/v1/admin/billing/refunds/readiness", admin=True)
smoke = get("/api/v1/admin/billing/payment-smoke/readiness", admin=True)
reconciliation = get("/api/v1/admin/billing/reconciliation", admin=True)
if health.get("ok") is not True or health.get("version") != expected_version:
    raise SystemExit("health version mismatch")
if not disable:
    if refunds.get("productionReady") is not True:
        raise SystemExit("refund readiness is not production-ready")
    if smoke.get("smokeCompleted") is not True:
        raise SystemExit("payment smoke is incomplete")
    completed_refunds = int(
        (smoke.get("summary") or {}).get("completedRefundSmokeCandidates") or 0
    )
    if completed_refunds < 1:
        raise SystemExit("completed full-refund smoke evidence is missing")
    if reconciliation.get("requiresAttention") is not False:
        raise SystemExit("billing reconciliation requires attention")
print("readiness_preflight_ok=true")
print("completed_refund_smoke=" + str(
    int((smoke.get("summary") or {}).get("completedRefundSmokeCandidates") or 0)
))
PY

target_state="enabled"
if [[ $DISABLE -eq 1 ]]; then target_state="disabled"; fi
echo "mode=$([[ $APPLY -eq 1 ]] && echo apply || echo dry-run)"
echo "target_state=$target_state"
[[ $APPLY -eq 1 ]] || exit 0
[[ $EUID -eq 0 ]] || { echo "Run apply mode as root" >&2; exit 1; }

timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
backup_dir="/root/greenvpn-public-sales-backups/${timestamp}-${target_state}"
install -d -m 700 "$backup_dir"
cp -a "$ENV_FILE" "$backup_dir/backend.env"
chmod 600 "$backup_dir/backend.env"

rollback_on_error() {
  code=$?
  trap - ERR
  cp -a "$backup_dir/backend.env" "$ENV_FILE"
  systemctl restart "$SERVICE" >/dev/null 2>&1 || true
  exit "$code"
}
trap rollback_on_error ERR

python3 - "$ENV_FILE" "$DISABLE" <<'PY'
import os
import pathlib
import re
import sys

path = pathlib.Path(sys.argv[1])
disable = sys.argv[2] == "1"
assignment = re.compile(r"^(?:export\s+)?([A-Za-z_][A-Za-z0-9_]*)\s*=(.*)$")
updates = {
    "GREENVPN_NPD_RECEIPT_MANUAL_OPERATOR_CONFIRMED": "1",
    "GREENVPN_REFUND_WORKFLOW_CONFIRMED": "1",
    "GREENVPN_REFUND_EXECUTION_ENABLED": "1",
    "GREENVPN_PAID_SALES_ENABLED": "0" if disable else "1",
    "GREENVPN_AUTO_RENEWAL_CHARGES_ENABLED": "0",
    "GREENVPN_AUTO_RENEWAL_BILLING_PRIMARY": "0",
}
out = []
for raw in path.read_text(encoding="utf-8").splitlines():
    match = assignment.match(raw.strip())
    if match and match.group(1) in updates:
        continue
    out.append(raw)
for key, value in updates.items():
    out.append(f"{key}={value}")
temporary = path.with_name(path.name + ".public-sales.tmp")
temporary.write_text("\n".join(out) + "\n", encoding="utf-8")
os.chmod(temporary, 0o600)
os.replace(temporary, path)
PY
chown root:root "$ENV_FILE"
chmod 600 "$ENV_FILE"
systemctl restart "$SERVICE"

for _ in $(seq 1 90); do
  if curl -fsS --max-time 3 http://127.0.0.1:8000/healthz >/dev/null; then
    break
  fi
  sleep 1
done

python3 - "$EXPECTED_BACKEND_VERSION" "$DISABLE" "$ADMIN_TOKEN_FILE" <<'PY'
import json
import pathlib
import sys
import urllib.request

expected_version = sys.argv[1]
disable = sys.argv[2] == "1"
token = pathlib.Path(sys.argv[3]).read_text(encoding="utf-8").strip()
base = "http://127.0.0.1:8000"

def get(path, *, admin=False):
    headers = {"Accept": "application/json"}
    if admin:
        headers["X-Admin-Token"] = token
    request = urllib.request.Request(base + path, headers=headers)
    with urllib.request.urlopen(request, timeout=30) as response:
        return json.loads(response.read().decode("utf-8"))

health = get("/healthz")
catalog = get("/api/v1/catalog/tariffs").get("catalog") or {}
payments = get("/api/v1/admin/billing/readiness", admin=True)
refunds = get("/api/v1/admin/billing/refunds/readiness", admin=True)
smoke = get("/api/v1/admin/billing/payment-smoke/readiness", admin=True)
reconciliation = get("/api/v1/admin/billing/reconciliation", admin=True)

expected_sales = not disable
if health.get("ok") is not True or health.get("version") != expected_version:
    raise SystemExit("health version mismatch")
if bool(health.get("paidSalesEnabled")) != expected_sales:
    raise SystemExit("health sales state mismatch")
if bool(catalog.get("paidSalesEnabled")) != expected_sales:
    raise SystemExit("catalog sales state mismatch")
if bool(catalog.get("autoRenew")):
    raise SystemExit("manual NPD catalog unexpectedly offers auto-renew")
if expected_sales:
    if payments.get("productionReady") is not True:
        raise SystemExit("payment readiness is not production-ready")
    if catalog.get("paymentsProductionReady") is not True:
        raise SystemExit("catalog payment readiness mismatch")
    if refunds.get("productionReady") is not True:
        raise SystemExit("refund readiness is not production-ready")
    if smoke.get("smokeCompleted") is not True:
        raise SystemExit("payment smoke is incomplete")
    completed_refunds = int(
        (smoke.get("summary") or {}).get("completedRefundSmokeCandidates") or 0
    )
    if completed_refunds < 1:
        raise SystemExit("completed full-refund smoke evidence is missing")
    if reconciliation.get("requiresAttention") is not False:
        raise SystemExit("billing reconciliation requires attention")

print("public_sales_status=ok")
print("backend_version=" + expected_version)
print("paid_sales_enabled=" + str(expected_sales).lower())
print("payments_production_ready=" + str(bool(payments.get("productionReady"))).lower())
print("refund_production_ready=" + str(bool(refunds.get("productionReady"))).lower())
print("smoke_completed=" + str(bool(smoke.get("smokeCompleted"))).lower())
print("automatic_charges_enabled=false")
PY

trap - ERR
echo "public_sales_promotion_status=ok"
echo "backup_dir=$backup_dir"
