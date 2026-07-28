#!/usr/bin/env bash
set -euo pipefail

APPLY="0"
IFACE="wg0"
WG_TOOL="wg"
SERVER_ID="current_wg0"
API_BASE="https://api.greenvpn.pro"
TOKEN_FILE="/etc/greenvpn-monitoring/admin_token"
SCRIPT_PATH="/opt/greenvpn-server/report_vpn_capacity.sh"
UNIT_NAME="greenvpn-vpn-capacity-report"
INTERVAL_SECONDS="60"
PLANNED_MBPS=""
RESERVED_MBPS=""
REPORT_PEER_TRAFFIC="0"

usage() {
  cat <<'USAGE'
Usage:
  install_vpn_capacity_reporter_systemd.sh [--apply] [options]

Options:
  --apply              Install and start the systemd timer. Default is dry-run.
  --token-file PATH    Root-only admin token file used by the reporter.
  --script-path PATH   Where to install report_vpn_capacity.sh.
  --unit-name NAME     systemd unit prefix, default greenvpn-vpn-capacity-report.
  --server-id ID       Managed server_catalog serverId, default current_wg0.
  --iface IFACE        WireGuard interface, default wg0.
  --wg-tool PATH       WireGuard-compatible CLI used by the interface.
  --api-base URL       Backend API base, default https://api.greenvpn.pro.
  --interval-seconds N Timer interval, default 60.
  --planned-mbps N     Optional planned link bandwidth sent by reporter.
  --reserved-mbps N    Optional reserved bandwidth sent by reporter.
  --report-peer-traffic Also report per-peer WireGuard counters for usage/quota accounting.

Notes:
  - Dry-run prints the systemd unit/timer and does not install anything.
  - Token values are never printed; only the token file path is used.
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
    --script-path)
      SCRIPT_PATH="${2:-}"
      shift 2
      ;;
    --unit-name)
      UNIT_NAME="${2:-}"
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
    --interval-seconds)
      INTERVAL_SECONDS="${2:-}"
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

if ! [[ "$INTERVAL_SECONDS" =~ ^[0-9]+$ ]] || [[ "$INTERVAL_SECONDS" -lt 30 ]]; then
  echo "--interval-seconds must be an integer >= 30." >&2
  exit 2
fi
if ! [[ "$UNIT_NAME" =~ ^[A-Za-z0-9_.@-]+$ ]]; then
  echo "--unit-name contains unsafe characters." >&2
  exit 2
fi

source_script="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/report_vpn_capacity.sh"
if [[ ! -f "$source_script" ]]; then
  echo "report_vpn_capacity.sh not found next to installer." >&2
  exit 2
fi

extra_args=()
if [[ -n "$PLANNED_MBPS" ]]; then
  extra_args+=(--planned-mbps "$PLANNED_MBPS")
fi
if [[ -n "$RESERVED_MBPS" ]]; then
  extra_args+=(--reserved-mbps "$RESERVED_MBPS")
fi
if [[ "$REPORT_PEER_TRAFFIC" == "1" ]]; then
  extra_args+=(--report-peer-traffic)
fi

service_file="/etc/systemd/system/${UNIT_NAME}.service"
timer_file="/etc/systemd/system/${UNIT_NAME}.timer"
exec_start=(
  "$SCRIPT_PATH"
  --apply
  --token-file "$TOKEN_FILE"
  --server-id "$SERVER_ID"
  --iface "$IFACE"
  --wg-tool "$WG_TOOL"
  --api-base "$API_BASE"
)
exec_start+=("${extra_args[@]}")

render_exec_start() {
  printf '%q ' "${exec_start[@]}"
}

service_content="$(
  cat <<EOF
[Unit]
Description=Green VPN capacity reporter
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
User=root
ExecStart=$(render_exec_start)
EOF
)"

timer_content="$(
  cat <<EOF
[Unit]
Description=Run Green VPN capacity reporter periodically

[Timer]
OnBootSec=120
OnUnitActiveSec=${INTERVAL_SECONDS}
AccuracySec=10
Unit=${UNIT_NAME}.service

[Install]
WantedBy=timers.target
EOF
)"

if [[ "$APPLY" != "1" ]]; then
  cat <<EOF
[dry-run] install -m 0755 "$source_script" "$SCRIPT_PATH"
[dry-run] write $service_file:
$service_content

[dry-run] write $timer_file:
$timer_content

[dry-run] systemctl daemon-reload
[dry-run] systemctl enable --now ${UNIT_NAME}.timer
EOF
  exit 0
fi

if [[ ! -r "$TOKEN_FILE" ]]; then
  echo "Token file is not readable: $TOKEN_FILE" >&2
  exit 2
fi

install -d -m 0755 "$(dirname "$SCRIPT_PATH")"
install -m 0755 "$source_script" "$SCRIPT_PATH"
printf '%s\n' "$service_content" > "$service_file"
printf '%s\n' "$timer_content" > "$timer_file"
chmod 0644 "$service_file" "$timer_file"
systemctl daemon-reload
systemctl enable --now "${UNIT_NAME}.timer"
systemctl list-timers --all "${UNIT_NAME}.timer" --no-pager
