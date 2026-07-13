#!/usr/bin/env bash
set -euo pipefail

APPLY=0
BUNDLE=""
EXPECTED_HOSTNAME="msk-1-vm-02nw"
SITE_ROOT="/var/www/greenvpn"
STAGE_ROOT="/root/greenvpn-main-site-stage"
BACKUP_ROOT="/root/greenvpn-main-site-backups"
declare -a RELEASE_FILES=(
  "index.html"
  "styles.css"
  "assets/app_icon.ico"
  "privacy/index.html"
)

usage() {
  cat <<'USAGE'
Install the Green VPN main-site source without touching public downloads.

  install_main_site_release.sh --bundle /root/greenvpn-main-site-stage/site.tar.gz [--apply]

Dry-run is the default. The archive must contain exactly index.html, styles.css,
assets/app_icon.ico, and privacy/index.html. Apply creates a root-only rollback
copy and restores it automatically when nginx or HTTPS verification fails.
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --bundle) BUNDLE="${2:?missing bundle}"; shift 2 ;;
    --apply) APPLY=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
done

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
      install -d -m 0755 -- "$(dirname -- "${SITE_ROOT}/${relative}")"
      install -m 0644 -- "${BACKUP_DIR}/${relative}" "${SITE_ROOT}/${relative}"
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

grep -Fq '<title>Green VPN для Windows и Android</title>' "${WORK_ROOT}/index.html"
grep -Fq '249 ₽' "${WORK_ROOT}/index.html"
grep -Fq '649 ₽' "${WORK_ROOT}/index.html"
grep -Fq '1 099 ₽' "${WORK_ROOT}/index.html"
grep -Fq 'href="/legal/offer"' "${WORK_ROOT}/index.html"
grep -Fq 'Политика конфиденциальности' "${WORK_ROOT}/privacy/index.html"
[[ -s "${WORK_ROOT}/styles.css" && -s "${WORK_ROOT}/assets/app_icon.ico" ]]

echo "main_site_apply=${APPLY}"
echo "main_site_bundle_sha256=$(sha256sum -- "${BUNDLE}" | cut -d' ' -f1)"
echo "main_site_release_files=${#RELEASE_FILES[@]}"
[[ "${APPLY}" -eq 1 ]] || exit 0

TIMESTAMP="$(date -u +%Y%m%dT%H%M%SZ)"
BACKUP_DIR="${BACKUP_ROOT}/${TIMESTAMP}"
install -d -m 0700 -- "${BACKUP_DIR}"
for relative in "${RELEASE_FILES[@]}"; do
  source_path="${SITE_ROOT}/${relative}"
  [[ -f "${source_path}" && ! -L "${source_path}" ]] || {
    echo "Current site file is missing or unsafe: ${relative}" >&2
    exit 1
  }
  install -d -m 0700 -- "$(dirname -- "${BACKUP_DIR}/${relative}")"
  install -m 0600 -- "${source_path}" "${BACKUP_DIR}/${relative}"
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
curl --fail --silent --show-error --max-time 15 \
  --resolve greenvpn.pro:443:127.0.0.1 \
  https://greenvpn.pro/ | grep -F '249 ₽' >/dev/null
curl --fail --silent --show-error --max-time 15 \
  --resolve greenvpn.pro:443:127.0.0.1 \
  https://greenvpn.pro/legal/offer | grep -F 'Публичная оферта' >/dev/null

APPLY_STARTED=0
echo "main_site_status=installed"
echo "main_site_rollback_dir=${BACKUP_DIR}"
