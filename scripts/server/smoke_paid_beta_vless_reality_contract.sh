#!/usr/bin/env bash
set -euo pipefail

CURRENT_BACKEND="${GREENVPN_PAID_BETA_BACKEND_DIR:-/opt/bluevpn-paid-beta/current/backend}"
PYTHON_BIN="${GREENVPN_PAID_BETA_PYTHON:-/opt/bluevpn-paid-beta/.venv/bin/python}"
SERVICE_NAME="${GREENVPN_PAID_BETA_SERVICE:-greenvpn-paid-beta.service}"
SERVER_ID="${GREENVPN_VLESS_SMOKE_SERVER_ID:-nl2-vless-reality-xhttp-canary}"
EXPECTED_HOST="${GREENVPN_VLESS_SMOKE_EXPECTED_HOST:-5.129.216.42}"
EXPECTED_PORT="${GREENVPN_VLESS_SMOKE_EXPECTED_PORT:-443}"

if [[ "${EUID}" -ne 0 ]]; then
  echo "Run as root on a paid-beta control-plane." >&2
  exit 1
fi
if [[ ! -x "${PYTHON_BIN}" || ! -d "${CURRENT_BACKEND}" ]]; then
  echo "Paid-beta runtime is incomplete." >&2
  exit 1
fi
MAIN_PID="$(systemctl show --property MainPID --value "${SERVICE_NAME}")"
if ! [[ "${MAIN_PID}" =~ ^[1-9][0-9]*$ ]] || [[ ! -r "/proc/${MAIN_PID}/environ" ]]; then
  echo "Paid-beta service process environment is unavailable." >&2
  exit 1
fi

cd "${CURRENT_BACKEND}"
exec "${PYTHON_BIN}" - "${MAIN_PID}" "${CURRENT_BACKEND}" "${SERVER_ID}" "${EXPECTED_HOST}" "${EXPECTED_PORT}" <<'PY'
import json
import os
import sys

main_pid, backend_dir, server_id, expected_host, expected_port = sys.argv[1:]
for entry in open(f"/proc/{main_pid}/environ", "rb").read().split(b"\0"):
    if not entry or b"=" not in entry:
        continue
    key, value = entry.split(b"=", 1)
    os.environ[key.decode("utf-8")] = value.decode("utf-8")
sys.path.insert(0, backend_dir)

from app import main
row = main.get_managed_server_catalog_row_by_server_id(server_id)
if row is None:
    raise SystemExit("Guarded VLESS REALITY catalog row is missing")
readiness = main.server_client_config_readiness(row)
if not readiness.get("ready"):
    codes = [item.get("code") for item in readiness.get("blockers") or []]
    raise SystemExit("VLESS REALITY readiness failed: " + ",".join(str(code) for code in codes))

loaded = main.load_vless_reality_client_config(
    server_id,
    row_host=expected_host,
    row_port=int(expected_port),
)
issued = json.loads(loaded["configText"])

def contains_private_material(value):
    if isinstance(value, dict):
        return any(
            str(key).lower() in {"privatekey", "mldsa65seed"}
            or contains_private_material(child)
            for key, child in value.items()
        )
    if isinstance(value, list):
        return any(contains_private_material(child) for child in value)
    return False

inbounds = issued.get("inbounds") or []
outbounds = issued.get("outbounds") or []
checks = {
    "readiness": True,
    "endpoint": loaded.get("host") == expected_host and loaded.get("port") == int(expected_port),
    "singleLoopbackInbound": (
        len(inbounds) == 1
        and inbounds[0].get("listen") == "127.0.0.1"
        and inbounds[0].get("port") == 1981
        and inbounds[0].get("protocol") == "socks"
    ),
    "vlessOutbound": bool(outbounds) and outbounds[0].get("protocol") == "vless",
    "noServerPrivateMaterial": not contains_private_material(issued),
}
if not all(checks.values()):
    raise SystemExit("VLESS REALITY redacted smoke failed: " + json.dumps(checks, sort_keys=True))
print(
    json.dumps(
        {
            "ok": True,
            "version": main.APP_VERSION,
            "serverId": server_id,
            "profile": readiness.get("profile"),
            "endpoint": f"{loaded['host']}:{loaded['port']}",
            "configFormat": "xray-json",
            "configTextBytes": len(loaded["configText"].encode("utf-8")),
            "checks": checks,
            "secretPolicy": "configText and client credentials are never printed",
        },
        sort_keys=True,
    )
)
PY
