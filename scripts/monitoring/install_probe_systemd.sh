#!/usr/bin/env bash
set -euo pipefail

INSTALL_DIR="/opt/greenvpn-monitoring"
ENV_DIR="/etc/greenvpn-monitoring"
SERVICE_NAME="greenvpn-service-probe"
API_BASE="${GREENVPN_API_BASE:-https://api.greenvpn.pro}"
PROBE_ID="${GREENVPN_PROBE_ID:-$(hostname -s 2>/dev/null || echo probe)}"
PROBE_REGION="${GREENVPN_PROBE_REGION:-external}"
INTERVAL_SECONDS="${GREENVPN_PROBE_INTERVAL_SECONDS:-300}"
TOKEN_FILE="${ENV_DIR}/admin_token"
SOURCE_SCRIPT=""
TOKEN_FROM_STDIN="0"
DRY_RUN="0"
SERVER_HEALTH="1"

usage() {
  cat <<USAGE
Usage:
  install_probe_systemd.sh [options]

Options:
  --source-script PATH       Path to service_probe.py. Defaults to repo-relative script.
  --api-base URL             Backend base URL. Default: ${API_BASE}
  --probe-id ID              Stable probe id. Default: ${PROBE_ID}
  --probe-region REGION      Human region/network label. Default: ${PROBE_REGION}
  --interval SECONDS         systemd timer interval. Default: ${INTERVAL_SECONDS}
  --token-file PATH          Existing admin_token file to copy into ${TOKEN_FILE}
  --token-stdin              Read admin_token from stdin and save only on this machine.
  --server-health            Also post VPN endpoint health observations. Default: on.
  --no-server-health         Post only service availability observations.
  --dry-run                  Print actions without writing systemd files.
  -h, --help                 Show this help.

Secrets are never written to the repository. The admin token is stored only on
the probe machine at ${TOKEN_FILE} with mode 600.
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --source-script)
      SOURCE_SCRIPT="${2:-}"
      shift 2
      ;;
    --api-base)
      API_BASE="${2:-}"
      shift 2
      ;;
    --probe-id)
      PROBE_ID="${2:-}"
      shift 2
      ;;
    --probe-region)
      PROBE_REGION="${2:-}"
      shift 2
      ;;
    --interval)
      INTERVAL_SECONDS="${2:-}"
      shift 2
      ;;
    --token-file)
      INPUT_TOKEN_FILE="${2:-}"
      shift 2
      ;;
    --token-stdin)
      TOKEN_FROM_STDIN="1"
      shift
      ;;
    --server-health)
      SERVER_HEALTH="1"
      shift
      ;;
    --no-server-health)
      SERVER_HEALTH="0"
      shift
      ;;
    --dry-run)
      DRY_RUN="1"
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

if [[ -z "${SOURCE_SCRIPT}" ]]; then
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  SOURCE_SCRIPT="${SCRIPT_DIR}/service_probe.py"
fi

if [[ ! -f "${SOURCE_SCRIPT}" ]]; then
  echo "service_probe.py not found: ${SOURCE_SCRIPT}" >&2
  exit 2
fi

if [[ ! "${INTERVAL_SECONDS}" =~ ^[0-9]+$ ]] || [[ "${INTERVAL_SECONDS}" -lt 60 ]]; then
  echo "--interval must be an integer >= 60 seconds." >&2
  exit 2
fi

if [[ "${DRY_RUN}" == "1" ]]; then
  cat <<DRYRUN
[Green VPN probe install] dry-run
install_dir=${INSTALL_DIR}
env_dir=${ENV_DIR}
api_base=${API_BASE}
probe_id=${PROBE_ID}
probe_region=${PROBE_REGION}
interval_seconds=${INTERVAL_SECONDS}
source_script=${SOURCE_SCRIPT}
server_health=${SERVER_HEALTH}
service=${SERVICE_NAME}.service
timer=${SERVICE_NAME}.timer
DRYRUN
  exit 0
fi

if [[ "$(id -u)" -ne 0 ]]; then
  echo "Run as root on the monitoring VPS." >&2
  exit 1
fi

install -d -m 755 "${INSTALL_DIR}"
install -d -m 700 "${ENV_DIR}"
install -m 755 "${SOURCE_SCRIPT}" "${INSTALL_DIR}/service_probe.py"

if [[ "${TOKEN_FROM_STDIN}" == "1" ]]; then
  umask 077
  cat > "${TOKEN_FILE}"
elif [[ -n "${INPUT_TOKEN_FILE:-}" ]]; then
  install -m 600 "${INPUT_TOKEN_FILE}" "${TOKEN_FILE}"
elif [[ ! -s "${TOKEN_FILE}" ]]; then
  echo "Admin token is required on first install. Use --token-stdin or --token-file." >&2
  exit 2
fi
chmod 600 "${TOKEN_FILE}"

cat > "${ENV_DIR}/probe.env" <<EOF
GREENVPN_API_BASE="${API_BASE}"
GREENVPN_PROBE_ID="${PROBE_ID}"
GREENVPN_PROBE_REGION="${PROBE_REGION}"
GREENVPN_ADMIN_TOKEN_FILE="${TOKEN_FILE}"
EOF
chmod 600 "${ENV_DIR}/probe.env"

SERVER_HEALTH_ARGS=""
if [[ "${SERVER_HEALTH}" == "1" ]]; then
  SERVER_HEALTH_ARGS="--server-health"
fi

cat > "/etc/systemd/system/${SERVICE_NAME}.service" <<EOF
[Unit]
Description=Green VPN controlled service availability probe
Wants=network-online.target
After=network-online.target

[Service]
Type=oneshot
EnvironmentFile=${ENV_DIR}/probe.env
ExecStart=/usr/bin/env python3 ${INSTALL_DIR}/service_probe.py --api-base \${GREENVPN_API_BASE} --admin-token-file \${GREENVPN_ADMIN_TOKEN_FILE} --probe-id \${GREENVPN_PROBE_ID} --probe-region \${GREENVPN_PROBE_REGION} ${SERVER_HEALTH_ARGS}
User=root
PrivateTmp=true
NoNewPrivileges=true
EOF

cat > "/etc/systemd/system/${SERVICE_NAME}.timer" <<EOF
[Unit]
Description=Run Green VPN service availability probe every ${INTERVAL_SECONDS} seconds

[Timer]
OnBootSec=90
OnUnitActiveSec=${INTERVAL_SECONDS}
AccuracySec=30
Unit=${SERVICE_NAME}.service

[Install]
WantedBy=timers.target
EOF

systemctl daemon-reload
systemctl enable --now "${SERVICE_NAME}.timer"
systemctl start "${SERVICE_NAME}.service" || true
systemctl status "${SERVICE_NAME}.timer" --no-pager

echo "[Green VPN probe install] installed. Check logs with:"
echo "journalctl -u ${SERVICE_NAME}.service -n 80 --no-pager"
