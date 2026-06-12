#!/usr/bin/env bash
set -euo pipefail

APPLY=0
ALLOW_CURRENT_VPN_HOST=0
PROTOCOL=""
BINARY=""
CONFIG_FILE=""
SERVICE_NAME=""
CURRENT_VPN_IP="37.220.85.211"

usage() {
  cat <<'EOF'
Green VPN guarded transport canary service installer.

Default mode is dry-run. It never publishes a transport to users.

Usage:
  install_transport_canary_service.sh --protocol PROTOCOL --binary PATH --config-file PATH [--apply]
      [--service-name NAME] [--allow-current-vpn-host]

Supported PROTOCOL values:
  amneziawg
  openvpn_tcp
  shadowsocks
  hysteria2
  trojan_tls
  vless_reality
  masque_udp

Examples:
  install_transport_canary_service.sh --protocol openvpn_tcp \
      --binary /usr/sbin/openvpn \
      --config-file /etc/greenvpn-transport/openvpn_tcp.conf

  install_transport_canary_service.sh --protocol hysteria2 \
      --binary /usr/local/bin/hysteria \
      --config-file /etc/greenvpn-transport/hysteria2.yaml

Safety:
  - intended for a separate canary node;
  - refuses to run on 37.220.85.211 unless --allow-current-vpn-host is set;
  - requires trusted/pinned binaries to be installed before this script runs;
  - requires a root-owned config file that is not world-readable;
  - never prints config contents, credentials or private keys;
  - creates a systemd service only in --apply mode;
  - does not edit WireGuard peers, DNS, backend env, firewall, nginx or public catalog.

WireGuard-over-TCP has its own dedicated script:
  scripts/server/install_wireguard_tcp_canary.sh
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --apply)
      APPLY=1
      shift
      ;;
    --allow-current-vpn-host)
      ALLOW_CURRENT_VPN_HOST=1
      shift
      ;;
    --protocol)
      PROTOCOL="${2:?missing protocol}"
      shift 2
      ;;
    --binary)
      BINARY="${2:?missing binary path}"
      shift 2
      ;;
    --config-file)
      CONFIG_FILE="${2:?missing config file path}"
      shift 2
      ;;
    --service-name)
      SERVICE_NAME="${2:?missing service name}"
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
  echo "Run as root on the canary transport node." >&2
  exit 1
fi

case "${PROTOCOL}" in
  amneziawg|openvpn_tcp|shadowsocks|hysteria2|trojan_tls|vless_reality|masque_udp)
    ;;
  "")
    echo "--protocol is required." >&2
    usage >&2
    exit 2
    ;;
  wireguard_tcp)
    echo "Use install_wireguard_tcp_canary.sh for wireguard_tcp." >&2
    exit 2
    ;;
  *)
    echo "Unsupported protocol: ${PROTOCOL}" >&2
    usage >&2
    exit 2
    ;;
esac

if [[ -z "${BINARY}" || -z "${CONFIG_FILE}" ]]; then
  echo "--binary and --config-file are required." >&2
  exit 2
fi

if [[ "${BINARY}" =~ [[:space:]] || "${CONFIG_FILE}" =~ [[:space:]] ]]; then
  echo "Paths with whitespace are not supported for canary systemd units." >&2
  exit 2
fi

if [[ ! -x "${BINARY}" ]]; then
  echo "Binary is not executable: ${BINARY}" >&2
  echo "Install a trusted/pinned binary first, then rerun this script." >&2
  exit 1
fi

if [[ ! -f "${CONFIG_FILE}" ]]; then
  echo "Config file not found: ${CONFIG_FILE}" >&2
  echo "Create the root-only canary config first. This script will not generate secrets." >&2
  exit 1
fi

CONFIG_OWNER="$(stat -c '%U' "${CONFIG_FILE}" 2>/dev/null || echo unknown)"
CONFIG_MODE="$(stat -c '%a' "${CONFIG_FILE}" 2>/dev/null || echo 000)"
OTHER_PERMS=$(( CONFIG_MODE % 10 ))
if [[ "${CONFIG_OWNER}" != "root" ]]; then
  echo "Config file must be owned by root: ${CONFIG_FILE}" >&2
  exit 1
fi
if (( OTHER_PERMS != 0 )); then
  echo "Config file must not be world-readable/executable: ${CONFIG_FILE} mode=${CONFIG_MODE}" >&2
  exit 1
fi

if [[ -z "${SERVICE_NAME}" ]]; then
  SERVICE_NAME="greenvpn-${PROTOCOL}-canary"
fi
if ! [[ "${SERVICE_NAME}" =~ ^[a-zA-Z0-9_.@-]+$ ]]; then
  echo "Unsafe --service-name: ${SERVICE_NAME}" >&2
  exit 2
fi

PUBLIC_IP="$(curl -fsS --max-time 5 https://api.ipify.org || true)"
if [[ "${PUBLIC_IP}" == "${CURRENT_VPN_IP}" && "${ALLOW_CURRENT_VPN_HOST}" -ne 1 ]]; then
  echo "Refusing to install canary service on current production VPN host ${CURRENT_VPN_IP}." >&2
  echo "Use a separate canary node, or pass --allow-current-vpn-host only for a deliberate maintenance window." >&2
  exit 1
fi

EXEC_START=""
EXEC_STOP=""
case "${PROTOCOL}" in
  amneziawg)
    EXEC_START="${BINARY} up ${CONFIG_FILE}"
    EXEC_STOP="${BINARY} down ${CONFIG_FILE}"
    ;;
  openvpn_tcp)
    EXEC_START="${BINARY} --config ${CONFIG_FILE}"
    ;;
  shadowsocks)
    EXEC_START="${BINARY} -c ${CONFIG_FILE}"
    ;;
  hysteria2)
    EXEC_START="${BINARY} server -c ${CONFIG_FILE}"
    ;;
  trojan_tls)
    EXEC_START="${BINARY} -c ${CONFIG_FILE}"
    ;;
  vless_reality)
    EXEC_START="${BINARY} run -config ${CONFIG_FILE}"
    ;;
  masque_udp)
    EXEC_START="${BINARY} --config ${CONFIG_FILE}"
    ;;
esac

echo "Green VPN guarded transport canary plan"
echo "public_ip=${PUBLIC_IP:-unknown}"
echo "protocol=${PROTOCOL}"
echo "binary=${BINARY}"
echo "config_file=${CONFIG_FILE}"
echo "config_owner=${CONFIG_OWNER}"
echo "config_mode=${CONFIG_MODE}"
echo "service=${SERVICE_NAME}.service"
echo "mode=$([[ "${APPLY}" -eq 1 ]] && echo apply || echo dry-run)"
echo "catalog_publication=not_changed"

if [[ "${APPLY}" -ne 1 ]]; then
  echo "Dry-run only. Re-run with --apply on a canary node to create the service."
  exit 0
fi

cat > "/etc/systemd/system/${SERVICE_NAME}.service" <<EOF
[Unit]
Description=Green VPN guarded ${PROTOCOL} canary transport
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=${EXEC_START}
$(if [[ -n "${EXEC_STOP}" ]]; then echo "ExecStop=${EXEC_STOP}"; fi)
Restart=always
RestartSec=3
NoNewPrivileges=true
PrivateTmp=true

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now "${SERVICE_NAME}.service"
systemctl is-active "${SERVICE_NAME}.service"
echo "Canary service installed. Keep it internal until backend/admin route-health and Windows client engine are ready."
