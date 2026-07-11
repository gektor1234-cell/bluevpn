#!/usr/bin/env bash
set -euo pipefail

APPLY=0
EXPECTED_PUBLIC_IP=""
APPROVED_EXISTING_HOST=""
CLIENT_PUBLIC_KEY=""
CANARY_HOST="5.129.216.42"
CANARY_INTERFACE="awgcanary0"
CANARY_PORT="1443"
CANARY_SUBNET="10.202.0.0/24"
CANARY_SERVER_ADDRESS="10.202.0.1/24"
CANARY_CLIENT_ADDRESS="10.202.0.2/32"
INSTALL_ROOT="/opt/greenvpn-canary/amneziawg2"
CONFIG_DIR="/etc/greenvpn-transport"
CONFIG_FILE="${CONFIG_DIR}/${CANARY_INTERFACE}.conf"
SERVER_PUBLIC_KEY_FILE="${CONFIG_DIR}/${CANARY_INTERFACE}.server.pub"

GO_VERSION="go1.26.5"
GO_ARCHIVE="go1.26.5.linux-amd64.tar.gz"
GO_SHA256="5c2c3b16caefa1d968a94c1daca04a7ca301a496d9b086e17ad77bb81393f053"
AWG_GO_COMMIT="c1e9bb3758e71bb1adc402598465565bfc9663fd"
AWG_TOOLS_TAG="v1.0.20260618-2"
AWG_TOOLS_ARCHIVE="ubuntu-22.04-amneziawg-tools.zip"
AWG_TOOLS_SHA256="9f645117ba1aa536c8358e2c682a54cc3949e65b9efb86d8495d4343dcee99f9"

usage() {
  cat <<'USAGE'
Green VPN pinned AmneziaWG 2 canary bootstrap for the owner-approved NL2 host.

Usage:
  bootstrap_amneziawg2_canary.sh --client-public-key KEY \
      --expected-public-ip 5.129.216.42 \
      --approved-existing-host 5.129.216.42 [--apply]

Default mode is dry-run. This script never starts the canary and never edits wg0,
the public catalog, DNS, nginx, backend env, databases or existing WireGuard rules.
Apply mode installs a pinned userspace toolchain and writes a root-only config for
awgcanary0 UDP/1443. Starting the canary is a separate guarded step.
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --apply)
      APPLY=1
      shift
      ;;
    --expected-public-ip)
      EXPECTED_PUBLIC_IP="${2:?missing expected public ip}"
      shift 2
      ;;
    --approved-existing-host)
      APPROVED_EXISTING_HOST="${2:?missing approved existing host}"
      shift 2
      ;;
    --client-public-key)
      CLIENT_PUBLIC_KEY="${2:?missing client public key}"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

if [[ "$EUID" -ne 0 ]]; then
  echo "Run as root on the approved NL2 host." >&2
  exit 1
fi
if [[ "$EXPECTED_PUBLIC_IP" != "$CANARY_HOST" || "$APPROVED_EXISTING_HOST" != "$CANARY_HOST" ]]; then
  echo "Both host confirmations must equal ${CANARY_HOST}." >&2
  exit 1
fi
if ! [[ "$CLIENT_PUBLIC_KEY" =~ ^[A-Za-z0-9+/]{43}=$ ]]; then
  echo "--client-public-key is not a valid WireGuard-compatible public key." >&2
  exit 2
fi

PUBLIC_IP="$(curl -fsS --max-time 5 https://api.ipify.org || true)"
if [[ "$PUBLIC_IP" != "$CANARY_HOST" ]]; then
  echo "This bootstrap is pinned to ${CANARY_HOST}; detected ${PUBLIC_IP:-unknown}." >&2
  exit 1
fi
if [[ "$(systemctl is-active wg-quick@wg0 2>/dev/null || true)" != "active" ]]; then
  echo "Existing wg0 is not active; refusing canary work." >&2
  exit 1
fi
if ss -H -lntu | awk '{print $5}' | grep -Eq "(:|])${CANARY_PORT}$"; then
  echo "Canary port ${CANARY_PORT} is already occupied." >&2
  exit 1
fi
if ip link show "$CANARY_INTERFACE" >/dev/null 2>&1; then
  echo "Canary interface ${CANARY_INTERFACE} already exists." >&2
  exit 1
fi

echo "Green VPN AmneziaWG 2 canary bootstrap plan"
echo "public_ip=${PUBLIC_IP}"
echo "existing_wg0=active_untouched"
echo "interface=${CANARY_INTERFACE}"
echo "listen=udp/${CANARY_PORT}"
echo "subnet=${CANARY_SUBNET}"
echo "go=${GO_VERSION} sha256=${GO_SHA256}"
echo "amneziawg_go_commit=${AWG_GO_COMMIT}"
echo "amneziawg_tools=${AWG_TOOLS_TAG} sha256=${AWG_TOOLS_SHA256}"
echo "config=${CONFIG_FILE}"
echo "mode=$([[ "$APPLY" -eq 1 ]] && echo apply || echo dry-run)"
echo "public_catalog=not_changed"

if [[ "$APPLY" -ne 1 ]]; then
  echo "Dry-run only. Add --apply after the plan and rollback path are verified."
  exit 0
fi

export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq ca-certificates curl git unzip build-essential >/dev/null

WORK_ROOT="$(mktemp -d /root/greenvpn-awg2-build.XXXXXX)"
trap 'rm -rf -- "$WORK_ROOT"' EXIT

curl -fsSL "https://go.dev/dl/${GO_ARCHIVE}" -o "${WORK_ROOT}/${GO_ARCHIVE}"
printf '%s  %s\n' "$GO_SHA256" "${WORK_ROOT}/${GO_ARCHIVE}" | sha256sum -c - >/dev/null
mkdir -p "${WORK_ROOT}/go-toolchain"
tar -C "${WORK_ROOT}/go-toolchain" -xzf "${WORK_ROOT}/${GO_ARCHIVE}"
GO_BIN="${WORK_ROOT}/go-toolchain/go/bin/go"
[[ "$($GO_BIN version)" == *"${GO_VERSION}"* ]] || { echo "Unexpected Go version." >&2; exit 1; }

git clone --quiet --no-checkout https://github.com/amnezia-vpn/amneziawg-go.git "${WORK_ROOT}/amneziawg-go"
git -C "${WORK_ROOT}/amneziawg-go" checkout --quiet "$AWG_GO_COMMIT"
[[ "$(git -C "${WORK_ROOT}/amneziawg-go" rev-parse HEAD)" == "$AWG_GO_COMMIT" ]] \
  || { echo "AmneziaWG source commit mismatch." >&2; exit 1; }
(
  cd "${WORK_ROOT}/amneziawg-go"
  GOTOOLCHAIN=local "$GO_BIN" mod verify
  GOTOOLCHAIN=local CGO_ENABLED=0 "$GO_BIN" build -trimpath -o "${WORK_ROOT}/amneziawg-go.bin" .
)

TOOLS_URL="https://github.com/amnezia-vpn/amneziawg-tools/releases/download/${AWG_TOOLS_TAG}/${AWG_TOOLS_ARCHIVE}"
curl -fsSL "$TOOLS_URL" -o "${WORK_ROOT}/${AWG_TOOLS_ARCHIVE}"
printf '%s  %s\n' "$AWG_TOOLS_SHA256" "${WORK_ROOT}/${AWG_TOOLS_ARCHIVE}" | sha256sum -c - >/dev/null
mkdir -p "${WORK_ROOT}/tools"
unzip -q -j "${WORK_ROOT}/${AWG_TOOLS_ARCHIVE}" -d "${WORK_ROOT}/tools"
AWG_SOURCE="$(find "${WORK_ROOT}/tools" -maxdepth 1 -type f -name awg -print -quit)"
AWG_QUICK_SOURCE="$(find "${WORK_ROOT}/tools" -maxdepth 1 -type f -name awg-quick -print -quit)"
[[ -n "$AWG_SOURCE" && -n "$AWG_QUICK_SOURCE" ]] || { echo "Pinned tools archive is incomplete." >&2; exit 1; }

install -d -m 0755 "${INSTALL_ROOT}/bin"
install -m 0755 "${WORK_ROOT}/amneziawg-go.bin" "${INSTALL_ROOT}/bin/amneziawg-go"
install -m 0755 "$AWG_SOURCE" "${INSTALL_ROOT}/bin/awg"
install -m 0755 "$AWG_QUICK_SOURCE" "${INSTALL_ROOT}/bin/awg-quick"
"${INSTALL_ROOT}/bin/awg" --version >/dev/null

install -d -m 0700 "$CONFIG_DIR"
SERVER_PRIVATE_KEY="$(${INSTALL_ROOT}/bin/awg genkey)"
SERVER_PUBLIC_KEY="$(printf '%s' "$SERVER_PRIVATE_KEY" | ${INSTALL_ROOT}/bin/awg pubkey)"
H1="$(od -An -N4 -tu4 /dev/urandom | tr -d ' ')"
H2="$(od -An -N4 -tu4 /dev/urandom | tr -d ' ')"
H3="$(od -An -N4 -tu4 /dev/urandom | tr -d ' ')"
H4="$(od -An -N4 -tu4 /dev/urandom | tr -d ' ')"
[[ "$H1" != "$H2" && "$H1" != "$H3" && "$H1" != "$H4" \
  && "$H2" != "$H3" && "$H2" != "$H4" && "$H3" != "$H4" ]] \
  || { echo "Generated header collision; rerun bootstrap." >&2; exit 1; }
DEFAULT_IFACE="$(ip route show default | awk 'NR==1 {print $5}')"
[[ -n "$DEFAULT_IFACE" ]] || { echo "Default network interface not found." >&2; exit 1; }

umask 077
cat > "$CONFIG_FILE" <<EOF
[Interface]
Address = ${CANARY_SERVER_ADDRESS}
ListenPort = ${CANARY_PORT}
PrivateKey = ${SERVER_PRIVATE_KEY}
S1 = 15
S2 = 20
S3 = 15
S4 = 20
H1 = ${H1}
H2 = ${H2}
H3 = ${H3}
H4 = ${H4}
PostUp = iptables -A FORWARD -i %i -j ACCEPT; iptables -A FORWARD -o %i -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT; iptables -t nat -A POSTROUTING -s ${CANARY_SUBNET} -o ${DEFAULT_IFACE} -j MASQUERADE
PostDown = iptables -D FORWARD -i %i -j ACCEPT; iptables -D FORWARD -o %i -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT; iptables -t nat -D POSTROUTING -s ${CANARY_SUBNET} -o ${DEFAULT_IFACE} -j MASQUERADE

[Peer]
PublicKey = ${CLIENT_PUBLIC_KEY}
AllowedIPs = ${CANARY_CLIENT_ADDRESS}
EOF
printf '%s\n' "$SERVER_PUBLIC_KEY" > "$SERVER_PUBLIC_KEY_FILE"
chmod 0600 "$CONFIG_FILE" "$SERVER_PUBLIC_KEY_FILE"

cat > "${CONFIG_DIR}/${CANARY_INTERFACE}.build-manifest" <<EOF
go_version=${GO_VERSION}
go_archive_sha256=${GO_SHA256}
amneziawg_go_commit=${AWG_GO_COMMIT}
amneziawg_tools_tag=${AWG_TOOLS_TAG}
amneziawg_tools_archive_sha256=${AWG_TOOLS_SHA256}
amneziawg_go_binary_sha256=$(sha256sum "${INSTALL_ROOT}/bin/amneziawg-go" | awk '{print $1}')
awg_binary_sha256=$(sha256sum "${INSTALL_ROOT}/bin/awg" | awk '{print $1}')
awg_quick_sha256=$(sha256sum "${INSTALL_ROOT}/bin/awg-quick" | awk '{print $1}')
EOF
chmod 0600 "${CONFIG_DIR}/${CANARY_INTERFACE}.build-manifest"

unset SERVER_PRIVATE_KEY SERVER_PUBLIC_KEY CLIENT_PUBLIC_KEY
echo "Pinned toolchain and root-only canary config prepared. The interface was not started."
