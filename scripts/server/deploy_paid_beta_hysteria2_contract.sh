#!/usr/bin/env bash
set -euo pipefail

APPLY=0
ROLE=""
EXPECTED_PUBLIC_IP=""
BACKEND_FILE=""
BASE_CONFIG_FILE=""
EXPECTED_BACKEND_SHA256=""
EXPECTED_CONFIG_SHA256=""

TIMEWEB_IP="72.56.32.197"
RUVDS_IP="176.113.81.35"
EXPECTED_CURRENT_RELEASE="paid-beta-0.3.0-paid-beta.6-2026071106-r15-awg2-active-active"
RELEASE_ID="paid-beta-0.3.0-paid-beta.6-2026071106-r16-hysteria-contract"
BACKEND_VERSION="0.9.110-transport-preview.4"
SERVER_ID="nl2-hysteria2-canary"
SERVER_HOST="5.129.216.42"
SERVER_PORT="2443"
SERVER_SNI="nl2.vpn.greenvpn.pro"

INSTALL_ROOT="/opt/bluevpn-paid-beta"
RELEASES_ROOT="${INSTALL_ROOT}/releases"
CURRENT_LINK="${INSTALL_ROOT}/current"
DATA_DIR="${INSTALL_ROOT}/data"
DB_PATH="${DATA_DIR}/bluevpn.db"
ENV_FILE="/etc/bluevpn/paid-beta.env"
CONFIG_ROOT="/etc/bluevpn/transport_clients"
LIVE_BASE_CONFIG="${CONFIG_ROOT}/${SERVER_ID}.hysteria2.yaml"
SERVICE_NAME="greenvpn-paid-beta.service"
BACKUP_ROOT="/root/greenvpn-hysteria2-contract-prechange"

usage() {
  cat <<'USAGE'
Deploy the guarded Hysteria2 config contract to one isolated paid-beta control-plane.

Default mode is dry-run.

  deploy_paid_beta_hysteria2_contract.sh \
    --role timeweb|ruvds \
    --expected-public-ip IP \
    --backend-file /root/stage/main.py \
    --base-config-file /root/stage/nl2-hysteria2-canary.hysteria2.yaml \
    --backend-sha256 SHA256 \
    --config-sha256 SHA256 \
    [--apply]

The script modifies only the isolated paid-beta release, paid-beta env, paid-beta
SQLite catalog and root-only Hysteria2 base config. Production backend/site/DB,
public downloads and VPN nodes are verified but never edited.
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --apply) APPLY=1; shift ;;
    --role) ROLE="${2:?missing role}"; shift 2 ;;
    --expected-public-ip) EXPECTED_PUBLIC_IP="${2:?missing expected public ip}"; shift 2 ;;
    --backend-file) BACKEND_FILE="${2:?missing backend file}"; shift 2 ;;
    --base-config-file) BASE_CONFIG_FILE="${2:?missing base config file}"; shift 2 ;;
    --backend-sha256) EXPECTED_BACKEND_SHA256="${2:?missing backend sha256}"; shift 2 ;;
    --config-sha256) EXPECTED_CONFIG_SHA256="${2:?missing config sha256}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
done

case "${ROLE}" in
  timeweb) ROLE_IP="${TIMEWEB_IP}" ;;
  ruvds) ROLE_IP="${RUVDS_IP}" ;;
  *) echo "--role must be timeweb or ruvds" >&2; exit 2 ;;
esac

if [[ "${EUID}" -ne 0 ]]; then
  echo "Run as root on the target paid-beta control-plane." >&2
  exit 1
fi
PUBLIC_IP="$(curl -fsS --max-time 5 https://api.ipify.org || true)"
if [[ -z "${PUBLIC_IP}" || "${PUBLIC_IP}" != "${ROLE_IP}" || "${EXPECTED_PUBLIC_IP}" != "${ROLE_IP}" ]]; then
  echo "Role/public IP mismatch; refusing deploy." >&2
  exit 1
fi
if [[ ! -f "${BACKEND_FILE}" || ! -f "${BASE_CONFIG_FILE}" ]]; then
  echo "Staged backend or Hysteria2 config is missing." >&2
  exit 1
fi
if [[ -L "${BACKEND_FILE}" || -L "${BASE_CONFIG_FILE}" ]]; then
  echo "Staged files must not be symlinks." >&2
  exit 1
fi
if ! [[ "${EXPECTED_BACKEND_SHA256}" =~ ^[0-9a-fA-F]{64}$ \
  && "${EXPECTED_CONFIG_SHA256}" =~ ^[0-9a-fA-F]{64}$ ]]; then
  echo "Expected SHA-256 values are invalid." >&2
  exit 2
fi
printf '%s  %s\n' "${EXPECTED_BACKEND_SHA256,,}" "${BACKEND_FILE}" | sha256sum -c -
printf '%s  %s\n' "${EXPECTED_CONFIG_SHA256,,}" "${BASE_CONFIG_FILE}" | sha256sum -c -
python3 -m py_compile "${BACKEND_FILE}"

CONFIG_MODE="$(stat -c '%a' "${BASE_CONFIG_FILE}")"
CONFIG_OWNER="$(stat -c '%U' "${BASE_CONFIG_FILE}")"
if [[ "${CONFIG_OWNER}" != "root" || "${CONFIG_MODE}" != "600" ]]; then
  echo "Staged Hysteria2 config must be root:root 0600." >&2
  exit 1
fi
for pattern in \
  "^server: ${SERVER_HOST}:${SERVER_PORT}$" \
  '^auth: [^[:space:]#]+$' \
  '^tls:$' \
  "^[[:space:]]+sni: ${SERVER_SNI}$" \
  '^[[:space:]]+insecure: false$' \
  '^obfs:$' \
  '^[[:space:]]+type: salamander$' \
  '^[[:space:]]+password: [^[:space:]#]+$'; do
  if ! grep -Eq "${pattern}" "${BASE_CONFIG_FILE}"; then
    echo "Staged Hysteria2 base config failed shape validation." >&2
    exit 1
  fi
done
if grep -Eq '^(socks5|http|tun|tcpForwarding|udpForwarding|tcpTProxy|udpTProxy):' "${BASE_CONFIG_FILE}"; then
  echo "Staged base config must not define a client-local mode." >&2
  exit 1
fi

CURRENT_RELEASE="$(readlink -f "${CURRENT_LINK}" 2>/dev/null || true)"
if [[ "$(basename "${CURRENT_RELEASE}")" != "${EXPECTED_CURRENT_RELEASE}" ]]; then
  echo "Unexpected current paid-beta release; refusing non-linear deploy: ${CURRENT_RELEASE}" >&2
  exit 1
fi
if [[ ! -f "${ENV_FILE}" || ! -f "${DB_PATH}" ]]; then
  echo "Paid-beta env or DB is missing." >&2
  exit 1
fi
if ! systemctl is-active --quiet bluevpn-backend.service \
  || ! curl -fsS --max-time 10 http://127.0.0.1:8000/healthz >/dev/null; then
  echo "Production backend is not healthy; refusing beta deploy." >&2
  exit 1
fi
if ! systemctl is-active --quiet "${SERVICE_NAME}" \
  || ! curl -fsS --max-time 10 http://127.0.0.1:8010/healthz >/dev/null; then
  echo "Paid-beta backend is not healthy before deploy." >&2
  exit 1
fi

echo "Green VPN paid-beta Hysteria2 contract plan"
echo "mode=$([[ "${APPLY}" -eq 1 ]] && echo apply || echo dry-run)"
echo "role=${ROLE}"
echo "public_ip=${PUBLIC_IP}"
echo "current_release=${CURRENT_RELEASE}"
echo "next_release=${RELEASES_ROOT}/${RELEASE_ID}"
echo "backend_version=${BACKEND_VERSION}"
echo "server_id=${SERVER_ID}"
echo "production_changed=false"
echo "stable_catalog_changed=false"

if [[ "${APPLY}" -ne 1 ]]; then
  exit 0
fi

RELEASE_DIR="${RELEASES_ROOT}/${RELEASE_ID}"
if [[ -e "${RELEASE_DIR}" ]]; then
  echo "Target release already exists; refusing overwrite." >&2
  exit 1
fi

STAMP="$(date -u +%Y%m%dT%H%M%SZ)"
BACKUP_DIR="${BACKUP_ROOT}/${STAMP}-${ROLE}"
install -d -m 0700 "${BACKUP_DIR}"
cp -a -- "${ENV_FILE}" "${BACKUP_DIR}/paid-beta.env.before"
printf '%s\n' "${CURRENT_RELEASE}" > "${BACKUP_DIR}/previous-current-link.txt"
if [[ -e "${LIVE_BASE_CONFIG}" ]]; then
  cp -a -- "${LIVE_BASE_CONFIG}" "${BACKUP_DIR}/"
  printf '1\n' > "${BACKUP_DIR}/live-config-existed.txt"
else
  printf '0\n' > "${BACKUP_DIR}/live-config-existed.txt"
fi
python3 - "${DB_PATH}" "${BACKUP_DIR}/bluevpn.db.before.sqlite" <<'PY'
import sqlite3, sys
source = sqlite3.connect(f"file:{sys.argv[1]}?mode=ro", uri=True)
target = sqlite3.connect(sys.argv[2])
source.backup(target)
target.close()
source.close()
PY
chmod 0600 "${BACKUP_DIR}"/*

ROLLBACK_ARMED=1
rollback_on_error() {
  local exit_code=$?
  trap - ERR
  set +e
  if [[ "${ROLLBACK_ARMED}" -eq 1 ]]; then
    ln -sfn "${CURRENT_RELEASE}" "${CURRENT_LINK}"
    cp -a -- "${BACKUP_DIR}/paid-beta.env.before" "${ENV_FILE}"
    chown root:root "${ENV_FILE}"
    chmod 0600 "${ENV_FILE}"
    if [[ "$(cat "${BACKUP_DIR}/live-config-existed.txt")" == "1" ]]; then
      cp -a -- "${BACKUP_DIR}/$(basename "${LIVE_BASE_CONFIG}")" "${LIVE_BASE_CONFIG}"
    elif [[ -f "${LIVE_BASE_CONFIG}" ]]; then
      mv -- "${LIVE_BASE_CONFIG}" "${BACKUP_DIR}/failed-new-base-config.yaml"
    fi
    if [[ -d "${RELEASE_DIR}" && "$(readlink -f "${CURRENT_LINK}" 2>/dev/null)" != "${RELEASE_DIR}" ]]; then
      mv -- "${RELEASE_DIR}" "${BACKUP_DIR}/failed-release"
    fi
    systemctl restart "${SERVICE_NAME}"
  fi
  exit "${exit_code}"
}
trap rollback_on_error ERR

cp -a -- "${CURRENT_RELEASE}" "${RELEASE_DIR}"
install -m 0644 "${BACKEND_FILE}" "${RELEASE_DIR}/backend/app/main.py"
install -d -m 0700 "${CONFIG_ROOT}"
install -m 0600 "${BASE_CONFIG_FILE}" "${LIVE_BASE_CONFIG}"
chown root:root "${RELEASE_DIR}/backend/app/main.py" "${CONFIG_ROOT}" "${LIVE_BASE_CONFIG}"
chmod 0700 "${CONFIG_ROOT}"
chmod 0600 "${LIVE_BASE_CONFIG}"

python3 - "${ENV_FILE}" "${BACKEND_VERSION}" "${SERVER_ID}" "${SERVER_SNI}" "${CONFIG_ROOT}" <<'PY'
import os, pathlib, re, sys
path = pathlib.Path(sys.argv[1])
updates = {
    "GREENVPN_BACKEND_VERSION": sys.argv[2],
    "GREENVPN_HYSTERIA2_CLIENT_CONFIG_ENABLED": "1",
    "GREENVPN_HYSTERIA2_CANARY_SERVER_IDS": sys.argv[3],
    "GREENVPN_HYSTERIA2_CANARY_SNI": sys.argv[4],
    "GREENVPN_HYSTERIA2_CLIENT_CONFIG_ROOT": sys.argv[5],
}
lines = path.read_text(encoding="utf-8").splitlines()
assignment = re.compile(r"^(?:export\s+)?([A-Za-z_][A-Za-z0-9_]*)\s*=")
preview_ids = []
for raw in lines:
    match = assignment.match(raw.strip())
    if match and match.group(1) == "GREENVPN_PREVIEW_SERVER_IDS":
        value = raw.split("=", 1)[1].strip().strip("\"'")
        preview_ids.extend(item.strip() for item in value.split(",") if item.strip())
preview_ids.append(sys.argv[3])
updates["GREENVPN_PREVIEW_SERVER_IDS"] = ",".join(dict.fromkeys(preview_ids))
out = []
for raw in lines:
    match = assignment.match(raw.strip())
    if match and match.group(1) in updates:
        continue
    out.append(raw)
out.extend(f"{key}={value}" for key, value in updates.items())
temporary = path.with_name(path.name + ".hysteria2.tmp")
temporary.write_text("\n".join(out) + "\n", encoding="utf-8")
os.chmod(temporary, 0o600)
os.replace(temporary, path)
PY
chown root:root "${ENV_FILE}"
chmod 0600 "${ENV_FILE}"

python3 - "${DB_PATH}" "${SERVER_ID}" "${SERVER_HOST}" "${SERVER_PORT}" <<'PY'
import sqlite3, sys
from datetime import datetime, timezone
db_path, server_id, host, port = sys.argv[1:]
now = datetime.now(timezone.utc).isoformat()
conn = sqlite3.connect(db_path)
conn.execute("PRAGMA foreign_keys=ON")
conn.execute(
    """
    INSERT INTO server_catalog_entries(
        server_id, title, subtitle, country, city, provider, host, port,
        protocol, transport, access_tier, client_config_profile, status, health_score,
        latency_ms, priority, is_active, is_public, planned_bandwidth_mbps,
        reserved_bandwidth_mbps, current_load_mbps, active_clients,
        assigned_users, load_updated_at, notes, created_at, updated_at,
        publication_paused_at, publication_paused_reason, publication_paused_by
    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, NULL, NULL, NULL)
    ON CONFLICT(server_id) DO UPDATE SET
        title=excluded.title,
        subtitle=excluded.subtitle,
        country=excluded.country,
        city=excluded.city,
        provider=excluded.provider,
        host=excluded.host,
        port=excluded.port,
        protocol=excluded.protocol,
        transport=excluded.transport,
        client_config_profile=excluded.client_config_profile,
        status=excluded.status,
        health_score=excluded.health_score,
        latency_ms=excluded.latency_ms,
        priority=excluded.priority,
        is_active=excluded.is_active,
        is_public=excluded.is_public,
        planned_bandwidth_mbps=excluded.planned_bandwidth_mbps,
        reserved_bandwidth_mbps=excluded.reserved_bandwidth_mbps,
        notes=excluded.notes,
        updated_at=excluded.updated_at,
        publication_paused_at=NULL,
        publication_paused_reason=NULL,
        publication_paused_by=NULL
    """,
    (
        server_id, "Netherlands #2", "", "NL", "Amsterdam", "internal-canary",
        host, int(port), "hysteria2", "quic", "premium", "static_hysteria2_canary",
        "healthy", 100, 44, 900, 1, 0, 1000, 100, 0, 0, 0, now,
        "Isolated Hysteria2 preview canary; never expose without client capability.",
        now, now,
    ),
)
conn.commit()
check = conn.execute("PRAGMA quick_check").fetchone()[0]
if check != "ok":
    raise SystemExit(f"SQLite quick_check failed: {check}")
conn.close()
PY

ln -sfn "${RELEASE_DIR}" "${CURRENT_LINK}"
systemctl restart "${SERVICE_NAME}"
for _ in $(seq 1 40); do
  if curl -fsS --max-time 3 http://127.0.0.1:8010/healthz >/dev/null; then
    break
  fi
  sleep 0.25
done
systemctl is-active --quiet "${SERVICE_NAME}"

python3 - "${BACKEND_VERSION}" "${SERVER_ID}" <<'PY'
import json, sys, urllib.request
version, server_id = sys.argv[1:]
def get(path, headers=None):
    request = urllib.request.Request("http://127.0.0.1:8010" + path, headers=headers or {})
    with urllib.request.urlopen(request, timeout=10) as response:
        return json.load(response)
health = get("/healthz")
if health.get("version") != version:
    raise SystemExit("Paid-beta version mismatch after deploy")
legacy = get("/api/v1/catalog/servers")["catalog"]
if any(server_id == item.get("id") for item in legacy.get("servers") or []):
    raise SystemExit("Hysteria2 leaked into legacy catalog")
preview = get(
    "/api/v1/catalog/servers?channel=preview&currentVersion=0.3.0-transport-preview.2",
    {"X-GreenVPN-Supported-Protocols": "wireguard_udp,amneziawg,hysteria2"},
)["catalog"]
matches = [item for item in preview.get("servers") or [] if item.get("id") == server_id]
if len(matches) != 1 or not matches[0].get("clientConfigReady") or not matches[0].get("available"):
    raise SystemExit("Hysteria2 preview catalog contract is not ready")
default = next((item for item in preview.get("servers") or [] if item.get("id") == preview.get("defaultServerId")), {})
protocol = str(((default.get("protocols") or [{}])[0] or {}).get("code") or "")
if protocol != "wireguard_udp":
    raise SystemExit("Preview auto-selection no longer prefers WireGuard UDP")
print("paid_beta_health=ok")
print("legacy_hysteria_count=0")
print("preview_hysteria_count=1")
print("preview_default_protocol=wireguard_udp")
PY

curl -fsS --max-time 10 http://127.0.0.1:8000/healthz >/dev/null
python3 - "${DB_PATH}" <<'PY'
import sqlite3, sys
conn = sqlite3.connect(sys.argv[1])
print("db_quick_check=" + conn.execute("PRAGMA quick_check").fetchone()[0])
conn.close()
PY
ROLLBACK_ARMED=0
trap - ERR
echo "backup=${BACKUP_DIR}"
echo "release=${RELEASE_DIR}"
echo "Hysteria2 paid-beta contract deployed without changing production."
