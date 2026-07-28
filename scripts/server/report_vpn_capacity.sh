#!/usr/bin/env bash
set -euo pipefail

IFACE="wg0"
WG_TOOL="wg"
SERVER_ID="current_wg0"
API_BASE="https://api.greenvpn.pro"
TOKEN_FILE=""
PLANNED_MBPS=""
RESERVED_MBPS=""
SAMPLE_SECONDS="10"
ACTIVE_WINDOW_SECONDS="180"
REPORT_PEER_TRAFFIC="0"
APPLY="0"

usage() {
  cat <<'USAGE'
Usage:
  report_vpn_capacity.sh [--apply] --token-file /root/admin_token \
    [--server-id current_wg0] [--iface wg0] [--api-base https://api.greenvpn.pro]

Options:
  --apply                    POST the capacity payload to backend. Default is dry-run.
  --token-file PATH          Root-only file with admin token. Required for --apply.
  --server-id ID             Managed server_catalog serverId to update.
  --iface IFACE              WireGuard interface, default wg0.
  --wg-tool PATH             WireGuard-compatible CLI, default wg.
  --api-base URL             Backend API base, default https://api.greenvpn.pro.
  --planned-mbps N           Optional planned link bandwidth override.
  --reserved-mbps N          Optional reserved bandwidth override.
  --sample-seconds N         Measurement window, default 10.
  --active-window-seconds N  Peer is active if latest handshake is newer than this, default 180.
  --report-peer-traffic      Also report per-peer WireGuard counters for traffic usage accounting.

Notes:
  - Dry-run is default and prints only sanitized JSON.
  - The admin token is read only from --token-file and is never printed.
  - The script measures total rx+tx delta on the WireGuard interface.
  - Peer traffic reporting sends public keys and byte counters only; private keys are never read.
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --apply)
      APPLY="1"
      shift
      ;;
    --token-file)
      TOKEN_FILE="${2:-}"
      shift 2
      ;;
    --server-id)
      SERVER_ID="${2:-}"
      shift 2
      ;;
    --iface)
      IFACE="${2:-}"
      shift 2
      ;;
    --wg-tool)
      WG_TOOL="${2:-}"
      shift 2
      ;;
    --api-base)
      API_BASE="${2:-}"
      shift 2
      ;;
    --planned-mbps)
      PLANNED_MBPS="${2:-}"
      shift 2
      ;;
    --reserved-mbps)
      RESERVED_MBPS="${2:-}"
      shift 2
      ;;
    --sample-seconds)
      SAMPLE_SECONDS="${2:-}"
      shift 2
      ;;
    --active-window-seconds)
      ACTIVE_WINDOW_SECONDS="${2:-}"
      shift 2
      ;;
    --report-peer-traffic)
      REPORT_PEER_TRAFFIC="1"
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

require_uint() {
  local name="$1"
  local value="$2"
  if ! [[ "$value" =~ ^[0-9]+$ ]]; then
    echo "$name must be an integer." >&2
    exit 2
  fi
}

require_uint "--sample-seconds" "$SAMPLE_SECONDS"
require_uint "--active-window-seconds" "$ACTIVE_WINDOW_SECONDS"
if [[ -n "$PLANNED_MBPS" ]]; then
  require_uint "--planned-mbps" "$PLANNED_MBPS"
fi
if [[ -n "$RESERVED_MBPS" ]]; then
  require_uint "--reserved-mbps" "$RESERVED_MBPS"
fi

rx_path="/sys/class/net/${IFACE}/statistics/rx_bytes"
tx_path="/sys/class/net/${IFACE}/statistics/tx_bytes"
if [[ ! -r "$rx_path" || ! -r "$tx_path" ]]; then
  echo "Interface statistics are not readable for ${IFACE}." >&2
  exit 2
fi

if [[ "$WG_TOOL" == */* ]]; then
  if [[ ! -x "$WG_TOOL" ]]; then
    echo "WireGuard tool is not executable: ${WG_TOOL}" >&2
    exit 2
  fi
elif ! command -v "$WG_TOOL" >/dev/null 2>&1; then
  echo "WireGuard tool is required: ${WG_TOOL}" >&2
  exit 2
fi

rx1="$(cat "$rx_path")"
tx1="$(cat "$tx_path")"
sleep "$SAMPLE_SECONDS"
rx2="$(cat "$rx_path")"
tx2="$(cat "$tx_path")"

delta_bytes=$(((rx2 - rx1) + (tx2 - tx1)))
if [[ "$delta_bytes" -lt 0 ]]; then
  delta_bytes="0"
fi
current_load_mbps="$(awk -v bytes="$delta_bytes" -v sec="$SAMPLE_SECONDS" 'BEGIN { printf "%d", ((bytes * 8) / sec / 1000000) + 0.5 }')"

now_epoch="$(date +%s)"
peer_rows="$("$WG_TOOL" show "$IFACE" dump | awk 'NR > 1')"
assigned_users="0"
active_clients="0"
if [[ -n "$peer_rows" ]]; then
  assigned_users="$(printf '%s\n' "$peer_rows" | awk 'NF > 0 { count++ } END { print count + 0 }')"
  active_clients="$(
    printf '%s\n' "$peer_rows" |
      awk -v now="$now_epoch" -v win="$ACTIVE_WINDOW_SECONDS" 'NF > 0 && $5 > 0 && (now - $5) <= win { count++ } END { print count + 0 }'
  )"
fi

observed_at="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

payload="$(awk \
  -v currentLoadMbps="$current_load_mbps" \
  -v activeClients="$active_clients" \
  -v assignedUsers="$assigned_users" \
  -v loadUpdatedAt="$observed_at" \
  -v plannedBandwidthMbps="$PLANNED_MBPS" \
  -v reservedBandwidthMbps="$RESERVED_MBPS" \
  'BEGIN {
    printf "{";
    sep="";
    if (plannedBandwidthMbps != "") { printf "%s\"plannedBandwidthMbps\":%d", sep, plannedBandwidthMbps; sep=","; }
    if (reservedBandwidthMbps != "") { printf "%s\"reservedBandwidthMbps\":%d", sep, reservedBandwidthMbps; sep=","; }
    printf "%s\"currentLoadMbps\":%d", sep, currentLoadMbps; sep=",";
    printf "%s\"activeClients\":%d", sep, activeClients;
    printf "%s\"assignedUsers\":%d", sep, assignedUsers;
    printf "%s\"loadUpdatedAt\":\"%s\"", sep, loadUpdatedAt;
    printf "}";
  }'
)"

endpoint="${API_BASE%/}/api/v1/admin/server-catalog/server-id/${SERVER_ID}/capacity"
traffic_endpoint="${API_BASE%/}/api/v1/admin/traffic/wireguard-report"
traffic_payload=""
if [[ "$REPORT_PEER_TRAFFIC" == "1" ]]; then
  traffic_payload="$(
    printf '%s\n' "$peer_rows" |
      awk -v serverId="$SERVER_ID" -v iface="$IFACE" -v observedAt="$observed_at" '
        BEGIN {
          printf "{";
          printf "\"serverId\":\"%s\",\"iface\":\"%s\",\"observedAt\":\"%s\",\"peers\":[", serverId, iface, observedAt;
          sep="";
        }
        NF > 0 {
          publicKey=$1;
          peerIp=$4;
          sub(/,.*/, "", peerIp);
          sub(/\/32$/, "", peerIp);
          latestHandshake=$5;
          rxBytes=$6 + 0;
          txBytes=$7 + 0;
          printf "%s{\"publicKey\":\"%s\",\"peerIp\":\"%s\",\"rxBytes\":%d,\"txBytes\":%d,\"latestHandshakeAt\":\"%s\"}", sep, publicKey, peerIp, rxBytes, txBytes, latestHandshake;
          sep=",";
        }
        END {
          printf "]}";
        }
      '
  )"
fi

if [[ "$APPLY" != "1" ]]; then
  cat <<EOF
{
  "ok": true,
  "mode": "dry-run",
  "endpoint": "$endpoint",
  "trafficEndpoint": "$traffic_endpoint",
  "peerTrafficReportEnabled": $REPORT_PEER_TRAFFIC,
  "interface": "$IFACE",
  "sampleSeconds": $SAMPLE_SECONDS,
  "payload": $payload,
  "trafficPayload": ${traffic_payload:-null}
}
EOF
  exit 0
fi

if [[ -z "$TOKEN_FILE" ]]; then
  echo "--token-file is required with --apply." >&2
  exit 2
fi
if [[ ! -r "$TOKEN_FILE" ]]; then
  echo "Token file is not readable." >&2
  exit 2
fi
token="$(tr -d '\r\n' < "$TOKEN_FILE")"
if [[ -z "$token" ]]; then
  echo "Token file is empty." >&2
  exit 2
fi

curl -fsS \
  -X POST "$endpoint" \
  -H "Authorization: Bearer ${token}" \
  -H "Content-Type: application/json" \
  --data "$payload" >/dev/null

if [[ "$REPORT_PEER_TRAFFIC" == "1" ]]; then
  curl -fsS \
    -X POST "$traffic_endpoint" \
    -H "Authorization: Bearer ${token}" \
    -H "Content-Type: application/json" \
    --data "$traffic_payload" >/dev/null
fi

echo "{\"ok\":true,\"mode\":\"applied\",\"serverId\":\"${SERVER_ID}\",\"interface\":\"${IFACE}\",\"currentLoadMbps\":${current_load_mbps},\"activeClients\":${active_clients},\"assignedUsers\":${assigned_users}}"
