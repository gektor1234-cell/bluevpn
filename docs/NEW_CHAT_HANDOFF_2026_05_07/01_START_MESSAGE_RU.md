# Первое сообщение для нового Codex-чата

Скопируй текст ниже первым сообщением в новый чат.

```text
Продолжаем проект Green VPN.

Репозиторий:
C:\Users\gekto\projects\bluevpn

Сначала прочитай новый handoff-пакет:
C:\Users\gekto\projects\bluevpn\docs\NEW_CHAT_HANDOFF_2026_05_07\README_RU.md
C:\Users\gekto\projects\bluevpn\docs\NEW_CHAT_HANDOFF_2026_05_07\00_COVER_LETTER_RU.md
C:\Users\gekto\projects\bluevpn\docs\NEW_CHAT_HANDOFF_2026_05_07\02_WORKFLOW_AND_COMMUNICATION_RU.md
C:\Users\gekto\projects\bluevpn\docs\NEW_CHAT_HANDOFF_2026_05_07\03_PROJECT_STATE_RU.md
C:\Users\gekto\projects\bluevpn\docs\NEW_CHAT_HANDOFF_2026_05_07\04_NON_NEGOTIABLE_RULES_RU.md
C:\Users\gekto\projects\bluevpn\docs\NEW_CHAT_HANDOFF_2026_05_07\06_YOOKASSA_AND_PAYMENTS_RU.md
C:\Users\gekto\projects\bluevpn\docs\NEW_CHAT_HANDOFF_2026_05_07\13_NEXT_DEVELOPMENT_TASKS_RU.md
C:\Users\gekto\projects\bluevpn\docs\NEW_CHAT_HANDOFF_2026_05_07\14_TEST_AND_DEPLOY_COMMANDS_RU.md

Если нужны детали, открывай остальные файлы из этого же каталога. Большие docs открывай только точечно:
C:\Users\gekto\projects\bluevpn\docs\CODEX_CONTEXT_COMPACT_RU.md
C:\Users\gekto\projects\bluevpn\docs\CURRENT_HANDOFF.md
C:\Users\gekto\projects\bluevpn\docs\RELEASE_STATE.md
C:\Users\gekto\projects\bluevpn\docs\GREENVPN_MASTER_PLAN.md
C:\Users\gekto\projects\bluevpn\docs\DEVELOPMENT_PROTOCOL.md

Критически важно:
- Видимый бренд: Green VPN.
- Внутренние имена пока не переименовывать: BlueVPNDev1, WireGuardTunnel$BlueVPNDev1, C:\ProgramData\BlueVPN.
- Не трогать Friendly Linnet/personal server, Amnezia, WARP и чужие VPN.
- Dev/prod server: 37.220.85.211.
- Domain/API: greenvpn.pro, https://api.greenvpn.pro.
- Пароли, admin token, SMTP/SMS/YooKassa secrets и WireGuard private keys не писать в repo и не выводить в чат.
- Не делать git reset --hard, git checkout -- или destructive cleanup без моего прямого разрешения.
- В worktree много незакоммиченных изменений, сначала сделай git status --short.
- Новый installer не собирать до финального handoff или моей явной просьбы остановиться и тестировать.

Текущий backend live: 0.9.67.
Public site readiness live: GET /api/v1/admin/site/readiness green, bannedPhraseMatches=0.
Payment smoke readiness live: GET /api/v1/admin/billing/payment-smoke/readiness; currently blocked until YooKassa production keys are applied through safe env.
Billing renewals/expiry readiness require clean payment smoke before any safe-enable signal.
Payment launch safety CLI: scripts\windows\check_payment_launch_safety.ps1; owner packet command: payment_launch_safety.
Monitoring probe plan CLI: scripts\windows\get_monitoring_probe_plan.ps1; owner packet command: monitoring_probe_plan.
User auth flow readiness live: GET /api/v1/admin/auth/user-flow/readiness green; phone_code primary, email_code fallback, no codes/tokens exposed.
Launch closure plan live: GET /api/v1/admin/launch/closure-plan; support SLA is clean and inactive START20 draft exists. Launch gates now have no unblocked autonomous next item; remaining items are owner/final/payment-dependent.
Owner launch packet live: GET /api/v1/admin/launch/owner-packet; gives owner-facing commands/inputs/checks without returning secret values.
Owner-action notes are server-guarded; fake/real-looking secret assignments are rejected without echoing values.
API/VPN split-plan live includes mutation-free preflight tooling via scripts\windows\check_api_vpn_split_preflight.ps1.
ЮKassa в кабинете владельца теперь активна, но backend еще нужно подключить через server-only env. Нужны YOOKASSA_SHOP_ID и YOOKASSA_SECRET_KEY; secret key не писать в чат, вводить через scripts\windows\configure_backend_env_wsl.ps1.

Главный красный production-блокер: api.greenvpn.pro и VPN endpoint пока используют один IP 37.220.85.211. Для публичного запуска нужно разделить API/site IP и VPN endpoint IP.

Работай по нашему протоколу:
- если я рядом и даю внешние данные, веди пошагово;
- если я ухожу на 5-7 часов, работай автономно пункт за пунктом по плану, проверяй, деплой backend только по необходимости, обновляй handoff docs и не останавливайся после одного маленького пункта.

Начни с инвентаризации состояния проекта и доведи текущий логический шаг до конца.
```
