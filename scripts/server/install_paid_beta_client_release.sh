#!/usr/bin/env bash
set -euo pipefail

APPLY=0
LEAVE_SYNC_STOPPED=0
ROLE=""
ANDROID_APK=""
WINDOWS_EXE=""
ANDROID_VERSION=""
ANDROID_BUILD_NUMBER=""
WINDOWS_VERSION=""
WINDOWS_BUILD_NUMBER=""
ANDROID_SHA256=""
WINDOWS_SHA256=""
ANDROID_REQUIRED=0
WINDOWS_REQUIRED=0

ENV_FILE="/etc/bluevpn/paid-beta.env"
DOWNLOADS="/var/www/paid-beta/downloads"
STATIC_MANIFEST="${DOWNLOADS}/manifest.json"
DB_FILE="/opt/bluevpn-paid-beta/data/bluevpn.db"
SERVICE="greenvpn-paid-beta.service"
SYNC_SERVICE="greenvpn-paid-beta-db-sync.service"
SYNC_TIMER="greenvpn-paid-beta-db-sync.timer"

usage() {
  cat <<'EOF'
Publish Android and Windows clients only to the isolated paid-beta contour.

Required arguments:
  --role timeweb|ruvds
  --android-apk PATH
  --windows-exe PATH
  --android-version VERSION
  --android-build-number NUMBER
  --windows-version VERSION
  --windows-build-number NUMBER
  --android-sha256 SHA256
  --windows-sha256 SHA256

Optional arguments:
  --android-required 0|1       (default: 0)
  --windows-required 0|1       (default: 0)
  --leave-sync-stopped
  --apply

The default is dry-run. Production files, environment, database and service are
never read or changed by this installer.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --role) ROLE="${2:?missing role}"; shift 2 ;;
    --android-apk) ANDROID_APK="${2:?missing Android APK}"; shift 2 ;;
    --windows-exe) WINDOWS_EXE="${2:?missing Windows EXE}"; shift 2 ;;
    --android-version) ANDROID_VERSION="${2:?missing Android version}"; shift 2 ;;
    --android-build-number) ANDROID_BUILD_NUMBER="${2:?missing Android build number}"; shift 2 ;;
    --windows-version) WINDOWS_VERSION="${2:?missing Windows version}"; shift 2 ;;
    --windows-build-number) WINDOWS_BUILD_NUMBER="${2:?missing Windows build number}"; shift 2 ;;
    --android-sha256) ANDROID_SHA256="${2:?missing Android SHA256}"; shift 2 ;;
    --windows-sha256) WINDOWS_SHA256="${2:?missing Windows SHA256}"; shift 2 ;;
    --android-required) ANDROID_REQUIRED="${2:?missing Android required flag}"; shift 2 ;;
    --windows-required) WINDOWS_REQUIRED="${2:?missing Windows required flag}"; shift 2 ;;
    --leave-sync-stopped) LEAVE_SYNC_STOPPED=1; shift ;;
    --apply) APPLY=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
done

case "$ROLE" in
  timeweb) DOWNLOAD_BASE="https://greenvpn.pro/paid-beta/downloads" ;;
  ruvds) DOWNLOAD_BASE="https://176-113-81-35.sslip.io/paid-beta/downloads" ;;
  *) echo "--role must be timeweb or ruvds" >&2; exit 2 ;;
esac

for version in "$ANDROID_VERSION" "$WINDOWS_VERSION"; do
  [[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+[A-Za-z0-9._-]*$ ]] || {
    echo "Invalid version: $version" >&2
    exit 2
  }
done
for number in "$ANDROID_BUILD_NUMBER" "$WINDOWS_BUILD_NUMBER"; do
  [[ "$number" =~ ^[0-9]+$ ]] || { echo "Invalid build number" >&2; exit 2; }
done
for flag in "$ANDROID_REQUIRED" "$WINDOWS_REQUIRED"; do
  [[ "$flag" =~ ^[01]$ ]] || { echo "Required flags must be 0 or 1" >&2; exit 2; }
done

ANDROID_SHA256="${ANDROID_SHA256^^}"
WINDOWS_SHA256="${WINDOWS_SHA256^^}"
[[ "$ANDROID_SHA256" =~ ^[0-9A-F]{64}$ ]] || { echo "Invalid Android SHA256" >&2; exit 2; }
[[ "$WINDOWS_SHA256" =~ ^[0-9A-F]{64}$ ]] || { echo "Invalid Windows SHA256" >&2; exit 2; }
for path in "$ANDROID_APK" "$WINDOWS_EXE" "$ENV_FILE" "$STATIC_MANIFEST" "$DB_FILE"; do
  [[ -f "$path" && ! -L "$path" ]] || { echo "Missing or unsafe file: $path" >&2; exit 2; }
done

actual_android="$(sha256sum "$ANDROID_APK" | awk '{print toupper($1)}')"
actual_windows="$(sha256sum "$WINDOWS_EXE" | awk '{print toupper($1)}')"
[[ "$actual_android" == "$ANDROID_SHA256" ]] || { echo "Android hash mismatch" >&2; exit 2; }
[[ "$actual_windows" == "$WINDOWS_SHA256" ]] || { echo "Windows hash mismatch" >&2; exit 2; }

echo "mode=$([[ $APPLY -eq 1 ]] && echo apply || echo dry-run)"
echo "role=$ROLE"
echo "android_version=$ANDROID_VERSION"
echo "android_build_number=$ANDROID_BUILD_NUMBER"
echo "windows_version=$WINDOWS_VERSION"
echo "windows_build_number=$WINDOWS_BUILD_NUMBER"
echo "android_sha256=$ANDROID_SHA256"
echo "windows_sha256=$WINDOWS_SHA256"
echo "android_required=$ANDROID_REQUIRED"
echo "windows_required=$WINDOWS_REQUIRED"
echo "production_changed=false"
echo "leave_sync_stopped=$LEAVE_SYNC_STOPPED"

[[ $APPLY -eq 1 ]] || exit 0
[[ $EUID -eq 0 ]] || { echo "Run apply mode as root" >&2; exit 1; }
systemctl is-active --quiet "$SERVICE"
curl -fsS --max-time 10 http://127.0.0.1:8010/healthz >/dev/null

timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
released_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
backup_dir="/root/greenvpn-paid-beta-client-release-backups/${timestamp}-${ROLE}-${ANDROID_VERSION}-${WINDOWS_VERSION}"
install -d -m 700 "$backup_dir"
cp -a --reflink=auto "$ENV_FILE" "$backup_dir/paid-beta.env"
cp -a --reflink=auto "$STATIC_MANIFEST" "$backup_dir/manifest.json"
cp -a --reflink=auto "$DOWNLOADS/GreenVPN_Android.apk" "$backup_dir/GreenVPN_Android.previous.apk"
cp -a --reflink=auto "$DOWNLOADS/GreenVPN_Setup.exe" "$backup_dir/GreenVPN_Setup.previous.exe"
chmod 600 "$backup_dir"/*

python3 - "$DB_FILE" "$backup_dir/bluevpn.db" <<'PY'
import pathlib
import sqlite3
import sys

source = sqlite3.connect(f"file:{sys.argv[1]}?mode=ro", uri=True, timeout=60)
target_path = pathlib.Path(sys.argv[2])
target = sqlite3.connect(target_path, timeout=60)
try:
    if source.execute("PRAGMA quick_check").fetchone()[0] != "ok":
        raise SystemExit("source database quick_check failed")
    source.backup(target)
    if target.execute("PRAGMA quick_check").fetchone()[0] != "ok":
        raise SystemExit("backup database quick_check failed")
finally:
    target.close()
    source.close()
target_path.chmod(0o600)
PY

sync_was_active=0
if systemctl is-active --quiet "$SYNC_TIMER"; then
  sync_was_active=1
fi
systemctl stop "$SYNC_TIMER" >/dev/null 2>&1 || true
systemctl stop "$SYNC_SERVICE" >/dev/null 2>&1 || true

aliases_switched=0
state_modified=0
rollback_on_error() {
  code=$?
  trap - ERR
  if [[ $state_modified -eq 1 ]]; then
    systemctl stop "$SERVICE" >/dev/null 2>&1 || true
    cp -a "$backup_dir/paid-beta.env" "$ENV_FILE"
    cp -a "$backup_dir/manifest.json" "$STATIC_MANIFEST"
    python3 - "$backup_dir/bluevpn.db" "$DB_FILE" <<'PY'
import sqlite3
import sys

source = sqlite3.connect(f"file:{sys.argv[1]}?mode=ro", uri=True, timeout=60)
target = sqlite3.connect(sys.argv[2], timeout=60)
try:
    source.backup(target)
    if target.execute("PRAGMA quick_check").fetchone()[0] != "ok":
        raise SystemExit("restored database quick_check failed")
finally:
    target.close()
    source.close()
PY
  fi
  if [[ $aliases_switched -eq 1 ]]; then
    install -m 644 "$backup_dir/GreenVPN_Android.previous.apk" "$DOWNLOADS/GreenVPN_Android.apk"
    install -m 644 "$backup_dir/GreenVPN_Setup.previous.exe" "$DOWNLOADS/GreenVPN_Setup.exe"
  fi
  systemctl restart "$SERVICE" >/dev/null 2>&1 || true
  if [[ $sync_was_active -eq 1 ]]; then
    systemctl restart "$SYNC_TIMER" >/dev/null 2>&1 || true
  fi
  exit "$code"
}
trap rollback_on_error ERR

android_versioned="$DOWNLOADS/GreenVPN_Android_${ANDROID_VERSION}_${ANDROID_BUILD_NUMBER}.apk"
windows_versioned="$DOWNLOADS/GreenVPN_Setup_${WINDOWS_VERSION}_${WINDOWS_BUILD_NUMBER}.exe"
install -m 644 "$ANDROID_APK" "$android_versioned"
install -m 644 "$WINDOWS_EXE" "$windows_versioned"
install -m 644 "$ANDROID_APK" "$DOWNLOADS/.GreenVPN_Android.apk.new"
install -m 644 "$WINDOWS_EXE" "$DOWNLOADS/.GreenVPN_Setup.exe.new"
mv -f "$DOWNLOADS/.GreenVPN_Android.apk.new" "$DOWNLOADS/GreenVPN_Android.apk"
mv -f "$DOWNLOADS/.GreenVPN_Setup.exe.new" "$DOWNLOADS/GreenVPN_Setup.exe"
aliases_switched=1
state_modified=1

python3 - \
  "$ENV_FILE" "$STATIC_MANIFEST" "$DB_FILE" \
  "$ANDROID_APK" "$WINDOWS_EXE" \
  "$ANDROID_VERSION" "$ANDROID_BUILD_NUMBER" "$ANDROID_SHA256" "$ANDROID_REQUIRED" \
  "$WINDOWS_VERSION" "$WINDOWS_BUILD_NUMBER" "$WINDOWS_SHA256" "$WINDOWS_REQUIRED" \
  "$DOWNLOAD_BASE" "$released_at" <<'PY'
import json
import os
import pathlib
import re
import sqlite3
import sys

(
    env_raw,
    manifest_raw,
    db_raw,
    android_raw,
    windows_raw,
    android_version,
    android_build,
    android_sha,
    android_required,
    windows_version,
    windows_build,
    windows_sha,
    windows_required,
    download_base,
    released_at,
) = sys.argv[1:]

env_path = pathlib.Path(env_raw)
manifest_path = pathlib.Path(manifest_raw)
android_path = pathlib.Path(android_raw)
windows_path = pathlib.Path(windows_raw)
assignment = re.compile(r"^(?:export\s+)?([A-Za-z_][A-Za-z0-9_]*)\s*=")
changelog = json.dumps(
    [
        "Бесплатный режим с рекламой и платные функции разделены на сервере.",
        "Режим для выбранных приложений доступен по подписке.",
        "Каталог локаций поддерживает бесплатный и платный доступ.",
    ],
    ensure_ascii=False,
)
updates = {
    "GREENVPN_ANDROID_PAID_BETA_LATEST_VERSION": android_version,
    "GREENVPN_ANDROID_PAID_BETA_UPDATE_URL": f"{download_base}/GreenVPN_Android.apk",
    "GREENVPN_ANDROID_PAID_BETA_UPDATE_SHA256": android_sha,
    "GREENVPN_ANDROID_PAID_BETA_UPDATE_REQUIRED": android_required,
    "GREENVPN_ANDROID_PAID_BETA_UPDATE_RELEASED_AT": released_at,
    "GREENVPN_ANDROID_PAID_BETA_UPDATE_CHANGELOG": changelog,
    "GREENVPN_WINDOWS_PAID_BETA_LATEST_VERSION": windows_version,
    "GREENVPN_WINDOWS_PAID_BETA_UPDATE_URL": f"{download_base}/GreenVPN_Setup.exe",
    "GREENVPN_WINDOWS_PAID_BETA_UPDATE_SHA256": windows_sha,
    "GREENVPN_WINDOWS_PAID_BETA_UPDATE_REQUIRED": windows_required,
    "GREENVPN_WINDOWS_PAID_BETA_UPDATE_RELEASED_AT": released_at,
    "GREENVPN_WINDOWS_PAID_BETA_UPDATE_CHANGELOG": changelog,
}
out = []
for raw in env_path.read_text(encoding="utf-8").splitlines():
    match = assignment.match(raw.strip())
    if match and match.group(1) in updates:
        continue
    out.append(raw)
for key, value in updates.items():
    escaped = str(value).replace("\\", "\\\\").replace('"', '\\"')
    out.append(f'{key}="{escaped}"')
temporary_env = env_path.with_name(env_path.name + ".paid-beta-client-release.tmp")
temporary_env.write_text("\n".join(out) + "\n", encoding="utf-8")
os.chmod(temporary_env, 0o600)
os.replace(temporary_env, env_path)

payload = json.loads(manifest_path.read_text(encoding="utf-8-sig"))
existing = {
    str(item.get("platform") or "").lower(): item
    for item in (payload.get("artifacts") or [])
    if isinstance(item, dict)
}
existing["android"] = {
    "platform": "android",
    "fileName": "GreenVPN_Android.apk",
    "version": android_version,
    "buildNumber": android_build,
    "sizeBytes": android_path.stat().st_size,
    "sha256": android_sha,
    "signed": True,
    "signatureStatus": None,
}
existing["windows"] = {
    "platform": "windows",
    "fileName": "GreenVPN_Setup.exe",
    "version": windows_version,
    "buildNumber": windows_build,
    "sizeBytes": windows_path.stat().st_size,
    "sha256": windows_sha,
    "signed": False,
    "signatureStatus": "NotSigned",
}
payload.update(
    {
        "channel": "paid-beta",
        "isolated": True,
        "productionPublished": False,
        "appVersion": android_version,
        "androidApplicationId": "pro.greenvpn.app.beta",
        "androidAppLabel": "Green VPN Beta",
        "windowsAppVersion": windows_version,
        "generatedAt": released_at,
        "artifacts": [existing["android"], existing["windows"]],
    }
)
temporary_manifest = manifest_path.with_name(manifest_path.name + ".paid-beta-client-release.tmp")
temporary_manifest.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
os.chmod(temporary_manifest, 0o644)
os.replace(temporary_manifest, manifest_path)

conn = sqlite3.connect(db_raw, timeout=60)
try:
    if conn.execute("PRAGMA quick_check").fetchone()[0] != "ok":
        raise SystemExit("pre-update database quick_check failed")
    conn.execute("BEGIN IMMEDIATE")
    for platform, version, build, url, sha, artifact, required in (
        (
            "android",
            android_version,
            android_build,
            f"{download_base}/GreenVPN_Android.apk",
            android_sha,
            android_path,
            int(android_required),
        ),
        (
            "windows",
            windows_version,
            windows_build,
            f"{download_base}/GreenVPN_Setup.exe",
            windows_sha,
            windows_path,
            int(windows_required),
        ),
    ):
        conn.execute(
            """
            UPDATE app_releases
            SET status = 'retired', retired_at = ?, updated_at = ?
            WHERE platform = ? AND channel = 'paid-beta'
              AND status = 'published' AND version <> ?
            """,
            (released_at, released_at, platform, version),
        )
        conn.execute(
            """
            INSERT INTO app_releases(
                platform, channel, version, build_number, download_url, sha256,
                size_bytes, is_required, min_supported_version, rollout_percent,
                changelog_json, status, created_at, updated_at, published_at, retired_at
            )
            VALUES (?, 'paid-beta', ?, ?, ?, ?, ?, ?, '', 100, ?, 'published', ?, ?, ?, NULL)
            ON CONFLICT(platform, channel, version) DO UPDATE SET
                build_number = excluded.build_number,
                download_url = excluded.download_url,
                sha256 = excluded.sha256,
                size_bytes = excluded.size_bytes,
                is_required = excluded.is_required,
                min_supported_version = '',
                rollout_percent = 100,
                changelog_json = excluded.changelog_json,
                status = 'published',
                updated_at = excluded.updated_at,
                published_at = excluded.published_at,
                retired_at = NULL
            """,
            (
                platform,
                version,
                build,
                url,
                sha,
                artifact.stat().st_size,
                required,
                changelog,
                released_at,
                released_at,
                released_at,
            ),
        )
    conn.commit()
    if conn.execute("PRAGMA quick_check").fetchone()[0] != "ok":
        raise SystemExit("post-update database quick_check failed")
except Exception:
    conn.rollback()
    raise
finally:
    conn.close()
PY
chown root:root "$ENV_FILE" "$STATIC_MANIFEST"
chmod 600 "$ENV_FILE"
chmod 644 "$STATIC_MANIFEST"

systemctl restart "$SERVICE"
for _ in $(seq 1 45); do
  curl -fsS --max-time 3 http://127.0.0.1:8010/healthz >/dev/null && break
  sleep 1
done
curl -fsS --max-time 5 http://127.0.0.1:8010/healthz >/dev/null

android_manifest="$(curl -fsS --max-time 20 'http://127.0.0.1:8010/api/v1/updates/manifest?platform=android&channel=paid-beta&currentVersion=0.0.0&clientId=paid-beta-client-release')"
windows_manifest="$(curl -fsS --max-time 20 'http://127.0.0.1:8010/api/v1/updates/manifest?platform=windows&channel=paid-beta&currentVersion=0.0.0&clientId=paid-beta-client-release')"
python3 - \
  "$STATIC_MANIFEST" \
  "$ANDROID_VERSION" "$ANDROID_BUILD_NUMBER" "$ANDROID_SHA256" "$ANDROID_REQUIRED" \
  "$WINDOWS_VERSION" "$WINDOWS_BUILD_NUMBER" "$WINDOWS_SHA256" "$WINDOWS_REQUIRED" \
  "$android_manifest" "$windows_manifest" <<'PY'
import json
import pathlib
import sys

(
    static_raw,
    android_version,
    android_build,
    android_sha,
    android_required,
    windows_version,
    windows_build,
    windows_sha,
    windows_required,
    android_raw,
    windows_raw,
) = sys.argv[1:]
expected = {
    "android": (android_version, android_build, android_sha, android_required == "1", android_raw),
    "windows": (windows_version, windows_build, windows_sha, windows_required == "1", windows_raw),
}
for platform, (version, build, sha, required, raw) in expected.items():
    manifest = json.loads(raw).get("manifest") or {}
    if manifest.get("latestVersion") != version:
        raise SystemExit(f"{platform} API manifest version mismatch")
    if str(manifest.get("buildNumber") or "") != build:
        raise SystemExit(f"{platform} API manifest build mismatch")
    if str(manifest.get("sha256") or "").upper() != sha:
        raise SystemExit(f"{platform} API manifest hash mismatch")
    if manifest.get("required") is not required or manifest.get("fileReady") is not True:
        raise SystemExit(f"{platform} API manifest readiness mismatch")

static = json.loads(pathlib.Path(static_raw).read_text(encoding="utf-8-sig"))
artifacts = {
    str(item.get("platform") or "").lower(): item
    for item in (static.get("artifacts") or [])
    if isinstance(item, dict)
}
for platform, (version, build, sha, _, _) in expected.items():
    artifact = artifacts.get(platform) or {}
    if artifact.get("version") != version or str(artifact.get("buildNumber") or "") != build:
        raise SystemExit(f"{platform} static manifest version mismatch")
    if str(artifact.get("sha256") or "").upper() != sha:
        raise SystemExit(f"{platform} static manifest hash mismatch")
print("android_manifest_ready=true")
print("windows_manifest_ready=true")
print("static_manifest_ready=true")
PY

[[ "$(sha256sum "$DOWNLOADS/GreenVPN_Android.apk" | awk '{print toupper($1)}')" == "$ANDROID_SHA256" ]]
[[ "$(sha256sum "$DOWNLOADS/GreenVPN_Setup.exe" | awk '{print toupper($1)}')" == "$WINDOWS_SHA256" ]]

if [[ $sync_was_active -eq 1 && $LEAVE_SYNC_STOPPED -eq 0 ]]; then
  systemctl restart "$SYNC_TIMER"
fi

trap - ERR
echo "paid_beta_client_release_status=ok"
echo "backup_dir=$backup_dir"
echo "production_changed=false"
echo "sync_timer=$(systemctl is-active "$SYNC_TIMER" 2>/dev/null || true)"
