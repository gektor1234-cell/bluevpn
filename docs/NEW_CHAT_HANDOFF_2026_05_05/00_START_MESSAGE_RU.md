# Первое сообщение для нового Codex-чата

Продолжаем проект Green VPN. Репозиторий лежит здесь:

`C:\Users\gekto\projects\bluevpn`

Сначала обязательно прочитай эти файлы:

`C:\Users\gekto\projects\bluevpn\docs\NEW_CHAT_HANDOFF_2026_05_05\README_RU.md`

`C:\Users\gekto\projects\bluevpn\docs\NEW_CHAT_HANDOFF_2026_05_05\01_PROJECT_STATE_RU.md`

`C:\Users\gekto\projects\bluevpn\docs\NEW_CHAT_HANDOFF_2026_05_05\02_MASTER_PLAN_FULL_RU.md`

`C:\Users\gekto\projects\bluevpn\docs\NEW_CHAT_HANDOFF_2026_05_05\03_NON_NEGOTIABLE_RULES_RU.md`

`C:\Users\gekto\projects\bluevpn\docs\NEW_CHAT_HANDOFF_2026_05_05\08_NEXT_DEVELOPMENT_TASKS_RU.md`

Потом, если нужно, прочитай:

`C:\Users\gekto\projects\bluevpn\docs\NEW_CHAT_HANDOFF_2026_05_05\09_TEST_AND_DEPLOY_COMMANDS_RU.md`

`C:\Users\gekto\projects\bluevpn\docs\CODEX_CONTEXT_COMPACT_RU.md`

`C:\Users\gekto\projects\bluevpn\docs\CURRENT_HANDOFF.md`

`C:\Users\gekto\projects\bluevpn\docs\RELEASE_STATE.md`

Критически важно:

1. Это Windows-first Flutter VPN-клиент. Цель - продаваемый Windows MVP.
2. Видимый бренд теперь `Green VPN`.
3. Внутренний tunnel/config/service пока НЕ переименовывать:
   - `BlueVPNDev1`
   - `WireGuardTunnel$BlueVPNDev1`
   - `C:\ProgramData\BlueVPN`
4. Не трогать Friendly Linnet/personal server, Amnezia, WARP и чужие VPN.
5. Рабочий dev/prod server: `37.220.85.211`.
6. Production domain: `greenvpn.pro`.
7. Production API: `https://api.greenvpn.pro`.
8. Пароли, tokens, admin_token, YooKassa secrets, SMTP passwords, SMS keys, WireGuard private keys в репозиторий не писать и в чат не выводить.
9. Не делать `git reset --hard`, `git checkout --`, destructive cleanup или массовые удаления без прямого разрешения.
10. В worktree много незакоммиченных изменений. Сначала смотри `git status --short`.
11. Пользовательский VPN-клиент и installer не трогать, если текущая задача касается только backend/admin app.
12. Если клиент меняется и получается стабильная версия, нужно готовить свежий `GreenVPN_Setup.exe` и чистить предыдущую локальную установку тестового Green VPN.

Текущий рабочий installer:

`C:\BlueVPN_Builds\GreenVPN_Setup.exe`

`C:\BlueVPN_Builds\GreenVPN_Setup_LATEST.exe`

Стабильный rollback:

`C:\BlueVPN_Builds\ROLLBACK_20260430_2028_payment_confirmation_ok\GreenVPN_Setup_ROLLBACK.exe`

Главная текущая задача ближайшего этапа:

Стабилизировать backend/admin monitoring, health scoring и server catalog. Публичный клиентский catalog должен оставаться безопасным и не выдавать managed endpoints пользователям автоматически.

Текущие ожидаемые endpoints:

- `GET /healthz`
- `GET /api/v1/catalog/servers`
- `GET /api/v1/admin/server-catalog`
- `GET /api/v1/admin/server-health`
- `POST /api/v1/admin/server-health/probe-current`

Health scoring должен быть внутренним:

- проверяет `wg0`, конфиг, peer/handshake, UDP endpoint;
- не пишет ключи, токены, приватные конфиги;
- сохраняет только безопасные технические признаки и score `0-100`;
- русские формулировки в админке: `Наблюдения здоровья`, `Оценка здоровья`, `Проверить текущий endpoint`, `Задержка`, `потери`, `статус`, `score`.

Работай по мастер-плану из `02_MASTER_PLAN_FULL_RU.md`. Не придумывай хаотичные пользовательские вкладки, не возвращай dev/admin UI в обычный клиент, не меняй внутренние WireGuard имена.

Перед началом:

1. Выполни `git status --short`.
2. Проверь текущую версию backend в `backend_live\app\main.py`.
3. Проверь, что изменения действительно относятся к текущему пункту плана.
4. После работы обнови `CURRENT_HANDOFF.md`, `RELEASE_STATE.md`, `GREENVPN_MASTER_PLAN.md` или компактный handoff, если это нужно.

Не надо переписывать весь старый чат. Всё важное лежит в handoff-файлах.

Если handoff-файлов недостаточно, есть конфликт между документами или нужно восстановить точную причину решения, можно обратиться к старой переписке этого чата как к аварийному архиву. Но не читать её по умолчанию и не тащить в контекст без причины: сначала handoff, потом код, потом docs, и только потом старая переписка.
