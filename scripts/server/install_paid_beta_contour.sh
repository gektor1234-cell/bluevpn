#!/usr/bin/env bash
set -euo pipefail

APPLY=0
CONFIGURE_NGINX=0
START_SYNC=0
STOP_SYNC=0
REPLACE_ENV=0
REMOVE_SEED_ENV=0
ROLE=""
BUNDLE_DIR=""
SEED_ENV=""
PEER_HOST=""
PEER_NAME=""
SYNC_INTERVAL=10

INSTALL_ROOT="/opt/bluevpn-paid-beta"
RELEASES_ROOT="${INSTALL_ROOT}/releases"
CURRENT_LINK="${INSTALL_ROOT}/current"
DATA_DIR="${INSTALL_ROOT}/data"
VENV_DIR="${INSTALL_ROOT}/.venv"
SITE_RELEASES_ROOT="/var/www/greenvpn-paid-beta/releases"
SITE_LINK="/var/www/paid-beta"
ENV_FILE="/etc/bluevpn/paid-beta.env"
SYNC_ENV_FILE="/etc/bluevpn/paid-beta-db-sync.env"
SERVICE_NAME="greenvpn-paid-beta"
SYNC_SERVICE_NAME="greenvpn-paid-beta-db-sync"
SYNC_STATE_DIR="/var/lib/greenvpn-paid-beta-db-sync"
SYNC_SSH_KEY="/root/.ssh/greenvpn_db_sync_ed25519"
BACKUP_ROOT="/root/greenvpn-paid-beta-backups"

usage() {
  cat <<'EOF'
Install or update the isolated Green VPN paid beta contour.

Default mode is dry-run. Production backend, production DB, public downloads
and the main site files are never replaced.

Usage:
  install_paid_beta_contour.sh \
    --role timeweb|ruvds \
    --bundle-dir PATH \
    --peer-host HOST \
    --peer-name NAME \
    [--seed-env PATH] [--replace-env] [--remove-seed-env] \
    [--sync-interval SECONDS] [--configure-nginx] \
    [--start-sync|--stop-sync] [--apply]

The bundle must contain backend/, ops/, site/ and bundle-manifest.json.
The seed env is required on first install and must already contain shared,
root-only beta secrets. The script validates keys without printing values.

Safety:
  - backend binds only to 127.0.0.1:8010;
  - data lives only in /opt/bluevpn-paid-beta/data;
  - beta sync has separate config, timer, scripts and state;
  - Nginx adds only /paid-beta-api/ and /paid-beta/ locations;
  - production health is checked before and after apply;
  - every touched live config is backed up under /root.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --apply)
      APPLY=1
      shift
      ;;
    --configure-nginx)
      CONFIGURE_NGINX=1
      shift
      ;;
    --start-sync)
      START_SYNC=1
      shift
      ;;
    --stop-sync)
      STOP_SYNC=1
      shift
      ;;
    --replace-env)
      REPLACE_ENV=1
      shift
      ;;
    --remove-seed-env)
      REMOVE_SEED_ENV=1
      shift
      ;;
    --role)
      ROLE="${2:?missing role}"
      shift 2
      ;;
    --bundle-dir)
      BUNDLE_DIR="${2:?missing bundle dir}"
      shift 2
      ;;
    --seed-env)
      SEED_ENV="${2:?missing seed env path}"
      shift 2
      ;;
    --peer-host)
      PEER_HOST="${2:?missing peer host}"
      shift 2
      ;;
    --peer-name)
      PEER_NAME="${2:?missing peer name}"
      shift 2
      ;;
    --sync-interval)
      SYNC_INTERVAL="${2:?missing sync interval}"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

case "${ROLE}" in
  timeweb|ruvds) ;;
  *) echo "--role must be timeweb or ruvds" >&2; exit 2 ;;
esac

if [[ -z "${BUNDLE_DIR}" || ! -d "${BUNDLE_DIR}" ]]; then
  echo "Bundle directory not found: ${BUNDLE_DIR:-<empty>}" >&2
  exit 2
fi
if [[ ! "${PEER_HOST}" =~ ^[A-Za-z0-9.-]+$ ]]; then
  echo "Unsafe --peer-host" >&2
  exit 2
fi
if [[ ! "${PEER_NAME}" =~ ^[a-z0-9][a-z0-9_-]{1,63}$ ]]; then
  echo "Unsafe --peer-name" >&2
  exit 2
fi
if [[ ! "${SYNC_INTERVAL}" =~ ^[0-9]+$ ]] || (( SYNC_INTERVAL < 5 || SYNC_INTERVAL > 300 )); then
  echo "--sync-interval must be 5..300 seconds" >&2
  exit 2
fi
if [[ "${START_SYNC}" -eq 1 && "${STOP_SYNC}" -eq 1 ]]; then
  echo "--start-sync and --stop-sync are mutually exclusive" >&2
  exit 2
fi

required_bundle_files=(
  "backend/app/main.py"
  "backend/requirements.txt"
  "ops/greenvpn_db_sync_from_peer.sh"
  "ops/greenvpn_sqlite_snapshot_stdout.py"
  "ops/greenvpn_sqlite_state_sync.py"
  "site/index.html"
  "site/styles.css"
  "site/downloads/GreenVPN_Android.apk"
  "site/downloads/GreenVPN_Setup.exe"
  "site/downloads/manifest.json"
  "bundle-manifest.json"
)
for relative in "${required_bundle_files[@]}"; do
  if [[ ! -f "${BUNDLE_DIR}/${relative}" ]]; then
    echo "Bundle file missing: ${relative}" >&2
    exit 2
  fi
done

RELEASE_ID="$(python3 - "${BUNDLE_DIR}/bundle-manifest.json" <<'PY'
import json, re, sys
with open(sys.argv[1], encoding="utf-8-sig") as fh:
    value = str(json.load(fh).get("releaseId") or "")
if not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9._-]{4,120}", value):
    raise SystemExit("unsafe or missing releaseId")
print(value)
PY
)"
BACKEND_VERSION="$(python3 - "${BUNDLE_DIR}/bundle-manifest.json" <<'PY'
import json, re, sys
with open(sys.argv[1], encoding="utf-8-sig") as fh:
    value = str(json.load(fh).get("backendVersion") or "")
if not re.fullmatch(r"[0-9]+\.[0-9]+\.[0-9]+-paid-beta\.[0-9]+", value):
    raise SystemExit("unsafe or missing paid beta backendVersion")
print(value)
PY
)"

if [[ -n "${SEED_ENV}" && ! -f "${SEED_ENV}" ]]; then
  echo "Seed env not found: ${SEED_ENV}" >&2
  exit 2
fi
if [[ ! -f "${ENV_FILE}" && -z "${SEED_ENV}" ]]; then
  echo "First install requires --seed-env" >&2
  exit 2
fi
if [[ "${REPLACE_ENV}" -eq 1 && -z "${SEED_ENV}" ]]; then
  echo "--replace-env requires --seed-env" >&2
  exit 2
fi
if [[ "${REMOVE_SEED_ENV}" -eq 1 && -z "${SEED_ENV}" ]]; then
  echo "--remove-seed-env requires --seed-env" >&2
  exit 2
fi
if [[ "${REMOVE_SEED_ENV}" -eq 1 ]]; then
  if [[ -L "${SEED_ENV}" ]]; then
    echo "Refusing to remove a symlink seed env" >&2
    exit 2
  fi
  seed_env_real="$(readlink -f -- "${SEED_ENV}")"
  live_env_real="$(readlink -f -- "${ENV_FILE}" 2>/dev/null || printf '%s' "${ENV_FILE}")"
  if [[ "${seed_env_real}" == "${live_env_real}" ]]; then
    echo "Refusing to remove the live beta env" >&2
    exit 2
  fi
  case "${seed_env_real}" in
    /root/greenvpn-paid-beta-stage/*|/run/greenvpn-paid-beta-*) ;;
    *)
      echo "--remove-seed-env accepts only beta staging or /run seed files" >&2
      exit 2
      ;;
  esac
  if [[ "$(stat -c '%U' -- "${SEED_ENV}")" != "root" ]]; then
    echo "Refusing to remove a seed env not owned by root" >&2
    exit 2
  fi
fi

echo "Green VPN paid beta contour plan"
echo "mode=$([[ ${APPLY} -eq 1 ]] && echo apply || echo dry-run)"
echo "role=${ROLE}"
echo "release_id=${RELEASE_ID}"
echo "backend_version=${BACKEND_VERSION}"
echo "bundle_dir=${BUNDLE_DIR}"
echo "backend=127.0.0.1:8010"
echo "data_dir=${DATA_DIR}"
echo "site_link=${SITE_LINK}"
echo "api_path=/paid-beta-api/"
echo "site_path=/paid-beta/"
echo "peer=${PEER_NAME}@${PEER_HOST}"
echo "sync_interval=${SYNC_INTERVAL}"
echo "configure_nginx=${CONFIGURE_NGINX}"
echo "start_sync=${START_SYNC}"
echo "stop_sync=${STOP_SYNC}"
echo "remove_seed_env=${REMOVE_SEED_ENV}"
echo "production_backend_changed=false"
echo "production_db_changed=false"
echo "production_downloads_replaced=false"

if [[ "${APPLY}" -ne 1 ]]; then
  exit 0
fi
if [[ "${EUID}" -ne 0 ]]; then
  echo "Run apply mode as root" >&2
  exit 1
fi
if [[ ! -f "${SYNC_SSH_KEY}" ]]; then
  echo "Beta sync SSH key is missing" >&2
  exit 1
fi
if ! systemctl is-active --quiet bluevpn-backend.service; then
  echo "Production backend is not active; refusing beta deploy" >&2
  exit 1
fi
if ! curl -fsS --max-time 10 http://127.0.0.1:8000/healthz >/dev/null; then
  echo "Production backend health failed; refusing beta deploy" >&2
  exit 1
fi
nginx -t >/dev/null

if ss -lnt | awk '{print $4}' | grep -Eq '(^|:)8010$' && ! systemctl is-active --quiet "${SERVICE_NAME}.service"; then
  echo "Port 8010 is occupied by a non-beta service" >&2
  exit 1
fi
if [[ -e "${CURRENT_LINK}" && ! -L "${CURRENT_LINK}" ]]; then
  echo "Current beta path exists but is not a symlink: ${CURRENT_LINK}" >&2
  exit 1
fi
if [[ -e "${SITE_LINK}" && ! -L "${SITE_LINK}" ]]; then
  echo "Beta site path exists but is not a symlink: ${SITE_LINK}" >&2
  exit 1
fi

timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
backup_dir="${BACKUP_ROOT}/${timestamp}-${ROLE}-${RELEASE_ID}"
install -d -m 700 "${backup_dir}"
for path in \
  "${ENV_FILE}" \
  "${SYNC_ENV_FILE}" \
  "/etc/systemd/system/${SERVICE_NAME}.service" \
  "/etc/systemd/system/${SYNC_SERVICE_NAME}.service" \
  "/etc/systemd/system/${SYNC_SERVICE_NAME}.timer"; do
  if [[ -e "${path}" ]]; then
    cp -a "${path}" "${backup_dir}/"
  fi
done
if [[ -L "${CURRENT_LINK}" ]]; then
  readlink "${CURRENT_LINK}" > "${backup_dir}/previous-current-link.txt"
fi
if [[ -L "${SITE_LINK}" ]]; then
  readlink "${SITE_LINK}" > "${backup_dir}/previous-site-link.txt"
fi

release_dir="${RELEASES_ROOT}/${RELEASE_ID}"
site_release_dir="${SITE_RELEASES_ROOT}/${RELEASE_ID}"
if [[ -e "${release_dir}" || -e "${site_release_dir}" ]]; then
  echo "Release already exists; use a new release id: ${RELEASE_ID}" >&2
  exit 1
fi

install -d -m 755 "${release_dir}/backend/app" "${release_dir}/ops" "${release_dir}/monitoring" "${site_release_dir}"
install -d -m 700 "${DATA_DIR}" "${SYNC_STATE_DIR}"
if [[ ! -d "$(dirname "${ENV_FILE}")" ]]; then
  install -d -m 700 "$(dirname "${ENV_FILE}")"
fi
install -d -m 755 "${RELEASES_ROOT}" "${SITE_RELEASES_ROOT}"
cp -a "${BUNDLE_DIR}/backend/." "${release_dir}/backend/"
cp -a "${BUNDLE_DIR}/ops/." "${release_dir}/ops/"
if [[ -d "${BUNDLE_DIR}/monitoring" ]]; then
  cp -a "${BUNDLE_DIR}/monitoring/." "${release_dir}/monitoring/"
fi
cp -a "${BUNDLE_DIR}/site/." "${site_release_dir}/"
cp -a "${BUNDLE_DIR}/bundle-manifest.json" "${release_dir}/bundle-manifest.json"
chmod 755 "${release_dir}/ops/greenvpn_db_sync_from_peer.sh"
chmod 755 "${release_dir}/ops/greenvpn_sqlite_snapshot_stdout.py"
chmod 755 "${release_dir}/ops/greenvpn_sqlite_state_sync.py"
if [[ -f "${release_dir}/ops/create_paid_beta_first20_package.py" ]]; then
  chmod 755 "${release_dir}/ops/create_paid_beta_first20_package.py"
fi
if [[ -f "${release_dir}/monitoring/service_probe.py" ]]; then
  chmod 755 "${release_dir}/monitoring/service_probe.py"
fi
if [[ -f "${release_dir}/monitoring/install_paid_beta_probe_systemd.sh" ]]; then
  chmod 755 "${release_dir}/monitoring/install_paid_beta_probe_systemd.sh"
fi
find "${site_release_dir}" -type d -exec chmod 755 {} +
find "${site_release_dir}" -type f -exec chmod 644 {} +

if [[ ! -d "${VENV_DIR}" ]]; then
  python3 -m venv "${VENV_DIR}"
fi
"${VENV_DIR}/bin/pip" install --disable-pip-version-check -r "${release_dir}/backend/requirements.txt" >/dev/null

if [[ ! -f "${ENV_FILE}" || "${REPLACE_ENV}" -eq 1 ]]; then
  install -m 600 "${SEED_ENV}" "${ENV_FILE}"
fi
chown root:root "${ENV_FILE}"
chmod 600 "${ENV_FILE}"

python3 - "${ENV_FILE}" "${BACKEND_VERSION}" <<'PY'
import os
import pathlib
import re
import sys

path = pathlib.Path(sys.argv[1])
backend_version = sys.argv[2]
lines = path.read_text(encoding="utf-8").splitlines()
pattern = re.compile(r"^(?:export\s+)?GREENVPN_BACKEND_VERSION\s*=")
out = []
replaced = False
for raw in lines:
    if pattern.match(raw.strip()):
        if not replaced:
            out.append(f"GREENVPN_BACKEND_VERSION={backend_version}")
            replaced = True
        continue
    out.append(raw)
if not replaced:
    out.append(f"GREENVPN_BACKEND_VERSION={backend_version}")
temporary = path.with_name(path.name + ".version.tmp")
temporary.write_text("\n".join(out) + "\n", encoding="utf-8")
os.chmod(temporary, 0o600)
os.replace(temporary, path)
print(f"beta backend version: {backend_version}")
PY
chown root:root "${ENV_FILE}"
chmod 600 "${ENV_FILE}"

python3 - "${ENV_FILE}" "${BUNDLE_DIR}/site/downloads/manifest.json" "${ROLE}" <<'PY'
import json
import os
import pathlib
import re
import sys

env_path = pathlib.Path(sys.argv[1])
manifest_path = pathlib.Path(sys.argv[2])
role = sys.argv[3]
manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
artifacts = {
    str(item.get("platform") or "").strip().lower(): item
    for item in manifest.get("artifacts") or []
    if isinstance(item, dict)
}
android = artifacts.get("android") or {}
windows = artifacts.get("windows") or {}
for platform, artifact in (("android", android), ("windows", windows)):
    version = str(artifact.get("version") or "").strip()
    sha256 = re.sub(r"\s+", "", str(artifact.get("sha256") or "")).upper()
    if "paid-beta" not in version or not re.fullmatch(r"[0-9A-F]{64}", sha256):
        raise SystemExit(f"Invalid {platform} paid beta artifact metadata")

download_base = (
    "https://greenvpn.pro/paid-beta/downloads"
    if role == "timeweb"
    else "https://176-113-81-35.sslip.io/paid-beta/downloads"
)
released_at = str(manifest.get("generatedAt") or "").strip()
updates = {
    "GREENVPN_PAID_BETA_BILLING_PRIMARY": "1" if role == "timeweb" else "0",
    "GREENVPN_REPLICATION_NODE_ID": role,
    "GREENVPN_SQLITE_NODE_ID_BASE": "0" if role == "timeweb" else "1000000000",
    "GREENVPN_ANDROID_PAID_BETA_LATEST_VERSION": str(android["version"]).strip(),
    "GREENVPN_ANDROID_PAID_BETA_UPDATE_URL": f"{download_base}/GreenVPN_Android.apk",
    "GREENVPN_ANDROID_PAID_BETA_UPDATE_SHA256": str(android["sha256"]).strip().upper(),
    "GREENVPN_ANDROID_PAID_BETA_UPDATE_REQUIRED": "0",
    "GREENVPN_ANDROID_PAID_BETA_UPDATE_RELEASED_AT": released_at,
    "GREENVPN_ANDROID_PAID_BETA_UPDATE_CHANGELOG": (
        "Закрытая paid beta: выбор любых установленных приложений для VPN."
    ),
    "GREENVPN_WINDOWS_PAID_BETA_LATEST_VERSION": str(windows["version"]).strip(),
    "GREENVPN_WINDOWS_PAID_BETA_UPDATE_URL": f"{download_base}/GreenVPN_Setup.exe",
    "GREENVPN_WINDOWS_PAID_BETA_UPDATE_SHA256": str(windows["sha256"]).strip().upper(),
    "GREENVPN_WINDOWS_PAID_BETA_UPDATE_REQUIRED": "0",
    "GREENVPN_WINDOWS_PAID_BETA_UPDATE_RELEASED_AT": released_at,
    "GREENVPN_WINDOWS_PAID_BETA_UPDATE_CHANGELOG": (
        "Закрытая paid beta: персональные инвайты и фиксированный тариф."
    ),
}

assignment = re.compile(r"^(?:export\s+)?([A-Za-z_][A-Za-z0-9_]*)\s*=")
out = []
for raw in env_path.read_text(encoding="utf-8").splitlines():
    match = assignment.match(raw.strip())
    if match and match.group(1) in updates:
        continue
    out.append(raw)

safe_value = re.compile(r"^[A-Za-z0-9_./:@+,-]*$")
for key, value in updates.items():
    rendered = value if safe_value.fullmatch(value) else '"' + value.replace("\\", "\\\\").replace('"', '\\"') + '"'
    out.append(f"{key}={rendered}")

temporary = env_path.with_name(env_path.name + ".release.tmp")
temporary.write_text("\n".join(out) + "\n", encoding="utf-8")
os.chmod(temporary, 0o600)
os.replace(temporary, env_path)
print(
    "beta client releases: "
    f"android={updates['GREENVPN_ANDROID_PAID_BETA_LATEST_VERSION']} "
    f"windows={updates['GREENVPN_WINDOWS_PAID_BETA_LATEST_VERSION']} "
    f"role={role}"
)
PY
chown root:root "${ENV_FILE}"
chmod 600 "${ENV_FILE}"

python3 - "${ENV_FILE}" <<'PY'
import os
import pathlib
import re
import sys

path = pathlib.Path(sys.argv[1])
lines = path.read_text(encoding="utf-8").splitlines()
assignment = re.compile(r"^(?:export\s+)?([A-Za-z_][A-Za-z0-9_]*)\s*=")
last_index = {}
for index, raw in enumerate(lines):
    match = assignment.match(raw.strip())
    if match:
        last_index[match.group(1)] = index

out = []
removed = 0
for index, raw in enumerate(lines):
    match = assignment.match(raw.strip())
    if match and last_index[match.group(1)] != index:
        removed += 1
        continue
    out.append(raw)

if removed:
    temporary = path.with_name(path.name + ".dedupe.tmp")
    temporary.write_text("\n".join(out) + "\n", encoding="utf-8")
    os.chmod(temporary, 0o600)
    os.replace(temporary, path)
print(f"beta env dedupe: removed={removed}")
PY
chown root:root "${ENV_FILE}"
chmod 600 "${ENV_FILE}"

python3 - "${ENV_FILE}" "${BACKEND_VERSION}" "${ROLE}" <<'PY'
import pathlib, sys
path = pathlib.Path(sys.argv[1])
backend_version = sys.argv[2]
role = sys.argv[3]
values = {}
for raw in path.read_text(encoding="utf-8").splitlines():
    line = raw.strip()
    if not line or line.startswith("#") or "=" not in line:
        continue
    key, value = line.split("=", 1)
    values[key.strip()] = value.strip().strip("\"'")
expected = {
    "BLUEVPN_BASE_DIR": "/opt/bluevpn-paid-beta/current/backend",
    "BLUEVPN_DATA_DIR": "/opt/bluevpn-paid-beta/data",
    "BLUEVPN_CLIENT_IP_START": "180",
    "BLUEVPN_CLIENT_IP_END": "229",
    "BLUEVPN_SQLITE_ENABLE_WAL": "1",
    "GREENVPN_DISABLE_BUILTIN_WG0_CATALOG": "1",
    "GREENVPN_PAID_BETA_ENABLED": "1",
    "GREENVPN_PAID_BETA_CLIENT_MARKER": "green-vpn-paid-beta-v1",
    "GREENVPN_PAID_BETA_RELEASE_CHANNEL": "paid-beta",
    "GREENVPN_BACKEND_VERSION": backend_version,
    "GREENVPN_REPLICATION_NODE_ID": role,
    "GREENVPN_SQLITE_NODE_ID_BASE": "0" if role == "timeweb" else "1000000000",
    "GREENVPN_PUBLIC_API_BASE_URL": "https://api.greenvpn.pro/paid-beta-api",
    "GREENVPN_PUBLIC_BASE_URL": "https://api.greenvpn.pro/paid-beta-api",
    "GREENVPN_FREE_AD_GATE_ENABLED": "0",
    "GREENVPN_FREE_AD_SESSION_TIMER_ENABLED": "0",
    "GREENVPN_YANDEX_REWARDED_ANDROID_ENABLED": "0",
    "GREENVPN_ADMIN_ALERTS_ENABLED": "0",
}
bad = [key for key, expected_value in expected.items() if values.get(key) != expected_value]
for key in (
    "GREENVPN_AUTH_CODE_PEPPER",
    "GREENVPN_PAID_BETA_INVITE_PEPPER",
    "GREENVPN_ADMIN_2FA_CODE_PEPPER",
):
    if len(values.get(key, "")) < 24:
        bad.append(key)
if bad:
    print("Invalid beta env keys: " + ", ".join(sorted(set(bad))), file=sys.stderr)
    raise SystemExit(2)
print("beta env validation: ok")
PY

ln -sfn "${release_dir}" "${CURRENT_LINK}"
ln -sfn "${site_release_dir}" "${SITE_LINK}"

cat > "/etc/systemd/system/${SERVICE_NAME}.service" <<EOF
[Unit]
Description=Green VPN isolated paid beta backend
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=root
WorkingDirectory=${CURRENT_LINK}/backend
EnvironmentFile=${ENV_FILE}
ExecStart=${VENV_DIR}/bin/uvicorn app.main:app --host 127.0.0.1 --port 8010
Restart=always
RestartSec=2
UMask=0077
PrivateTmp=true
NoNewPrivileges=true

[Install]
WantedBy=multi-user.target
EOF

cat > "${SYNC_ENV_FILE}" <<EOF
GREENVPN_DB_SYNC_PEER_HOST=${PEER_HOST}
GREENVPN_DB_SYNC_PEER_NAME=${PEER_NAME}
GREENVPN_DB_SYNC_TARGET_DB=${DATA_DIR}/bluevpn.db
GREENVPN_DB_SYNC_STATE_DIR=${SYNC_STATE_DIR}
GREENVPN_DB_SYNC_APPLY=1
GREENVPN_DB_SYNC_SSH_KEY=${SYNC_SSH_KEY}
GREENVPN_DB_SYNC_REMOTE_SNAPSHOT_ENV_FILE=${ENV_FILE}
GREENVPN_DB_SYNC_REMOTE_SNAPSHOT_SCRIPT=${CURRENT_LINK}/ops/greenvpn_sqlite_snapshot_stdout.py
GREENVPN_DB_SYNC_LOCAL_STATE_SYNC_SCRIPT=${CURRENT_LINK}/ops/greenvpn_sqlite_state_sync.py
GREENVPN_DB_SYNC_SNAPSHOT_COMPRESSION=gzip
EOF
chmod 600 "${SYNC_ENV_FILE}"

cat > "/etc/systemd/system/${SYNC_SERVICE_NAME}.service" <<EOF
[Unit]
Description=Green VPN paid beta SQLite state sync from peer
Wants=network-online.target ${SERVICE_NAME}.service
After=network-online.target ${SERVICE_NAME}.service

[Service]
Type=oneshot
Environment=GREENVPN_DB_SYNC_CONF=${SYNC_ENV_FILE}
ExecStart=${CURRENT_LINK}/ops/greenvpn_db_sync_from_peer.sh
Nice=5
IOSchedulingClass=best-effort
IOSchedulingPriority=6
PrivateTmp=true
NoNewPrivileges=true
EOF

cat > "/etc/systemd/system/${SYNC_SERVICE_NAME}.timer" <<EOF
[Unit]
Description=Run Green VPN paid beta DB sync every ${SYNC_INTERVAL} seconds

[Timer]
OnBootSec=30s
OnUnitActiveSec=${SYNC_INTERVAL}s
AccuracySec=2s
Unit=${SYNC_SERVICE_NAME}.service
Persistent=false

[Install]
WantedBy=timers.target
EOF

configure_nginx() {
  local api_snippet="/etc/nginx/snippets/greenvpn-paid-beta-api.conf"
  local site_snippet="/etc/nginx/snippets/greenvpn-paid-beta-site.conf"
  install -d -m 755 /etc/nginx/snippets

  cat > "${api_snippet}" <<'EOF'
location = /paid-beta-api {
    return 308 /paid-beta-api/;
}

location /paid-beta-api/ {
    proxy_pass http://127.0.0.1:8010/;
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto https;
    proxy_set_header X-Forwarded-Prefix /paid-beta-api;
    proxy_http_version 1.1;
    proxy_set_header Connection "";
    proxy_connect_timeout 10s;
    proxy_send_timeout 60s;
    proxy_read_timeout 60s;
    client_max_body_size 1m;
    # Green VPN API security headers
    add_header Cache-Control "no-store" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header Strict-Transport-Security "max-age=31536000" always;
    add_header Referrer-Policy "no-referrer" always;
    add_header X-Frame-Options "DENY" always;
    add_header Content-Security-Policy "default-src 'none'; base-uri 'none'; frame-ancestors 'none'" always;
    add_header Permissions-Policy "camera=(), microphone=(), geolocation=(), payment=()" always;
    add_header X-Robots-Tag "noindex, nofollow, noarchive" always;
}

# Green VPN YooKassa recurring-payment review
location = /yookassa-review-20260711 {
    return 302 /yookassa-review-20260711/;
}

location ^~ /yookassa-review-20260711/ {
    root /var/www/paid-beta;
    index index.html;
    try_files $uri $uri/ =404;
    autoindex off;
    # Green VPN public security headers
    add_header Cache-Control "private, no-store" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header Referrer-Policy "strict-origin-when-cross-origin" always;
    add_header Strict-Transport-Security "max-age=31536000" always;
    add_header X-Frame-Options "DENY" always;
    add_header Content-Security-Policy "default-src 'self'; style-src 'self' 'unsafe-inline'; img-src 'self' data:; object-src 'none'; base-uri 'self'; form-action 'self'; frame-ancestors 'none'" always;
    add_header Permissions-Policy "camera=(), microphone=(), geolocation=(), payment=()" always;
    add_header X-Robots-Tag "noindex, nofollow, noarchive" always;
}
EOF

  cat > "${site_snippet}" <<'EOF'
location = /paid-beta {
    return 302 /paid-beta/;
}

location /paid-beta/ {
    root /var/www;
    index index.html;
    try_files $uri $uri/ =404;
    autoindex off;
    # Green VPN public security headers
    add_header Cache-Control "private, no-store" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header Referrer-Policy "strict-origin-when-cross-origin" always;
    add_header Strict-Transport-Security "max-age=31536000" always;
    add_header X-Frame-Options "DENY" always;
    add_header Content-Security-Policy "default-src 'self'; style-src 'self' 'unsafe-inline'; img-src 'self' data:; object-src 'none'; base-uri 'self'; form-action 'self'; frame-ancestors 'none'" always;
    add_header Permissions-Policy "camera=(), microphone=(), geolocation=(), payment=()" always;
    add_header X-Robots-Tag "noindex, nofollow, noarchive" always;
}
EOF
  chmod 644 "${api_snippet}" "${site_snippet}"

  inject_include() {
    local config="$1"
    local anchor="$2"
    shift 2
    cp -a "${config}" "${backup_dir}/$(basename "${config}").pre-beta"
    python3 - "${config}" "${anchor}" "$@" <<'PY'
import pathlib, sys
path = pathlib.Path(sys.argv[1])
anchor = sys.argv[2]
includes = list(sys.argv[3:])
text = path.read_text(encoding="utf-8")
missing = [line for line in includes if line not in text]
if not missing:
    raise SystemExit(0)
if text.count(anchor) != 1:
    print(f"Expected one Nginx anchor in {path}, found {text.count(anchor)}", file=sys.stderr)
    raise SystemExit(2)
replacement = anchor + "\n\n" + "\n".join(missing)
path.write_text(text.replace(anchor, replacement, 1), encoding="utf-8")
PY
  }

  if [[ "${ROLE}" == "timeweb" ]]; then
    inject_include \
      /etc/nginx/sites-available/greenvpn-api \
      '    error_log /var/log/nginx/greenvpn-api.error.log warn;' \
      '    include /etc/nginx/snippets/greenvpn-paid-beta-api.conf;'
    inject_include \
      /etc/nginx/sites-available/greenvpn-site \
      '    add_header Referrer-Policy "strict-origin-when-cross-origin" always;' \
      '    include /etc/nginx/snippets/greenvpn-paid-beta-site.conf;'
  else
    inject_include \
      /etc/nginx/sites-available/greenvpn-ruvds-m9-api \
      '    error_log /var/log/nginx/greenvpn-ruvds-m9.error.log warn;' \
      '    include /etc/nginx/snippets/greenvpn-paid-beta-api.conf;' \
      '    include /etc/nginx/snippets/greenvpn-paid-beta-site.conf;'
  fi

  if ! nginx -t; then
    echo "Nginx validation failed; restoring config backup" >&2
    if [[ "${ROLE}" == "timeweb" ]]; then
      cp -a "${backup_dir}/greenvpn-api.pre-beta" /etc/nginx/sites-available/greenvpn-api
      cp -a "${backup_dir}/greenvpn-site.pre-beta" /etc/nginx/sites-available/greenvpn-site
    else
      cp -a "${backup_dir}/greenvpn-ruvds-m9-api.pre-beta" /etc/nginx/sites-available/greenvpn-ruvds-m9-api
    fi
    nginx -t
    return 1
  fi
  systemctl reload nginx
}

systemctl daemon-reload
systemctl enable "${SERVICE_NAME}.service"
systemctl restart "${SERVICE_NAME}.service"

for _ in $(seq 1 30); do
  if curl -fsS --max-time 3 http://127.0.0.1:8010/healthz >/dev/null; then
    break
  fi
  sleep 1
done
if ! curl -fsS --max-time 5 http://127.0.0.1:8010/healthz >/dev/null; then
  journalctl -u "${SERVICE_NAME}.service" -n 40 --no-pager >&2 || true
  echo "Paid beta backend failed local health" >&2
  exit 1
fi

if [[ "${CONFIGURE_NGINX}" -eq 1 ]]; then
  configure_nginx
fi
if [[ "${START_SYNC}" -eq 1 ]]; then
  systemctl enable "${SYNC_SERVICE_NAME}.timer"
  systemctl restart "${SYNC_SERVICE_NAME}.timer"
  systemctl start "${SYNC_SERVICE_NAME}.service"
elif [[ "${STOP_SYNC}" -eq 1 ]]; then
  systemctl disable --now "${SYNC_SERVICE_NAME}.timer" >/dev/null 2>&1 || true
fi

if ! systemctl is-active --quiet bluevpn-backend.service; then
  echo "Production backend stopped during beta deploy" >&2
  exit 1
fi
if ! curl -fsS --max-time 10 http://127.0.0.1:8000/healthz >/dev/null; then
  echo "Production backend health failed after beta deploy" >&2
  exit 1
fi

echo "paid_beta_backend=active"
echo "paid_beta_local_health=ok"
echo "production_backend=active"
echo "production_local_health=ok"
echo "backup_dir=${backup_dir}"
echo "release_dir=${release_dir}"
echo "site_release_dir=${site_release_dir}"
echo "sync_timer=$(systemctl is-active "${SYNC_SERVICE_NAME}.timer" 2>/dev/null || true)"

if [[ "${REMOVE_SEED_ENV}" -eq 1 ]]; then
  if command -v shred >/dev/null 2>&1; then
    shred -u -- "${SEED_ENV}"
  else
    rm -f -- "${SEED_ENV}"
  fi
  echo "seed_env_removed=true"
fi
