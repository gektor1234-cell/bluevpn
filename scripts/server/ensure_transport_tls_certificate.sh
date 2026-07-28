#!/usr/bin/env bash
set -euo pipefail

APPLY=0
EXPECTED_PUBLIC_IP=""
APPROVED_EXISTING_HOST=""
CANARY_HOST=""
CANARY_DOMAIN=""
WEBROOT="/var/www/greenvpn-transport-acme"
NGINX_CONFIG="/etc/nginx/conf.d/greenvpn-transport-acme.conf"
RENEWAL_HOOK="/etc/letsencrypt/renewal-hooks/deploy/greenvpn-transport-reload"

usage() {
  cat <<'USAGE'
Ensure a trusted TLS certificate for an approved Green VPN transport data plane.

Default mode is dry-run. Apply requires the exact host/domain passport:
  ensure_transport_tls_certificate.sh --canary-host 37.220.85.211 \
      --canary-domain nl1.vpn.greenvpn.pro \
      --expected-public-ip 37.220.85.211 \
      --approved-existing-host 37.220.85.211 --apply

The script only accepts NL1 and London, preserves wg0, creates an exact nginx
HTTP-01 virtual host, validates nginx before reload, and installs a guarded
certificate renewal hook. It never stops nginx or changes the VPN firewall.
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --apply) APPLY=1; shift ;;
    --expected-public-ip) EXPECTED_PUBLIC_IP="${2:?missing expected public ip}"; shift 2 ;;
    --approved-existing-host) APPROVED_EXISTING_HOST="${2:?missing approved existing host}"; shift 2 ;;
    --canary-host) CANARY_HOST="${2:?missing canary host}"; shift 2 ;;
    --canary-domain) CANARY_DOMAIN="${2:?missing canary domain}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
done

if [[ "${EUID}" -ne 0 ]]; then
  echo "Run as root on the approved VPN data plane." >&2
  exit 1
fi
case "${CANARY_HOST}|${CANARY_DOMAIN}" in
  "37.220.85.211|nl1.vpn.greenvpn.pro"|"88.218.250.86|88-218-250-86.sslip.io")
    ;;
  *)
    echo "Unsupported Green VPN TLS host/domain passport." >&2
    exit 1
    ;;
esac
for command in certbot curl getent nginx openssl sha256sum systemctl; do
  command -v "${command}" >/dev/null 2>&1 || {
    echo "Required command is missing: ${command}" >&2
    exit 1
  }
done

PUBLIC_IP="$(curl -fsS --max-time 5 https://api.ipify.org || true)"
DNS_IP="$(getent ahostsv4 "${CANARY_DOMAIN}" | awk 'NR==1 {print $1}')"
if [[ "${PUBLIC_IP}" != "${CANARY_HOST}" || "${DNS_IP}" != "${CANARY_HOST}" ]]; then
  echo "Public IP or DNS does not match the approved TLS passport." >&2
  exit 1
fi
if [[ "${APPLY}" -eq 1 && ( \
  "${EXPECTED_PUBLIC_IP}" != "${CANARY_HOST}" \
  || "${APPROVED_EXISTING_HOST}" != "${CANARY_HOST}" ) ]]; then
  echo "Apply requires exact expected/approved host values." >&2
  exit 1
fi
systemctl is-active --quiet nginx || {
  echo "nginx is not active; refusing certificate work." >&2
  exit 1
}

CERT_FILE="/etc/letsencrypt/live/${CANARY_DOMAIN}/fullchain.pem"
CERT_KEY_FILE="/etc/letsencrypt/live/${CANARY_DOMAIN}/privkey.pem"
CERT_READY=0
if [[ -s "${CERT_FILE}" && -s "${CERT_KEY_FILE}" ]] \
  && openssl x509 -in "${CERT_FILE}" -noout -checkhost "${CANARY_DOMAIN}" >/dev/null 2>&1 \
  && openssl x509 -in "${CERT_FILE}" -noout -checkend 604800 >/dev/null 2>&1; then
  CERT_READY=1
fi

echo "Green VPN transport TLS certificate plan"
echo "public_ip=${PUBLIC_IP}"
echo "domain=${CANARY_DOMAIN}"
echo "dns_ip=${DNS_IP}"
echo "certificate_ready=${CERT_READY}"
echo "mode=$([[ "${APPLY}" -eq 1 ]] && echo apply || echo dry-run)"
echo "stable_wireguard=not_changed"

if [[ "${APPLY}" -ne 1 ]]; then
  echo "Dry-run only. Re-run with exact host approval and --apply."
  exit 0
fi

WG_HASH_BEFORE="$(sha256sum /etc/wireguard/wg0.conf | awk '{print $1}')"
STAMP="$(date -u +%Y%m%dT%H%M%SZ)"
BACKUP_ROOT="/root/greenvpn-transport-tls-prechange/${STAMP}"
mkdir -p "${BACKUP_ROOT}"
chmod 0700 "${BACKUP_ROOT}"
HAD_NGINX_CONFIG=0
if [[ -e "${NGINX_CONFIG}" ]]; then
  cp -a -- "${NGINX_CONFIG}" "${BACKUP_ROOT}/"
  HAD_NGINX_CONFIG=1
fi

rollback_nginx() {
  if [[ "${HAD_NGINX_CONFIG}" -eq 1 ]]; then
    cp -a -- "${BACKUP_ROOT}/$(basename "${NGINX_CONFIG}")" "${NGINX_CONFIG}"
  else
    rm -f -- "${NGINX_CONFIG}"
  fi
  nginx -t >/dev/null 2>&1 && systemctl reload nginx >/dev/null 2>&1 || true
}
trap 'rollback_nginx' ERR

DOMAIN_VHOST_EXISTS=0
if nginx -T 2>/dev/null | grep -Fq "server_name ${CANARY_DOMAIN};"; then
  DOMAIN_VHOST_EXISTS=1
fi
if [[ "${CERT_READY}" -ne 1 || "${DOMAIN_VHOST_EXISTS}" -ne 1 || -e "${NGINX_CONFIG}" ]]; then
  install -d -m 0755 "${WEBROOT}/.well-known/acme-challenge"
  cat > "${NGINX_CONFIG}.tmp" <<EOF
server {
    listen 80;
    listen [::]:80;
    server_name ${CANARY_DOMAIN};

    location ^~ /.well-known/acme-challenge/ {
        root ${WEBROOT};
        default_type text/plain;
        try_files \$uri =404;
    }

    location / {
        return 404;
    }
}
EOF
  chmod 0644 "${NGINX_CONFIG}.tmp"
  mv -f -- "${NGINX_CONFIG}.tmp" "${NGINX_CONFIG}"
  nginx -t
  systemctl reload nginx
else
  echo "existing_domain_vhost=reused"
fi

if [[ "${CERT_READY}" -ne 1 ]]; then
  certbot certonly \
    --webroot --webroot-path "${WEBROOT}" \
    --cert-name "${CANARY_DOMAIN}" \
    --domain "${CANARY_DOMAIN}" \
    --preferred-challenges http \
    --non-interactive --agree-tos --register-unsafely-without-email
fi
openssl x509 -in "${CERT_FILE}" -noout -checkhost "${CANARY_DOMAIN}"
openssl x509 -in "${CERT_FILE}" -noout -checkend 604800

install -d -m 0755 "$(dirname "${RENEWAL_HOOK}")"
cat > "${RENEWAL_HOOK}.tmp" <<'HOOK'
#!/usr/bin/env bash
set -euo pipefail

HYSTERIA_CONFIG="/etc/greenvpn-transport/hysteria2-canary.yaml"
NAIVE_ROOT="/etc/greenvpn-naive-https-canary"
if [[ -n "${RENEWED_LINEAGE:-}" && -f "${HYSTERIA_CONFIG}" ]] \
  && grep -Fq "${RENEWED_LINEAGE}/" "${HYSTERIA_CONFIG}"; then
  systemctl try-restart greenvpn-hysteria2-canary.service
fi
if [[ -n "${RENEWED_LINEAGE:-}" && -s "${NAIVE_ROOT}/certificate-domain" ]]; then
  EXPECTED_DOMAIN="$(tr -d '\r\n' < "${NAIVE_ROOT}/certificate-domain")"
  case " ${RENEWED_DOMAINS:-} " in
    *" ${EXPECTED_DOMAIN} "*)
      SERVICE_GROUP="$(id -gn greenvpn-naive)"
      install -m 0640 -o root -g "${SERVICE_GROUP}" \
        "${RENEWED_LINEAGE}/fullchain.pem" "${NAIVE_ROOT}/server.crt"
      install -m 0640 -o root -g "${SERVICE_GROUP}" \
        "${RENEWED_LINEAGE}/privkey.pem" "${NAIVE_ROOT}/server.key"
      systemctl try-restart greenvpn-naive-https-canary.service
      ;;
  esac
fi
HOOK
chmod 0755 "${RENEWAL_HOOK}.tmp"
mv -f -- "${RENEWAL_HOOK}.tmp" "${RENEWAL_HOOK}"

[[ "$(sha256sum /etc/wireguard/wg0.conf | awk '{print $1}')" == "${WG_HASH_BEFORE}" ]]
systemctl is-active --quiet wg-quick@wg0.service
trap - ERR
echo "transport_tls_certificate=ready"
echo "certificate_domain=${CANARY_DOMAIN}"
echo "backup=${BACKUP_ROOT}"
echo "stable_wireguard=verified_unchanged"
