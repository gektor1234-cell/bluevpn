#!/usr/bin/env bash
set -euo pipefail

REQUIRE_DELEGATION=0
SKIP_SMOKE=0
CANARY_HOST="5.129.216.42"
CANARY_ZONE="t.greenvpn.pro"
CANARY_NS="tns.greenvpn.pro"
SOCKS_PORT="1083"
SERVER_SERVICE="greenvpn-dnstt-canary"
SOCKS_SERVICE="greenvpn-dnstt-socks-canary"
INSTALL_ROOT="/opt/greenvpn-canary/dnstt"
CONFIG_ROOT="/etc/greenvpn-dnstt-canary"
CLIENT_CONFIG_FILE="/etc/greenvpn-transport/dnstt-canary.client.json"
DNSTT_SERVER_SHA256="cf3e6a3091752b72e94e360eaad76e3cb14b69923af691e6477aa3f33e740895"
DNSTT_CLIENT_SHA256="366e30297caf3289d9c03bf0a3c8f4522e8972fa7ddd3d289d7887ad01daf8fe"
XRAY_SHA256="5200ed9b358cf380b2d9f1fe28c7e56220c0159adcd86a64592246d8257a043c"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --require-delegation) REQUIRE_DELEGATION=1; shift ;;
    --skip-smoke) SKIP_SMOKE=1; shift ;;
    -h|--help)
      echo "Usage: check_dnstt_canary_readiness.sh [--require-delegation] [--skip-smoke]"
      exit 0
      ;;
    *) echo "Unknown argument: $1" >&2; exit 2 ;;
  esac
done

[[ "${EUID}" -eq 0 ]] || { echo "Run as root on NL2." >&2; exit 1; }
for command in curl dig python3 sha256sum ss systemctl stat; do
  command -v "${command}" >/dev/null 2>&1 || { echo "Required command missing: ${command}" >&2; exit 1; }
done

PUBLIC_IP="$(curl -4fsS --max-time 5 https://api.ipify.org || true)"
[[ "${PUBLIC_IP}" == "${CANARY_HOST}" ]] || { echo "Readiness refused outside exact NL2 host." >&2; exit 1; }

for unit in "${SERVER_SERVICE}" "${SOCKS_SERVICE}" wg-quick@wg0 greenvpn-hysteria2-canary greenvpn-vless-reality-canary greenvpn-naive-https-canary; do
  systemctl is-active --quiet "${unit}.service" || { echo "Required unit is not active: ${unit}" >&2; exit 1; }
done

declare -A expected_hashes=(
  ["${INSTALL_ROOT}/bin/dnstt-server"]="${DNSTT_SERVER_SHA256}"
  ["${INSTALL_ROOT}/bin/dnstt-client"]="${DNSTT_CLIENT_SHA256}"
  ["${INSTALL_ROOT}/bin/xray"]="${XRAY_SHA256}"
)
for path in "${!expected_hashes[@]}"; do
  [[ -f "${path}" && ! -L "${path}" ]] || { echo "Runtime missing or symlinked: ${path}" >&2; exit 1; }
  [[ "$(sha256sum "${path}" | awk '{print $1}')" == "${expected_hashes[${path}]}" ]] || { echo "Runtime hash mismatch: ${path}" >&2; exit 1; }
done

check_file() {
  local path="$1" expected_owner="$2" expected_group="$3" expected_mode="$4"
  [[ -f "${path}" && ! -L "${path}" ]] || { echo "Protected file missing or symlinked: ${path}" >&2; exit 1; }
  [[ "$(stat -c '%U:%G:%a' "${path}")" == "${expected_owner}:${expected_group}:${expected_mode}" ]] || {
    echo "Protected file ownership/mode mismatch: ${path}" >&2
    exit 1
  }
}
check_file "${CONFIG_ROOT}/server.key" root greenvpn-dnstt 640
check_file "${CONFIG_ROOT}/server.pub" root root 644
check_file "${CONFIG_ROOT}/xray-socks.json" root greenvpn-dnstt 640
check_file "${CONFIG_ROOT}/socks-auth.json" root root 600
check_file "${CLIENT_CONFIG_FILE}" root root 600

[[ "$(stat -c '%U:%G:%a' "${CONFIG_ROOT}")" == "root:greenvpn-dnstt:750" ]] || { echo "Config directory ACL is invalid." >&2; exit 1; }
ss -H -lunp | awk -v endpoint="${CANARY_HOST}:53" '$4 == endpoint {found=1} END {exit !found}' || { echo "Exact public dnstt UDP listener is missing." >&2; exit 1; }
if ss -H -lntp | awk -v endpoint="${CANARY_HOST}:53" '$4 == endpoint {found=1} END {exit !found}'; then
  echo "dnstt must not expose public TCP/53." >&2
  exit 1
fi
ss -H -lntp | awk -v endpoint="127.0.0.1:${SOCKS_PORT}" '$4 == endpoint {found=1} END {exit !found}' || { echo "Loopback SOCKS listener is missing." >&2; exit 1; }
"${INSTALL_ROOT}/bin/xray" run -test -config "${CONFIG_ROOT}/xray-socks.json" >/dev/null

server_data_plane_ready=false
if [[ "${SKIP_SMOKE}" -eq 0 ]]; then
  work="$(mktemp -d)"
  pid=""
  cleanup() {
    [[ -z "${pid}" ]] || kill "${pid}" 2>/dev/null || true
    [[ -z "${pid}" ]] || wait "${pid}" 2>/dev/null || true
    rm -rf -- "${work}"
  }
  trap cleanup EXIT
  python3 - "${CLIENT_CONFIG_FILE}" "${work}/curl.conf" <<'PY'
import json, os, sys
with open(sys.argv[1], encoding="utf-8") as f:
    p = json.load(f)
fd = os.open(sys.argv[2], os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
with os.fdopen(fd, "w", encoding="utf-8") as f:
    f.write('proxy = "socks5h://127.0.0.1:1983"\n')
    f.write('proxy-user = "{}:{}"\n'.format(p["socks"]["username"], p["socks"]["password"]))
    f.write('silent\nshow-error\nmax-time = 120\n')
PY
  "${INSTALL_ROOT}/bin/dnstt-client" -udp "${CANARY_HOST}:53" \
    -pubkey-file "${CONFIG_ROOT}/server.pub" "${CANARY_ZONE}" 127.0.0.1:1983 \
    >"${work}/client.stdout" 2>"${work}/client.stderr" &
  pid="$!"
  for _ in $(seq 1 80); do
    ss -H -lnt | awk '$4 == "127.0.0.1:1983" {found=1} END {exit !found}' && break
    sleep 0.25
  done
  ss -H -lnt | awk '$4 == "127.0.0.1:1983" {found=1} END {exit !found}' || { echo "Local dnstt smoke listener failed." >&2; exit 1; }
  egress="$(curl --config "${work}/curl.conf" https://api.ipify.org)"
  youtube_status="$(curl --config "${work}/curl.conf" -o /dev/null -w '%{http_code}' https://www.youtube.com/generate_204)"
  [[ "${egress}" == "${CANARY_HOST}" ]] || { echo "Direct dnstt smoke returned unexpected egress." >&2; exit 1; }
  [[ "${youtube_status}" -ge 200 && "${youtube_status}" -lt 400 ]] || { echo "Direct dnstt YouTube smoke failed." >&2; exit 1; }
  server_data_plane_ready=true
  cleanup
  trap - EXIT
fi

delegated_a="$(dig +short A "${CANARY_NS}" @1.1.1.1 | sed '/^$/d' | sort -u | tr '\n' ' ')"
delegated_ns="$(dig +short NS "${CANARY_ZONE}" @1.1.1.1 | tr '[:upper:]' '[:lower:]' | sed 's/\.$//' | sort -u | tr '\n' ' ')"
doh_delegation_ready=false
if grep -qw "${CANARY_HOST}" <<<"${delegated_a}" && grep -qw "${CANARY_NS}" <<<"${delegated_ns}"; then
  doh_delegation_ready=true
fi

echo "dnstt_server_service=active"
echo "dnstt_socks_service=active"
echo "server_data_plane_ready=${server_data_plane_ready}"
echo "doh_delegation_ready=${doh_delegation_ready}"
echo "dns_records_required=A:${CANARY_NS}->${CANARY_HOST},NS:${CANARY_ZONE}->${CANARY_NS}"
echo "stable_transports=active"
echo "secrets_printed=false"

if [[ "${REQUIRE_DELEGATION}" -eq 1 && "${doh_delegation_ready}" != true ]]; then
  echo "Required DNS delegation is not ready." >&2
  exit 2
fi
