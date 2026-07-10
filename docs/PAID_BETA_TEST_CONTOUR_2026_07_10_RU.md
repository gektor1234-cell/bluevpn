# Green VPN: изолированный тестовый paid beta-контур

Дата: 2026-07-10. Статус: работает только как закрытый тестовый контур. Этот документ не разрешает замену production stable или публичный массовый запуск.

## Размещение

| Роль | Узел | Beta API | Beta site |
| --- | --- | --- | --- |
| Primary | Timeweb Moscow `72.56.32.197` | `https://api.greenvpn.pro/paid-beta-api` | `https://greenvpn.pro/paid-beta/` |
| Fallback | RUVDS Moscow `176.113.81.35` | `https://176-113-81-35.sslip.io/paid-beta-api` | `https://176-113-81-35.sslip.io/paid-beta/` |

На каждом control-plane:

- service: `greenvpn-paid-beta.service`;
- bind: только `127.0.0.1:8010`;
- release root: `/opt/bluevpn-paid-beta/releases`;
- current symlink: `/opt/bluevpn-paid-beta/current`;
- data: `/opt/bluevpn-paid-beta/data/bluevpn.db`;
- root-only env: `/etc/bluevpn/paid-beta.env`;
- static current symlink: `/var/www/paid-beta`;
- DB sync: `greenvpn-paid-beta-db-sync.timer`, каждые 10 секунд;
- sync state: `/var/lib/greenvpn-paid-beta-db-sync`.

Production продолжает использовать отдельные `bluevpn-backend.service`, `127.0.0.1:8000`, `/opt/bluevpn/backend`, production DB и `/var/www/greenvpn/downloads`.

## Текущий release

- App: `0.3.0-paid-beta.2`, Android build `2026071002`.
- Backend: `0.9.106-paid-beta.2`.
- Release directory: `paid-beta-0.3.0-paid-beta.2-2026071002-r2`.
- Bundle SHA-256: `440671161C710AD6BA7A47D4A5DC77CB96D3451F9FF26E3C233EF58853295B17`.
- Android SHA-256: `29252A8AE44BA4487363E669A0ED31DDAC159289A49254EBBED34F123D20AB50`.
- Windows SHA-256: `41F96CB95118507AACA861721F83B2972CF419E2F10BA2FCF38CB73800988332`.
- Windows Authenticode: `NotSigned`.
- Client IP pool: `10.10.0.180-10.10.0.229`, проверен свободным относительно production DB и live peers перед запуском.

Beta-env создан из уже работающей серверной конфигурации, но получает отдельные auth/admin/invite peppers, отдельные пути, beta URLs и принудительно выключенные рекламу, session timer, auto-renew и beta alert-шум. Оба узла используют один beta invite/auth contract и отдельный одинаковый admin token. Значения не выводились и не попадали в Git.

## Nginx

В существующие TLS virtual hosts добавлены только includes:

- `/etc/nginx/snippets/greenvpn-paid-beta-api.conf`;
- `/etc/nginx/snippets/greenvpn-paid-beta-site.conf`.

API prefix срезается перед proxy на `127.0.0.1:8010`. Static path использует отдельный `/var/www/paid-beta`. Для beta routes выставлены `noindex`, `noarchive`, `nosniff` и `no-store`; directory listing выключен. Production root locations и downloads не заменялись.

## Проверки

- 22 backend/DB-sync unit tests: OK.
- Flutter smoke: OK; release APK/EXE: OK.
- Release gate: 0 предупреждений, 0 ошибок.
- Оба local/public beta health возвращают `0.9.106-paid-beta.2`.
- Оба production health одновременно возвращают `0.9.105`.
- Каталог на обоих beta-узлах содержит 5 managed записей и 3 доступных config-ready сервера.
- DB sync на обоих узлах активен; последние summary: 0 conflicts, 0 errors.
- Stateful HTTP smoke: login primary/fallback, beta denial до claim, персональный invite, Trial, quote 149 RUB, 2 устройства, без рекламы/timer, app-open/funnel, bootstrap и config на обоих API: OK.
- Primary/fallback выдали один и тот же config и `10.10.0.180`; тестовый peer затем удалён live и из `wg0.conf`.
- После cleanup на обоих control-plane: 0 smoke users/devices/subscriptions/invites/redemptions/events.
- При остановке только Timeweb beta primary вернул 502, selector выбрал RUVDS fallback; production `0.9.105` продолжил отвечать. После запуска primary восстановился.
- Android и Windows полностью скачаны по обоим HTTPS-маршрутам; размеры и SHA совпали.
- Production Android SHA остался `308320429991A3278E3BA903155482D6613425D46681F180338ECB8C0929248F`.
- Production Windows SHA остался `0B2FEAA2232582207CFB998902B04107067C8DDE1C4243A003FF979C2F2B5F15`.

## Backups и rollback

Installer сделал root-only backups:

- Timeweb first install: `/root/greenvpn-paid-beta-backups/20260710T094349Z-timeweb-paid-beta-0.3.0-paid-beta.2-2026071002`;
- RUVDS first install: `/root/greenvpn-paid-beta-backups/20260710T094428Z-ruvds-paid-beta-0.3.0-paid-beta.2-2026071002`;
- Timeweb r2: `/root/greenvpn-paid-beta-backups/20260710T101011Z-timeweb-paid-beta-0.3.0-paid-beta.2-2026071002-r2`;
- RUVDS r2: `/root/greenvpn-paid-beta-backups/20260710T101015Z-ruvds-paid-beta-0.3.0-paid-beta.2-2026071002-r2`.

Первый backend release сохранён рядом с r2 для адресного rollback. На NL1 есть отдельная backup конфигурации перед ручной очисткой первого smoke peer: `/root/greenvpn-paid-beta-smoke-cleanup-20260710T100214Z`.

Rollback beta выполняется отдельно: остановить beta sync, переключить beta current/site symlinks на предыдущий release, перезапустить только `greenvpn-paid-beta.service`, проверить `:8010` и снова включить beta sync. Production service/DB/downloads при beta rollback не трогать.

## Оставшиеся ограничения

- Два SQLite-узла не дают глобальную транзакционную блокировку при строго одновременном claim до sync. Для 20 персональных кодов используется primary-normal/fallback-only; массовый запуск требует общего transactional storage или одного write authority.
- Реальный платёж YooKassa не создавался. Webhook production не перенастраивался; beta пока рассчитывает на client polling. Владелец должен провести один реальный платёж и сверку активации/возврата.
- Windows installer не подписан Authenticode.
- Android и Windows beta ещё нужно установить на реальные устройства владельца и проверить upgrade/background/reboot.
- Beta legal/privacy тексты не проверены профильным юристом.
- `noindex` не является контролем доступа к бинарникам; продуктовый доступ защищает marker + персональный invite + cohort.
