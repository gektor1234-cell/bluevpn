#!/usr/bin/env bash
set -euo pipefail

APPLY=0
EXPECTED_PUBLIC_IP=""
APPROVED_EXISTING_HOST=""
CANARY_HOST="5.129.216.42"
CANARY_PORT="8443"
SERVICE_NAME="greenvpn-naive-https-canary"
CONFIG_FILE="/etc/greenvpn-naive-https-canary"
CLIENT_CONFIG_FILE="/etc/greenvpn-transport/naive-https-canary.client.json"
INSTALL_ROOT="/opt/greenvpn-canary/naive-https"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --apply) APPLY=1; shift ;;
    --expected-public-ip) EXPECTED_PUBLIC_IP="${2:?missing expected public ip}"; shift 2 ;;
    --approved-existing-host) APPROVED_EXISTING_HOST="${2:?missing approved existing host}"; shift 2 ;;
    -h|--help)
      echo "Dry-run by default; exact NL2 host approval and --apply are required."
      exit 0
      ;;
    *) echo "Unknown argument: $1" >&2; exit 2 ;;
  esac
done

[[ "${EUID}" -eq 0 ]] || { echo "Run as root on NL2." >&2; exit 1; }
PUBLIC_IP="$(curl -fsS --max-time 5 https://api.ipify.org || true)"
[[ "${PUBLIC_IP}" == "${CANARY_HOST}" ]] || {
  echo "Refusing Naive HTTPS rollback outside exact NL2 host." >&2
  exit 1
}

echo "Green VPN Naive HTTPS canary rollback plan"
echo "public_ip=${PUBLIC_IP}"
echo "service=${SERVICE_NAME}.service"
echo "listen=tcp/${CANARY_PORT}"
echo "stable_wireguard=not_changed"
echo "amneziawg_canary=not_changed"
echo "hysteria2_canary=not_changed"
echo "vless_reality_canary=not_changed"
echo "public_catalog=not_changed"
echo "mode=$([[ "${APPLY}" -eq 1 ]] && echo apply || echo dry-run)"

if [[ "${APPLY}" -ne 1 ]]; then
  echo "Dry-run only."
  exit 0
fi
if [[ "${EXPECTED_PUBLIC_IP}" != "${CANARY_HOST}" \
  || "${APPROVED_EXISTING_HOST}" != "${CANARY_HOST}" ]]; then
  echo "Apply requires exact NL2 expected/approved host values." >&2
  exit 1
fi

umask 077
STAMP="$(date -u +%Y%m%dT%H%M%SZ)"
BACKUP_ROOT="/root/greenvpn-naive-https-removed/${STAMP}"
mkdir -p "${BACKUP_ROOT}"
chmod 0700 "${BACKUP_ROOT}"
for path in \
  "/etc/systemd/system/${SERVICE_NAME}.service" \
  "${CONFIG_FILE}" "${CLIENT_CONFIG_FILE}" "${INSTALL_ROOT}"; do
  [[ ! -e "${path}" ]] || cp -a -- "${path}" "${BACKUP_ROOT}/"
done

systemctl disable --now "${SERVICE_NAME}.service" >/dev/null 2>&1 || true
rm -f -- "/etc/systemd/system/${SERVICE_NAME}.service" "${CLIENT_CONFIG_FILE}"
rm -rf -- "${CONFIG_FILE}" "${INSTALL_ROOT}"
systemctl daemon-reload
systemctl reset-failed "${SERVICE_NAME}.service" >/dev/null 2>&1 || true
if ss -H -lnt | awk '{print $4}' | grep -Eq "(:|])${CANARY_PORT}$"; then
  echo "TCP/${CANARY_PORT} remains occupied after rollback." >&2
  exit 1
fi
for stable_service in \
  wg-quick@wg0.service greenvpn-amneziawg-canary.service \
  greenvpn-hysteria2-canary.service greenvpn-vless-reality-canary.service; do
  systemctl is-active --quiet "${stable_service}"
done

echo "removed=true"
echo "backup=${BACKUP_ROOT}"
echo "stable_transports=active"
