#!/usr/bin/env bash
set -euo pipefail

APPLY=0
EXPECTED_PUBLIC_IP=""
APPROVED_EXISTING_HOST=""
CANARY_HOST="5.129.216.42"
DNSTT_SERVICE="greenvpn-dnstt-canary"
FRONT_SERVICE="greenvpn-dnstt-dns-front"
DNSDIST_CONFIG="/etc/dnsdist/dnsdist-greenvpn-dnstt.conf"
DNSDIST_UNIT="/etc/systemd/system/${FRONT_SERVICE}.service"
DNSTT_DROPIN_DIR="/etc/systemd/system/${DNSTT_SERVICE}.service.d"
DNSTT_DROPIN="${DNSTT_DROPIN_DIR}/dns-front.conf"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --apply) APPLY=1; shift ;;
    --expected-public-ip) EXPECTED_PUBLIC_IP="${2:?missing expected public ip}"; shift 2 ;;
    --approved-existing-host) APPROVED_EXISTING_HOST="${2:?missing approved existing host}"; shift 2 ;;
    -h|--help)
      echo "Usage: remove_dnstt_dns_frontend.sh --expected-public-ip 5.129.216.42 --approved-existing-host 5.129.216.42 [--apply]"
      exit 0
      ;;
    *) echo "Unknown argument: $1" >&2; exit 2 ;;
  esac
done

[[ "${EUID}" -eq 0 ]] || { echo "Run as root on NL2." >&2; exit 1; }
PUBLIC_IP="$(curl -4fsS --max-time 5 https://api.ipify.org || true)"
[[ "${PUBLIC_IP}" == "${CANARY_HOST}" ]] || { echo "Refusing DNS frontend rollback outside exact NL2 host." >&2; exit 1; }

echo "Green VPN dnstt DNS frontend rollback plan"
echo "public_ip=${PUBLIC_IP}"
echo "frontend_service=${FRONT_SERVICE}.service"
echo "direct_dnstt_listener=${CANARY_HOST}:53/udp"
echo "registrar_dns=not_changed"
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

backup="/root/greenvpn-dnstt-dns-front-rollback/$(date -u +%Y%m%dT%H%M%SZ)"
install -d -m 0700 "${backup}"
for path in "${DNSDIST_CONFIG}" "${DNSDIST_UNIT}" "${DNSTT_DROPIN}"; do
  [[ ! -e "${path}" ]] || cp -a -- "${path}" "${backup}/"
done

systemctl disable --now "${FRONT_SERVICE}.service" >/dev/null 2>&1 || true
rm -f -- "${DNSDIST_UNIT}" "${DNSDIST_CONFIG}" "${DNSTT_DROPIN}"
rmdir "${DNSTT_DROPIN_DIR}" >/dev/null 2>&1 || true
systemctl daemon-reload
systemctl restart "${DNSTT_SERVICE}.service"

systemctl is-active --quiet "${DNSTT_SERVICE}.service"
ss -H -lunp | awk -v endpoint="${CANARY_HOST}:53" '$4 == endpoint && /dnstt-server/ {found=1} END {exit !found}'
if ss -H -lntp | awk -v endpoint="${CANARY_HOST}:53" '$4 == endpoint {found=1} END {exit !found}'; then
  echo "Public TCP/53 remained after DNS frontend rollback." >&2
  exit 1
fi
for unit in wg-quick@wg0 greenvpn-hysteria2-canary greenvpn-vless-reality-canary greenvpn-naive-https-canary; do
  systemctl is-active --quiet "${unit}.service" || { echo "Required transport is not active after rollback: ${unit}" >&2; exit 1; }
done

echo "dnstt_dns_frontend=removed"
echo "direct_dnstt_listener=restored"
echo "stable_transports=active"
echo "backup=${backup}"
