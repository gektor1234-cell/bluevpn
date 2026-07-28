#!/usr/bin/env bash
set -euo pipefail

APPLY=0
EXPECTED_HOST="5.129.216.42"
SOURCE_SCRIPT=""
INSTALL_SCRIPT="/usr/local/sbin/greenvpn_sync_naive_certificate.sh"
SERVICE_UNIT="/etc/systemd/system/greenvpn-naive-certificate-sync.service"
TIMER_UNIT="/etc/systemd/system/greenvpn-naive-certificate-sync.timer"
BACKUP_ROOT="/root/greenvpn-naive-certificate-sync-backups"

usage() {
  cat <<'EOF'
Install the guarded NL2 Hysteria-to-Naive certificate synchronization timer.

Usage:
  install_naive_certificate_sync.sh --source-script PATH [--apply]

Default mode validates the exact host and source script without changing the
server. Apply mode backs up any prior files and rolls back automatically.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --source-script) SOURCE_SCRIPT="${2:?missing source script}"; shift 2 ;;
    --apply) APPLY=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
done

[[ "${EUID}" -eq 0 ]] || { echo "Run as root on NL2." >&2; exit 1; }
[[ -n "${SOURCE_SCRIPT}" && -f "${SOURCE_SCRIPT}" && ! -L "${SOURCE_SCRIPT}" ]] || {
  echo "A regular --source-script is required." >&2
  exit 1
}
bash -n "${SOURCE_SCRIPT}"
PUBLIC_IP="$(curl -4fsS --max-time 5 https://api.ipify.org || true)"
[[ "${PUBLIC_IP}" == "${EXPECTED_HOST}" ]] || {
  echo "Exact NL2 host guard failed." >&2
  exit 1
}
bash "${SOURCE_SCRIPT}"

echo "host_guard=passed"
echo "source_script_valid=true"
echo "apply=${APPLY}"
if [[ "${APPLY}" -ne 1 ]]; then
  echo "status=dry-run"
  exit 0
fi

timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
backup_dir="${BACKUP_ROOT}/${timestamp}"
install -d -m 0700 "${BACKUP_ROOT}"
[[ ! -e "${backup_dir}" ]] || {
  echo "Backup directory already exists." >&2
  exit 1
}
install -d -m 0700 "${backup_dir}"
for path in "${INSTALL_SCRIPT}" "${SERVICE_UNIT}" "${TIMER_UNIT}"; do
  if [[ -e "${path}" ]]; then
    [[ -f "${path}" && ! -L "${path}" ]] || {
      echo "Existing managed path is unsafe: ${path}" >&2
      exit 1
    }
    install -m 0600 "${path}" "${backup_dir}/$(basename "${path}")"
  fi
done
systemctl is-enabled greenvpn-naive-certificate-sync.timer \
  >"${backup_dir}/timer-enabled" 2>/dev/null || true
systemctl is-active greenvpn-naive-certificate-sync.timer \
  >"${backup_dir}/timer-active" 2>/dev/null || true
chmod 0600 "${backup_dir}/timer-enabled" "${backup_dir}/timer-active"

rollback_on_error() {
  local exit_code=$?
  trap - ERR
  systemctl disable --now greenvpn-naive-certificate-sync.timer \
    >/dev/null 2>&1 || true
  rm -f -- "${INSTALL_SCRIPT}" "${SERVICE_UNIT}" "${TIMER_UNIT}"
  for path in "${INSTALL_SCRIPT}" "${SERVICE_UNIT}" "${TIMER_UNIT}"; do
    local backup_path="${backup_dir}/$(basename "${path}")"
    if [[ -f "${backup_path}" ]]; then
      install -m 0755 "${backup_path}" "${path}" || true
    fi
  done
  [[ ! -f "${backup_dir}/greenvpn-naive-certificate-sync.service" ]] || \
    chmod 0644 "${SERVICE_UNIT}" || true
  [[ ! -f "${backup_dir}/greenvpn-naive-certificate-sync.timer" ]] || \
    chmod 0644 "${TIMER_UNIT}" || true
  systemctl daemon-reload >/dev/null 2>&1 || true
  if grep -qxF enabled "${backup_dir}/timer-enabled" 2>/dev/null; then
    systemctl enable greenvpn-naive-certificate-sync.timer \
      >/dev/null 2>&1 || true
  fi
  if grep -qxF active "${backup_dir}/timer-active" 2>/dev/null; then
    systemctl start greenvpn-naive-certificate-sync.timer \
      >/dev/null 2>&1 || true
  fi
  echo "rollback=restored" >&2
  exit "${exit_code}"
}
trap rollback_on_error ERR

install -m 0755 "${SOURCE_SCRIPT}" "${INSTALL_SCRIPT}"
cat >"${SERVICE_UNIT}.tmp" <<'UNIT'
[Unit]
Description=Green VPN guarded Naive certificate synchronization
After=network-online.target greenvpn-hysteria2-canary.service
Wants=network-online.target
Requires=greenvpn-hysteria2-canary.service

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/greenvpn_sync_naive_certificate.sh --apply
User=root
Group=root
NoNewPrivileges=true
PrivateTmp=true
ProtectHome=true
ProtectSystem=strict
ReadWritePaths=/etc/greenvpn-naive-https-canary /var/lib/greenvpn-naive-cert-sync
LockPersonality=true
MemoryDenyWriteExecute=true
RestrictRealtime=true
UNIT
chmod 0644 "${SERVICE_UNIT}.tmp"
mv -f -- "${SERVICE_UNIT}.tmp" "${SERVICE_UNIT}"

cat >"${TIMER_UNIT}.tmp" <<'UNIT'
[Unit]
Description=Check Green VPN Naive certificate synchronization every 15 minutes

[Timer]
OnBootSec=5min
OnUnitActiveSec=15min
RandomizedDelaySec=2min
Persistent=true
Unit=greenvpn-naive-certificate-sync.service

[Install]
WantedBy=timers.target
UNIT
chmod 0644 "${TIMER_UNIT}.tmp"
mv -f -- "${TIMER_UNIT}.tmp" "${TIMER_UNIT}"

systemctl daemon-reload
systemctl enable --now greenvpn-naive-certificate-sync.timer
systemctl start greenvpn-naive-certificate-sync.service
systemctl is-active --quiet greenvpn-naive-certificate-sync.timer
systemctl is-enabled --quiet greenvpn-naive-certificate-sync.timer
systemctl is-active --quiet greenvpn-naive-https-canary.service

trap - ERR
echo "status=applied"
echo "timer_active=true"
echo "timer_enabled=true"
echo "naive_service_active=true"
echo "backup_dir=${backup_dir}"
echo "rollback=not_needed"
