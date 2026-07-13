#!/usr/bin/env bash
set -euo pipefail

EXPECTED_HOSTNAME=""
APPLY=0
REMOVE_STALE_ONETIME=0

usage() {
  cat <<'USAGE'
Repair ACLs of Green VPN runtime secrets and SQLite files.

  repair_runtime_file_permissions.sh --expected-hostname HOST \
    [--remove-stale-onetime] [--apply]

Dry-run is the default. The optional cleanup removes only two exact historical
one-time credential filenames when they are regular root-owned files older than
seven days. It never follows symlinks or scans arbitrary directories for delete.
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --expected-hostname) EXPECTED_HOSTNAME="${2:?missing hostname}"; shift 2 ;;
    --remove-stale-onetime) REMOVE_STALE_ONETIME=1; shift ;;
    --apply) APPLY=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
done

[[ "${EUID}" -eq 0 ]] || { echo "Run as root." >&2; exit 1; }
[[ "${EXPECTED_HOSTNAME}" =~ ^[a-zA-Z0-9._-]{1,120}$ ]] || {
  echo "A valid --expected-hostname is required." >&2
  exit 2
}
[[ "$(hostname -s)" == "${EXPECTED_HOSTNAME}" ]] || {
  echo "Host guard failed." >&2
  exit 1
}

declare -a FILES=()
for path in \
  /etc/bluevpn/backend.env \
  /etc/bluevpn/paid-beta.env \
  /etc/bluevpn/node.env \
  /etc/bluevpn/paid-beta-node.env \
  /opt/bluevpn/backend/data/admin_token.txt \
  /opt/bluevpn/backend/data/bluevpn.db \
  /opt/bluevpn/backend/data/bluevpn.db-wal \
  /opt/bluevpn/backend/data/bluevpn.db-shm \
  /opt/bluevpn-paid-beta/data/admin_token.txt \
  /opt/bluevpn-paid-beta/data/bluevpn.db \
  /opt/bluevpn-paid-beta/data/bluevpn.db-wal \
  /opt/bluevpn-paid-beta/data/bluevpn.db-shm; do
  [[ -f "${path}" && ! -L "${path}" ]] && FILES+=("${path}")
done
if [[ -d /etc/bluevpn/vpn_nodes && ! -L /etc/bluevpn/vpn_nodes ]]; then
  while IFS= read -r -d '' path; do
    FILES+=("${path}")
  done < <(find /etc/bluevpn/vpn_nodes -maxdepth 1 -type f -name '*.env' -print0)
fi

declare -a DATA_DIRS=()
for path in /opt/bluevpn/backend/data /opt/bluevpn-paid-beta/data; do
  [[ -d "${path}" && ! -L "${path}" ]] && DATA_DIRS+=("${path}")
done

declare -a STALE_ONETIME=()
if [[ "${REMOVE_STALE_ONETIME}" -eq 1 ]]; then
  for path in \
    /root/greenvpn-admin-basic-auth-onetime.txt \
    /root/greenvpn-admin-owner-login-onetime.txt; do
    if [[ -f "${path}" && ! -L "${path}" && "$(stat -c '%u' "${path}")" -eq 0 ]]; then
      if find "${path}" -maxdepth 0 -type f -mtime +7 -print -quit | grep -q .; then
        STALE_ONETIME+=("${path}")
      fi
    fi
  done
fi

echo "permission_repair_host=$(hostname -s)"
echo "permission_repair_apply=${APPLY}"
echo "permission_repair_files=${#FILES[@]}"
echo "permission_repair_data_dirs=${#DATA_DIRS[@]}"
echo "permission_repair_stale_onetime=${#STALE_ONETIME[@]}"
[[ "${APPLY}" -eq 1 ]] || exit 0

for path in "${FILES[@]}"; do
  if [[ "$(stat -c '%a:%u:%g' "${path}")" == "600:0:0" ]]; then
    continue
  fi
  chown root:root "${path}"
  chmod 0600 "${path}"
done
for path in "${DATA_DIRS[@]}"; do
  if [[ "$(stat -c '%a:%u:%g' "${path}")" == "700:0:0" ]]; then
    continue
  fi
  chown root:root "${path}"
  chmod 0700 "${path}"
done
for path in "${STALE_ONETIME[@]}"; do
  case "${path}" in
    /root/greenvpn-admin-basic-auth-onetime.txt|/root/greenvpn-admin-owner-login-onetime.txt)
      rm -f -- "${path}"
      ;;
    *) echo "Unsafe cleanup path: ${path}" >&2; exit 1 ;;
  esac
done

for path in "${FILES[@]}"; do
  [[ "$(stat -c '%a:%u:%g' "${path}")" == "600:0:0" ]] || {
    echo "Permission verification failed: ${path}" >&2
    exit 1
  }
done
echo "permission_repair_status=applied"
