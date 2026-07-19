#!/usr/bin/env bash
set -euo pipefail

APPLY=0
CONTOUR=""
ENABLED=""
CLIENT_MARKER=""
DESKTOP_BLOCK_ID=""
TEST_WEB=0

usage() {
  cat <<'EOF'
Configure Yandex web Rewarded ads for free Windows connections on one control plane.

Usage:
  configure_windows_rewarded_ads.sh \
    --contour production|paid-beta \
    --enabled 0|1 \
    --client-marker VERSION \
    [--desktop-block-id R-A-N-N] \
    [--test-web 0|1] \
    [--apply]

The default is a dry run. Apply mode preserves other enabled ad platforms,
backs up the selected environment file, disables the VPN session timer,
restarts the backend and rolls back automatically if verification fails. Test
web is accepted only for enabled paid-beta and never for production.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --contour) CONTOUR="${2:?missing contour}"; shift 2 ;;
    --enabled) ENABLED="${2:?missing enabled value}"; shift 2 ;;
    --client-marker) CLIENT_MARKER="${2:?missing client marker}"; shift 2 ;;
    --desktop-block-id) DESKTOP_BLOCK_ID="${2:?missing desktop block id}"; shift 2 ;;
    --test-web) TEST_WEB="${2:?missing test web value}"; shift 2 ;;
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
[[ "$TEST_WEB" == "0" || "$TEST_WEB" == "1" ]] || {
  echo "--test-web must be 0 or 1" >&2
  exit 2
}
[[ "$CLIENT_MARKER" =~ ^[0-9]+\.[0-9]+\.[0-9]+[A-Za-z0-9._-]*$ ]] || {
  echo "Invalid client marker" >&2
  exit 2
}
if [[ "$TEST_WEB" == "1" ]]; then
  [[ "$CONTOUR" == "paid-beta" && "$ENABLED" == "1" ]] || {
    echo "--test-web is allowed only for enabled paid-beta" >&2
    exit 2
  }
  DESKTOP_BLOCK_ID=""
elif [[ "$ENABLED" == "1" ]]; then
  [[ "$DESKTOP_BLOCK_ID" =~ ^R-A-[0-9]+-[0-9]+$ ]] || {
    echo "Enabled production Rewarded requires a valid desktop block id" >&2
    exit 2
  }
elif [[ -n "$DESKTOP_BLOCK_ID" && ! "$DESKTOP_BLOCK_ID" =~ ^R-A-[0-9]+-[0-9]+$ ]]; then
  echo "Invalid desktop Rewarded block id" >&2
  exit 2
fi
[[ -f "$ENV_FILE" && ! -L "$ENV_FILE" ]] || {
  echo "Environment file is missing or unsafe" >&2
  exit 2
}

echo "mode=$([[ $APPLY -eq 1 ]] && echo apply || echo dry-run)"
echo "contour=$CONTOUR"
echo "windows_rewarded_enabled=$ENABLED"
echo "client_marker=$CLIENT_MARKER"
echo "grant_connects=1"
echo "session_timer_enabled=0"
echo "test_web_enabled=$TEST_WEB"

[[ $APPLY -eq 1 ]] || exit 0
[[ $EUID -eq 0 ]] || { echo "Run apply mode as root" >&2; exit 1; }

timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
backup_dir="/root/greenvpn-rewarded-ads-backups/${timestamp}-${CONTOUR}-windows"
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

python3 - "$ENV_FILE" "$ENABLED" "$CLIENT_MARKER" "$DESKTOP_BLOCK_ID" "$TEST_WEB" <<'PY'
import os
import pathlib
import re
import sys

path = pathlib.Path(sys.argv[1])
enabled, marker, block_id, test_web = sys.argv[2:]
assignment = re.compile(r"^(?:export\s+)?([A-Za-z_][A-Za-z0-9_]*)\s*=(.*)$")
values = {}
for raw in path.read_text(encoding="utf-8").splitlines():
    match = assignment.match(raw.strip())
    if match:
        values[match.group(1)] = match.group(2).strip().strip('"').strip("'")

platforms = {
    part.strip().lower()
    for part in values.get("GREENVPN_FREE_AD_GATE_PLATFORMS", "").split(",")
    if part.strip()
}
if enabled == "1":
    platforms.add("windows")
else:
    platforms.discard("windows")

updates = {
    "GREENVPN_FREE_AD_GATE_ENABLED": "1" if enabled == "1" or platforms else "0",
    "GREENVPN_FREE_AD_GATE_CLIENT_MARKER": marker,
    "GREENVPN_FREE_AD_GATE_PLATFORMS": ",".join(sorted(platforms)),
    "GREENVPN_FREE_AD_GRANT_CONNECTS": "1",
    "GREENVPN_FREE_AD_SESSION_TIMER_ENABLED": "0",
    "GREENVPN_FREE_AD_SESSION_SECONDS": "0",
    "GREENVPN_YANDEX_REWARDED_WEB_ENABLED": "1" if enabled == "1" and test_web == "0" else "0",
    "GREENVPN_YANDEX_REWARDED_WEB_DESKTOP_BLOCK_ID": block_id,
    "GREENVPN_FREE_AD_TEST_WEB_ENABLED": test_web,
}

out = []
for raw in path.read_text(encoding="utf-8").splitlines():
    match = assignment.match(raw.strip())
    if match and match.group(1) in updates:
        continue
    out.append(raw)
for key, value in updates.items():
    out.append(f"{key}={value}")

temporary = path.with_name(path.name + ".windows-rewarded.tmp")
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

python3 - "$ENV_FILE" "$ENABLED" "$CLIENT_MARKER" "$DESKTOP_BLOCK_ID" "$TEST_WEB" <<'PY'
import pathlib
import re
import sys

path = pathlib.Path(sys.argv[1])
enabled, marker, block_id, test_web = sys.argv[2:]
assignment = re.compile(r"^(?:export\s+)?([A-Za-z_][A-Za-z0-9_]*)\s*=(.*)$")
values = {}
for raw in path.read_text(encoding="utf-8").splitlines():
    match = assignment.match(raw.strip())
    if match:
        values[match.group(1)] = match.group(2).strip().strip('"').strip("'")

platforms = {
    part.strip().lower()
    for part in values.get("GREENVPN_FREE_AD_GATE_PLATFORMS", "").split(",")
    if part.strip()
}
expected = {
    "GREENVPN_FREE_AD_GATE_CLIENT_MARKER": marker,
    "GREENVPN_FREE_AD_GRANT_CONNECTS": "1",
    "GREENVPN_FREE_AD_SESSION_TIMER_ENABLED": "0",
    "GREENVPN_FREE_AD_SESSION_SECONDS": "0",
    "GREENVPN_YANDEX_REWARDED_WEB_ENABLED": "1" if enabled == "1" and test_web == "0" else "0",
    "GREENVPN_YANDEX_REWARDED_WEB_DESKTOP_BLOCK_ID": block_id,
    "GREENVPN_FREE_AD_TEST_WEB_ENABLED": test_web,
}
for key, value in expected.items():
    if values.get(key) != value:
        raise SystemExit(f"postcondition failed: {key}")
if ("windows" in platforms) != (enabled == "1"):
    raise SystemExit("postcondition failed: GREENVPN_FREE_AD_GATE_PLATFORMS")
if enabled == "1" and values.get("GREENVPN_FREE_AD_GATE_ENABLED") != "1":
    raise SystemExit("postcondition failed: GREENVPN_FREE_AD_GATE_ENABLED")
print("configuration_verified=true")
PY

trap - ERR
echo "windows_rewarded_ads_status=ok"
echo "backup_dir=$backup_dir"
