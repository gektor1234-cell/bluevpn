#!/usr/bin/env bash
set -euo pipefail

APPLY=0
EXPECTED_HOSTNAME="ams-1-vm-p28w"
LOCAL_IPV4="37.220.85.211"
API_HOST="api.greenvpn.pro"
NGINX_LINK="/etc/nginx/sites-enabled/greenvpn-api.conf"
NGINX_CONFIG="/etc/nginx/sites-available/greenvpn-api.conf"
RENEWAL_CONFIG="/etc/letsencrypt/renewal/api.greenvpn.pro.conf"
BACKUP_ROOT="/root/greenvpn-maintenance-backups"

usage() {
  cat <<'USAGE'
Retire the obsolete api.greenvpn.pro TLS vhost and Certbot timer on NL1.

  retire_nl1_legacy_api_tls.sh [--apply]

Dry-run is the default. The backend's default HTTP fallback and the VPN
interface remain active. Apply creates a root-only rollback copy first.
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
[[ -L "${NGINX_LINK}" ]] || { echo "Legacy nginx link is missing." >&2; exit 1; }
[[ "$(readlink -f -- "${NGINX_LINK}")" == "${NGINX_CONFIG}" ]] || {
  echo "Legacy nginx target guard failed." >&2
  exit 1
}
[[ -f "${NGINX_CONFIG}" && ! -L "${NGINX_CONFIG}" ]] || exit 1
[[ -f "${RENEWAL_CONFIG}" && ! -L "${RENEWAL_CONFIG}" ]] || exit 1
grep -Fq "server_name ${API_HOST};" "${NGINX_CONFIG}" || {
  echo "Expected legacy server_name is missing." >&2
  exit 1
}
grep -Fq "authenticator = nginx" "${RENEWAL_CONFIG}" || {
  echo "Unexpected Certbot renewal method." >&2
  exit 1
}

mapfile -t API_IPV4 < <(getent ahostsv4 "${API_HOST}" | awk '{print $1}' | sort -u)
[[ "${#API_IPV4[@]}" -gt 0 ]] || { echo "API DNS lookup failed." >&2; exit 1; }
for ip in "${API_IPV4[@]}"; do
  [[ "${ip}" != "${LOCAL_IPV4}" ]] || {
    echo "API DNS still points at NL1; refusing retirement." >&2
    exit 1
  }
done

systemctl is-active --quiet wg-quick@wg0.service || {
  echo "VPN interface is not active." >&2
  exit 1
}
curl --fail --silent --show-error --max-time 10 http://127.0.0.1/healthz >/dev/null
nginx -t

echo "nl1_legacy_tls_apply=${APPLY}"
echo "nl1_legacy_tls_api_ipv4=$(IFS=,; echo "${API_IPV4[*]}")"
echo "nl1_legacy_tls_certbot_timer_enabled=$(systemctl is-enabled certbot.timer 2>/dev/null || true)"
echo "nl1_legacy_tls_certbot_timer_active=$(systemctl is-active certbot.timer 2>/dev/null || true)"
[[ "${APPLY}" -eq 1 ]] || exit 0

TIMESTAMP="$(date -u +%Y%m%dT%H%M%SZ)"
BACKUP_DIR="${BACKUP_ROOT}/${TIMESTAMP}-nl1-legacy-api-tls"
install -d -m 0700 -- "${BACKUP_DIR}"
install -m 0600 -- "${NGINX_CONFIG}" "${BACKUP_DIR}/greenvpn-api.conf"
install -m 0600 -- "${RENEWAL_CONFIG}" "${BACKUP_DIR}/api.greenvpn.pro.renewal.conf"

systemctl disable --now certbot.timer
rm -f -- "${NGINX_LINK}"

if ! nginx -t; then
  ln -s -- "${NGINX_CONFIG}" "${NGINX_LINK}"
  systemctl enable --now certbot.timer
  echo "nginx validation failed; rollback completed." >&2
  exit 1
fi
systemctl reload nginx
systemctl reset-failed certbot.service || true

curl --fail --silent --show-error --max-time 10 http://127.0.0.1/healthz >/dev/null
systemctl is-active --quiet wg-quick@wg0.service
[[ ! -e "${NGINX_LINK}" ]] || exit 1
[[ "$(systemctl is-enabled certbot.timer 2>/dev/null || true)" == "disabled" ]] || exit 1
if systemctl --failed --no-legend | grep -F 'certbot.service' >/dev/null; then
  echo "Certbot remains failed after retirement." >&2
  exit 1
fi

echo "nl1_legacy_tls_status=retired"
echo "nl1_legacy_tls_rollback_dir=${BACKUP_DIR}"
