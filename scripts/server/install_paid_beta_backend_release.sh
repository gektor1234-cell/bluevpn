#!/usr/bin/env bash
set -euo pipefail

APPLY=0
LEAVE_SYNC_STOPPED=0
ROLE=""
BUNDLE_DIR=""

INSTALL_ROOT="/opt/bluevpn-paid-beta"
RELEASES_ROOT="${INSTALL_ROOT}/releases"
CURRENT_LINK="${INSTALL_ROOT}/current"
DATA_DIR="${INSTALL_ROOT}/data"
VENV_DIR="${INSTALL_ROOT}/.venv"
ENV_FILE="/etc/bluevpn/paid-beta.env"
SERVICE="greenvpn-paid-beta.service"
SYNC_SERVICE="greenvpn-paid-beta-db-sync.service"
SYNC_TIMER="greenvpn-paid-beta-db-sync.timer"

usage() {
  cat <<'EOF'
Install a backend-only paid-beta release without changing site or client files.

Usage:
  install_paid_beta_backend_release.sh \
    --role timeweb|ruvds \
    --bundle-dir PATH \
    [--leave-sync-stopped] [--apply]

Default mode is dry-run. The installer clones the current paid-beta release,
replaces only backend/app/main.py, requirements.txt and the three DB sync files,
creates an online SQLite backup, updates node identity atomically and verifies
health, schema and database integrity.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --role) ROLE="${2:?missing role}"; shift 2 ;;
    --bundle-dir) BUNDLE_DIR="${2:?missing bundle dir}"; shift 2 ;;
    --leave-sync-stopped) LEAVE_SYNC_STOPPED=1; shift ;;
    --apply) APPLY=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
done

case "$ROLE" in
  timeweb) NODE_ID_BASE=0 ;;
  ruvds) NODE_ID_BASE=1000000000 ;;
  *) echo "--role must be timeweb or ruvds" >&2; exit 2 ;;
esac

[[ -d "$BUNDLE_DIR" ]] || { echo "Bundle directory not found" >&2; exit 2; }
[[ -L "$CURRENT_LINK" ]] || { echo "Current paid-beta release link is missing" >&2; exit 2; }
[[ -f "$ENV_FILE" && ! -L "$ENV_FILE" ]] || { echo "Paid-beta env is missing or unsafe" >&2; exit 2; }

required=(
  backend/app/main.py
  backend/requirements.txt
  ops/greenvpn_db_sync_from_peer.sh
  ops/greenvpn_sqlite_snapshot_stdout.py
  ops/greenvpn_sqlite_state_sync.py
  backend-release-manifest.json
)
for relative in "${required[@]}"; do
  [[ -f "$BUNDLE_DIR/$relative" && ! -L "$BUNDLE_DIR/$relative" ]] || {
    echo "Required bundle file is missing or unsafe: $relative" >&2
    exit 2
  }
done

readarray -t manifest_values < <(python3 - "$BUNDLE_DIR/backend-release-manifest.json" <<'PY'
import hashlib
import json
import pathlib
import re
import sys

value = json.loads(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8-sig"))
root = pathlib.Path(sys.argv[1]).resolve().parent
release_id = str(value.get("releaseId") or "")
backend_version = str(value.get("backendVersion") or "")
if value.get("contour") != "paid-beta":
    raise SystemExit("invalid contour")
if value.get("changesClientArtifacts") is not False or value.get("changesSite") is not False:
    raise SystemExit("backend-only bundle may not change client artifacts or site")
if not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9._-]{4,120}", release_id):
    raise SystemExit("invalid release id")
if not re.fullmatch(r"[0-9]+\.[0-9]+\.[0-9]+[A-Za-z0-9._-]*", backend_version):
    raise SystemExit("invalid backend version")
for item in value.get("files") or []:
    relative = pathlib.PurePosixPath(str(item.get("path") or ""))
    if relative.is_absolute() or ".." in relative.parts:
        raise SystemExit("unsafe manifest path")
    path = root.joinpath(*relative.parts)
    if not path.is_file() or path.is_symlink():
        raise SystemExit(f"manifest file is missing or unsafe: {relative}")
    digest = hashlib.sha256(path.read_bytes()).hexdigest().upper()
    if digest != str(item.get("sha256") or "").strip().upper():
        raise SystemExit(f"manifest hash mismatch: {relative}")
print(release_id)
print(backend_version)
PY
)
RELEASE_ID="${manifest_values[0]:-}"
BACKEND_VERSION="${manifest_values[1]:-}"
CURRENT_DIR="$(readlink -f -- "$CURRENT_LINK")"
RELEASE_DIR="${RELEASES_ROOT}/${RELEASE_ID}"

case "$CURRENT_DIR" in
  "${RELEASES_ROOT}"/*) ;;
  *) echo "Current release is outside release root" >&2; exit 2 ;;
esac
[[ ! -e "$RELEASE_DIR" ]] || { echo "Release already exists: $RELEASE_DIR" >&2; exit 2; }

echo "mode=$([[ $APPLY -eq 1 ]] && echo apply || echo dry-run)"
echo "role=$ROLE"
echo "release_id=$RELEASE_ID"
echo "backend_version=$BACKEND_VERSION"
echo "current_release=$CURRENT_DIR"
echo "node_id_base=$NODE_ID_BASE"
echo "client_artifacts_changed=false"
echo "site_changed=false"
echo "leave_sync_stopped=$LEAVE_SYNC_STOPPED"

[[ $APPLY -eq 1 ]] || exit 0
[[ $EUID -eq 0 ]] || { echo "Run apply mode as root" >&2; exit 1; }

for command in curl python3 systemctl; do
  command -v "$command" >/dev/null 2>&1 || {
    echo "Required command missing: $command" >&2
    exit 1
  }
done

timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
backup_dir="/root/greenvpn-paid-beta-backend-backups/${timestamp}-${RELEASE_ID}"
install -d -m 700 "$backup_dir"
printf '%s\n' "$CURRENT_DIR" >"$backup_dir/previous-release.txt"
cp -a "$ENV_FILE" "$backup_dir/paid-beta.env"
chmod 600 "$backup_dir/paid-beta.env"

sync_was_active=0
switched=0
env_modified=0
if systemctl is-active --quiet "$SYNC_TIMER"; then
  sync_was_active=1
fi

rollback_on_error() {
  code=$?
  trap - ERR
  if [[ $switched -eq 1 ]]; then
    ln -sfn "$CURRENT_DIR" "$CURRENT_LINK"
  fi
  if [[ $env_modified -eq 1 ]]; then
    cp -a "$backup_dir/paid-beta.env" "$ENV_FILE"
  fi
  if [[ $switched -eq 1 ]]; then
    systemctl restart "$SERVICE" >/dev/null 2>&1 || true
  fi
  if [[ $sync_was_active -eq 1 ]]; then
    systemctl restart "$SYNC_TIMER" >/dev/null 2>&1 || true
  fi
  exit "$code"
}
trap rollback_on_error ERR

systemctl stop "$SYNC_TIMER" >/dev/null 2>&1 || true
systemctl stop "$SYNC_SERVICE" >/dev/null 2>&1 || true

python3 - "$DATA_DIR/bluevpn.db" "$backup_dir/bluevpn.db" <<'PY'
import pathlib
import sqlite3
import sys

source_path = pathlib.Path(sys.argv[1])
target_path = pathlib.Path(sys.argv[2])
source = sqlite3.connect(f"file:{source_path}?mode=ro", uri=True, timeout=30)
target = sqlite3.connect(target_path, timeout=30)
try:
    source.backup(target)
    result = target.execute("PRAGMA quick_check").fetchone()[0]
finally:
    target.close()
    source.close()
if result != "ok":
    raise SystemExit(f"backup quick_check failed: {result}")
target_path.chmod(0o600)
PY

install -d -m 755 "$RELEASE_DIR"
cp -a --reflink=auto "$CURRENT_DIR/." "$RELEASE_DIR/"
install -m 644 "$BUNDLE_DIR/backend/app/main.py" "$RELEASE_DIR/backend/app/main.py"
install -m 644 "$BUNDLE_DIR/backend/requirements.txt" "$RELEASE_DIR/backend/requirements.txt"
install -m 755 "$BUNDLE_DIR/ops/greenvpn_db_sync_from_peer.sh" "$RELEASE_DIR/ops/greenvpn_db_sync_from_peer.sh"
install -m 755 "$BUNDLE_DIR/ops/greenvpn_sqlite_snapshot_stdout.py" "$RELEASE_DIR/ops/greenvpn_sqlite_snapshot_stdout.py"
install -m 755 "$BUNDLE_DIR/ops/greenvpn_sqlite_state_sync.py" "$RELEASE_DIR/ops/greenvpn_sqlite_state_sync.py"
cp -a "$BUNDLE_DIR/backend-release-manifest.json" "$RELEASE_DIR/backend-release-manifest.json"

python3 -m py_compile \
  "$RELEASE_DIR/backend/app/main.py" \
  "$RELEASE_DIR/ops/greenvpn_sqlite_snapshot_stdout.py" \
  "$RELEASE_DIR/ops/greenvpn_sqlite_state_sync.py"
"$VENV_DIR/bin/pip" install --disable-pip-version-check -r "$RELEASE_DIR/backend/requirements.txt" >/dev/null

python3 - "$ENV_FILE" "$BACKEND_VERSION" "$ROLE" "$NODE_ID_BASE" <<'PY'
import os
import pathlib
import re
import sys

path = pathlib.Path(sys.argv[1])
updates = {
    "GREENVPN_BACKEND_VERSION": sys.argv[2],
    "GREENVPN_REPLICATION_NODE_ID": sys.argv[3],
    "GREENVPN_SQLITE_NODE_ID_BASE": sys.argv[4],
}
assignment = re.compile(r"^(?:export\s+)?([A-Za-z_][A-Za-z0-9_]*)\s*=")
out = []
for raw in path.read_text(encoding="utf-8").splitlines():
    match = assignment.match(raw.strip())
    if match and match.group(1) in updates:
        continue
    out.append(raw)
for key, value in updates.items():
    out.append(f"{key}={value}")
temporary = path.with_name(path.name + ".backend-release.tmp")
temporary.write_text("\n".join(out) + "\n", encoding="utf-8")
os.chmod(temporary, 0o600)
os.replace(temporary, path)
PY
env_modified=1
chown root:root "$ENV_FILE"
chmod 600 "$ENV_FILE"

ln -sfn "$RELEASE_DIR" "$CURRENT_LINK"
switched=1
systemctl restart "$SERVICE"
for _ in $(seq 1 30); do
  curl -fsS --max-time 3 http://127.0.0.1:8010/healthz >/dev/null && break
  sleep 1
done
curl -fsS --max-time 5 http://127.0.0.1:8010/healthz >/dev/null

python3 - "$DATA_DIR/bluevpn.db" "$ROLE" "$NODE_ID_BASE" <<'PY'
import sqlite3
import sys

path, role, base_raw = sys.argv[1:]
base = int(base_raw)
conn = sqlite3.connect(f"file:{path}?mode=ro", uri=True, timeout=30)
try:
    result = conn.execute("PRAGMA quick_check").fetchone()[0]
    tombstones = conn.execute(
        "SELECT COUNT(*) FROM sqlite_master WHERE type='table' AND name='replication_tombstones'"
    ).fetchone()[0]
    sequences = conn.execute(
        """
        SELECT s.name, s.seq
        FROM sqlite_sequence s
        JOIN sqlite_master m ON m.name = s.name
        WHERE m.type = 'table' AND m.sql LIKE '%AUTOINCREMENT%'
        """
    ).fetchall()
finally:
    conn.close()
if result != "ok" or tombstones != 1:
    raise SystemExit("database readiness failed")
if role == "ruvds" and any(int(seq or 0) < base for _, seq in sequences):
    raise SystemExit("RUVDS sequence range was not reserved")
print(f"database_quick_check={result}")
print(f"replication_tombstones_ready={bool(tombstones)}")
print(f"autoincrement_sequences={len(sequences)}")
PY

if [[ $sync_was_active -eq 1 && $LEAVE_SYNC_STOPPED -eq 0 ]]; then
  systemctl restart "$SYNC_TIMER"
fi

systemctl is-active --quiet bluevpn-backend.service
curl -fsS --max-time 5 http://127.0.0.1:8000/healthz >/dev/null

trap - ERR
echo "backend_release_status=ok"
echo "current_release=$(readlink -f -- "$CURRENT_LINK")"
echo "backup_dir=$backup_dir"
echo "sync_timer=$(systemctl is-active "$SYNC_TIMER" 2>/dev/null || true)"
echo "client_artifacts_changed=false"
echo "site_changed=false"
