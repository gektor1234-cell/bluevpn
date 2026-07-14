#!/usr/bin/env bash
set -Eeuo pipefail

readonly REVIEW_PATH="/yookassa-review-20260711"
readonly REVIEW_ROOT="/var/www/paid-beta${REVIEW_PATH}"
readonly API_SNIPPET="/etc/nginx/snippets/greenvpn-paid-beta-api.conf"
readonly BACKUP_ROOT="/root/greenvpn-yookassa-review-backups"
readonly MARKER="# Green VPN YooKassa recurring-payment review"

if [[ "${EUID}" -ne 0 ]]; then
  echo "Run as root." >&2
  exit 1
fi

for file in index.html autorenew-on.png autorenew-off.png; do
  if [[ ! -s "${REVIEW_ROOT}/${file}" ]]; then
    echo "Missing review artifact: ${REVIEW_ROOT}/${file}" >&2
    exit 1
  fi
done

if [[ ! -f "${API_SNIPPET}" ]]; then
  echo "Missing Nginx API snippet: ${API_SNIPPET}" >&2
  exit 1
fi

if grep -Fq "${MARKER}" "${API_SNIPPET}"; then
  nginx -t
  echo "YooKassa review route is already installed."
  exit 0
fi

timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
backup_dir="${BACKUP_ROOT}/${timestamp}"
mkdir -p "${backup_dir}"
chmod 700 "${BACKUP_ROOT}" "${backup_dir}"
cp -a "${API_SNIPPET}" "${backup_dir}/greenvpn-paid-beta-api.conf"

candidate="$(mktemp)"
trap 'rm -f "${candidate}"' EXIT
cat "${API_SNIPPET}" > "${candidate}"
cat >> "${candidate}" <<'NGINX'

# Green VPN YooKassa recurring-payment review
location = /yookassa-review-20260711 {
    return 302 /yookassa-review-20260711/;
}

location ^~ /yookassa-review-20260711/ {
    root /var/www/paid-beta;
    index index.html;
    try_files $uri $uri/ =404;
    autoindex off;
    add_header Cache-Control "private, no-store" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header Referrer-Policy "strict-origin-when-cross-origin" always;
    add_header X-Robots-Tag "noindex, nofollow, noarchive" always;
}
NGINX

install -o root -g root -m 0644 "${candidate}" "${API_SNIPPET}"
if ! nginx -t; then
  cp -a "${backup_dir}/greenvpn-paid-beta-api.conf" "${API_SNIPPET}"
  nginx -t
  echo "Nginx validation failed; the original snippet was restored." >&2
  exit 1
fi

systemctl reload nginx
echo "YooKassa review route installed; backup: ${backup_dir}"
