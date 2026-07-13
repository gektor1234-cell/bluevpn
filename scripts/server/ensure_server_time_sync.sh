#!/usr/bin/env bash
set -euo pipefail

EXPECTED_HOSTNAME=""
MODE="slew"
APPLY=0
ALLOW_CLOCK_STEP=0
STATEFUL_SERVICES_STOPPED=0
TIME_SOURCE="https://www.cloudflare.com/cdn-cgi/trace"

usage() {
  cat <<'USAGE'
Guard and configure Green VPN server time synchronization.

  ensure_server_time_sync.sh --expected-hostname HOST [--mode slew|step]
      [--allow-clock-step --stateful-services-stopped] [--apply]

Dry-run is the default. Slew mode disables chrony's makestep directive and
uses the maximum supported slew rate so wall time never moves backwards. Step
mode is refused unless both explicit safety flags are present; the orchestrator
must back up databases and stop stateful services first. The script never
reboots a server and never edits application or VPN configuration.
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --expected-hostname) EXPECTED_HOSTNAME="${2:?missing hostname}"; shift 2 ;;
    --mode) MODE="${2:?missing mode}"; shift 2 ;;
    --allow-clock-step) ALLOW_CLOCK_STEP=1; shift ;;
    --stateful-services-stopped) STATEFUL_SERVICES_STOPPED=1; shift ;;
    --apply) APPLY=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
done

[[ "${EUID}" -eq 0 ]] || { echo "Run as root." >&2; exit 1; }
[[ "${EXPECTED_HOSTNAME}" =~ ^[a-zA-Z0-9._-]{1,120}$ ]] || {
  echo "A valid --expected-hostname is required." >&2
  exit 2
}
[[ "$(hostname -s)" == "${EXPECTED_HOSTNAME}" ]] || { echo "Host guard failed." >&2; exit 1; }
[[ "${MODE}" == slew || "${MODE}" == step ]] || { echo "--mode must be slew or step" >&2; exit 2; }
if [[ "${MODE}" == step && ("${ALLOW_CLOCK_STEP}" -ne 1 || "${STATEFUL_SERVICES_STOPPED}" -ne 1) ]]; then
  echo "Step mode requires --allow-clock-step and --stateful-services-stopped." >&2
  exit 2
fi
for command in apt-get awk curl date hostname install systemctl; do
  command -v "${command}" >/dev/null 2>&1 || {
    echo "Required command missing: ${command}" >&2
    exit 1
  }
done

external_epoch() {
  local header
  header="$(curl -sSI --max-time 15 "${TIME_SOURCE}" | awk 'BEGIN {IGNORECASE=1} /^date:/ {sub(/^[^:]+:[[:space:]]*/, ""); sub(/\r$/, ""); print; exit}')"
  [[ -n "${header}" ]] || return 1
  date -u -d "${header}" +%s
}

offset_seconds() {
  local external local_epoch
  external="$(external_epoch)"
  local_epoch="$(date -u +%s)"
  echo "$((local_epoch - external))"
}

OFFSET_BEFORE="$(offset_seconds)"
echo "time_sync_host=$(hostname -s)"
echo "time_sync_mode=${MODE}"
echo "time_sync_apply=${APPLY}"
echo "time_sync_offset_before_seconds=${OFFSET_BEFORE}"
if command -v chronyc >/dev/null 2>&1; then
  echo "time_sync_provider_before=chrony"
elif systemctl list-unit-files systemd-timesyncd.service --no-legend 2>/dev/null | grep -q .; then
  echo "time_sync_provider_before=systemd-timesyncd"
else
  echo "time_sync_provider_before=none"
fi
[[ "${APPLY}" -eq 1 ]] || exit 0

export DEBIAN_FRONTEND=noninteractive
umask 077
STAMP="$(date -u +%Y%m%dT%H%M%SZ)"
BACKUP_ROOT="/root/greenvpn-time-sync-backups/${STAMP}"
install -d -m 0700 "${BACKUP_ROOT}"

if ! command -v chronyc >/dev/null 2>&1; then
  if [[ "${MODE}" == slew ]]; then
    systemctl mask chrony.service >/dev/null 2>&1 || true
  fi
  apt-get update
  apt-get install -y --no-install-recommends chrony
fi

CHRONY_CONFIG="/etc/chrony/chrony.conf"
[[ -f "${CHRONY_CONFIG}" && ! -L "${CHRONY_CONFIG}" ]] || {
  echo "Chrony config is missing or unsafe." >&2
  exit 1
}
cp -a -- "${CHRONY_CONFIG}" "${BACKUP_ROOT}/chrony.conf"

if [[ "${MODE}" == slew ]]; then
  systemctl stop chrony.service >/dev/null 2>&1 || true
  TEMP_CONFIG="$(mktemp /etc/chrony/chrony.conf.greenvpn.XXXXXX)"
  awk '
    /^[[:space:]]*makestep[[:space:]]/ {
      print "# Green VPN slew-only: " $0
      next
    }
    /^[[:space:]]*maxslewrate[[:space:]]/ {
      print "# Green VPN replaced: " $0
      next
    }
    { print }
    END { print "maxslewrate 100000" }
  ' "${CHRONY_CONFIG}" >"${TEMP_CONFIG}"
  chown root:root "${TEMP_CONFIG}"
  chmod 0644 "${TEMP_CONFIG}"
  mv -f -- "${TEMP_CONFIG}" "${CHRONY_CONFIG}"
fi

systemctl unmask chrony.service >/dev/null 2>&1 || true
systemctl enable --now chrony.service
if [[ "${MODE}" == step ]]; then
  chronyc makestep
  chronyc waitsync 30 1
fi
sleep 3
systemctl is-active --quiet chrony.service
chronyc tracking
OFFSET_AFTER="$(offset_seconds)"
echo "time_sync_status=active"
echo "time_sync_backup=${BACKUP_ROOT}"
echo "time_sync_offset_after_seconds=${OFFSET_AFTER}"
echo "time_sync_clock_step_allowed=${ALLOW_CLOCK_STEP}"
echo "time_sync_application_files_changed=false"
echo "time_sync_vpn_files_changed=false"
