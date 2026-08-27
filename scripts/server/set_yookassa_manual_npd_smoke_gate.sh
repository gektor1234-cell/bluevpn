#!/usr/bin/env bash
set -euo pipefail

APPLY=0
DISARM=0
EXPECTED_BACKEND_VERSION=""

ENV_FILE="/etc/bluevpn/backend.env"
SERVICE="bluevpn-backend.service"
ADMIN_TOKEN_FILE="/opt/bluevpn/backend/data/admin_token.txt"

usage() {
  cat <<'EOF'
Arm or disarm the isolated YooKassa manual-NPD payment smoke on the primary.

Usage:
  set_yookassa_manual_npd_smoke_gate.sh \
    --expected-backend-version VERSION [--disarm] [--apply]

The default is a dry run. Public sales and automatic charges always remain off.
Apply mode creates a root-only env backup and restores it automatically on error.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --expected-backend-version)
      EXPECTED_BACKEND_VERSION="${2:?missing backend version}"
      shift 2
      ;;
    --disarm) DISARM=1; shift ;;
    --apply) APPLY=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
done

[[ "$EXPECTED_BACKEND_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+[A-Za-z0-9._-]*$ ]] || {
  echo "--expected-backend-version is required" >&2
  exit 2
}
[[ -f "$ENV_FILE" && ! -L "$ENV_FILE" ]] || {
  echo "Production env is missing or unsafe" >&2
  exit 2
}
[[ -f "$ADMIN_TOKEN_FILE" && ! -L "$ADMIN_TOKEN_FILE" ]] || {
  echo "Production admin token is missing or unsafe" >&2
  exit 2
}

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
    "GREENVPN_PUBLIC_PRODUCT_BILLING_PRIMARY": "1",
    "GREENVPN_REFUND_BILLING_PRIMARY": "1",
    "GREENVPN_PAID_SALES_ENABLED": "0",
    "GREENVPN_AUTO_RENEWAL_CHARGES_ENABLED": "0",
}
bad = [key for key, expected in required.items() if values.get(key) != expected]
if bad:
    raise SystemExit("smoke gate preflight mismatch: " + ",".join(sorted(bad)))

print("preflight_ok=true")
print("backend_version=" + values["GREENVPN_BACKEND_VERSION"])
print("payment_provider=" + values["GREENVPN_PAYMENT_PROVIDER"])
print("tax_receipt_mode=" + values["GREENVPN_TAX_RECEIPT_MODE"])
print("billing_primary=true")
print("paid_sales_enabled=false")
print("automatic_charges_enabled=false")
PY

target_state="armed"
if [[ $DISARM -eq 1 ]]; then target_state="disarmed"; fi
echo "mode=$([[ $APPLY -eq 1 ]] && echo apply || echo dry-run)"
echo "target_state=$target_state"
[[ $APPLY -eq 1 ]] || exit 0
[[ $EUID -eq 0 ]] || { echo "Run apply mode as root" >&2; exit 1; }

timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
backup_dir="/root/greenvpn-payment-smoke-gate-backups/${timestamp}-${target_state}"
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

python3 - "$ENV_FILE" "$DISARM" <<'PY'
import os
import pathlib
import re
import sys

path = pathlib.Path(sys.argv[1])
disarm = sys.argv[2] == "1"
assignment = re.compile(r"^(?:export\s+)?([A-Za-z_][A-Za-z0-9_]*)\s*=(.*)$")
updates = {
    "GREENVPN_NPD_RECEIPT_MANUAL_OPERATOR_CONFIRMED": "0" if disarm else "1",
    "GREENVPN_REFUND_WORKFLOW_CONFIRMED": "0" if disarm else "1",
    "GREENVPN_REFUND_EXECUTION_ENABLED": "0" if disarm else "1",
    "GREENVPN_PAID_SALES_ENABLED": "0",
    "GREENVPN_AUTO_RENEWAL_CHARGES_ENABLED": "0",
}
out = []
for raw in path.read_text(encoding="utf-8").splitlines():
    match = assignment.match(raw.strip())
    if match and match.group(1) in updates:
        continue
    out.append(raw)
for key, value in updates.items():
    out.append(f"{key}={value}")
temporary = path.with_name(path.name + ".payment-smoke.tmp")
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

python3 - "$EXPECTED_BACKEND_VERSION" "$DISARM" "$ADMIN_TOKEN_FILE" <<'PY'
import json
import pathlib
import sys
import urllib.request

expected_version = sys.argv[1]
disarm = sys.argv[2] == "1"
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
smoke = get("/api/v1/admin/billing/payment-smoke/readiness", admin=True)
refunds = get("/api/v1/admin/billing/refunds/readiness", admin=True)
if health.get("version") != expected_version or health.get("paidSalesEnabled") is not False:
    raise SystemExit("health contract mismatch")
if disarm:
    if smoke.get("safeToRunSmoke") is True:
        raise SystemExit("disarmed smoke unexpectedly reports safe")
    if refunds.get("policy", {}).get("executionEnabled") is True:
        raise SystemExit("disarmed refund execution unexpectedly enabled")
else:
    if smoke.get("safeToRunSmoke") is not True:
        raise SystemExit("armed smoke does not report safe")
    if refunds.get("productionReady") is not True:
        raise SystemExit("armed refund contour is not ready")
    if refunds.get("policy", {}).get("executionEnabled") is not True:
        raise SystemExit("armed refund execution is not enabled")

print("health_ok=true")
print("backend_version=" + str(health.get("version")))
print("paid_sales_enabled=false")
print("safe_to_run_smoke=" + str(bool(smoke.get("safeToRunSmoke"))).lower())
print("smoke_completed=" + str(bool(smoke.get("smokeCompleted"))).lower())
print("refund_execution_enabled=" + str(bool(refunds.get("policy", {}).get("executionEnabled"))).lower())
PY

trap - ERR
echo "payment_smoke_gate_status=ok"
echo "backup_dir=$backup_dir"
