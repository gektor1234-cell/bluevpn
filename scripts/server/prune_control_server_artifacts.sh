#!/usr/bin/env bash
set -euo pipefail

APPLY=0
declare -a EXPECTED_HOSTNAMES=(
  "msk-1-vm-02nw"
  "greenvpn-ruvds-m9-control-01"
)
PUBLIC_DOWNLOADS="/var/www/greenvpn/downloads"
PAID_RELEASES="/var/www/greenvpn-paid-beta/releases"
PAID_CURRENT_LINK="/var/www/paid-beta"
CURRENT_PAID_RELEASE="paid-beta-0.3.0-paid-beta.6-2026071106-r12"
PREVIOUS_PAID_RELEASE="paid-beta-0.3.0-paid-beta.5-2026071005-r11"
SITE_BACKUPS="/root/greenvpn-site-backups"
STABLE_CHECKPOINTS="/root/greenvpn_stable_checkpoints"

declare -a KEEP_DOWNLOADS=(
  "GreenVPN_Android.apk"
  "GreenVPN_Android_0.2.44_2026070504_stable.apk"
  "GreenVPN_Setup.exe"
  "GreenVPN_Setup_0.2.39_windows_clean_server_ui.exe"
)
declare -a KEEP_SITE_BACKUPS=(
  "GreenVPN_Android_pre_stable_0.2.44_20260705T082437Z.apk"
  "GreenVPN_Setup_pre_20260705_0923.exe"
)

usage() {
  cat <<'USAGE'
Prune superseded control-server public builds, paid-site releases, and copies.

  prune_control_server_artifacts.sh [--apply]

Dry-run is the default. Apply is guarded by the exact hostname and exact roots.
It retains the current Android/Windows installers, one paid-site rollback
release, and one prior Android/Windows rollback pair under /root.
USAGE
}

contains_name() {
  local candidate="$1"
  shift
  local expected
  for expected in "$@"; do
    [[ "${candidate}" == "${expected}" ]] && return 0
  done
  return 1
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --apply) APPLY=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
done

[[ "${EUID}" -eq 0 ]] || { echo "Run as root." >&2; exit 1; }
HOSTNAME_SHORT="$(hostname -s)"
contains_name "${HOSTNAME_SHORT}" "${EXPECTED_HOSTNAMES[@]}" || {
  echo "Host guard failed." >&2
  exit 1
}

guard_root() {
  local root="$1"
  [[ -d "${root}" && ! -L "${root}" ]] || {
    echo "Required root is missing or unsafe: ${root}" >&2
    exit 1
  }
  [[ "$(readlink -f -- "${root}")" == "${root}" ]] || {
    echo "Root path guard failed: ${root}" >&2
    exit 1
  }
}

guard_direct_child() {
  local root="$1"
  local path="$2"
  [[ "$(dirname -- "${path}")" == "${root}" ]] || {
    echo "Nested cleanup path rejected: ${path}" >&2
    exit 1
  }
  [[ ! -L "${path}" ]] || {
    echo "Symlink cleanup path rejected: ${path}" >&2
    exit 1
  }
  if [[ -d "${path}" ]] && mountpoint -q -- "${path}"; then
    echo "Mounted cleanup path rejected: ${path}" >&2
    exit 1
  fi
}

for root in "${PUBLIC_DOWNLOADS}" "${PAID_RELEASES}" "${SITE_BACKUPS}" "${STABLE_CHECKPOINTS}"; do
  guard_root "${root}"
done

for name in "${KEEP_DOWNLOADS[@]}"; do
  [[ -f "${PUBLIC_DOWNLOADS}/${name}" && ! -L "${PUBLIC_DOWNLOADS}/${name}" ]] || {
    echo "Retained public build is missing or unsafe: ${name}" >&2
    exit 1
  }
done
for name in "${KEEP_SITE_BACKUPS[@]}"; do
  [[ -f "${SITE_BACKUPS}/${name}" && ! -L "${SITE_BACKUPS}/${name}" ]] || {
    echo "Retained rollback build is missing or unsafe: ${name}" >&2
    exit 1
  }
done
for name in "${CURRENT_PAID_RELEASE}" "${PREVIOUS_PAID_RELEASE}"; do
  [[ -d "${PAID_RELEASES}/${name}" && ! -L "${PAID_RELEASES}/${name}" ]] || {
    echo "Retained paid-site release is missing or unsafe: ${name}" >&2
    exit 1
  }
done

EXPECTED_PAID_TARGET="${PAID_RELEASES}/${CURRENT_PAID_RELEASE}"
[[ -L "${PAID_CURRENT_LINK}" ]] || {
  echo "Current paid-site path is not a symlink." >&2
  exit 1
}
[[ "$(readlink -f -- "${PAID_CURRENT_LINK}")" == "${EXPECTED_PAID_TARGET}" ]] || {
  echo "Current paid-site target guard failed." >&2
  exit 1
}

[[ "$(sha256sum -- "${PUBLIC_DOWNLOADS}/GreenVPN_Android.apk" | cut -d' ' -f1)" == \
   "$(sha256sum -- "${PUBLIC_DOWNLOADS}/GreenVPN_Android_0.2.44_2026070504_stable.apk" | cut -d' ' -f1)" ]] || {
  echo "Android alias and retained version differ." >&2
  exit 1
}
[[ "$(sha256sum -- "${PUBLIC_DOWNLOADS}/GreenVPN_Setup.exe" | cut -d' ' -f1)" == \
   "$(sha256sum -- "${PUBLIC_DOWNLOADS}/GreenVPN_Setup_0.2.39_windows_clean_server_ui.exe" | cut -d' ' -f1)" ]] || {
  echo "Windows alias and retained version differ." >&2
  exit 1
}

declare -a DELETE_DOWNLOADS=()
while IFS= read -r -d '' path; do
  guard_direct_child "${PUBLIC_DOWNLOADS}" "${path}"
  [[ -f "${path}" ]] || {
    echo "Unexpected public-download entry type: ${path}" >&2
    exit 1
  }
  name="$(basename -- "${path}")"
  if ! contains_name "${name}" "${KEEP_DOWNLOADS[@]}"; then
    [[ "${name}" =~ ^GreenVPN_(Android|Setup).*(apk|exe)$ ]] || {
      echo "Unexpected public-download filename: ${name}" >&2
      exit 1
    }
    DELETE_DOWNLOADS+=("${path}")
  fi
done < <(find "${PUBLIC_DOWNLOADS}" -mindepth 1 -maxdepth 1 -print0)

declare -a DELETE_PAID_RELEASES=()
while IFS= read -r -d '' path; do
  guard_direct_child "${PAID_RELEASES}" "${path}"
  [[ -d "${path}" ]] || {
    echo "Unexpected paid-release entry type: ${path}" >&2
    exit 1
  }
  name="$(basename -- "${path}")"
  if [[ "${name}" != "${CURRENT_PAID_RELEASE}" && "${name}" != "${PREVIOUS_PAID_RELEASE}" ]]; then
    [[ "${name}" =~ ^paid-beta-[0-9A-Za-z._-]+$ ]] || {
      echo "Unexpected paid-release directory: ${name}" >&2
      exit 1
    }
    DELETE_PAID_RELEASES+=("${path}")
  fi
done < <(find "${PAID_RELEASES}" -mindepth 1 -maxdepth 1 -print0)

declare -a DELETE_SITE_BACKUPS=()
while IFS= read -r -d '' path; do
  guard_direct_child "${SITE_BACKUPS}" "${path}"
  name="$(basename -- "${path}")"
  if ! contains_name "${name}" "${KEEP_SITE_BACKUPS[@]}"; then
    DELETE_SITE_BACKUPS+=("${path}")
  fi
done < <(find "${SITE_BACKUPS}" -mindepth 1 -maxdepth 1 -print0)

declare -a DELETE_STABLE_CHECKPOINTS=()
while IFS= read -r -d '' path; do
  guard_direct_child "${STABLE_CHECKPOINTS}" "${path}"
  name="$(basename -- "${path}")"
  [[ "${name}" =~ ^stable_[0-9A-Za-z._-]+$ ]] || {
    echo "Unexpected stable-checkpoint entry: ${name}" >&2
    exit 1
  }
  DELETE_STABLE_CHECKPOINTS+=("${path}")
done < <(find "${STABLE_CHECKPOINTS}" -mindepth 1 -maxdepth 1 -print0)

BEFORE_BYTES="$((
  $(du -sb -- "${PUBLIC_DOWNLOADS}" | cut -f1) +
  $(du -sb -- "${PAID_RELEASES}" | cut -f1) +
  $(du -sb -- "${SITE_BACKUPS}" | cut -f1) +
  $(du -sb -- "${STABLE_CHECKPOINTS}" | cut -f1)
))"
echo "control_prune_host=${HOSTNAME_SHORT}"
echo "control_prune_apply=${APPLY}"
echo "control_prune_before_bytes=${BEFORE_BYTES}"
echo "control_prune_public_files=${#DELETE_DOWNLOADS[@]}"
echo "control_prune_paid_releases=${#DELETE_PAID_RELEASES[@]}"
echo "control_prune_site_backup_entries=${#DELETE_SITE_BACKUPS[@]}"
echo "control_prune_stable_checkpoint_entries=${#DELETE_STABLE_CHECKPOINTS[@]}"
[[ "${APPLY}" -eq 1 ]] || exit 0

for path in "${DELETE_DOWNLOADS[@]}"; do
  guard_direct_child "${PUBLIC_DOWNLOADS}" "${path}"
  rm -f -- "${path}"
done
for path in "${DELETE_PAID_RELEASES[@]}"; do
  guard_direct_child "${PAID_RELEASES}" "${path}"
  rm -rf --one-file-system -- "${path}"
done
for path in "${DELETE_SITE_BACKUPS[@]}"; do
  guard_direct_child "${SITE_BACKUPS}" "${path}"
  if [[ -d "${path}" ]]; then
    rm -rf --one-file-system -- "${path}"
  else
    rm -f -- "${path}"
  fi
done
for path in "${DELETE_STABLE_CHECKPOINTS[@]}"; do
  guard_direct_child "${STABLE_CHECKPOINTS}" "${path}"
  if [[ -d "${path}" ]]; then
    rm -rf --one-file-system -- "${path}"
  else
    rm -f -- "${path}"
  fi
done

[[ "$(readlink -f -- "${PAID_CURRENT_LINK}")" == "${EXPECTED_PAID_TARGET}" ]] || exit 1
for name in "${KEEP_DOWNLOADS[@]}"; do
  [[ -f "${PUBLIC_DOWNLOADS}/${name}" ]] || exit 1
done
for name in "${KEEP_SITE_BACKUPS[@]}"; do
  [[ -f "${SITE_BACKUPS}/${name}" ]] || exit 1
done

AFTER_BYTES="$((
  $(du -sb -- "${PUBLIC_DOWNLOADS}" | cut -f1) +
  $(du -sb -- "${PAID_RELEASES}" | cut -f1) +
  $(du -sb -- "${SITE_BACKUPS}" | cut -f1) +
  $(du -sb -- "${STABLE_CHECKPOINTS}" | cut -f1)
))"
echo "control_prune_status=applied"
echo "control_prune_after_bytes=${AFTER_BYTES}"
echo "control_prune_freed_bytes=$((BEFORE_BYTES - AFTER_BYTES))"
