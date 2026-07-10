#!/usr/bin/env bash
set -euo pipefail

systemctl stop bluevpn-backend.service >/dev/null 2>&1 || true
cd /opt/bluevpn/backend/data
timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
for file in bluevpn.db-wal bluevpn.db-shm; do
  if [[ -e "$file" ]]; then
    mv "$file" "${file}.stale_after_recovery_${timestamp}"
    echo "moved=${file}"
  fi
done
python3 -c 'import sqlite3; con=sqlite3.connect("/opt/bluevpn/backend/data/bluevpn.db"); print(con.execute("pragma quick_check").fetchall())'
systemctl start bluevpn-backend.service >/dev/null 2>&1 || true
systemctl start greenvpn-vpn-capacity-report.timer greenvpn-service-probe.timer >/dev/null 2>&1 || true
systemctl is-active bluevpn-backend.service
