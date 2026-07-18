#!/usr/bin/env bash
set -euo pipefail

APPLY=0
CONTOUR=""
ENABLED=""
CLIENT_MARKER=""
AD_UNIT_ID=""

usage() {
  cat <<'EOF'
Configure rewarded ads for free Android connections on one control plane.

Usage:
  configure_android_rewarded_ads.sh \
    --contour production|paid-beta \
    --enabled 0|1 \
    --client-marker VERSION \
    --ad-unit-id ID \
    [--apply]

The default is a dry run. The VPN session timer is always disabled. Apply mode
backs up the selected environment file, rewrites only ad-related settings,
restarts the selected backend service and rolls back automatically on failure.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --contour) CONTOUR="${2:?missing contour}"; shift 2 ;;
    --enabled) ENABLED="${2:?missing enabled value}"; shift 2 ;;
    --client-marker) CLIENT_MARKER="${2:?missing client marker}"; shift 2 ;;
    --ad-unit-id) AD_UNIT_ID="${2:?missing ad unit id}"; shift 2 ;;
    --apply) APPLY=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
done

case "$CONTOUR" in
  production)
    ENV_FILE="/etc/bluevpn/backend.env"
    SERVICE="bluevpn-backend.service"
    LOCAL_HEALTH="http://127.0.0.1:8000/healthz"
    ;;
  paid-beta)
    ENV_FILE="/etc/bluevpn/paid-beta.env"
    SERVICE="greenvpn-paid-beta.service"
    LOCAL_HEALTH="http://127.0.0.1:8010/healthz"
    ;;
  *) echo "--contour must be production or paid-beta" >&2; exit 2 ;;
esac

[[ "$ENABLED" == "0" || "$ENABLED" == "1" ]] || {
  echo "--enabled must be 0 or 1" >&2
  exit 2
}
[[ "$CLIENT_MARKER" =~ ^[0-9]+\.[0-9]+\.[0-9]+[A-Za-z0-9._-]*$ ]] || {
  echo "Invalid client marker" >&2
  exit 2
}
[[ "$AD_UNIT_ID" =~ ^R-M-[0-9]+-[0-9]+$ ]] || {
  echo "Invalid rewarded ad unit id" >&2
  exit 2
}
[[ -f "$ENV_FILE" && ! -L "$ENV_FILE" ]] || {
  echo "Environment file is missing or unsafe" >&2
  exit 2
}

echo "mode=$([[ $APPLY -eq 1 ]] && echo apply || echo dry-run)"
echo "contour=$CONTOUR"
echo "enabled=$ENABLED"
echo "client_marker=$CLIENT_MARKER"
echo "platforms=android"
echo "grant_connects=1"
echo "session_timer_enabled=0"

[[ $APPLY -eq 1 ]] || exit 0
[[ $EUID -eq 0 ]] || { echo "Run apply mode as root" >&2; exit 1; }

timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
backup_dir="/root/greenvpn-rewarded-ads-backups/${timestamp}-${CONTOUR}"
install -d -m 700 "$backup_dir"
cp -a "$ENV_FILE" "$backup_dir/$(basename "$ENV_FILE")"
chmod 600 "$backup_dir/$(basename "$ENV_FILE")"

modified=0
rollback_on_error() {
  code=$?
  trap - ERR
  if [[ $modified -eq 1 ]]; then
    cp -a "$backup_dir/$(basename "$ENV_FILE")" "$ENV_FILE"
    systemctl restart "$SERVICE" >/dev/null 2>&1 || true
  fi
  exit "$code"
}
trap rollback_on_error ERR

python3 - "$ENV_FILE" "$ENABLED" "$CLIENT_MARKER" "$AD_UNIT_ID" <<'PY'
import os
import pathlib
import re
import sys

path = pathlib.Path(sys.argv[1])
enabled, marker, ad_unit_id = sys.argv[2:]
updates = {
    "GREENVPN_FREE_AD_GATE_ENABLED": enabled,
    "GREENVPN_FREE_AD_GATE_PROVIDER": "yandex_mobile_ads",
    "GREENVPN_FREE_AD_GATE_CLIENT_MARKER": marker,
    "GREENVPN_FREE_AD_GATE_PLATFORMS": "android",
    "GREENVPN_FREE_AD_GRANT_CONNECTS": "1",
    "GREENVPN_FREE_AD_SESSION_TIMER_ENABLED": "0",
    "GREENVPN_FREE_AD_SESSION_SECONDS": "0",
    "GREENVPN_YANDEX_REWARDED_ANDROID_ENABLED": enabled,
    "GREENVPN_YANDEX_REWARDED_ANDROID_AD_UNIT_ID": ad_unit_id,
}
assignment = re.compile(r"^(?:export\s+)?([A-Za-z_][A-Za-z0-9_]*)\s*=")
out = []
for raw in path.read_text(encoding="utf-8").splitlines():
    match = assignment.match(raw.strip())
    if match and match.group(1) in updates:
        continue
    out.append(raw)
for key, value in updates.items():
    out.append(f"{key}={value}")
temporary = path.with_name(path.name + ".rewarded-ads.tmp")
temporary.write_text("\n".join(out) + "\n", encoding="utf-8")
os.chmod(temporary, 0o600)
os.replace(temporary, path)
PY
modified=1
chown root:root "$ENV_FILE"
chmod 600 "$ENV_FILE"

systemctl restart "$SERVICE"
for _ in $(seq 1 45); do
  curl -fsS --max-time 3 "$LOCAL_HEALTH" >/dev/null && break
  sleep 1
done
curl -fsS --max-time 5 "$LOCAL_HEALTH" >/dev/null
systemctl is-active --quiet "$SERVICE"

python3 - "$ENV_FILE" "$ENABLED" "$CLIENT_MARKER" <<'PY'
import pathlib
import re
import sys

path = pathlib.Path(sys.argv[1])
expected_enabled, expected_marker = sys.argv[2:]
wanted = {
    "GREENVPN_FREE_AD_GATE_ENABLED": expected_enabled,
    "GREENVPN_FREE_AD_GATE_PROVIDER": "yandex_mobile_ads",
    "GREENVPN_FREE_AD_GATE_CLIENT_MARKER": expected_marker,
    "GREENVPN_FREE_AD_GATE_PLATFORMS": "android",
    "GREENVPN_FREE_AD_GRANT_CONNECTS": "1",
    "GREENVPN_FREE_AD_SESSION_TIMER_ENABLED": "0",
    "GREENVPN_FREE_AD_SESSION_SECONDS": "0",
    "GREENVPN_YANDEX_REWARDED_ANDROID_ENABLED": expected_enabled,
}
assignment = re.compile(r"^(?:export\s+)?([A-Za-z_][A-Za-z0-9_]*)\s*=(.*)$")
actual = {}
for raw in path.read_text(encoding="utf-8").splitlines():
    match = assignment.match(raw.strip())
    if match:
        actual[match.group(1)] = match.group(2).strip().strip('"').strip("'")
for key, value in wanted.items():
    if actual.get(key) != value:
        raise SystemExit(f"postcondition failed: {key}")
print("configuration_verified=true")
PY

trap - ERR
echo "rewarded_ads_status=ok"
echo "backup_dir=$backup_dir"
