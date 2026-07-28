#!/usr/bin/env bash
set -euo pipefail

APPLY=0
CONTOUR="paid-beta"
ENABLED=""
QUOTA_ENFORCED=""
RATE_LIMIT_ENFORCED=""
MONTHLY_LIMIT_GB=""
MAX_DEVICES=""
SPEED_MBPS=""
ROLLBACK_DIR=""

ENV_FILE=""
SERVICE=""
LOCAL_HEALTH=""
BACKUP_ROOT=""
BACKUP_ENV_NAME="environment.before"

usage() {
  cat <<'EOF'
Configure the Green VPN free tier on one explicitly selected contour.

Usage:
  configure_paid_beta_free_tier.sh \
    --contour production|paid-beta \
    [--enabled 0|1] \
    [--quota-enforced 0|1] \
    [--rate-limit-enforced 0|1] \
    [--monthly-limit-gb N] \
    [--max-devices N] \
    [--speed-mbps N] \
    [--apply]

  configure_paid_beta_free_tier.sh \
    --contour production|paid-beta \
    --rollback /root/greenvpn-paid-beta-free-tier-backups/TIMESTAMP \
    --apply

Examples:
  # Preview the normal 3 GB monthly cap.
  configure_paid_beta_free_tier.sh \
    --contour paid-beta \
    --enabled 1 --quota-enforced 1 --monthly-limit-gb 3

  # Apply unlimited free paid-beta access while still tracking traffic.
  configure_paid_beta_free_tier.sh \
    --contour production \
    --enabled 1 --quota-enforced 0 --rate-limit-enforced 0 \
    --speed-mbps 10 --apply

  # Restore the previous paid-beta paywall.
  configure_paid_beta_free_tier.sh \
    --contour paid-beta --enabled 0 --apply

Dry-run is the default. Apply mode backs up and atomically updates only
the selected contour env, restarts only its backend service, verifies the
matching loopback health endpoint and rolls back automatically on failure.
Run the same command on each control plane.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --contour) CONTOUR="${2:?missing contour}"; shift 2 ;;
    --enabled) ENABLED="${2:?missing enabled value}"; shift 2 ;;
    --quota-enforced)
      QUOTA_ENFORCED="${2:?missing quota-enforced value}"
      shift 2
      ;;
    --rate-limit-enforced)
      RATE_LIMIT_ENFORCED="${2:?missing rate-limit-enforced value}"
      shift 2
      ;;
    --monthly-limit-gb)
      MONTHLY_LIMIT_GB="${2:?missing monthly limit}"
      shift 2
      ;;
    --max-devices) MAX_DEVICES="${2:?missing max devices}"; shift 2 ;;
    --speed-mbps) SPEED_MBPS="${2:?missing speed}"; shift 2 ;;
    --rollback) ROLLBACK_DIR="${2:?missing rollback directory}"; shift 2 ;;
    --apply) APPLY=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
done

case "${CONTOUR}" in
  paid-beta)
    ENV_FILE="/etc/bluevpn/paid-beta.env"
    SERVICE="greenvpn-paid-beta.service"
    LOCAL_HEALTH="http://127.0.0.1:8010/healthz"
    BACKUP_ROOT="/root/greenvpn-paid-beta-free-tier-backups"
    ;;
  production)
    ENV_FILE="/etc/bluevpn/backend.env"
    SERVICE="bluevpn-backend.service"
    LOCAL_HEALTH="http://127.0.0.1:8000/healthz"
    BACKUP_ROOT="/root/greenvpn-production-free-tier-backups"
    ;;
  *)
    echo "--contour must be production or paid-beta" >&2
    exit 2
    ;;
esac

is_flag() {
  [[ "$1" == "0" || "$1" == "1" ]]
}

[[ -z "${ENABLED}" ]] || is_flag "${ENABLED}" || {
  echo "--enabled must be 0 or 1" >&2
  exit 2
}
[[ -z "${QUOTA_ENFORCED}" ]] || is_flag "${QUOTA_ENFORCED}" || {
  echo "--quota-enforced must be 0 or 1" >&2
  exit 2
}
[[ -z "${RATE_LIMIT_ENFORCED}" ]] || is_flag "${RATE_LIMIT_ENFORCED}" || {
  echo "--rate-limit-enforced must be 0 or 1" >&2
  exit 2
}
if [[ -n "${MONTHLY_LIMIT_GB}" ]]; then
  [[ "${MONTHLY_LIMIT_GB}" =~ ^[0-9]+$ ]] || {
    echo "--monthly-limit-gb must be an integer" >&2
    exit 2
  }
  (( MONTHLY_LIMIT_GB >= 1 && MONTHLY_LIMIT_GB <= 10000 )) || {
    echo "--monthly-limit-gb must be between 1 and 10000" >&2
    exit 2
  }
fi
if [[ -n "${MAX_DEVICES}" ]]; then
  [[ "${MAX_DEVICES}" =~ ^[0-9]+$ ]] || {
    echo "--max-devices must be an integer" >&2
    exit 2
  }
  (( MAX_DEVICES >= 1 && MAX_DEVICES <= 5 )) || {
    echo "--max-devices must be between 1 and 5" >&2
    exit 2
  }
fi
if [[ -n "${SPEED_MBPS}" ]]; then
  [[ "${SPEED_MBPS}" =~ ^[0-9]+$ ]] || {
    echo "--speed-mbps must be an integer" >&2
    exit 2
  }
  (( SPEED_MBPS >= 1 && SPEED_MBPS <= 1000 )) || {
    echo "--speed-mbps must be between 1 and 1000" >&2
    exit 2
  }
fi

if [[ -n "${ROLLBACK_DIR}" ]]; then
  [[ -z "${ENABLED}${QUOTA_ENFORCED}${RATE_LIMIT_ENFORCED}${MONTHLY_LIMIT_GB}${MAX_DEVICES}${SPEED_MBPS}" ]] || {
    echo "--rollback cannot be combined with setting changes" >&2
    exit 2
  }
else
  [[ -n "${ENABLED}${QUOTA_ENFORCED}${RATE_LIMIT_ENFORCED}${MONTHLY_LIMIT_GB}${MAX_DEVICES}${SPEED_MBPS}" ]] || {
    echo "Specify at least one free-tier setting" >&2
    usage >&2
    exit 2
  }
fi

echo "mode=$([[ ${APPLY} -eq 1 ]] && echo apply || echo dry-run)"
echo "contour=${CONTOUR}"
if [[ -n "${ROLLBACK_DIR}" ]]; then
  echo "action=rollback"
  echo "rollback_dir=${ROLLBACK_DIR}"
else
  echo "action=configure"
  [[ -z "${ENABLED}" ]] || echo "free_tier_enabled=${ENABLED}"
  [[ -z "${QUOTA_ENFORCED}" ]] || echo "quota_enforced=${QUOTA_ENFORCED}"
  [[ -z "${RATE_LIMIT_ENFORCED}" ]] || echo "rate_limit_enforced=${RATE_LIMIT_ENFORCED}"
  [[ -z "${MONTHLY_LIMIT_GB}" ]] || echo "monthly_limit_gb=${MONTHLY_LIMIT_GB}"
  [[ -z "${MAX_DEVICES}" ]] || echo "max_devices=${MAX_DEVICES}"
  [[ -z "${SPEED_MBPS}" ]] || echo "speed_mbps=${SPEED_MBPS}"
fi

[[ ${APPLY} -eq 1 ]] || exit 0
[[ ${EUID} -eq 0 ]] || { echo "Run apply mode as root" >&2; exit 1; }
[[ -f "${ENV_FILE}" && ! -L "${ENV_FILE}" ]] || {
  echo "Selected contour environment file is missing or unsafe" >&2
  exit 2
}

python3 - "${ENV_FILE}" "${CONTOUR}" <<'PY'
import pathlib
import re
import sys

path = pathlib.Path(sys.argv[1])
contour = sys.argv[2]
values = {}
assignment = re.compile(r"^(?:export\s+)?([A-Za-z_][A-Za-z0-9_]*)\s*=(.*)$")
for raw in path.read_text(encoding="utf-8").splitlines():
    match = assignment.match(raw.strip())
    if match:
        values[match.group(1)] = match.group(2).strip().strip("\"'")

if contour == "paid-beta":
    expected = {
        "BLUEVPN_BASE_DIR": "/opt/bluevpn-paid-beta/current/backend",
        "BLUEVPN_DATA_DIR": "/opt/bluevpn-paid-beta/data",
        "GREENVPN_PAID_BETA_ENABLED": "1",
        "GREENVPN_PAID_BETA_RELEASE_CHANNEL": "paid-beta",
        "GREENVPN_FREE_AD_GATE_ENABLED": "0",
    }
else:
    expected = {
        "GREENVPN_PUBLIC_PRODUCT_ENABLED": "1",
        "GREENVPN_PUBLIC_PRODUCT_RELEASE_CHANNEL": "public-product",
        "GREENVPN_FREE_AD_GATE_ENABLED": "0",
    }
bad = [key for key, value in expected.items() if values.get(key) != value]
if bad:
    raise SystemExit(
        "Refusing mismatched or ad-enabled environment: " + ", ".join(bad)
    )
PY

if [[ -n "${ROLLBACK_DIR}" ]]; then
  backup_real="$(readlink -f -- "${ROLLBACK_DIR}")"
  root_real="$(readlink -f -- "${BACKUP_ROOT}")"
  case "${backup_real}" in
    "${root_real}"/*) ;;
    *) echo "Rollback path must be below ${BACKUP_ROOT}" >&2; exit 2 ;;
  esac
  backup_env="${backup_real}/${BACKUP_ENV_NAME}"
  [[ -f "${backup_env}" && ! -L "${backup_env}" ]] || {
    echo "Rollback environment backup is missing or unsafe" >&2
    exit 2
  }
  cp -a -- "${backup_env}" "${ENV_FILE}.rollback.tmp"
  chown root:root "${ENV_FILE}.rollback.tmp"
  chmod 600 "${ENV_FILE}.rollback.tmp"
  mv -f -- "${ENV_FILE}.rollback.tmp" "${ENV_FILE}"
  systemctl restart "${SERVICE}"
  for _ in $(seq 1 45); do
    curl -fsS --max-time 3 "${LOCAL_HEALTH}" >/dev/null && break
    sleep 1
  done
  curl -fsS --max-time 5 "${LOCAL_HEALTH}" >/dev/null
  systemctl is-active --quiet "${SERVICE}"
  echo "free_tier_status=rolled_back"
  echo "contour=${CONTOUR}"
  exit 0
fi

timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
backup_dir="${BACKUP_ROOT}/${timestamp}"
install -d -m 700 "${backup_dir}"
cp -a -- "${ENV_FILE}" "${backup_dir}/${BACKUP_ENV_NAME}"
chmod 600 "${backup_dir}/${BACKUP_ENV_NAME}"

modified=0
rollback_on_error() {
  code=$?
  trap - ERR
  if [[ ${modified} -eq 1 ]]; then
    cp -a -- "${backup_dir}/${BACKUP_ENV_NAME}" "${ENV_FILE}"
    chown root:root "${ENV_FILE}"
    chmod 600 "${ENV_FILE}"
    systemctl restart "${SERVICE}" >/dev/null 2>&1 || true
  fi
  exit "${code}"
}
trap rollback_on_error ERR

python3 - \
  "${ENV_FILE}" \
  "${ENABLED}" \
  "${QUOTA_ENFORCED}" \
  "${RATE_LIMIT_ENFORCED}" \
  "${MONTHLY_LIMIT_GB}" \
  "${MAX_DEVICES}" \
  "${SPEED_MBPS}" <<'PY'
import os
import pathlib
import re
import sys

path = pathlib.Path(sys.argv[1])
(
    enabled,
    quota_enforced,
    rate_limit_enforced,
    monthly_limit_gb,
    max_devices,
    speed_mbps,
) = sys.argv[2:]
updates = {
    key: value
    for key, value in {
        "GREENVPN_FREE_TIER_ENABLED": enabled,
        "GREENVPN_FREE_TIER_QUOTA_ENFORCED": quota_enforced,
        "GREENVPN_FREE_TIER_RATE_LIMIT_ENFORCED": rate_limit_enforced,
        "GREENVPN_FREE_TIER_MONTHLY_LIMIT_GB": monthly_limit_gb,
        "GREENVPN_FREE_TIER_MAX_DEVICES": max_devices,
        "GREENVPN_FREE_TIER_SPEED_MBPS": speed_mbps,
    }.items()
    if value
}

assignment = re.compile(r"^(?:export\s+)?([A-Za-z_][A-Za-z0-9_]*)\s*=")
out = []
for raw in path.read_text(encoding="utf-8").splitlines():
    match = assignment.match(raw.strip())
    if match and match.group(1) in updates:
        continue
    out.append(raw)
for key, value in updates.items():
    out.append(f"{key}={value}")

temporary = path.with_name(path.name + ".free-tier.tmp")
temporary.write_text("\n".join(out) + "\n", encoding="utf-8")
os.chmod(temporary, 0o600)
os.replace(temporary, path)
PY
modified=1
chown root:root "${ENV_FILE}"
chmod 600 "${ENV_FILE}"

systemctl restart "${SERVICE}"
for _ in $(seq 1 45); do
  curl -fsS --max-time 3 "${LOCAL_HEALTH}" >/dev/null && break
  sleep 1
done
curl -fsS --max-time 5 "${LOCAL_HEALTH}" >/dev/null
systemctl is-active --quiet "${SERVICE}"

python3 - "${ENV_FILE}" <<'PY'
import pathlib
import re
import sys

path = pathlib.Path(sys.argv[1])
assignment = re.compile(r"^(?:export\s+)?([A-Za-z_][A-Za-z0-9_]*)\s*=(.*)$")
values = {}
for raw in path.read_text(encoding="utf-8").splitlines():
    match = assignment.match(raw.strip())
    if match:
        values[match.group(1)] = match.group(2).strip().strip("\"'")

for key in (
    "GREENVPN_FREE_TIER_ENABLED",
    "GREENVPN_FREE_TIER_QUOTA_ENFORCED",
    "GREENVPN_FREE_TIER_RATE_LIMIT_ENFORCED",
):
    if values.get(key) not in {"0", "1"}:
        raise SystemExit(f"postcondition failed: {key}")
for key, minimum, maximum in (
    ("GREENVPN_FREE_TIER_MONTHLY_LIMIT_GB", 1, 10000),
    ("GREENVPN_FREE_TIER_MAX_DEVICES", 1, 5),
    ("GREENVPN_FREE_TIER_SPEED_MBPS", 1, 1000),
):
    try:
        value = int(values.get(key, ""))
    except ValueError:
        raise SystemExit(f"postcondition failed: {key}")
    if value < minimum or value > maximum:
        raise SystemExit(f"postcondition failed: {key}")

print(f"free_tier_enabled={values['GREENVPN_FREE_TIER_ENABLED']}")
print(f"quota_enforced={values['GREENVPN_FREE_TIER_QUOTA_ENFORCED']}")
print(f"rate_limit_enforced={values['GREENVPN_FREE_TIER_RATE_LIMIT_ENFORCED']}")
print(f"monthly_limit_gb={values['GREENVPN_FREE_TIER_MONTHLY_LIMIT_GB']}")
print(f"max_devices={values['GREENVPN_FREE_TIER_MAX_DEVICES']}")
print(f"speed_mbps={values['GREENVPN_FREE_TIER_SPEED_MBPS']}")
PY

trap - ERR
echo "free_tier_status=ok"
echo "contour=${CONTOUR}"
echo "backup_dir=${backup_dir}"
echo "rollback_command=$0 --contour ${CONTOUR} --rollback ${backup_dir} --apply"
