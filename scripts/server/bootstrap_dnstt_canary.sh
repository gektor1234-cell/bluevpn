#!/usr/bin/env bash
set -euo pipefail

APPLY=0
EXPECTED_PUBLIC_IP=""
APPROVED_EXISTING_HOST=""
CANARY_HOST="5.129.216.42"
CANARY_ZONE="t.greenvpn.pro"
CANARY_NS="tns.greenvpn.pro"
CANARY_PORT="53"
SOCKS_PORT="1083"
SERVICE_USER="greenvpn-dnstt"
SERVER_SERVICE="greenvpn-dnstt-canary"
SOCKS_SERVICE="greenvpn-dnstt-socks-canary"
INSTALL_ROOT="/opt/greenvpn-canary/dnstt"
CONFIG_ROOT="/etc/greenvpn-dnstt-canary"
FAILED_STAGING_CONFIG_ROOT="/etc/greenvpn-transport/dnstt-canary"
CLIENT_CONFIG_FILE="/etc/greenvpn-transport/dnstt-canary.client.json"
SERVER_BINARY_SOURCE="/root/greenvpn-dnstt-build-20260501/out/dnstt-server-linux-amd64"
CLIENT_BINARY_SOURCE="/root/greenvpn-dnstt-build-20260501/out/dnstt-client-linux-amd64"
XRAY_BINARY_SOURCE="/opt/greenvpn-canary/xray-vless-reality/bin/xray"
DNSTT_SOURCE_VERSION="20260501"
DNSTT_SOURCE_COMMIT="0c5c52a57d899c05428c116898941761a2ed83c2"
DNSTT_ARCHIVE_SHA256="a7b21d3d787570d9127643e360e150d2da7b33aa8039d0546a04dcfe8ee1864f"
DNSTT_SERVER_SHA256="cf3e6a3091752b72e94e360eaad76e3cb14b69923af691e6477aa3f33e740895"
DNSTT_CLIENT_SHA256="366e30297caf3289d9c03bf0a3c8f4522e8972fa7ddd3d289d7887ad01daf8fe"
XRAY_SHA256="5200ed9b358cf380b2d9f1fe28c7e56220c0159adcd86a64592246d8257a043c"

usage() {
  cat <<'USAGE'
Bootstrap the owner-approved isolated dnstt last-resort canary on Green VPN NL2.

Dry-run is the default. Apply requires the exact NL2 tuple:
  bootstrap_dnstt_canary.sh --expected-public-ip 5.129.216.42 \
      --approved-existing-host 5.129.216.42 --apply

The script does not modify registrar DNS, dnsmasq, systemd-resolved, existing
VPN transports, the public catalog, control planes, databases, or installers.
It binds only 5.129.216.42:53/udp and keeps its proxy on 127.0.0.1:1083.
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --apply) APPLY=1; shift ;;
    --expected-public-ip) EXPECTED_PUBLIC_IP="${2:?missing expected public ip}"; shift 2 ;;
    --approved-existing-host) APPROVED_EXISTING_HOST="${2:?missing approved existing host}"; shift 2 ;;
    --server-binary) SERVER_BINARY_SOURCE="${2:?missing server binary}"; shift 2 ;;
    --client-binary) CLIENT_BINARY_SOURCE="${2:?missing client binary}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
done

[[ "${EUID}" -eq 0 ]] || { echo "Run as root on NL2." >&2; exit 1; }
for command in curl openssl python3 sha256sum systemctl ss getent; do
  command -v "${command}" >/dev/null 2>&1 || { echo "Required command missing: ${command}" >&2; exit 1; }
done

PUBLIC_IP="$(curl -4fsS --max-time 5 https://api.ipify.org || true)"
[[ "${PUBLIC_IP}" == "${CANARY_HOST}" ]] || { echo "Refusing dnstt bootstrap outside exact NL2 host." >&2; exit 1; }
if [[ "${APPLY}" -eq 1 && ( "${EXPECTED_PUBLIC_IP}" != "${CANARY_HOST}" || "${APPROVED_EXISTING_HOST}" != "${CANARY_HOST}" ) ]]; then
  echo "Apply requires exact NL2 expected/approved host values." >&2
  exit 1
fi

for pair in \
  "${SERVER_BINARY_SOURCE}:${DNSTT_SERVER_SHA256}" \
  "${CLIENT_BINARY_SOURCE}:${DNSTT_CLIENT_SHA256}" \
  "${XRAY_BINARY_SOURCE}:${XRAY_SHA256}"; do
  path="${pair%%:*}"
  expected="${pair##*:}"
  [[ -f "${path}" && ! -L "${path}" ]] || { echo "Pinned runtime is missing or unsafe: ${path}" >&2; exit 1; }
  [[ "$(sha256sum "${path}" | awk '{print $1}')" == "${expected}" ]] || { echo "Pinned runtime hash mismatch: ${path}" >&2; exit 1; }
done

for unit in wg-quick@wg0 greenvpn-hysteria2-canary greenvpn-vless-reality-canary greenvpn-naive-https-canary; do
  systemctl is-active --quiet "${unit}.service" || { echo "Stable transport unit is not active: ${unit}" >&2; exit 1; }
done

if systemctl is-active --quiet "${SERVER_SERVICE}.service"; then
  PORT_STATE="managed-active"
else
  if ss -H -lun 2>/dev/null | awk '{print $5}' | grep -Eq "^(0\.0\.0\.0|\*|${CANARY_HOST}):${CANARY_PORT}$"; then
    echo "Public UDP/${CANARY_PORT} is occupied by an unmanaged service." >&2
    exit 1
  fi
  PORT_STATE="free"
fi
if ss -H -lnt 2>/dev/null | awk '{print $4}' | grep -Eq "^(0\.0\.0\.0|\*|${CANARY_HOST}):${CANARY_PORT}$"; then
  echo "Public TCP/${CANARY_PORT} must remain unused by dnstt." >&2
  exit 1
fi

echo "Green VPN dnstt canary bootstrap plan"
echo "public_ip=${PUBLIC_IP}"
echo "zone=${CANARY_ZONE}"
echo "nameserver=${CANARY_NS}"
echo "listen=${CANARY_HOST}:${CANARY_PORT}/udp"
echo "upstream=127.0.0.1:${SOCKS_PORT}/tcp"
echo "source_version=${DNSTT_SOURCE_VERSION}"
echo "source_commit=${DNSTT_SOURCE_COMMIT}"
echo "source_archive_sha256=${DNSTT_ARCHIVE_SHA256}"
echo "port_state=${PORT_STATE}"
echo "mode=$([[ "${APPLY}" -eq 1 ]] && echo apply || echo dry-run)"
echo "registrar_dns=not_changed"
echo "dnsmasq=not_changed"
echo "stable_transports=not_changed"
echo "public_catalog=not_changed"

if [[ "${APPLY}" -ne 1 ]]; then
  echo "Dry-run only. Re-run with exact host approval and --apply."
  exit 0
fi

stable_files=(
  /etc/wireguard/wg0.conf
  /etc/greenvpn-transport/awgcanary0.conf
  /etc/greenvpn-transport/hysteria2-canary.yaml
  /etc/greenvpn-transport/vless-reality-xhttp-canary.json
  /etc/greenvpn-naive-https-canary/Caddyfile
)
stable_before="$(mktemp)"
stable_after="$(mktemp)"
cleanup() { rm -f -- "${stable_before}" "${stable_after}"; }
trap cleanup EXIT
for path in "${stable_files[@]}"; do [[ ! -f "${path}" ]] || sha256sum "${path}"; done | sort >"${stable_before}"

if ! getent group "${SERVICE_USER}" >/dev/null; then groupadd --system "${SERVICE_USER}"; fi
if ! getent passwd "${SERVICE_USER}" >/dev/null; then
  useradd --system --gid "${SERVICE_USER}" --home-dir /nonexistent --shell /usr/sbin/nologin "${SERVICE_USER}"
fi

backup_root="/root/greenvpn-dnstt-prechange/$(date -u +%Y%m%dT%H%M%SZ)"
install -d -m 0700 "${backup_root}"
for path in "${CONFIG_ROOT}" "${CLIENT_CONFIG_FILE}" "${INSTALL_ROOT}" \
  "/etc/systemd/system/${SERVER_SERVICE}.service" "/etc/systemd/system/${SOCKS_SERVICE}.service"; do
  [[ ! -e "${path}" ]] || cp -a -- "${path}" "${backup_root}/"
done

install -d -m 0755 "${INSTALL_ROOT}/bin"
install -d -o root -g "${SERVICE_USER}" -m 0750 "${CONFIG_ROOT}"
if [[ -d "${FAILED_STAGING_CONFIG_ROOT}" ]]; then
  for name in server.key server.pub socks-auth.json; do
    if [[ ! -e "${CONFIG_ROOT}/${name}" && -f "${FAILED_STAGING_CONFIG_ROOT}/${name}" && ! -L "${FAILED_STAGING_CONFIG_ROOT}/${name}" ]]; then
      install -m 0600 "${FAILED_STAGING_CONFIG_ROOT}/${name}" "${CONFIG_ROOT}/${name}"
    fi
  done
fi
install -m 0755 "${SERVER_BINARY_SOURCE}" "${INSTALL_ROOT}/bin/dnstt-server"
install -m 0755 "${CLIENT_BINARY_SOURCE}" "${INSTALL_ROOT}/bin/dnstt-client"
install -m 0755 "${XRAY_BINARY_SOURCE}" "${INSTALL_ROOT}/bin/xray"
cat >"${INSTALL_ROOT}/SOURCE" <<EOF
dnstt ${DNSTT_SOURCE_VERSION}
commit=${DNSTT_SOURCE_COMMIT}
source=https://www.bamsoftware.com/software/dnstt/dnstt-${DNSTT_SOURCE_VERSION}.zip
archive_sha256=${DNSTT_ARCHIVE_SHA256}
signer_fingerprint=AD1AB35C674DF572FBCE8B0A6BC758CBC11F6276
public_domain_notice=https://www.bamsoftware.com/software/dnstt/
EOF
chmod 0644 "${INSTALL_ROOT}/SOURCE"

private_key="${CONFIG_ROOT}/server.key"
public_key="${CONFIG_ROOT}/server.pub"
if [[ ! -s "${private_key}" || ! -s "${public_key}" ]]; then
  rm -f -- "${private_key}" "${public_key}"
  "${INSTALL_ROOT}/bin/dnstt-server" -gen-key -privkey-file "${private_key}" -pubkey-file "${public_key}" >/dev/null
fi
chown root:"${SERVICE_USER}" "${private_key}"
chmod 0640 "${private_key}"
chown root:root "${public_key}"
chmod 0644 "${public_key}"

auth_file="${CONFIG_ROOT}/socks-auth.json"
if [[ ! -s "${auth_file}" ]]; then
  username="gvd_$(openssl rand -hex 8)"
  password="$(openssl rand -base64 36 | tr -d '\n')"
  python3 - "${auth_file}" "${username}" "${password}" <<'PY'
import json, os, sys
path, username, password = sys.argv[1:]
fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
with os.fdopen(fd, "w", encoding="utf-8") as f:
    json.dump({"username": username, "password": password}, f, separators=(",", ":"))
    f.write("\n")
PY
fi
chmod 0600 "${auth_file}"

python3 - "${auth_file}" "${CONFIG_ROOT}/xray-socks.json" "${SOCKS_PORT}" <<'PY'
import json, os, sys
auth_path, output_path, port = sys.argv[1], sys.argv[2], int(sys.argv[3])
with open(auth_path, encoding="utf-8") as f:
    auth = json.load(f)
config = {
    "log": {"loglevel": "warning"},
    "inbounds": [{
        "tag": "dnstt-socks",
        "listen": "127.0.0.1",
        "port": port,
        "protocol": "socks",
        "settings": {"auth": "password", "accounts": [{"user": auth["username"], "pass": auth["password"]}], "udp": False},
    }],
    "outbounds": [
        {"tag": "direct", "protocol": "freedom", "settings": {}},
        {"tag": "block", "protocol": "blackhole", "settings": {}},
    ],
    "routing": {"domainStrategy": "AsIs", "rules": [{
        "type": "field",
        "ip": [
            "0.0.0.0/8", "10.0.0.0/8", "100.64.0.0/10", "127.0.0.0/8", "169.254.0.0/16",
            "172.16.0.0/12", "192.0.0.0/24", "192.168.0.0/16", "198.18.0.0/15",
            "224.0.0.0/4", "240.0.0.0/4", "::1/128", "fc00::/7", "fe80::/10", "ff00::/8"
        ],
        "outboundTag": "block",
    }]},
}
fd = os.open(output_path, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o640)
with os.fdopen(fd, "w", encoding="utf-8") as f:
    json.dump(config, f, separators=(",", ":"))
    f.write("\n")
PY
chown root:"${SERVICE_USER}" "${CONFIG_ROOT}/xray-socks.json"
chmod 0640 "${CONFIG_ROOT}/xray-socks.json"

python3 - "${auth_file}" "${public_key}" "${CLIENT_CONFIG_FILE}" "${CANARY_ZONE}" <<'PY'
import json, os, sys
auth_path, pub_path, output_path, zone = sys.argv[1:]
with open(auth_path, encoding="utf-8") as f:
    auth = json.load(f)
with open(pub_path, encoding="utf-8") as f:
    public_key = f.read().strip()
profile = {
    "zone": zone,
    "publicKey": public_key,
    "socks": {"listen": "127.0.0.1:1983", "username": auth["username"], "password": auth["password"]},
    "resolvers": [
        {"mode": "doh", "endpoint": "https://1.1.1.1/dns-query"},
        {"mode": "doh", "endpoint": "https://8.8.8.8/dns-query"},
        {"mode": "dot", "endpoint": "1.1.1.1:853"}
    ],
    "expectedEgress": "5.129.216.42",
}
fd = os.open(output_path, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
with os.fdopen(fd, "w", encoding="utf-8") as f:
    json.dump(profile, f, separators=(",", ":"))
    f.write("\n")
PY
chmod 0600 "${CLIENT_CONFIG_FILE}"

"${INSTALL_ROOT}/bin/xray" run -test -config "${CONFIG_ROOT}/xray-socks.json" >/dev/null
cat >"/etc/systemd/system/${SOCKS_SERVICE}.service" <<EOF
[Unit]
Description=Green VPN isolated SOCKS endpoint for dnstt canary
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=${SERVICE_USER}
Group=${SERVICE_USER}
ExecStart=${INSTALL_ROOT}/bin/xray run -config ${CONFIG_ROOT}/xray-socks.json
Restart=on-failure
RestartSec=3s
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ProtectHome=true
ProtectKernelTunables=true
ProtectKernelModules=true
ProtectControlGroups=true
RestrictAddressFamilies=AF_INET AF_INET6 AF_UNIX
LockPersonality=true
MemoryDenyWriteExecute=true

[Install]
WantedBy=multi-user.target
EOF

cat >"/etc/systemd/system/${SERVER_SERVICE}.service" <<EOF
[Unit]
Description=Green VPN isolated dnstt last-resort canary
After=network-online.target ${SOCKS_SERVICE}.service
Wants=network-online.target
Requires=${SOCKS_SERVICE}.service

[Service]
Type=simple
User=${SERVICE_USER}
Group=${SERVICE_USER}
ExecStart=${INSTALL_ROOT}/bin/dnstt-server -mtu 1232 -udp ${CANARY_HOST}:${CANARY_PORT} -privkey-file ${private_key} ${CANARY_ZONE} 127.0.0.1:${SOCKS_PORT}
Restart=on-failure
RestartSec=3s
AmbientCapabilities=CAP_NET_BIND_SERVICE
CapabilityBoundingSet=CAP_NET_BIND_SERVICE
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ProtectHome=true
ProtectKernelTunables=true
ProtectKernelModules=true
ProtectControlGroups=true
RestrictAddressFamilies=AF_INET AF_INET6 AF_UNIX
LockPersonality=true
MemoryDenyWriteExecute=true

[Install]
WantedBy=multi-user.target
EOF
chmod 0644 "/etc/systemd/system/${SOCKS_SERVICE}.service" "/etc/systemd/system/${SERVER_SERVICE}.service"
systemctl daemon-reload
systemctl enable --now "${SOCKS_SERVICE}.service"
systemctl enable --now "${SERVER_SERVICE}.service"

systemctl is-active --quiet "${SOCKS_SERVICE}.service"
systemctl is-active --quiet "${SERVER_SERVICE}.service"
ss -H -lunp | awk -v endpoint="${CANARY_HOST}:${CANARY_PORT}" '$4 == endpoint {found=1} END {exit !found}'
ss -H -lntp | awk -v endpoint="127.0.0.1:${SOCKS_PORT}" '$4 == endpoint {found=1} END {exit !found}'

for path in "${stable_files[@]}"; do [[ ! -f "${path}" ]] || sha256sum "${path}"; done | sort >"${stable_after}"
cmp -s "${stable_before}" "${stable_after}" || { echo "Existing transport config changed during dnstt bootstrap." >&2; exit 1; }
for unit in wg-quick@wg0 greenvpn-hysteria2-canary greenvpn-vless-reality-canary greenvpn-naive-https-canary; do
  systemctl is-active --quiet "${unit}.service" || { echo "Stable transport failed after dnstt bootstrap: ${unit}" >&2; exit 1; }
done

cat >"${INSTALL_ROOT}/manifest" <<EOF
source_version=${DNSTT_SOURCE_VERSION}
source_commit=${DNSTT_SOURCE_COMMIT}
source_archive_sha256=${DNSTT_ARCHIVE_SHA256}
signer_fingerprint=AD1AB35C674DF572FBCE8B0A6BC758CBC11F6276
server_binary_sha256=${DNSTT_SERVER_SHA256}
client_binary_sha256=${DNSTT_CLIENT_SHA256}
xray_binary_sha256=${XRAY_SHA256}
zone=${CANARY_ZONE}
nameserver=${CANARY_NS}
listen=${CANARY_HOST}:${CANARY_PORT}/udp
upstream=127.0.0.1:${SOCKS_PORT}/tcp
server_service=${SERVER_SERVICE}.service
socks_service=${SOCKS_SERVICE}.service
client_config=${CLIENT_CONFIG_FILE}
backup=${backup_root}
EOF
chmod 0600 "${INSTALL_ROOT}/manifest"

echo "dnstt_canary=active"
echo "dns_delegation=pending_external_registrar_records"
echo "client_profile=root_only"
echo "stable_transports=verified_unchanged"
