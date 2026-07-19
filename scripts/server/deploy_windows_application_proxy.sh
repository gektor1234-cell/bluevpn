#!/usr/bin/env bash
set -euo pipefail

APPLY=0
EXPECTED_PUBLIC_IP=""
APPROVED_EXISTING_HOST=""
TARGET_HOST="5.129.216.42"
WG_INTERFACE="wg0"
WG_ADDRESS="10.10.0.1"
WG_NETWORK="10.10.0.0/24"
LISTEN_PORT="1080"
CONFIG_PATH="/etc/danted.conf"
SERVICE_NAME="danted.service"

usage() {
  cat <<'USAGE'
Deploy the internal SOCKS5 gateway for Green VPN Windows application routing.

Default mode is dry-run. Apply is restricted to the owner-approved NL2 host:
  deploy_windows_application_proxy.sh \
    --expected-public-ip 5.129.216.42 \
    --approved-existing-host 5.129.216.42 --apply

The gateway binds only to 10.10.0.1:1080 on wg0 and accepts clients only from
10.10.0.0/24. It is not published in the user catalog and does not alter wg0,
peers, routes, NAT, DNS, nginx, backend services, or other transports.
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --apply)
      APPLY=1
      shift
      ;;
    --expected-public-ip)
      EXPECTED_PUBLIC_IP="${2:?missing expected public IP}"
      shift 2
      ;;
    --approved-existing-host)
      APPROVED_EXISTING_HOST="${2:?missing approved host}"
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
  echo "Run as root on the target VPN node." >&2
  exit 1
fi

if ! ip -4 -o address show scope global | awk '{print $4}' \
  | cut -d/ -f1 | grep -Fxq "${TARGET_HOST}"; then
  echo "Refusing deployment outside exact NL2 host ${TARGET_HOST}." >&2
  exit 1
fi
if [[ "${APPLY}" -eq 1 ]] && {
  [[ "${EXPECTED_PUBLIC_IP}" != "${TARGET_HOST}" ]] \
    || [[ "${APPROVED_EXISTING_HOST}" != "${TARGET_HOST}" ]];
}; then
  echo "Apply requires exact expected and approved NL2 host values." >&2
  exit 1
fi
if ! ip link show dev "${WG_INTERFACE}" >/dev/null 2>&1; then
  echo "Required interface ${WG_INTERFACE} is missing." >&2
  exit 1
fi
if ! ip -4 -o address show dev "${WG_INTERFACE}" \
  | awk '{print $4}' | grep -Fxq "${WG_ADDRESS}/24"; then
  echo "Required ${WG_ADDRESS}/24 address is missing on ${WG_INTERFACE}." >&2
  exit 1
fi

EXTERNAL_INTERFACE="$(ip -4 route show default | awk 'NR == 1 {print $5}')"
if [[ -z "${EXTERNAL_INTERFACE}" ]]; then
  echo "Cannot determine the external interface." >&2
  exit 1
fi

echo "Green VPN Windows application proxy plan"
echo "host=${TARGET_HOST}"
echo "internal=${WG_ADDRESS}:${LISTEN_PORT}"
echo "clients=${WG_NETWORK}"
echo "external_interface=${EXTERNAL_INTERFACE}"
echo "service=${SERVICE_NAME}"
echo "mode=$([[ "${APPLY}" -eq 1 ]] && echo apply || echo dry-run)"
echo "wireguard=not_changed"
echo "public_catalog=not_changed"

if [[ "${APPLY}" -ne 1 ]]; then
  echo "Dry-run only. Re-run with exact host approval and --apply."
  exit 0
fi

umask 077
STAMP="$(date -u +%Y%m%dT%H%M%SZ)"
BACKUP_ROOT="/root/greenvpn-windows-app-proxy-prechange/${STAMP}"
mkdir -p "${BACKUP_ROOT}"
chmod 0700 "${BACKUP_ROOT}"

PACKAGE_WAS_INSTALLED=0
SERVICE_WAS_ENABLED=0
SERVICE_WAS_ACTIVE=0
dpkg-query -W -f='${Status}' dante-server 2>/dev/null \
  | grep -Fq 'install ok installed' && PACKAGE_WAS_INSTALLED=1 || true
systemctl is-enabled --quiet "${SERVICE_NAME}" 2>/dev/null \
  && SERVICE_WAS_ENABLED=1 || true
systemctl is-active --quiet "${SERVICE_NAME}" 2>/dev/null \
  && SERVICE_WAS_ACTIVE=1 || true

if [[ -e "${CONFIG_PATH}" ]]; then
  cp -a -- "${CONFIG_PATH}" "${BACKUP_ROOT}/danted.conf"
fi
systemctl cat "${SERVICE_NAME}" > "${BACKUP_ROOT}/danted.service.txt" 2>/dev/null || true
iptables-save > "${BACKUP_ROOT}/iptables-save.txt" 2>/dev/null || true
nft list ruleset > "${BACKUP_ROOT}/nft-ruleset.txt" 2>/dev/null || true

cat > "${BACKUP_ROOT}/state.env" <<EOF
PACKAGE_WAS_INSTALLED=${PACKAGE_WAS_INSTALLED}
SERVICE_WAS_ENABLED=${SERVICE_WAS_ENABLED}
SERVICE_WAS_ACTIVE=${SERVICE_WAS_ACTIVE}
EOF
chmod 0600 "${BACKUP_ROOT}/state.env"

if [[ "${PACKAGE_WAS_INSTALLED}" -ne 1 ]]; then
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -qq
  apt-get install -y --no-install-recommends dante-server
fi

cat > "${CONFIG_PATH}" <<EOF
logoutput: syslog
internal: ${WG_ADDRESS} port = ${LISTEN_PORT}
external: ${EXTERNAL_INTERFACE}
clientmethod: none
socksmethod: none
user.privileged: proxy
user.unprivileged: nobody

client pass {
  from: ${WG_NETWORK} to: 0.0.0.0/0
  log: error
}

client block {
  from: 0.0.0.0/0 to: 0.0.0.0/0
  log: error
}

socks pass {
  from: ${WG_NETWORK} to: 0.0.0.0/0
  command: connect udpassociate
  protocol: tcp udp
  socksmethod: none
  log: error
}

socks block {
  from: 0.0.0.0/0 to: 0.0.0.0/0
  log: error
}
EOF
chown root:root "${CONFIG_PATH}"
chmod 0600 "${CONFIG_PATH}"

danted -V -f "${CONFIG_PATH}"
systemctl enable "${SERVICE_NAME}"
systemctl restart "${SERVICE_NAME}"
systemctl is-active --quiet "${SERVICE_NAME}"

LISTEN_STATE="$(ss -H -lntup "sport = :${LISTEN_PORT}" 2>/dev/null || true)"
if [[ -z "${LISTEN_STATE}" ]]; then
  echo "Dante did not create the expected listener." >&2
  exit 1
fi
if ! grep -Fq "${WG_ADDRESS}:${LISTEN_PORT}" <<<"${LISTEN_STATE}"; then
  echo "Dante is not bound to the expected internal address." >&2
  exit 1
fi
if grep -Eq "(^|[[:space:]])(0\.0\.0\.0|${TARGET_HOST}):${LISTEN_PORT}([[:space:]]|$)" \
  <<<"${LISTEN_STATE}"; then
  echo "Dante unexpectedly exposed the gateway on a public/wildcard address." >&2
  exit 1
fi

cat > "${BACKUP_ROOT}/rollback.sh" <<'ROLLBACK'
#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
source "${ROOT}/state.env"
systemctl stop danted.service 2>/dev/null || true
if [[ -f "${ROOT}/danted.conf" ]]; then
  cp -a -- "${ROOT}/danted.conf" /etc/danted.conf
else
  rm -f -- /etc/danted.conf
fi
if [[ "${SERVICE_WAS_ENABLED}" -eq 1 ]]; then
  systemctl enable danted.service
else
  systemctl disable danted.service 2>/dev/null || true
fi
if [[ "${SERVICE_WAS_ACTIVE}" -eq 1 ]]; then
  systemctl restart danted.service
fi
if [[ "${PACKAGE_WAS_INSTALLED}" -ne 1 ]]; then
  apt-get remove -y dante-server
fi
ROLLBACK
chmod 0700 "${BACKUP_ROOT}/rollback.sh"

echo "application_proxy=ready"
echo "backup=${BACKUP_ROOT}"
