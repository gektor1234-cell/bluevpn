#!/usr/bin/env bash
set -euo pipefail

CANARY_HOST="5.129.216.42"
CANARY_DOMAIN="nl2.vpn.greenvpn.pro"
CANARY_PORT="2443"
SOCKS_PORT="1980"
BASE_STACK_ONLY=0
SERVICE_NAME="greenvpn-hysteria2-canary"
CONFIG_FILE="/etc/greenvpn-transport/hysteria2-canary.yaml"
CLIENT_CONFIG_FILE="/etc/greenvpn-transport/hysteria2-canary.client.yaml"
INSTALL_ROOT="/opt/greenvpn-canary/hysteria2"
EXPECTED_VERSION="2.9.3"
EXPECTED_SHA256="66dbdb0608f25f3057b433afe975a9fc1af2ca8e512479e294988b3ef363d6c1"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --canary-host) CANARY_HOST="${2:?missing canary host}"; shift 2 ;;
    --canary-domain) CANARY_DOMAIN="${2:?missing canary domain}"; shift 2 ;;
    --base-stack-only) BASE_STACK_ONLY=1; shift ;;
    -h|--help)
      echo "Usage: $0 [--canary-host IP --canary-domain DOMAIN] [--base-stack-only]"
      exit 0
      ;;
    *) echo "Unknown argument: $1" >&2; exit 2 ;;
  esac
done

[[ "${EUID}" -eq 0 ]] || { echo "Run as root on an approved VPN data plane." >&2; exit 1; }
case "${CANARY_HOST}|${CANARY_DOMAIN}" in
  "5.129.216.42|nl2.vpn.greenvpn.pro"|"37.220.85.211|nl1.vpn.greenvpn.pro"|"88.218.250.86|88-218-250-86.sslip.io")
    ;;
  *) echo "blocker=unsupported_host_domain_passport" >&2; exit 1 ;;
esac
for command in curl getent sha256sum ss stat systemctl; do
  command -v "${command}" >/dev/null 2>&1 || {
    echo "blocker=missing_command:${command}" >&2
    exit 1
  }
done

PUBLIC_IP="$(curl -4fsS --max-time 5 https://api.ipify.org || true)"
[[ "${PUBLIC_IP}" == "${CANARY_HOST}" ]] || { echo "blocker=wrong_public_ip" >&2; exit 1; }
[[ "$(getent ahostsv4 "${CANARY_DOMAIN}" | awk 'NR==1 {print $1}')" == "${CANARY_HOST}" ]] || {
  echo "blocker=domain_mismatch" >&2
  exit 1
}
systemctl is-active --quiet "${SERVICE_NAME}.service" || { echo "blocker=service_inactive" >&2; exit 1; }

for path in "${CONFIG_FILE}" "${CLIENT_CONFIG_FILE}"; do
  [[ -f "${path}" && ! -L "${path}" ]] || { echo "blocker=unsafe_config_path" >&2; exit 1; }
  [[ "$(stat -c '%U:%G:%a' "${path}")" == "root:root:600" ]] || {
    echo "blocker=config_owner_or_mode" >&2
    exit 1
  }
done
[[ "$(sha256sum "${INSTALL_ROOT}/bin/hysteria" | awk '{print $1}')" == "${EXPECTED_SHA256}" ]] || {
  echo "blocker=binary_hash_mismatch" >&2
  exit 1
}
"${INSTALL_ROOT}/bin/hysteria" version 2>&1 | grep -Fq "v${EXPECTED_VERSION}" || {
  echo "blocker=version_mismatch" >&2
  exit 1
}
ss -H -lun | awk '{print $4}' | grep -Eq "(:|])${CANARY_PORT}$" || {
  echo "blocker=udp_listener_missing" >&2
  exit 1
}
if ss -H -lnt | awk '{print $4}' | grep -Eq "(:|])${SOCKS_PORT}$"; then
  echo "blocker=smoke_port_in_use" >&2
  exit 1
fi

WORK_ROOT="$(mktemp -d /tmp/greenvpn-hysteria-readiness.XXXXXX)"
SMOKE_PID=""
cleanup() {
  if [[ -n "${SMOKE_PID}" ]]; then
    kill "${SMOKE_PID}" >/dev/null 2>&1 || true
    wait "${SMOKE_PID}" 2>/dev/null || true
  fi
  rm -rf -- "${WORK_ROOT}"
}
trap cleanup EXIT

"${INSTALL_ROOT}/bin/hysteria" client -c "${CLIENT_CONFIG_FILE}" >"${WORK_ROOT}/client.log" 2>&1 &
SMOKE_PID="$!"
for _ in $(seq 1 80); do
  ss -H -lnt | awk '{print $4}' | grep -Eq "(:|])${SOCKS_PORT}$" && break
  kill -0 "${SMOKE_PID}" 2>/dev/null || { echo "blocker=smoke_client_exited" >&2; exit 1; }
  sleep 0.25
done
ss -H -lnt | awk '{print $4}' | grep -Eq "(:|])${SOCKS_PORT}$" || {
  echo "blocker=smoke_listener_missing" >&2
  exit 1
}
EGRESS="$(curl -4fsS --max-time 30 --socks5-hostname "127.0.0.1:${SOCKS_PORT}" https://api.ipify.org)"
YOUTUBE_STATUS="$(curl -fsS --max-time 30 --socks5-hostname "127.0.0.1:${SOCKS_PORT}" -o /dev/null -w '%{http_code}' https://www.youtube.com/generate_204)"
[[ "${EGRESS}" == "${CANARY_HOST}" ]] || { echo "blocker=egress_mismatch" >&2; exit 1; }
[[ "${YOUTUBE_STATUS}" -ge 200 && "${YOUTUBE_STATUS}" -lt 400 ]] || {
  echo "blocker=youtube_smoke_failed" >&2
  exit 1
}

REQUIRED_UNITS=(wg-quick@wg0 greenvpn-amneziawg-canary)
if [[ "${BASE_STACK_ONLY}" -ne 1 ]]; then
  REQUIRED_UNITS+=(
    greenvpn-vless-reality-canary
    greenvpn-naive-https-canary
    greenvpn-dnstt-canary
    greenvpn-dnstt-dns-front
  )
fi
for unit in "${REQUIRED_UNITS[@]}"; do
  systemctl is-active --quiet "${unit}.service" || {
    echo "blocker=dependent_service_inactive:${unit}" >&2
    exit 1
  }
done

echo "ready=true"
echo "service=${SERVICE_NAME}.service"
echo "listen=udp/${CANARY_PORT}"
echo "version=${EXPECTED_VERSION}"
echo "egress=${CANARY_HOST}"
echo "youtube_http=${YOUTUBE_STATUS}"
echo "secrets_printed=false"
echo "stable_transports=active"
echo "dependency_scope=$([[ "${BASE_STACK_ONLY}" -eq 1 ]] && echo prior_layers_only || echo full_nl2_stack)"
