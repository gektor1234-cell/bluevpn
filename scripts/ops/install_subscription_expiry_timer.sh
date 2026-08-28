#!/usr/bin/env bash
set -euo pipefail

APPLY=0
RUNNER=""
API_BASE="http://127.0.0.1:8000"
TOKEN_FILE="/opt/bluevpn/backend/data/admin_token.txt"
UNIT_PREFIX="greenvpn-subscription-expiry"
BACKEND_SERVICE=""
LIMIT=100

while [[ $# -gt 0 ]]; do
  case "$1" in
    --apply) APPLY=1; shift ;;
    --runner) RUNNER="${2:?missing runner}"; shift 2 ;;
    --api-base) API_BASE="${2:?missing api base}"; shift 2 ;;
    --token-file) TOKEN_FILE="${2:?missing token file}"; shift 2 ;;
    --unit-prefix) UNIT_PREFIX="${2:?missing unit prefix}"; shift 2 ;;
    --backend-service) BACKEND_SERVICE="${2:?missing backend service}"; shift 2 ;;
    --limit) LIMIT="${2:?missing limit}"; shift 2 ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done

[[ -n "$RUNNER" && -f "$RUNNER" && ! -L "$RUNNER" ]] || {
  echo "runner is required" >&2
  exit 2
}
[[ -f "$TOKEN_FILE" && ! -L "$TOKEN_FILE" ]] || {
  echo "token file is missing or unsafe" >&2
  exit 2
}
[[ "$UNIT_PREFIX" =~ ^[a-zA-Z0-9_.@-]+$ ]] || {
  echo "invalid unit prefix" >&2
  exit 2
}
[[ -z "$BACKEND_SERVICE" || "$BACKEND_SERVICE" =~ ^[a-zA-Z0-9_.@-]+$ ]] || {
  echo "invalid backend service" >&2
  exit 2
}
[[ "$LIMIT" =~ ^[0-9]+$ ]] || { echo "invalid limit" >&2; exit 2; }

TARGET_DIR="/opt/greenvpn-ops/${UNIT_PREFIX}"
TARGET_RUNNER="${TARGET_DIR}/run_subscription_expiry.py"
SERVICE_FILE="/etc/systemd/system/${UNIT_PREFIX}.service"
TIMER_FILE="/etc/systemd/system/${UNIT_PREFIX}.timer"

echo "mode=$([[ $APPLY -eq 1 ]] && echo apply || echo dry-run)"
echo "api_base=$API_BASE"
echo "unit_prefix=$UNIT_PREFIX"
echo "backend_service=${BACKEND_SERVICE:-none}"
echo "token_file=$TOKEN_FILE"

[[ $APPLY -eq 1 ]] || exit 0
[[ $EUID -eq 0 ]] || { echo "apply mode requires root" >&2; exit 1; }

/usr/bin/python3 "$RUNNER" \
  --api-base "$API_BASE" \
  --token-file "$TOKEN_FILE" \
  --limit "$LIMIT" \
  --dry-run

install -d -m 0755 -o root -g root "$TARGET_DIR"
install -m 0755 -o root -g root "$RUNNER" "$TARGET_RUNNER"
cat >"$SERVICE_FILE" <<EOF
[Unit]
Description=Green VPN subscription expiry reconciliation
After=network-online.target${BACKEND_SERVICE:+ $BACKEND_SERVICE}
Wants=network-online.target

[Service]
Type=oneshot
User=root
Group=root
ExecStart=/usr/bin/python3 $TARGET_RUNNER --api-base $API_BASE --token-file $TOKEN_FILE --limit $LIMIT
NoNewPrivileges=true
PrivateTmp=true
ProtectHome=true
ProtectSystem=strict
ReadOnlyPaths=$TOKEN_FILE $TARGET_RUNNER
EOF

cat >"$TIMER_FILE" <<EOF
[Unit]
Description=Reconcile expired Green VPN subscriptions every 5 minutes

[Timer]
OnBootSec=2min
OnUnitActiveSec=5min
RandomizedDelaySec=30
Persistent=true
Unit=${UNIT_PREFIX}.service

[Install]
WantedBy=timers.target
EOF

chmod 0644 "$SERVICE_FILE" "$TIMER_FILE"
systemctl daemon-reload
systemctl enable --now "${UNIT_PREFIX}.timer"
systemctl is-active "${UNIT_PREFIX}.timer"
