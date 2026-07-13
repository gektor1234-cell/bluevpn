#!/usr/bin/env bash
set -euo pipefail

APPLY=0
EXPECTED_HOSTNAME="greenvpn-ruvds-ld8-test-01"
BACKUP_ROOT="/root/greenvpn-db-backups"
KEEP_NAME="bluevpn.db.before_app_schema_recovery_20260702T042753Z"
ACTIVE_DB="/opt/bluevpn/backend/data/bluevpn.db"

usage() {
  cat <<'USAGE'
Prune the exact historical London database-recovery directory.

  prune_london_recovery_backups.sh [--apply]

Dry-run is the default. Apply is host/path guarded, validates the active and
retained SQLite files, compresses the retained recovery copy, and removes only
direct regular files named bluevpn.db* from the exact backup root.
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --apply) APPLY=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
done

[[ "${EUID}" -eq 0 ]] || { echo "Run as root." >&2; exit 1; }
[[ "$(hostname -s)" == "${EXPECTED_HOSTNAME}" ]] || {
  echo "Host guard failed." >&2
  exit 1
}
[[ "$(readlink -f -- "${BACKUP_ROOT}")" == "${BACKUP_ROOT}" ]] || {
  echo "Backup root guard failed." >&2
  exit 1
}
[[ -d "${BACKUP_ROOT}" && ! -L "${BACKUP_ROOT}" ]] || {
  echo "Backup root is missing or unsafe." >&2
  exit 1
}
KEEP_PATH="${BACKUP_ROOT}/${KEEP_NAME}"
[[ -f "${ACTIVE_DB}" && ! -L "${ACTIVE_DB}" ]] || {
  echo "Active database is missing or unsafe." >&2
  exit 1
}
[[ -f "${KEEP_PATH}" && ! -L "${KEEP_PATH}" ]] || {
  echo "Retained recovery database is missing or unsafe." >&2
  exit 1
}

python3 - "${ACTIVE_DB}" "${KEEP_PATH}" <<'PY'
import sqlite3
import sys

for path in sys.argv[1:]:
    connection = sqlite3.connect(f"file:{path}?mode=ro", uri=True, timeout=30)
    try:
        result = connection.execute("PRAGMA quick_check").fetchone()[0]
    finally:
        connection.close()
    if result != "ok":
        raise SystemExit(f"SQLite quick_check failed: {path}")
PY

declare -a DELETE_PATHS=()
while IFS= read -r -d '' path; do
  [[ "$(dirname -- "${path}")" == "${BACKUP_ROOT}" ]] || {
    echo "Nested cleanup path rejected: ${path}" >&2
    exit 1
  }
  case "$(basename -- "${path}")" in
    bluevpn.db*) ;;
    *) echo "Unexpected backup filename rejected: ${path}" >&2; exit 1 ;;
  esac
  [[ "${path}" == "${KEEP_PATH}" ]] || DELETE_PATHS+=("${path}")
done < <(find "${BACKUP_ROOT}" -mindepth 1 -maxdepth 1 -type f -print0)

BEFORE_BYTES="$(du -sb -- "${BACKUP_ROOT}" | cut -f1)"
echo "london_prune_apply=${APPLY}"
echo "london_prune_before_bytes=${BEFORE_BYTES}"
echo "london_prune_delete_files=${#DELETE_PATHS[@]}"
echo "london_prune_keep=${KEEP_PATH}"
[[ "${APPLY}" -eq 1 ]] || exit 0

KEEP_GZIP="${KEEP_PATH}.gz"
[[ ! -e "${KEEP_GZIP}" ]] || {
  echo "Compressed retained backup already exists." >&2
  exit 1
}
TEMP_GZIP="${KEEP_GZIP}.tmp.$$"
gzip -1 -c -- "${KEEP_PATH}" >"${TEMP_GZIP}"
chmod 0600 "${TEMP_GZIP}"
gzip -t -- "${TEMP_GZIP}"
mv -- "${TEMP_GZIP}" "${KEEP_GZIP}"

for path in "${DELETE_PATHS[@]}"; do
  [[ "$(dirname -- "${path}")" == "${BACKUP_ROOT}" ]] || exit 1
  rm -f -- "${path}"
done
rm -f -- "${KEEP_PATH}"

AFTER_BYTES="$(du -sb -- "${BACKUP_ROOT}" | cut -f1)"
echo "london_prune_status=applied"
echo "london_prune_after_bytes=${AFTER_BYTES}"
echo "london_prune_freed_bytes=$((BEFORE_BYTES - AFTER_BYTES))"
