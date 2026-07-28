#!/usr/bin/env bash
set -euo pipefail

APPLY=0
EXPECTED_HOST="5.129.216.42"
EXPECTED_DOMAIN="nl2.vpn.greenvpn.pro"
SOURCE_ROOT="/etc/greenvpn-transport/hysteria2-canary/acme/certificates/acme-v02.api.letsencrypt.org-directory/nl2.vpn.greenvpn.pro"
SOURCE_CERT="${SOURCE_ROOT}/nl2.vpn.greenvpn.pro.crt"
SOURCE_KEY="${SOURCE_ROOT}/nl2.vpn.greenvpn.pro.key"
DEST_ROOT="/etc/greenvpn-naive-https-canary"
DEST_CERT="${DEST_ROOT}/server.crt"
DEST_KEY="${DEST_ROOT}/server.key"
DOMAIN_FILE="${DEST_ROOT}/certificate-domain"
STATE_ROOT="/var/lib/greenvpn-naive-cert-sync"
BACKUP_ROOT="${STATE_ROOT}/backups"
LOCK_FILE="${STATE_ROOT}/sync.lock"
SERVICE="greenvpn-naive-https-canary.service"

usage() {
  cat <<'EOF'
Synchronize the NL2 Hysteria ACME certificate into the isolated Naive service.

Usage:
  greenvpn_sync_naive_certificate.sh [--apply]

Default mode validates both certificate pairs and reports whether a copy is
needed. Apply mode creates a root-only rollback, atomically replaces the Naive
certificate pair, restarts only the Naive service and restores on any error.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --apply) APPLY=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
done

[[ "${EUID}" -eq 0 ]] || { echo "Run as root on NL2." >&2; exit 1; }
for command in cmp curl flock id install openssl python3 sha256sum stat systemctl; do
  command -v "${command}" >/dev/null 2>&1 || {
    echo "Required command missing: ${command}" >&2
    exit 1
  }
done
PUBLIC_IP="$(curl -4fsS --max-time 5 https://api.ipify.org || true)"
[[ "${PUBLIC_IP}" == "${EXPECTED_HOST}" ]] || {
  echo "Exact NL2 host guard failed." >&2
  exit 1
}
for path in "${SOURCE_CERT}" "${SOURCE_KEY}" "${DEST_CERT}" "${DEST_KEY}" "${DOMAIN_FILE}"; do
  [[ -f "${path}" && ! -L "${path}" ]] || {
    echo "Certificate material is missing or unsafe: ${path}" >&2
    exit 1
  }
done
[[ "$(tr -d '\r\n' < "${DOMAIN_FILE}")" == "${EXPECTED_DOMAIN}" ]] || {
  echo "Naive certificate-domain guard failed." >&2
  exit 1
}

certificate_public_key_hash() {
  openssl x509 -in "$1" -pubkey -noout |
    openssl pkey -pubin -outform DER 2>/dev/null |
    sha256sum |
    awk '{print $1}'
}

private_public_key_hash() {
  openssl pkey -in "$1" -pubout -outform DER 2>/dev/null |
    sha256sum |
    awk '{print $1}'
}

validate_pair() {
  local certificate="$1" private_key="$2" label="$3"
  openssl x509 -in "${certificate}" -noout -checkhost "${EXPECTED_DOMAIN}" >/dev/null
  openssl x509 -in "${certificate}" -noout -checkend 604800 >/dev/null
  [[ "$(certificate_public_key_hash "${certificate}")" == \
      "$(private_public_key_hash "${private_key}")" ]] || {
    echo "${label} certificate/key pair mismatch." >&2
    exit 1
  }
}

validate_pair "${SOURCE_CERT}" "${SOURCE_KEY}" "source"
validate_pair "${DEST_CERT}" "${DEST_KEY}" "destination"

install -d -m 0700 "${STATE_ROOT}" "${BACKUP_ROOT}"
exec 9>"${LOCK_FILE}"
flock -n 9 || {
  echo "Another certificate synchronization is already running." >&2
  exit 1
}
chmod 0600 "${LOCK_FILE}"

source_not_after="$(openssl x509 -in "${SOURCE_CERT}" -noout -enddate | cut -d= -f2-)"
destination_not_after="$(openssl x509 -in "${DEST_CERT}" -noout -enddate | cut -d= -f2-)"
copy_needed=1
if cmp -s "${SOURCE_CERT}" "${DEST_CERT}" && cmp -s "${SOURCE_KEY}" "${DEST_KEY}"; then
  copy_needed=0
fi

echo "source_certificate_ready=true"
echo "destination_certificate_ready=true"
echo "source_not_after=${source_not_after}"
echo "destination_not_after=${destination_not_after}"
echo "copy_needed=$([[ "${copy_needed}" -eq 1 ]] && echo true || echo false)"
echo "apply=${APPLY}"
echo "secrets_printed=false"
if [[ "${copy_needed}" -eq 0 ]]; then
  echo "status=unchanged"
  exit 0
fi
if [[ "${APPLY}" -ne 1 ]]; then
  echo "status=dry-run"
  exit 0
fi

timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
backup_dir="${BACKUP_ROOT}/${timestamp}"
[[ ! -e "${backup_dir}" ]] || {
  echo "Certificate rollback directory already exists." >&2
  exit 1
}
install -d -m 0700 "${backup_dir}"
install -m 0600 "${DEST_CERT}" "${backup_dir}/server.crt"
install -m 0600 "${DEST_KEY}" "${backup_dir}/server.key"

rollback_on_error() {
  local exit_code=$?
  trap - ERR
  local service_group
  service_group="$(id -gn greenvpn-naive 2>/dev/null || echo root)"
  install -m 0640 -o root -g "${service_group}" \
    "${backup_dir}/server.crt" "${DEST_CERT}" || true
  install -m 0640 -o root -g "${service_group}" \
    "${backup_dir}/server.key" "${DEST_KEY}" || true
  systemctl restart "${SERVICE}" >/dev/null 2>&1 || true
  echo "rollback=restored" >&2
  exit "${exit_code}"
}
trap rollback_on_error ERR

service_group="$(id -gn greenvpn-naive)"
temporary_cert="${DEST_ROOT}/.server.crt.sync-${timestamp}"
temporary_key="${DEST_ROOT}/.server.key.sync-${timestamp}"
install -m 0640 -o root -g "${service_group}" "${SOURCE_CERT}" "${temporary_cert}"
install -m 0640 -o root -g "${service_group}" "${SOURCE_KEY}" "${temporary_key}"
validate_pair "${temporary_cert}" "${temporary_key}" "staged"
mv -f -- "${temporary_cert}" "${DEST_CERT}"
mv -f -- "${temporary_key}" "${DEST_KEY}"
validate_pair "${DEST_CERT}" "${DEST_KEY}" "installed"

systemctl restart "${SERVICE}"
systemctl is-active --quiet "${SERVICE}"
tls_status="$(
  curl -sS -o /dev/null -w '%{http_code}:%{ssl_verify_result}' \
    --max-time 15 \
    --resolve "${EXPECTED_DOMAIN}:8443:${EXPECTED_HOST}" \
    "https://${EXPECTED_DOMAIN}:8443/"
)"
[[ "${tls_status}" == "404:0" ]] || {
  echo "Naive TLS verification failed after certificate synchronization." >&2
  exit 1
}

python3 - "${BACKUP_ROOT}" <<'PY'
import pathlib
import re
import shutil
import sys

root = pathlib.Path(sys.argv[1])
if root.is_symlink() or not root.is_dir():
    raise SystemExit("unsafe certificate backup root")
resolved = root.resolve(strict=True)
entries = sorted(
    (
        child
        for child in resolved.iterdir()
        if child.is_dir()
        and not child.is_symlink()
        and re.fullmatch(r"\d{8}T\d{6}Z", child.name)
    ),
    key=lambda child: child.name,
    reverse=True,
)
for child in entries[4:]:
    if child.resolve(strict=True).parent != resolved:
        raise SystemExit("unsafe certificate backup candidate")
    shutil.rmtree(child)
PY

trap - ERR
echo "status=updated"
echo "tls_status=${tls_status}"
echo "backup_dir=${backup_dir}"
echo "rollback=not_needed"
