#!/usr/bin/env bash
set -euo pipefail

APPLY=0
EXPECTED_PUBLIC_IP=""
APPROVED_EXISTING_HOST=""
CANARY_HOST="5.129.216.42"
CANARY_DOMAIN="nl2.vpn.greenvpn.pro"
CANARY_PORT="8443"
SERVICE_NAME="greenvpn-naive-https-canary"
SERVICE_USER="greenvpn-naive"
CLIENT_CONFIG_FILE="/etc/greenvpn-transport/naive-https-canary.client.json"
MATERIAL_ROOT="/etc/greenvpn-naive-https-canary"
CONFIG_FILE="${MATERIAL_ROOT}/Caddyfile"
INSTALL_ROOT="/opt/greenvpn-canary/naive-https"
CERT_FILE="/etc/greenvpn-transport/hysteria2-canary/acme/certificates/acme-v02.api.letsencrypt.org-directory/nl2.vpn.greenvpn.pro/nl2.vpn.greenvpn.pro.crt"
CERT_KEY_FILE="/etc/greenvpn-transport/hysteria2-canary/acme/certificates/acme-v02.api.letsencrypt.org-directory/nl2.vpn.greenvpn.pro/nl2.vpn.greenvpn.pro.key"

GO_VERSION="1.26.5"
GO_ARCHIVE_SHA256="5c2c3b16caefa1d968a94c1daca04a7ca301a496d9b086e17ad77bb81393f053"
GO_ARCHIVE_URL="https://go.dev/dl/go${GO_VERSION}.linux-amd64.tar.gz"
CADDY_VERSION="v2.11.4"
XCADDY_VERSION="v0.4.5"
FORWARDPROXY_COMMIT="d62c80d3dd2c706b6b87579844d2397bddd18317"
NAIVE_VERSION="v150.0.7871.63-1"
NAIVE_LINUX_ARCHIVE_SHA256="0c4f506ce66a7881892fd6932b542c53fc06ac2351987756096c61e753c687bf"
NAIVE_LINUX_ARCHIVE_URL="https://github.com/klzgrad/naiveproxy/releases/download/${NAIVE_VERSION}/naiveproxy-${NAIVE_VERSION}-linux-x64.tar.xz"

usage() {
  cat <<'USAGE'
Bootstrap the owner-approved Naive HTTPS canary on Green VPN NL2.

Default mode is dry-run. Apply requires the exact NL2 tuple:
  bootstrap_naive_https_canary.sh --expected-public-ip 5.129.216.42 \
      --approved-existing-host 5.129.216.42 --apply

The initial canary listens on TCP/8443 so VLESS REALITY TCP/443 and all
stable transports remain untouched. It uses the existing trusted
nl2.vpn.greenvpn.pro certificate and never prints proxy credentials.
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --apply) APPLY=1; shift ;;
    --expected-public-ip) EXPECTED_PUBLIC_IP="${2:?missing expected public ip}"; shift 2 ;;
    --approved-existing-host) APPROVED_EXISTING_HOST="${2:?missing approved existing host}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
done

if [[ "${EUID}" -ne 0 ]]; then
  echo "Run as root on NL2." >&2
  exit 1
fi
for command in curl openssl python3 sha256sum systemctl ss tar; do
  command -v "${command}" >/dev/null 2>&1 || {
    echo "Required command is missing: ${command}" >&2
    exit 1
  }
done

PUBLIC_IP="$(curl -fsS --max-time 5 https://api.ipify.org || true)"
if [[ "${PUBLIC_IP}" != "${CANARY_HOST}" ]]; then
  echo "Refusing Naive HTTPS bootstrap outside exact NL2 host." >&2
  exit 1
fi
if [[ "${APPLY}" -eq 1 && ( \
  "${EXPECTED_PUBLIC_IP}" != "${CANARY_HOST}" \
  || "${APPROVED_EXISTING_HOST}" != "${CANARY_HOST}" ) ]]; then
  echo "Apply requires exact NL2 expected/approved host values." >&2
  exit 1
fi
if [[ "$(getent ahostsv4 "${CANARY_DOMAIN}" | awk 'NR==1 {print $1}')" != "${CANARY_HOST}" ]]; then
  echo "Canary domain does not resolve to the exact NL2 host." >&2
  exit 1
fi
if [[ ! -s "${CERT_FILE}" || ! -s "${CERT_KEY_FILE}" ]]; then
  echo "Trusted NL2 certificate material is missing." >&2
  exit 1
fi
if ! openssl x509 -in "${CERT_FILE}" -noout -checkend 604800 >/dev/null 2>&1; then
  echo "Trusted NL2 certificate expires in less than seven days." >&2
  exit 1
fi
if ! openssl x509 -in "${CERT_FILE}" -noout -checkhost "${CANARY_DOMAIN}" >/dev/null 2>&1; then
  echo "Trusted NL2 certificate does not cover the canary domain." >&2
  exit 1
fi

if systemctl is-active --quiet "${SERVICE_NAME}.service"; then
  PORT_STATE="managed-active"
elif ss -H -lnt 2>/dev/null | awk '{print $4}' | grep -Eq "(:|])${CANARY_PORT}$"; then
  echo "TCP/${CANARY_PORT} is already occupied by an unmanaged service." >&2
  exit 1
else
  PORT_STATE="free"
fi

echo "Green VPN Naive HTTPS canary bootstrap plan"
echo "public_ip=${PUBLIC_IP}"
echo "domain=${CANARY_DOMAIN}"
echo "listen=tcp/${CANARY_PORT}"
echo "service=${SERVICE_NAME}.service"
echo "go_version=${GO_VERSION}"
echo "caddy_version=${CADDY_VERSION}"
echo "xcaddy_version=${XCADDY_VERSION}"
echo "forwardproxy_commit=${FORWARDPROXY_COMMIT}"
echo "naive_version=${NAIVE_VERSION}"
echo "port_state=${PORT_STATE}"
echo "mode=$([[ "${APPLY}" -eq 1 ]] && echo apply || echo dry-run)"
echo "stable_wireguard=not_changed"
echo "amneziawg_canary=not_changed"
echo "hysteria2_canary=not_changed"
echo "vless_reality_canary=not_changed"
echo "public_catalog=not_changed"

if [[ "${APPLY}" -ne 1 ]]; then
  echo "Dry-run only. Re-run with exact host approval and --apply."
  exit 0
fi

umask 077
STAMP="$(date -u +%Y%m%dT%H%M%SZ)"
BACKUP_ROOT="/root/greenvpn-naive-https-prechange/${STAMP}"
WORK_ROOT="$(mktemp -d /tmp/greenvpn-naive-https.XXXXXX)"
SMOKE_PID=""
cleanup() {
  if [[ -n "${SMOKE_PID}" ]]; then
    kill "${SMOKE_PID}" >/dev/null 2>&1 || true
    wait "${SMOKE_PID}" 2>/dev/null || true
  fi
  rm -rf -- "${WORK_ROOT}"
}
trap cleanup EXIT
mkdir -p "${BACKUP_ROOT}"
chmod 0700 "${BACKUP_ROOT}"
for path in \
  "${CONFIG_FILE}" "${CLIENT_CONFIG_FILE}" "${MATERIAL_ROOT}" "${INSTALL_ROOT}" \
  "/etc/systemd/system/${SERVICE_NAME}.service"; do
  [[ ! -e "${path}" ]] || cp -a -- "${path}" "${BACKUP_ROOT}/"
done

stable_hash() {
  if [[ -f "$1" ]]; then sha256sum "$1" | awk '{print $1}'; else echo absent; fi
}
WG_HASH_BEFORE="$(stable_hash /etc/wireguard/wg0.conf)"
AWG_HASH_BEFORE="$(stable_hash /etc/greenvpn-transport/awgcanary0.conf)"
HYSTERIA_HASH_BEFORE="$(stable_hash /etc/greenvpn-transport/hysteria2-canary.yaml)"
VLESS_HASH_BEFORE="$(stable_hash /etc/greenvpn-transport/vless-reality-xhttp-canary.json)"

REUSE_PINNED_BINARIES=0
if [[ -x "${INSTALL_ROOT}/bin/caddy" && -x "${INSTALL_ROOT}/bin/naive" ]]; then
  CADDY_BUILD_INFO="$("${INSTALL_ROOT}/bin/caddy" build-info 2>/dev/null || true)"
  NAIVE_BUILD_INFO="$("${INSTALL_ROOT}/bin/naive" --version 2>&1 || true)"
  if grep -Fq $'dep\tgithub.com/caddyserver/caddy/v2\tv2.11.4' <<<"${CADDY_BUILD_INFO}" \
    && grep -Fq "github.com/klzgrad/forwardproxy" <<<"${CADDY_BUILD_INFO}" \
    && grep -Fq "${FORWARDPROXY_COMMIT:0:12}" <<<"${CADDY_BUILD_INFO}" \
    && grep -Fxq 'naive 150.0.7871.63' <<<"${NAIVE_BUILD_INFO}"; then
    REUSE_PINNED_BINARIES=1
    echo "pinned_binaries=reused_after_build_metadata_verification"
  fi
fi

if [[ "${REUSE_PINNED_BINARIES}" -ne 1 ]]; then
curl -fL --retry 3 --connect-timeout 10 --max-time 240 \
  "${GO_ARCHIVE_URL}" -o "${WORK_ROOT}/go.tar.gz"
printf '%s  %s\n' "${GO_ARCHIVE_SHA256}" "${WORK_ROOT}/go.tar.gz" | sha256sum -c -
mkdir "${WORK_ROOT}/go-root"
tar -xzf "${WORK_ROOT}/go.tar.gz" -C "${WORK_ROOT}/go-root"
export PATH="${WORK_ROOT}/go-root/go/bin:${PATH}"
export GOBIN="${WORK_ROOT}/go-bin"
export GOCACHE="${WORK_ROOT}/go-cache"
export GOPATH="${WORK_ROOT}/go-path"
mkdir -p "${GOBIN}" "${GOCACHE}" "${GOPATH}"
go install "github.com/caddyserver/xcaddy/cmd/xcaddy@${XCADDY_VERSION}"
"${GOBIN}/xcaddy" build "${CADDY_VERSION}" \
  --with "github.com/caddyserver/forwardproxy=github.com/klzgrad/forwardproxy@${FORWARDPROXY_COMMIT}" \
  --output "${WORK_ROOT}/caddy"
"${WORK_ROOT}/caddy" list-modules | grep -Fx 'http.handlers.forward_proxy' >/dev/null

curl -fL --retry 3 --connect-timeout 10 --max-time 180 \
  "${NAIVE_LINUX_ARCHIVE_URL}" -o "${WORK_ROOT}/naive.tar.xz"
printf '%s  %s\n' "${NAIVE_LINUX_ARCHIVE_SHA256}" "${WORK_ROOT}/naive.tar.xz" | sha256sum -c -
mkdir "${WORK_ROOT}/naive"
tar -xJf "${WORK_ROOT}/naive.tar.xz" -C "${WORK_ROOT}/naive"
NAIVE_BINARY="$(find "${WORK_ROOT}/naive" -type f -name naive -print -quit)"
if [[ -z "${NAIVE_BINARY}" ]]; then
  echo "Pinned Naive archive does not contain the expected binary." >&2
  exit 1
fi

install -d -m 0755 "${INSTALL_ROOT}/bin" "${INSTALL_ROOT}/licenses"
install -m 0755 "${WORK_ROOT}/caddy" "${INSTALL_ROOT}/bin/caddy"
install -m 0755 "${NAIVE_BINARY}" "${INSTALL_ROOT}/bin/naive"
else
  install -d -m 0755 "${INSTALL_ROOT}/licenses"
fi
curl -fsSL "https://raw.githubusercontent.com/caddyserver/caddy/${CADDY_VERSION}/LICENSE" \
  -o "${INSTALL_ROOT}/licenses/CADDY_APACHE_2.txt"
curl -fsSL "https://raw.githubusercontent.com/klzgrad/forwardproxy/${FORWARDPROXY_COMMIT}/LICENSE" \
  -o "${INSTALL_ROOT}/licenses/FORWARDPROXY_APACHE_2.txt"
curl -fsSL "https://raw.githubusercontent.com/klzgrad/naiveproxy/${NAIVE_VERSION}/LICENSE" \
  -o "${INSTALL_ROOT}/licenses/NAIVEPROXY_BSD_3_CLAUSE.txt"
cat > "${INSTALL_ROOT}/SOURCE" <<EOF
Caddy ${CADDY_VERSION}: https://github.com/caddyserver/caddy/tree/${CADDY_VERSION}
xcaddy ${XCADDY_VERSION}: https://github.com/caddyserver/xcaddy/tree/${XCADDY_VERSION}
forwardproxy ${FORWARDPROXY_COMMIT}: https://github.com/klzgrad/forwardproxy/tree/${FORWARDPROXY_COMMIT}
NaiveProxy ${NAIVE_VERSION}: https://github.com/klzgrad/naiveproxy/tree/${NAIVE_VERSION}
EOF
chmod 0644 "${INSTALL_ROOT}/SOURCE" "${INSTALL_ROOT}"/licenses/*

if ! getent passwd "${SERVICE_USER}" >/dev/null; then
  useradd --system --home-dir /nonexistent --shell /usr/sbin/nologin "${SERVICE_USER}"
fi
SERVICE_GROUP="$(id -gn "${SERVICE_USER}")"
install -d -m 0750 -o root -g "${SERVICE_GROUP}" "${MATERIAL_ROOT}"
if [[ ! -s "${MATERIAL_ROOT}/username" ]]; then
  printf 'green%s\n' "$(openssl rand -hex 6)" > "${MATERIAL_ROOT}/username"
fi
if [[ ! -s "${MATERIAL_ROOT}/password" ]]; then
  openssl rand -hex 24 > "${MATERIAL_ROOT}/password"
fi
install -m 0640 -o root -g "${SERVICE_GROUP}" "${CERT_FILE}" "${MATERIAL_ROOT}/server.crt"
install -m 0640 -o root -g "${SERVICE_GROUP}" "${CERT_KEY_FILE}" "${MATERIAL_ROOT}/server.key"
chown root:"${SERVICE_GROUP}" "${MATERIAL_ROOT}/username" "${MATERIAL_ROOT}/password"
chmod 0640 "${MATERIAL_ROOT}/username" "${MATERIAL_ROOT}/password"
USERNAME="$(tr -d '\r\n' < "${MATERIAL_ROOT}/username")"
PASSWORD="$(tr -d '\r\n' < "${MATERIAL_ROOT}/password")"

cat > "${CONFIG_FILE}" <<EOF
{
  admin off
  auto_https off
  order forward_proxy before respond
  servers {
    protocols h1 h2
  }
}

:${CANARY_PORT}, ${CANARY_DOMAIN}:${CANARY_PORT} {
  tls ${MATERIAL_ROOT}/server.crt ${MATERIAL_ROOT}/server.key
  forward_proxy {
    basic_auth ${USERNAME} ${PASSWORD}
    hide_ip
    hide_via
    probe_resistance
  }
  respond "Not found" 404
}
EOF
chown root:"${SERVICE_GROUP}" "${CONFIG_FILE}"
chmod 0640 "${CONFIG_FILE}"

python3 - "${CLIENT_CONFIG_FILE}" "${CANARY_DOMAIN}" "${CANARY_PORT}" "${USERNAME}" "${PASSWORD}" <<'PY'
import json
import os
import sys

path, host, port, username, password = sys.argv[1:]
config = {
    "listen": "socks://127.0.0.1:1982",
    "proxy": f"https://{username}:{password}@{host}:{port}",
}
temporary = path + ".tmp"
with open(temporary, "w", encoding="utf-8") as handle:
    json.dump(config, handle, separators=(",", ":"))
    handle.write("\n")
os.chmod(temporary, 0o600)
os.replace(temporary, path)
PY
chmod 0600 "${CLIENT_CONFIG_FILE}"

cat > "/etc/systemd/system/${SERVICE_NAME}.service" <<EOF
[Unit]
Description=Green VPN guarded Naive HTTPS canary
After=network-online.target
Wants=network-online.target

[Service]
Type=notify
User=${SERVICE_USER}
Group=${SERVICE_GROUP}
Environment=XDG_CONFIG_HOME=/var/lib/${SERVICE_NAME}/config
Environment=XDG_DATA_HOME=/var/lib/${SERVICE_NAME}/data
StateDirectory=${SERVICE_NAME}
ExecStart=${INSTALL_ROOT}/bin/caddy run --config ${CONFIG_FILE} --adapter caddyfile
ExecReload=${INSTALL_ROOT}/bin/caddy reload --config ${CONFIG_FILE} --adapter caddyfile --force
Restart=on-failure
RestartSec=3
NoNewPrivileges=true
PrivateTmp=true
PrivateDevices=true
ProtectSystem=strict
ProtectHome=true
ProtectKernelTunables=true
ProtectKernelModules=true
ProtectControlGroups=true
RestrictAddressFamilies=AF_UNIX AF_INET AF_INET6
LockPersonality=true
MemoryDenyWriteExecute=true
SystemCallArchitectures=native
UMask=0027

[Install]
WantedBy=multi-user.target
EOF
chmod 0644 "/etc/systemd/system/${SERVICE_NAME}.service"

"${INSTALL_ROOT}/bin/caddy" validate --config "${CONFIG_FILE}" --adapter caddyfile >/dev/null
systemctl daemon-reload
systemctl enable --now "${SERVICE_NAME}.service"
systemctl is-active --quiet "${SERVICE_NAME}.service"
ss -H -lnt | awk '{print $4}' | grep -Eq "(:|])${CANARY_PORT}$"

"${INSTALL_ROOT}/bin/naive" "${CLIENT_CONFIG_FILE}" >"${WORK_ROOT}/naive-smoke.log" 2>&1 &
SMOKE_PID="$!"
for _ in $(seq 1 60); do
  if ss -H -lnt | awk '{print $4}' | grep -Eq '(:|])1982$'; then break; fi
  kill -0 "${SMOKE_PID}" 2>/dev/null || {
    echo "Naive smoke client exited before opening loopback SOCKS." >&2
    exit 1
  }
  sleep 0.25
done
TRACE="$(curl -fsS --max-time 30 --socks5-hostname 127.0.0.1:1982 https://1.1.1.1/cdn-cgi/trace)"
if ! grep -Fx "ip=${CANARY_HOST}" <<<"${TRACE}" >/dev/null; then
  echo "Naive HTTPS data-plane smoke did not return NL2 egress." >&2
  exit 1
fi
kill "${SMOKE_PID}" >/dev/null 2>&1 || true
wait "${SMOKE_PID}" 2>/dev/null || true
SMOKE_PID=""

[[ "$(stable_hash /etc/wireguard/wg0.conf)" == "${WG_HASH_BEFORE}" ]]
[[ "$(stable_hash /etc/greenvpn-transport/awgcanary0.conf)" == "${AWG_HASH_BEFORE}" ]]
[[ "$(stable_hash /etc/greenvpn-transport/hysteria2-canary.yaml)" == "${HYSTERIA_HASH_BEFORE}" ]]
[[ "$(stable_hash /etc/greenvpn-transport/vless-reality-xhttp-canary.json)" == "${VLESS_HASH_BEFORE}" ]]
systemctl is-active --quiet wg-quick@wg0.service
systemctl is-active --quiet greenvpn-amneziawg-canary.service
systemctl is-active --quiet greenvpn-hysteria2-canary.service
systemctl is-active --quiet greenvpn-vless-reality-canary.service

cat > "${MATERIAL_ROOT}/build-manifest" <<EOF
go=${GO_VERSION}
go_archive_sha256=${GO_ARCHIVE_SHA256}
caddy=${CADDY_VERSION}
xcaddy=${XCADDY_VERSION}
forwardproxy=${FORWARDPROXY_COMMIT}
naive=${NAIVE_VERSION}
naive_linux_archive_sha256=${NAIVE_LINUX_ARCHIVE_SHA256}
caddy_binary_sha256=$(sha256sum "${INSTALL_ROOT}/bin/caddy" | awk '{print $1}')
naive_binary_sha256=$(sha256sum "${INSTALL_ROOT}/bin/naive" | awk '{print $1}')
EOF
chown root:"${SERVICE_GROUP}" "${MATERIAL_ROOT}/build-manifest"
chmod 0640 "${MATERIAL_ROOT}/build-manifest"

echo "Naive HTTPS canary installed and data-plane smoke passed."
echo "backup=${BACKUP_ROOT}"
echo "service_active=true"
echo "egress=${CANARY_HOST}"
echo "credentials=stored_root_only_not_printed"
echo "stable_transports=verified_unchanged"
