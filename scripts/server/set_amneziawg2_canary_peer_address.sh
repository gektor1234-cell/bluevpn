#!/usr/bin/env bash
set -euo pipefail

APPLY=0
EXPECTED_PUBLIC_IP=""
APPROVED_EXISTING_HOST=""
PEER_FINGERPRINT=""
CLIENT_ADDRESS=""

CANARY_HOST="5.129.216.42"
CANARY_INTERFACE="awgcanary0"
CONFIG_FILE="/etc/greenvpn-transport/awgcanary0.conf"
AWG_BIN="/opt/greenvpn-canary/amneziawg2/bin/awg"
AWG_QUICK_BIN="/opt/greenvpn-canary/amneziawg2/bin/awg-quick"

usage() {
  cat <<'USAGE'
Assign a unique address to one existing AmneziaWG 2 canary peer by a truncated
SHA-256 fingerprint of its public key. The public key is never printed.

Usage:
  set_amneziawg2_canary_peer_address.sh \
    --peer-fingerprint 0123456789abcdef \
    --client-address 10.202.0.3/32 \
    --expected-public-ip 5.129.216.42 \
    --approved-existing-host 5.129.216.42 [--apply]

Default mode is read-only. Apply mode atomically updates only awgcanary0.conf,
syncs only awgcanary0 and rolls the config back if validation or sync fails.
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
    --peer-fingerprint)
      PEER_FINGERPRINT="${2:?missing peer fingerprint}"
      shift 2
      ;;
    --client-address)
      CLIENT_ADDRESS="${2:?missing client address}"
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
if ! [[ "$PEER_FINGERPRINT" =~ ^[A-Fa-f0-9]{16}$ ]]; then
  echo "--peer-fingerprint must contain exactly 16 hexadecimal characters." >&2
  exit 2
fi
if ! [[ "$CLIENT_ADDRESS" =~ ^10\.202\.0\.([2-9]|[1-9][0-9]|1[0-9]{2}|2[0-4][0-9]|25[0-4])/32$ ]]; then
  echo "--client-address must be a host in 10.202.0.2-254 with /32." >&2
  exit 2
fi

PUBLIC_IP="$(curl -fsS --max-time 5 https://api.ipify.org || true)"
if [[ "$PUBLIC_IP" != "$CANARY_HOST" ]]; then
  echo "This operation is pinned to ${CANARY_HOST}; detected ${PUBLIC_IP:-unknown}." >&2
  exit 1
fi
if [[ "$(systemctl is-active wg-quick@wg0 2>/dev/null || true)" != "active" ]]; then
  echo "Existing wg0 is not active; refusing canary work." >&2
  exit 1
fi
if [[ "$(systemctl is-active greenvpn-amneziawg-canary 2>/dev/null || true)" != "active" ]]; then
  echo "AmneziaWG canary service is not active." >&2
  exit 1
fi
[[ -f "$CONFIG_FILE" && -x "$AWG_BIN" && -x "$AWG_QUICK_BIN" ]] \
  || { echo "Canary config or pinned tools are missing." >&2; exit 1; }
[[ "$(stat -c '%U:%G:%a' "$CONFIG_FILE")" == "root:root:600" ]] \
  || { echo "Canary config ownership or mode is unsafe." >&2; exit 1; }

WORK_ROOT="$(mktemp -d /root/greenvpn-awg-peer.XXXXXX)"
TARGET_KEY_FILE="${WORK_ROOT}/target-public-key"
UPDATED_CONFIG="${WORK_ROOT}/awgcanary0.conf"
BACKUP_FILE="${CONFIG_FILE}.rollback.$(date -u +%Y%m%dT%H%M%SZ)"
WG0_HASH_BEFORE="$(sha256sum /etc/wireguard/wg0.conf | awk '{print $1}')"
trap 'rm -rf -- "$WORK_ROOT"' EXIT

python3 - "$CONFIG_FILE" "$PEER_FINGERPRINT" "$CLIENT_ADDRESS" "$UPDATED_CONFIG" "$TARGET_KEY_FILE" <<'PY'
import hashlib
import pathlib
import sys

source, wanted_fingerprint, wanted_address, output, key_output = sys.argv[1:]
lines = pathlib.Path(source).read_text(encoding="utf-8").splitlines(keepends=True)
peers = []
current = None

for index, line in enumerate(lines):
    stripped = line.strip()
    if stripped == "[Peer]":
        current = {"public_key": None, "allowed_index": None, "allowed": None}
        peers.append(current)
    elif current is not None and stripped.startswith("PublicKey") and "=" in stripped:
        current["public_key"] = stripped.split("=", 1)[1].strip()
    elif current is not None and stripped.startswith("AllowedIPs") and "=" in stripped:
        current["allowed_index"] = index
        current["allowed"] = stripped.split("=", 1)[1].strip()

for peer in peers:
    key = peer["public_key"] or ""
    peer["fingerprint"] = hashlib.sha256(key.encode("utf-8")).hexdigest()[:16]

matches = [peer for peer in peers if peer["fingerprint"].lower() == wanted_fingerprint.lower()]
if len(matches) != 1:
    raise SystemExit(f"Expected exactly one peer fingerprint match, found {len(matches)}")
target = matches[0]
if target["allowed_index"] is None:
    raise SystemExit("Target peer has no AllowedIPs line")

conflicts = [
    peer for peer in peers
    if peer is not target and peer["allowed"] == wanted_address
]
if conflicts:
    raise SystemExit("Requested client address is already assigned to another peer")

print(f"peer_fingerprint={target['fingerprint']}")
print(f"old_allowed_ips={target['allowed']}")
print(f"new_allowed_ips={wanted_address}")

lines[target["allowed_index"]] = f"AllowedIPs = {wanted_address}\n"
pathlib.Path(output).write_text("".join(lines), encoding="utf-8")
pathlib.Path(key_output).write_text(target["public_key"] + "\n", encoding="ascii")
PY

chmod 0600 "$UPDATED_CONFIG" "$TARGET_KEY_FILE"
if [[ "$APPLY" -ne 1 ]]; then
  echo "mode=dry-run"
  echo "wg0=active_untouched"
  exit 0
fi

install -m 0600 -o root -g root "$CONFIG_FILE" "$BACKUP_FILE"
install -m 0600 -o root -g root "$UPDATED_CONFIG" "$CONFIG_FILE"

rollback() {
  install -m 0600 -o root -g root "$BACKUP_FILE" "$CONFIG_FILE"
  "$AWG_BIN" syncconf "$CANARY_INTERFACE" <("$AWG_QUICK_BIN" strip "$CONFIG_FILE") || true
}

if ! "$AWG_BIN" syncconf "$CANARY_INTERFACE" <("$AWG_QUICK_BIN" strip "$CONFIG_FILE"); then
  rollback
  echo "Canary sync failed; original config restored." >&2
  exit 1
fi

if ! python3 - "$AWG_BIN" "$CANARY_INTERFACE" "$PEER_FINGERPRINT" "$CLIENT_ADDRESS" <<'PY'
import hashlib
import subprocess
import sys

binary, interface, wanted_fingerprint, wanted_address = sys.argv[1:]
rows = subprocess.check_output([binary, "show", interface, "dump"], text=True).splitlines()[1:]
matches = []
addresses = []
for row in rows:
    fields = row.split("\t")
    if len(fields) < 7:
        continue
    fingerprint = hashlib.sha256(fields[0].encode("utf-8")).hexdigest()[:16]
    addresses.append(fields[3])
    if fingerprint.lower() == wanted_fingerprint.lower():
        matches.append(fields[3])
if matches != [wanted_address]:
    raise SystemExit("Live peer address verification failed")
if addresses.count(wanted_address) != 1:
    raise SystemExit("Live client address is not unique")
PY
then
  rollback
  echo "Canary validation failed; original config restored." >&2
  exit 1
fi

WG0_HASH_AFTER="$(sha256sum /etc/wireguard/wg0.conf | awk '{print $1}')"
if [[ "$WG0_HASH_AFTER" != "$WG0_HASH_BEFORE" || "$(systemctl is-active wg-quick@wg0)" != "active" ]]; then
  rollback
  echo "Stable wg0 invariant changed; canary config restored." >&2
  exit 1
fi

echo "mode=applied"
echo "backup=${BACKUP_FILE}"
echo "canary_peer_address=verified"
echo "wg0=active_unchanged"
