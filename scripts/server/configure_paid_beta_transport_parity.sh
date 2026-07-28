#!/usr/bin/env bash
set -euo pipefail

APPLY=0
ROLE=""
EXPECTED_BACKEND_VERSION=""
CATALOG_VERSION="2026-07-28-paid-beta-transport-v1"
ENV_FILE="/etc/bluevpn/paid-beta.env"
DB_FILE="/opt/bluevpn-paid-beta/data/bluevpn.db"
SERVICE="greenvpn-paid-beta.service"
BACKUP_ROOT="/root/greenvpn-paid-beta-transport-parity-backups"
TRANSPORT_SERVER_IDS="nl1-awg2-canary,nl1-hysteria2-canary,nl1-vless-reality-xhttp-canary,nl1-naive-https-canary,nl2-awg2-canary,nl2-hysteria2-canary,nl2-vless-reality-xhttp-canary,nl2-naive-https-canary,nl2-dnstt-canary,gb1-awg2-canary,gb1-hysteria2-canary,gb1-vless-reality-xhttp-canary,gb1-naive-https-canary"

usage() {
  cat <<'EOF'
Configure the isolated paid-beta API to expose the reviewed 16-route cascade.

Usage:
  configure_paid_beta_transport_parity.sh \
    --role timeweb|ruvds \
    --expected-backend-version VERSION \
    [--catalog-version VERSION] [--apply]

Default mode is a read-only dry run. Apply mode backs up the protected
paid-beta environment file, changes only catalog visibility/version keys,
restarts only the paid-beta service and rolls back automatically on error.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --role) ROLE="${2:?missing role}"; shift 2 ;;
    --expected-backend-version)
      EXPECTED_BACKEND_VERSION="${2:?missing backend version}"
      shift 2
      ;;
    --catalog-version) CATALOG_VERSION="${2:?missing catalog version}"; shift 2 ;;
    --apply) APPLY=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
done

case "${ROLE}" in
  timeweb) EXPECTED_PUBLIC_IP="72.56.32.197" ;;
  ruvds) EXPECTED_PUBLIC_IP="176.113.81.35" ;;
  *) echo "--role must be timeweb or ruvds" >&2; exit 2 ;;
esac
[[ "${EXPECTED_BACKEND_VERSION}" =~ ^[0-9]+\.[0-9]+\.[0-9]+[A-Za-z0-9._-]*$ ]] || {
  echo "Invalid --expected-backend-version." >&2
  exit 2
}
[[ "${CATALOG_VERSION}" =~ ^[A-Za-z0-9][A-Za-z0-9._-]{4,120}$ ]] || {
  echo "Invalid --catalog-version." >&2
  exit 2
}
[[ "${EUID}" -eq 0 ]] || { echo "Run as root." >&2; exit 1; }
for command in curl python3 stat systemctl; do
  command -v "${command}" >/dev/null 2>&1 || {
    echo "Required command missing: ${command}" >&2
    exit 1
  }
done
[[ -f "${ENV_FILE}" && ! -L "${ENV_FILE}" ]] || {
  echo "Paid-beta environment file is missing or unsafe." >&2
  exit 1
}
[[ -f "${DB_FILE}" && ! -L "${DB_FILE}" ]] || {
  echo "Paid-beta database is missing or unsafe." >&2
  exit 1
}
[[ "$(stat -c '%U:%G:%a' "${ENV_FILE}")" == "root:root:600" ]] || {
  echo "Paid-beta environment ACL is invalid." >&2
  exit 1
}
PUBLIC_IP="$(curl -4fsS --max-time 5 https://api.ipify.org || true)"
[[ "${PUBLIC_IP}" == "${EXPECTED_PUBLIC_IP}" ]] || {
  echo "Role/public-IP guard failed." >&2
  exit 1
}

python3 - "${ENV_FILE}" "${DB_FILE}" "${EXPECTED_BACKEND_VERSION}" <<'PY'
import pathlib
import re
import sqlite3
import sys

env_path, db_path, expected_version = sys.argv[1:]
assignment = re.compile(r"^(?:export\s+)?([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.*)$")
values = {}
for raw in pathlib.Path(env_path).read_text(encoding="utf-8").splitlines():
    match = assignment.match(raw.strip())
    if match:
        values[match.group(1)] = match.group(2).strip().strip('"').strip("'")
if values.get("GREENVPN_BACKEND_VERSION") != expected_version:
    raise SystemExit("paid-beta backend version guard failed")
truthy = {"1", "true", "yes", "on"}
for key in (
    "GREENVPN_FREE_AD_GATE_ENABLED",
    "GREENVPN_FREE_AD_TEST_WEB_ENABLED",
    "GREENVPN_AD_MASTER_ENABLED",
    "GREENVPN_FORCE_DISCONNECT_ENABLED",
    "GREENVPN_AUTO_RENEWAL_CHARGES_ENABLED",
    "GREENVPN_REFUND_EXECUTION_ENABLED",
):
    if values.get(key, "").strip().lower() in truthy:
        raise SystemExit(f"unsafe monetization or disconnect gate is enabled: {key}")

expected_ids = {
    "nl1-awg2-canary",
    "nl1-hysteria2-canary",
    "nl1-vless-reality-xhttp-canary",
    "nl1-naive-https-canary",
    "nl2-awg2-canary",
    "nl2-hysteria2-canary",
    "nl2-vless-reality-xhttp-canary",
    "nl2-naive-https-canary",
    "nl2-dnstt-canary",
    "gb1-awg2-canary",
    "gb1-hysteria2-canary",
    "gb1-vless-reality-xhttp-canary",
    "gb1-naive-https-canary",
}
conn = sqlite3.connect(f"file:{db_path}?mode=ro", uri=True, timeout=30)
try:
    if conn.execute("PRAGMA quick_check").fetchone()[0] != "ok":
        raise SystemExit("paid-beta database quick_check failed")
    rows = conn.execute(
        """
        SELECT server_id, protocol, status, is_active, is_public
        FROM server_catalog_entries
        WHERE server_id IN ({})
        """.format(",".join("?" for _ in expected_ids)),
        sorted(expected_ids),
    ).fetchall()
finally:
    conn.close()
observed_ids = {str(row[0]) for row in rows}
if observed_ids != expected_ids:
    raise SystemExit("paid-beta database lacks the reviewed transport set")
for server_id, protocol, status, is_active, is_public in rows:
    if (
        status != "healthy"
        or int(is_active or 0) != 1
        or int(is_public or 0) != 0
        or protocol not in {
            "amneziawg",
            "hysteria2",
            "vless_reality",
            "naive_https",
            "dnstt",
        }
    ):
        raise SystemExit(f"paid-beta route guard failed: {server_id}")
print("preflight_database_quick_check=ok")
print("preflight_transport_rows=13")
print("dangerous_gates_enabled=false")
PY

echo "role=${ROLE}"
echo "backend_version=${EXPECTED_BACKEND_VERSION}"
echo "catalog_version=${CATALOG_VERSION}"
echo "transport_rows=13"
echo "apply=${APPLY}"
echo "client_artifacts_changed=false"
echo "production_contour_changed=false"
if [[ "${APPLY}" -ne 1 ]]; then
  echo "status=dry-run"
  exit 0
fi

timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
backup_dir="${BACKUP_ROOT}/${timestamp}-${ROLE}-${CATALOG_VERSION}"
install -d -m 0700 "${BACKUP_ROOT}"
[[ ! -e "${backup_dir}" ]] || {
  echo "Backup directory already exists." >&2
  exit 1
}
install -d -m 0700 "${backup_dir}"
install -m 0600 "${ENV_FILE}" "${backup_dir}/paid-beta.env"

rollback_on_error() {
  local exit_code=$?
  trap - ERR
  install -m 0600 "${backup_dir}/paid-beta.env" "${ENV_FILE}" || true
  chown root:root "${ENV_FILE}" || true
  systemctl restart "${SERVICE}" >/dev/null 2>&1 || true
  echo "rollback=restored" >&2
  exit "${exit_code}"
}
trap rollback_on_error ERR

python3 - "${ENV_FILE}" "${TRANSPORT_SERVER_IDS}" "${CATALOG_VERSION}" <<'PY'
import os
import pathlib
import re
import sys

path = pathlib.Path(sys.argv[1])
updates = {
    "GREENVPN_PREVIEW_SERVER_IDS": sys.argv[2],
    "GREENVPN_SERVER_CATALOG_VERSION": sys.argv[3],
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
temporary = path.with_name(path.name + ".transport-parity.tmp")
temporary.write_text("\n".join(out) + "\n", encoding="utf-8")
os.chmod(temporary, 0o600)
os.replace(temporary, path)
PY
chown root:root "${ENV_FILE}"
chmod 0600 "${ENV_FILE}"

systemctl restart "${SERVICE}"
for _ in $(seq 1 60); do
  curl -fsS --max-time 3 http://127.0.0.1:8010/healthz >/dev/null && break
  sleep 1
done
health="$(curl -fsS --max-time 5 http://127.0.0.1:8010/healthz)"
python3 - "${EXPECTED_BACKEND_VERSION}" "${CATALOG_VERSION}" "${health}" <<'PY'
import json
import sys
import urllib.request

expected_backend, expected_catalog, raw_health = sys.argv[1:]
health = json.loads(raw_health)
if health.get("ok") is not True or health.get("version") != expected_backend:
    raise SystemExit("paid-beta health/version verification failed")
request = urllib.request.Request(
    "http://127.0.0.1:8010/api/v1/catalog/servers",
    headers={
        "X-GreenVPN-Release-Channel": "paid-beta",
        "X-GreenVPN-Version": "0.3.16",
        "X-GreenVPN-Supported-Protocols": (
            "wireguard_udp,amneziawg,hysteria2,"
            "vless_reality,naive_https,dnstt"
        ),
    },
)
with urllib.request.urlopen(request, timeout=10) as response:
    payload = json.load(response)
catalog = payload.get("catalog") or {}
servers = catalog.get("servers") or []
counts = {}
for server in servers:
    protocols = server.get("protocols") or []
    code = str((protocols[0] if protocols else {}).get("code") or "")
    counts[code] = counts.get(code, 0) + 1
expected_counts = {
    "wireguard_udp": 3,
    "amneziawg": 3,
    "hysteria2": 3,
    "vless_reality": 3,
    "naive_https": 3,
    "dnstt": 1,
}
if catalog.get("version") != expected_catalog:
    raise SystemExit("paid-beta catalog version verification failed")
if len(servers) != 16 or counts != expected_counts:
    raise SystemExit("paid-beta 16-route catalog verification failed")
print("health_ok=true")
print("catalog_routes=16")
print("catalog_protocol_counts=3,3,3,3,3,1")
PY

trap - ERR
echo "status=applied"
echo "backup_dir=${backup_dir}"
echo "rollback=not_needed"
