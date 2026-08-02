#!/usr/bin/env bash
set -euo pipefail

SERVER_HOST="${1:-}"
if [[ -z "${SERVER_HOST}" ]]; then
  echo "Usage: $0 <control-plane-host>" >&2
  exit 2
fi
case "${SERVER_HOST}" in
  72.56.32.197|176.113.81.35) ;;
  *)
    echo "Refusing legacy backend deploy to non-control-plane host: ${SERVER_HOST}" >&2
    exit 2
    ;;
esac
REMOTE="root@${SERVER_HOST}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
SRC_DIR="${PROJECT_ROOT}/backend_live"
STAMP="$(date +%Y%m%d_%H%M%S)"
REMOTE_TMP="/tmp/bluevpn_backend_deploy_${STAMP}"

if [[ ! -f "${SRC_DIR}/app/main.py" ]]; then
  echo "backend main.py not found: ${SRC_DIR}/app/main.py" >&2
  exit 1
fi

if [[ ! -f "${SRC_DIR}/requirements.txt" ]]; then
  echo "backend requirements.txt not found: ${SRC_DIR}/requirements.txt" >&2
  exit 1
fi

echo "[BlueVPN deploy] server=${SERVER_HOST}"
echo "[BlueVPN deploy] source=${SRC_DIR}"
echo "[BlueVPN deploy] creating remote temp..."
ssh "${REMOTE}" "mkdir -p '${REMOTE_TMP}/app'"

echo "[BlueVPN deploy] uploading backend files..."
scp "${SRC_DIR}/requirements.txt" "${REMOTE}:${REMOTE_TMP}/requirements.txt"
scp "${SRC_DIR}/app/main.py" "${REMOTE}:${REMOTE_TMP}/app/main.py"

echo "[BlueVPN deploy] installing and restarting backend..."
ssh "${REMOTE}" "bash -s -- '${REMOTE_TMP}' '${STAMP}'" <<'REMOTE_SCRIPT'
set -euo pipefail

REMOTE_TMP="$1"
STAMP="$2"
APP_ROOT="/opt/bluevpn/backend"

mkdir -p "${APP_ROOT}/app" "${APP_ROOT}/data"

if [[ -f "${APP_ROOT}/app/main.py" ]]; then
  cp "${APP_ROOT}/app/main.py" "${APP_ROOT}/app/main.py.bak_${STAMP}"
fi

install -m 0644 "${REMOTE_TMP}/requirements.txt" "${APP_ROOT}/requirements.txt"
install -m 0644 "${REMOTE_TMP}/app/main.py" "${APP_ROOT}/app/main.py"

cd "${APP_ROOT}"
if [[ ! -x ".venv/bin/python" ]]; then
  python3 -m venv .venv
fi

.venv/bin/pip install -r requirements.txt
.venv/bin/python -m py_compile app/main.py

systemctl daemon-reload
systemctl restart bluevpn-backend
sleep 1
systemctl is-active bluevpn-backend
curl -fsS http://127.0.0.1:8000/healthz
rm -rf "${REMOTE_TMP}"
REMOTE_SCRIPT

echo
echo "[BlueVPN deploy] done."
