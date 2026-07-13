#!/usr/bin/env bash
set -euo pipefail

CANARY_HOST="5.129.216.42"
CANARY_PORT="443"
SOCKS_PORT="1981"
SERVICE_NAME="greenvpn-vless-reality-canary"
CONFIG_FILE="/etc/greenvpn-transport/vless-reality-xhttp-canary.json"
CLIENT_CONFIG_FILE="/etc/greenvpn-transport/vless-reality-xhttp-canary.client.json"
INSTALL_ROOT="/opt/greenvpn-canary/xray-vless-reality"
EXPECTED_VERSION="26.7.11"
EXPECTED_SHA256="5200ed9b358cf380b2d9f1fe28c7e56220c0159adcd86a64592246d8257a043c"

[[ "${EUID}" -eq 0 ]] || { echo "Run as root on NL2." >&2; exit 1; }
for command in curl sha256sum ss stat systemctl; do
  command -v "${command}" >/dev/null 2>&1 || {
    echo "blocker=missing_command:${command}" >&2
    exit 1
  }
done

PUBLIC_IP="$(curl -4fsS --max-time 5 https://api.ipify.org || true)"
[[ "${PUBLIC_IP}" == "${CANARY_HOST}" ]] || { echo "blocker=wrong_public_ip" >&2; exit 1; }
systemctl is-active --quiet "${SERVICE_NAME}.service" || { echo "blocker=service_inactive" >&2; exit 1; }

for path in "${CONFIG_FILE}" "${CLIENT_CONFIG_FILE}"; do
  [[ -f "${path}" && ! -L "${path}" ]] || { echo "blocker=unsafe_config_path" >&2; exit 1; }
  [[ "$(stat -c '%U:%G:%a' "${path}")" == "root:root:600" ]] || {
    echo "blocker=config_owner_or_mode" >&2
    exit 1
  }
done
[[ "$(sha256sum "${INSTALL_ROOT}/bin/xray" | awk '{print $1}')" == "${EXPECTED_SHA256}" ]] || {
  echo "blocker=binary_hash_mismatch" >&2
  exit 1
}
"${INSTALL_ROOT}/bin/xray" version | head -n 1 | grep -Fq "Xray ${EXPECTED_VERSION}" || {
  echo "blocker=version_mismatch" >&2
  exit 1
}
"${INSTALL_ROOT}/bin/xray" run -test -config "${CONFIG_FILE}" >/dev/null
"${INSTALL_ROOT}/bin/xray" run -test -config "${CLIENT_CONFIG_FILE}" >/dev/null
ss -H -lnt | awk '{print $4}' | grep -Eq "(:|])${CANARY_PORT}$" || {
  echo "blocker=tcp_listener_missing" >&2
  exit 1
}
if ss -H -lnt | awk '{print $4}' | grep -Eq "(:|])${SOCKS_PORT}$"; then
  echo "blocker=smoke_port_in_use" >&2
  exit 1
fi

WORK_ROOT="$(mktemp -d /tmp/greenvpn-vless-readiness.XXXXXX)"
SMOKE_PID=""
cleanup() {
  if [[ -n "${SMOKE_PID}" ]]; then
    kill "${SMOKE_PID}" >/dev/null 2>&1 || true
    wait "${SMOKE_PID}" 2>/dev/null || true
  fi
  rm -rf -- "${WORK_ROOT}"
}
trap cleanup EXIT

"${INSTALL_ROOT}/bin/xray" run -config "${CLIENT_CONFIG_FILE}" >"${WORK_ROOT}/client.log" 2>&1 &
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

for unit in wg-quick@wg0 greenvpn-amneziawg-canary greenvpn-hysteria2-canary \
  greenvpn-naive-https-canary greenvpn-dnstt-canary greenvpn-dnstt-dns-front; do
  systemctl is-active --quiet "${unit}.service" || {
    echo "blocker=dependent_service_inactive:${unit}" >&2
    exit 1
  }
done

echo "ready=true"
echo "service=${SERVICE_NAME}.service"
echo "listen=tcp/${CANARY_PORT}"
echo "version=${EXPECTED_VERSION}"
echo "egress=${CANARY_HOST}"
echo "youtube_http=${YOUTUBE_STATUS}"
echo "secrets_printed=false"
echo "stable_transports=active"
