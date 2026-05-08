# Сообщение для нового Codex

Скопируй текст из свежего start-файла:

`C:\Users\gekto\projects\bluevpn\docs\NEW_CHAT_HANDOFF_2026_05_07\01_START_MESSAGE_RU.md`

Новый пакет передачи:

`C:\Users\gekto\projects\bluevpn\docs\NEW_CHAT_HANDOFF_2026_05_07`

Обязательно прочитать в начале:

- `README_RU.md`
- `00_COVER_LETTER_RU.md`
- `02_WORKFLOW_AND_COMMUNICATION_RU.md`
- `03_PROJECT_STATE_RU.md`
- `04_NON_NEGOTIABLE_RULES_RU.md`
- `06_YOOKASSA_AND_PAYMENTS_RU.md`
- `13_NEXT_DEVELOPMENT_TASKS_RU.md`
- `14_TEST_AND_DEPLOY_COMMANDS_RU.md`

Короткая суть:

- Продолжаем Green VPN в `C:\Users\gekto\projects\bluevpn`.
- Видимый бренд: Green VPN.
- Внутренние имена не переименовывать: `BlueVPNDev1`, `WireGuardTunnel$BlueVPNDev1`, `C:\ProgramData\BlueVPN`.
- Не трогать Friendly Linnet, Amnezia, WARP и чужие VPN.
- Backend/live server: `37.220.85.211`.
- Public API/site: `https://api.greenvpn.pro`.
- Backend live: `0.9.67`.
- Public site readiness live: `GET /api/v1/admin/site/readiness` green (`bannedPhraseMatches=0`).
- Payment smoke readiness live: `GET /api/v1/admin/billing/payment-smoke/readiness`; currently blocked until YooKassa production keys are applied through safe env.
- Billing renewals/expiry readiness require clean payment smoke before any safe-enable signal.
- Payment launch safety CLI: `scripts\windows\check_payment_launch_safety.ps1`; also exposed as owner packet command `payment_launch_safety`.
- Monitoring probe plan CLI: `scripts\windows\get_monitoring_probe_plan.ps1`; also exposed as owner packet command `monitoring_probe_plan`.
- User auth flow readiness live: `GET /api/v1/admin/auth/user-flow/readiness` green (`phone_code` primary, `email_code` fallback, no codes/tokens exposed).
- Launch closure plan live: `GET /api/v1/admin/launch/closure-plan`; support SLA is clean and inactive `START20` draft exists. Launch gates now have no unblocked autonomous next item; remaining items are owner/final/payment-dependent.
- Owner launch packet live: `GET /api/v1/admin/launch/owner-packet`; gives owner-facing commands/inputs/checks without returning secret values.
- Owner launch packet CLI: `scripts\windows\get_owner_launch_packet.ps1`; admin token stays on the server by default.
- Owner-action notes are server-guarded: `POST /api/v1/admin/external-actions/{action_code}` rejects fake/real-looking secret assignments without echoing values; self-check reports `ownerNoteServerEnforced=true`.
- API/VPN split-plan live includes mutation-free preflight command via `scripts\windows\check_api_vpn_split_preflight.ps1`; run only after a separate API/site IP or reverse proxy exists.
- Separate admin/support app locally prechecks owner notes before POST, formats structured API errors without `[object Object]`, and renders the owner launch packet.
- ЮKassa в кабинете владельца активна; backend еще нужно подключить через `YOOKASSA_SHOP_ID` и `YOOKASSA_SECRET_KEY` только через safe env script.
- Главный red blocker перед public release: API/site и VPN endpoint пока на одном IP `37.220.85.211`.
- Новый installer не собирать до финального handoff или явной просьбы.

Старый чат использовать только как аварийный архив.
