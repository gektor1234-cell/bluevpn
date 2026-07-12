#!/usr/bin/env bash
set -euo pipefail

APPLY=0
EXPECTED_PUBLIC_IP=""
APPROVED_EXISTING_HOST=""
CANARY_HOST="5.129.216.42"
CANARY_PORT="443"
SERVICE_NAME="greenvpn-vless-reality-canary"
CONFIG_FILE="/etc/greenvpn-transport/vless-reality-xhttp-canary.json"
CLIENT_BASE_CONFIG_FILE="/etc/greenvpn-transport/vless-reality-xhttp-canary.base.json"
CLIENT_CONFIG_FILE="/etc/greenvpn-transport/vless-reality-xhttp-canary.client.json"
MATERIAL_ROOT="/etc/greenvpn-transport/vless-reality-xhttp-canary"
INSTALL_ROOT="/opt/greenvpn-canary/xray-vless-reality"
XRAY_VERSION="26.7.11"
XRAY_TAG="v26.7.11"
XRAY_LINUX_ZIP_SHA256="aa11c3685c71da0ffc71e511db50404609e7e963bb914b048f59a6a00af8930e"
XRAY_LINUX_BINARY_SHA256="5200ed9b358cf380b2d9f1fe28c7e56220c0159adcd86a64592246d8257a043c"
XRAY_ZIP_URL="https://github.com/XTLS/Xray-core/releases/download/${XRAY_TAG}/Xray-linux-64.zip"
REALITY_TARGET="www.amazon.com:443"
REALITY_SERVER_NAME="www.amazon.com"

usage() {
  cat <<'USAGE'
Bootstrap the owner-approved VLESS REALITY/XHTTP canary on Green VPN NL2.

Default mode is dry-run. Apply requires all three explicit arguments:
  bootstrap_vless_reality_xhttp_canary.sh --expected-public-ip 5.129.216.42 \
      --approved-existing-host 5.129.216.42 --apply

The script:
  - refuses every host except the exact NL2 public IP;
  - pins the official Xray-core v26.7.11 Linux archive and binary SHA-256;
  - listens only on TCP/443; existing WireGuard UDP/443 is unaffected;
  - creates one root-only VLESS identity, REALITY keypair, short ID and XHTTP path;
  - keeps root-only base/full client profiles for controlled preview tests;
  - preserves wg0, AWG2, Hysteria2, DNS, backend, databases and public catalog;
  - packages the exact MPL-2.0 license and source URL;
  - never prints credentials, REALITY material, UUID or XHTTP path.
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --apply)
      APPLY=1
      shift
      ;;
    --expected-public-ip)
      EXPECTED_PUBLIC_IP="${2:?missing expected public ip}"
      shift 2
      ;;
    --approved-existing-host)
      APPROVED_EXISTING_HOST="${2:?missing approved existing host}"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

if [[ "${EUID}" -ne 0 ]]; then
  echo "Run as root on NL2." >&2
  exit 1
fi
for command in curl unzip openssl python3 sha256sum systemctl ss; do
  command -v "${command}" >/dev/null 2>&1 || {
    echo "Required command is missing: ${command}" >&2
    exit 1
  }
done

PUBLIC_IP="$(curl -fsS --max-time 5 https://api.ipify.org || true)"
if [[ "${PUBLIC_IP}" != "${CANARY_HOST}" ]]; then
  echo "Refusing VLESS REALITY bootstrap outside exact NL2 host." >&2
  exit 1
fi
if [[ "${APPLY}" -eq 1 ]]; then
  if [[ "${EXPECTED_PUBLIC_IP}" != "${CANARY_HOST}" \
    || "${APPROVED_EXISTING_HOST}" != "${CANARY_HOST}" ]]; then
    echo "Apply requires exact NL2 expected/approved host values." >&2
    exit 1
  fi
fi

if systemctl is-active --quiet "${SERVICE_NAME}.service"; then
  PORT_STATE="managed-active"
elif ss -H -lnt 2>/dev/null | awk '{print $4}' | grep -Eq "(:|])${CANARY_PORT}$"; then
  echo "TCP/${CANARY_PORT} is already occupied by an unmanaged service." >&2
  exit 1
else
  PORT_STATE="free"
fi

echo "Green VPN VLESS REALITY/XHTTP canary bootstrap plan"
echo "public_ip=${PUBLIC_IP}"
echo "listen=tcp/${CANARY_PORT}"
echo "wireguard_udp_443=separate_transport_unchanged"
echo "service=${SERVICE_NAME}.service"
echo "xray_version=${XRAY_VERSION}"
echo "xray_zip_sha256=${XRAY_LINUX_ZIP_SHA256}"
echo "xray_binary_sha256=${XRAY_LINUX_BINARY_SHA256}"
echo "reality_target=${REALITY_TARGET}"
echo "xhttp_mode=auto"
echo "port_state=${PORT_STATE}"
echo "mode=$([[ "${APPLY}" -eq 1 ]] && echo apply || echo dry-run)"
echo "stable_wireguard=not_changed"
echo "amneziawg_canary=not_changed"
echo "hysteria2_canary=not_changed"
echo "public_catalog=not_changed"

if [[ "${APPLY}" -ne 1 ]]; then
  echo "Dry-run only. Re-run with exact host approval and --apply."
  exit 0
fi

umask 077
STAMP="$(date -u +%Y%m%dT%H%M%SZ)"
BACKUP_ROOT="/root/greenvpn-vless-reality-prechange/${STAMP}"
WORK_ROOT="$(mktemp -d /tmp/greenvpn-vless-reality.XXXXXX)"
SMOKE_PID=""
cleanup() {
  if [[ -n "${SMOKE_PID}" ]]; then
    kill "${SMOKE_PID}" >/dev/null 2>&1 || true
    wait "${SMOKE_PID}" 2>/dev/null || true
  fi
  rm -rf -- "${WORK_ROOT}"
}
trap cleanup EXIT
mkdir -p "${BACKUP_ROOT}"
chmod 0700 "${BACKUP_ROOT}"

for path in \
  "${CONFIG_FILE}" \
  "${CLIENT_BASE_CONFIG_FILE}" \
  "${CLIENT_CONFIG_FILE}" \
  "${MATERIAL_ROOT}" \
  "${INSTALL_ROOT}" \
  "/etc/systemd/system/${SERVICE_NAME}.service"; do
  if [[ -e "${path}" ]]; then
    cp -a -- "${path}" "${BACKUP_ROOT}/"
  fi
done

stable_hash() {
  if [[ -f "$1" ]]; then sha256sum "$1" | awk '{print $1}'; else echo absent; fi
}
WG_HASH_BEFORE="$(stable_hash /etc/wireguard/wg0.conf)"
AWG_HASH_BEFORE="$(stable_hash /etc/greenvpn-transport/awgcanary0.conf)"
HYSTERIA_HASH_BEFORE="$(stable_hash /etc/greenvpn-transport/hysteria2-canary.yaml)"

curl -fL --retry 3 --connect-timeout 10 --max-time 240 \
  "${XRAY_ZIP_URL}" -o "${WORK_ROOT}/xray.zip"
printf '%s  %s\n' "${XRAY_LINUX_ZIP_SHA256}" "${WORK_ROOT}/xray.zip" | sha256sum -c -
unzip -q "${WORK_ROOT}/xray.zip" -d "${WORK_ROOT}/xray"
printf '%s  %s\n' "${XRAY_LINUX_BINARY_SHA256}" "${WORK_ROOT}/xray/xray" | sha256sum -c -

install -d -m 0755 "${INSTALL_ROOT}/bin"
install -m 0755 "${WORK_ROOT}/xray/xray" "${INSTALL_ROOT}/bin/xray"
install -m 0644 "${WORK_ROOT}/xray/LICENSE" "${INSTALL_ROOT}/LICENSE"
install -m 0644 "${WORK_ROOT}/xray/README.md" "${INSTALL_ROOT}/README.md"
cat > "${INSTALL_ROOT}/SOURCE" <<EOF
Xray-core ${XRAY_TAG}
Source: https://github.com/XTLS/Xray-core/tree/${XRAY_TAG}
Release: https://github.com/XTLS/Xray-core/releases/tag/${XRAY_TAG}
License: Mozilla Public License 2.0; see LICENSE in this directory.
EOF
chmod 0644 "${INSTALL_ROOT}/SOURCE"

install -d -m 0700 "${MATERIAL_ROOT}"
if [[ ! -s "${MATERIAL_ROOT}/client.id" ]]; then
  cat /proc/sys/kernel/random/uuid > "${MATERIAL_ROOT}/client.id"
fi
if [[ ! -s "${MATERIAL_ROOT}/short_id" ]]; then
  openssl rand -hex 8 > "${MATERIAL_ROOT}/short_id"
fi
if [[ ! -s "${MATERIAL_ROOT}/xhttp_path" ]]; then
  printf '/%s\n' "$(openssl rand -hex 12)" > "${MATERIAL_ROOT}/xhttp_path"
fi
if [[ ! -s "${MATERIAL_ROOT}/reality.private" \
  || ! -s "${MATERIAL_ROOT}/reality.password" ]]; then
  KEY_OUTPUT="$("${INSTALL_ROOT}/bin/xray" x25519)"
  PRIVATE_KEY="$(printf '%s\n' "${KEY_OUTPUT}" | sed -nE 's/^PrivateKey:[[:space:]]*//p' | head -n1)"
  REALITY_PASSWORD="$(printf '%s\n' "${KEY_OUTPUT}" | sed -nE 's/^(Password \(PublicKey\)|PublicKey):[[:space:]]*//p' | head -n1)"
  if [[ -z "${PRIVATE_KEY}" || -z "${REALITY_PASSWORD}" ]]; then
    echo "Xray did not return a parseable REALITY keypair." >&2
    exit 1
  fi
  printf '%s\n' "${PRIVATE_KEY}" > "${MATERIAL_ROOT}/reality.private"
  printf '%s\n' "${REALITY_PASSWORD}" > "${MATERIAL_ROOT}/reality.password"
fi
chmod 0600 "${MATERIAL_ROOT}"/*

CLIENT_ID="$(tr -d '\r\n' < "${MATERIAL_ROOT}/client.id")"
SHORT_ID="$(tr -d '\r\n' < "${MATERIAL_ROOT}/short_id")"
XHTTP_PATH="$(tr -d '\r\n' < "${MATERIAL_ROOT}/xhttp_path")"
PRIVATE_KEY="$(tr -d '\r\n' < "${MATERIAL_ROOT}/reality.private")"
REALITY_PASSWORD="$(tr -d '\r\n' < "${MATERIAL_ROOT}/reality.password")"
DERIVED_REALITY_PASSWORD="$(
  "${INSTALL_ROOT}/bin/xray" x25519 -i "${PRIVATE_KEY}" \
    | sed -nE 's/^(Password \(PublicKey\)|PublicKey):[[:space:]]*//p' \
    | head -n1
)"
if [[ -z "${DERIVED_REALITY_PASSWORD}" \
  || "${DERIVED_REALITY_PASSWORD}" != "${REALITY_PASSWORD}" ]]; then
  echo "Stored REALITY keypair validation failed." >&2
  exit 1
fi

cat > "${CONFIG_FILE}" <<EOF
{
  "log": {"loglevel": "warning"},
  "inbounds": [
    {
      "listen": "0.0.0.0",
      "port": ${CANARY_PORT},
      "protocol": "vless",
      "settings": {
        "clients": [{"id": "${CLIENT_ID}"}],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "xhttp",
        "security": "reality",
        "realitySettings": {
          "show": false,
          "target": "${REALITY_TARGET}",
          "xver": 0,
          "serverNames": ["${REALITY_SERVER_NAME}"],
          "privateKey": "${PRIVATE_KEY}",
          "shortIds": ["${SHORT_ID}"],
          "limitFallbackUpload": {"afterBytes": 2097152, "bytesPerSec": 1048576, "burstBytesPerSec": 2097152},
          "limitFallbackDownload": {"afterBytes": 8388608, "bytesPerSec": 2097152, "burstBytesPerSec": 4194304}
        },
        "xhttpSettings": {"path": "${XHTTP_PATH}", "mode": "auto"}
      }
    }
  ],
  "outbounds": [
    {"protocol": "freedom", "tag": "direct"},
    {"protocol": "blackhole", "tag": "block"}
  ]
}
EOF
chmod 0600 "${CONFIG_FILE}"

cat > "${CLIENT_BASE_CONFIG_FILE}" <<EOF
{
  "log": {"loglevel": "warning"},
  "inbounds": [],
  "outbounds": [
    {
      "tag": "proxy",
      "protocol": "vless",
      "settings": {
        "vnext": [{"address": "${CANARY_HOST}", "port": ${CANARY_PORT}, "users": [{"id": "${CLIENT_ID}", "encryption": "none"}]}]
      },
      "streamSettings": {
        "network": "xhttp",
        "security": "reality",
        "realitySettings": {
          "fingerprint": "chrome",
          "serverName": "${REALITY_SERVER_NAME}",
          "password": "${REALITY_PASSWORD}",
          "shortId": "${SHORT_ID}",
          "spiderX": "/"
        },
        "xhttpSettings": {"path": "${XHTTP_PATH}", "mode": "auto"}
      }
    },
    {"protocol": "freedom", "tag": "direct"}
  ]
}
EOF
chmod 0600 "${CLIENT_BASE_CONFIG_FILE}"

python3 - "${CLIENT_BASE_CONFIG_FILE}" "${CLIENT_CONFIG_FILE}" <<'PY'
import json
import os
import sys

with open(sys.argv[1], "r", encoding="utf-8") as handle:
    root = json.load(handle)
root["inbounds"] = [{
    "listen": "127.0.0.1",
    "port": 1981,
    "protocol": "socks",
    "settings": {"udp": True},
    "tag": "managed-socks",
}]
with open(sys.argv[2], "w", encoding="utf-8") as handle:
    json.dump(root, handle, ensure_ascii=True, indent=2)
    handle.write("\n")
os.chmod(sys.argv[2], 0o600)
PY

"${INSTALL_ROOT}/bin/xray" run -test -config "${CONFIG_FILE}"
"${INSTALL_ROOT}/bin/xray" run -test -config "${CLIENT_CONFIG_FILE}"
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
"${SCRIPT_DIR}/install_transport_canary_service.sh" \
  --protocol vless_reality \
  --binary "${INSTALL_ROOT}/bin/xray" \
  --config-file "${CONFIG_FILE}" \
  --service-name "${SERVICE_NAME}" \
  --expected-public-ip "${CANARY_HOST}" \
  --approved-existing-host "${CANARY_HOST}" \
  --apply

"${SCRIPT_DIR}/check_transport_canary_readiness.sh" \
  --protocol vless_reality \
  --binary "${INSTALL_ROOT}/bin/xray" \
  --config-file "${CONFIG_FILE}" \
  --service-name "${SERVICE_NAME}" \
  --listen-port "${CANARY_PORT}" \
  --endpoint-id nl2-vless-reality-xhttp-canary \
  --transport reality \
  --approved-existing-host "${CANARY_HOST}" \
  --json

SMOKE_LOG="${WORK_ROOT}/xray-smoke.log"
"${INSTALL_ROOT}/bin/xray" run -config "${CLIENT_CONFIG_FILE}" \
  >"${SMOKE_LOG}" 2>&1 &
SMOKE_PID="$!"
SMOKE_READY=0
for _ in $(seq 1 40); do
  if ! kill -0 "${SMOKE_PID}" >/dev/null 2>&1; then
    break
  fi
  if ss -H -lnt 2>/dev/null | awk '{print $4}' | grep -Eq '(:|])1981$'; then
    SMOKE_READY=1
    break
  fi
  sleep 0.25
done
if [[ "${SMOKE_READY}" -ne 1 ]]; then
  kill "${SMOKE_PID}" >/dev/null 2>&1 || true
  wait "${SMOKE_PID}" 2>/dev/null || true
  SMOKE_PID=""
  echo "VLESS REALITY client smoke listener did not start." >&2
  exit 1
fi
set +e
SMOKE_EGRESS="$(
  curl -fsS --max-time 20 --socks5-hostname 127.0.0.1:1981 \
    https://api.ipify.org 2>/dev/null
)"
SMOKE_CURL_EXIT="$?"
set -e
kill "${SMOKE_PID}" >/dev/null 2>&1 || true
wait "${SMOKE_PID}" 2>/dev/null || true
SMOKE_PID=""
if [[ "${SMOKE_CURL_EXIT}" -ne 0 || "${SMOKE_EGRESS}" != "${CANARY_HOST}" ]]; then
  echo "VLESS REALITY data-plane smoke failed." >&2
  exit 1
fi
echo "vless_reality_data_plane=ok"

[[ "$(stable_hash /etc/wireguard/wg0.conf)" == "${WG_HASH_BEFORE}" ]] || {
  echo "Stable wg0 invariant changed." >&2
  exit 1
}
[[ "$(stable_hash /etc/greenvpn-transport/awgcanary0.conf)" == "${AWG_HASH_BEFORE}" ]] || {
  echo "AWG2 canary invariant changed." >&2
  exit 1
}
[[ "$(stable_hash /etc/greenvpn-transport/hysteria2-canary.yaml)" == "${HYSTERIA_HASH_BEFORE}" ]] || {
  echo "Hysteria2 canary invariant changed." >&2
  exit 1
}
systemctl is-active --quiet wg-quick@wg0
systemctl is-active --quiet greenvpn-amneziawg-canary
systemctl is-active --quiet greenvpn-hysteria2-canary

cat > "${INSTALL_ROOT}/manifest" <<EOF
xray_version=${XRAY_VERSION}
xray_tag=${XRAY_TAG}
xray_linux_zip_sha256=${XRAY_LINUX_ZIP_SHA256}
xray_linux_binary_sha256=${XRAY_LINUX_BINARY_SHA256}
source=https://github.com/XTLS/Xray-core/tree/${XRAY_TAG}
license=MPL-2.0
service=${SERVICE_NAME}.service
listen=tcp/${CANARY_PORT}
config=${CONFIG_FILE}
client_base_config=${CLIENT_BASE_CONFIG_FILE}
client_config=${CLIENT_CONFIG_FILE}
backup=${BACKUP_ROOT}
stable_wireguard=active_unchanged
amneziawg_canary=active_unchanged
hysteria2_canary=active_unchanged
public_catalog=not_changed
EOF
chmod 0600 "${INSTALL_ROOT}/manifest"
echo "VLESS REALITY/XHTTP canary installed without publishing credentials or changing the public catalog."
