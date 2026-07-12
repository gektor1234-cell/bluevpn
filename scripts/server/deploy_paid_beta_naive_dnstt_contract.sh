#!/usr/bin/env bash
set -euo pipefail

APPLY=0
ROLE=""
EXPECTED_PUBLIC_IP=""
BACKEND_FILE=""
NAIVE_CONFIG_FILE=""
DNSTT_CONFIG_FILE=""
EXPECTED_BACKEND_SHA256=""
EXPECTED_NAIVE_SHA256=""
EXPECTED_DNSTT_SHA256=""

TIMEWEB_IP="72.56.32.197"
RUVDS_IP="176.113.81.35"
EXPECTED_CURRENT_RELEASE="paid-beta-0.3.0-paid-beta.6-2026071106-r17-vless-contract"
RELEASE_ID="paid-beta-0.3.0-paid-beta.6-2026071106-r18-naive-dnstt-contract"
BACKEND_VERSION="0.9.112-transport-preview.6"
NAIVE_SERVER_ID="nl2-naive-https-canary"
DNSTT_SERVER_ID="nl2-dnstt-canary"
CANARY_IP="5.129.216.42"
NAIVE_HOST="nl2.vpn.greenvpn.pro"
NAIVE_PORT="8443"
DNSTT_ZONE="t.greenvpn.pro"
DNSTT_PORT="53"

INSTALL_ROOT="/opt/bluevpn-paid-beta"
RELEASES_ROOT="${INSTALL_ROOT}/releases"
CURRENT_LINK="${INSTALL_ROOT}/current"
DATA_DIR="${INSTALL_ROOT}/data"
DB_PATH="${DATA_DIR}/bluevpn.db"
ENV_FILE="/etc/bluevpn/paid-beta.env"
CONFIG_ROOT="/etc/bluevpn/transport_clients"
LIVE_NAIVE_CONFIG="${CONFIG_ROOT}/${NAIVE_SERVER_ID}.naive-https.json"
LIVE_DNSTT_CONFIG="${CONFIG_ROOT}/${DNSTT_SERVER_ID}.dnstt.json"
SERVICE_NAME="greenvpn-paid-beta.service"
BACKUP_ROOT="/root/greenvpn-naive-dnstt-contract-prechange"

usage() {
  cat <<'USAGE'
Deploy guarded Naive HTTPS and dnstt config contracts to one isolated paid-beta
control-plane. Dry-run is the default.

  deploy_paid_beta_naive_dnstt_contract.sh \
    --role timeweb|ruvds \
    --expected-public-ip IP \
    --backend-file /root/stage/main.py \
    --naive-config-file /root/stage/nl2-naive-https-canary.naive-https.json \
    --dnstt-config-file /root/stage/nl2-dnstt-canary.dnstt.json \
    --backend-sha256 SHA256 \
    --naive-sha256 SHA256 \
    --dnstt-sha256 SHA256 \
    [--apply]

Only paid-beta release/env/SQLite and two root-only client profiles are changed.
Production backend/site/DB, public downloads, public catalog and VPN nodes are
verified but never edited.
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --apply) APPLY=1; shift ;;
    --role) ROLE="${2:?missing role}"; shift 2 ;;
    --expected-public-ip) EXPECTED_PUBLIC_IP="${2:?missing expected public ip}"; shift 2 ;;
    --backend-file) BACKEND_FILE="${2:?missing backend file}"; shift 2 ;;
    --naive-config-file) NAIVE_CONFIG_FILE="${2:?missing naive config file}"; shift 2 ;;
    --dnstt-config-file) DNSTT_CONFIG_FILE="${2:?missing dnstt config file}"; shift 2 ;;
    --backend-sha256) EXPECTED_BACKEND_SHA256="${2:?missing backend sha256}"; shift 2 ;;
    --naive-sha256) EXPECTED_NAIVE_SHA256="${2:?missing naive sha256}"; shift 2 ;;
    --dnstt-sha256) EXPECTED_DNSTT_SHA256="${2:?missing dnstt sha256}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
done

case "${ROLE}" in
  timeweb) ROLE_IP="${TIMEWEB_IP}" ;;
  ruvds) ROLE_IP="${RUVDS_IP}" ;;
  *) echo "--role must be timeweb or ruvds" >&2; exit 2 ;;
esac

[[ "${EUID}" -eq 0 ]] || { echo "Run as root on the paid-beta control-plane." >&2; exit 1; }
for command in curl python3 sha256sum stat systemctl readlink; do
  command -v "${command}" >/dev/null 2>&1 || { echo "Required command missing: ${command}" >&2; exit 1; }
done
PUBLIC_IP="$(curl -fsS --max-time 5 https://api.ipify.org || true)"
if [[ -z "${PUBLIC_IP}" || "${PUBLIC_IP}" != "${ROLE_IP}" || "${EXPECTED_PUBLIC_IP}" != "${ROLE_IP}" ]]; then
  echo "Role/public IP mismatch; refusing deploy." >&2
  exit 1
fi

declare -A staged_hashes=(
  ["${BACKEND_FILE}"]="${EXPECTED_BACKEND_SHA256}"
  ["${NAIVE_CONFIG_FILE}"]="${EXPECTED_NAIVE_SHA256}"
  ["${DNSTT_CONFIG_FILE}"]="${EXPECTED_DNSTT_SHA256}"
)
for path in "${!staged_hashes[@]}"; do
  expected="${staged_hashes[${path}]}"
  [[ -f "${path}" && ! -L "${path}" ]] || { echo "Staged file is missing or symlinked: ${path}" >&2; exit 1; }
  [[ "${expected}" =~ ^[0-9a-fA-F]{64}$ ]] || { echo "Invalid expected SHA-256 for ${path}" >&2; exit 2; }
  printf '%s  %s\n' "${expected,,}" "${path}" | sha256sum -c -
done
python3 -m py_compile "${BACKEND_FILE}"
for profile in "${NAIVE_CONFIG_FILE}" "${DNSTT_CONFIG_FILE}"; do
  [[ "$(stat -c '%U:%G:%a' "${profile}")" == "root:root:600" ]] || {
    echo "Staged transport profiles must be root:root 0600." >&2
    exit 1
  }
done

python3 - "${NAIVE_CONFIG_FILE}" "${DNSTT_CONFIG_FILE}" "${NAIVE_HOST}" "${NAIVE_PORT}" "${DNSTT_ZONE}" "${CANARY_IP}" <<'PY'
import json, pathlib, re, sys, urllib.parse
naive_path, dnstt_path, naive_host, naive_port, dnstt_zone, canary_ip = sys.argv[1:]

naive = json.loads(pathlib.Path(naive_path).read_text(encoding="utf-8"))
if not isinstance(naive, dict) or set(naive) != {"listen", "proxy"}:
    raise SystemExit("Naive profile fields are invalid")
if naive.get("listen") != "socks://127.0.0.1:1982":
    raise SystemExit("Naive listener is not loopback-only")
proxy = urllib.parse.urlsplit(str(naive.get("proxy") or ""))
if (
    proxy.scheme.lower() != "https"
    or (proxy.hostname or "").lower() != naive_host.lower()
    or int(proxy.port or 0) != int(naive_port)
    or proxy.path
    or proxy.query
    or proxy.fragment
    or not proxy.username
    or not proxy.password
):
    raise SystemExit("Naive proxy URI does not match the guarded canary")

dnstt = json.loads(pathlib.Path(dnstt_path).read_text(encoding="utf-8"))
if not isinstance(dnstt, dict) or set(dnstt) != {"zone", "publicKey", "socks", "resolvers", "expectedEgress"}:
    raise SystemExit("dnstt profile fields are invalid")
if dnstt.get("zone") != dnstt_zone or dnstt.get("expectedEgress") != canary_ip:
    raise SystemExit("dnstt zone or egress does not match the guarded canary")
if not re.fullmatch(r"[0-9a-f]{64}", str(dnstt.get("publicKey") or "")):
    raise SystemExit("dnstt public key is invalid")
socks = dnstt.get("socks")
if not isinstance(socks, dict) or set(socks) != {"listen", "username", "password"}:
    raise SystemExit("dnstt SOCKS profile is invalid")
if socks.get("listen") != "127.0.0.1:1983":
    raise SystemExit("dnstt listener is not loopback-only")
if not re.fullmatch(r"[A-Za-z0-9_.-]{3,128}", str(socks.get("username") or "")):
    raise SystemExit("dnstt username is invalid")
if not re.fullmatch(r"[A-Za-z0-9+/=]{16,256}", str(socks.get("password") or "")):
    raise SystemExit("dnstt password is invalid")
allowed = {
    ("doh", "https://1.1.1.1/dns-query"),
    ("doh", "https://8.8.8.8/dns-query"),
    ("dot", "1.1.1.1:853"),
}
resolvers = dnstt.get("resolvers")
items = [
    (str(item.get("mode") or "").lower(), str(item.get("endpoint") or ""))
    for item in resolvers
    if isinstance(item, dict) and set(item) == {"mode", "endpoint"}
] if isinstance(resolvers, list) else []
if len(items) != len(resolvers or []) or not items or items[0] != ("doh", "https://1.1.1.1/dns-query"):
    raise SystemExit("dnstt primary DoH contract is invalid")
if len(set(items)) != len(items) or any(item not in allowed for item in items):
    raise SystemExit("dnstt resolver allowlist is invalid")
PY

CURRENT_RELEASE="$(readlink -f "${CURRENT_LINK}" 2>/dev/null || true)"
if [[ "$(basename "${CURRENT_RELEASE}")" != "${EXPECTED_CURRENT_RELEASE}" ]]; then
  echo "Unexpected paid-beta release; refusing non-linear deploy: ${CURRENT_RELEASE}" >&2
  exit 1
fi
[[ -f "${ENV_FILE}" && -f "${DB_PATH}" ]] || { echo "Paid-beta env or DB is missing." >&2; exit 1; }
systemctl is-active --quiet bluevpn-backend.service
curl -fsS --max-time 10 http://127.0.0.1:8000/healthz >/dev/null
systemctl is-active --quiet "${SERVICE_NAME}"
curl -fsS --max-time 10 http://127.0.0.1:8010/healthz >/dev/null

echo "Green VPN paid-beta Naive/dnstt contract plan"
echo "mode=$([[ "${APPLY}" -eq 1 ]] && echo apply || echo dry-run)"
echo "role=${ROLE}"
echo "public_ip=${PUBLIC_IP}"
echo "current_release=${CURRENT_RELEASE}"
echo "next_release=${RELEASES_ROOT}/${RELEASE_ID}"
echo "backend_version=${BACKEND_VERSION}"
echo "preview_servers=${NAIVE_SERVER_ID},${DNSTT_SERVER_ID}"
echo "production_changed=false"
echo "stable_catalog_changed=false"
echo "public_downloads_changed=false"

[[ "${APPLY}" -eq 1 ]] || exit 0

RELEASE_DIR="${RELEASES_ROOT}/${RELEASE_ID}"
[[ ! -e "${RELEASE_DIR}" ]] || { echo "Target release already exists; refusing overwrite." >&2; exit 1; }
STAMP="$(date -u +%Y%m%dT%H%M%SZ)"
BACKUP_DIR="${BACKUP_ROOT}/${STAMP}-${ROLE}"
install -d -m 0700 "${BACKUP_DIR}"
cp -a -- "${ENV_FILE}" "${BACKUP_DIR}/paid-beta.env.before"
printf '%s\n' "${CURRENT_RELEASE}" >"${BACKUP_DIR}/previous-current-link.txt"
for item in "${LIVE_NAIVE_CONFIG}" "${LIVE_DNSTT_CONFIG}"; do
  name="$(basename "${item}")"
  if [[ -e "${item}" ]]; then
    cp -a -- "${item}" "${BACKUP_DIR}/${name}.before"
    printf '1\n' >"${BACKUP_DIR}/${name}.existed"
  else
    printf '0\n' >"${BACKUP_DIR}/${name}.existed"
  fi
done
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
    systemctl stop "${SERVICE_NAME}" 2>/dev/null || true
    ln -sfn "${CURRENT_RELEASE}" "${CURRENT_LINK}"
    cp -a -- "${BACKUP_DIR}/paid-beta.env.before" "${ENV_FILE}"
    chown root:root "${ENV_FILE}"
    chmod 0600 "${ENV_FILE}"
    for item in "${LIVE_NAIVE_CONFIG}" "${LIVE_DNSTT_CONFIG}"; do
      name="$(basename "${item}")"
      if [[ "$(cat "${BACKUP_DIR}/${name}.existed")" == 1 ]]; then
        cp -a -- "${BACKUP_DIR}/${name}.before" "${item}"
      else
        rm -f -- "${item}"
      fi
    done
    python3 - "${BACKUP_DIR}/bluevpn.db.before.sqlite" "${DB_PATH}" <<'PY'
import sqlite3, sys
source = sqlite3.connect(f"file:{sys.argv[1]}?mode=ro", uri=True)
target = sqlite3.connect(sys.argv[2])
source.backup(target)
target.close()
source.close()
PY
    if [[ -d "${RELEASE_DIR}" && "$(readlink -f "${CURRENT_LINK}" 2>/dev/null)" != "${RELEASE_DIR}" ]]; then
      mv -- "${RELEASE_DIR}" "${BACKUP_DIR}/failed-release"
    fi
    systemctl start "${SERVICE_NAME}" 2>/dev/null || true
  fi
  exit "${exit_code}"
}
trap rollback_on_error ERR

cp -a -- "${CURRENT_RELEASE}" "${RELEASE_DIR}"
install -m 0644 "${BACKEND_FILE}" "${RELEASE_DIR}/backend/app/main.py"
install -d -m 0700 "${CONFIG_ROOT}"
install -m 0600 "${NAIVE_CONFIG_FILE}" "${LIVE_NAIVE_CONFIG}"
install -m 0600 "${DNSTT_CONFIG_FILE}" "${LIVE_DNSTT_CONFIG}"
chown root:root "${RELEASE_DIR}/backend/app/main.py" "${CONFIG_ROOT}" "${LIVE_NAIVE_CONFIG}" "${LIVE_DNSTT_CONFIG}"
chmod 0700 "${CONFIG_ROOT}"
chmod 0600 "${LIVE_NAIVE_CONFIG}" "${LIVE_DNSTT_CONFIG}"

python3 - "${ENV_FILE}" "${BACKEND_VERSION}" "${NAIVE_SERVER_ID}" "${DNSTT_SERVER_ID}" "${NAIVE_HOST}" "${CANARY_IP}" "${DNSTT_ZONE}" "${CONFIG_ROOT}" <<'PY'
import os, pathlib, re, sys
path = pathlib.Path(sys.argv[1])
version, naive_id, dnstt_id, naive_host, canary_ip, dnstt_zone, config_root = sys.argv[2:]
updates = {
    "GREENVPN_BACKEND_VERSION": version,
    "GREENVPN_NAIVE_HTTPS_CLIENT_CONFIG_ENABLED": "1",
    "GREENVPN_NAIVE_HTTPS_CANARY_SERVER_IDS": naive_id,
    "GREENVPN_NAIVE_HTTPS_CANARY_HOST": naive_host,
    "GREENVPN_NAIVE_HTTPS_CANARY_IP": canary_ip,
    "GREENVPN_NAIVE_HTTPS_CLIENT_CONFIG_ROOT": config_root,
    "GREENVPN_DNSTT_CLIENT_CONFIG_ENABLED": "1",
    "GREENVPN_DNSTT_CANARY_SERVER_IDS": dnstt_id,
    "GREENVPN_DNSTT_CANARY_ZONE": dnstt_zone,
    "GREENVPN_DNSTT_CANARY_IP": canary_ip,
    "GREENVPN_DNSTT_CLIENT_CONFIG_ROOT": config_root,
}
lines = path.read_text(encoding="utf-8").splitlines()
assignment = re.compile(r"^(?:export\s+)?([A-Za-z_][A-Za-z0-9_]*)\s*=")
preview_ids = []
for raw in lines:
    match = assignment.match(raw.strip())
    if match and match.group(1) == "GREENVPN_PREVIEW_SERVER_IDS":
        value = raw.split("=", 1)[1].strip().strip("\"'")
        preview_ids.extend(item.strip() for item in value.split(",") if item.strip())
preview_ids.extend((naive_id, dnstt_id))
updates["GREENVPN_PREVIEW_SERVER_IDS"] = ",".join(dict.fromkeys(preview_ids))
out = []
for raw in lines:
    match = assignment.match(raw.strip())
    if match and match.group(1) in updates:
        continue
    out.append(raw)
out.extend(f"{key}={value}" for key, value in updates.items())
temporary = path.with_name(path.name + ".naive-dnstt.tmp")
temporary.write_text("\n".join(out) + "\n", encoding="utf-8")
os.chmod(temporary, 0o600)
os.replace(temporary, path)
PY
chown root:root "${ENV_FILE}"
chmod 0600 "${ENV_FILE}"

python3 - "${DB_PATH}" "${NAIVE_SERVER_ID}" "${DNSTT_SERVER_ID}" "${CANARY_IP}" "${NAIVE_PORT}" "${DNSTT_PORT}" <<'PY'
import sqlite3, sys
from datetime import datetime, timezone
db_path, naive_id, dnstt_id, host, naive_port, dnstt_port = sys.argv[1:]
now = datetime.now(timezone.utc).isoformat()
entries = (
    (naive_id, int(naive_port), "naive_https", "https", "static_naive_https_canary", 930,
     "Isolated Naive HTTPS preview canary; never expose without client capability."),
    (dnstt_id, int(dnstt_port), "dnstt", "doh", "static_dnstt_canary", 940,
     "Isolated dnstt preview canary; last resort only; DNS delegation required."),
)
conn = sqlite3.connect(db_path)
conn.execute("PRAGMA foreign_keys=ON")
for server_id, port, protocol, transport, profile, priority, notes in entries:
    conn.execute(
        """
        INSERT INTO server_catalog_entries(
            server_id, title, subtitle, country, city, provider, host, port,
            protocol, transport, client_config_profile, status, health_score,
            latency_ms, priority, is_active, is_public, planned_bandwidth_mbps,
            reserved_bandwidth_mbps, current_load_mbps, active_clients,
            assigned_users, load_updated_at, notes, created_at, updated_at,
            publication_paused_at, publication_paused_reason, publication_paused_by
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, NULL, NULL, NULL)
        ON CONFLICT(server_id) DO UPDATE SET
            title=excluded.title, subtitle=excluded.subtitle, country=excluded.country,
            city=excluded.city, provider=excluded.provider, host=excluded.host,
            port=excluded.port, protocol=excluded.protocol, transport=excluded.transport,
            client_config_profile=excluded.client_config_profile, status=excluded.status,
            health_score=excluded.health_score, latency_ms=excluded.latency_ms,
            priority=excluded.priority, is_active=excluded.is_active,
            is_public=excluded.is_public, planned_bandwidth_mbps=excluded.planned_bandwidth_mbps,
            reserved_bandwidth_mbps=excluded.reserved_bandwidth_mbps, notes=excluded.notes,
            updated_at=excluded.updated_at, publication_paused_at=NULL,
            publication_paused_reason=NULL, publication_paused_by=NULL
        """,
        (
            server_id, "Netherlands #2", "", "NL", "Amsterdam", "internal-canary",
            host, port, protocol, transport, profile, "healthy", 100, 44,
            priority, 1, 0, 1000, 100, 0, 0, 0, now, notes, now, now,
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
  curl -fsS --max-time 3 http://127.0.0.1:8010/healthz >/dev/null && break
  sleep 0.25
done
systemctl is-active --quiet "${SERVICE_NAME}"

python3 - "${BACKEND_VERSION}" "${NAIVE_SERVER_ID}" "${DNSTT_SERVER_ID}" <<'PY'
import json, sys, urllib.request
version, naive_id, dnstt_id = sys.argv[1:]
def get(path, headers=None):
    request = urllib.request.Request("http://127.0.0.1:8010" + path, headers=headers or {})
    with urllib.request.urlopen(request, timeout=10) as response:
        return json.load(response)
health = get("/healthz")
if health.get("version") != version:
    raise SystemExit("Paid-beta version mismatch after deploy")
legacy = get("/api/v1/catalog/servers")["catalog"]
if any(item.get("id") in {naive_id, dnstt_id} for item in legacy.get("servers") or []):
    raise SystemExit("Naive/dnstt leaked into legacy catalog")
preview = get(
    "/api/v1/catalog/servers?channel=preview&currentVersion=0.3.0-transport-preview.6",
    {"X-GreenVPN-Supported-Protocols": "wireguard_udp,amneziawg,hysteria2,vless_reality,naive_https,dnstt"},
)["catalog"]
matches = {item.get("id"): item for item in preview.get("servers") or [] if item.get("id") in {naive_id, dnstt_id}}
if set(matches) != {naive_id, dnstt_id}:
    raise SystemExit("Naive/dnstt preview catalog rows are missing")
if any(not item.get("clientConfigReady") or not item.get("available") for item in matches.values()):
    raise SystemExit("Naive/dnstt guarded config readiness failed")
default = next((item for item in preview.get("servers") or [] if item.get("id") == preview.get("defaultServerId")), {})
protocol = str(((default.get("protocols") or [{}])[0] or {}).get("code") or "")
if protocol != "wireguard_udp":
    raise SystemExit("Server-side preview default no longer prefers the stable route")
print("paid_beta_health=ok")
print("legacy_naive_dnstt_count=0")
print("preview_naive_dnstt_count=2")
print("server_default_protocol=wireguard_udp")
PY

curl -fsS --max-time 10 http://127.0.0.1:8000/healthz >/dev/null
[[ "$(stat -c '%U:%G:%a' "${LIVE_NAIVE_CONFIG}")" == "root:root:600" ]]
[[ "$(stat -c '%U:%G:%a' "${LIVE_DNSTT_CONFIG}")" == "root:root:600" ]]
printf '%s  %s\n' "${EXPECTED_NAIVE_SHA256,,}" "${LIVE_NAIVE_CONFIG}" | sha256sum -c -
printf '%s  %s\n' "${EXPECTED_DNSTT_SHA256,,}" "${LIVE_DNSTT_CONFIG}" | sha256sum -c -
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
echo "Naive HTTPS and dnstt paid-beta contracts deployed without changing production."
