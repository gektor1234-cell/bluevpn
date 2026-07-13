#!/usr/bin/env bash
set -euo pipefail

APPLY=0
EXPECTED_PUBLIC_IP=""
APPROVED_EXISTING_HOST=""
CANARY_HOST="5.129.216.42"
CANARY_ZONE="t.greenvpn.pro"
CANARY_NS="tns.greenvpn.pro"
CANARY_NS2="tns2.greenvpn.pro"
PUBLIC_PORT="53"
BACKEND_HOST="127.0.0.1"
BACKEND_PORT="5353"
SOCKS_PORT="1083"
DNSTT_SERVICE="greenvpn-dnstt-canary"
FRONT_SERVICE="greenvpn-dnstt-dns-front"
DNSTT_BINARY="/opt/greenvpn-canary/dnstt/bin/dnstt-server"
DNSTT_PRIVATE_KEY="/etc/greenvpn-dnstt-canary/server.key"
DNSDIST_CONFIG="/etc/dnsdist/dnsdist-greenvpn-dnstt.conf"
DNSDIST_UNIT="/etc/systemd/system/${FRONT_SERVICE}.service"
DNSTT_DROPIN_DIR="/etc/systemd/system/${DNSTT_SERVICE}.service.d"
DNSTT_DROPIN="${DNSTT_DROPIN_DIR}/dns-front.conf"
DNSDIST_KEYRING="/etc/apt/keyrings/greenvpn-dnsdist-21.gpg"
DNSDIST_SOURCE="/etc/apt/sources.list.d/greenvpn-dnsdist-21.list"
DNSDIST_PREFERENCES="/etc/apt/preferences.d/greenvpn-dnsdist-21"
DNSDIST_VERSION="2.1.0-1pdns.ubuntu24.04"
DNSDIST_KEY_FINGERPRINT="9FAAA5577E8FCF62093D036C1B0C6205FD380FBB"
DNSDIST_KEY_URL="https://repo.powerdns.com/FD380FBB-pub.asc"
DNSDIST_REPOSITORY="https://repo.powerdns.com/ubuntu"

usage() {
  cat <<'USAGE'
Install the authoritative DNS frontend for the existing Green VPN dnstt canary.

Dry-run is the default. Apply requires the exact NL2 tuple:
  bootstrap_dnstt_dns_frontend.sh --expected-public-ip 5.129.216.42 \
      --approved-existing-host 5.129.216.42 --apply

The frontend serves authoritative NS/SOA on public UDP/TCP 53 and forwards only
t.greenvpn.pro tunnel traffic to dnstt on 127.0.0.1:5353. It does not modify
registrar records, WireGuard, other transports, WARP, databases or catalogs.
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

[[ "${EUID}" -eq 0 ]] || { echo "Run as root on NL2." >&2; exit 1; }
for command in apt-get curl dig dpkg-query gpg sha256sum ss systemctl; do
  command -v "${command}" >/dev/null 2>&1 || { echo "Required command missing: ${command}" >&2; exit 1; }
done

PUBLIC_IP="$(curl -4fsS --max-time 5 https://api.ipify.org || true)"
[[ "${PUBLIC_IP}" == "${CANARY_HOST}" ]] || { echo "Refusing DNS frontend outside exact NL2 host." >&2; exit 1; }
if [[ "${APPLY}" -eq 1 && ( "${EXPECTED_PUBLIC_IP}" != "${CANARY_HOST}" || "${APPROVED_EXISTING_HOST}" != "${CANARY_HOST}" ) ]]; then
  echo "Apply requires exact NL2 expected/approved host values." >&2
  exit 1
fi

[[ -x "${DNSTT_BINARY}" && ! -L "${DNSTT_BINARY}" ]] || { echo "Pinned dnstt server is missing or unsafe." >&2; exit 1; }
[[ -f "${DNSTT_PRIVATE_KEY}" && ! -L "${DNSTT_PRIVATE_KEY}" ]] || { echo "Protected dnstt private key is missing or unsafe." >&2; exit 1; }
systemctl is-active --quiet "${DNSTT_SERVICE}.service" || { echo "Existing dnstt service is not active." >&2; exit 1; }
for unit in wg-quick@wg0 greenvpn-hysteria2-canary greenvpn-vless-reality-canary greenvpn-naive-https-canary; do
  systemctl is-active --quiet "${unit}.service" || { echo "Required transport is not active: ${unit}" >&2; exit 1; }
done

echo "Green VPN dnstt authoritative frontend plan"
echo "public_ip=${PUBLIC_IP}"
echo "zone=${CANARY_ZONE}"
echo "authoritative_nameservers=${CANARY_NS},${CANARY_NS2}"
echo "frontend=${CANARY_HOST}:${PUBLIC_PORT}/udp+tcp"
echo "dnstt_backend=${BACKEND_HOST}:${BACKEND_PORT}/udp"
echo "dnsdist_version=${DNSDIST_VERSION}"
echo "mode=$([[ "${APPLY}" -eq 1 ]] && echo apply || echo dry-run)"
echo "registrar_dns=not_changed"
echo "stable_transports=not_changed"
echo "public_catalog=not_changed"
echo "databases=not_changed"

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
key_tmp="$(mktemp)"
backup_root="/root/greenvpn-dnstt-dns-front-prechange/$(date -u +%Y%m%dT%H%M%SZ)"
install -d -m 0700 "${backup_root}"
for path in "${DNSDIST_CONFIG}" "${DNSDIST_UNIT}" "${DNSTT_DROPIN}" "${DNSDIST_KEYRING}" "${DNSDIST_SOURCE}" "${DNSDIST_PREFERENCES}"; do
  if [[ -e "${path}" || -L "${path}" ]]; then
    target="${backup_root}${path}"
    install -d -m 0700 "$(dirname "${target}")"
    cp -a -- "${path}" "${target}"
  fi
done
for path in "${stable_files[@]}"; do [[ ! -f "${path}" ]] || sha256sum "${path}"; done | sort >"${stable_before}"

switched=0
cleanup() {
  rm -f -- "${stable_before}" "${stable_after}" "${key_tmp}"
}
restore_direct_listener() {
  set +e
  systemctl disable --now "${FRONT_SERVICE}.service" >/dev/null 2>&1
  rm -f -- "${DNSTT_DROPIN}"
  rmdir "${DNSTT_DROPIN_DIR}" >/dev/null 2>&1 || true
  systemctl daemon-reload
  systemctl restart "${DNSTT_SERVICE}.service"
  set -e
}
on_error() {
  status=$?
  if [[ "${switched}" -eq 1 ]]; then
    echo "DNS frontend validation failed; restoring direct dnstt UDP/53." >&2
    restore_direct_listener
  fi
  cleanup
  exit "${status}"
}
trap on_error ERR
trap cleanup EXIT

curl -fsSL --max-time 20 "${DNSDIST_KEY_URL}" -o "${key_tmp}"
key_fingerprint="$(gpg --show-keys --with-colons "${key_tmp}" | awk -F: '/^fpr:/{print $10; exit}')"
[[ "${key_fingerprint}" == "${DNSDIST_KEY_FINGERPRINT}" ]] || { echo "PowerDNS signing key fingerprint mismatch." >&2; exit 1; }
install -d -m 0755 /etc/apt/keyrings
gpg --batch --yes --dearmor -o "${DNSDIST_KEYRING}" "${key_tmp}"
chmod 0644 "${DNSDIST_KEYRING}"
cat >"${DNSDIST_SOURCE}" <<EOF
deb [signed-by=${DNSDIST_KEYRING}] ${DNSDIST_REPOSITORY} noble-dnsdist-21 main
EOF
cat >"${DNSDIST_PREFERENCES}" <<EOF
Package: dnsdist*
Pin: version ${DNSDIST_VERSION}
Pin-Priority: 1001
EOF
chmod 0644 "${DNSDIST_SOURCE}" "${DNSDIST_PREFERENCES}"
apt-get update -o Acquire::Retries=3 >/dev/null
DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends "dnsdist=${DNSDIST_VERSION}" >/dev/null
[[ "$(dpkg-query -W -f='${Version}' dnsdist)" == "${DNSDIST_VERSION}" ]] || { echo "Unexpected dnsdist package version." >&2; exit 1; }
systemctl disable --now dnsdist.service >/dev/null 2>&1 || true

install -d -o root -g _dnsdist -m 0750 /etc/dnsdist
cat >"${DNSDIST_CONFIG}" <<EOF
setSecurityPollSuffix("")
setLocal("${CANARY_HOST}:${PUBLIC_PORT}")
setACL({"0.0.0.0/0"})
setAddEDNSToSelfGeneratedResponses(true)
setPayloadSizeOnSelfGeneratedAnswers(1232)

local zone = "${CANARY_ZONE}."
local ns1 = "${CANARY_NS}."
local ns2 = "${CANARY_NS2}."
local rname = "hostmaster.greenvpn.pro."
local serial = 2026071301

local function uint32(value)
  return string.char(
    math.floor(value / 16777216) % 256,
    math.floor(value / 65536) % 256,
    math.floor(value / 256) % 256,
    value % 256
  )
end

local soa = newDNSName(ns1):toDNSString() .. newDNSName(rname):toDNSString() ..
  uint32(serial) .. uint32(3600) .. uint32(600) .. uint32(86400) .. uint32(300)

newServer({
  address="${BACKEND_HOST}:${BACKEND_PORT}",
  name="dnstt-loopback",
  pool="dnstt",
  healthCheckMode="up"
})

addAction(
  AndRule({QNameRule(zone), QTypeRule(DNSQType.NS)}),
  SpoofRawAction({newDNSName(ns1):toDNSString(), newDNSName(ns2):toDNSString()}, {aa=true, ra=false, ttl=300})
)
addAction(
  AndRule({QNameRule(zone), QTypeRule(DNSQType.SOA)}),
  SpoofRawAction(soa, {aa=true, ra=false, ttl=300})
)
addAction(
  QNameRule(zone),
  NegativeAndSOAAction(false, zone, 300, ns1, rname, serial, 3600, 600, 86400, 300,
    {aa=true, ra=false, soaInAuthoritySection=true})
)
addAction(QNameSuffixRule(zone, true), PoolAction("dnstt"))
addAction(AllRule(), RCodeAction(5, {aa=false, ra=false}))
EOF
chown root:_dnsdist "${DNSDIST_CONFIG}"
chmod 0640 "${DNSDIST_CONFIG}"
/usr/bin/dnsdist --check-config --config "${DNSDIST_CONFIG}" >/dev/null

install -d -m 0755 "${DNSTT_DROPIN_DIR}"
cat >"${DNSTT_DROPIN}" <<EOF
[Service]
ExecStart=
ExecStart=${DNSTT_BINARY} -mtu 1232 -udp ${BACKEND_HOST}:${BACKEND_PORT} -privkey-file ${DNSTT_PRIVATE_KEY} ${CANARY_ZONE} 127.0.0.1:${SOCKS_PORT}
AmbientCapabilities=
CapabilityBoundingSet=
EOF
chmod 0644 "${DNSTT_DROPIN}"

cat >"${DNSDIST_UNIT}" <<EOF
[Unit]
Description=Green VPN authoritative DNS frontend for dnstt canary
After=network-online.target ${DNSTT_SERVICE}.service
Wants=network-online.target
Requires=${DNSTT_SERVICE}.service

[Service]
Type=notify
User=_dnsdist
Group=_dnsdist
ExecStartPre=/usr/bin/dnsdist --check-config --config ${DNSDIST_CONFIG}
ExecStart=/usr/bin/dnsdist --supervised --disable-syslog --config ${DNSDIST_CONFIG}
Restart=on-failure
RestartSec=2s
TimeoutStopSec=5s
TasksMax=8192
LimitNOFILE=16384
CapabilityBoundingSet=CAP_NET_BIND_SERVICE
AmbientCapabilities=CAP_NET_BIND_SERVICE
NoNewPrivileges=true
PrivateDevices=true
PrivateTmp=true
ProtectControlGroups=true
ProtectHome=true
ProtectHostname=true
ProtectKernelLogs=true
ProtectKernelModules=true
ProtectKernelTunables=true
ProtectSystem=strict
RestrictAddressFamilies=AF_INET AF_INET6 AF_UNIX
RestrictNamespaces=true
RestrictRealtime=true
RestrictSUIDSGID=true
LockPersonality=true
SystemCallArchitectures=native

[Install]
WantedBy=multi-user.target
EOF
chmod 0644 "${DNSDIST_UNIT}"

switched=1
systemctl daemon-reload
systemctl restart "${DNSTT_SERVICE}.service"
systemctl enable --now "${FRONT_SERVICE}.service"

systemctl is-active --quiet "${DNSTT_SERVICE}.service"
systemctl is-active --quiet "${FRONT_SERVICE}.service"
ss -H -lunp | awk -v endpoint="${BACKEND_HOST}:${BACKEND_PORT}" '$4 == endpoint && /dnstt-server/ {found=1} END {exit !found}'
ss -H -lunp | awk -v endpoint="${CANARY_HOST}:${PUBLIC_PORT}" '$4 == endpoint && /dnsdist/ {found=1} END {exit !found}'
ss -H -lntp | awk -v endpoint="${CANARY_HOST}:${PUBLIC_PORT}" '$4 == endpoint && /dnsdist/ {found=1} END {exit !found}'

ns_answer="$(dig +short NS "${CANARY_ZONE}" @"${CANARY_HOST}" | tr '[:upper:]' '[:lower:]' | sed 's/\.$//' | sort -u | tr '\n' ' ')"
grep -qw "${CANARY_NS}" <<<"${ns_answer}"
grep -qw "${CANARY_NS2}" <<<"${ns_answer}"
soa_answer="$(dig +time=2 +tries=1 SOA "${CANARY_ZONE}" @"${CANARY_HOST}")"
grep -q 'status: NOERROR' <<<"${soa_answer}"
grep -Eq 'flags:.* aa([ ;]|$)' <<<"${soa_answer}"

for path in "${stable_files[@]}"; do [[ ! -f "${path}" ]] || sha256sum "${path}"; done | sort >"${stable_after}"
cmp -s "${stable_before}" "${stable_after}" || { echo "Stable transport config changed during DNS frontend bootstrap." >&2; exit 1; }
for unit in wg-quick@wg0 greenvpn-hysteria2-canary greenvpn-vless-reality-canary greenvpn-naive-https-canary; do
  systemctl is-active --quiet "${unit}.service" || { echo "Required transport failed after DNS frontend bootstrap: ${unit}" >&2; exit 1; }
done

switched=0
trap - ERR
echo "dnstt_dns_frontend=active"
echo "authoritative_ns_soa=ready"
echo "dnstt_backend=loopback_only"
echo "stable_transports=verified_unchanged"
echo "secrets_printed=false"
echo "backup=${backup_root}"
