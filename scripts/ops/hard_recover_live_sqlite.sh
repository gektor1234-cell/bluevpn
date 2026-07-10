#!/usr/bin/env bash
set -euo pipefail

DB_DIR="/opt/bluevpn/backend/data"
DB="${DB_DIR}/bluevpn.db"
BACKUP_DIR="/root/greenvpn-db-backups"
RECOVER="/tmp/recover_live_sqlite.py"
CHECK="/tmp/check_live_sqlite_tables.py"
STAMP="$(date -u +%Y%m%dT%H%M%SZ)"

mkdir -p "$BACKUP_DIR"

echo "stopping_backend"
systemctl stop bluevpn-backend.service || true
systemctl stop greenvpn-vpn-capacity-report.timer greenvpn-service-probe.timer || true
systemctl stop greenvpn-vpn-capacity-report.service greenvpn-service-probe.service || true

for _ in 1 2 3 4 5; do
  if ! pgrep -f 'uvicorn app.main:app' >/dev/null 2>&1; then
    break
  fi
  sleep 1
done

if pgrep -f 'uvicorn app.main:app' >/dev/null 2>&1; then
  echo "stopping_lingering_uvicorn"
  pkill -TERM -f 'uvicorn app.main:app' || true
  sleep 2
fi

if pgrep -f 'uvicorn app.main:app' >/dev/null 2>&1; then
  echo "killing_lingering_uvicorn"
  pkill -KILL -f 'uvicorn app.main:app' || true
  sleep 1
fi

echo "moving_sidecars_before_recovery"
for suffix in "-wal" "-shm"; do
  sidecar="${DB}${suffix}"
  if [ -e "$sidecar" ]; then
    mv "$sidecar" "${BACKUP_DIR}/bluevpn.db${suffix}.hard_stop_${STAMP}"
  fi
done

echo "running_recovery"
python3 "$RECOVER"

sync
echo "post_recovery_files"
ls -lh "$DB" "${DB}"-* 2>/dev/null || true

echo "post_recovery_tables"
python3 "$CHECK"

echo "starting_backend"
systemctl start bluevpn-backend.service
systemctl start greenvpn-vpn-capacity-report.timer greenvpn-service-probe.timer || true

sleep 2
echo "backend_status"
systemctl is-active bluevpn-backend.service
systemctl show bluevpn-backend.service -p MainPID --value

echo "post_start_tables"
python3 "$CHECK"

echo "hard_recovery_done"
