#!/usr/bin/env bash
set -euo pipefail

EXPECTED_HOSTNAME=""
APPLY=0
UPGRADE_PACKAGES=0
CONFIGURE_TIME_SYNC=0

usage() {
  cat <<'USAGE'
Install the Green VPN operating-system maintenance baseline.

  apply_server_os_baseline.sh --expected-hostname HOST [--upgrade-packages]
      [--configure-time-sync] [--apply]

Dry-run is the default. Apply installs/configures unattended-upgrades and an
sshd-only fail2ban jail, applies journald retention limits, and optionally
installs currently available package upgrades. Time synchronization is always
audited; --configure-time-sync installs/enables a provider and must be used in
a maintenance window because correcting a large offset can step the clock. The
script never reboots the server.
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --expected-hostname) EXPECTED_HOSTNAME="${2:?missing hostname}"; shift 2 ;;
    --upgrade-packages) UPGRADE_PACKAGES=1; shift ;;
    --configure-time-sync) CONFIGURE_TIME_SYNC=1; shift ;;
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
[[ "$(hostname -s)" == "${EXPECTED_HOSTNAME}" ]] || {
  echo "Host guard failed." >&2
  exit 1
}
for command in apt-get dpkg-query hostname install systemctl; do
  command -v "${command}" >/dev/null 2>&1 || {
    echo "Required command missing: ${command}" >&2
    exit 1
  }
done

time_sync_provider() {
  if command -v chronyc >/dev/null 2>&1; then
    echo chrony
  elif systemctl list-unit-files systemd-timesyncd.service --no-legend 2>/dev/null | grep -q .; then
    echo systemd-timesyncd
  else
    echo none
  fi
}

time_sync_synchronized() {
  local provider="$1"
  case "${provider}" in
    chrony)
      systemctl is-active --quiet chrony.service \
        && chronyc tracking 2>/dev/null | grep -Eq '^Leap status[[:space:]]*:[[:space:]]*Normal$' \
        && chronyc tracking 2>/dev/null | awk '
          /^System time[[:space:]]*:/ {
            offset = $4 + 0
            if (offset < 0) offset = -offset
            found = 1
            ok = (offset <= 5)
          }
          END { exit !(found && ok) }
        '
      ;;
    systemd-timesyncd)
      systemctl is-active --quiet systemd-timesyncd.service \
        && command -v timedatectl >/dev/null 2>&1 \
        && [[ "$(timedatectl show --property=NTPSynchronized --value 2>/dev/null || true)" == yes ]]
      ;;
    *) return 1 ;;
  esac
}

time_sync_offset_seconds() {
  local provider="$1"
  case "${provider}" in
    chrony)
      chronyc tracking 2>/dev/null | awk '/^System time[[:space:]]*:/ {print $4; found=1} END {if (!found) print "unknown"}'
      ;;
    systemd-timesyncd)
      if command -v timedatectl >/dev/null 2>&1; then
        timedatectl timesync-status 2>/dev/null | awk '/Offset:/ {print $2; found=1} END {if (!found) print "unknown"}'
      else
        echo unknown
      fi
      ;;
    *) echo unknown ;;
  esac
}

PENDING_BEFORE="$(apt list --upgradable 2>/dev/null | tail -n +2 | grep -c . || true)"
NTP_PROVIDER_BEFORE="$(time_sync_provider)"
echo "os_baseline_host=$(hostname -s)"
echo "os_baseline_apply=${APPLY}"
echo "os_baseline_upgrade_packages=${UPGRADE_PACKAGES}"
echo "os_baseline_configure_time_sync=${CONFIGURE_TIME_SYNC}"
echo "os_baseline_ntp_provider_before=${NTP_PROVIDER_BEFORE}"
echo "os_baseline_ntp_offset_before=$(time_sync_offset_seconds "${NTP_PROVIDER_BEFORE}")"
if time_sync_synchronized "${NTP_PROVIDER_BEFORE}"; then
  echo "os_baseline_ntp_synchronized_before=true"
else
  echo "os_baseline_ntp_synchronized_before=false"
fi
echo "os_baseline_pending_before=${PENDING_BEFORE}"
[[ "${APPLY}" -eq 1 ]] || exit 0

export DEBIAN_FRONTEND=noninteractive
umask 077
STAMP="$(date -u +%Y%m%dT%H%M%SZ)"
BACKUP_ROOT="/root/greenvpn-os-baseline-backups/${STAMP}"
install -d -m 0700 "${BACKUP_ROOT}"

backup_if_present() {
  local path="$1"
  if [[ -e "${path}" && ! -L "${path}" ]]; then
    cp -a -- "${path}" "${BACKUP_ROOT}/$(basename "${path}")"
  fi
}

AUTO_CONFIG="/etc/apt/apt.conf.d/20auto-upgrades"
FAIL2BAN_CONFIG="/etc/fail2ban/jail.d/greenvpn-sshd.local"
JOURNAL_CONFIG="/etc/systemd/journald.conf.d/greenvpn-limits.conf"
backup_if_present "${AUTO_CONFIG}"
backup_if_present "${FAIL2BAN_CONFIG}"
backup_if_present "${JOURNAL_CONFIG}"

install -d -m 0755 /etc/fail2ban/jail.d /etc/systemd/journald.conf.d
cat >"${AUTO_CONFIG}" <<'EOF'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
APT::Periodic::AutocleanInterval "7";
EOF
chmod 0644 "${AUTO_CONFIG}"

cat >"${FAIL2BAN_CONFIG}" <<'EOF'
[sshd]
enabled = true
backend = systemd
mode = normal
maxretry = 5
findtime = 10m
bantime = 1h
EOF
chmod 0644 "${FAIL2BAN_CONFIG}"

cat >"${JOURNAL_CONFIG}" <<'EOF'
[Journal]
SystemMaxUse=500M
RuntimeMaxUse=100M
MaxRetentionSec=14day
RateLimitIntervalSec=30s
RateLimitBurst=10000
EOF
chmod 0644 "${JOURNAL_CONFIG}"

apt-get update
apt-get install -y --no-install-recommends \
  unattended-upgrades fail2ban python3-systemd

if [[ "${CONFIGURE_TIME_SYNC}" -eq 1 ]]; then
  NTP_PROVIDER="$(time_sync_provider)"
  if [[ "${NTP_PROVIDER}" == none ]]; then
    apt-get install -y --no-install-recommends chrony
    NTP_PROVIDER=chrony
  fi
  case "${NTP_PROVIDER}" in
    chrony) systemctl enable --now chrony.service ;;
    systemd-timesyncd)
      timedatectl set-ntp true
      systemctl enable --now systemd-timesyncd.service
      ;;
  esac
fi

fail2ban-client -t
systemctl enable --now unattended-upgrades.service
systemctl enable --now fail2ban.service
systemctl restart systemd-journald.service

if [[ "${UPGRADE_PACKAGES}" -eq 1 ]]; then
  apt-get -y -o Dpkg::Options::=--force-confold upgrade
  apt-get clean
fi

systemctl is-active --quiet unattended-upgrades.service
systemctl is-active --quiet fail2ban.service
fail2ban-client status sshd >/dev/null
PENDING_AFTER="$(apt list --upgradable 2>/dev/null | tail -n +2 | grep -c . || true)"

echo "os_baseline_status=applied"
echo "os_baseline_backup=${BACKUP_ROOT}"
echo "os_baseline_pending_after=${PENDING_AFTER}"
NTP_PROVIDER_AFTER="$(time_sync_provider)"
echo "os_baseline_ntp_provider_after=${NTP_PROVIDER_AFTER}"
echo "os_baseline_ntp_offset_after=$(time_sync_offset_seconds "${NTP_PROVIDER_AFTER}")"
if time_sync_synchronized "${NTP_PROVIDER_AFTER}"; then
  echo "os_baseline_ntp_synchronized_after=true"
else
  echo "os_baseline_ntp_synchronized_after=false"
fi
if [[ -f /var/run/reboot-required ]]; then
  echo "os_baseline_reboot_required=true"
else
  echo "os_baseline_reboot_required=false"
fi
