#!/usr/bin/env bash
set -euo pipefail

EXPECTED_HOSTNAME=""
SITE_CONFIG="/etc/nginx/sites-enabled/greenvpn-site"
APPLY=0

usage() {
  cat <<'USAGE'
Install the Green VPN main-domain /legal/ reverse-proxy route.

  install_main_site_legal_proxy.sh --expected-hostname HOST [--site-config PATH] [--apply]

Dry-run is the default. Apply creates a root-only backup, validates nginx,
reloads it, and verifies the legal page through loopback TLS. On any failure the
original configuration is restored automatically.
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --expected-hostname) EXPECTED_HOSTNAME="${2:?missing hostname}"; shift 2 ;;
    --site-config) SITE_CONFIG="${2:?missing site config}"; shift 2 ;;
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

for command in curl hostname nginx python3 readlink systemctl; do
  command -v "${command}" >/dev/null 2>&1 || {
    echo "Required command missing: ${command}" >&2
    exit 1
  }
done

CONFIG_REAL="$(readlink -f -- "${SITE_CONFIG}")"
case "${CONFIG_REAL}" in
  /etc/nginx/sites-available/*|/etc/nginx/sites-enabled/*) ;;
  *) echo "Unsafe nginx config path: ${CONFIG_REAL}" >&2; exit 1 ;;
esac
[[ -f "${CONFIG_REAL}" && ! -L "${CONFIG_REAL}" ]] || {
  echo "Resolved nginx config is not a regular file." >&2
  exit 1
}
grep -Eq 'server_name[[:space:]]+greenvpn\.pro([[:space:]]|;)' "${CONFIG_REAL}" || {
  echo "Target config does not own greenvpn.pro." >&2
  exit 1
}

if grep -q '# BEGIN GREENVPN SITE BACKEND ROUTES' "${CONFIG_REAL}"; then
  echo "legal_proxy_status=already_installed"
  nginx -t
  exit 0
fi

echo "legal_proxy_plan=insert_exact_legal_location"
echo "legal_proxy_target=${CONFIG_REAL}"
echo "legal_proxy_apply=${APPLY}"
[[ "${APPLY}" -eq 1 ]] || exit 0

STAMP="$(date -u +%Y%m%dT%H%M%SZ)"
BACKUP_ROOT="/root/greenvpn-nginx-backups"
BACKUP_PATH="${BACKUP_ROOT}/${STAMP}-greenvpn-site-before-legal-proxy"
mkdir -p -- "${BACKUP_ROOT}"
chmod 0700 "${BACKUP_ROOT}"
cp -a -- "${CONFIG_REAL}" "${BACKUP_PATH}"
chmod 0600 "${BACKUP_PATH}"

VERIFY_PAGE=""
rollback() {
  [[ -z "${VERIFY_PAGE}" ]] || rm -f -- "${VERIFY_PAGE}"
  cp -a -- "${CONFIG_REAL}" "${BACKUP_PATH}.failed"
  chmod 0600 "${BACKUP_PATH}.failed"
  cp -a -- "${BACKUP_PATH}" "${CONFIG_REAL}"
  nginx -t >/dev/null 2>&1 && systemctl reload nginx >/dev/null 2>&1 || true
}
trap rollback ERR

python3 - "${CONFIG_REAL}" <<'PY'
from pathlib import Path
import os
import sys

path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8")
needle = """    location / {
        try_files $uri $uri/ /index.html;
    }
"""
if text.count(needle) != 1:
    raise SystemExit("Expected one exact static fallback location.")
block = """    # BEGIN GREENVPN SITE BACKEND ROUTES
    location ^~ /legal/ {
        proxy_pass http://127.0.0.1:8000;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto https;
        proxy_set_header X-Forwarded-Host $host;
        proxy_http_version 1.1;
        proxy_set_header Connection "";
        proxy_connect_timeout 10s;
        proxy_send_timeout 30s;
        proxy_read_timeout 30s;
    }
    # END GREENVPN SITE BACKEND ROUTES

"""
temporary = path.with_name(path.name + ".legal-proxy.tmp")
temporary.write_text(text.replace(needle, block + needle), encoding="utf-8")
os.chmod(temporary, path.stat().st_mode & 0o777)
os.replace(temporary, path)
PY

nginx -t
systemctl reload nginx
VERIFY_PAGE="$(mktemp)"
VERIFIED=0
for _attempt in {1..20}; do
  if curl -fsS --noproxy '*' --max-time 15 --resolve greenvpn.pro:443:127.0.0.1 \
      https://greenvpn.pro/legal/offer >"${VERIFY_PAGE}" && \
      python3 - "${VERIFY_PAGE}" <<'PY'
from pathlib import Path
import sys

text = Path(sys.argv[1]).read_text(encoding="utf-8")
raise SystemExit(0 if '<html lang="ru">' in text and "Green VPN</title>" in text else 1)
PY
  then
    VERIFIED=1
    break
  fi
  sleep 0.5
done
if [[ "${VERIFIED}" -ne 1 ]]; then
  python3 - "${VERIFY_PAGE}" <<'PY'
from pathlib import Path
import sys

text = Path(sys.argv[1]).read_text(encoding="utf-8", errors="replace")
title_start = text.find("<title>")
title_end = text.find("</title>", title_start)
title = text[title_start:title_end + len("</title>")] if title_start >= 0 and title_end >= 0 else "<missing>"
raise SystemExit(f"Legal offer content verification failed: size={len(text)} title={title!r}")
PY
fi
rm -f -- "${VERIFY_PAGE}"
VERIFY_PAGE=""

trap - ERR
echo "legal_proxy_status=installed"
echo "legal_proxy_backup=${BACKUP_PATH}"
