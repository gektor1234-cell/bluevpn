#!/usr/bin/env bash
set -euo pipefail

APPLY=0
ROLE=""
EXPECTED_PUBLIC_IP=""
BACKEND_FILE=""
EXPECTED_BACKEND_SHA256=""

TIMEWEB_IP="72.56.32.197"
RUVDS_IP="176.113.81.35"
EXPECTED_CURRENT_RELEASE="paid-beta-0.3.0-paid-beta.6-2026071106-r18-naive-dnstt-contract"
RELEASE_ID="paid-beta-0.3.0-paid-beta.6-2026071201-r19-preview-probe-contract"
BACKEND_VERSION="0.9.113-transport-preview.7"
INSTALL_ROOT="/opt/bluevpn-paid-beta"
CURRENT_LINK="${INSTALL_ROOT}/current"
RELEASES_ROOT="${INSTALL_ROOT}/releases"
ENV_FILE="/etc/bluevpn/paid-beta.env"
DB_PATH="${INSTALL_ROOT}/data/bluevpn.db"
SERVICE_NAME="greenvpn-paid-beta.service"
CONFIG_ROOT="/etc/bluevpn/transport_clients"
NAIVE_PROFILE="${CONFIG_ROOT}/nl2-naive-https-canary.naive-https.json"
DNSTT_PROFILE="${CONFIG_ROOT}/nl2-dnstt-canary.dnstt.json"
EXPECTED_NAIVE_SHA256="e6dd56cae8cee7d85043bdef611660560141e543503a48bfdb6783974cc051f7"
EXPECTED_DNSTT_SHA256="a61aa8592a529a2f98b3327b9cce46069c02c9e171d10ab2755cea80dc44f3f7"
BACKUP_ROOT="/root/greenvpn-preview-probe-contract-prechange"

usage() {
  cat <<'USAGE'
Deploy the preview route-probe event contract to one isolated paid-beta control-plane.

  deploy_paid_beta_preview_probe_contract.sh \
    --role timeweb|ruvds \
    --expected-public-ip IP \
    --backend-file /root/stage/main.py \
    --backend-sha256 SHA256 \
    [--apply]

The script changes only a new paid-beta release and paid-beta version env value.
Production, SQLite, transport profiles and VPN nodes are verified but not edited.
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --apply) APPLY=1; shift ;;
    --role) ROLE="${2:?missing role}"; shift 2 ;;
    --expected-public-ip) EXPECTED_PUBLIC_IP="${2:?missing expected public ip}"; shift 2 ;;
    --backend-file) BACKEND_FILE="${2:?missing backend file}"; shift 2 ;;
    --backend-sha256) EXPECTED_BACKEND_SHA256="${2:?missing backend sha256}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
done

case "${ROLE}" in
  timeweb) ROLE_IP="${TIMEWEB_IP}" ;;
  ruvds) ROLE_IP="${RUVDS_IP}" ;;
  *) echo "--role must be timeweb or ruvds" >&2; exit 2 ;;
esac

[[ "${EUID}" -eq 0 ]] || { echo "Run as root." >&2; exit 1; }
for command in curl python3 sha256sum stat systemctl readlink; do
  command -v "${command}" >/dev/null 2>&1 || { echo "Required command missing: ${command}" >&2; exit 1; }
done
PUBLIC_IP="$(curl -fsS --max-time 5 https://api.ipify.org || true)"
if [[ -z "${PUBLIC_IP}" || "${PUBLIC_IP}" != "${ROLE_IP}" || "${EXPECTED_PUBLIC_IP}" != "${ROLE_IP}" ]]; then
  echo "Role/public IP mismatch; refusing deploy." >&2
  exit 1
fi
[[ -f "${BACKEND_FILE}" && ! -L "${BACKEND_FILE}" ]] || { echo "Backend file is missing or symlinked." >&2; exit 1; }
[[ "${EXPECTED_BACKEND_SHA256}" =~ ^[0-9a-fA-F]{64}$ ]] || { echo "Invalid backend SHA-256." >&2; exit 2; }
printf '%s  %s\n' "${EXPECTED_BACKEND_SHA256,,}" "${BACKEND_FILE}" | sha256sum -c -
python3 -m py_compile "${BACKEND_FILE}"

CURRENT_RELEASE="$(readlink -f "${CURRENT_LINK}" 2>/dev/null || true)"
[[ "$(basename "${CURRENT_RELEASE}")" == "${EXPECTED_CURRENT_RELEASE}" ]] || {
  echo "Unexpected current paid-beta release; refusing deploy." >&2
  exit 1
}
[[ -f "${ENV_FILE}" && -f "${DB_PATH}" ]] || { echo "Paid-beta env or DB is missing." >&2; exit 1; }
systemctl is-active --quiet "${SERVICE_NAME}"
[[ "$(stat -c '%U:%G:%a' "${NAIVE_PROFILE}")" == "root:root:600" ]]
[[ "$(stat -c '%U:%G:%a' "${DNSTT_PROFILE}")" == "root:root:600" ]]
printf '%s  %s\n' "${EXPECTED_NAIVE_SHA256}" "${NAIVE_PROFILE}" | sha256sum -c -
printf '%s  %s\n' "${EXPECTED_DNSTT_SHA256}" "${DNSTT_PROFILE}" | sha256sum -c -
python3 - "${DB_PATH}" <<'PY'
import sqlite3, sys
conn = sqlite3.connect(sys.argv[1])
if conn.execute("PRAGMA quick_check").fetchone()[0] != "ok":
    raise SystemExit("SQLite quick_check failed")
conn.close()
PY
python3 - <<'PY'
import json, urllib.request
production = json.load(urllib.request.urlopen("http://127.0.0.1:8000/healthz", timeout=5))
if production.get("version") != "0.9.105":
    raise SystemExit("Production health/version guard failed")
PY

echo "role=${ROLE}"
echo "public_ip=${PUBLIC_IP}"
echo "current_release=$(basename "${CURRENT_RELEASE}")"
echo "target_release=${RELEASE_ID}"
echo "backend_version=${BACKEND_VERSION}"
if [[ "${APPLY}" -ne 1 ]]; then
  echo "dry_run=ok"
  exit 0
fi

RELEASE_DIR="${RELEASES_ROOT}/${RELEASE_ID}"
[[ ! -e "${RELEASE_DIR}" ]] || { echo "Target release already exists; refusing overwrite." >&2; exit 1; }
STAMP="$(date -u +%Y%m%dT%H%M%SZ)"
BACKUP_DIR="${BACKUP_ROOT}/${STAMP}-${ROLE}"
mkdir -p "${BACKUP_DIR}"
chmod 0700 "${BACKUP_ROOT}" "${BACKUP_DIR}"
printf '%s\n' "${CURRENT_RELEASE}" >"${BACKUP_DIR}/current_release.txt"
cp -a -- "${ENV_FILE}" "${BACKUP_DIR}/paid-beta.env.before"
cp -a -- "${DB_PATH}" "${BACKUP_DIR}/bluevpn.db.unchanged"
chmod 0600 "${BACKUP_DIR}/paid-beta.env.before" "${BACKUP_DIR}/bluevpn.db.unchanged"

ROLLBACK_ARMED=1
rollback() {
  rc=$?
  if [[ "${ROLLBACK_ARMED}" -eq 1 ]]; then
    systemctl stop "${SERVICE_NAME}" 2>/dev/null || true
    cp -a -- "${BACKUP_DIR}/paid-beta.env.before" "${ENV_FILE}"
    ln -sfn "${CURRENT_RELEASE}" "${CURRENT_LINK}"
    if [[ -d "${RELEASE_DIR}" && "$(readlink -f "${CURRENT_LINK}" 2>/dev/null)" != "${RELEASE_DIR}" ]]; then
      mv -- "${RELEASE_DIR}" "${BACKUP_DIR}/failed-release"
    fi
    systemctl start "${SERVICE_NAME}" 2>/dev/null || true
  fi
  exit "${rc}"
}
trap rollback ERR

cp -a -- "${CURRENT_RELEASE}" "${RELEASE_DIR}"
install -m 0644 "${BACKEND_FILE}" "${RELEASE_DIR}/backend/app/main.py"
chown root:root "${RELEASE_DIR}/backend/app/main.py"
python3 - "${ENV_FILE}" "${BACKEND_VERSION}" <<'PY'
import os, pathlib, sys
path = pathlib.Path(sys.argv[1])
version = sys.argv[2]
lines = path.read_text(encoding="utf-8").splitlines()
out = []
replaced = False
for line in lines:
    if line.startswith("GREENVPN_BACKEND_VERSION="):
        out.append("GREENVPN_BACKEND_VERSION=" + version)
        replaced = True
    else:
        out.append(line)
if not replaced:
    out.append("GREENVPN_BACKEND_VERSION=" + version)
tmp = path.with_name(path.name + ".preview-probe.tmp")
tmp.write_text("\n".join(out) + "\n", encoding="utf-8")
os.chmod(tmp, 0o600)
os.replace(tmp, path)
PY
chown root:root "${ENV_FILE}"
chmod 0600 "${ENV_FILE}"

ln -sfn "${RELEASE_DIR}" "${CURRENT_LINK}"
systemctl restart "${SERVICE_NAME}"
for _ in $(seq 1 40); do
  curl -fsS --max-time 3 http://127.0.0.1:8010/healthz >/dev/null && break
  sleep 0.25
done
systemctl is-active --quiet "${SERVICE_NAME}"
python3 - "${BACKEND_VERSION}" <<'PY'
import json, sys, urllib.request
version = sys.argv[1]
health = json.load(urllib.request.urlopen("http://127.0.0.1:8010/healthz", timeout=5))
if health.get("version") != version:
    raise SystemExit("Paid-beta version mismatch")
request = urllib.request.Request(
    "http://127.0.0.1:8010/api/v1/catalog/servers?channel=preview&currentVersion=0.3.0-transport-preview.7",
    headers={"X-GreenVPN-Supported-Protocols": "wireguard_udp,amneziawg,hysteria2,vless_reality,naive_https,dnstt"},
)
catalog = json.load(urllib.request.urlopen(request, timeout=10))["catalog"]
expected = {"amneziawg", "hysteria2", "vless_reality", "naive_https", "dnstt"}
seen = {
    str(((item.get("protocols") or [{}])[0] or {}).get("code") or "")
    for item in catalog.get("servers") or []
    if item.get("available") and item.get("clientConfigReady")
}
if not expected.issubset(seen):
    raise SystemExit("Five-stage preview catalog is incomplete")
PY
curl -fsS --max-time 10 http://127.0.0.1:8000/healthz | python3 -c 'import json,sys; assert json.load(sys.stdin).get("version") == "0.9.105"'
printf '%s  %s\n' "${EXPECTED_NAIVE_SHA256}" "${NAIVE_PROFILE}" | sha256sum -c -
printf '%s  %s\n' "${EXPECTED_DNSTT_SHA256}" "${DNSTT_PROFILE}" | sha256sum -c -

ROLLBACK_ARMED=0
trap - ERR
echo "backup=${BACKUP_DIR}"
echo "release=${RELEASE_DIR}"
echo "preview_probe_contract=deployed"
