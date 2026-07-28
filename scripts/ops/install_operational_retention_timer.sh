#!/usr/bin/env bash
set -euo pipefail

APPLY=0
SOURCE_SCRIPT=""
INSTALL_SCRIPT="/usr/local/sbin/greenvpn_prune_operational_history.py"
SERVICE_UNIT="/etc/systemd/system/greenvpn-operational-retention.service"
TIMER_UNIT="/etc/systemd/system/greenvpn-operational-retention.timer"

usage() {
  cat <<'EOF'
Install the bounded Green VPN operational-history retention timer.

Usage:
  install_operational_retention_timer.sh --source-script PATH [--apply]

The default is a dry run. Apply mode installs a hardened six-hour timer and runs
one retention pass for production and paid-beta SQLite databases. It never
touches account, subscription, payment, support-report, or catalog records.
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

[[ -f "$SOURCE_SCRIPT" && ! -L "$SOURCE_SCRIPT" ]] || {
  echo "Source retention script is missing or unsafe." >&2
  exit 2
}
python3 -m py_compile "$SOURCE_SCRIPT"

echo "mode=$([[ $APPLY -eq 1 ]] && echo apply || echo dry-run)"
echo "source_script_sha256=$(sha256sum "$SOURCE_SCRIPT" | awk '{print $1}')"
echo "production_db=/opt/bluevpn/backend/data/bluevpn.db"
echo "paid_beta_db=/opt/bluevpn-paid-beta/data/bluevpn.db"

[[ $APPLY -eq 1 ]] || exit 0
[[ $EUID -eq 0 ]] || { echo "Run apply mode as root." >&2; exit 1; }
for path in \
  /opt/bluevpn/backend/data/bluevpn.db \
  /opt/bluevpn-paid-beta/data/bluevpn.db; do
  [[ -f "$path" && ! -L "$path" ]] || {
    echo "Required database is missing or unsafe: $path" >&2
    exit 2
  }
done

timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
backup_dir="/root/greenvpn-operational-retention-backups/${timestamp}"
install -d -m 700 "$backup_dir"
for path in "$INSTALL_SCRIPT" "$SERVICE_UNIT" "$TIMER_UNIT"; do
  if [[ -e "$path" ]]; then
    cp -a -- "$path" "$backup_dir/$(basename "$path")"
  else
    touch "$backup_dir/$(basename "$path").absent"
  fi
done
chmod 600 "$backup_dir"/*

rollback() {
  code=$?
  trap - ERR
  systemctl disable --now greenvpn-operational-retention.timer >/dev/null 2>&1 || true
  for path in "$INSTALL_SCRIPT" "$SERVICE_UNIT" "$TIMER_UNIT"; do
    name="$(basename "$path")"
    if [[ -f "$backup_dir/$name" ]]; then
      cp -a -- "$backup_dir/$name" "$path"
    else
      rm -f -- "$path"
    fi
  done
  systemctl daemon-reload >/dev/null 2>&1 || true
  if [[ -f "$TIMER_UNIT" ]]; then
    systemctl enable --now greenvpn-operational-retention.timer >/dev/null 2>&1 || true
  fi
  exit "$code"
}
trap rollback ERR

install -m 755 "$SOURCE_SCRIPT" "$INSTALL_SCRIPT"
cat >"$SERVICE_UNIT" <<'EOF'
[Unit]
Description=Green VPN bounded operational-history retention
After=local-fs.target

[Service]
Type=oneshot
ExecStart=/usr/bin/python3 /usr/local/sbin/greenvpn_prune_operational_history.py --db /opt/bluevpn/backend/data/bluevpn.db --db /opt/bluevpn-paid-beta/data/bluevpn.db --apply
User=root
Nice=10
IOSchedulingClass=idle
PrivateTmp=true
PrivateDevices=true
ProtectHome=true
ProtectSystem=strict
ReadWritePaths=/opt/bluevpn/backend/data /opt/bluevpn-paid-beta/data
NoNewPrivileges=true
LockPersonality=true
MemoryDenyWriteExecute=true
RestrictSUIDSGID=true
EOF
cat >"$TIMER_UNIT" <<'EOF'
[Unit]
Description=Run Green VPN operational-history retention every six hours

[Timer]
OnCalendar=*-*-* 01:20:00 UTC
OnCalendar=*-*-* 07:20:00 UTC
OnCalendar=*-*-* 13:20:00 UTC
OnCalendar=*-*-* 19:20:00 UTC
RandomizedDelaySec=20m
Persistent=true
Unit=greenvpn-operational-retention.service

[Install]
WantedBy=timers.target
EOF
chmod 644 "$SERVICE_UNIT" "$TIMER_UNIT"
systemctl daemon-reload
systemctl enable --now greenvpn-operational-retention.timer
systemctl start greenvpn-operational-retention.service
systemctl is-active --quiet greenvpn-operational-retention.timer

trap - ERR
echo "retention_status=ok"
echo "timer_status=$(systemctl is-active greenvpn-operational-retention.timer)"
echo "backup_dir=$backup_dir"
