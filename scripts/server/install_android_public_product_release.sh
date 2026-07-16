#!/usr/bin/env bash
set -euo pipefail

APPLY=0
ROLE=""
PRODUCTION_APK=""
TEST_APK=""
VERSION=""
BUILD_NUMBER=""
PRODUCTION_SHA256=""
TEST_SHA256=""

PRODUCTION_ENV="/etc/bluevpn/backend.env"
TEST_ENV="/etc/bluevpn/paid-beta.env"
PRODUCTION_DOWNLOADS="/var/www/greenvpn/downloads"
TEST_DOWNLOADS="/var/www/paid-beta/downloads"
PRODUCTION_SERVICE="bluevpn-backend.service"
TEST_SERVICE="greenvpn-paid-beta.service"

usage() {
  cat <<'EOF'
Atomically publish matching production and test Android APKs on one RU node.

Required arguments:
  --role timeweb|ruvds
  --production-apk PATH
  --test-apk PATH
  --version VERSION
  --build-number NUMBER
  --production-sha256 SHA256
  --test-sha256 SHA256

The default is dry-run. Apply mode preserves APK/env rollback files, switches
aliases atomically, restarts only local backend services, and verifies both
update manifests before success.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --role) ROLE="${2:?missing role}"; shift 2 ;;
    --production-apk) PRODUCTION_APK="${2:?missing production APK}"; shift 2 ;;
    --test-apk) TEST_APK="${2:?missing test APK}"; shift 2 ;;
    --version) VERSION="${2:?missing version}"; shift 2 ;;
    --build-number) BUILD_NUMBER="${2:?missing build number}"; shift 2 ;;
    --production-sha256) PRODUCTION_SHA256="${2:?missing production SHA256}"; shift 2 ;;
    --test-sha256) TEST_SHA256="${2:?missing test SHA256}"; shift 2 ;;
    --apply) APPLY=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
done

case "$ROLE" in
  timeweb)
    PRODUCTION_URL="https://greenvpn.pro/downloads/GreenVPN_Android.apk"
    TEST_URL="https://greenvpn.pro/paid-beta/downloads/GreenVPN_Android.apk"
    ;;
  ruvds)
    PRODUCTION_URL="https://176-113-81-35.sslip.io/downloads/GreenVPN_Android.apk"
    TEST_URL="https://176-113-81-35.sslip.io/paid-beta/downloads/GreenVPN_Android.apk"
    ;;
  *) echo "--role must be timeweb or ruvds" >&2; exit 2 ;;
esac

[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+[A-Za-z0-9._-]*$ ]] || { echo "Invalid version" >&2; exit 2; }
[[ "$BUILD_NUMBER" =~ ^[0-9]+$ ]] || { echo "Invalid build number" >&2; exit 2; }
PRODUCTION_SHA256="${PRODUCTION_SHA256^^}"
TEST_SHA256="${TEST_SHA256^^}"
[[ "$PRODUCTION_SHA256" =~ ^[0-9A-F]{64}$ ]] || { echo "Invalid production SHA256" >&2; exit 2; }
[[ "$TEST_SHA256" =~ ^[0-9A-F]{64}$ ]] || { echo "Invalid test SHA256" >&2; exit 2; }
for path in "$PRODUCTION_APK" "$TEST_APK" "$PRODUCTION_ENV" "$TEST_ENV"; do
  [[ -f "$path" && ! -L "$path" ]] || { echo "Missing or unsafe file: $path" >&2; exit 2; }
done

actual_production="$(sha256sum "$PRODUCTION_APK" | awk '{print toupper($1)}')"
actual_test="$(sha256sum "$TEST_APK" | awk '{print toupper($1)}')"
[[ "$actual_production" == "$PRODUCTION_SHA256" ]] || { echo "Production APK hash mismatch" >&2; exit 2; }
[[ "$actual_test" == "$TEST_SHA256" ]] || { echo "Test APK hash mismatch" >&2; exit 2; }

echo "mode=$([[ $APPLY -eq 1 ]] && echo apply || echo dry-run)"
echo "role=$ROLE"
echo "version=$VERSION"
echo "build_number=$BUILD_NUMBER"
echo "production_sha256=$PRODUCTION_SHA256"
echo "test_sha256=$TEST_SHA256"
[[ $APPLY -eq 1 ]] || exit 0
[[ $EUID -eq 0 ]] || { echo "Run apply mode as root" >&2; exit 1; }

timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
released_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
backup_dir="/root/greenvpn-apk-release-backups/${timestamp}-${ROLE}-${VERSION}-${BUILD_NUMBER}"
install -d -m 700 "$backup_dir"
cp -a --reflink=auto "$PRODUCTION_ENV" "$backup_dir/backend.env"
cp -a --reflink=auto "$TEST_ENV" "$backup_dir/paid-beta.env"
cp -a --reflink=auto "$PRODUCTION_DOWNLOADS/GreenVPN_Android.apk" "$backup_dir/GreenVPN_Android.production.previous.apk"
cp -a --reflink=auto "$TEST_DOWNLOADS/GreenVPN_Android.apk" "$backup_dir/GreenVPN_Android.test.previous.apk"
chmod 600 "$backup_dir"/*
sha256sum "$backup_dir"/*.apk >"$backup_dir/previous-apk-sha256.txt"
chmod 600 "$backup_dir/previous-apk-sha256.txt"

aliases_switched=0
env_modified=0
rollback_on_error() {
  code=$?
  trap - ERR
  if [[ $aliases_switched -eq 1 ]]; then
    install -m 644 "$backup_dir/GreenVPN_Android.production.previous.apk" "$PRODUCTION_DOWNLOADS/GreenVPN_Android.apk"
    install -m 644 "$backup_dir/GreenVPN_Android.test.previous.apk" "$TEST_DOWNLOADS/GreenVPN_Android.apk"
  fi
  if [[ $env_modified -eq 1 ]]; then
    cp -a "$backup_dir/backend.env" "$PRODUCTION_ENV"
    cp -a "$backup_dir/paid-beta.env" "$TEST_ENV"
  fi
  systemctl restart "$PRODUCTION_SERVICE" >/dev/null 2>&1 || true
  systemctl restart "$TEST_SERVICE" >/dev/null 2>&1 || true
  exit "$code"
}
trap rollback_on_error ERR

production_versioned="$PRODUCTION_DOWNLOADS/GreenVPN_Android_${VERSION}_${BUILD_NUMBER}.apk"
test_versioned="$TEST_DOWNLOADS/GreenVPN_Android_${VERSION}_${BUILD_NUMBER}.apk"
install -m 644 "$PRODUCTION_APK" "$production_versioned"
install -m 644 "$TEST_APK" "$test_versioned"
install -m 644 "$PRODUCTION_APK" "$PRODUCTION_DOWNLOADS/.GreenVPN_Android.apk.new"
install -m 644 "$TEST_APK" "$TEST_DOWNLOADS/.GreenVPN_Android.apk.new"
mv -f "$PRODUCTION_DOWNLOADS/.GreenVPN_Android.apk.new" "$PRODUCTION_DOWNLOADS/GreenVPN_Android.apk"
mv -f "$TEST_DOWNLOADS/.GreenVPN_Android.apk.new" "$TEST_DOWNLOADS/GreenVPN_Android.apk"
aliases_switched=1

python3 - \
  "$PRODUCTION_ENV" "$TEST_ENV" "$VERSION" "$PRODUCTION_URL" "$TEST_URL" \
  "$PRODUCTION_SHA256" "$TEST_SHA256" "$released_at" <<'PY'
import os
import pathlib
import re
import sys

production_path, test_path, version, production_url, test_url, production_sha, test_sha, released_at = sys.argv[1:]
assignment = re.compile(r"^(?:export\s+)?([A-Za-z_][A-Za-z0-9_]*)\s*=")
changelog = (
    f"Green VPN {version}: подписка на 1, 3 или 6 месяцев; управление автопродлением "
    "в настройках; автоматическое защищённое переключение; серверы сгруппированы "
    "по странам; реклама и таймер отключены."
)

def rewrite(path_raw, updates):
    path = pathlib.Path(path_raw)
    out = []
    for raw in path.read_text(encoding="utf-8").splitlines():
        match = assignment.match(raw.strip())
        if match and match.group(1) in updates:
            continue
        out.append(raw)
    for key, value in updates.items():
        escaped = str(value).replace("\\", "\\\\").replace('"', '\\"')
        out.append(f'{key}="{escaped}"')
    temporary = path.with_name(path.name + ".android-release.tmp")
    temporary.write_text("\n".join(out) + "\n", encoding="utf-8")
    os.chmod(temporary, 0o600)
    os.replace(temporary, path)

stable = {
    "GREENVPN_ANDROID_LATEST_VERSION": version,
    "GREENVPN_ANDROID_UPDATE_URL": production_url,
    "GREENVPN_ANDROID_UPDATE_SHA256": production_sha,
    "GREENVPN_ANDROID_UPDATE_REQUIRED": "1",
    "GREENVPN_ANDROID_UPDATE_RELEASED_AT": released_at,
    "GREENVPN_ANDROID_UPDATE_CHANGELOG": changelog,
    "GREENVPN_ANDROID_UPDATE_ROLLOUT": "100",
    "GREENVPN_ANDROID_PREVIEW_LATEST_VERSION": version,
    "GREENVPN_ANDROID_PREVIEW_UPDATE_URL": production_url,
    "GREENVPN_ANDROID_PREVIEW_UPDATE_SHA256": production_sha,
    "GREENVPN_ANDROID_PREVIEW_UPDATE_REQUIRED": "1",
    "GREENVPN_ANDROID_PREVIEW_UPDATE_RELEASED_AT": released_at,
    "GREENVPN_ANDROID_PREVIEW_UPDATE_CHANGELOG": changelog,
    "GREENVPN_ANDROID_PREVIEW_UPDATE_ROLLOUT": "100",
}
paid_beta = {
    **stable,
    "GREENVPN_ANDROID_PAID_BETA_LATEST_VERSION": version,
    "GREENVPN_ANDROID_PAID_BETA_UPDATE_URL": test_url,
    "GREENVPN_ANDROID_PAID_BETA_UPDATE_SHA256": test_sha,
    "GREENVPN_ANDROID_PAID_BETA_UPDATE_REQUIRED": "1",
    "GREENVPN_ANDROID_PAID_BETA_UPDATE_RELEASED_AT": released_at,
    "GREENVPN_ANDROID_PAID_BETA_UPDATE_CHANGELOG": changelog,
}
rewrite(production_path, stable)
rewrite(test_path, paid_beta)
PY
env_modified=1
chown root:root "$PRODUCTION_ENV" "$TEST_ENV"
chmod 600 "$PRODUCTION_ENV" "$TEST_ENV"

systemctl restart "$PRODUCTION_SERVICE"
systemctl restart "$TEST_SERVICE"
for port in 8000 8010; do
  for _ in $(seq 1 45); do
    curl -fsS --max-time 3 "http://127.0.0.1:${port}/healthz" >/dev/null && break
    sleep 1
  done
  curl -fsS --max-time 5 "http://127.0.0.1:${port}/healthz" >/dev/null
done

production_manifest="$(curl -fsS --max-time 20 "http://127.0.0.1:8000/api/v1/updates/manifest?platform=android&channel=stable&currentVersion=0.2.44&clientId=release-install")"
test_manifest="$(curl -fsS --max-time 20 "http://127.0.0.1:8010/api/v1/updates/manifest?platform=android&channel=paid-beta&currentVersion=0.3.0-paid-beta.6&clientId=release-install")"
python3 - "$VERSION" "$PRODUCTION_SHA256" "$TEST_SHA256" "$production_manifest" "$test_manifest" <<'PY'
import json
import sys

version, production_sha, test_sha, production_raw, test_raw = sys.argv[1:]
for label, raw, expected_sha in (
    ("production", production_raw, production_sha),
    ("test", test_raw, test_sha),
):
    manifest = json.loads(raw).get("manifest") or {}
    if manifest.get("latestVersion") != version:
        raise SystemExit(f"{label} manifest version mismatch")
    if str(manifest.get("sha256") or "").upper() != expected_sha:
        raise SystemExit(f"{label} manifest hash mismatch")
    if manifest.get("required") is not True or manifest.get("fileReady") is not True:
        raise SystemExit(f"{label} manifest is not mandatory and ready")
print("production_manifest_ready=true")
print("test_manifest_ready=true")
PY

[[ "$(sha256sum "$PRODUCTION_DOWNLOADS/GreenVPN_Android.apk" | awk '{print toupper($1)}')" == "$PRODUCTION_SHA256" ]]
[[ "$(sha256sum "$TEST_DOWNLOADS/GreenVPN_Android.apk" | awk '{print toupper($1)}')" == "$TEST_SHA256" ]]
trap - ERR
echo "android_release_status=ok"
echo "backup_dir=$backup_dir"
