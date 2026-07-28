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
APPROVED_EXISTING_HOST=""
PROTECTED_HOST_IPS=(
  "37.220.85.211"
  "5.129.216.42"
  "88.218.250.86"
  "72.56.32.197"
  "176.113.81.35"
  "5.129.237.163"
)
APPROVED_DATA_PLANE_IPS=(
  "37.220.85.211"
  "5.129.216.42"
  "88.218.250.86"
)

usage() {
  cat <<'USAGE'
Green VPN guarded transport canary readiness checker.

Usage:
  check_transport_canary_readiness.sh --protocol PROTOCOL [--service-name NAME]
      [--binary PATH] [--config-file PATH] [--listen-port PORT]
      [--endpoint-id ID] [--transport TRANSPORT] [--json]
      [--approved-existing-host EXACT_DATA_PLANE_IP]

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
    --approved-existing-host)
      APPROVED_EXISTING_HOST="${2:-}"
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

host_has_protected_ip() {
  local addresses
  addresses="$(hostname -I 2>/dev/null || true) $(curl -fsS --max-time 5 https://api.ipify.org || true)"
  for protected_ip in "${PROTECTED_HOST_IPS[@]}"; do
    if printf '%s\n' "$addresses" | tr ' ' '\n' | grep -qxF "$protected_ip"; then
      return 0
    fi
  done
  return 1
}

if host_has_protected_ip; then
  public_ip="$(curl -fsS --max-time 5 https://api.ipify.org || true)"
  approved_data_plane=0
  for approved_ip in "${APPROVED_DATA_PLANE_IPS[@]}"; do
    [[ "${public_ip}" == "${approved_ip}" ]] && approved_data_plane=1
  done
  approved_tuple=0
  if [[ "${APPROVED_EXISTING_HOST}" == "${public_ip}" ]]; then
    case "${PROTOCOL}" in
      amneziawg)
        [[ "${SERVICE_NAME}" == "greenvpn-amneziawg-canary" \
          && "${CONFIG_FILE}" == "/etc/greenvpn-transport/awgcanary0.conf" ]] \
          && approved_tuple=1
        ;;
      hysteria2)
        [[ "${SERVICE_NAME}" == "greenvpn-hysteria2-canary" \
          && "${CONFIG_FILE}" == "/etc/greenvpn-transport/hysteria2-canary.yaml" ]] \
          && approved_tuple=1
        ;;
      vless_reality)
        [[ "${SERVICE_NAME}" == "greenvpn-vless-reality-canary" \
          && "${CONFIG_FILE}" == "/etc/greenvpn-transport/vless-reality-xhttp-canary.json" ]] \
          && approved_tuple=1
        ;;
    esac
  fi
  if [[ "${approved_data_plane}" -ne 1 || "${approved_tuple}" -ne 1 ]]; then
    add_blocker "protected_production_host_refused"
  fi
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
  elif [[ -L "$CONFIG_FILE" ]]; then
    add_blocker "config_symlink_refused"
  else
    owner_uid="$(stat -c '%u' "$CONFIG_FILE" 2>/dev/null || echo unknown)"
    mode="$(stat -c '%a' "$CONFIG_FILE" 2>/dev/null || echo 777)"
    group_digit="${mode: -2:1}"
    other_digit="${mode: -1}"
    if [[ "$owner_uid" != "0" ]]; then
      add_blocker "config_not_root_owned"
    fi
    if [[ "$group_digit" =~ ^[0-7]$ ]] && (( group_digit != 0 )); then
      add_blocker "config_not_root_only"
    fi
    if [[ "$other_digit" =~ ^[0-7]$ ]] && (( other_digit != 0 )); then
      add_blocker "config_not_root_only"
    fi
    if [[ "$PROTOCOL" == "amneziawg" ]]; then
      required_awg_fields=(PrivateKey ListenPort S1 S2 S3 S4 H1 H2 H3 H4)
      for field in "${required_awg_fields[@]}"; do
        if ! grep -Eq "^[[:space:]]*${field}[[:space:]]*=" "$CONFIG_FILE"; then
          add_blocker "amneziawg2_required_fields_missing"
          break
        fi
      done
      if ! grep -Eq '^[[:space:]]*\[Peer\][[:space:]]*$' "$CONFIG_FILE"; then
        add_blocker "amneziawg_canary_peer_missing"
      fi
      header_values="$(sed -nE 's/^[[:space:]]*H[1-4][[:space:]]*=[[:space:]]*([^[:space:]#]+).*/\1/p' "$CONFIG_FILE")"
      if [[ "$(printf '%s\n' "$header_values" | sed '/^$/d' | wc -l)" -ne 4 ]] \
        || [[ "$(printf '%s\n' "$header_values" | sed '/^$/d' | sort -u | wc -l)" -ne 4 ]] \
        || printf '%s\n' "$header_values" | grep -Evq '^[0-9]+(-[0-9]+)?$' \
        || printf '%s\n' "$header_values" | grep -qx '0'; then
        add_blocker "amneziawg2_headers_invalid"
      fi
    elif [[ "$PROTOCOL" == "hysteria2" ]]; then
      for pattern in \
        '^[[:space:]]*listen:[[:space:]]*' \
        '^[[:space:]]*auth:[[:space:]]*$' \
        '^[[:space:]]*obfs:[[:space:]]*$' \
        '^[[:space:]]*masquerade:[[:space:]]*$'; do
        if ! grep -Eq "$pattern" "$CONFIG_FILE"; then
          add_blocker "hysteria2_required_fields_missing"
          break
        fi
      done
      if ! grep -Eq '^[[:space:]]*(tls|acme):[[:space:]]*$' "$CONFIG_FILE"; then
        add_blocker "hysteria2_tls_material_missing"
      fi
      if grep -Eq '^[[:space:]]*insecure:[[:space:]]*(true|yes|1)[[:space:]]*$' "$CONFIG_FILE"; then
        add_blocker "hysteria2_insecure_tls_refused"
      fi
      if ! grep -Eq '^[[:space:]]*type:[[:space:]]*salamander[[:space:]]*$' "$CONFIG_FILE"; then
        add_blocker "hysteria2_obfuscation_missing"
      fi
    elif [[ "$PROTOCOL" == "vless_reality" ]]; then
      if ! python3 - "$CONFIG_FILE" <<'PY'
import json
import sys

with open(sys.argv[1], "r", encoding="utf-8") as handle:
    root = json.load(handle)
inbounds = root.get("inbounds")
if not isinstance(inbounds, list) or len(inbounds) != 1:
    raise SystemExit(1)
inbound = inbounds[0]
stream = inbound.get("streamSettings") or {}
reality = stream.get("realitySettings") or {}
xhttp = stream.get("xhttpSettings") or {}
if inbound.get("protocol") != "vless":
    raise SystemExit(1)
if stream.get("network") != "xhttp" or stream.get("security") != "reality":
    raise SystemExit(1)
if not isinstance(reality.get("target"), str) or ":443" not in reality["target"]:
    raise SystemExit(1)
if not reality.get("serverNames") or not reality.get("privateKey") or not reality.get("shortIds"):
    raise SystemExit(1)
if not isinstance(xhttp.get("path"), str) or not xhttp["path"].startswith("/"):
    raise SystemExit(1)
if xhttp.get("mode", "auto") not in {"auto", "stream-one", "stream-up", "packet-up"}:
    raise SystemExit(1)
PY
      then
        add_blocker "vless_reality_xhttp_config_invalid"
      fi
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
