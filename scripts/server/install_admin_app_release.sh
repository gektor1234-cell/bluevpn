#!/usr/bin/env bash
set -euo pipefail

APPLY=0
SOURCE_DIR=""
RELEASE_ID=""
TARGET_DIR="/var/www/greenvpn-admin"
VERIFY_URL="https://admin.greenvpn.pro/"
FILES=(index.html app.js styles.css)

usage() {
  cat <<'EOF'
Install the Green VPN admin static application on the protected Timeweb host.

Usage:
  install_admin_app_release.sh \
    --source-dir PATH \
    --release-id ID \
    [--apply]

The default is a dry run. Apply mode creates a root-only backup, replaces only
the three canonical static files atomically, validates nginx and the protected
HTTP surface, and restores the previous files automatically on error.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --source-dir) SOURCE_DIR="${2:?missing source directory}"; shift 2 ;;
    --release-id) RELEASE_ID="${2:?missing release id}"; shift 2 ;;
    --apply) APPLY=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
done

[[ "$RELEASE_ID" =~ ^[A-Za-z0-9][A-Za-z0-9._-]{4,120}$ ]] || {
  echo "Invalid release id" >&2
  exit 2
}
[[ -d "$SOURCE_DIR" && ! -L "$SOURCE_DIR" ]] || { echo "Source directory is missing or unsafe" >&2; exit 2; }
[[ -d "$TARGET_DIR" && ! -L "$TARGET_DIR" ]] || { echo "Target directory is missing or unsafe" >&2; exit 2; }
for name in "${FILES[@]}"; do
  [[ -f "$SOURCE_DIR/$name" && ! -L "$SOURCE_DIR/$name" ]] || {
    echo "Source file is missing or unsafe: $name" >&2
    exit 2
  }
  if [[ -e "$TARGET_DIR/$name" && ( ! -f "$TARGET_DIR/$name" || -L "$TARGET_DIR/$name" ) ]]; then
    echo "Target file is unsafe: $name" >&2
    exit 2
  fi
done

grep -Fq '<body>' "$SOURCE_DIR/index.html"
grep -Fq 'src="./app.js"' "$SOURCE_DIR/index.html"
grep -Fq 'href="./styles.css"' "$SOURCE_DIR/index.html"
grep -Fq 'cancelStaleBillingOrder' "$SOURCE_DIR/app.js"
grep -Fq '.small-button.danger' "$SOURCE_DIR/styles.css"

echo "mode=$([[ $APPLY -eq 1 ]] && echo apply || echo dry-run)"
echo "release_id=$RELEASE_ID"
for name in "${FILES[@]}"; do
  echo "source_${name//./_}_sha256=$(sha256sum -- "$SOURCE_DIR/$name" | awk '{print toupper($1)}')"
done
[[ $APPLY -eq 1 ]] || exit 0
[[ $EUID -eq 0 ]] || { echo "Run apply mode as root" >&2; exit 1; }

timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
backup_dir="/root/greenvpn-admin-static-backups/${timestamp}-${RELEASE_ID}"
install -d -m 700 -- "$backup_dir"
for name in "${FILES[@]}"; do
  if [[ -f "$TARGET_DIR/$name" ]]; then
    cp -a -- "$TARGET_DIR/$name" "$backup_dir/$name"
  else
    install -m 600 /dev/null "$backup_dir/.missing-$name"
  fi
done
chmod 600 "$backup_dir"/* 2>/dev/null || true

modified=0
rollback_on_error() {
  code=$?
  trap - ERR
  if [[ $modified -eq 1 ]]; then
    for name in "${FILES[@]}"; do
      if [[ -f "$backup_dir/$name" ]]; then
        install -m 644 -- "$backup_dir/$name" "$TARGET_DIR/$name"
      elif [[ -f "$backup_dir/.missing-$name" ]]; then
        rm -f -- "$TARGET_DIR/$name"
      fi
    done
    nginx -t >/dev/null 2>&1 && systemctl reload nginx >/dev/null 2>&1 || true
  fi
  exit "$code"
}
trap rollback_on_error ERR

for name in "${FILES[@]}"; do
  temporary="$TARGET_DIR/.${name}.tmp.$$"
  install -m 644 -- "$SOURCE_DIR/$name" "$temporary"
  mv -f -- "$temporary" "$TARGET_DIR/$name"
done
modified=1
chown root:root "${FILES[@]/#/$TARGET_DIR/}"

for name in "${FILES[@]}"; do
  source_sha="$(sha256sum -- "$SOURCE_DIR/$name" | awk '{print toupper($1)}')"
  target_sha="$(sha256sum -- "$TARGET_DIR/$name" | awk '{print toupper($1)}')"
  [[ "$source_sha" == "$target_sha" ]] || { echo "Installed hash mismatch: $name" >&2; exit 1; }
done
nginx -t
systemctl reload nginx
http_status="$(curl --silent --show-error --max-time 15 --output /dev/null --write-out '%{http_code}' "$VERIFY_URL")"
[[ "$http_status" == "401" ]] || { echo "Protected admin surface returned HTTP $http_status" >&2; exit 1; }

trap - ERR
echo "admin_static_release_status=ok"
echo "backup_dir=$backup_dir"
