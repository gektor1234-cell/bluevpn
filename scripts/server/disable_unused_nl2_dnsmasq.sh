#!/usr/bin/env bash
set -euo pipefail

APPLY=0
EXPECTED_HOSTNAME="greenvpn-nl1-vpn-20260511"
DNSMASQ_CONFIG="/etc/dnsmasq.d/greenvpn-wg0.conf"
declare -a REQUIRED_SERVICES=(
  "wg-quick@wg0.service"
  "greenvpn-amneziawg-canary.service"
  "greenvpn-hysteria2-canary.service"
  "greenvpn-vless-reality-canary.service"
  "greenvpn-naive-https-canary.service"
  "greenvpn-dnstt-canary.service"
  "greenvpn-dnstt-dns-front.service"
  "greenvpn-dnstt-socks-canary.service"
)

usage() {
  cat <<'USAGE'
Disable the unused dnsmasq unit that conflicts with the NL2 DNS canary.

  disable_unused_nl2_dnsmasq.sh [--apply]

Dry-run is the default. The script requires the VPN interface and every
isolated transport canary service to be healthy before and after the change.
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
[[ -f "${DNSMASQ_CONFIG}" && ! -L "${DNSMASQ_CONFIG}" ]] || {
  echo "Expected dnsmasq configuration is missing or unsafe." >&2
  exit 1
}
grep -Fxq 'bind-interfaces' "${DNSMASQ_CONFIG}" || exit 1
grep -Fxq 'listen-address=10.10.0.1' "${DNSMASQ_CONFIG}" || exit 1
grep -Fxq 'port=53' "${DNSMASQ_CONFIG}" || exit 1

for unit in "${REQUIRED_SERVICES[@]}"; do
  systemctl is-active --quiet "${unit}" || {
    echo "Required service is not active: ${unit}" >&2
    exit 1
  }
done
ss -lntup | grep -F '5.129.216.42:53' >/dev/null || {
  echo "Authoritative DNS frontend is not listening." >&2
  exit 1
}

echo "nl2_dnsmasq_apply=${APPLY}"
echo "nl2_dnsmasq_enabled=$(systemctl is-enabled dnsmasq.service 2>/dev/null || true)"
echo "nl2_dnsmasq_active=$(systemctl is-active dnsmasq.service 2>/dev/null || true)"
[[ "${APPLY}" -eq 1 ]] || exit 0

systemctl disable --now dnsmasq.service || true
systemctl mask dnsmasq.service
systemctl reset-failed dnsmasq.service || true

for unit in "${REQUIRED_SERVICES[@]}"; do
  systemctl is-active --quiet "${unit}"
done
ss -lntup | grep -F '5.129.216.42:53' >/dev/null
[[ "$(systemctl is-enabled dnsmasq.service 2>/dev/null || true)" == "masked" ]] || exit 1
if systemctl --failed --no-legend | grep -F 'dnsmasq.service' >/dev/null; then
  echo "dnsmasq remains failed after retirement." >&2
  exit 1
fi

echo "nl2_dnsmasq_status=disabled_and_masked"
