#!/usr/bin/env bash
set -euo pipefail

EXPECTED_HOSTNAME=""
APPLY=0
DROP_IN="/etc/ssh/sshd_config.d/00-greenvpn-hardening.conf"

usage() {
  cat <<'USAGE'
Apply the Green VPN SSH baseline without disabling key-based root recovery.

  harden_ssh_server.sh --expected-hostname HOST [--apply]

Dry-run is the default. Apply requires an existing root authorized_keys entry,
backs up an older managed drop-in, validates effective sshd settings and reloads
the daemon. The calling orchestrator must verify a second SSH connection before
closing the original one.
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --expected-hostname) EXPECTED_HOSTNAME="${2:?missing hostname}"; shift 2 ;;
    --apply) APPLY=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
done

[[ "${EUID}" -eq 0 ]] || { echo "Run as root." >&2; exit 1; }
[[ "${EXPECTED_HOSTNAME}" =~ ^[a-zA-Z0-9._-]{1,120}$ ]] || {
  echo "A valid --expected-hostname is required." >&2
  exit 2
}
[[ "$(hostname -s)" == "${EXPECTED_HOSTNAME}" ]] || {
  echo "Host guard failed." >&2
  exit 1
}
for command in grep hostname install sshd systemctl; do
  command -v "${command}" >/dev/null 2>&1 || {
    echo "Required command missing: ${command}" >&2
    exit 1
  }
done

AUTHORIZED_KEYS="/root/.ssh/authorized_keys"
[[ -f "${AUTHORIZED_KEYS}" && ! -L "${AUTHORIZED_KEYS}" ]] || {
  echo "Root authorized_keys is missing or unsafe." >&2
  exit 1
}
grep -Eq '^[[:space:]]*(ssh-(ed25519|rsa)|ecdsa-sha2-nistp(256|384|521))[[:space:]]+' \
  "${AUTHORIZED_KEYS}" || {
    echo "No supported public key entry found in root authorized_keys." >&2
    exit 1
  }

echo "ssh_hardening_host=$(hostname -s)"
echo "ssh_hardening_target=${DROP_IN}"
echo "ssh_hardening_apply=${APPLY}"
echo "ssh_hardening_root_key_ready=true"
[[ "${APPLY}" -eq 1 ]] || exit 0

umask 077
STAMP="$(date -u +%Y%m%dT%H%M%SZ)"
BACKUP_ROOT="/root/greenvpn-ssh-backups"
BACKUP_PATH="${BACKUP_ROOT}/${STAMP}-00-greenvpn-hardening.conf"
mkdir -p -- "${BACKUP_ROOT}"
chmod 0700 "${BACKUP_ROOT}"
HAD_OLD=0
if [[ -e "${DROP_IN}" ]]; then
  [[ -f "${DROP_IN}" && ! -L "${DROP_IN}" ]] || {
    echo "Managed SSH drop-in path is unsafe." >&2
    exit 1
  }
  cp -a -- "${DROP_IN}" "${BACKUP_PATH}"
  chmod 0600 "${BACKUP_PATH}"
  HAD_OLD=1
fi

rollback() {
  if [[ "${HAD_OLD}" -eq 1 ]]; then
    cp -a -- "${BACKUP_PATH}" "${DROP_IN}"
  else
    rm -f -- "${DROP_IN}"
  fi
  sshd -t >/dev/null 2>&1 && systemctl reload ssh >/dev/null 2>&1 || true
}
trap rollback ERR

install -d -m 0700 -o root -g root /root/.ssh
chmod 0600 "${AUTHORIZED_KEYS}"
chown root:root "${AUTHORIZED_KEYS}"
install -d -m 0755 -o root -g root /etc/ssh/sshd_config.d
TEMP_PATH="${DROP_IN}.tmp.$$"
cat >"${TEMP_PATH}" <<'EOF'
# Managed by Green VPN server baseline.
PasswordAuthentication no
KbdInteractiveAuthentication no
ChallengeResponseAuthentication no
PermitRootLogin prohibit-password
PubkeyAuthentication yes
X11Forwarding no
AllowAgentForwarding no
AllowTcpForwarding no
PermitTunnel no
MaxAuthTries 3
LoginGraceTime 30
EOF
chmod 0600 "${TEMP_PATH}"
chown root:root "${TEMP_PATH}"
mv -f -- "${TEMP_PATH}" "${DROP_IN}"

sshd -t
EFFECTIVE="$(sshd -T)"
grep -qx 'passwordauthentication no' <<<"${EFFECTIVE}"
grep -Eq '^permitrootlogin (prohibit-password|without-password)$' <<<"${EFFECTIVE}"
grep -qx 'pubkeyauthentication yes' <<<"${EFFECTIVE}"
grep -qx 'x11forwarding no' <<<"${EFFECTIVE}"
grep -qx 'allowtcpforwarding no' <<<"${EFFECTIVE}"
grep -qx 'maxauthtries 3' <<<"${EFFECTIVE}"
systemctl reload ssh

trap - ERR
echo "ssh_hardening_status=applied"
echo "ssh_hardening_backup=${BACKUP_PATH}"
