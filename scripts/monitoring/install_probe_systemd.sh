#!/usr/bin/env bash
set -euo pipefail

INSTALL_DIR="/opt/greenvpn-monitoring"
ENV_DIR="/etc/greenvpn-monitoring"
SERVICE_NAME="greenvpn-service-probe"
INSTANCE=""
API_BASE="${GREENVPN_API_BASE:-https://api.greenvpn.pro}"
PROBE_ID="${GREENVPN_PROBE_ID:-$(hostname -s 2>/dev/null || echo probe)}"
PROBE_REGION="${GREENVPN_PROBE_REGION:-external}"
INTERVAL_SECONDS="${GREENVPN_PROBE_INTERVAL_SECONDS:-300}"
API_TIMEOUT_SECONDS="${GREENVPN_PROBE_API_TIMEOUT_SECONDS:-60}"
TOKEN_FILE="${ENV_DIR}/admin_token"
PYTHON_BIN="${GREENVPN_PROBE_PYTHON_BIN:-/usr/bin/python3}"
SOURCE_SCRIPT=""
TOKEN_FROM_STDIN="0"
DRY_RUN="0"
SERVER_HEALTH="1"
ROUTE_HEALTH="1"
ROUTE_CANDIDATES=()
SERVER_HEALTH_SERVER_IDS=()
TARGET_IDS=()

usage() {
  cat <<USAGE
Usage:
  install_probe_systemd.sh [options]

Options:
  --source-script PATH       Path to service_probe.py. Defaults to repo-relative script.
  --instance NAME           Install an isolated additional probe instance.
  --api-base URL             Backend base URL. Default: ${API_BASE}
  --probe-id ID              Stable probe id. Default: ${PROBE_ID}
  --probe-region REGION      Human region/network label. Default: ${PROBE_REGION}
  --interval SECONDS         systemd timer interval. Default: ${INTERVAL_SECONDS}
  --api-timeout SECONDS      Backend admin API request timeout. Default: ${API_TIMEOUT_SECONDS}
  --token-file PATH          Existing admin_token file to copy into ${TOKEN_FILE}
  --token-stdin              Read admin_token from stdin and save only on this machine.
  --python-bin PATH          Absolute Python interpreter for the probe. Default: ${PYTHON_BIN}
  --server-health            Also post VPN endpoint health observations. Default: on.
  --no-server-health         Post only service availability observations.
  --server-health-server-id ID
                             Also probe this managed server id even if it is still
                             draft/inactive. Repeat for pre-publication canaries.
  --route-health             Also post adaptive route observations. Default: on.
  --no-route-health          Do not post adaptive route observations.
  --route-candidate VALUE    Candidate for adaptive route observations. Repeat for canary
                             transports after the probe host actually uses that path.
                             Format: endpointId=...,protocol=...,transport=...
  --target-id ID             Limit this probe to a monitoring target. Repeat as needed.
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
    --instance)
      INSTANCE="${2:-}"
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
    --api-timeout)
      API_TIMEOUT_SECONDS="${2:-}"
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
    --python-bin)
      PYTHON_BIN="${2:-}"
      shift 2
      ;;
    --server-health)
      SERVER_HEALTH="1"
      shift
      ;;
    --no-server-health)
      SERVER_HEALTH="0"
      shift
      ;;
    --server-health-server-id)
      SERVER_HEALTH_SERVER_IDS+=("${2:-}")
      SERVER_HEALTH="1"
      shift 2
      ;;
    --route-health)
      ROUTE_HEALTH="1"
      shift
      ;;
    --no-route-health)
      ROUTE_HEALTH="0"
      shift
      ;;
    --route-candidate)
      ROUTE_CANDIDATES+=("${2:-}")
      shift 2
      ;;
    --target-id)
      TARGET_IDS+=("${2:-}")
      shift 2
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

if [[ -n "${INSTANCE}" ]]; then
  if [[ ! "${INSTANCE}" =~ ^[A-Za-z0-9][A-Za-z0-9._-]{0,39}$ ]]; then
    echo "--instance must be a safe identifier up to 40 characters." >&2
    exit 2
  fi
  INSTALL_DIR="/opt/greenvpn-monitoring-${INSTANCE}"
  ENV_DIR="/etc/greenvpn-monitoring-${INSTANCE}"
  SERVICE_NAME="greenvpn-service-probe-${INSTANCE}"
  TOKEN_FILE="${ENV_DIR}/admin_token"
fi

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

if [[ ! "${API_TIMEOUT_SECONDS}" =~ ^[0-9]+$ ]] || [[ "${API_TIMEOUT_SECONDS}" -lt 10 ]]; then
  echo "--api-timeout must be an integer >= 10 seconds." >&2
  exit 2
fi
if [[ ! "${PYTHON_BIN}" =~ ^/[A-Za-z0-9._/-]+$ ]]; then
  echo "--python-bin must be a safe absolute path." >&2
  exit 2
fi

if [[ "${DRY_RUN}" == "1" ]]; then
  cat <<DRYRUN
[Green VPN probe install] dry-run
install_dir=${INSTALL_DIR}
env_dir=${ENV_DIR}
instance=${INSTANCE:-default}
api_base=${API_BASE}
probe_id=${PROBE_ID}
probe_region=${PROBE_REGION}
interval_seconds=${INTERVAL_SECONDS}
api_timeout_seconds=${API_TIMEOUT_SECONDS}
python_bin=${PYTHON_BIN}
source_script=${SOURCE_SCRIPT}
server_health=${SERVER_HEALTH}
server_health_server_ids=${SERVER_HEALTH_SERVER_IDS[*]:-(none)}
route_health=${ROUTE_HEALTH}
route_candidates=${ROUTE_CANDIDATES[*]:-(default current route)}
target_ids=${TARGET_IDS[*]:-(all active targets)}
service=${SERVICE_NAME}.service
timer=${SERVICE_NAME}.timer
DRYRUN
  exit 0
fi

if [[ "$(id -u)" -ne 0 ]]; then
  echo "Run as root on the monitoring VPS." >&2
  exit 1
fi
if [[ ! -x "${PYTHON_BIN}" ]]; then
  echo "Probe Python is not executable: ${PYTHON_BIN}" >&2
  exit 2
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
GREENVPN_PROBE_API_TIMEOUT_SECONDS="${API_TIMEOUT_SECONDS}"
EOF
chmod 600 "${ENV_DIR}/probe.env"

SERVER_HEALTH_ARGS=""
if [[ "${SERVER_HEALTH}" == "1" ]]; then
  SERVER_HEALTH_ARGS="--server-health"
fi
ROUTE_HEALTH_ARGS=""
if [[ "${ROUTE_HEALTH}" == "1" ]]; then
  ROUTE_HEALTH_ARGS="--route-health"
fi
ROUTE_CANDIDATE_ARGS=""
for candidate in "${ROUTE_CANDIDATES[@]}"; do
  if [[ -z "${candidate}" ]]; then
    echo "--route-candidate value cannot be empty." >&2
    exit 2
  fi
  if [[ "${candidate}" =~ [[:space:]] ]]; then
    echo "--route-candidate cannot contain whitespace; use comma-separated key=value pairs." >&2
    exit 2
  fi
  ROUTE_CANDIDATE_ARGS="${ROUTE_CANDIDATE_ARGS} --route-candidate ${candidate}"
done
SERVER_HEALTH_SERVER_ID_ARGS=""
for server_id in "${SERVER_HEALTH_SERVER_IDS[@]}"; do
  if [[ -z "${server_id}" ]]; then
    echo "--server-health-server-id value cannot be empty." >&2
    exit 2
  fi
  if [[ "${server_id}" =~ [[:space:]] ]]; then
    echo "--server-health-server-id cannot contain whitespace." >&2
    exit 2
  fi
  SERVER_HEALTH_SERVER_ID_ARGS="${SERVER_HEALTH_SERVER_ID_ARGS} --server-health-server-id ${server_id}"
done
TARGET_ID_ARGS=""
for target_id in "${TARGET_IDS[@]}"; do
  if [[ -z "${target_id}" ]]; then
    echo "--target-id value cannot be empty." >&2
    exit 2
  fi
  if [[ ! "${target_id}" =~ ^[A-Za-z0-9._-]+$ ]]; then
    echo "--target-id must contain only safe identifier characters." >&2
    exit 2
  fi
  TARGET_ID_ARGS="${TARGET_ID_ARGS} --target-id ${target_id}"
done

cat > "/etc/systemd/system/${SERVICE_NAME}.service" <<EOF
[Unit]
Description=Green VPN controlled service availability probe
Wants=network-online.target
After=network-online.target

[Service]
Type=oneshot
EnvironmentFile=${ENV_DIR}/probe.env
ExecStart=${PYTHON_BIN} ${INSTALL_DIR}/service_probe.py --api-base \${GREENVPN_API_BASE} --admin-token-file \${GREENVPN_ADMIN_TOKEN_FILE} --probe-id \${GREENVPN_PROBE_ID} --probe-region \${GREENVPN_PROBE_REGION}${TARGET_ID_ARGS} ${SERVER_HEALTH_ARGS}${SERVER_HEALTH_SERVER_ID_ARGS} ${ROUTE_HEALTH_ARGS}${ROUTE_CANDIDATE_ARGS}
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
