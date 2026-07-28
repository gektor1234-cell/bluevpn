#!/usr/bin/env bash
set -euo pipefail

APPLY=0
SOURCE_SCRIPT=""
INSTALL_SCRIPT="/usr/local/sbin/greenvpn_prune_release_backups.py"
SERVICE_UNIT="/etc/systemd/system/greenvpn-release-backup-retention.service"
TIMER_UNIT="/etc/systemd/system/greenvpn-release-backup-retention.timer"

usage() {
  cat <<'EOF'
Install bounded retention for Green VPN release rollback directories.

Usage:
  install_release_backup_retention_timer.sh --source-script PATH [--apply]

The default is a dry run. Apply mode keeps the four newest rollback
directories in each explicitly allowlisted release-backup root.
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
  echo "Source backup-retention script is missing or unsafe." >&2
  exit 2
}
python3 -m py_compile "$SOURCE_SCRIPT"

echo "mode=$([[ $APPLY -eq 1 ]] && echo apply || echo dry-run)"
echo "source_script_sha256=$(sha256sum "$SOURCE_SCRIPT" | awk '{print $1}')"

[[ $APPLY -eq 1 ]] || exit 0
[[ $EUID -eq 0 ]] || { echo "Run apply mode as root." >&2; exit 1; }

timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
backup_dir="/root/greenvpn-release-backup-retention-backups/${timestamp}"
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
  systemctl disable --now greenvpn-release-backup-retention.timer >/dev/null 2>&1 || true
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
    systemctl enable --now greenvpn-release-backup-retention.timer >/dev/null 2>&1 || true
  fi
  exit "$code"
}
trap rollback ERR

install -m 755 "$SOURCE_SCRIPT" "$INSTALL_SCRIPT"
cat >"$SERVICE_UNIT" <<'EOF'
[Unit]
Description=Green VPN bounded release-backup retention
After=local-fs.target

[Service]
Type=oneshot
ExecStart=/usr/bin/python3 /usr/local/sbin/greenvpn_prune_release_backups.py --apply --keep 4
User=root
Nice=10
IOSchedulingClass=idle
PrivateTmp=true
PrivateDevices=true
ProtectSystem=strict
ProtectHome=read-only
ReadWritePaths=-/root/greenvpn-paid-beta-backend-backups
ReadWritePaths=-/root/greenvpn-paid-beta-client-release-backups
ReadWritePaths=-/root/greenvpn-paid-beta-backups
ReadWritePaths=-/root/greenvpn-apk-release-backups
ReadWritePaths=-/root/greenvpn-windows-release-backups
ReadWritePaths=-/root/greenvpn-public-product-backups
ReadWritePaths=-/root/greenvpn-main-site-backups
ReadWritePaths=-/root/greenvpn-admin-static-backups
ReadWritePaths=-/root/greenvpn-release-rollback-backups
NoNewPrivileges=true
LockPersonality=true
MemoryDenyWriteExecute=true
RestrictSUIDSGID=true
EOF
cat >"$TIMER_UNIT" <<'EOF'
[Unit]
Description=Run Green VPN release-backup retention daily

[Timer]
OnCalendar=*-*-* 04:20:00 UTC
RandomizedDelaySec=20m
Persistent=true
Unit=greenvpn-release-backup-retention.service

[Install]
WantedBy=timers.target
EOF
chmod 644 "$SERVICE_UNIT" "$TIMER_UNIT"
systemd-analyze verify "$SERVICE_UNIT" "$TIMER_UNIT"
systemctl daemon-reload
systemctl enable --now greenvpn-release-backup-retention.timer
systemctl start greenvpn-release-backup-retention.service
systemctl is-active --quiet greenvpn-release-backup-retention.timer

trap - ERR
echo "retention_status=ok"
echo "timer_status=$(systemctl is-active greenvpn-release-backup-retention.timer)"
echo "backup_dir=$backup_dir"
