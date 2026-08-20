#!/usr/bin/env bash
set -euo pipefail

APPLY=0
ROLE=""
APK=""
VERSION=""
BUILD_NUMBER=""
SHA256=""
REQUIRED=0
MIN_SUPPORTED_VERSION=""

ENV_FILE="/etc/bluevpn/backend.env"
DOWNLOADS="/var/www/greenvpn/downloads"
SERVICE="bluevpn-backend.service"
DATABASE="/opt/bluevpn/backend/data/bluevpn.db"

usage() {
  cat <<'EOF'
Atomically publish one Android stable APK on one production control plane.

Required arguments:
  --role timeweb|ruvds
  --apk PATH
  --version VERSION
  --build-number NUMBER
  --sha256 SHA256

Optional arguments:
  --required 0|1  (default: 0)
  --min-supported-version VERSION
  --apply

The default is dry-run. Apply mode preserves rollback files, switches only the
stable Android alias, updates only the production environment and stable
release row, restarts only the production backend, and leaves paid-beta intact.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --role) ROLE="${2:?missing role}"; shift 2 ;;
    --apk) APK="${2:?missing APK}"; shift 2 ;;
    --version) VERSION="${2:?missing version}"; shift 2 ;;
    --build-number) BUILD_NUMBER="${2:?missing build number}"; shift 2 ;;
    --sha256) SHA256="${2:?missing SHA256}"; shift 2 ;;
    --required) REQUIRED="${2:?missing required flag}"; shift 2 ;;
    --min-supported-version) MIN_SUPPORTED_VERSION="${2:?missing minimum version}"; shift 2 ;;
    --apply) APPLY=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
done

case "$ROLE" in
  timeweb) DOWNLOAD_URL="https://greenvpn.pro/downloads/GreenVPN_Android.apk" ;;
  ruvds) DOWNLOAD_URL="https://176-113-81-35.sslip.io/downloads/GreenVPN_Android.apk" ;;
  *) echo "--role must be timeweb or ruvds" >&2; exit 2 ;;
esac

[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+[A-Za-z0-9._-]*$ ]] || {
  echo "Invalid version" >&2
  exit 2
}
[[ "$BUILD_NUMBER" =~ ^[0-9]+$ ]] || {
  echo "Invalid build number" >&2
  exit 2
}
[[ "$REQUIRED" =~ ^[01]$ ]] || {
  echo "Invalid required flag" >&2
  exit 2
}
if [[ "$REQUIRED" == "1" ]]; then
  [[ "$MIN_SUPPORTED_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+[A-Za-z0-9._+-]*$ ]] || {
    echo "Mandatory release requires a valid minimum supported version" >&2
    exit 2
  }
elif [[ -n "$MIN_SUPPORTED_VERSION" ]]; then
  echo "Minimum supported version is only valid for a mandatory release" >&2
  exit 2
fi
SHA256="${SHA256^^}"
[[ "$SHA256" =~ ^[0-9A-F]{64}$ ]] || {
  echo "Invalid SHA256" >&2
  exit 2
}

for path in "$APK" "$ENV_FILE" "$DATABASE"; do
  [[ -f "$path" && ! -L "$path" ]] || {
    echo "Missing or unsafe file: $path" >&2
    exit 2
  }
done
[[ -d "$DOWNLOADS" && ! -L "$DOWNLOADS" ]] || {
  echo "Missing or unsafe downloads directory: $DOWNLOADS" >&2
  exit 2
}
[[ -f "$DOWNLOADS/GreenVPN_Android.apk" && ! -L "$DOWNLOADS/GreenVPN_Android.apk" ]] || {
  echo "Missing or unsafe current stable APK" >&2
  exit 2
}

actual_sha256="$(sha256sum "$APK" | awk '{print toupper($1)}')"
[[ "$actual_sha256" == "$SHA256" ]] || {
  echo "APK hash mismatch" >&2
  exit 2
}

echo "mode=$([[ $APPLY -eq 1 ]] && echo apply || echo dry-run)"
echo "role=$ROLE"
echo "version=$VERSION"
echo "build_number=$BUILD_NUMBER"
echo "sha256=$SHA256"
echo "size_bytes=$(stat -c %s "$APK")"
echo "required=$REQUIRED"
echo "min_supported_version=$MIN_SUPPORTED_VERSION"
[[ $APPLY -eq 1 ]] || exit 0
[[ $EUID -eq 0 ]] || {
  echo "Run apply mode as root" >&2
  exit 1
}

timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
released_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
backup_dir="/root/greenvpn-android-stable-release-backups/${timestamp}-${ROLE}-${VERSION}-${BUILD_NUMBER}"
versioned_apk="$DOWNLOADS/GreenVPN_Android_${VERSION}_${BUILD_NUMBER}.apk"
install -d -m 700 "$backup_dir"
cp -a --reflink=auto "$ENV_FILE" "$backup_dir/backend.env"
cp -a --reflink=auto \
  "$DOWNLOADS/GreenVPN_Android.apk" \
  "$backup_dir/GreenVPN_Android.previous.apk"
chmod 600 "$backup_dir"/*
sha256sum "$backup_dir/GreenVPN_Android.previous.apk" >"$backup_dir/previous-apk-sha256.txt"
chmod 600 "$backup_dir/previous-apk-sha256.txt"

python3 - "$DATABASE" "$backup_dir/production.db" <<'PY'
import sqlite3
import sys

source_raw, target_raw = sys.argv[1:]
source = sqlite3.connect(source_raw, timeout=60)
target = sqlite3.connect(target_raw)
try:
    if source.execute("PRAGMA quick_check").fetchone()[0] != "ok":
        raise SystemExit("source database quick_check failed")
    source.backup(target)
    if target.execute("PRAGMA quick_check").fetchone()[0] != "ok":
        raise SystemExit("backup database quick_check failed")
finally:
    target.close()
    source.close()
PY
chmod 600 "$backup_dir/production.db"

alias_switched=0
env_modified=0
db_modified=0
rollback_on_error() {
  code=$?
  trap - ERR
  if [[ $db_modified -eq 1 ]]; then
    systemctl stop "$SERVICE" >/dev/null 2>&1 || true
    python3 - "$backup_dir/production.db" "$DATABASE" <<'PY'
import sqlite3
import sys

source_raw, target_raw = sys.argv[1:]
source = sqlite3.connect(f"file:{source_raw}?mode=ro", uri=True, timeout=60)
target = sqlite3.connect(target_raw, timeout=60)
try:
    source.backup(target)
    if target.execute("PRAGMA quick_check").fetchone()[0] != "ok":
        raise SystemExit("database restore quick_check failed")
finally:
    target.close()
    source.close()
PY
  fi
  if [[ $alias_switched -eq 1 ]]; then
    install -m 644 \
      "$backup_dir/GreenVPN_Android.previous.apk" \
      "$DOWNLOADS/GreenVPN_Android.apk"
  fi
  if [[ $env_modified -eq 1 ]]; then
    cp -a "$backup_dir/backend.env" "$ENV_FILE"
  fi
  systemctl restart "$SERVICE" >/dev/null 2>&1 || true
  exit "$code"
}
trap rollback_on_error ERR

install -m 644 "$APK" "$versioned_apk"
install -m 644 "$APK" "$DOWNLOADS/.GreenVPN_Android.apk.new"
mv -f "$DOWNLOADS/.GreenVPN_Android.apk.new" "$DOWNLOADS/GreenVPN_Android.apk"
alias_switched=1

python3 - \
  "$ENV_FILE" "$VERSION" "$DOWNLOAD_URL" "$SHA256" "$REQUIRED" \
  "$MIN_SUPPORTED_VERSION" "$released_at" <<'PY'
import os
import pathlib
import re
import sys

(
    path_raw,
    version,
    download_url,
    sha256,
    required,
    min_supported_version,
    released_at,
) = sys.argv[1:]
path = pathlib.Path(path_raw)
assignment = re.compile(r"^(?:export\s+)?([A-Za-z_][A-Za-z0-9_]*)\s*=")
updates = {
    "GREENVPN_ANDROID_LATEST_VERSION": version,
    "GREENVPN_ANDROID_UPDATE_URL": download_url,
    "GREENVPN_ANDROID_UPDATE_SHA256": sha256,
    "GREENVPN_ANDROID_UPDATE_REQUIRED": required,
    "GREENVPN_ANDROID_MIN_SUPPORTED_VERSION": min_supported_version,
    "GREENVPN_ANDROID_UPDATE_RELEASED_AT": released_at,
    "GREENVPN_ANDROID_UPDATE_CHANGELOG": (
        f"Green VPN {version}: режим выбранных приложений, улучшенная диагностика "
        "и обязательное безопасное обновление."
    ),
    "GREENVPN_ANDROID_UPDATE_ROLLOUT": "100",
}
out = []
for raw in path.read_text(encoding="utf-8").splitlines():
    match = assignment.match(raw.strip())
    if match and match.group(1) in updates:
        continue
    out.append(raw)
for key, value in updates.items():
    escaped = str(value).replace("\\", "\\\\").replace('"', '\\"')
    out.append(f'{key}="{escaped}"')
temporary = path.with_name(path.name + ".android-stable-release.tmp")
temporary.write_text("\n".join(out) + "\n", encoding="utf-8")
os.chmod(temporary, 0o600)
os.replace(temporary, path)
PY
env_modified=1
chown root:root "$ENV_FILE"
chmod 600 "$ENV_FILE"

db_modified=1
python3 - \
  "$DATABASE" "$VERSION" "$BUILD_NUMBER" "$DOWNLOAD_URL" "$SHA256" \
  "$APK" "$REQUIRED" "$MIN_SUPPORTED_VERSION" "$released_at" <<'PY'
import json
import pathlib
import sqlite3
import sys

(
    database,
    version,
    build_number,
    download_url,
    sha256,
    apk_raw,
    required_raw,
    min_supported_version,
    released_at,
) = sys.argv[1:]
apk = pathlib.Path(apk_raw)
required = 1 if required_raw == "1" else 0
changelog = json.dumps(
    [
        "Добавлен режим VPN только для выбранных приложений и сайтов.",
        "Улучшена диагностика активного подключения.",
        "Обновление приложения теперь нельзя пропустить, когда оно обязательное.",
    ],
    ensure_ascii=False,
)
conn = sqlite3.connect(database, timeout=60)
try:
    if conn.execute("PRAGMA quick_check").fetchone()[0] != "ok":
        raise SystemExit(f"pre-update quick_check failed: {database}")
    conn.execute("BEGIN IMMEDIATE")
    conn.execute(
        """
        UPDATE app_releases
        SET status = 'retired', retired_at = ?, updated_at = ?
        WHERE platform = 'android' AND channel = 'stable'
          AND status = 'published' AND version <> ?
        """,
        (released_at, released_at, version),
    )
    conn.execute(
        """
        INSERT INTO app_releases(
            platform, channel, version, build_number, download_url, sha256,
            size_bytes, is_required, min_supported_version, rollout_percent,
            changelog_json, status, created_at, updated_at, published_at, retired_at
        )
        VALUES ('android', 'stable', ?, ?, ?, ?, ?, ?, ?, 100, ?,
                'published', ?, ?, ?, NULL)
        ON CONFLICT(platform, channel, version) DO UPDATE SET
            build_number = excluded.build_number,
            download_url = excluded.download_url,
            sha256 = excluded.sha256,
            size_bytes = excluded.size_bytes,
            is_required = excluded.is_required,
            min_supported_version = excluded.min_supported_version,
            rollout_percent = 100,
            changelog_json = excluded.changelog_json,
            status = 'published',
            updated_at = excluded.updated_at,
            published_at = excluded.published_at,
            retired_at = NULL
        """,
        (
            version,
            build_number,
            download_url,
            sha256,
            apk.stat().st_size,
            required,
            min_supported_version,
            changelog,
            released_at,
            released_at,
            released_at,
        ),
    )
    conn.commit()
    if conn.execute("PRAGMA quick_check").fetchone()[0] != "ok":
        raise SystemExit(f"post-update quick_check failed: {database}")
except Exception:
    conn.rollback()
    raise
finally:
    conn.close()
PY

systemctl restart "$SERVICE"
ready=0
for _ in $(seq 1 90); do
  if curl -fsS --max-time 3 "http://127.0.0.1:8000/healthz" >/dev/null; then
    ready=1
    break
  fi
  sleep 1
done
[[ $ready -eq 1 ]]

stable_manifest="$(
  curl -fsS --max-time 20 \
    "http://127.0.0.1:8000/api/v1/updates/manifest?platform=android&channel=stable&currentVersion=0.0.0&clientId=stable-release"
)"
public_product_manifest="$(
  curl -fsS --max-time 20 \
    "http://127.0.0.1:8000/api/v1/updates/manifest?platform=android&channel=public-product&currentVersion=0.0.0&clientId=stable-release"
)"
python3 - \
  "$VERSION" "$BUILD_NUMBER" "$SHA256" "$REQUIRED" "$MIN_SUPPORTED_VERSION" \
  "$stable_manifest" "$public_product_manifest" <<'PY'
import json
import sys

(
    version,
    build_number,
    sha256,
    required_raw,
    min_supported_version,
    stable_raw,
    public_product_raw,
) = sys.argv[1:]
required = required_raw == "1"
for label, raw in (("stable", stable_raw), ("public-product", public_product_raw)):
    manifest = json.loads(raw).get("manifest") or {}
    if manifest.get("latestVersion") != version:
        raise SystemExit(f"{label} manifest version mismatch")
    if str(manifest.get("buildNumber") or "") != build_number:
        raise SystemExit(f"{label} manifest build mismatch")
    if str(manifest.get("sha256") or "").upper() != sha256:
        raise SystemExit(f"{label} manifest hash mismatch")
    if manifest.get("required") is not required:
        raise SystemExit(f"{label} manifest required flag mismatch")
    if str(manifest.get("minSupportedVersion") or "") != min_supported_version:
        raise SystemExit(f"{label} manifest minimum version mismatch")
    if manifest.get("fileReady") is not True:
        raise SystemExit(f"{label} manifest readiness mismatch")
print("stable_manifest_ready=true")
print("public_product_manifest_ready=true")
PY

if [[ "$REQUIRED" == "1" ]]; then
  blocked_status="$(curl -sS --max-time 10 -o /dev/null -w '%{http_code}' \
    -H 'X-GreenVPN-Platform: android' \
    -H 'X-GreenVPN-Version: 0.0.0' \
    -H 'X-GreenVPN-Release-Channel: stable' \
    'http://127.0.0.1:8000/api/v1/catalog/servers')"
  [[ "$blocked_status" == "426" ]]
fi

[[ "$(sha256sum "$DOWNLOADS/GreenVPN_Android.apk" | awk '{print toupper($1)}')" == "$SHA256" ]]
[[ "$(stat -c %s "$DOWNLOADS/GreenVPN_Android.apk")" == "$(stat -c %s "$APK")" ]]
trap - ERR
echo "android_stable_release_status=ok"
echo "backup_dir=$backup_dir"
