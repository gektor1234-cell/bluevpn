#!/usr/bin/env bash
set -euo pipefail

APPLY="0"
IFACE="wg0"
WG_PORT="443"
WG_ADDRESS="10.10.0.1/24"
WG_NETWORK="10.10.0.0/24"
WAN_IFACE=""

usage() {
  cat <<'USAGE'
Usage:
  bootstrap_wireguard_node.sh [--apply] [--iface wg0] [--port 443] [--wg-address 10.10.0.1/24] [--wg-network 10.10.0.0/24] [--wan-iface eth0]

Default mode is dry-run. Use --apply only on a fresh test VPS.

The script:
  - installs WireGuard and basic networking tools;
  - enables IPv4 forwarding;
  - creates /etc/wireguard/wg0.conf;
  - starts wg-quick@wg0;
  - prints only the server public key and safe connection facts.

It never prints the WireGuard private key.
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --apply)
      APPLY="1"
      shift
      ;;
    --iface)
      IFACE="${2:-}"
      shift 2
      ;;
    --port)
      WG_PORT="${2:-}"
      shift 2
      ;;
    --wg-address)
      WG_ADDRESS="${2:-}"
      shift 2
      ;;
    --wg-network)
      WG_NETWORK="${2:-}"
      shift 2
      ;;
    --wan-iface)
      WAN_IFACE="${2:-}"
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

if [[ "$(id -u)" != "0" ]]; then
  echo "Run as root." >&2
  exit 2
fi

if [[ -z "$WAN_IFACE" ]]; then
  WAN_IFACE="$(ip route get 1.1.1.1 2>/dev/null | awk '{ for (i=1; i<=NF; i++) if ($i == "dev") { print $(i+1); exit } }')"
fi
if [[ -z "$WAN_IFACE" ]]; then
  echo "Unable to detect WAN interface. Pass --wan-iface." >&2
  exit 2
fi

echo "Green VPN WireGuard node bootstrap"
echo "mode=$([[ "$APPLY" == "1" ]] && echo apply || echo dry-run)"
echo "iface=$IFACE"
echo "port=$WG_PORT"
echo "wg_address=$WG_ADDRESS"
echo "wg_network=$WG_NETWORK"
echo "wan_iface=$WAN_IFACE"

if [[ "$APPLY" != "1" ]]; then
  echo "Dry-run only. Re-run with --apply on the fresh VPS."
  exit 0
fi

export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y wireguard iptables iproute2 ca-certificates curl python3

install -d -m 0700 /etc/wireguard
private_key_path="/etc/wireguard/${IFACE}_server_private.key"
public_key_path="/etc/wireguard/${IFACE}_server_public.key"

if [[ ! -s "$private_key_path" ]]; then
  umask 077
  wg genkey > "$private_key_path"
fi
wg pubkey < "$private_key_path" > "$public_key_path"

conf_path="/etc/wireguard/${IFACE}.conf"
private_key="$(cat "$private_key_path")"
cat > "$conf_path" <<EOF
[Interface]
Address = ${WG_ADDRESS}
ListenPort = ${WG_PORT}
PrivateKey = ${private_key}
SaveConfig = false
PostUp = iptables -t nat -A POSTROUTING -s ${WG_NETWORK} -o ${WAN_IFACE} -j MASQUERADE; iptables -A FORWARD -i ${IFACE} -j ACCEPT; iptables -A FORWARD -o ${IFACE} -j ACCEPT
PostDown = iptables -t nat -D POSTROUTING -s ${WG_NETWORK} -o ${WAN_IFACE} -j MASQUERADE; iptables -D FORWARD -i ${IFACE} -j ACCEPT; iptables -D FORWARD -o ${IFACE} -j ACCEPT
EOF
chmod 0600 "$conf_path"
unset private_key

cat > /etc/sysctl.d/99-greenvpn-wireguard.conf <<EOF
net.ipv4.ip_forward=1
EOF
sysctl --system >/dev/null

systemctl enable "wg-quick@${IFACE}" >/dev/null
systemctl restart "wg-quick@${IFACE}"

server_public_key="$(cat "$public_key_path")"
echo "status=ok"
echo "server_public_key=${server_public_key}"
echo "backend_env_required=GREENVPN_NODE_HOST, GREENVPN_NODE_SSH_KEY, GREENVPN_NODE_WG_PUBLIC_KEY, GREENVPN_NODE_PUBLIC_PORT=${WG_PORT}, GREENVPN_NODE_WG_INTERFACE=${IFACE}"
echo "private_key_path=${private_key_path}"
echo "Do not copy the private key into the repository."
