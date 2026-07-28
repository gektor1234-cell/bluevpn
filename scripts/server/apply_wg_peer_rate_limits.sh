#!/usr/bin/env bash
set -euo pipefail

IFACE="wg0"
ROOT_MBPS="1000"
RESERVED_MBPS="250"
FREE_MBPS="10"
FREE_BURST_MBPS="20"
APPLY="0"
PEER_FILE=""
PEERS=()

usage() {
  cat <<'USAGE'
Usage:
  apply_wg_peer_rate_limits.sh [--apply] [--iface wg0] [--root-mbps 1000] [--reserved-mbps 250] \
    [--free-mbps 10] [--free-burst-mbps 20] \
    --peer 10.8.0.2=paid_standard --peer 10.8.0.3=free_ad

  apply_wg_peer_rate_limits.sh --apply --free-mbps 10 --free-burst-mbps 20 \
    --file /etc/greenvpn/peer-rate-limits.txt

Peer classes:
  free_ad        configurable sustained/burst, defaults to 10/20mbit
  paid_light     25mbit sustained, 100mbit burst
  paid_standard  50mbit sustained, 150mbit burst
  paid_plus      100mbit sustained, 250mbit burst
  paid_max       150mbit sustained, 300mbit burst
  bulk_heavy     10mbit sustained, 30mbit burst

Notes:
  - Dry-run is default. Pass --apply to change tc qdisc/filter state.
  - This shapes traffic leaving the WireGuard interface toward client VPN IPs.
  - Input format is vpn_ip=class, one per --peer or one per file line.
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
    --root-mbps)
      ROOT_MBPS="${2:-}"
      shift 2
      ;;
    --reserved-mbps)
      RESERVED_MBPS="${2:-}"
      shift 2
      ;;
    --free-mbps)
      FREE_MBPS="${2:-}"
      shift 2
      ;;
    --free-burst-mbps)
      FREE_BURST_MBPS="${2:-}"
      shift 2
      ;;
    --peer)
      PEERS+=("${2:-}")
      shift 2
      ;;
    --file)
      PEER_FILE="${2:-}"
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

if [[ -n "$PEER_FILE" ]]; then
  if [[ ! -f "$PEER_FILE" ]]; then
    echo "Peer file not found: $PEER_FILE" >&2
    exit 2
  fi
  while IFS= read -r line; do
    line="${line%%#*}"
    line="$(echo "$line" | xargs)"
    [[ -z "$line" ]] && continue
    PEERS+=("$line")
  done < "$PEER_FILE"
fi

if [[ ${#PEERS[@]} -eq 0 ]]; then
  echo "No peers supplied. Nothing to do." >&2
  usage >&2
  exit 2
fi

if ! [[ "$ROOT_MBPS" =~ ^[0-9]+$ ]] \
  || ! [[ "$RESERVED_MBPS" =~ ^[0-9]+$ ]] \
  || ! [[ "$FREE_MBPS" =~ ^[0-9]+$ ]] \
  || ! [[ "$FREE_BURST_MBPS" =~ ^[0-9]+$ ]]; then
  echo "Bandwidth values must be integers." >&2
  exit 2
fi
if (( FREE_MBPS < 1 || FREE_MBPS > 1000 )); then
  echo "--free-mbps must be between 1 and 1000." >&2
  exit 2
fi
if (( FREE_BURST_MBPS < FREE_MBPS || FREE_BURST_MBPS > 2000 )); then
  echo "--free-burst-mbps must be between free-mbps and 2000." >&2
  exit 2
fi

USABLE_MBPS=$((ROOT_MBPS - RESERVED_MBPS))
if [[ "$USABLE_MBPS" -lt 1 ]]; then
  echo "Reserved bandwidth must be lower than root bandwidth." >&2
  exit 2
fi

run() {
  if [[ "$APPLY" == "1" ]]; then
    "$@"
  else
    printf '[dry-run] '
    printf '%q ' "$@"
    printf '\n'
  fi
}

class_params() {
  case "$1" in
    free_ad)        echo "10 ${FREE_MBPS} ${FREE_BURST_MBPS}" ;;
    paid_light)     echo "20 25 100" ;;
    paid_standard)  echo "30 50 150" ;;
    paid_plus)      echo "40 100 250" ;;
    paid_max)       echo "50 150 300" ;;
    bulk_heavy)     echo "60 10 30" ;;
    *)
      echo "Unknown peer class: $1" >&2
      exit 2
      ;;
  esac
}

validate_ip() {
  local ip="$1"
  if [[ ! "$ip" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
    echo "Invalid IPv4 peer address: $ip" >&2
    exit 2
  fi
}

echo "Green VPN WireGuard rate-limit plan"
echo "Interface: $IFACE"
echo "Root: ${ROOT_MBPS}mbit, reserved: ${RESERVED_MBPS}mbit, usable: ${USABLE_MBPS}mbit"
echo "Mode: $([[ "$APPLY" == "1" ]] && echo apply || echo dry-run)"

run tc qdisc del dev "$IFACE" root || true
run tc qdisc add dev "$IFACE" root handle 1: htb default 90
run tc class add dev "$IFACE" parent 1: classid 1:1 htb rate "${USABLE_MBPS}mbit" ceil "${ROOT_MBPS}mbit"
run tc class add dev "$IFACE" parent 1:1 classid 1:90 htb rate "10mbit" ceil "50mbit" prio 7
run tc qdisc add dev "$IFACE" parent 1:90 fq_codel

declare -A CLASS_CREATED=()
FILTER_PRIO=10

for peer in "${PEERS[@]}"; do
  if [[ "$peer" != *=* ]]; then
    echo "Bad peer entry, expected ip=class: $peer" >&2
    exit 2
  fi
  ip="${peer%%=*}"
  cls="${peer#*=}"
  ip="${ip%/32}"
  validate_ip "$ip"
  read -r class_id rate burst <<<"$(class_params "$cls")"

  if [[ -z "${CLASS_CREATED[$class_id]+x}" ]]; then
    run tc class add dev "$IFACE" parent 1:1 classid "1:${class_id}" htb rate "${rate}mbit" ceil "${burst}mbit" prio "$class_id"
    run tc qdisc add dev "$IFACE" parent "1:${class_id}" fq_codel
    CLASS_CREATED[$class_id]="1"
  fi

  run tc filter add dev "$IFACE" protocol ip parent 1:0 prio "$FILTER_PRIO" u32 match ip dst "$ip/32" flowid "1:${class_id}"
  FILTER_PRIO=$((FILTER_PRIO + 1))
done

echo "Done."
