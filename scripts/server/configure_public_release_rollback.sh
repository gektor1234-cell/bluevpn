#!/usr/bin/env bash
set -euo pipefail

APPLY=0
ROLE=""
CONTOUR=""
PLATFORM=""
ARTIFACT=""
VERSION=""
EXPECTED_SHA256=""

usage() {
  cat <<'EOF'
Configure a public rollback artifact for one Green VPN control-plane contour.

Usage:
  configure_public_release_rollback.sh \
    --role timeweb|ruvds \
    --contour production|paid-beta \
    --platform android|windows \
    --artifact PATH \
    --version VERSION \
    --sha256 SHA256 \
    [--apply]

The default is a dry run. Apply mode publishes a versioned artifact, updates
only public rollback environment keys, restarts one backend service, verifies
health and the public download, and rolls back automatically on error.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --role) ROLE="${2:?missing role}"; shift 2 ;;
    --contour) CONTOUR="${2:?missing contour}"; shift 2 ;;
    --platform) PLATFORM="${2:?missing platform}"; shift 2 ;;
    --artifact) ARTIFACT="${2:?missing artifact}"; shift 2 ;;
    --version) VERSION="${2:?missing version}"; shift 2 ;;
    --sha256) EXPECTED_SHA256="${2:?missing SHA256}"; shift 2 ;;
    --apply) APPLY=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
done

case "$ROLE" in
  timeweb) PUBLIC_ORIGIN="https://greenvpn.pro" ;;
  ruvds) PUBLIC_ORIGIN="https://176-113-81-35.sslip.io" ;;
  *) echo "--role must be timeweb or ruvds" >&2; exit 2 ;;
esac
case "$CONTOUR" in
  production)
    ENV_FILE="/etc/bluevpn/backend.env"
    SERVICE="bluevpn-backend.service"
    DOWNLOADS_DIR="/var/www/greenvpn/downloads"
    PUBLIC_PREFIX="${PUBLIC_ORIGIN}/downloads"
    HEALTH_URL="http://127.0.0.1:8000/healthz"
    ;;
  paid-beta)
    ENV_FILE="/etc/bluevpn/paid-beta.env"
    SERVICE="greenvpn-paid-beta.service"
    DOWNLOADS_DIR="/var/www/paid-beta/downloads"
    PUBLIC_PREFIX="${PUBLIC_ORIGIN}/paid-beta/downloads"
    HEALTH_URL="http://127.0.0.1:8010/healthz"
    ;;
  *) echo "--contour must be production or paid-beta" >&2; exit 2 ;;
esac
case "$PLATFORM" in
  android)
    EXTENSION="apk"
    FILE_PREFIX="GreenVPN_Android"
    if [[ "$CONTOUR" == "production" ]]; then
      ENV_PREFIX="GREENVPN_ANDROID_ROLLBACK"
    else
      ENV_PREFIX="GREENVPN_ANDROID_PAID_BETA_ROLLBACK"
    fi
    ;;
  windows)
    EXTENSION="exe"
    FILE_PREFIX="GreenVPN_Setup"
    if [[ "$CONTOUR" == "production" ]]; then
      ENV_PREFIX="GREENVPN_ROLLBACK"
    else
      ENV_PREFIX="GREENVPN_WINDOWS_PAID_BETA_ROLLBACK"
    fi
    ;;
  *) echo "--platform must be android or windows" >&2; exit 2 ;;
esac

[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+[A-Za-z0-9._-]*$ ]] || {
  echo "Invalid version" >&2
  exit 2
}
EXPECTED_SHA256="${EXPECTED_SHA256^^}"
[[ "$EXPECTED_SHA256" =~ ^[0-9A-F]{64}$ ]] || { echo "Invalid SHA256" >&2; exit 2; }
[[ -f "$ARTIFACT" && ! -L "$ARTIFACT" ]] || { echo "Artifact is missing or unsafe" >&2; exit 2; }
[[ -f "$ENV_FILE" && ! -L "$ENV_FILE" ]] || { echo "Environment file is missing or unsafe" >&2; exit 2; }
[[ -d "$DOWNLOADS_DIR" && ! -L "$DOWNLOADS_DIR" ]] || { echo "Downloads directory is missing or unsafe" >&2; exit 2; }

ACTUAL_SHA256="$(sha256sum -- "$ARTIFACT" | awk '{print toupper($1)}')"
[[ "$ACTUAL_SHA256" == "$EXPECTED_SHA256" ]] || { echo "Artifact SHA256 mismatch" >&2; exit 2; }

FILE_NAME="${FILE_PREFIX}_${VERSION}_rollback.${EXTENSION}"
DESTINATION="${DOWNLOADS_DIR}/${FILE_NAME}"
PUBLIC_URL="${PUBLIC_PREFIX}/${FILE_NAME}"
if [[ -e "$DESTINATION" && ( ! -f "$DESTINATION" || -L "$DESTINATION" ) ]]; then
  echo "Existing destination is unsafe" >&2
  exit 2
fi

echo "mode=$([[ $APPLY -eq 1 ]] && echo apply || echo dry-run)"
echo "role=$ROLE"
echo "contour=$CONTOUR"
echo "platform=$PLATFORM"
echo "version=$VERSION"
echo "sha256=$EXPECTED_SHA256"
echo "public_url=$PUBLIC_URL"
[[ $APPLY -eq 1 ]] || exit 0
[[ $EUID -eq 0 ]] || { echo "Run apply mode as root" >&2; exit 1; }

timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
backup_dir="/root/greenvpn-release-rollback-backups/${timestamp}-${ROLE}-${CONTOUR}-${PLATFORM}-${VERSION}"
install -d -m 700 -- "$backup_dir"
cp -a -- "$ENV_FILE" "$backup_dir/environment.env"
chmod 600 "$backup_dir/environment.env"
destination_existed=0
if [[ -f "$DESTINATION" ]]; then
  cp -a -- "$DESTINATION" "$backup_dir/previous-artifact"
  chmod 600 "$backup_dir/previous-artifact"
  destination_existed=1
fi

artifact_modified=0
env_modified=0
rollback_on_error() {
  code=$?
  trap - ERR
  if [[ $env_modified -eq 1 ]]; then
    cp -a -- "$backup_dir/environment.env" "$ENV_FILE"
  fi
  if [[ $artifact_modified -eq 1 ]]; then
    if [[ $destination_existed -eq 1 ]]; then
      install -m 644 -- "$backup_dir/previous-artifact" "$DESTINATION"
    else
      rm -f -- "$DESTINATION"
    fi
  fi
  systemctl restart "$SERVICE" >/dev/null 2>&1 || true
  exit "$code"
}
trap rollback_on_error ERR

temporary="${DESTINATION}.tmp.$$"
install -m 644 -- "$ARTIFACT" "$temporary"
mv -f -- "$temporary" "$DESTINATION"
artifact_modified=1

python3 - "$ENV_FILE" "$ENV_PREFIX" "$VERSION" "$PUBLIC_URL" "$EXPECTED_SHA256" <<'PY'
import os
import pathlib
import re
import sys

path = pathlib.Path(sys.argv[1])
prefix, version, url, sha256 = sys.argv[2:]
updates = {
    f"{prefix}_VERSION": version,
    f"{prefix}_URL": url,
    f"{prefix}_SHA256": sha256,
}
assignment = re.compile(r"^(?:export\s+)?([A-Za-z_][A-Za-z0-9_]*)\s*=")
out = []
for raw in path.read_text(encoding="utf-8").splitlines():
    match = assignment.match(raw.strip())
    if match and match.group(1) in updates:
        continue
    out.append(raw)
for key, value in updates.items():
    escaped = value.replace("\\", "\\\\").replace('"', '\\"')
    out.append(f'{key}="{escaped}"')
temporary = path.with_name(path.name + ".rollback.tmp")
temporary.write_text("\n".join(out) + "\n", encoding="utf-8")
os.chmod(temporary, 0o600)
os.replace(temporary, path)
PY
env_modified=1
chown root:root "$ENV_FILE"
chmod 600 "$ENV_FILE"

systemctl restart "$SERVICE"
for _ in $(seq 1 45); do
  curl -fsS --max-time 3 "$HEALTH_URL" >/dev/null && break
  sleep 1
done
curl -fsS --max-time 5 "$HEALTH_URL" >/dev/null
downloaded_sha256="$(curl -fsS --max-time 120 "$PUBLIC_URL" | sha256sum | awk '{print toupper($1)}')"
[[ "$downloaded_sha256" == "$EXPECTED_SHA256" ]] || { echo "Public rollback SHA256 mismatch" >&2; exit 1; }

trap - ERR
echo "rollback_configuration_status=ok"
echo "backup_dir=$backup_dir"
