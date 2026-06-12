#!/usr/bin/env bash
set -euo pipefail

APPLY=0
ALLOW_CURRENT_VPN_HOST=0
LISTEN_PORT="8443"
WIREGUARD_HOST="127.0.0.1"
WIREGUARD_PORT="51820"
UDP2RAW_BIN="/usr/local/bin/udp2raw"
KEY_FILE="/etc/greenvpn-transport/wireguard_tcp_key"
SERVICE_NAME="greenvpn-wg-tcp-canary"
CURRENT_VPN_IP="37.220.85.211"

usage() {
  cat <<'EOF'
Green VPN WireGuard TCP canary installer.

Default mode is dry-run. It does not publish the transport to users.

Usage:
  install_wireguard_tcp_canary.sh [--apply] [--listen-port 8443]
      [--wireguard-host 127.0.0.1] [--wireguard-port 51820]
      [--udp2raw-bin /usr/local/bin/udp2raw]
      [--key-file /etc/greenvpn-transport/wireguard_tcp_key]
      [--allow-current-vpn-host]

Safety:
  - intended for a separate canary VPN node;
  - refuses to run on 37.220.85.211 unless --allow-current-vpn-host is set;
  - never prints the transport key;
  - creates a systemd service only in --apply mode;
  - does not edit WireGuard peers, DNS, backend env, or the public catalog.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --apply)
      APPLY=1
      shift
      ;;
    --listen-port)
      LISTEN_PORT="${2:?missing listen port}"
      shift 2
      ;;
    --wireguard-host)
      WIREGUARD_HOST="${2:?missing WireGuard host}"
      shift 2
      ;;
    --wireguard-port)
      WIREGUARD_PORT="${2:?missing WireGuard port}"
      shift 2
      ;;
    --udp2raw-bin)
      UDP2RAW_BIN="${2:?missing udp2raw path}"
      shift 2
      ;;
    --key-file)
      KEY_FILE="${2:?missing key file path}"
      shift 2
      ;;
    --allow-current-vpn-host)
      ALLOW_CURRENT_VPN_HOST=1
      shift
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
  echo "Run as root on the canary VPN node." >&2
  exit 1
fi

if ! [[ "${LISTEN_PORT}" =~ ^[0-9]+$ ]] || (( LISTEN_PORT < 1 || LISTEN_PORT > 65535 )); then
  echo "Invalid --listen-port: ${LISTEN_PORT}" >&2
  exit 1
fi

if ! [[ "${WIREGUARD_PORT}" =~ ^[0-9]+$ ]] || (( WIREGUARD_PORT < 1 || WIREGUARD_PORT > 65535 )); then
  echo "Invalid --wireguard-port: ${WIREGUARD_PORT}" >&2
  exit 1
fi

PUBLIC_IP="$(curl -fsS --max-time 5 https://api.ipify.org || true)"
if [[ "${PUBLIC_IP}" == "${CURRENT_VPN_IP}" && "${ALLOW_CURRENT_VPN_HOST}" -ne 1 ]]; then
  echo "Refusing to install canary wrapper on current production VPN host ${CURRENT_VPN_IP}." >&2
  echo "Use a separate canary node, or pass --allow-current-vpn-host only for a deliberate maintenance window." >&2
  exit 1
fi

if [[ ! -x "${UDP2RAW_BIN}" ]]; then
  echo "udp2raw binary is not executable at ${UDP2RAW_BIN}." >&2
  echo "Install a trusted/pinned udp2raw build first, then rerun this script." >&2
  exit 1
fi

echo "Green VPN WireGuard TCP canary plan"
echo "public_ip=${PUBLIC_IP:-unknown}"
echo "listen=0.0.0.0:${LISTEN_PORT}"
echo "wireguard=${WIREGUARD_HOST}:${WIREGUARD_PORT}"
echo "service=${SERVICE_NAME}.service"
echo "mode=$([[ "${APPLY}" -eq 1 ]] && echo apply || echo dry-run)"

if [[ "${APPLY}" -ne 1 ]]; then
  echo "Dry-run only. Re-run with --apply on a canary node to create the service."
  exit 0
fi

install -d -m 0700 "$(dirname "${KEY_FILE}")"
if [[ ! -f "${KEY_FILE}" ]]; then
  umask 077
  head -c 32 /dev/urandom | base64 > "${KEY_FILE}"
fi
chmod 0600 "${KEY_FILE}"

cat > "/etc/systemd/system/${SERVICE_NAME}.service" <<EOF
[Unit]
Description=Green VPN WireGuard TCP canary wrapper
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=/bin/sh -c 'exec "${UDP2RAW_BIN}" -s -l 0.0.0.0:${LISTEN_PORT} -r ${WIREGUARD_HOST}:${WIREGUARD_PORT} --raw-mode faketcp -k "\$(cat "${KEY_FILE}")" -a'
Restart=always
RestartSec=3
NoNewPrivileges=true

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now "${SERVICE_NAME}.service"
systemctl is-active "${SERVICE_NAME}.service"
echo "Canary service installed. Keep it internal until backend/admin route-health and Windows client engine are ready."
