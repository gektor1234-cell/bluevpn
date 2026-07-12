#!/usr/bin/env bash
set -euo pipefail

APPLY=0
EXPECTED_PUBLIC_IP=""
APPROVED_EXISTING_HOST=""
CANARY_HOST="5.129.216.42"
SERVER_SERVICE="greenvpn-dnstt-canary"
SOCKS_SERVICE="greenvpn-dnstt-socks-canary"
INSTALL_ROOT="/opt/greenvpn-canary/dnstt"
CONFIG_ROOT="/etc/greenvpn-dnstt-canary"
FAILED_STAGING_CONFIG_ROOT="/etc/greenvpn-transport/dnstt-canary"
CLIENT_CONFIG_FILE="/etc/greenvpn-transport/dnstt-canary.client.json"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --apply) APPLY=1; shift ;;
    --expected-public-ip) EXPECTED_PUBLIC_IP="${2:?missing expected public ip}"; shift 2 ;;
    --approved-existing-host) APPROVED_EXISTING_HOST="${2:?missing approved existing host}"; shift 2 ;;
    -h|--help)
      echo "Usage: remove_dnstt_canary.sh --expected-public-ip 5.129.216.42 --approved-existing-host 5.129.216.42 [--apply]"
      exit 0
      ;;
    *) echo "Unknown argument: $1" >&2; exit 2 ;;
  esac
done

[[ "${EUID}" -eq 0 ]] || { echo "Run as root on NL2." >&2; exit 1; }
PUBLIC_IP="$(curl -4fsS --max-time 5 https://api.ipify.org || true)"
[[ "${PUBLIC_IP}" == "${CANARY_HOST}" ]] || { echo "Refusing dnstt rollback outside exact NL2 host." >&2; exit 1; }

echo "Green VPN dnstt canary rollback plan"
echo "public_ip=${PUBLIC_IP}"
echo "server_service=${SERVER_SERVICE}.service"
echo "socks_service=${SOCKS_SERVICE}.service"
echo "registrar_dns=not_changed"
echo "dnsmasq=not_changed"
echo "stable_transports=not_changed"
echo "mode=$([[ "${APPLY}" -eq 1 ]] && echo apply || echo dry-run)"

if [[ "${APPLY}" -ne 1 ]]; then
  echo "Dry-run only. Exact host approval and --apply are required."
  exit 0
fi
if [[ "${EXPECTED_PUBLIC_IP}" != "${CANARY_HOST}" || "${APPROVED_EXISTING_HOST}" != "${CANARY_HOST}" ]]; then
  echo "Apply requires exact NL2 expected/approved host values." >&2
  exit 1
fi

backup="/root/greenvpn-dnstt-rollback/$(date -u +%Y%m%dT%H%M%SZ)"
install -d -m 0700 "${backup}"
for path in "${CONFIG_ROOT}" "${FAILED_STAGING_CONFIG_ROOT}" "${CLIENT_CONFIG_FILE}" "${INSTALL_ROOT}" \
  "/etc/systemd/system/${SERVER_SERVICE}.service" "/etc/systemd/system/${SOCKS_SERVICE}.service"; do
  [[ ! -e "${path}" ]] || cp -a -- "${path}" "${backup}/"
done

systemctl disable --now "${SERVER_SERVICE}.service" "${SOCKS_SERVICE}.service" 2>/dev/null || true
rm -f -- "/etc/systemd/system/${SERVER_SERVICE}.service" "/etc/systemd/system/${SOCKS_SERVICE}.service"
systemctl daemon-reload
rm -rf -- "${CONFIG_ROOT}" "${FAILED_STAGING_CONFIG_ROOT}" "${INSTALL_ROOT}"
rm -f -- "${CLIENT_CONFIG_FILE}"

if ss -H -lunp | awk -v endpoint="${CANARY_HOST}:53" '$4 == endpoint {found=1} END {exit !found}'; then
  echo "dnstt UDP listener remained after rollback." >&2
  exit 1
fi
for unit in wg-quick@wg0 greenvpn-hysteria2-canary greenvpn-vless-reality-canary greenvpn-naive-https-canary; do
  systemctl is-active --quiet "${unit}.service" || { echo "Stable transport is not active after rollback: ${unit}" >&2; exit 1; }
done

echo "dnstt_canary=removed"
echo "backup=${backup}"
echo "stable_transports=active"
echo "remove_registrar_records_manually=A:tns.greenvpn.pro,NS:t.greenvpn.pro"
