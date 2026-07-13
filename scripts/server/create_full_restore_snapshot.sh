#!/usr/bin/env bash
set -euo pipefail

LABEL=""
OUTPUT=""

usage() {
  cat <<'USAGE'
Create a root-only restore snapshot of one Green VPN server.

  create_full_restore_snapshot.sh --label LABEL --output /root/file.tar.gz

The archive may contain credentials and private configuration. Transfer it to
the protected workstation, encrypt it, verify the encrypted copy, and remove
the plaintext archive from both machines.
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --label) LABEL="${2:?missing label}"; shift 2 ;;
    --output) OUTPUT="${2:?missing output}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
done

[[ "${EUID}" -eq 0 ]] || { echo "Run as root." >&2; exit 1; }
[[ "${LABEL}" =~ ^[a-zA-Z0-9._-]{1,80}$ ]] || { echo "Invalid label." >&2; exit 2; }
[[ "${OUTPUT}" == /root/* && "${OUTPUT}" != */ ]] || {
  echo "Output must be a file directly below /root or its subdirectories." >&2
  exit 2
}
for command in find gzip hostname python3 sha256sum stat systemctl tar; do
  command -v "${command}" >/dev/null 2>&1 || {
    echo "Required command missing: ${command}" >&2
    exit 1
  }
done

umask 077
HOST_NAME="$(hostname -s | tr -cd 'a-zA-Z0-9._-')"
STAGE="/root/.greenvpn-full-snapshot-${LABEL}-${HOST_NAME}"
META="${STAGE}/metadata"
DATABASES="${STAGE}/database_copies"

[[ ! -e "${OUTPUT}" ]] || { echo "Output already exists: ${OUTPUT}" >&2; exit 1; }
rm -rf -- "${STAGE}"
mkdir -p -- "${META}" "${DATABASES}"
chmod 0700 "${STAGE}" "${META}" "${DATABASES}"

cleanup() {
  rm -rf -- "${STAGE}"
}
trap cleanup EXIT

printf '%s\n' "${LABEL}" >"${META}/label.txt"
date -u +%Y-%m-%dT%H:%M:%SZ >"${META}/created_utc.txt"
hostnamectl >"${META}/hostnamectl.txt" 2>&1 || hostname >"${META}/hostname.txt"
uname -a >"${META}/uname.txt"
df -hT >"${META}/filesystems.txt"
free -h >"${META}/memory.txt" 2>&1 || true
systemctl --failed --no-pager >"${META}/failed_units.txt" 2>&1 || true
systemctl list-unit-files --no-pager >"${META}/unit_files.txt" 2>&1 || true
systemctl list-timers --all --no-pager >"${META}/timers.txt" 2>&1 || true
systemctl list-units --type=service --all --no-pager >"${META}/services.txt" 2>&1 || true
ss -lntup >"${META}/listening_sockets.txt" 2>&1 || true
ip -details address show >"${META}/ip_addresses.txt" 2>&1 || true
ip route show table all >"${META}/routes.txt" 2>&1 || true
iptables-save >"${META}/iptables.rules" 2>/dev/null || true
nft list ruleset >"${META}/nftables.rules" 2>/dev/null || true
dpkg-query -W -f='${binary:Package}\t${Version}\n' >"${META}/packages.tsv" 2>/dev/null || true
getent passwd >"${META}/passwd.txt" 2>/dev/null || true
getent group >"${META}/group.txt" 2>/dev/null || true

mapfile -t ACTIVE_DATABASES < <(
  find /opt -path '*/.venv/*' -prune -o -path '*/backups/*' -prune -o \
    -type f -path '*/data/bluevpn.db' -print 2>/dev/null | sort
)

: >"${META}/databases.tsv"
for source_db in "${ACTIVE_DATABASES[@]}"; do
  relative_db="${source_db#/}"
  target_db="${DATABASES}/${relative_db}"
  mkdir -p -- "$(dirname "${target_db}")"
  python3 - "${source_db}" "${target_db}" <<'PY'
import sqlite3
import sys

source_path, target_path = sys.argv[1:3]
source = sqlite3.connect(f"file:{source_path}?mode=ro", uri=True, timeout=30)
target = sqlite3.connect(target_path)
with target:
    source.backup(target)
result = target.execute("PRAGMA quick_check").fetchone()[0]
source.close()
target.close()
if result != "ok":
    raise SystemExit(f"SQLite quick_check failed for {source_path}: {result}")
PY
  chmod 0600 "${target_db}"
  printf '%s\t%s\t%s\n' \
    "${source_db}" \
    "$(stat -c '%s' "${target_db}")" \
    "$(sha256sum "${target_db}" | cut -d' ' -f1)" \
    >>"${META}/databases.tsv"
done

declare -a INCLUDE_PATHS=(
  "etc/bluevpn"
  "etc/nginx"
  "etc/systemd/system"
  "etc/wireguard"
  "etc/amnezia"
  "etc/hysteria"
  "etc/xray"
  "etc/caddy"
  "etc/dnsdist"
  "etc/dnstt"
  "etc/letsencrypt"
  "etc/ufw"
  "etc/fail2ban"
  "etc/ssh/sshd_config"
  "etc/ssh/sshd_config.d"
  "etc/cron.d"
  "etc/crontab"
  "var/spool/cron"
  "var/www"
  "opt/bluevpn"
  "opt/bluevpn-paid-beta"
  "opt/greenvpn-monitoring"
  "opt/greenvpn-ops"
  "opt/greenvpn-server"
  "opt/greenvpn-canary"
  "opt/greenvpn-smtp-relay"
  "root/.ssh/authorized_keys"
)

declare -a EXISTING_PATHS=()
for path in "${INCLUDE_PATHS[@]}"; do
  [[ -e "/${path}" && ! -L "/${path}" ]] && EXISTING_PATHS+=("${path}")
done
printf '%s\n' "${EXISTING_PATHS[@]}" >"${META}/included_paths.txt"

mkdir -p -- "$(dirname "${OUTPUT}")"
tar -C / -czf "${OUTPUT}" \
  --numeric-owner \
  --exclude='*/.git/*' \
  --exclude='*/.venv/*' \
  --exclude='*/__pycache__/*' \
  --exclude='*/.cache/*' \
  --exclude='*/backups/*' \
  --exclude='*/logs/*' \
  --exclude='*/data/bluevpn.db' \
  --exclude='*/data/bluevpn.db-wal' \
  --exclude='*/data/bluevpn.db-shm' \
  --exclude='*/bluevpn.db-wal' \
  --exclude='*/bluevpn.db-shm' \
  "${EXISTING_PATHS[@]}" \
  "${STAGE#/}"

chmod 0600 "${OUTPUT}"
ARCHIVE_SHA256="$(sha256sum "${OUTPUT}" | cut -d' ' -f1)"
ARCHIVE_SIZE="$(stat -c '%s' "${OUTPUT}")"
tar -tzf "${OUTPUT}" >/dev/null

echo "snapshot_status=ok"
echo "snapshot_host=${HOST_NAME}"
echo "snapshot_path=${OUTPUT}"
echo "snapshot_size=${ARCHIVE_SIZE}"
echo "snapshot_sha256=${ARCHIVE_SHA256}"
echo "database_count=${#ACTIVE_DATABASES[@]}"
