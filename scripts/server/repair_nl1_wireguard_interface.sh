#!/usr/bin/env bash
set -euo pipefail

EXPECTED_HOSTNAME="ams-1-vm-p28w"
WG_CONFIG="/etc/wireguard/wg0.conf"
INTERFACE_SOURCE="/root/greenvpn-paid-beta-smoke-cleanup-20260710T100214Z/wg0.conf"
EXPECTED_PUBLIC_SHA256=""
APPLY=0

usage() {
  cat <<'USAGE'
Restore the missing NL1 WireGuard interface block without restoring stale peers.

  repair_nl1_wireguard_interface.sh \
    --expected-public-sha256 SHA256 [--apply]

Dry-run is the default. The script takes only the [Interface] section from the
known recovery copy and preserves the peer blocks from the current wg0.conf.
Apply creates a root-only rollback copy, validates the candidate, restarts wg0,
and verifies the public-key fingerprint, port, address, and peer count.
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --expected-public-sha256)
      EXPECTED_PUBLIC_SHA256="${2:?missing SHA-256}"
      shift 2
      ;;
    --apply)
      APPLY=1
      shift
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

[[ "${EUID}" -eq 0 ]] || { echo "Run as root." >&2; exit 1; }
[[ "$(hostname -s)" == "${EXPECTED_HOSTNAME}" ]] || {
  echo "Host guard failed." >&2
  exit 1
}
[[ "${EXPECTED_PUBLIC_SHA256}" =~ ^[a-f0-9]{64}$ ]] || {
  echo "A lowercase expected public-key SHA-256 is required." >&2
  exit 2
}
for command in hostname install ip python3 sha256sum systemctl wg wg-quick; do
  command -v "${command}" >/dev/null 2>&1 || {
    echo "Required command missing: ${command}" >&2
    exit 1
  }
done
for path in "${WG_CONFIG}" "${INTERFACE_SOURCE}"; do
  [[ -f "${path}" && ! -L "${path}" ]] || {
    echo "Required WireGuard file is missing or unsafe: ${path}" >&2
    exit 1
  }
  [[ "$(stat -c '%u:%g' "${path}")" == "0:0" ]] || {
    echo "WireGuard file is not root-owned: ${path}" >&2
    exit 1
  }
done

SOURCE_PRIVATE="$(python3 - "${INTERFACE_SOURCE}" <<'PY'
import re
import sys

text = open(sys.argv[1], encoding="utf-8").read()
interface = text.split("[Peer]", 1)[0]
match = re.search(r"(?im)^\s*PrivateKey\s*=\s*([^\s#]+)", interface)
if interface.count("[Interface]") != 1 or match is None:
    raise SystemExit("recovery source has no unique private interface key")
print(match.group(1))
PY
)"
SOURCE_PUBLIC="$(printf '%s\n' "${SOURCE_PRIVATE}" | wg pubkey)"
unset SOURCE_PRIVATE
SOURCE_PUBLIC_SHA256="$(printf '%s' "${SOURCE_PUBLIC}" | sha256sum | awk '{print $1}')"
unset SOURCE_PUBLIC
[[ "${SOURCE_PUBLIC_SHA256}" == "${EXPECTED_PUBLIC_SHA256}" ]] || {
  echo "Recovery source public-key fingerprint mismatch." >&2
  exit 1
}

CURRENT_PEERS="$(grep -c '^\[Peer\][[:space:]]*$' "${WG_CONFIG}" || true)"
[[ "${CURRENT_PEERS}" -gt 0 ]] || {
  echo "Current config has no peers to preserve." >&2
  exit 1
}

CANDIDATE="$(mktemp /etc/wireguard/wgrXXXXXX.conf)"
cleanup() {
  rm -f -- "${CANDIDATE}"
}
trap cleanup EXIT

python3 - "${INTERFACE_SOURCE}" "${WG_CONFIG}" "${CANDIDATE}" <<'PY'
import re
import sys

source_path, current_path, candidate_path = sys.argv[1:]
source = open(source_path, encoding="utf-8").read()
current = open(current_path, encoding="utf-8").read()

source_peer = re.search(r"(?m)^\[Peer\]\s*$", source)
if source_peer is None:
    raise SystemExit("recovery source has no peer boundary")
interface = source[: source_peer.start()].rstrip()
if interface.count("[Interface]") != 1:
    raise SystemExit("recovery source has no unique interface section")
for field in ("PrivateKey", "Address", "ListenPort"):
    if not re.search(rf"(?im)^\s*{field}\s*=", interface):
        raise SystemExit(f"recovery interface is missing {field}")
if not re.search(r"(?im)^\s*ListenPort\s*=\s*443\s*$", interface):
    raise SystemExit("recovery interface does not listen on UDP 443")
if not re.search(r"(?im)^\s*Address\s*=\s*10\.10\.0\.1/24\s*$", interface):
    raise SystemExit("recovery interface address is unexpected")

managed_marker = re.search(
    r"(?m)^# BEGIN (?:GREENVPN|BLUEVPN) MANAGED PEER [^\n]+$", current
)
plain_peer = re.search(r"(?m)^\[Peer\]\s*$", current)
starts = [match.start() for match in (managed_marker, plain_peer) if match is not None]
if not starts:
    raise SystemExit("current config has no peer section")
peers = current[min(starts) :].strip()
if "[Interface]" in peers:
    raise SystemExit("current peer section unexpectedly contains an interface")

candidate = interface + "\n\n" + peers + "\n"
if len(re.findall(r"(?m)^\[Peer\]\s*$", candidate)) != len(
    re.findall(r"(?m)^\[Peer\]\s*$", current)
):
    raise SystemExit("candidate peer count changed")
with open(candidate_path, "w", encoding="utf-8", newline="\n") as fh:
    fh.write(candidate)
PY
chmod 0600 "${CANDIDATE}"
chown root:root "${CANDIDATE}"
wg-quick strip "${CANDIDATE}" >/dev/null
CANDIDATE_PEERS="$(grep -c '^\[Peer\][[:space:]]*$' "${CANDIDATE}")"
[[ "${CANDIDATE_PEERS}" == "${CURRENT_PEERS}" ]] || exit 1

echo "nl1_wg_repair_apply=${APPLY}"
echo "nl1_wg_repair_source=${INTERFACE_SOURCE}"
echo "nl1_wg_repair_public_sha256=${SOURCE_PUBLIC_SHA256}"
echo "nl1_wg_repair_preserved_peers=${CURRENT_PEERS}"
[[ "${APPLY}" -eq 1 ]] || exit 0

STAMP="$(date -u +%Y%m%dT%H%M%SZ)"
BACKUP_DIR="/root/greenvpn-maintenance-backups/${STAMP}-nl1-wg-interface-repair"
install -d -m 0700 -- "${BACKUP_DIR}"
install -m 0600 -- "${WG_CONFIG}" "${BACKUP_DIR}/wg0.conf.before"
install -m 0600 -- "${INTERFACE_SOURCE}" "${BACKUP_DIR}/wg0.interface-source.conf"

rollback() {
  install -m 0600 -- "${BACKUP_DIR}/wg0.conf.before" "${WG_CONFIG}"
  systemctl restart wg-quick@wg0.service >/dev/null 2>&1 || true
}
trap rollback ERR

TEMP_CONFIG="${WG_CONFIG}.tmp.$$"
install -m 0600 -- "${CANDIDATE}" "${TEMP_CONFIG}"
mv -f -- "${TEMP_CONFIG}" "${WG_CONFIG}"
systemctl restart wg-quick@wg0.service
systemctl is-active --quiet wg-quick@wg0.service

ACTUAL_PUBLIC="$(wg show wg0 public-key)"
ACTUAL_PUBLIC_SHA256="$(printf '%s' "${ACTUAL_PUBLIC}" | sha256sum | awk '{print $1}')"
unset ACTUAL_PUBLIC
[[ "${ACTUAL_PUBLIC_SHA256}" == "${EXPECTED_PUBLIC_SHA256}" ]]
[[ "$(wg show wg0 listen-port)" == "443" ]]
ip -4 address show dev wg0 | grep -Fq '10.10.0.1/24'
LIVE_PEERS="$(wg show wg0 peers | wc -w)"
[[ "${LIVE_PEERS}" == "${CURRENT_PEERS}" ]]

trap - ERR
echo "nl1_wg_repair_status=applied"
echo "nl1_wg_repair_rollback_dir=${BACKUP_DIR}"
echo "nl1_wg_repair_live_port=443"
echo "nl1_wg_repair_live_peers=${LIVE_PEERS}"
