#!/usr/bin/env bash
set -euo pipefail

PROTOCOL=""
BINARY_PATH=""
CONFIG_FILE=""
SERVICE_NAME=""
LISTEN_PORT=""
ENDPOINT_ID=""
TRANSPORT=""
JSON_OUTPUT=0
ALLOW_CURRENT_VPN_HOST=0
CURRENT_VPN_IP="37.220.85.211"

usage() {
  cat <<'USAGE'
Green VPN guarded transport canary readiness checker.

Usage:
  check_transport_canary_readiness.sh --protocol PROTOCOL [--service-name NAME]
      [--binary PATH] [--config-file PATH] [--listen-port PORT]
      [--endpoint-id ID] [--transport TRANSPORT] [--json]

Supported protocols:
  wireguard_tcp
  amneziawg
  openvpn_tcp
  shadowsocks
  hysteria2
  trojan_tls
  vless_reality
  masque_udp

This checker is safe to run before public rollout:
  - does not read or print transport secrets;
  - does not edit WireGuard peers, backend env, DNS, firewall, nginx or catalog;
  - refuses the current production VPN host by default;
  - only reports sanitized readiness and the route-candidate string for the probe.
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --protocol)
      PROTOCOL="${2:-}"
      shift 2
      ;;
    --binary)
      BINARY_PATH="${2:-}"
      shift 2
      ;;
    --config-file)
      CONFIG_FILE="${2:-}"
      shift 2
      ;;
    --service-name)
      SERVICE_NAME="${2:-}"
      shift 2
      ;;
    --listen-port)
      LISTEN_PORT="${2:-}"
      shift 2
      ;;
    --endpoint-id)
      ENDPOINT_ID="${2:-}"
      shift 2
      ;;
    --transport)
      TRANSPORT="${2:-}"
      shift 2
      ;;
    --json)
      JSON_OUTPUT=1
      shift
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

case "$PROTOCOL" in
  wireguard_tcp|amneziawg|openvpn_tcp|shadowsocks|hysteria2|trojan_tls|vless_reality|masque_udp)
    ;;
  "")
    echo "--protocol is required." >&2
    usage >&2
    exit 2
    ;;
  *)
    echo "Unsupported protocol: $PROTOCOL" >&2
    usage >&2
    exit 2
    ;;
esac

if [[ -z "$SERVICE_NAME" ]]; then
  if [[ "$PROTOCOL" == "wireguard_tcp" ]]; then
    SERVICE_NAME="greenvpn-wg-tcp-canary"
  else
    SERVICE_NAME="greenvpn-${PROTOCOL}-canary"
  fi
fi

if [[ -z "$ENDPOINT_ID" ]]; then
  ENDPOINT_ID="${PROTOCOL}_canary"
fi

if [[ -z "$TRANSPORT" ]]; then
  case "$PROTOCOL" in
    wireguard_tcp|openvpn_tcp)
      TRANSPORT="tcp"
      ;;
    amneziawg)
      TRANSPORT="udp"
      ;;
    shadowsocks)
      TRANSPORT="tcp"
      ;;
    hysteria2)
      TRANSPORT="quic"
      ;;
    trojan_tls)
      TRANSPORT="tls"
      ;;
    vless_reality)
      TRANSPORT="reality"
      ;;
    masque_udp)
      TRANSPORT="masque"
      ;;
  esac
fi

BLOCKERS=()
WARNINGS=()

add_blocker() {
  BLOCKERS+=("$1")
}

add_warning() {
  WARNINGS+=("$1")
}

json_array() {
  local first=1
  printf '['
  for item in "$@"; do
    if [[ $first -eq 0 ]]; then
      printf ','
    fi
    first=0
    printf '"%s"' "$item"
  done
  printf ']'
}

host_has_current_ip() {
  hostname -I 2>/dev/null | tr ' ' '\n' | grep -qxF "$CURRENT_VPN_IP"
}

if host_has_current_ip && [[ "$ALLOW_CURRENT_VPN_HOST" -ne 1 ]]; then
  add_blocker "current_production_vpn_host_refused"
fi

if [[ -n "$BINARY_PATH" ]]; then
  if [[ ! -x "$BINARY_PATH" ]]; then
    add_blocker "binary_missing_or_not_executable"
  fi
else
  add_warning "binary_path_not_checked"
fi

if [[ -n "$CONFIG_FILE" ]]; then
  if [[ ! -f "$CONFIG_FILE" ]]; then
    add_blocker "config_file_missing"
  else
    owner_uid="$(stat -c '%u' "$CONFIG_FILE" 2>/dev/null || echo unknown)"
    mode="$(stat -c '%a' "$CONFIG_FILE" 2>/dev/null || echo 777)"
    other_digit="${mode: -1}"
    if [[ "$owner_uid" != "0" ]]; then
      add_blocker "config_not_root_owned"
    fi
    if [[ "$other_digit" =~ ^[0-7]$ ]] && (( other_digit & 4 )); then
      add_blocker "config_world_readable"
    fi
  fi
else
  add_warning "config_file_not_checked"
fi

SERVICE_ACTIVE=0
if systemctl list-unit-files "${SERVICE_NAME}.service" >/dev/null 2>&1; then
  if systemctl is-active --quiet "${SERVICE_NAME}.service"; then
    SERVICE_ACTIVE=1
  else
    add_blocker "service_not_active"
  fi
else
  add_blocker "service_not_installed"
fi

LISTEN_READY=0
if [[ -n "$LISTEN_PORT" ]]; then
  if ! [[ "$LISTEN_PORT" =~ ^[0-9]+$ ]] || (( LISTEN_PORT < 1 || LISTEN_PORT > 65535 )); then
    add_blocker "listen_port_invalid"
  elif command -v ss >/dev/null 2>&1; then
    if ss -H -lntu 2>/dev/null | awk '{print $5}' | grep -Eq "(:|])${LISTEN_PORT}$"; then
      LISTEN_READY=1
    else
      add_blocker "listen_port_not_open"
    fi
  else
    add_warning "ss_not_available_listen_not_checked"
  fi
else
  add_warning "listen_port_not_checked"
fi

READY=0
if [[ "${#BLOCKERS[@]}" -eq 0 ]]; then
  READY=1
fi

ROUTE_CANDIDATE=""
if [[ "$READY" -eq 1 ]]; then
  ROUTE_CANDIDATE="endpointId=${ENDPOINT_ID},protocol=${PROTOCOL},transport=${TRANSPORT}"
fi

if [[ "$JSON_OUTPUT" -eq 1 ]]; then
  printf '{'
  printf '"ok":%s,' "$([[ "$READY" -eq 1 ]] && echo true || echo false)"
  printf '"protocol":"%s",' "$PROTOCOL"
  printf '"serviceName":"%s",' "$SERVICE_NAME"
  printf '"serviceActive":%s,' "$([[ "$SERVICE_ACTIVE" -eq 1 ]] && echo true || echo false)"
  printf '"listenChecked":%s,' "$([[ -n "$LISTEN_PORT" ]] && echo true || echo false)"
  printf '"listenReady":%s,' "$([[ "$LISTEN_READY" -eq 1 ]] && echo true || echo false)"
  printf '"routeCandidate":"%s",' "$ROUTE_CANDIDATE"
  printf '"blockers":'
  json_array "${BLOCKERS[@]}"
  printf ',"warnings":'
  json_array "${WARNINGS[@]}"
  printf '}\n'
else
  echo "Green VPN transport canary readiness"
  echo "protocol=${PROTOCOL}"
  echo "service=${SERVICE_NAME}"
  echo "ready=${READY}"
  echo "service_active=${SERVICE_ACTIVE}"
  if [[ -n "$LISTEN_PORT" ]]; then
    echo "listen_port=${LISTEN_PORT}"
    echo "listen_ready=${LISTEN_READY}"
  fi
  if [[ -n "$ROUTE_CANDIDATE" ]]; then
    echo "route_candidate=${ROUTE_CANDIDATE}"
  fi
  if [[ "${#BLOCKERS[@]}" -gt 0 ]]; then
    echo "blockers=${BLOCKERS[*]}"
  fi
  if [[ "${#WARNINGS[@]}" -gt 0 ]]; then
    echo "warnings=${WARNINGS[*]}"
  fi
fi
