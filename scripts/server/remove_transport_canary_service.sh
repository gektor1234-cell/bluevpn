#!/usr/bin/env bash
set -euo pipefail

APPLY=0
PROTOCOL=""
SERVICE_NAME=""
EXPECTED_PUBLIC_IP=""
APPROVED_EXISTING_HOST=""
PROTECTED_HOST_IPS=(
  "37.220.85.211"
  "5.129.216.42"
  "88.218.250.86"
  "72.56.32.197"
  "176.113.81.35"
  "5.129.237.163"
)

usage() {
  cat <<'USAGE'
Green VPN guarded transport canary rollback.

Usage:
  remove_transport_canary_service.sh --protocol PROTOCOL [--service-name NAME]
      [--expected-public-ip IP] [--apply]
      [--approved-existing-host 5.129.216.42]

The default mode is dry-run. Apply mode:
  - is permanently refused on known production/control-plane hosts;
  - requires an exact --expected-public-ip match;
  - stops and removes only the selected canary systemd unit;
  - does not remove configs, keys, binaries, firewall rules or public catalog data.
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --protocol)
      PROTOCOL="${2:?missing protocol}"
      shift 2
      ;;
    --service-name)
      SERVICE_NAME="${2:?missing service name}"
      shift 2
      ;;
    --expected-public-ip)
      EXPECTED_PUBLIC_IP="${2:?missing expected public ip}"
      shift 2
      ;;
    --approved-existing-host)
      APPROVED_EXISTING_HOST="${2:?missing approved existing host}"
      shift 2
      ;;
    --apply)
      APPLY=1
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
  *)
    echo "A supported --protocol is required." >&2
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
if ! [[ "$SERVICE_NAME" =~ ^greenvpn-[a-zA-Z0-9_.@-]+-canary$ ]]; then
  echo "Refusing non-canary service name: $SERVICE_NAME" >&2
  exit 2
fi

PUBLIC_IP="$(curl -fsS --max-time 5 https://api.ipify.org || true)"
for protected_ip in "${PROTECTED_HOST_IPS[@]}"; do
  if [[ "$PUBLIC_IP" == "$protected_ip" && "$APPLY" -eq 1 ]]; then
    approved_nl2_awg=0
    approved_nl2_hysteria=0
    approved_nl2_vless=0
    if [[ "$PUBLIC_IP" == "5.129.216.42" \
      && "$APPROVED_EXISTING_HOST" == "5.129.216.42" \
      && "$PROTOCOL" == "amneziawg" \
      && "$SERVICE_NAME" == "greenvpn-amneziawg-canary" ]]; then
      approved_nl2_awg=1
    fi
    if [[ "$PUBLIC_IP" == "5.129.216.42" \
      && "$APPROVED_EXISTING_HOST" == "5.129.216.42" \
      && "$PROTOCOL" == "hysteria2" \
      && "$SERVICE_NAME" == "greenvpn-hysteria2-canary" ]]; then
      approved_nl2_hysteria=1
    fi
    if [[ "$PUBLIC_IP" == "5.129.216.42" \
      && "$APPROVED_EXISTING_HOST" == "5.129.216.42" \
      && "$PROTOCOL" == "vless_reality" \
      && "$SERVICE_NAME" == "greenvpn-vless-reality-canary" ]]; then
      approved_nl2_vless=1
    fi
    if [[ "$approved_nl2_awg" -ne 1 \
      && "$approved_nl2_hysteria" -ne 1 \
      && "$approved_nl2_vless" -ne 1 ]]; then
      echo "Refusing canary rollback mutation on protected Green VPN host ${protected_ip}." >&2
      exit 1
    fi
    echo "Owner-approved narrow NL2 ${PROTOCOL} rollback exception accepted."
  fi
done
if [[ "$APPLY" -eq 1 ]]; then
  if [[ -z "$PUBLIC_IP" || -z "$EXPECTED_PUBLIC_IP" || "$PUBLIC_IP" != "$EXPECTED_PUBLIC_IP" ]]; then
    echo "Verified public IP does not match --expected-public-ip; refusing apply mode." >&2
    exit 1
  fi
fi

UNIT_PATH="/etc/systemd/system/${SERVICE_NAME}.service"
echo "Green VPN transport canary rollback plan"
echo "public_ip=${PUBLIC_IP:-unknown}"
echo "protocol=${PROTOCOL}"
echo "service=${SERVICE_NAME}.service"
echo "unit_path=${UNIT_PATH}"
echo "mode=$([[ "$APPLY" -eq 1 ]] && echo apply || echo dry-run)"
echo "config_keys_binaries=preserved"
echo "public_catalog=not_changed"

if [[ "$APPLY" -ne 1 ]]; then
  echo "Dry-run only. Re-run with --expected-public-ip and --apply on the test canary node."
  exit 0
fi

systemctl disable --now "${SERVICE_NAME}.service" 2>/dev/null || true
if [[ -f "$UNIT_PATH" ]]; then
  rm -f -- "$UNIT_PATH"
fi
systemctl daemon-reload
systemctl reset-failed "${SERVICE_NAME}.service" 2>/dev/null || true
echo "Canary service removed; config, keys and binaries were preserved for diagnostics."
