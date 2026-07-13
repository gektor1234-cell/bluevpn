# Карта проекта Green VPN

Актуально на 2026-07-13. Этот файл отвечает на вопрос «где менять конкретную
функцию». Текущее состояние production и запреты всегда сверяются с
`CURRENT_HANDOFF.md`.

## Порядок чтения

1. `CURRENT_HANDOFF.md` — текущие версии, серверы, checkpoints и запреты.
2. `PROJECT_MAP_RU.md` — расположение компонентов.
3. `PROJECT_OPERATIONS_MASTER_RUNBOOK_RU.md` — штатные операции и восстановление.
4. `SERVER_SECURITY_CONTOUR_INTEGRATION_RUNBOOK_RU.md` — транспортный контур.
5. Документ конкретного релиза или транспорта — только для его доказательств.

Старые отчёты не являются источником текущей конфигурации, если они расходятся
с handoff или фактическим runtime.

## Runtime-контуры

| Контур | Основной узел | Резерв | Назначение |
| --- | --- | --- | --- |
| Production API | Timeweb Москва | RUVDS Москва | вход, bootstrap, каталог, подписки, обновления |
| Paid/public candidate API | Timeweb Москва `/paid-beta-api` | RUVDS Москва `/paid-beta-api` | тарифы, YooKassa, транспортный preview |
| Stable VPN | NL1, London, NL2 | выбор через API | стабильные клиентские туннели |
| Transport preview | только NL2 | отсутствует | AWG2, Hysteria2, VLESS, Naive, dnstt |
| SMTP login codes | Timeweb Москва | RUVDS Москва | отправка email-кодов |
| Billing writer | Timeweb paid/public | RUVDS read/fallback | создание платежей и автопродление |

## Серверный инвентарь

| Узел | Роль | Ограничение |
| --- | --- | --- |
| `72.56.32.197` | Timeweb Москва, primary control plane | единственный billing writer |
| `176.113.81.35` | RUVDS Москва, fallback control plane | billing mutations запрещены |
| `37.220.85.211` | NL1 stable VPN | только stable data plane |
| `88.218.250.86` | London stable VPN/WARP | обслуживать отдельно от control plane |
| `5.129.216.42` | NL2 stable VPN + hidden preview | единственный разрешённый multiprotocol canary |
| `5.129.237.163` | внешний исключённый узел | не изменять |

KZ `94.198.221.206` выведен из эксплуатации. Для аварийного возврата сохранён
provider image `2d3d1ae6-899f-48f0-ba1e-985eb5e0344d`; живым узлом проекта он
больше не считается.

## Главные директории

| Путь | Ответственность |
| --- | --- |
| `lib/main.dart` | оболочка Flutter, auth/session, тарифы, UI, platform backends |
| `lib/services/transport_preview_policy.dart` | порядок и eligibility preview-транспортов |
| `lib/services/route_failure_cooldown.dart` | cooldown 1/3/10/30 минут |
| `android/app/` | Android application, VPN service, release signing |
| `android/transport_preview/awg_tunnel/` | изолированный AWG2 preview |
| `android/transport_preview/hysteria_tunnel/` | shared H2/VLESS/Naive/dnstt preview runtime |
| `backend_live/app/main.py` | API, DB schema, auth, billing, catalog, admin, monitoring |
| `backend_live/tests/` | backend policy, sync and transport guards |
| `admin_support_app/` | закрытая операторская web-консоль |
| `scripts/windows/` | Android/Windows build, installer, deploy and release gates |
| `scripts/server/` | root-only server rollout and rollback scripts |
| `scripts/ops/` | DB sync, probes, backup and operational services |
| `scripts/infra/` | provider APIs and creation of new VPS |
| `public_demo_site/` | актуальный источник публичной продуктовой страницы |
| `paid_beta_site/` | исторический закрытый beta-контур; не public source of truth |

Ключевые idempotent/guarded операции:

- `scripts/server/apply_server_os_baseline.sh` - OS, updates и time-sync audit;
- `scripts/server/ensure_server_time_sync.sh` - guarded slew/step времени;
- `scripts/server/repair_runtime_file_permissions.sh` - root-only ACL runtime;
- `scripts/ops/audit_sqlite_future_timestamps.py` - безопасный аудит timestamp;
- `scripts/ops/repair_sqlite_future_event_timestamps.py` - guarded repair только
  event timestamp с обязательным online-backup;
- `scripts/monitoring/public_surface_probe.py` - внешний тест без секретов;
- `scripts/windows/create_full_project_checkpoint.ps1` - полный encrypted restore point.

## Где менять функцию

| Задача | Основная точка | Обязательная проверка |
| --- | --- | --- |
| API endpoint | `backend_live/app/main.py` | backend tests + OpenAPI route index |
| SQLite schema | `init_db()` в backend | migration/idempotency test + snapshot |
| Логин/session | backend auth routes + `lib/main.dart` | background/relaunch physical test |
| Тарифы | `PUBLIC_PRODUCT_PLANS` + Flutter tariff UI | quote/order/activation tests |
| YooKassa | backend billing functions | provider-backed 249 RUB smoke |
| Каталог серверов | `server_catalog_entries` и admin API | обе control-plane DB + bootstrap |
| Новый обычный сервер | server bootstrap + catalog row | config probe from both APIs |
| Новый транспорт | isolated preview module + paid catalog | protocol physical proof and rollback |
| Android release | `pubspec.yaml`, Gradle, build script | expected signer fingerprint |
| Windows release | installer/service scripts | Authenticode + clean VM install |
| Принудительное обновление | update manifest/admin release | staged percentage then 100% |
| Публичный сайт | `public_demo_site/` | legal links, mobile/desktop, live fetch |
| Оферта/политика | site legal pages + backend legal routes | links from site and clients |
| Мониторинг | `scripts/monitoring/`, admin readiness | independent external probe |

## Динамическое добавление серверов

Приложение не требует обновления, если новый узел использует уже поддерживаемый
клиентом protocol/config contract. Сервер разворачивается отдельно, затем запись
добавляется в `server_catalog_entries`. Клиент получает её при следующем
bootstrap/catalog refresh.

Обновление приложения обязательно, если меняются native engine, формат конфига,
Android service, Windows service или capability contract.

## Секреты

- Локальный источник: `D:\GreenVPN_Secrets`, ACL только owner/SYSTEM/Admins.
- Серверы: root-only env/config (`0600`) под `/etc/bluevpn` и transport paths.
- В Git разрешены только `.example`, имена переменных, хэши публичных артефактов
  и отпечатки публичных сертификатов.
- Никогда не копировать значения ключей в документы, команды чата, логи или
  release manifests.

## Неполноценные платформы

Production-клиенты существуют для Android и Windows. `ios/`, `macos/`, `linux/`
и Flutter `web/` пока являются оболочками и не должны объявляться продуктами.
