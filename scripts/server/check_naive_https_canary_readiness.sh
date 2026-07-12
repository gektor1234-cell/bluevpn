#!/usr/bin/env bash
set -euo pipefail

CANARY_HOST="5.129.216.42"
CANARY_DOMAIN="nl2.vpn.greenvpn.pro"
CANARY_PORT="8443"
SERVICE_NAME="greenvpn-naive-https-canary"
CONFIG_FILE="/etc/greenvpn-naive-https-canary/Caddyfile"
CLIENT_CONFIG_FILE="/etc/greenvpn-transport/naive-https-canary.client.json"
INSTALL_ROOT="/opt/greenvpn-canary/naive-https"
EXPECTED_CADDY="v2.11.4"
EXPECTED_FORWARDPROXY="d62c80d3dd2c"
EXPECTED_NAIVE="naive 150.0.7871.63"

if [[ "${EUID}" -ne 0 ]]; then
  echo "Run as root on NL2." >&2
  exit 1
fi
for command in curl openssl sha256sum systemctl ss python3; do
  command -v "${command}" >/dev/null 2>&1 || {
    echo "blocker=missing_command:${command}" >&2
    exit 1
  }
done

PUBLIC_IP="$(curl -fsS --max-time 5 https://api.ipify.org || true)"
[[ "${PUBLIC_IP}" == "${CANARY_HOST}" ]] || {
  echo "blocker=wrong_public_ip" >&2
  exit 1
}
[[ "$(getent ahostsv4 "${CANARY_DOMAIN}" | awk 'NR==1 {print $1}')" == "${CANARY_HOST}" ]] || {
  echo "blocker=domain_mismatch" >&2
  exit 1
}
systemctl is-active --quiet "${SERVICE_NAME}.service" || {
  echo "blocker=service_inactive" >&2
  exit 1
}

for path in "${CONFIG_FILE}" "${CLIENT_CONFIG_FILE}"; do
  [[ -f "${path}" && ! -L "${path}" ]] || {
    echo "blocker=unsafe_config_path" >&2
    exit 1
  }
  [[ "$(stat -c '%U' "${path}")" == root ]] || {
    echo "blocker=config_not_root_owned" >&2
    exit 1
  }
done
[[ "$(stat -c '%a' "${CONFIG_FILE}")" == 640 ]] || {
  echo "blocker=server_config_mode" >&2
  exit 1
}
[[ "$(stat -c '%a' "${CLIENT_CONFIG_FILE}")" == 600 ]] || {
  echo "blocker=client_config_mode" >&2
  exit 1
}

CADDY_INFO="$("${INSTALL_ROOT}/bin/caddy" build-info)"
grep -Fq $'dep\tgithub.com/caddyserver/caddy/v2\tv2.11.4' <<<"${CADDY_INFO}" || {
  echo "blocker=caddy_version_mismatch" >&2
  exit 1
}
grep -Fq "${EXPECTED_FORWARDPROXY}" <<<"${CADDY_INFO}" || {
  echo "blocker=forwardproxy_commit_mismatch" >&2
  exit 1
}
[[ "$("${INSTALL_ROOT}/bin/naive" --version 2>&1)" == "${EXPECTED_NAIVE}" ]] || {
  echo "blocker=naive_version_mismatch" >&2
  exit 1
}
ss -H -lnt | awk '{print $4}' | grep -Eq "(:|])${CANARY_PORT}$" || {
  echo "blocker=tcp_listener_missing" >&2
  exit 1
}
if ss -H -lun | awk '{print $5}' | grep -Eq "(:|])${CANARY_PORT}$"; then
  echo "blocker=unexpected_udp_listener" >&2
  exit 1
fi

TLS_STATUS="$(curl -sS -o /dev/null -w '%{http_code}:%{ssl_verify_result}' \
  --max-time 15 "https://${CANARY_DOMAIN}:${CANARY_PORT}/")"
[[ "${TLS_STATUS}" == "404:0" ]] || {
  echo "blocker=tls_camouflage_failed" >&2
  exit 1
}

SMOKE_ROOT="$(mktemp -d /tmp/greenvpn-naive-readiness.XXXXXX)"
SMOKE_PID=""
cleanup() {
  if [[ -n "${SMOKE_PID}" ]]; then
    kill "${SMOKE_PID}" >/dev/null 2>&1 || true
    wait "${SMOKE_PID}" 2>/dev/null || true
  fi
  rm -rf -- "${SMOKE_ROOT}"
}
trap cleanup EXIT
"${INSTALL_ROOT}/bin/naive" "${CLIENT_CONFIG_FILE}" >"${SMOKE_ROOT}/naive.log" 2>&1 &
SMOKE_PID="$!"
for _ in $(seq 1 60); do
  ss -H -lnt | awk '{print $4}' | grep -Eq '(:|])1982$' && break
  kill -0 "${SMOKE_PID}" 2>/dev/null || {
    echo "blocker=smoke_client_exited" >&2
    exit 1
  }
  sleep 0.25
done
TRACE="$(curl -fsS --max-time 30 --socks5-hostname 127.0.0.1:1982 https://1.1.1.1/cdn-cgi/trace)"
grep -Fx "ip=${CANARY_HOST}" <<<"${TRACE}" >/dev/null || {
  echo "blocker=egress_mismatch" >&2
  exit 1
}

for stable_service in \
  wg-quick@wg0.service greenvpn-amneziawg-canary.service \
  greenvpn-hysteria2-canary.service greenvpn-vless-reality-canary.service; do
  systemctl is-active --quiet "${stable_service}" || {
    echo "blocker=dependent_service_inactive:${stable_service}" >&2
    exit 1
  }
done

echo "ready=true"
echo "public_ip=${PUBLIC_IP}"
echo "domain=${CANARY_DOMAIN}"
echo "listen=tcp/${CANARY_PORT}"
echo "service=${SERVICE_NAME}.service"
echo "caddy=${EXPECTED_CADDY}"
echo "forwardproxy=${EXPECTED_FORWARDPROXY}"
echo "naive=${EXPECTED_NAIVE#naive }"
echo "tls_camouflage_http=404"
echo "egress=${CANARY_HOST}"
echo "credentials=not_printed"
echo "stable_transports=active"
