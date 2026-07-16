#!/usr/bin/env bash
set -Eeuo pipefail

usage() {
  cat <<'EOF'
Usage: smoke_remote_wireguard_dataplane.sh --node-env PATH [--rounds N]

Runs an isolated WireGuard data-plane smoke from a control-plane host. The
temporary peer, network namespace and firewall rules are removed on exit.
EOF
}

NODE_ENV=""
ROUNDS=3

while (($#)); do
  case "$1" in
    --node-env)
      NODE_ENV="${2:-}"
      shift 2
      ;;
    --rounds)
      ROUNDS="${2:-}"
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

[[ ${EUID} -eq 0 ]] || { echo "Run as root." >&2; exit 1; }
[[ -n ${NODE_ENV} && -f ${NODE_ENV} ]] || { echo "A valid --node-env is required." >&2; exit 2; }
[[ ${ROUNDS} =~ ^[1-9][0-9]*$ && ${ROUNDS} -le 10 ]] || { echo "--rounds must be between 1 and 10." >&2; exit 2; }

# shellcheck disable=SC1090
source "${NODE_ENV}"

required=(
  GREENVPN_NODE_HOST
  GREENVPN_NODE_USER
  GREENVPN_NODE_SSH_KEY
  GREENVPN_NODE_PUBLIC_HOST
  GREENVPN_NODE_PUBLIC_PORT
  GREENVPN_NODE_WG_INTERFACE
)
for name in "${required[@]}"; do
  [[ -n ${!name:-} ]] || { echo "Missing ${name}." >&2; exit 2; }
done

[[ ${GREENVPN_NODE_HOST} =~ ^[A-Za-z0-9.-]+$ ]]
[[ ${GREENVPN_NODE_USER} =~ ^[A-Za-z_][A-Za-z0-9_-]*$ ]]
[[ ${GREENVPN_NODE_PUBLIC_HOST} =~ ^[A-Za-z0-9.-]+$ ]]
[[ ${GREENVPN_NODE_PUBLIC_PORT} =~ ^[0-9]+$ ]]
[[ ${GREENVPN_NODE_WG_INTERFACE} =~ ^[A-Za-z0-9_.-]+$ ]]
[[ -r ${GREENVPN_NODE_SSH_KEY} ]] || { echo "SSH key is not readable." >&2; exit 2; }
command -v wg >/dev/null
command -v ip >/dev/null
command -v curl >/dev/null
if command -v iptables >/dev/null; then
  firewall_backend=iptables
elif command -v nft >/dev/null; then
  firewall_backend=nft
else
  echo "Neither iptables nor nft is available." >&2
  exit 1
fi
original_ip_forward="$(sysctl -n net.ipv4.ip_forward)"
[[ ${original_ip_forward} == 0 || ${original_ip_forward} == 1 ]] || { echo "Unexpected IPv4 forwarding state." >&2; exit 1; }

SSH=(
  ssh -i "${GREENVPN_NODE_SSH_KEY}"
  -o BatchMode=yes
  -o ConnectTimeout=10
  -o StrictHostKeyChecking=yes
  "${GREENVPN_NODE_USER}@${GREENVPN_NODE_HOST}"
)

endpoint_ip="$(getent ahostsv4 "${GREENVPN_NODE_PUBLIC_HOST}" | awk 'NR == 1 {print $1}')"
[[ ${endpoint_ip} =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] || { echo "Public endpoint did not resolve to IPv4." >&2; exit 1; }
wan_iface="$(ip -4 route get "${endpoint_ip}" | awk '{for (i=1; i<=NF; i++) if ($i == "dev") {print $(i+1); exit}}')"
[[ ${wan_iface} =~ ^[A-Za-z0-9_.-]+$ ]] || { echo "Could not determine WAN interface." >&2; exit 1; }

server_public_key="$("${SSH[@]}" "wg show ${GREENVPN_NODE_WG_INTERFACE} public-key")"
[[ -n ${server_public_key} ]] || { echo "Remote WireGuard public key is empty." >&2; exit 1; }
if [[ -n ${GREENVPN_NODE_WG_PUBLIC_KEY:-} && ${server_public_key} != "${GREENVPN_NODE_WG_PUBLIC_KEY}" ]]; then
  echo "Live WireGuard public key does not match the control-plane inventory." >&2
  exit 1
fi

used_ips="$("${SSH[@]}" "wg show ${GREENVPN_NODE_WG_INTERFACE} allowed-ips" | awk '{for (i=2; i<=NF; i++) print $i}')"
client_ip=""
for candidate in $(seq 240 250); do
  if ! grep -qx "10.10.0.${candidate}/32" <<<"${used_ips}"; then
    client_ip="10.10.0.${candidate}"
    break
  fi
done
[[ -n ${client_ip} ]] || { echo "No isolated smoke address is available." >&2; exit 1; }

suffix="$(printf '%05d' $((RANDOM % 100000)))"
namespace="gvns${suffix}"
host_veth="gvh${suffix}"
ns_veth="gvn${suffix}"
tag="gv-london-smoke-${suffix}"
nft_table="gvsm${suffix}"
workdir="$(mktemp -d /root/greenvpn-london-dataplane.XXXXXX)"
chmod 700 "${workdir}"
private_key_file="${workdir}/client.key"
public_key_file="${workdir}/client.pub"
wg genkey | tee "${private_key_file}" | wg pubkey >"${public_key_file}"
chmod 600 "${private_key_file}" "${public_key_file}"
client_public_key="$(<"${public_key_file}")"

octet=$((100 + (10#${suffix} % 100)))
while ip -4 address show | grep -q "169\.254\.${octet}\."; do
  octet=$((octet + 1))
  ((octet < 254)) || octet=100
done
host_link_ip="169.254.${octet}.1"
ns_link_ip="169.254.${octet}.2"
link_cidr="169.254.${octet}.0/30"

peer_added=0
namespace_added=0
firewall_added=0
forwarding_changed=0

cleanup() {
  set +e
  if ((peer_added)); then
    "${SSH[@]}" "wg set ${GREENVPN_NODE_WG_INTERFACE} peer ${client_public_key} remove" >/dev/null 2>&1
  fi
  if ((namespace_added)); then
    ip netns delete "${namespace}" >/dev/null 2>&1
  fi
  if ((firewall_added)); then
    if [[ ${firewall_backend} == iptables ]]; then
      iptables -D FORWARD -i "${host_veth}" -o "${wan_iface}" -m comment --comment "${tag}" -j ACCEPT >/dev/null 2>&1
      iptables -D FORWARD -i "${wan_iface}" -o "${host_veth}" -m conntrack --ctstate RELATED,ESTABLISHED -m comment --comment "${tag}" -j ACCEPT >/dev/null 2>&1
      iptables -t nat -D POSTROUTING -s "${link_cidr}" -o "${wan_iface}" -m comment --comment "${tag}" -j MASQUERADE >/dev/null 2>&1
    else
      nft delete table ip "${nft_table}" >/dev/null 2>&1
    fi
  fi
  if ((forwarding_changed)); then
    sysctl -q -w "net.ipv4.ip_forward=${original_ip_forward}" >/dev/null 2>&1
  fi
  rm -rf -- "/etc/netns/${namespace}"
  rm -rf -- "${workdir}"
}
trap cleanup EXIT INT TERM

if [[ ${original_ip_forward} == 0 ]]; then
  sysctl -q -w net.ipv4.ip_forward=1
  forwarding_changed=1
fi

"${SSH[@]}" "wg set ${GREENVPN_NODE_WG_INTERFACE} peer ${client_public_key} allowed-ips ${client_ip}/32"
peer_added=1

ip netns add "${namespace}"
namespace_added=1
install -d -m 0755 "/etc/netns/${namespace}"
printf 'nameserver 1.1.1.1\nnameserver 8.8.8.8\n' >"/etc/netns/${namespace}/resolv.conf"
ip link add "${host_veth}" type veth peer name "${ns_veth}"
ip link set "${ns_veth}" netns "${namespace}"
ip address add "${host_link_ip}/30" dev "${host_veth}"
ip link set "${host_veth}" up
ip netns exec "${namespace}" ip link set lo up
ip netns exec "${namespace}" ip address add "${ns_link_ip}/30" dev "${ns_veth}"
ip netns exec "${namespace}" ip link set "${ns_veth}" up
ip netns exec "${namespace}" ip route add default via "${host_link_ip}" dev "${ns_veth}"

if [[ ${firewall_backend} == iptables ]]; then
  iptables -I FORWARD 1 -i "${host_veth}" -o "${wan_iface}" -m comment --comment "${tag}" -j ACCEPT
  iptables -I FORWARD 1 -i "${wan_iface}" -o "${host_veth}" -m conntrack --ctstate RELATED,ESTABLISHED -m comment --comment "${tag}" -j ACCEPT
  iptables -t nat -I POSTROUTING 1 -s "${link_cidr}" -o "${wan_iface}" -m comment --comment "${tag}" -j MASQUERADE
else
  nft add table ip "${nft_table}"
  nft "add chain ip ${nft_table} forward { type filter hook forward priority 0; policy accept; }"
  nft "add chain ip ${nft_table} postrouting { type nat hook postrouting priority srcnat; policy accept; }"
  nft add rule ip "${nft_table}" forward iifname "${host_veth}" oifname "${wan_iface}" accept
  nft add rule ip "${nft_table}" forward iifname "${wan_iface}" oifname "${host_veth}" ct state related,established accept
  nft add rule ip "${nft_table}" postrouting ip saddr "${link_cidr}" oifname "${wan_iface}" masquerade
fi
firewall_added=1

ip netns exec "${namespace}" ip link add wg0 type wireguard
ip netns exec "${namespace}" wg set wg0 \
  private-key "${private_key_file}" \
  peer "${server_public_key}" \
  endpoint "${endpoint_ip}:${GREENVPN_NODE_PUBLIC_PORT}" \
  allowed-ips 0.0.0.0/0 \
  persistent-keepalive 5
ip netns exec "${namespace}" ip address add "${client_ip}/32" dev wg0
ip netns exec "${namespace}" ip link set wg0 up
ip netns exec "${namespace}" ip route add "${endpoint_ip}/32" via "${host_link_ip}" dev "${ns_veth}"
ip netns exec "${namespace}" ip route replace default dev wg0

handshake_ok=false
for _ in $(seq 1 20); do
  ip netns exec "${namespace}" ping -c 1 -W 1 10.10.0.1 >/dev/null 2>&1 || true
  latest="$(ip netns exec "${namespace}" wg show wg0 latest-handshakes | awk 'NR == 1 {print $2}')"
  if [[ ${latest:-0} =~ ^[0-9]+$ && ${latest:-0} -gt 0 ]]; then
    handshake_ok=true
    break
  fi
  sleep 1
done
[[ ${handshake_ok} == true ]] || { echo "WireGuard handshake did not complete." >&2; exit 1; }

api_ok=0
google_ok=0
youtube_ok=0
for _ in $(seq 1 "${ROUNDS}"); do
  api_status="$(ip netns exec "${namespace}" curl -4ksS --max-time 20 -o /dev/null -w '%{http_code}' https://api.greenvpn.pro/healthz || true)"
  google_status="$(ip netns exec "${namespace}" curl -4sS --max-time 20 -o /dev/null -w '%{http_code}' https://www.google.com/generate_204 || true)"
  youtube_status="$(ip netns exec "${namespace}" curl -4sS --max-time 20 -o /dev/null -w '%{http_code}' https://www.youtube.com/generate_204 || true)"
  [[ ${api_status} == 200 ]] && ((api_ok += 1))
  [[ ${google_status} == 200 || ${google_status} == 204 ]] && ((google_ok += 1))
  [[ ${youtube_status} == 200 || ${youtube_status} == 204 ]] && ((youtube_ok += 1))
done

read -r rx_bytes tx_bytes < <(ip netns exec "${namespace}" wg show wg0 transfer | awk 'NR == 1 {print $2, $3}')
egress_ip="$(ip netns exec "${namespace}" curl -4fsS --max-time 20 https://api.ipify.org || true)"
[[ ${api_ok} -eq ${ROUNDS} && ${google_ok} -eq ${ROUNDS} && ${youtube_ok} -eq ${ROUNDS} ]] || {
  echo "HTTP data-plane checks did not all pass." >&2
  exit 1
}
[[ ${rx_bytes:-0} -gt 0 && ${tx_bytes:-0} -gt 0 ]] || { echo "WireGuard transfer counters are empty." >&2; exit 1; }
[[ ${egress_ip} == "${endpoint_ip}" ]] || { echo "Tunnel egress does not match the VPN node." >&2; exit 1; }

cleanup
trap - EXIT INT TERM
peer_added=0
namespace_added=0
firewall_added=0
forwarding_changed=0

if "${SSH[@]}" "wg show ${GREENVPN_NODE_WG_INTERFACE} peers" | grep -Fxq "${client_public_key}"; then
  echo "Temporary remote peer was not removed." >&2
  exit 1
fi
ip netns list | grep -q "^${namespace}\b" && { echo "Temporary namespace was not removed." >&2; exit 1; }
if [[ ${firewall_backend} == iptables ]]; then
  iptables-save | grep -Fq "${tag}" && { echo "Temporary firewall rules were not removed." >&2; exit 1; }
else
  nft list table ip "${nft_table}" >/dev/null 2>&1 && { echo "Temporary nft table was not removed." >&2; exit 1; }
fi
[[ ! -e ${workdir} ]] || { echo "Temporary key directory was not removed." >&2; exit 1; }
[[ ! -e /etc/netns/${namespace} ]] || { echo "Temporary namespace resolver was not removed." >&2; exit 1; }
[[ $(sysctl -n net.ipv4.ip_forward) == "${original_ip_forward}" ]] || { echo "IPv4 forwarding state was not restored." >&2; exit 1; }

printf '{"ok":true,"handshake":true,"apiRounds":%d,"googleRounds":%d,"youtubeRounds":%d,"egressMatches":true,"rxBytesPositive":true,"txBytesPositive":true,"cleanup":true}\n' \
  "${api_ok}" "${google_ok}" "${youtube_ok}"
