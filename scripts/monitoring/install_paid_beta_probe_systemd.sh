#!/usr/bin/env bash
set -euo pipefail

APPLY=0
ROLE=""
SOURCE_SCRIPT=""
INTERVAL_SECONDS=300

INSTALL_DIR="/opt/bluevpn-paid-beta/monitoring"
ENV_DIR="/etc/greenvpn-paid-beta-monitoring"
BETA_ENV_FILE="/etc/bluevpn/paid-beta.env"
BETA_ADMIN_TOKEN_FILE="/opt/bluevpn-paid-beta/data/admin_token.txt"
SERVICE_NAME="greenvpn-paid-beta-service-probe"
BACKUP_ROOT="/root/greenvpn-paid-beta-backups"

usage() {
  cat <<'EOF'
Install isolated service and VPN endpoint monitoring for the paid beta contour.

Default mode is dry-run. The installer accepts only the two approved paid-beta
API routes and never edits the production probe, backend, DB, or downloads.

Usage:
  install_paid_beta_probe_systemd.sh \
    --role timeweb|ruvds \
    [--source-script PATH] [--interval SECONDS] [--apply]
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --apply)
      APPLY=1
      shift
      ;;
    --role)
      ROLE="${2:?missing role}"
      shift 2
      ;;
    --source-script)
      SOURCE_SCRIPT="${2:?missing source script}"
      shift 2
      ;;
    --interval)
      INTERVAL_SECONDS="${2:?missing interval}"
      shift 2
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

case "${ROLE}" in
  timeweb)
    API_BASE="https://api.greenvpn.pro/paid-beta-api"
    PROBE_ID="paid-beta-timeweb-msk"
    PROBE_REGION="timeweb-msk-beta"
    ;;
  ruvds)
    API_BASE="https://176-113-81-35.sslip.io/paid-beta-api"
    PROBE_ID="paid-beta-ruvds-msk"
    PROBE_REGION="ruvds-msk-beta"
    ;;
  *)
    echo "--role must be timeweb or ruvds" >&2
    exit 2
    ;;
esac

if [[ -z "${SOURCE_SCRIPT}" ]]; then
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  SOURCE_SCRIPT="${SCRIPT_DIR}/service_probe.py"
fi
if [[ ! -f "${SOURCE_SCRIPT}" ]]; then
  echo "service_probe.py not found: ${SOURCE_SCRIPT}" >&2
  exit 2
fi
if [[ ! "${INTERVAL_SECONDS}" =~ ^[0-9]+$ ]] || (( INTERVAL_SECONDS < 60 || INTERVAL_SECONDS > 3600 )); then
  echo "--interval must be 60..3600 seconds" >&2
  exit 2
fi

echo "Green VPN paid beta probe plan"
echo "mode=$([[ ${APPLY} -eq 1 ]] && echo apply || echo dry-run)"
echo "role=${ROLE}"
echo "api_base=${API_BASE}"
echo "probe_id=${PROBE_ID}"
echo "probe_region=${PROBE_REGION}"
echo "interval_seconds=${INTERVAL_SECONDS}"
echo "service=${SERVICE_NAME}.service"
echo "production_probe_changed=false"
echo "production_backend_changed=false"
echo "production_db_changed=false"

if [[ "${APPLY}" -ne 1 ]]; then
  exit 0
fi
if [[ "${EUID}" -ne 0 ]]; then
  echo "Run apply mode as root" >&2
  exit 1
fi
if [[ ! -f "${BETA_ENV_FILE}" ]]; then
  echo "Paid beta env is missing: ${BETA_ENV_FILE}" >&2
  exit 1
fi
if ! grep -Eq '^GREENVPN_PAID_BETA_ENABLED=("?1"?|"?true"?)$' "${BETA_ENV_FILE}"; then
  echo "Paid beta flag is not enabled in the isolated env" >&2
  exit 1
fi
if [[ ! -s "${BETA_ADMIN_TOKEN_FILE}" ]]; then
  echo "Paid beta admin token file is missing" >&2
  exit 1
fi
if [[ "$(stat -c '%a:%U:%G' -- "${BETA_ADMIN_TOKEN_FILE}")" != "600:root:root" ]]; then
  echo "Paid beta admin token file must be mode 600 and owned by root" >&2
  exit 1
fi
if ! systemctl is-active --quiet bluevpn-backend.service; then
  echo "Production backend is not active; refusing probe install" >&2
  exit 1
fi
if ! systemctl is-active --quiet greenvpn-paid-beta.service; then
  echo "Paid beta backend is not active" >&2
  exit 1
fi
curl -fsS --max-time 10 http://127.0.0.1:8000/healthz >/dev/null
curl -fsS --max-time 10 http://127.0.0.1:8010/healthz >/dev/null

timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
backup_dir="${BACKUP_ROOT}/${timestamp}-${ROLE}-paid-beta-probe"
install -d -m 700 "${backup_dir}"
managed_paths=(
  "/etc/systemd/system/${SERVICE_NAME}.service"
  "/etc/systemd/system/${SERVICE_NAME}.timer"
  "${ENV_DIR}/probe.env"
  "${INSTALL_DIR}/service_probe.py"
)
previous_timer_enabled="$(systemctl is-enabled "${SERVICE_NAME}.timer" 2>/dev/null || true)"
previous_timer_active="$(systemctl is-active "${SERVICE_NAME}.timer" 2>/dev/null || true)"
for path in "${managed_paths[@]}"; do
  if [[ -e "${path}" ]]; then
    cp -a "${path}" "${backup_dir}/"
  fi
done

restore_probe_install() {
  systemctl disable --now "${SERVICE_NAME}.timer" >/dev/null 2>&1 || true
  for path in "${managed_paths[@]}"; do
    backup_path="${backup_dir}/$(basename "${path}")"
    if [[ -e "${backup_path}" ]]; then
      cp -a "${backup_path}" "${path}"
    else
      rm -f -- "${path}"
    fi
  done
  systemctl daemon-reload
  if [[ "${previous_timer_enabled}" == "enabled" ]]; then
    systemctl enable "${SERVICE_NAME}.timer" >/dev/null
  fi
  if [[ "${previous_timer_active}" == "active" ]]; then
    systemctl start "${SERVICE_NAME}.timer"
  fi
}

install -d -m 755 "${INSTALL_DIR}"
install -d -m 700 "${ENV_DIR}"
install -m 755 "${SOURCE_SCRIPT}" "${INSTALL_DIR}/service_probe.py"
cat > "${ENV_DIR}/probe.env" <<EOF
GREENVPN_PAID_BETA_PROBE_API_BASE=${API_BASE}
GREENVPN_PAID_BETA_PROBE_ID=${PROBE_ID}
GREENVPN_PAID_BETA_PROBE_REGION=${PROBE_REGION}
EOF
chmod 600 "${ENV_DIR}/probe.env"

cat > "/etc/systemd/system/${SERVICE_NAME}.service" <<EOF
[Unit]
Description=Green VPN isolated paid beta service probe
Wants=network-online.target greenvpn-paid-beta.service
After=network-online.target greenvpn-paid-beta.service

[Service]
Type=oneshot
User=root
EnvironmentFile=${ENV_DIR}/probe.env
ExecStart=/usr/bin/env python3 ${INSTALL_DIR}/service_probe.py --api-base \${GREENVPN_PAID_BETA_PROBE_API_BASE} --admin-token-file ${BETA_ADMIN_TOKEN_FILE} --probe-id \${GREENVPN_PAID_BETA_PROBE_ID} --probe-region \${GREENVPN_PAID_BETA_PROBE_REGION} --server-health --route-health --fail-on-post-error
TimeoutStartSec=240
UMask=0077
PrivateTmp=true
NoNewPrivileges=true
ProtectSystem=strict
ProtectHome=true
ProtectKernelTunables=true
ProtectKernelModules=true
ProtectControlGroups=true
RestrictSUIDSGID=true
LockPersonality=true

[Install]
WantedBy=multi-user.target
EOF

cat > "/etc/systemd/system/${SERVICE_NAME}.timer" <<EOF
[Unit]
Description=Run Green VPN paid beta service probe every ${INTERVAL_SECONDS} seconds

[Timer]
OnBootSec=120s
OnUnitActiveSec=${INTERVAL_SECONDS}s
AccuracySec=15s
Unit=${SERVICE_NAME}.service
Persistent=false

[Install]
WantedBy=timers.target
EOF

systemctl daemon-reload
systemctl enable --now "${SERVICE_NAME}.timer"
if ! systemctl start "${SERVICE_NAME}.service"; then
  journalctl -u "${SERVICE_NAME}.service" -n 100 --no-pager >&2 || true
  restore_probe_install
  exit 1
fi

if ! curl -fsS --max-time 10 http://127.0.0.1:8010/healthz >/dev/null || \
   ! curl -fsS --max-time 10 http://127.0.0.1:8000/healthz >/dev/null; then
  restore_probe_install
  echo "Backend health failed after paid beta probe install; previous probe restored" >&2
  exit 1
fi

echo "paid_beta_probe=installed"
echo "paid_beta_probe_timer=$(systemctl is-active "${SERVICE_NAME}.timer")"
echo "paid_beta_backend=healthy"
echo "production_backend=healthy"
echo "backup_dir=${backup_dir}"
