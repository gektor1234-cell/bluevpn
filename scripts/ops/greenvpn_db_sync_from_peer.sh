#!/usr/bin/env bash
set -euo pipefail

CONF="${GREENVPN_DB_SYNC_CONF:-/etc/bluevpn/db-sync.env}"
if [[ ! -f "$CONF" ]]; then
  echo "missing config: $CONF" >&2
  exit 2
fi

# shellcheck source=/dev/null
source "$CONF"

GREENVPN_DB_SYNC_PEER_HOST="${GREENVPN_DB_SYNC_PEER_HOST:-}"
GREENVPN_DB_SYNC_PEER_NAME="${GREENVPN_DB_SYNC_PEER_NAME:-}"
GREENVPN_DB_SYNC_TARGET_DB="${GREENVPN_DB_SYNC_TARGET_DB:-/opt/bluevpn/backend/data/bluevpn.db}"
GREENVPN_DB_SYNC_STATE_DIR="${GREENVPN_DB_SYNC_STATE_DIR:-/var/lib/greenvpn-db-sync}"
GREENVPN_DB_SYNC_APPLY="${GREENVPN_DB_SYNC_APPLY:-1}"
GREENVPN_DB_SYNC_SSH_KEY="${GREENVPN_DB_SYNC_SSH_KEY:-/root/.ssh/greenvpn_db_sync_ed25519}"
GREENVPN_DB_SYNC_PEER_HOST="${GREENVPN_DB_SYNC_PEER_HOST%$'\r'}"
GREENVPN_DB_SYNC_PEER_NAME="${GREENVPN_DB_SYNC_PEER_NAME%$'\r'}"
GREENVPN_DB_SYNC_TARGET_DB="${GREENVPN_DB_SYNC_TARGET_DB%$'\r'}"
GREENVPN_DB_SYNC_STATE_DIR="${GREENVPN_DB_SYNC_STATE_DIR%$'\r'}"
GREENVPN_DB_SYNC_APPLY="${GREENVPN_DB_SYNC_APPLY%$'\r'}"
GREENVPN_DB_SYNC_SSH_KEY="${GREENVPN_DB_SYNC_SSH_KEY%$'\r'}"

: "${GREENVPN_DB_SYNC_PEER_HOST:?}"
: "${GREENVPN_DB_SYNC_PEER_NAME:?}"

mkdir -p "$GREENVPN_DB_SYNC_STATE_DIR"
chmod 700 "$GREENVPN_DB_SYNC_STATE_DIR"

LOCK="/run/greenvpn-db-sync-${GREENVPN_DB_SYNC_PEER_NAME}.lock"
TMP="${GREENVPN_DB_SYNC_STATE_DIR}/${GREENVPN_DB_SYNC_PEER_NAME}.sqlite.tmp"
SNAPSHOT="${GREENVPN_DB_SYNC_STATE_DIR}/${GREENVPN_DB_SYNC_PEER_NAME}.sqlite"
SUMMARY="${GREENVPN_DB_SYNC_STATE_DIR}/${GREENVPN_DB_SYNC_PEER_NAME}.last-summary.json"
LOG="${GREENVPN_DB_SYNC_STATE_DIR}/${GREENVPN_DB_SYNC_PEER_NAME}.log"

exec 9>"$LOCK"
flock -n 9 || exit 0

ts() {
  date -u +%Y-%m-%dT%H:%M:%SZ
}

{
  echo "[$(ts)] start peer=${GREENVPN_DB_SYNC_PEER_NAME} host=${GREENVPN_DB_SYNC_PEER_HOST}"
  ssh -i "$GREENVPN_DB_SYNC_SSH_KEY" \
    -o BatchMode=yes -o ConnectTimeout=8 -o ServerAliveInterval=10 -o ServerAliveCountMax=2 \
    "root@${GREENVPN_DB_SYNC_PEER_HOST}" \
    "python3 /usr/local/sbin/greenvpn_sqlite_snapshot_stdout.py" > "$TMP"
  test -s "$TMP"
  mv "$TMP" "$SNAPSHOT"

  mode_args=()
  if [[ "$GREENVPN_DB_SYNC_APPLY" == "1" || "$GREENVPN_DB_SYNC_APPLY" == "true" ]]; then
    mode_args+=(--apply)
  fi

  python3 /usr/local/sbin/greenvpn_sqlite_state_sync.py \
    --source-db "$SNAPSHOT" \
    --target-db "$GREENVPN_DB_SYNC_TARGET_DB" \
    --summary-json "$SUMMARY" \
    "${mode_args[@]}"
  echo "[$(ts)] done peer=${GREENVPN_DB_SYNC_PEER_NAME}"
} >> "$LOG" 2>&1
