#!/usr/bin/env bash
set -euo pipefail

APPLY=0
BUNDLE=""
TARGET="timeweb"
EXPECTED_HOSTNAME=""
VERIFY_HOST=""
VERIFY_PUBLIC_SITE=0
SITE_ROOT="/var/www/greenvpn"
STAGE_ROOT="/root/greenvpn-main-site-stage"
BACKUP_ROOT="/root/greenvpn-main-site-backups"
declare -a RELEASE_FILES=(
  "index.html"
  "styles.css"
  "assets/app_icon.ico"
  "assets/app_android_full.png"
  "assets/app_windows_full.png"
  "assets/app_windows_selected.png"
  "privacy/index.html"
)

usage() {
  cat <<'USAGE'
Install the Green VPN main-site source without touching public downloads.

  install_main_site_release.sh --bundle /root/greenvpn-main-site-stage/site.tar.gz [--target timeweb|ruvds-msk] [--apply]

Dry-run is the default. The archive must contain exactly the guarded main page,
shared styles, app icon, three product screenshots, and privacy page. Apply
creates a root-only rollback copy and restores it automatically when nginx or
HTTPS verification fails.
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --bundle) BUNDLE="${2:?missing bundle}"; shift 2 ;;
    --target) TARGET="${2:?missing target}"; shift 2 ;;
    --apply) APPLY=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
done

case "${TARGET}" in
  timeweb)
    EXPECTED_HOSTNAME="msk-1-vm-02nw"
    VERIFY_HOST="greenvpn.pro"
    VERIFY_PUBLIC_SITE=1
    ;;
  ruvds-msk)
    EXPECTED_HOSTNAME="greenvpn-ruvds-m9-control-01"
    VERIFY_HOST="176-113-81-35.sslip.io"
    VERIFY_PUBLIC_SITE=0
    ;;
  *)
    echo "Unsupported target: ${TARGET}" >&2
    exit 2
    ;;
esac

[[ "${EUID}" -eq 0 ]] || { echo "Run as root." >&2; exit 1; }
[[ "$(hostname -s)" == "${EXPECTED_HOSTNAME}" ]] || {
  echo "Host guard failed." >&2
  exit 1
}
command -v python3 >/dev/null 2>&1 || { echo "python3 is required." >&2; exit 1; }
[[ -d "${SITE_ROOT}" && ! -L "${SITE_ROOT}" ]] || {
  echo "Site root is missing or unsafe." >&2
  exit 1
}
[[ -n "${BUNDLE}" && -f "${BUNDLE}" && ! -L "${BUNDLE}" ]] || {
  echo "Bundle is missing or unsafe." >&2
  exit 1
}
[[ "$(dirname -- "$(readlink -f -- "${BUNDLE}")")" == "${STAGE_ROOT}" ]] || {
  echo "Bundle path guard failed." >&2
  exit 1
}

WORK_ROOT="$(mktemp -d /root/greenvpn-main-site-verify.XXXXXX)"
BACKUP_DIR=""
APPLY_STARTED=0
cleanup() {
  rm -rf --one-file-system -- "${WORK_ROOT}"
}
rollback() {
  local status=$?
  if [[ "${APPLY_STARTED}" -eq 1 && -n "${BACKUP_DIR}" && -d "${BACKUP_DIR}" ]]; then
    for relative in "${RELEASE_FILES[@]}"; do
      destination="${SITE_ROOT}/${relative}"
      backup_file="${BACKUP_DIR}/${relative}"
      missing_marker="${BACKUP_DIR}/.missing/${relative}"
      if [[ -f "${backup_file}" ]]; then
        install -d -m 0755 -- "$(dirname -- "${destination}")"
        install -m 0644 -- "${backup_file}" "${destination}"
      elif [[ -f "${missing_marker}" ]]; then
        rm -f -- "${destination}"
      fi
    done
    nginx -t >/dev/null 2>&1 && systemctl reload nginx || true
    echo "main_site_rollback=completed" >&2
  fi
  cleanup
  exit "${status}"
}
trap rollback ERR INT TERM
trap cleanup EXIT

python3 - "${BUNDLE}" "${WORK_ROOT}" <<'PY'
import pathlib
import shutil
import sys
import tarfile

bundle = pathlib.Path(sys.argv[1])
destination = pathlib.Path(sys.argv[2])
expected_files = {
    "index.html",
    "styles.css",
    "assets/app_icon.ico",
    "assets/app_android_full.png",
    "assets/app_windows_full.png",
    "assets/app_windows_selected.png",
    "privacy/index.html",
}
allowed_directories = {"assets", "privacy"}
seen: set[str] = set()

with tarfile.open(bundle, mode="r:gz") as archive:
    for member in archive.getmembers():
        name = member.name.removeprefix("./").rstrip("/")
        pure = pathlib.PurePosixPath(name)
        if not name or pure.is_absolute() or ".." in pure.parts:
            raise SystemExit("Unsafe archive path")
        if member.isdir():
            if name not in allowed_directories:
                raise SystemExit("Unexpected archive directory")
            continue
        if not member.isfile() or name not in expected_files or name in seen:
            raise SystemExit("Unexpected archive member")
        seen.add(name)
        source = archive.extractfile(member)
        if source is None:
            raise SystemExit("Archive member cannot be read")
        target = destination.joinpath(*pure.parts)
        target.parent.mkdir(parents=True, exist_ok=True)
        with source, target.open("wb") as output:
            shutil.copyfileobj(source, output)

if seen != expected_files:
    raise SystemExit("Bundle file-set guard failed")
PY

grep -Fq '<title>Green VPN — скачать для Android и Windows</title>' "${WORK_ROOT}/index.html"
grep -Fq 'Защищённое подключение для всего интернета или только выбранных приложений и сайтов.' "${WORK_ROOT}/index.html"
grep -Fq 'Только выбранное' "${WORK_ROOT}/index.html"
grep -Fq 'Диагностика' "${WORK_ROOT}/index.html"
grep -Fq 'href="/downloads/GreenVPN_Android.apk"' "${WORK_ROOT}/index.html"
grep -Fq 'href="/downloads/GreenVPN_Setup.exe"' "${WORK_ROOT}/index.html"
if grep -Eq '249 ₽|649 ₽|1 099 ₽|Три понятных срока|приложение само|сам берёт' "${WORK_ROOT}/index.html"; then
  echo "Stale main-site copy detected." >&2
  exit 1
fi
grep -Fq 'href="/legal/offer"' "${WORK_ROOT}/index.html"
grep -Fq 'Политика конфиденциальности' "${WORK_ROOT}/privacy/index.html"
for asset in \
  "styles.css" \
  "assets/app_icon.ico" \
  "assets/app_android_full.png" \
  "assets/app_windows_full.png" \
  "assets/app_windows_selected.png"; do
  [[ -s "${WORK_ROOT}/${asset}" ]]
done

echo "main_site_apply=${APPLY}"
echo "main_site_target=${TARGET}"
echo "main_site_bundle_sha256=$(sha256sum -- "${BUNDLE}" | cut -d' ' -f1)"
echo "main_site_release_files=${#RELEASE_FILES[@]}"
[[ "${APPLY}" -eq 1 ]] || exit 0

TIMESTAMP="$(date -u +%Y%m%dT%H%M%SZ)"
BACKUP_DIR="${BACKUP_ROOT}/${TIMESTAMP}"
install -d -m 0700 -- "${BACKUP_DIR}"
for relative in "${RELEASE_FILES[@]}"; do
  source_path="${SITE_ROOT}/${relative}"
  [[ ! -L "${source_path}" ]] || {
    echo "Current site file is a symlink: ${relative}" >&2
    exit 1
  }
  if [[ -f "${source_path}" ]]; then
    install -d -m 0700 -- "$(dirname -- "${BACKUP_DIR}/${relative}")"
    install -m 0600 -- "${source_path}" "${BACKUP_DIR}/${relative}"
  elif [[ ! -e "${source_path}" ]]; then
    missing_marker="${BACKUP_DIR}/.missing/${relative}"
    install -d -m 0700 -- "$(dirname -- "${missing_marker}")"
    install -m 0600 /dev/null "${missing_marker}"
  else
    echo "Current site path is not a regular file: ${relative}" >&2
    exit 1
  fi
done

APPLY_STARTED=1
for relative in "${RELEASE_FILES[@]}"; do
  destination="${SITE_ROOT}/${relative}"
  temporary="${destination}.tmp.$$"
  install -d -m 0755 -- "$(dirname -- "${destination}")"
  install -m 0644 -- "${WORK_ROOT}/${relative}" "${temporary}"
  mv -f -- "${temporary}" "${destination}"
done

nginx -t
systemctl reload nginx
if [[ "${VERIFY_PUBLIC_SITE}" -eq 1 ]]; then
  curl --fail --silent --show-error --max-time 15 \
    --resolve "${VERIFY_HOST}:443:127.0.0.1" \
    "https://${VERIFY_HOST}/" | grep -F 'Скачать Green VPN' >/dev/null
  curl --fail --silent --show-error --max-time 15 \
    --resolve "${VERIFY_HOST}:443:127.0.0.1" \
    "https://${VERIFY_HOST}/legal/offer" | grep -F 'Публичная оферта' >/dev/null
else
  grep -Fq 'Скачать Green VPN' "${SITE_ROOT}/index.html"
  curl --fail --silent --show-error --max-time 15 \
    --resolve "${VERIFY_HOST}:443:127.0.0.1" \
    "https://${VERIFY_HOST}/assets/app_windows_selected.png" >/dev/null
  curl --fail --silent --show-error --max-time 15 \
    --resolve "${VERIFY_HOST}:443:127.0.0.1" \
    "https://${VERIFY_HOST}/healthz" >/dev/null
fi

APPLY_STARTED=0
echo "main_site_status=installed"
echo "main_site_rollback_dir=${BACKUP_DIR}"
