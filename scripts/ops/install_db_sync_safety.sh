#!/usr/bin/env bash
set -euo pipefail

APPLY=0
START_TIMERS=0
ROLE=""
SOURCE_SCRIPT=""

PROD_SCRIPT="/usr/local/sbin/greenvpn_db_sync_from_peer.sh"
BETA_SCRIPT="/opt/bluevpn-paid-beta/current/ops/greenvpn_db_sync_from_peer.sh"
PROD_TIMER="/etc/systemd/system/greenvpn-db-sync.timer"
BETA_TIMER="/etc/systemd/system/greenvpn-paid-beta-db-sync.timer"
PROD_DROPIN="/etc/systemd/system/greenvpn-db-sync.service.d/10-storage-safety.conf"
BETA_DROPIN="/etc/systemd/system/greenvpn-paid-beta-db-sync.service.d/10-storage-safety.conf"

usage() {
  cat <<'EOF'
Install safe Green VPN bidirectional SQLite sync scheduling.

Usage:
  install_db_sync_safety.sh \
    --role timeweb|ruvds \
    --source-script PATH \
    [--start-timers] [--apply]

The default is a dry run. Apply mode serializes local production and paid-beta
sync, sets staggered ten-minute production and thirty-minute paid-beta
calendars, and adds a five-minute service timeout.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --role) ROLE="${2:?missing role}"; shift 2 ;;
    --source-script) SOURCE_SCRIPT="${2:?missing source script}"; shift 2 ;;
    --start-timers) START_TIMERS=1; shift ;;
    --apply) APPLY=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
done

case "$ROLE" in
  timeweb)
    PROD_CALENDAR="*-*-* *:00,10,20,30,40,50:00 UTC"
    BETA_CALENDAR="*-*-* *:02,32:00 UTC"
    ;;
  ruvds)
    PROD_CALENDAR="*-*-* *:05,15,25,35,45,55:00 UTC"
    BETA_CALENDAR="*-*-* *:17,47:00 UTC"
    ;;
  *)
    echo "--role must be timeweb or ruvds" >&2
    exit 2
    ;;
esac

[[ -f "$SOURCE_SCRIPT" && ! -L "$SOURCE_SCRIPT" ]] || {
  echo "Source sync script is missing or unsafe." >&2
  exit 2
}
for path in "$PROD_SCRIPT" "$BETA_SCRIPT" "$PROD_TIMER" "$BETA_TIMER"; do
  [[ -e "$path" ]] || {
    echo "Required live sync path is missing: $path" >&2
    exit 2
  }
done
bash -n "$SOURCE_SCRIPT"

echo "mode=$([[ $APPLY -eq 1 ]] && echo apply || echo dry-run)"
echo "role=$ROLE"
echo "source_script_sha256=$(sha256sum "$SOURCE_SCRIPT" | awk '{print $1}')"
echo "production_interval=10min"
echo "paid_beta_interval=30min"
echo "production_calendar=$PROD_CALENDAR"
echo "paid_beta_calendar=$BETA_CALENDAR"

[[ $APPLY -eq 1 ]] || exit 0
[[ $EUID -eq 0 ]] || { echo "Run apply mode as root." >&2; exit 1; }

timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
backup_dir="/root/greenvpn-db-sync-safety-backups/${timestamp}"
install -d -m 700 "$backup_dir"

backup_path() {
  local path="$1"
  local name="$2"
  if [[ -e "$path" ]]; then
    cp -a -- "$path" "$backup_dir/$name"
  else
    touch "$backup_dir/$name.absent"
  fi
}

restore_path() {
  local path="$1"
  local name="$2"
  if [[ -e "$backup_dir/$name" ]]; then
    install -d -m 755 "$(dirname "$path")"
    cp -a -- "$backup_dir/$name" "$path"
  else
    rm -f -- "$path"
  fi
}

backup_path "$PROD_SCRIPT" "production-sync-script"
backup_path "$BETA_SCRIPT" "paid-beta-sync-script"
backup_path "$PROD_TIMER" "production-sync.timer"
backup_path "$BETA_TIMER" "paid-beta-sync.timer"
backup_path "$PROD_DROPIN" "production-sync-safety.conf"
backup_path "$BETA_DROPIN" "paid-beta-sync-safety.conf"
chmod -R go-rwx "$backup_dir"

rollback() {
  code=$?
  trap - ERR
  systemctl stop greenvpn-db-sync.timer greenvpn-paid-beta-db-sync.timer >/dev/null 2>&1 || true
  restore_path "$PROD_SCRIPT" "production-sync-script"
  restore_path "$BETA_SCRIPT" "paid-beta-sync-script"
  restore_path "$PROD_TIMER" "production-sync.timer"
  restore_path "$BETA_TIMER" "paid-beta-sync.timer"
  restore_path "$PROD_DROPIN" "production-sync-safety.conf"
  restore_path "$BETA_DROPIN" "paid-beta-sync-safety.conf"
  systemctl daemon-reload >/dev/null 2>&1 || true
  exit "$code"
}
trap rollback ERR

systemctl stop greenvpn-db-sync.timer greenvpn-paid-beta-db-sync.timer
timeout 30s systemctl stop greenvpn-db-sync.service greenvpn-paid-beta-db-sync.service || true

install -m 755 "$SOURCE_SCRIPT" "$PROD_SCRIPT"
install -m 755 "$SOURCE_SCRIPT" "$BETA_SCRIPT"

cat >"$PROD_TIMER" <<EOF
[Unit]
Description=Run staggered Green VPN SQLite state sync every ten minutes

[Timer]
OnCalendar=${PROD_CALENDAR}
AccuracySec=1s
Unit=greenvpn-db-sync.service
Persistent=false

[Install]
WantedBy=timers.target
EOF

cat >"$BETA_TIMER" <<EOF
[Unit]
Description=Run staggered Green VPN paid beta DB sync every thirty minutes

[Timer]
OnCalendar=${BETA_CALENDAR}
AccuracySec=1s
Unit=greenvpn-paid-beta-db-sync.service
Persistent=false

[Install]
WantedBy=timers.target
EOF

install -d -m 755 "$(dirname "$PROD_DROPIN")" "$(dirname "$BETA_DROPIN")"
cat >"$PROD_DROPIN" <<'EOF'
[Service]
TimeoutStartSec=5min
EOF
cat >"$BETA_DROPIN" <<'EOF'
[Service]
TimeoutStartSec=5min
EOF
chmod 644 "$PROD_TIMER" "$BETA_TIMER" "$PROD_DROPIN" "$BETA_DROPIN"

systemd-analyze verify "$PROD_TIMER" "$BETA_TIMER"
systemctl daemon-reload
systemctl reset-failed greenvpn-db-sync.service greenvpn-paid-beta-db-sync.service
systemctl enable greenvpn-db-sync.timer greenvpn-paid-beta-db-sync.timer
if [[ $START_TIMERS -eq 1 ]]; then
  systemctl start greenvpn-db-sync.timer greenvpn-paid-beta-db-sync.timer
fi

trap - ERR
echo "sync_safety_status=ok"
echo "production_timer=$(systemctl is-active greenvpn-db-sync.timer)"
echo "paid_beta_timer=$(systemctl is-active greenvpn-paid-beta-db-sync.timer)"
echo "backup_dir=$backup_dir"
