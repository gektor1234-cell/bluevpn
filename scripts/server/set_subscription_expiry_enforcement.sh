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
Enable or disable production subscription-expiry enforcement.

Usage:
  set_subscription_expiry_enforcement.sh \
    --expected-backend-version VERSION [--disable] [--apply]

The default is a dry run. Enabling is allowed only when the production admin
readiness endpoint reports safeToEnableExpiryEnforcement=true. Apply mode backs
up the root-only environment file and restores it automatically on error.
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
[[ -f "$ENV_FILE" && ! -L "$ENV_FILE" ]] || {
  echo "Production env is missing or unsafe" >&2
  exit 2
}
[[ -f "$ADMIN_TOKEN_FILE" && ! -L "$ADMIN_TOKEN_FILE" ]] || {
  echo "Production admin token is missing or unsafe" >&2
  exit 2
}

python3 - "$EXPECTED_BACKEND_VERSION" "$DISABLE" "$ADMIN_TOKEN_FILE" <<'PY'
import json
import pathlib
import sys
import urllib.request

expected_version = sys.argv[1]
disable = sys.argv[2] == "1"
token = pathlib.Path(sys.argv[3]).read_text(encoding="utf-8").strip()

def get(path, *, admin=False):
    headers = {"Accept": "application/json"}
    if admin:
        headers["X-Admin-Token"] = token
    request = urllib.request.Request(
        "http://127.0.0.1:8000" + path,
        headers=headers,
    )
    with urllib.request.urlopen(request, timeout=30) as response:
        return json.loads(response.read().decode("utf-8"))

health = get("/healthz")
readiness = get("/api/v1/admin/subscriptions/expiry-readiness", admin=True)
if health.get("ok") is not True or health.get("version") != expected_version:
    raise SystemExit("backend version or health mismatch")
if not disable and readiness.get("safeToEnableExpiryEnforcement") is not True:
    raise SystemExit("subscription expiry readiness is not safe")

summary = readiness.get("summary") or {}
print("preflight_ok=true")
print("backend_version=" + str(health.get("version")))
print("current_enforcement=" + str(bool(health.get("subscriptionEnforced"))).lower())
print("safe_to_enable=" + str(bool(readiness.get("safeToEnableExpiryEnforcement"))).lower())
print("expired_active=" + str(int(summary.get("expired") or 0)))
print("blocked_expiring=" + str(int(summary.get("blockedExpiring") or 0)))
print("payment_smoke_ready=" + str(bool(readiness.get("paymentSmokeReady"))).lower())
PY

target_state="enabled"
target_value="1"
if [[ $DISABLE -eq 1 ]]; then
  target_state="disabled"
  target_value="0"
fi
echo "mode=$([[ $APPLY -eq 1 ]] && echo apply || echo dry-run)"
echo "target_state=$target_state"
[[ $APPLY -eq 1 ]] || exit 0
[[ $EUID -eq 0 ]] || { echo "Run apply mode as root" >&2; exit 1; }

timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
backup_dir="/root/greenvpn-subscription-enforcement-backups/${timestamp}-${target_state}"
install -d -m 700 "$backup_dir"
cp -a "$ENV_FILE" "$backup_dir/backend.env"
chmod 600 "$backup_dir/backend.env"

rollback_on_error() {
  code=$?
  trap - ERR
  cp -a "$backup_dir/backend.env" "$ENV_FILE"
  chown root:root "$ENV_FILE"
  chmod 600 "$ENV_FILE"
  systemctl restart "$SERVICE" >/dev/null 2>&1 || true
  exit "$code"
}
trap rollback_on_error ERR

python3 - "$ENV_FILE" "$target_value" <<'PY'
import os
import pathlib
import re
import sys

path = pathlib.Path(sys.argv[1])
target_value = sys.argv[2]
key = "BLUEVPN_ENFORCE_SUBSCRIPTION_ACCESS"
assignment = re.compile(r"^(?:export\s+)?([A-Za-z_][A-Za-z0-9_]*)\s*=(.*)$")
out = []
for raw in path.read_text(encoding="utf-8").splitlines():
    match = assignment.match(raw.strip())
    if match and match.group(1) == key:
        continue
    out.append(raw)
out.append(f"{key}={target_value}")
temporary = path.with_name(path.name + ".subscription-enforcement.tmp")
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

def get(path, *, admin=False):
    headers = {"Accept": "application/json"}
    if admin:
        headers["X-Admin-Token"] = token
    request = urllib.request.Request(
        "http://127.0.0.1:8000" + path,
        headers=headers,
    )
    with urllib.request.urlopen(request, timeout=30) as response:
        return json.loads(response.read().decode("utf-8"))

health = get("/healthz")
readiness = get("/api/v1/admin/subscriptions/expiry-readiness", admin=True)
expected_enforcement = not disable
if health.get("ok") is not True or health.get("version") != expected_version:
    raise SystemExit("post-apply backend health mismatch")
if health.get("subscriptionEnforced") is not expected_enforcement:
    raise SystemExit("post-apply subscription enforcement mismatch")
if readiness.get("subscriptionEnforcementCurrentlyEnabled") is not expected_enforcement:
    raise SystemExit("post-apply readiness enforcement mismatch")
if not disable and readiness.get("safeToEnableExpiryEnforcement") is not True:
    raise SystemExit("post-apply subscription expiry readiness is not safe")

print("health_ok=true")
print("backend_version=" + str(health.get("version")))
print("subscription_enforced=" + str(expected_enforcement).lower())
print("safe_to_enable=" + str(bool(readiness.get("safeToEnableExpiryEnforcement"))).lower())
PY

trap - ERR
echo "subscription_enforcement_status=ok"
echo "backup_dir=$backup_dir"
