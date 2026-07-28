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
GREENVPN_DB_SYNC_REMOTE_SNAPSHOT_ENV_FILE="${GREENVPN_DB_SYNC_REMOTE_SNAPSHOT_ENV_FILE:-/etc/bluevpn/backend.env}"
GREENVPN_DB_SYNC_REMOTE_SNAPSHOT_SCRIPT="${GREENVPN_DB_SYNC_REMOTE_SNAPSHOT_SCRIPT:-/usr/local/sbin/greenvpn_sqlite_snapshot_stdout.py}"
GREENVPN_DB_SYNC_LOCAL_STATE_SYNC_SCRIPT="${GREENVPN_DB_SYNC_LOCAL_STATE_SYNC_SCRIPT:-/usr/local/sbin/greenvpn_sqlite_state_sync.py}"
GREENVPN_DB_SYNC_SNAPSHOT_COMPRESSION="${GREENVPN_DB_SYNC_SNAPSHOT_COMPRESSION:-gzip}"
GREENVPN_DB_SYNC_LOCK_FILE="${GREENVPN_DB_SYNC_LOCK_FILE:-/run/greenvpn-db-sync-outgoing.lock}"
GREENVPN_DB_SYNC_PEER_HOST="${GREENVPN_DB_SYNC_PEER_HOST%$'\r'}"
GREENVPN_DB_SYNC_PEER_NAME="${GREENVPN_DB_SYNC_PEER_NAME%$'\r'}"
GREENVPN_DB_SYNC_TARGET_DB="${GREENVPN_DB_SYNC_TARGET_DB%$'\r'}"
GREENVPN_DB_SYNC_STATE_DIR="${GREENVPN_DB_SYNC_STATE_DIR%$'\r'}"
GREENVPN_DB_SYNC_APPLY="${GREENVPN_DB_SYNC_APPLY%$'\r'}"
GREENVPN_DB_SYNC_SSH_KEY="${GREENVPN_DB_SYNC_SSH_KEY%$'\r'}"
GREENVPN_DB_SYNC_REMOTE_SNAPSHOT_ENV_FILE="${GREENVPN_DB_SYNC_REMOTE_SNAPSHOT_ENV_FILE%$'\r'}"
GREENVPN_DB_SYNC_REMOTE_SNAPSHOT_SCRIPT="${GREENVPN_DB_SYNC_REMOTE_SNAPSHOT_SCRIPT%$'\r'}"
GREENVPN_DB_SYNC_LOCAL_STATE_SYNC_SCRIPT="${GREENVPN_DB_SYNC_LOCAL_STATE_SYNC_SCRIPT%$'\r'}"
GREENVPN_DB_SYNC_SNAPSHOT_COMPRESSION="${GREENVPN_DB_SYNC_SNAPSHOT_COMPRESSION%$'\r'}"
GREENVPN_DB_SYNC_LOCK_FILE="${GREENVPN_DB_SYNC_LOCK_FILE%$'\r'}"

: "${GREENVPN_DB_SYNC_PEER_HOST:?}"
: "${GREENVPN_DB_SYNC_PEER_NAME:?}"

if [[ ! "$GREENVPN_DB_SYNC_REMOTE_SNAPSHOT_ENV_FILE" =~ ^/[A-Za-z0-9._/-]+$ ]]; then
  echo "invalid remote snapshot env path" >&2
  exit 2
fi
if [[ ! "$GREENVPN_DB_SYNC_REMOTE_SNAPSHOT_SCRIPT" =~ ^/[A-Za-z0-9._/-]+$ ]]; then
  echo "invalid remote snapshot script path" >&2
  exit 2
fi
if [[ ! "$GREENVPN_DB_SYNC_LOCAL_STATE_SYNC_SCRIPT" =~ ^/[A-Za-z0-9._/-]+$ ]]; then
  echo "invalid local state sync script path" >&2
  exit 2
fi
if [[ ! -f "$GREENVPN_DB_SYNC_LOCAL_STATE_SYNC_SCRIPT" ]]; then
  echo "local state sync script not found" >&2
  exit 2
fi
if [[ "$GREENVPN_DB_SYNC_SNAPSHOT_COMPRESSION" != "none" && "$GREENVPN_DB_SYNC_SNAPSHOT_COMPRESSION" != "gzip" ]]; then
  echo "invalid snapshot compression" >&2
  exit 2
fi
if [[ ! "$GREENVPN_DB_SYNC_LOCK_FILE" =~ ^/run/[A-Za-z0-9._/-]+$ ]]; then
  echo "invalid sync lock path" >&2
  exit 2
fi
if [[ "$GREENVPN_DB_SYNC_SNAPSHOT_COMPRESSION" == "gzip" ]]; then
  command -v gzip >/dev/null 2>&1 || {
    echo "gzip is required for compressed snapshots" >&2
    exit 2
  }
fi

mkdir -p "$GREENVPN_DB_SYNC_STATE_DIR"
chmod 700 "$GREENVPN_DB_SYNC_STATE_DIR"

TMP="${GREENVPN_DB_SYNC_STATE_DIR}/${GREENVPN_DB_SYNC_PEER_NAME}.sqlite.tmp"
TRANSFER_TMP="${GREENVPN_DB_SYNC_STATE_DIR}/${GREENVPN_DB_SYNC_PEER_NAME}.transfer.tmp"
SNAPSHOT="${GREENVPN_DB_SYNC_STATE_DIR}/${GREENVPN_DB_SYNC_PEER_NAME}.sqlite"
SUMMARY="${GREENVPN_DB_SYNC_STATE_DIR}/${GREENVPN_DB_SYNC_PEER_NAME}.last-summary.json"
LOG="${GREENVPN_DB_SYNC_STATE_DIR}/${GREENVPN_DB_SYNC_PEER_NAME}.log"

exec 9>"$GREENVPN_DB_SYNC_LOCK_FILE"
flock -w 240 9 || exit 0

cleanup() {
  rm -f -- "$TMP" "$TRANSFER_TMP"
}
trap cleanup EXIT

ts() {
  date -u +%Y-%m-%dT%H:%M:%SZ
}

{
  echo "[$(ts)] start peer=${GREENVPN_DB_SYNC_PEER_NAME} host=${GREENVPN_DB_SYNC_PEER_HOST}"
  ssh -i "$GREENVPN_DB_SYNC_SSH_KEY" \
    -o BatchMode=yes -o ConnectTimeout=8 -o ServerAliveInterval=10 -o ServerAliveCountMax=2 \
    "root@${GREENVPN_DB_SYNC_PEER_HOST}" \
    "GREENVPN_SNAPSHOT_ENV_FILE=${GREENVPN_DB_SYNC_REMOTE_SNAPSHOT_ENV_FILE} GREENVPN_SNAPSHOT_COMPRESSION=${GREENVPN_DB_SYNC_SNAPSHOT_COMPRESSION} python3 ${GREENVPN_DB_SYNC_REMOTE_SNAPSHOT_SCRIPT}" > "$TRANSFER_TMP"
  test -s "$TRANSFER_TMP"
  if [[ "$GREENVPN_DB_SYNC_SNAPSHOT_COMPRESSION" == "gzip" ]]; then
    gzip -t "$TRANSFER_TMP"
    gzip -dc "$TRANSFER_TMP" > "$TMP"
  else
    mv "$TRANSFER_TMP" "$TMP"
  fi
  test -s "$TMP"
  mv "$TMP" "$SNAPSHOT"

  mode_args=()
  if [[ "$GREENVPN_DB_SYNC_APPLY" == "1" || "$GREENVPN_DB_SYNC_APPLY" == "true" ]]; then
    mode_args+=(--apply)
  fi

  python3 "$GREENVPN_DB_SYNC_LOCAL_STATE_SYNC_SCRIPT" \
    --source-db "$SNAPSHOT" \
    --target-db "$GREENVPN_DB_SYNC_TARGET_DB" \
    --summary-json "$SUMMARY" \
    "${mode_args[@]}" >/dev/null
  python3 - "$SUMMARY" <<'PY'
import json
import pathlib
import sys

payload = json.loads(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8"))
totals = payload["totals"]
print(
    "summary "
    f"inserted={totals['inserted']} "
    f"updated={totals['updated']} "
    f"deleted={totals['deleted']} "
    f"skipped={totals['skipped']} "
    f"conflicts={totals['conflicts']} "
    f"errors={totals['errors']}"
)
PY
  echo "[$(ts)] done peer=${GREENVPN_DB_SYNC_PEER_NAME}"
} >> "$LOG" 2>&1
