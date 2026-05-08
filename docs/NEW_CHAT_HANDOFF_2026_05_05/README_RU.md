# Green VPN: пакет передачи в новый чат

Этот каталог создан специально, чтобы начать новый чат Codex без тяжёлого старого контекста.

Новый чат должен сначала прочитать этот файл, затем `00_START_MESSAGE_RU.md`, затем только нужные рабочие файлы из этого каталога. Не надо заново грузить весь старый диалог, скриншоты и длинные переписки.

## Как использовать

1. Открой новый чат в том же проекте.
2. Вставь текст из `00_START_MESSAGE_RU.md` первым сообщением.
3. Прикрепи этот каталог или отдельные файлы из него.
4. Попроси новый чат начать с инвентаризации и продолжить пункт `08_NEXT_DEVELOPMENT_TASKS_RU.md`.

## Старый чат как аварийный архив

Новый чат не должен читать старую переписку по умолчанию, потому что именно она раздувает контекст. Но если handoff-файлов не хватает, есть противоречие, непонятно происхождение решения или нужно восстановить точную историю багов/тестов, текущий старый чат можно использовать как аварийный архив.

Правило: сначала читать этот handoff-пакет и файлы проекта, потом код, потом docs, и только в крайней необходимости обращаться к старой переписке.

## Что внутри

- `00_START_MESSAGE_RU.md` - готовое первое сообщение для нового чата.
- `01_PROJECT_STATE_RU.md` - текущее состояние Green VPN.
- `02_MASTER_PLAN_FULL_RU.md` - полный мастер-план, в том формате, по которому мы идём.
- `03_NON_NEGOTIABLE_RULES_RU.md` - правила, которые нельзя нарушать.
- `04_RELEASE_AND_ROLLBACK_RU.md` - стабильные сборки, rollback, installer.
- `05_BACKEND_ADMIN_MONITORING_RU.md` - backend, admin API, health scoring, monitoring.
- `06_USER_APP_INSTALLER_RU.md` - пользовательское приложение, installer, service, tray.
- `07_EXTERNAL_SERVICES_OWNER_ACTIONS_RU.md` - что должен подключить владелец: домен, почта, SMS, YooKassa, сертификаты.
- `08_NEXT_DEVELOPMENT_TASKS_RU.md` - ближайшие задачи в правильном порядке.
- `09_TEST_AND_DEPLOY_COMMANDS_RU.md` - команды проверки, сборки и деплоя.
- `10_CONTEXT_HYGIENE_RU.md` - как не раздувать контекст снова.
- `11_SECRET_HANDLING_RU.md` - что считается секретами и куда их нельзя писать.
- `12_ADMIN_SUPPORT_APP_RU.md` - отдельная админка/саппорт-приложение.

## Самая короткая суть

Green VPN - Windows-first Flutter VPN-клиент с backend на сервере `37.220.85.211`, доменом `greenvpn.pro`, API `https://api.greenvpn.pro`, отдельным Windows service и отдельной внутренней админкой.

Видимый бренд: `Green VPN`.

Внутренние имена пока не переименовывать:

- `BlueVPNDev1`
- `WireGuardTunnel$BlueVPNDev1`
- `C:\ProgramData\BlueVPN`

Текущая ближайшая разработка: backend/admin monitoring, server catalog, health scoring, support/admin tooling, дальше auth/support report/update/payment/resilience строго по плану.

## Важное

В этом каталоге нет паролей, admin token, SSH secrets, YooKassa secrets, SMTP passwords, SMS keys, WireGuard private keys. Новый чат не должен просить хранить их в репозитории.
