#!/usr/bin/env bash
set -euo pipefail

APPLY=0
ROLE=""
PRODUCTION_EXE=""
TEST_EXE=""
VERSION=""
TEST_VERSION=""
BUILD_NUMBER=""
PRODUCTION_SHA256=""
TEST_SHA256=""
PRODUCTION_REQUIRED=1
TEST_REQUIRED=0
PRODUCTION_SIGNATURE_REPORT=""
TEST_SIGNATURE_REPORT=""

PRODUCTION_ENV="/etc/bluevpn/backend.env"
TEST_ENV="/etc/bluevpn/paid-beta.env"
PRODUCTION_DOWNLOADS="/var/www/greenvpn/downloads"
TEST_DOWNLOADS="/var/www/paid-beta/downloads"
TEST_STATIC_MANIFEST="$TEST_DOWNLOADS/manifest.json"
PRODUCTION_SERVICE="bluevpn-backend.service"
TEST_SERVICE="greenvpn-paid-beta.service"
PRODUCTION_DB="/opt/bluevpn/backend/data/bluevpn.db"
TEST_DB="/opt/bluevpn-paid-beta/data/bluevpn.db"

usage() {
  cat <<'EOF'
Atomically publish matching production and test Windows installers on one RU node.

Required arguments:
  --role timeweb|ruvds
  --production-exe PATH
  --test-exe PATH
  --version VERSION
  --test-version VERSION
  --build-number NUMBER
  --production-sha256 SHA256
  --test-sha256 SHA256

Optional arguments:
  --production-required 0|1  (default: 1)
  --test-required 0|1        (default: 0)
  --production-signature-report PATH
  --test-signature-report PATH

Signature reports must be the JSON output from sign_release_artifacts.ps1.
When supplied, both reports are required and are cryptographically bound to
the exact production/test SHA256 values before trusted metadata is published.

The default is dry-run. Apply mode preserves installer/env rollback files,
switches aliases atomically, restarts only local backend services, and verifies
both update manifests before success.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --role) ROLE="${2:?missing role}"; shift 2 ;;
    --production-exe) PRODUCTION_EXE="${2:?missing production EXE}"; shift 2 ;;
    --test-exe) TEST_EXE="${2:?missing test EXE}"; shift 2 ;;
    --version) VERSION="${2:?missing version}"; shift 2 ;;
    --test-version) TEST_VERSION="${2:?missing test version}"; shift 2 ;;
    --build-number) BUILD_NUMBER="${2:?missing build number}"; shift 2 ;;
    --production-sha256) PRODUCTION_SHA256="${2:?missing production SHA256}"; shift 2 ;;
    --test-sha256) TEST_SHA256="${2:?missing test SHA256}"; shift 2 ;;
    --production-required) PRODUCTION_REQUIRED="${2:?missing production required flag}"; shift 2 ;;
    --test-required) TEST_REQUIRED="${2:?missing test required flag}"; shift 2 ;;
    --production-signature-report) PRODUCTION_SIGNATURE_REPORT="${2:?missing production signature report}"; shift 2 ;;
    --test-signature-report) TEST_SIGNATURE_REPORT="${2:?missing test signature report}"; shift 2 ;;
    --apply) APPLY=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
done

case "$ROLE" in
  timeweb)
    PRODUCTION_URL="https://greenvpn.pro/downloads/GreenVPN_Setup.exe"
    TEST_URL="https://greenvpn.pro/paid-beta/downloads/GreenVPN_Setup.exe"
    ;;
  ruvds)
    PRODUCTION_URL="https://176-113-81-35.sslip.io/downloads/GreenVPN_Setup.exe"
    TEST_URL="https://176-113-81-35.sslip.io/paid-beta/downloads/GreenVPN_Setup.exe"
    ;;
  *) echo "--role must be timeweb or ruvds" >&2; exit 2 ;;
esac

[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+[A-Za-z0-9._-]*$ ]] || { echo "Invalid version" >&2; exit 2; }
[[ "$TEST_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+[A-Za-z0-9._-]*$ ]] || { echo "Invalid test version" >&2; exit 2; }
[[ "$BUILD_NUMBER" =~ ^[0-9]+$ ]] || { echo "Invalid build number" >&2; exit 2; }
[[ "$PRODUCTION_REQUIRED" =~ ^[01]$ ]] || { echo "Invalid production required flag" >&2; exit 2; }
[[ "$TEST_REQUIRED" =~ ^[01]$ ]] || { echo "Invalid test required flag" >&2; exit 2; }
PRODUCTION_SHA256="${PRODUCTION_SHA256^^}"
TEST_SHA256="${TEST_SHA256^^}"
[[ "$PRODUCTION_SHA256" =~ ^[0-9A-F]{64}$ ]] || { echo "Invalid production SHA256" >&2; exit 2; }
[[ "$TEST_SHA256" =~ ^[0-9A-F]{64}$ ]] || { echo "Invalid test SHA256" >&2; exit 2; }
for path in "$PRODUCTION_EXE" "$TEST_EXE" "$PRODUCTION_ENV" "$TEST_ENV" "$TEST_STATIC_MANIFEST" "$PRODUCTION_DB" "$TEST_DB"; do
  [[ -f "$path" && ! -L "$path" ]] || { echo "Missing or unsafe file: $path" >&2; exit 2; }
done
if [[ -n "$PRODUCTION_SIGNATURE_REPORT" || -n "$TEST_SIGNATURE_REPORT" ]]; then
  [[ -n "$PRODUCTION_SIGNATURE_REPORT" && -n "$TEST_SIGNATURE_REPORT" ]] || {
    echo "Both production and test signature reports are required" >&2
    exit 2
  }
  for path in "$PRODUCTION_SIGNATURE_REPORT" "$TEST_SIGNATURE_REPORT"; do
    [[ -f "$path" && ! -L "$path" ]] || { echo "Missing or unsafe signature report: $path" >&2; exit 2; }
  done
fi

actual_production="$(sha256sum "$PRODUCTION_EXE" | awk '{print toupper($1)}')"
actual_test="$(sha256sum "$TEST_EXE" | awk '{print toupper($1)}')"
[[ "$actual_production" == "$PRODUCTION_SHA256" ]] || { echo "Production EXE hash mismatch" >&2; exit 2; }
[[ "$actual_test" == "$TEST_SHA256" ]] || { echo "Test EXE hash mismatch" >&2; exit 2; }

SIGNED_RELEASE=0
SIGNATURE_STATUS="NotSigned"
SIGNING_PROVIDER=""
SIGNING_PUBLISHER=""
SIGNING_THUMBPRINT=""
if [[ -n "$PRODUCTION_SIGNATURE_REPORT" ]]; then
  mapfile -t signature_metadata < <(
    python3 - \
      "$PRODUCTION_SIGNATURE_REPORT" "$TEST_SIGNATURE_REPORT" \
      "$PRODUCTION_SHA256" "$TEST_SHA256" <<'PY'
import json
import pathlib
import re
import sys

production_report, test_report, production_sha, test_sha = sys.argv[1:]


def validate(label, path_raw, expected_sha):
    payload = json.loads(pathlib.Path(path_raw).read_text(encoding="utf-8-sig"))
    files = payload.get("files")
    if (
        payload.get("ok") is not True
        or payload.get("mode") != "sign-and-verify"
        or payload.get("unsignedCount") != 0
        or payload.get("publisherMismatchCount") != 0
        or payload.get("fileCount") != 1
        or not isinstance(files, list)
        or len(files) != 1
    ):
        raise SystemExit(f"{label} signature report is not a successful one-file signing report")
    item = files[0]
    publisher = str(payload.get("expectedPublisher") or "").strip()
    thumbprint = re.sub(r"\s+", "", str(payload.get("certificateThumbprint") or "")).upper()
    signer_thumbprint = re.sub(r"\s+", "", str(item.get("signerThumbprint") or "")).upper()
    issuer = str(item.get("signerIssuer") or "").strip()
    status = str(item.get("status") or "").strip()
    if not publisher or not re.fullmatch(r"[0-9A-F]{40}", thumbprint):
        raise SystemExit(f"{label} signature identity is incomplete")
    if (
        str(item.get("sha256") or "").upper() != expected_sha
        or item.get("signed") is not True
        or item.get("publisherMatches") is not True
        or status != "Valid"
        or signer_thumbprint != thumbprint
        or not issuer
    ):
        raise SystemExit(f"{label} signature report does not match the exact trusted artifact")
    for value in (publisher, thumbprint, issuer, status):
        if "\n" in value or "\r" in value:
            raise SystemExit(f"{label} signature metadata contains an invalid newline")
    return publisher, thumbprint, issuer, status


production = validate("production", production_report, production_sha)
test = validate("test", test_report, test_sha)
if production != test:
    raise SystemExit("Production and test installers must use the same trusted signing identity")
for value in production:
    print(value)
PY
  )
  [[ ${#signature_metadata[@]} -eq 4 ]] || {
    echo "Unable to read trusted signature metadata" >&2
    exit 2
  }
  SIGNING_PUBLISHER="${signature_metadata[0]}"
  SIGNING_THUMBPRINT="${signature_metadata[1]}"
  SIGNING_PROVIDER="${signature_metadata[2]}"
  SIGNATURE_STATUS="${signature_metadata[3]}"
  SIGNED_RELEASE=1
fi

echo "mode=$([[ $APPLY -eq 1 ]] && echo apply || echo dry-run)"
echo "role=$ROLE"
echo "version=$VERSION"
echo "test_version=$TEST_VERSION"
echo "build_number=$BUILD_NUMBER"
echo "production_sha256=$PRODUCTION_SHA256"
echo "test_sha256=$TEST_SHA256"
echo "production_required=$PRODUCTION_REQUIRED"
echo "test_required=$TEST_REQUIRED"
echo "signed_release=$SIGNED_RELEASE"
echo "signature_status=$SIGNATURE_STATUS"
[[ $APPLY -eq 1 ]] || exit 0
[[ $EUID -eq 0 ]] || { echo "Run apply mode as root" >&2; exit 1; }

timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
released_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
backup_dir="/root/greenvpn-windows-release-backups/${timestamp}-${ROLE}-${VERSION}-${BUILD_NUMBER}"
install -d -m 700 "$backup_dir"
cp -a --reflink=auto "$PRODUCTION_ENV" "$backup_dir/backend.env"
cp -a --reflink=auto "$TEST_ENV" "$backup_dir/paid-beta.env"
cp -a --reflink=auto "$TEST_STATIC_MANIFEST" "$backup_dir/paid-beta-manifest.json"
cp -a --reflink=auto "$PRODUCTION_DOWNLOADS/GreenVPN_Setup.exe" "$backup_dir/GreenVPN_Setup.production.previous.exe"
cp -a --reflink=auto "$TEST_DOWNLOADS/GreenVPN_Setup.exe" "$backup_dir/GreenVPN_Setup.test.previous.exe"
chmod 600 "$backup_dir"/*
sha256sum "$backup_dir"/*.exe >"$backup_dir/previous-exe-sha256.txt"
chmod 600 "$backup_dir/previous-exe-sha256.txt"

python3 - "$PRODUCTION_DB" "$TEST_DB" "$backup_dir" <<'PY'
import pathlib
import sqlite3
import sys

production_db, test_db, backup_raw = sys.argv[1:]
backup_dir = pathlib.Path(backup_raw)
for source_raw, backup_name in (
    (production_db, "production.db"),
    (test_db, "paid-beta.db"),
):
    source = sqlite3.connect(source_raw, timeout=60)
    target_path = backup_dir / backup_name
    target = sqlite3.connect(target_path)
    try:
        if source.execute("PRAGMA quick_check").fetchone()[0] != "ok":
            raise SystemExit(f"source quick_check failed: {source_raw}")
        source.backup(target)
        if target.execute("PRAGMA quick_check").fetchone()[0] != "ok":
            raise SystemExit(f"backup quick_check failed: {target_path}")
    finally:
        target.close()
        source.close()
    target_path.chmod(0o600)
PY

aliases_switched=0
env_modified=0
db_modified=0
rollback_on_error() {
  code=$?
  trap - ERR
  if [[ $db_modified -eq 1 ]]; then
    systemctl stop "$PRODUCTION_SERVICE" "$TEST_SERVICE" >/dev/null 2>&1 || true
    python3 - "$backup_dir/production.db" "$PRODUCTION_DB" "$backup_dir/paid-beta.db" "$TEST_DB" <<'PY'
import sqlite3
import sys

for source_raw, target_raw in (
    (sys.argv[1], sys.argv[2]),
    (sys.argv[3], sys.argv[4]),
):
    source = sqlite3.connect(f"file:{source_raw}?mode=ro", uri=True, timeout=60)
    target = sqlite3.connect(target_raw, timeout=60)
    try:
        source.backup(target)
        if target.execute("PRAGMA quick_check").fetchone()[0] != "ok":
            raise SystemExit(f"database restore quick_check failed: {target_raw}")
    finally:
        target.close()
        source.close()
PY
  fi
  if [[ $aliases_switched -eq 1 ]]; then
    install -m 644 "$backup_dir/GreenVPN_Setup.production.previous.exe" "$PRODUCTION_DOWNLOADS/GreenVPN_Setup.exe"
    install -m 644 "$backup_dir/GreenVPN_Setup.test.previous.exe" "$TEST_DOWNLOADS/GreenVPN_Setup.exe"
  fi
  if [[ $env_modified -eq 1 ]]; then
    cp -a "$backup_dir/backend.env" "$PRODUCTION_ENV"
    cp -a "$backup_dir/paid-beta.env" "$TEST_ENV"
    cp -a "$backup_dir/paid-beta-manifest.json" "$TEST_STATIC_MANIFEST"
  fi
  systemctl restart "$PRODUCTION_SERVICE" >/dev/null 2>&1 || true
  systemctl restart "$TEST_SERVICE" >/dev/null 2>&1 || true
  exit "$code"
}
trap rollback_on_error ERR

production_versioned="$PRODUCTION_DOWNLOADS/GreenVPN_Setup_${VERSION}_${BUILD_NUMBER}.exe"
test_versioned="$TEST_DOWNLOADS/GreenVPN_Setup_${TEST_VERSION}_${BUILD_NUMBER}.exe"
install -m 644 "$PRODUCTION_EXE" "$production_versioned"
install -m 644 "$TEST_EXE" "$test_versioned"
install -m 644 "$PRODUCTION_EXE" "$PRODUCTION_DOWNLOADS/.GreenVPN_Setup.exe.new"
install -m 644 "$TEST_EXE" "$TEST_DOWNLOADS/.GreenVPN_Setup.exe.new"
mv -f "$PRODUCTION_DOWNLOADS/.GreenVPN_Setup.exe.new" "$PRODUCTION_DOWNLOADS/GreenVPN_Setup.exe"
mv -f "$TEST_DOWNLOADS/.GreenVPN_Setup.exe.new" "$TEST_DOWNLOADS/GreenVPN_Setup.exe"
aliases_switched=1

python3 - \
  "$PRODUCTION_ENV" "$TEST_ENV" "$VERSION" "$TEST_VERSION" \
  "$PRODUCTION_URL" "$TEST_URL" "$PRODUCTION_SHA256" "$TEST_SHA256" \
  "$PRODUCTION_REQUIRED" "$TEST_REQUIRED" "$released_at" \
  "$SIGNED_RELEASE" "$SIGNING_PROVIDER" "$SIGNING_PUBLISHER" "$SIGNING_THUMBPRINT" <<'PY'
import os
import pathlib
import re
import sys

(
    production_path,
    test_path,
    version,
    test_version,
    production_url,
    test_url,
    production_sha,
    test_sha,
    production_required,
    test_required,
    released_at,
    signed_release,
    signing_provider,
    signing_publisher,
    signing_thumbprint,
) = sys.argv[1:]
assignment = re.compile(r"^(?:export\s+)?([A-Za-z_][A-Za-z0-9_]*)\s*=")
changelog = (
    f"Green VPN {version}: сохранение сессии; стабильное подключение Windows; "
    "серверы сгруппированы по локациям; тарифы на 1, 3 и 6 месяцев."
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
    temporary = path.with_name(path.name + ".windows-release.tmp")
    temporary.write_text("\n".join(out) + "\n", encoding="utf-8")
    os.chmod(temporary, 0o600)
    os.replace(temporary, path)


stable = {
    "GREENVPN_LATEST_VERSION": version,
    "GREENVPN_UPDATE_URL": production_url,
    "GREENVPN_UPDATE_SHA256": production_sha,
    "GREENVPN_UPDATE_REQUIRED": production_required,
    "GREENVPN_UPDATE_RELEASED_AT": released_at,
    "GREENVPN_UPDATE_CHANGELOG": changelog,
    "GREENVPN_PUBLIC_WINDOWS_DOWNLOAD_URL": production_url,
    "GREENVPN_WINDOWS_CODE_SIGNING_PROVIDER": signing_provider if signed_release == "1" else "",
    "GREENVPN_WINDOWS_CODE_SIGNING_PUBLISHER": signing_publisher if signed_release == "1" else "",
    "GREENVPN_WINDOWS_CODE_SIGNING_CERT_THUMBPRINT": signing_thumbprint if signed_release == "1" else "",
    "GREENVPN_WINDOWS_SIGNED_INSTALLER_URL": production_url if signed_release == "1" else "",
    "GREENVPN_WINDOWS_SIGNED_INSTALLER_SHA256": production_sha if signed_release == "1" else "",
}
paid_beta = {
    **stable,
    "GREENVPN_UPDATE_REQUIRED": "0",
    "GREENVPN_WINDOWS_PAID_BETA_LATEST_VERSION": test_version,
    "GREENVPN_WINDOWS_PAID_BETA_UPDATE_URL": test_url,
    "GREENVPN_WINDOWS_PAID_BETA_UPDATE_SHA256": test_sha,
    "GREENVPN_WINDOWS_PAID_BETA_UPDATE_REQUIRED": test_required,
    "GREENVPN_WINDOWS_PAID_BETA_UPDATE_RELEASED_AT": released_at,
    "GREENVPN_WINDOWS_PAID_BETA_UPDATE_CHANGELOG": changelog,
}
rewrite(production_path, stable)
rewrite(test_path, paid_beta)
PY

python3 - \
  "$TEST_STATIC_MANIFEST" "$TEST_VERSION" "$BUILD_NUMBER" "$TEST_SHA256" \
  "$TEST_EXE" "$released_at" "$SIGNED_RELEASE" "$SIGNATURE_STATUS" \
  "$SIGNING_PUBLISHER" "$SIGNING_THUMBPRINT" <<'PY'
import json
import os
import pathlib
import sys

(
    path_raw,
    version,
    build_number,
    sha256,
    installer_raw,
    generated_at,
    signed_release,
    signature_status,
    signing_publisher,
    signing_thumbprint,
) = sys.argv[1:]
path = pathlib.Path(path_raw)
installer = pathlib.Path(installer_raw)
payload = json.loads(path.read_text(encoding="utf-8"))
artifacts = payload.get("artifacts")
if not isinstance(artifacts, list):
    raise SystemExit("paid-beta static manifest artifacts are missing")
windows = next(
    (item for item in artifacts if isinstance(item, dict) and item.get("platform") == "windows"),
    None,
)
if windows is None:
    raise SystemExit("paid-beta static manifest Windows artifact is missing")
payload["windowsAppVersion"] = version
payload["generatedAt"] = generated_at
windows.update(
    {
        "fileName": "GreenVPN_Setup.exe",
        "version": version,
        "buildNumber": build_number,
        "sizeBytes": installer.stat().st_size,
        "sha256": sha256,
        "signed": signed_release == "1",
        "signatureStatus": signature_status,
        "signerPublisher": signing_publisher if signed_release == "1" else "",
        "signerThumbprint": signing_thumbprint if signed_release == "1" else "",
    }
)
temporary = path.with_name(path.name + ".windows-release.tmp")
temporary.write_text(
    json.dumps(payload, ensure_ascii=False, indent=2) + "\n",
    encoding="utf-8",
)
os.chmod(temporary, 0o644)
os.replace(temporary, path)
PY
env_modified=1
chown root:root "$PRODUCTION_ENV" "$TEST_ENV"
chmod 600 "$PRODUCTION_ENV" "$TEST_ENV"

db_modified=1
python3 - \
  "$PRODUCTION_DB" "$TEST_DB" "$VERSION" "$TEST_VERSION" "$BUILD_NUMBER" \
  "$PRODUCTION_URL" "$TEST_URL" "$PRODUCTION_SHA256" "$TEST_SHA256" \
  "$PRODUCTION_EXE" "$TEST_EXE" "$PRODUCTION_REQUIRED" "$TEST_REQUIRED" \
  "$released_at" <<'PY'
import json
import pathlib
import sqlite3
import sys

(
    production_db,
    test_db,
    production_version,
    test_version,
    build_number,
    production_url,
    test_url,
    production_sha,
    test_sha,
    production_exe,
    test_exe,
    production_required,
    test_required,
    released_at,
) = sys.argv[1:]

changelog = json.dumps(
    [
        "Исправлена установка для всех пользователей Windows.",
        "Добавлены безопасное обновление и автоматический откат установки.",
        "Исправлена обработка истекшей сессии.",
    ],
    ensure_ascii=False,
)

for db_raw, channel, version, url, sha256, artifact_raw, required_raw in (
    (
        production_db,
        "stable",
        production_version,
        production_url,
        production_sha,
        production_exe,
        production_required,
    ),
    (test_db, "paid-beta", test_version, test_url, test_sha, test_exe, test_required),
):
    artifact = pathlib.Path(artifact_raw)
    required = 1 if required_raw == "1" else 0
    conn = sqlite3.connect(db_raw, timeout=60)
    try:
        if conn.execute("PRAGMA quick_check").fetchone()[0] != "ok":
            raise SystemExit(f"pre-update quick_check failed: {db_raw}")
        conn.execute("BEGIN IMMEDIATE")
        conn.execute(
            """
            UPDATE app_releases
            SET status = 'retired', retired_at = ?, updated_at = ?
            WHERE platform = 'windows' AND channel = ?
              AND status = 'published' AND version <> ?
            """,
            (released_at, released_at, channel, version),
        )
        conn.execute(
            """
            INSERT INTO app_releases(
                platform, channel, version, build_number, download_url, sha256,
                size_bytes, is_required, min_supported_version, rollout_percent,
                changelog_json, status, created_at, updated_at, published_at, retired_at
            )
            VALUES ('windows', ?, ?, ?, ?, ?, ?, ?, '', 100, ?, 'published', ?, ?, ?, NULL)
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
                channel,
                version,
                build_number,
                url,
                sha256,
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
            raise SystemExit(f"post-update quick_check failed: {db_raw}")
    except Exception:
        conn.rollback()
        raise
    finally:
        conn.close()
PY

systemctl restart "$PRODUCTION_SERVICE"
systemctl restart "$TEST_SERVICE"
for port in 8000 8010; do
  ready=0
  for _ in $(seq 1 90); do
    if curl -fsS --max-time 3 "http://127.0.0.1:${port}/healthz" >/dev/null; then
      ready=1
      break
    fi
    sleep 1
  done
  [[ $ready -eq 1 ]]
done

production_manifest="$(curl -fsS --max-time 20 "http://127.0.0.1:8000/api/v1/updates/manifest?platform=windows&channel=stable&currentVersion=0.0.0&clientId=release-install")"
test_manifest="$(curl -fsS --max-time 20 "http://127.0.0.1:8010/api/v1/updates/manifest?platform=windows&channel=paid-beta&currentVersion=0.0.0&clientId=release-install")"
python3 - \
  "$VERSION" "$TEST_VERSION" "$PRODUCTION_SHA256" "$TEST_SHA256" \
  "$PRODUCTION_REQUIRED" "$TEST_REQUIRED" "$production_manifest" "$test_manifest" <<'PY'
import json
import sys

version, test_version, production_sha, test_sha, production_required, test_required, production_raw, test_raw = sys.argv[1:]
for label, raw, expected_version, expected_sha, expected_required in (
    ("production", production_raw, version, production_sha, production_required == "1"),
    ("test", test_raw, test_version, test_sha, test_required == "1"),
):
    manifest = json.loads(raw).get("manifest") or {}
    if manifest.get("latestVersion") != expected_version:
        raise SystemExit(f"{label} manifest version mismatch")
    if str(manifest.get("sha256") or "").upper() != expected_sha:
        raise SystemExit(f"{label} manifest hash mismatch")
    if manifest.get("required") is not expected_required or manifest.get("fileReady") is not True:
        raise SystemExit(f"{label} manifest readiness mismatch")
print("production_manifest_ready=true")
print("test_manifest_ready=true")
PY

[[ "$(sha256sum "$PRODUCTION_DOWNLOADS/GreenVPN_Setup.exe" | awk '{print toupper($1)}')" == "$PRODUCTION_SHA256" ]]
[[ "$(sha256sum "$TEST_DOWNLOADS/GreenVPN_Setup.exe" | awk '{print toupper($1)}')" == "$TEST_SHA256" ]]
python3 - \
  "$TEST_STATIC_MANIFEST" "$TEST_VERSION" "$TEST_SHA256" \
  "$SIGNED_RELEASE" "$SIGNATURE_STATUS" "$SIGNING_THUMBPRINT" <<'PY'
import json
import pathlib
import sys

path, version, sha256, signed_release, signature_status, signing_thumbprint = sys.argv[1:]
payload = json.loads(pathlib.Path(path).read_text(encoding="utf-8"))
windows = next(
    (item for item in payload.get("artifacts", []) if item.get("platform") == "windows"),
    {},
)
if payload.get("windowsAppVersion") != version:
    raise SystemExit("paid-beta static manifest version mismatch")
if str(windows.get("sha256") or "").upper() != sha256:
    raise SystemExit("paid-beta static manifest hash mismatch")
if windows.get("signed") is not (signed_release == "1"):
    raise SystemExit("paid-beta static manifest signature flag mismatch")
if windows.get("signatureStatus") != signature_status:
    raise SystemExit("paid-beta static manifest signature status mismatch")
if signed_release == "1" and str(windows.get("signerThumbprint") or "").upper() != signing_thumbprint:
    raise SystemExit("paid-beta static manifest signer thumbprint mismatch")
print("test_static_manifest_ready=true")
PY
trap - ERR
echo "windows_release_status=ok"
echo "backup_dir=$backup_dir"
