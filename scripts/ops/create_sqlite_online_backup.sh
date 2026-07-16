#!/usr/bin/env bash
set -Eeuo pipefail

ENV_FILE="/etc/bluevpn/backend.env"
OUTPUT_DIR=""
SNAPSHOT_SCRIPT="/usr/local/sbin/greenvpn_sqlite_snapshot_stdout.py"

while (($#)); do
  case "$1" in
    --env-file)
      ENV_FILE="${2:-}"
      shift 2
      ;;
    --output-dir)
      OUTPUT_DIR="${2:-}"
      shift 2
      ;;
    --snapshot-script)
      SNAPSHOT_SCRIPT="${2:-}"
      shift 2
      ;;
    *)
      echo "Unknown argument: $1" >&2
      exit 2
      ;;
  esac
done

[[ ${EUID} -eq 0 ]] || { echo "Run as root." >&2; exit 1; }
command -v realpath >/dev/null || { echo "realpath is required." >&2; exit 1; }
[[ ${ENV_FILE} =~ ^/[A-Za-z0-9._/-]+$ && -r ${ENV_FILE} ]] || { echo "Invalid env file." >&2; exit 2; }
[[ ${SNAPSHOT_SCRIPT} =~ ^/[A-Za-z0-9._/-]+$ && -r ${SNAPSHOT_SCRIPT} ]] || { echo "Invalid snapshot script." >&2; exit 2; }
[[ ${OUTPUT_DIR} =~ ^/root/greenvpn-[A-Za-z0-9._/-]+$ ]] || { echo "Output directory must be a guarded path under /root/greenvpn-." >&2; exit 2; }
canonical_output_dir="$(realpath -m -- "${OUTPUT_DIR}")"
[[ ${canonical_output_dir} == "${OUTPUT_DIR}" && ${canonical_output_dir} == /root/greenvpn-* ]] || {
  echo "Output directory must resolve directly under /root/greenvpn-." >&2
  exit 2
}

install -d -m 0700 "${OUTPUT_DIR}"
output="${OUTPUT_DIR}/bluevpn.db"
tmp="${OUTPUT_DIR}/.bluevpn.db.tmp.$$"
[[ ! -e ${output} ]] || { echo "Backup already exists: ${output}" >&2; exit 1; }

cleanup() {
  rm -f -- "${tmp}"
}
trap cleanup EXIT INT TERM

GREENVPN_SNAPSHOT_ENV_FILE="${ENV_FILE}" \
GREENVPN_SNAPSHOT_COMPRESSION=none \
  python3 "${SNAPSHOT_SCRIPT}" >"${tmp}"
chmod 0600 "${tmp}"

quick_check="$(python3 - "${tmp}" <<'PY'
import pathlib
import sqlite3
import sys

path = pathlib.Path(sys.argv[1])
connection = sqlite3.connect(f"file:{path}?mode=ro", uri=True, timeout=30)
try:
    print(connection.execute("PRAGMA quick_check").fetchone()[0])
finally:
    connection.close()
PY
)"
[[ ${quick_check} == ok ]] || { echo "Backup quick_check failed." >&2; exit 1; }

mv -- "${tmp}" "${output}"
trap - EXIT INT TERM
sha256="$(sha256sum "${output}" | awk '{print $1}')"
bytes="$(stat -c %s "${output}")"
printf '{"ok":true,"backup":"%s","bytes":%s,"sha256":"%s","quickCheck":"ok"}\n' \
  "${output}" "${bytes}" "${sha256}"
