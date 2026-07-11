#!/usr/bin/env bash
set -euo pipefail

APPLY=0
EXPECTED_PUBLIC_IP=""
APPROVED_EXISTING_HOST=""
CANARY_HOST="5.129.216.42"
CANARY_DOMAIN="nl2.vpn.greenvpn.pro"
CANARY_PORT="2443"
SERVICE_NAME="greenvpn-hysteria2-canary"
CONFIG_FILE="/etc/greenvpn-transport/hysteria2-canary.yaml"
CLIENT_CONFIG_FILE="/etc/greenvpn-transport/hysteria2-canary.client.yaml"
CLIENT_BASE_CONFIG_FILE="/etc/greenvpn-transport/hysteria2-canary.base.yaml"
MATERIAL_ROOT="/etc/greenvpn-transport/hysteria2-canary"
INSTALL_ROOT="/opt/greenvpn-canary/hysteria2"
HYSTERIA_VERSION="2.9.3"
HYSTERIA_TAG="app/v2.9.3"
HYSTERIA_LINUX_AMD64_SHA256="66dbdb0608f25f3057b433afe975a9fc1af2ca8e512479e294988b3ef363d6c1"
HYSTERIA_URL="https://github.com/apernet/hysteria/releases/download/${HYSTERIA_TAG}/hysteria-linux-amd64"

usage() {
  cat <<'USAGE'
Bootstrap the owner-approved Hysteria2 canary on Green VPN NL2.

Default mode is dry-run. Apply requires all three explicit arguments:
  bootstrap_hysteria2_canary.sh --expected-public-ip 5.129.216.42 \
      --approved-existing-host 5.129.216.42 --apply

The script:
  - refuses every host except the exact NL2 public IP;
  - pins the official Hysteria app/v2.9.3 linux-amd64 GitHub SHA-256;
  - uses only UDP/2443 and a dedicated systemd service;
  - obtains a trusted TLS certificate for nl2.vpn.greenvpn.pro via ACME HTTP;
  - creates separate auth and Salamander material with root-only permissions;
  - preserves wg0, AWG2, DNS, nginx, backend, databases and public catalog;
  - keeps a root-only client profile for controlled preview smoke tests;
  - never prints credentials or private keys.
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

PUBLIC_IP="$(curl -fsS --max-time 5 https://api.ipify.org || true)"
if [[ "${PUBLIC_IP}" != "${CANARY_HOST}" ]]; then
  echo "Refusing Hysteria2 bootstrap outside exact NL2 host." >&2
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
elif ss -H -lun 2>/dev/null | awk '{print $5}' | grep -Eq "(:|])${CANARY_PORT}$"; then
  echo "UDP/${CANARY_PORT} is already occupied by an unmanaged service." >&2
  exit 1
else
  PORT_STATE="free"
fi

echo "Green VPN Hysteria2 canary bootstrap plan"
echo "public_ip=${PUBLIC_IP}"
echo "domain=${CANARY_DOMAIN}"
echo "listen=udp/${CANARY_PORT}"
echo "service=${SERVICE_NAME}.service"
echo "hysteria_version=${HYSTERIA_VERSION}"
echo "hysteria_sha256=${HYSTERIA_LINUX_AMD64_SHA256}"
echo "port_state=${PORT_STATE}"
echo "mode=$([[ "${APPLY}" -eq 1 ]] && echo apply || echo dry-run)"
echo "stable_wireguard=not_changed"
echo "amneziawg_canary=not_changed"
echo "public_catalog=not_changed"

if [[ "${APPLY}" -ne 1 ]]; then
  echo "Dry-run only. Re-run with exact host approval and --apply."
  exit 0
fi

umask 077
STAMP="$(date -u +%Y%m%dT%H%M%SZ)"
BACKUP_ROOT="/root/greenvpn-hysteria2-prechange/${STAMP}"
WORK_ROOT="$(mktemp -d /tmp/greenvpn-hysteria2.XXXXXX)"
trap 'rm -rf -- "${WORK_ROOT}"' EXIT
mkdir -p "${BACKUP_ROOT}"
chmod 0700 "${BACKUP_ROOT}"

for path in \
  "${CONFIG_FILE}" \
  "${CLIENT_CONFIG_FILE}" \
  "${CLIENT_BASE_CONFIG_FILE}" \
  "${MATERIAL_ROOT}" \
  "${INSTALL_ROOT}" \
  "/etc/systemd/system/${SERVICE_NAME}.service"; do
  if [[ -e "${path}" ]]; then
    cp -a -- "${path}" "${BACKUP_ROOT}/"
  fi
done

curl -fL --retry 3 --connect-timeout 10 --max-time 180 \
  "${HYSTERIA_URL}" -o "${WORK_ROOT}/hysteria"
printf '%s  %s\n' "${HYSTERIA_LINUX_AMD64_SHA256}" "${WORK_ROOT}/hysteria" \
  | sha256sum -c -
install -d -m 0755 "${INSTALL_ROOT}/bin"
install -m 0755 "${WORK_ROOT}/hysteria" "${INSTALL_ROOT}/bin/hysteria"

install -d -m 0700 "${MATERIAL_ROOT}"
install -d -m 0700 "${MATERIAL_ROOT}/acme"

if [[ ! -s "${MATERIAL_ROOT}/auth.secret" ]]; then
  openssl rand -hex 32 > "${MATERIAL_ROOT}/auth.secret"
fi
if [[ ! -s "${MATERIAL_ROOT}/obfs.secret" ]]; then
  openssl rand -hex 32 > "${MATERIAL_ROOT}/obfs.secret"
fi
chmod 0600 "${MATERIAL_ROOT}/auth.secret" "${MATERIAL_ROOT}/obfs.secret"
AUTH_SECRET="$(tr -d '\r\n' < "${MATERIAL_ROOT}/auth.secret")"
OBFS_SECRET="$(tr -d '\r\n' < "${MATERIAL_ROOT}/obfs.secret")"

cat > "${CONFIG_FILE}" <<EOF
listen: 0.0.0.0:${CANARY_PORT}
acme:
  domains:
    - ${CANARY_DOMAIN}
  ca: letsencrypt
  listenHost: 0.0.0.0
  dir: ${MATERIAL_ROOT}/acme
  type: http
auth:
  type: password
  password: ${AUTH_SECRET}
obfs:
  type: salamander
  salamander:
    password: ${OBFS_SECRET}
ignoreClientBandwidth: true
congestion:
  type: bbr
  bbrProfile: standard
disableUDP: false
udpIdleTimeout: 60s
masquerade:
  type: string
  string:
    content: '<!doctype html><html><head><title>Green CDN</title></head><body></body></html>'
    headers:
      content-type: text/html; charset=utf-8
    statusCode: 200
EOF
chmod 0600 "${CONFIG_FILE}"

cat > "${CLIENT_BASE_CONFIG_FILE}" <<EOF
server: ${CANARY_HOST}:${CANARY_PORT}
auth: ${AUTH_SECRET}
tls:
  sni: ${CANARY_DOMAIN}
  insecure: false
obfs:
  type: salamander
  salamander:
    password: ${OBFS_SECRET}
EOF
chmod 0600 "${CLIENT_BASE_CONFIG_FILE}"

cp -- "${CLIENT_BASE_CONFIG_FILE}" "${CLIENT_CONFIG_FILE}"
cat >> "${CLIENT_CONFIG_FILE}" <<EOF
fastOpen: true
lazy: false
socks5:
  listen: 127.0.0.1:1980
EOF
chmod 0600 "${CLIENT_CONFIG_FILE}"

"${INSTALL_ROOT}/bin/hysteria" version | sed -n '1,3p'
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
"${SCRIPT_DIR}/install_transport_canary_service.sh" \
  --protocol hysteria2 \
  --binary "${INSTALL_ROOT}/bin/hysteria" \
  --config-file "${CONFIG_FILE}" \
  --service-name "${SERVICE_NAME}" \
  --expected-public-ip "${CANARY_HOST}" \
  --approved-existing-host "${CANARY_HOST}" \
  --apply

"${SCRIPT_DIR}/check_transport_canary_readiness.sh" \
  --protocol hysteria2 \
  --binary "${INSTALL_ROOT}/bin/hysteria" \
  --config-file "${CONFIG_FILE}" \
  --service-name "${SERVICE_NAME}" \
  --listen-port "${CANARY_PORT}" \
  --endpoint-id nl2-hysteria2-canary \
  --transport quic \
  --approved-existing-host "${CANARY_HOST}" \
  --json

cat > "${INSTALL_ROOT}/manifest" <<EOF
hysteria_version=${HYSTERIA_VERSION}
hysteria_tag=${HYSTERIA_TAG}
hysteria_linux_amd64_sha256=${HYSTERIA_LINUX_AMD64_SHA256}
hysteria_binary_sha256=$(sha256sum "${INSTALL_ROOT}/bin/hysteria" | awk '{print $1}')
service=${SERVICE_NAME}.service
listen_port=${CANARY_PORT}
config=${CONFIG_FILE}
client_config=${CLIENT_CONFIG_FILE}
client_base_config=${CLIENT_BASE_CONFIG_FILE}
backup=${BACKUP_ROOT}
EOF
chmod 0600 "${INSTALL_ROOT}/manifest"
echo "Hysteria2 canary installed without publishing credentials or changing the public catalog."
