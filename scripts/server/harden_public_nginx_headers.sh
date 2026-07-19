#!/usr/bin/env bash
set -euo pipefail

MODE="dry-run"

usage() {
  cat <<'EOF'
Usage: harden_public_nginx_headers.sh [--apply]

Audits the Green VPN Nginx sites and, with --apply, installs a conservative
security-header baseline. Apply mode creates a root-only backup, validates the
complete Nginx configuration and rolls back automatically if validation fails.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --apply) MODE="apply"; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
done

[[ "${EUID}" -eq 0 ]] || { echo "Run as root." >&2; exit 1; }
for command in nginx python3 readlink systemctl; do
  command -v "${command}" >/dev/null 2>&1 || { echo "Missing command: ${command}" >&2; exit 1; }
done

declare -a configs=()
for path in \
  /etc/nginx/sites-available/greenvpn-site \
  /etc/nginx/sites-available/greenvpn-api \
  /etc/nginx/sites-available/greenvpn-admin \
  /etc/nginx/sites-available/greenvpn-ruvds-m9-api \
  /etc/nginx/snippets/greenvpn-paid-beta-api.conf \
  /etc/nginx/snippets/greenvpn-paid-beta-site.conf; do
  [[ -f "${path}" ]] && configs+=("${path}")
done

[[ ${#configs[@]} -gt 0 ]] || { echo "No Green VPN Nginx configs found." >&2; exit 1; }

echo "mode=${MODE}"
printf 'config=%s\n' "${configs[@]}"
if [[ "${MODE}" != "apply" ]]; then
  echo "changed=false"
  echo "next=rerun with --apply"
  exit 0
fi

timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
backup_dir="/root/greenvpn-nginx-security-backups/${timestamp}"
install -d -m 700 "${backup_dir}"
for path in "${configs[@]}"; do
  relative="${path#/etc/nginx/}"
  target="${backup_dir}/${relative}"
  install -d -m 700 "$(dirname "${target}")"
  cp -a "${path}" "${target}"
done

rollback() {
  local status=$?
  if [[ ${status} -eq 0 ]]; then
    return
  fi
  echo "Header hardening failed; restoring ${backup_dir}" >&2
  for path in "${configs[@]}"; do
    relative="${path#/etc/nginx/}"
    cp -a "${backup_dir}/${relative}" "${path}"
  done
  nginx -t >/dev/null 2>&1 && systemctl reload nginx >/dev/null 2>&1 || true
  exit "${status}"
}
trap rollback EXIT

python3 - "${configs[@]}" <<'PY'
from __future__ import annotations

import pathlib
import sys

PUBLIC_MARKER = "# Green VPN public security headers"
API_MARKER = "# Green VPN API security headers"

PUBLIC_HEADERS = [
    PUBLIC_MARKER,
    'add_header Strict-Transport-Security "max-age=31536000" always;',
    'add_header X-Frame-Options "DENY" always;',
    'add_header Content-Security-Policy "default-src \'self\'; style-src \'self\' \'unsafe-inline\'; img-src \'self\' data:; object-src \'none\'; base-uri \'self\'; form-action \'self\'; frame-ancestors \'none\'" always;',
    'add_header Permissions-Policy "camera=(), microphone=(), geolocation=(), payment=()" always;',
]

API_HEADERS = [
    API_MARKER,
    'add_header Strict-Transport-Security "max-age=31536000" always;',
    'add_header X-Content-Type-Options "nosniff" always;',
    'add_header Referrer-Policy "no-referrer" always;',
    'add_header X-Frame-Options "DENY" always;',
    'add_header Content-Security-Policy "default-src \'none\'; base-uri \'none\'; frame-ancestors \'none\'" always;',
    'add_header Permissions-Policy "camera=(), microphone=(), geolocation=(), payment=()" always;',
]

ADMIN_CSP = (
    'add_header Content-Security-Policy '
    '"default-src \'self\'; connect-src \'self\' https://api.greenvpn.pro '
    'https://176-113-81-35.sslip.io; img-src \'self\' data:; style-src \'self\'; '
    'script-src \'self\'; object-src \'none\'; base-uri \'none\'; form-action \'self\'; '
    'frame-ancestors \'none\'" always;'
)


def blocks(text: str, opener: str) -> list[tuple[int, int]]:
    result: list[tuple[int, int]] = []
    cursor = 0
    while True:
        start = text.find(opener, cursor)
        if start < 0:
            return result
        brace = text.find("{", start)
        depth = 0
        end = -1
        for index in range(brace, len(text)):
            if text[index] == "{":
                depth += 1
            elif text[index] == "}":
                depth -= 1
                if depth == 0:
                    end = index + 1
                    break
        if end < 0:
            raise RuntimeError(f"Unclosed Nginx block starting at {start}")
        result.append((start, end))
        cursor = end


def indent_lines(lines: list[str], spaces: int) -> str:
    prefix = " " * spaces
    return "\n".join(prefix + line for line in lines)


def patch_matching_block(
    text: str,
    opener: str,
    required: tuple[str, ...],
    marker: str,
    headers: list[str],
) -> str:
    for start, end in blocks(text, opener):
        block = text[start:end]
        if not all(value in block for value in required):
            continue
        if marker in block:
            return text
        first_newline = block.find("\n")
        if first_newline < 0:
            raise RuntimeError(f"No insertion point in block {opener}")
        patched = block[: first_newline + 1] + indent_lines(headers, 4) + "\n" + block[first_newline + 1 :]
        return text[:start] + patched + text[end:]
    raise RuntimeError(f"Expected Nginx block not found: {opener} {required}")


def patch_location(text: str, opener: str, marker: str, headers: list[str]) -> str:
    return patch_matching_block(text, opener, (), marker, headers)


def patch_admin(text: str) -> str:
    old = 'add_header Content-Security-Policy "frame-ancestors \'none\'" always;'
    if old in text:
        text = text.replace(old, ADMIN_CSP, 1)
    elif ADMIN_CSP not in text:
        raise RuntimeError("Admin CSP anchor missing")
    return patch_matching_block(
        text,
        "server {",
        ("listen 443", "server_name admin.greenvpn.pro"),
        PUBLIC_MARKER,
        [
            PUBLIC_MARKER,
            'add_header Strict-Transport-Security "max-age=31536000" always;',
            'add_header Permissions-Policy "camera=(), microphone=(), geolocation=(), payment=()" always;',
        ],
    )


for raw_path in sys.argv[1:]:
    path = pathlib.Path(raw_path)
    text = path.read_text(encoding="utf-8")
    original = text
    name = path.name

    if name == "greenvpn-site":
        text = patch_matching_block(
            text,
            "server {",
            ("listen 443", "server_name greenvpn.pro"),
            PUBLIC_MARKER,
            PUBLIC_HEADERS,
        )
        text = patch_location(text, "location /downloads/ {", PUBLIC_MARKER, PUBLIC_HEADERS)
    elif name == "greenvpn-api":
        text = patch_matching_block(
            text,
            "server {",
            ("listen 443", "server_name api.greenvpn.pro"),
            API_MARKER,
            API_HEADERS,
        )
    elif name == "greenvpn-admin":
        text = patch_admin(text)
    elif name == "greenvpn-ruvds-m9-api":
        text = patch_matching_block(
            text,
            "server {",
            ("listen 443", "server_name 176-113-81-35.sslip.io"),
            API_MARKER,
            API_HEADERS,
        )
        text = patch_location(text, "location /downloads/ {", PUBLIC_MARKER, PUBLIC_HEADERS)
        text = patch_location(text, "location /assets/ {", PUBLIC_MARKER, PUBLIC_HEADERS)
    elif name == "greenvpn-paid-beta-api.conf":
        text = patch_location(text, "location /paid-beta-api/ {", API_MARKER, API_HEADERS)
        text = patch_location(text, "location ^~ /yookassa-review-20260711/ {", PUBLIC_MARKER, PUBLIC_HEADERS)
    elif name == "greenvpn-paid-beta-site.conf":
        text = patch_location(text, "location /paid-beta/ {", PUBLIC_MARKER, PUBLIC_HEADERS)

    if text != original:
        path.write_text(text, encoding="utf-8")
        print(f"changed={path}")
    else:
        print(f"unchanged={path}")
PY

nginx -t
systemctl reload nginx
trap - EXIT

echo "backup=${backup_dir}"
echo "nginx_config_ok=true"
echo "nginx_reloaded=true"
