#!/usr/bin/env bash
set -euo pipefail

SERVER_HOST="${1:-}"
if [[ -z "${SERVER_HOST}" ]]; then
  echo "Usage: $0 <control-plane-host>" >&2
  exit 2
fi
case "${SERVER_HOST}" in
  72.56.32.197|176.113.81.35) ;;
  *)
    echo "Refusing to configure backend env on non-control-plane host: ${SERVER_HOST}" >&2
    exit 2
    ;;
esac
REMOTE="root@${SERVER_HOST}"
APP_SERVICE="bluevpn-backend"
ENV_DIR="/etc/bluevpn"
ENV_FILE="${ENV_DIR}/backend.env"
DROPIN_DIR="/etc/systemd/system/${APP_SERVICE}.service.d"
DROPIN_FILE="${DROPIN_DIR}/greenvpn-secrets.conf"
REMOTE_UPDATE="${ENV_DIR}/backend.env.updates.$(date +%Y%m%d_%H%M%S).$$"

declare -a ENV_LINES=()

ask_yes_no() {
  local prompt="$1"
  local default="${2:-n}"
  local answer=""
  local suffix="[y/N]"
  if [[ "${default}" == "y" ]]; then
    suffix="[Y/n]"
  fi

  read -r -p "${prompt} ${suffix}: " answer || true
  answer="${answer:-${default}}"
  case "${answer,,}" in
    y|yes|д|да) return 0 ;;
    *) return 1 ;;
  esac
}

read_value() {
  local prompt="$1"
  local default="${2:-}"
  local value=""
  if [[ -n "${default}" ]]; then
    read -r -p "${prompt} [${default}]: " value || true
    printf '%s' "${value:-${default}}"
  else
    read -r -p "${prompt}: " value || true
    printf '%s' "${value}"
  fi
}

read_secret() {
  local prompt="$1"
  local value=""
  read -r -s -p "${prompt}: " value || true
  printf '\n' >&2
  printf '%s' "${value}"
}

read_required_secret() {
  local prompt="$1"
  local value=""
  local attempt=""
  for attempt in 1 2 3; do
    value="$(read_secret "${prompt}")"
    value="${value//$'\r'/}"
    if [[ -n "${value}" ]]; then
      printf '%s' "${value}"
      return 0
    fi
    echo "[Green VPN env] ${prompt} cannot be empty. Paste the value and press Enter." >&2
  done
  echo "[Green VPN env] ${prompt} is required; aborting without changing this secret." >&2
  exit 1
}

env_quote() {
  local value="$1"
  value="${value//$'\r'/}"
  value="${value//$'\n'/}"
  value="${value//\\/\\\\}"
  value="${value//\"/\\\"}"
  printf '"%s"' "${value}"
}

add_env() {
  local key="$1"
  local value="$2"
  if [[ -z "${value}" ]]; then
    return 0
  fi
  ENV_LINES+=("${key}=$(env_quote "${value}")")
}

generate_secret() {
  if command -v python3 >/dev/null 2>&1; then
    python3 - <<'PY'
import secrets
print(secrets.token_urlsafe(48))
PY
    return
  fi
  if command -v openssl >/dev/null 2>&1; then
    openssl rand -base64 48 | tr -d '\n'
    return
  fi
  date +%s%N | sha256sum | awk '{print $1}'
}

echo "[Green VPN env] Server: ${REMOTE}"
echo "[Green VPN env] This helper writes secrets only to ${ENV_FILE} on the server."
echo "[Green VPN env] Nothing secret is saved into the repository."
echo

add_env "GREENVPN_PUBLIC_API_BASE_URL" "https://api.greenvpn.pro"
add_env "GREENVPN_PUBLIC_BASE_URL" "https://api.greenvpn.pro"
add_env "GREENVPN_EMAIL_PUBLIC_BASE_URL" "https://api.greenvpn.pro"
add_env "GREENVPN_API_BASE_URLS" "https://api.greenvpn.pro"
add_env "GREENVPN_ADMIN_CORS_ORIGINS" "*"
add_env "GREENVPN_PUBLIC_SITE_URL" "https://api.greenvpn.pro"
add_env "GREENVPN_PAYMENT_PROVIDER" "yookassa"
add_env "YOOKASSA_RETURN_URL" "https://api.greenvpn.pro/payment/return"
add_env "YOOKASSA_WEBHOOK_URL" "https://api.greenvpn.pro/api/v1/billing/yookassa/webhook"
add_env "GREENVPN_PAID_SALES_ENABLED" "0"
add_env "GREENVPN_REFUND_EXECUTION_ENABLED" "0"
add_env "GREENVPN_REFUND_BILLING_PRIMARY" "0"
add_env "GREENVPN_AUTO_RENEWAL_CHARGES_ENABLED" "0"
add_env "GREENVPN_AUTO_RENEWAL_BILLING_PRIMARY" "0"
add_env "GREENVPN_TAX_RECEIPT_MODE" "yookassa_npd_manual"
add_env "GREENVPN_TAX_RECEIPT_WORKFLOW_CONFIRMED" "1"
add_env "GREENVPN_NPD_RECEIPT_MANUAL_OPERATOR_CONFIRMED" "0"
add_env "GREENVPN_NPD_RECEIPT_ALLOWED_HOSTS" "lknpd.nalog.ru"

if ask_yes_no "Configure public legal/requisites pages for the payment provider now?" "n"; then
  legal_owner_name="$(read_value "Public owner name for legal pages" "")"
  legal_owner_inn="$(read_value "Public self-employed INN for legal pages" "")"
  legal_contact_email="$(read_value "Public support/legal email" "support@greenvpn.pro")"

  add_env "GREENVPN_LEGAL_OWNER_NAME" "${legal_owner_name}"
  add_env "GREENVPN_LEGAL_OWNER_INN" "${legal_owner_inn}"
  add_env "GREENVPN_LEGAL_CONTACT_EMAIL" "${legal_contact_email}"
fi

if ask_yes_no "Generate/rotate one-time auth code pepper for email/phone login?" "n"; then
  add_env "GREENVPN_AUTH_CODE_PEPPER" "$(generate_secret)"
  add_env "GREENVPN_AUTH_CODE_TTL_MINUTES" "10"
  add_env "GREENVPN_AUTH_CODE_RESEND_COOLDOWN_SECONDS" "60"
  add_env "GREENVPN_AUTH_CODE_MAX_VERIFY_ATTEMPTS" "5"
  add_env "GREENVPN_AUTH_CODE_LOCKOUT_MINUTES" "15"
  add_env "GREENVPN_DEV_AUTH_CODES" "0"
fi

if ask_yes_no "Configure Yandex 360 SMTP email confirmation now?" "n"; then
  smtp_host="$(read_value "SMTP host" "smtp.yandex.ru")"
  smtp_port="$(read_value "SMTP port" "465")"
  smtp_user="$(read_value "SMTP username/full mailbox" "no-reply@greenvpn.pro")"
  smtp_from="$(read_value "From header" "Green VPN <no-reply@greenvpn.pro>")"
  smtp_password="$(read_secret "SMTP app password")"
  email_required="0"
  if ask_yes_no "Require confirmed email before protected actions now?" "n"; then
    email_required="1"
  fi

  add_env "GREENVPN_SMTP_HOST" "${smtp_host}"
  add_env "GREENVPN_SMTP_PORT" "${smtp_port}"
  add_env "GREENVPN_SMTP_USERNAME" "${smtp_user}"
  add_env "GREENVPN_SMTP_PASSWORD" "${smtp_password}"
  add_env "GREENVPN_SMTP_FROM" "${smtp_from}"
  add_env "GREENVPN_SMTP_USE_TLS" "1"
  add_env "GREENVPN_EMAIL_CONFIRMATION_REQUIRED" "${email_required}"
  add_env "GREENVPN_EMAIL_CONFIRMATION_TTL_HOURS" "24"
fi

echo "[Green VPN env] Direct SMS setup is skipped."
echo "[Green VPN env] SMS.ru refused VPN traffic and SMS Aero cannot deliver honest VPN-branded messages."
echo "[Green VPN env] Enable a phone provider only after written approval for Green VPN and a paid-beta OTP smoke."

if ask_yes_no "Configure YooKassa production credentials now?" "n"; then
  yookassa_shop_id="$(read_value "YOOKASSA_SHOP_ID" "")"
  if [[ -z "${yookassa_shop_id}" ]]; then
    echo "[Green VPN env] YOOKASSA_SHOP_ID is required; aborting without uploading changes." >&2
    exit 1
  fi
  yookassa_secret="$(read_required_secret "YOOKASSA_SECRET_KEY")"
  npd_operator_confirmed="0"
  if ask_yes_no "Is a named operator ready to register every payment and refund in My Tax?" "n"; then
    npd_operator_confirmed="1"
  fi

  add_env "YOOKASSA_SHOP_ID" "${yookassa_shop_id}"
  add_env "YOOKASSA_SECRET_KEY" "${yookassa_secret}"
  add_env "YOOKASSA_API_BASE" "https://api.yookassa.ru/v3"
  add_env "GREENVPN_NPD_RECEIPT_MANUAL_OPERATOR_CONFIRMED" "${npd_operator_confirmed}"
  add_env "GREENVPN_NPD_RECEIPT_ALLOWED_HOSTS" "lknpd.nalog.ru"
  add_env "GREENVPN_TAX_RECEIPT_MODE" "yookassa_npd_manual"
  add_env "GREENVPN_TAX_RECEIPT_WORKFLOW_CONFIRMED" "1"
  add_env "GREENVPN_TAX_RECEIPT_PAYMENT_SUBJECT" "service"
  add_env "GREENVPN_TAX_RECEIPT_PAYMENT_MODE" "full_payment"
  add_env "GREENVPN_REFUND_WORKFLOW_CONFIRMED" "0"
fi

if ask_yes_no "Configure final update and rollback artifacts now?" "n"; then
  latest_version="$(read_value "GREENVPN_LATEST_VERSION" "")"
  update_url="$(read_value "GREENVPN_UPDATE_URL (public HTTPS final installer)" "")"
  update_sha256="$(read_value "GREENVPN_UPDATE_SHA256" "")"
  rollback_version="$(read_value "GREENVPN_ROLLBACK_VERSION" "")"
  rollback_url="$(read_value "GREENVPN_ROLLBACK_URL (public HTTPS rollback installer)" "")"
  rollback_sha256="$(read_value "GREENVPN_ROLLBACK_SHA256" "")"

  add_env "GREENVPN_LATEST_VERSION" "${latest_version}"
  add_env "GREENVPN_UPDATE_URL" "${update_url}"
  add_env "GREENVPN_UPDATE_SHA256" "${update_sha256}"
  add_env "GREENVPN_ROLLBACK_VERSION" "${rollback_version}"
  add_env "GREENVPN_ROLLBACK_URL" "${rollback_url}"
  add_env "GREENVPN_ROLLBACK_SHA256" "${rollback_sha256}"
fi

if ask_yes_no "Configure Telegram incident alerts for admin/support now?" "n"; then
  telegram_bot_token="$(read_secret "Telegram bot token")"
  telegram_chat_id="$(read_value "Telegram chat id or @channel" "")"
  min_severity="$(read_value "Minimum severity for alerts (critical/high/medium/low)" "high")"

  add_env "GREENVPN_ADMIN_ALERTS_ENABLED" "1"
  add_env "GREENVPN_ADMIN_ALERT_MIN_SEVERITY" "${min_severity}"
  add_env "GREENVPN_TELEGRAM_ALERT_BOT_TOKEN" "${telegram_bot_token}"
  add_env "GREENVPN_TELEGRAM_ALERT_CHAT_ID" "${telegram_chat_id}"
fi

if [[ "${#ENV_LINES[@]}" -eq 0 ]]; then
  echo "[Green VPN env] Nothing to update."
  exit 0
fi

echo
echo "[Green VPN env] Uploading ${#ENV_LINES[@]} environment values to the server..."
printf '%s\n' "${ENV_LINES[@]}" | ssh "${REMOTE}" "umask 077; install -d -m 700 '${ENV_DIR}'; cat > '${REMOTE_UPDATE}'"

echo "[Green VPN env] Merging environment file and restarting backend..."
ssh "${REMOTE}" "bash -s -- '${ENV_FILE}' '${REMOTE_UPDATE}' '${DROPIN_DIR}' '${DROPIN_FILE}' '${APP_SERVICE}'" <<'REMOTE_SCRIPT'
set -euo pipefail

ENV_FILE="$1"
UPDATE_FILE="$2"
DROPIN_DIR="$3"
DROPIN_FILE="$4"
APP_SERVICE="$5"
KEY_FILE="$(mktemp)"
TMP_ENV="$(mktemp)"

cleanup() {
  rm -f "${KEY_FILE}" "${TMP_ENV}" "${UPDATE_FILE}"
}
trap cleanup EXIT

sed -n 's/^\([A-Za-z_][A-Za-z0-9_]*\)=.*/\1/p' "${UPDATE_FILE}" > "${KEY_FILE}"

install -d -m 700 "$(dirname "${ENV_FILE}")"
touch "${ENV_FILE}"
chmod 600 "${ENV_FILE}"

while IFS= read -r line || [[ -n "${line}" ]]; do
  if [[ "${line}" =~ ^[A-Za-z_][A-Za-z0-9_]*= ]]; then
    key="${line%%=*}"
    if grep -qxF "${key}" "${KEY_FILE}"; then
      continue
    fi
  fi
  printf '%s\n' "${line}" >> "${TMP_ENV}"
done < "${ENV_FILE}"

cat "${UPDATE_FILE}" >> "${TMP_ENV}"
install -m 600 "${TMP_ENV}" "${ENV_FILE}"

install -d -m 755 "${DROPIN_DIR}"
cat > "${DROPIN_FILE}" <<EOF
[Service]
EnvironmentFile=-${ENV_FILE}
EOF
chmod 644 "${DROPIN_FILE}"

systemctl daemon-reload
systemctl restart "${APP_SERVICE}"
for attempt in {1..20}; do
  if systemctl is-active --quiet "${APP_SERVICE}" && curl -fsS http://127.0.0.1:8000/healthz; then
    exit 0
  fi
  sleep 1
done

systemctl status "${APP_SERVICE}" --no-pager -l || true
echo "[Green VPN env] Backend did not become healthy after restart." >&2
exit 1
REMOTE_SCRIPT

echo
echo "[Green VPN env] Done."
