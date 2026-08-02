# Green VPN: working model

Дата фиксации: 2026-08-02.

Этот файл - текущий источник правды по логике Green VPN. Он не содержит секретов.

## Жесткие правила

- Каждый серьезный проход начинается с `git status --short`.
- Секреты, API keys, SMTP/SMS/YooKassa secrets, SSH private keys и WireGuard private keys не выводить в чат и не писать в repo.
- Не делать `git reset --hard`, `git checkout --` и destructive cleanup без прямого разрешения владельца.
- Видимый бренд: Green VPN. Внутренние имена BlueVPN пока допустимы.
- FriendlyLynet / Friendly Linnet не трогать.
- Основной сайт и stable-контур не трогать без явной команды владельца, потому что там сидят реальные пользователи.

## Замороженный Product Contract

- Решение владельца от 2026-08-02: `v1` закрывается как бесплатный
  direct-download VPN. Монетизация, реклама и магазины перенесены на следующий
  этап и не являются частью `v1` без нового явного решения владельца.

- Базовый продукт - постоянный Free, а не трехдневный Trial.
- Первый запуск - гостевой, без логина, SMS и обязательного email.
- Email требуется только перед оплатой либо для восстановления ранее
  привязанного доступа.
- Free policy управляется сервером: месячный лимит, число устройств, профиль
  скорости и enforcement меняются без обновления приложения.
- Текущее live-состояние: stored quota `3 GB/month`, one device,
  `10 Mbit/s` base / `20 Mbit/s` burst; quota enforcement и rate enforcement
  выключены, поэтому лимит трафика сейчас снят.
- Paid sales, refund execution, tax confirmation and automatic renewal charges
  fail closed. Rewarded ads and forced disconnect also remain off.
- Три платных срока `249/649/1099 RUB` сохранены в каталоге, но реальный
  checkout нельзя открывать до отдельного legal/tax owner gate.
- Authenticode для Windows перенесён отдельным внешним gate: на 2026-08-02 у
  владельца нет доступного проверенного публично доверенного маршрута выпуска
  при текущем юридическом статусе. Персональные и налоговые идентификаторы в
  репозитории не сохраняются. Текущая `v1` остаётся честно `NotSigned`;
  условия провайдеров нужно проверить заново после оформления ИП/юрлица либо
  при выборе Microsoft Store.

## Контуры

### Stable/main

- Сайт: `https://greenvpn.pro`.
- API: `https://api.greenvpn.pro`.
- Назначение: рабочий no-ads permanent-Free продукт для реальных пользователей.
- Stable не должен внезапно получать рекламу, тестовые проверки, экспериментальные серверы или рискованные update-манифесты.

### Preview/test

- Приватная тестовая страница: `https://greenvpn.pro/release-preview-20260517-private/`.
- Назначение: rewarded ads/adgate, принудительные обновления, новые серверы, новая логика Android/Windows.
- Все спорные изменения сначала идут сюда.
- Preview может видеть больше серверов, чем stable.

## Клиентская логика

### Login

1. При первом запуске клиент автоматически создаёт guest session.
2. Пользователь может подключиться в Free без email, телефона или пароля.
3. Перед checkout либо при восстановлении клиент вызывает
   `POST /api/v1/auth/email/code/start`.
4. Backend отправляет короткий email-код через SMTP.
5. Клиент подтверждает код через `POST /api/v1/auth/email/code/verify`.
6. Backend связывает guest/paid account и возвращает session token.
7. Клиент хранит session в защищённом хранилище платформы.
8. Ошибка SMTP не должна ломать уже работающий гостевой Free.

### Bootstrap/config

1. После входа или перед подключением клиент вызывает bootstrap/config.
2. Backend привязывает устройство и выбирает сервер.
3. Backend создает peer/config для конкретного устройства.
4. Клиент передает конфиг нативному VPN-слою.
5. Android показывает статус по факту владения VPN-туннелем нашим приложением, а не только по локальному флагу.

Важно: если Android показывает ключ в статус-баре, но приложение пишет `Другой VPN активен`, значит система держит VPN-сервис, который клиент не распознал как свой. Эту проверку нельзя делать только через сохраненный UI-state.

### Server select

- `Авто` выбирает доступный сервер из catalog.
- Ручной выбор сервера должен немедленно переполучать config под выбранный server id.
- Переключение сервера при уже активном VPN должно перезапускать туннель без требования вручную выключить/включить.
- Если выбранный сервер мертв, клиент должен быстро снять состояние подключения и дать понятную ошибку.

### Social-only

- Android social-only должен использовать per-app VPN.
- Включение social-only не должно ломать обычный full-tunnel режим.
- YouTube должен оставаться вне social-only, если пользователь выбрал только Telegram/Instagram.

### Ads/adgate

- Stable и paid-beta: рекламы сейчас нет.
- Будущая реклама может включаться только server-side после письменного
  разрешения провайдера и отдельного paid-beta smoke.
- Рекламу и таймер бесплатной сессии надо уметь отключать с backend без обновления приложения.
- Fake completion, autoplay, скрытые показы, автоклики и client-only grant
  запрещены. Один подтверждённый grant может дать только одно подключение.

### Updates

- Android должен получать APK, Windows - EXE.
- Нельзя допускать, чтобы телефон скачивал Windows installer.
- Update-flow должен быть в одну кнопку насколько это возможно для Android: скачать APK внутри приложения, открыть системную установку, не плодить лишние файлы в Downloads.
- Stable update и preview update должны быть разделены.
- Force-update для stable возможен технически, но включать его только отдельной командой владельца.

## Backend/API failover

Клиенты должны иметь минимум два API base URL:

- primary: `https://api.greenvpn.pro`;
- fallback: `https://176-113-81-35.sslip.io`.

Current control-plane policy after 2026-07-05:

- Timeweb Moscow `72.56.32.197` is the primary Russian API/site/download server.
- RUVDS Moscow `176.113.81.35` / `https://176-113-81-35.sslip.io` is the Russian fallback API/download mirror.
- RUVDS London `88.218.250.86` stays online only as legacy compatibility for already-built clients that still have its old hardcoded fallback.
- Foreign servers must be VPN nodes only, not the primary auth/bootstrap/config path for new builds.

Client API stickiness after 2026-07-05:

- Auth code start and auth code verify must stay on the same API base.
- The API base that returns a successful session is stored in `Session.apiBaseUrl`.
- Bootstrap/config bearer requests must prefer `Session.apiBaseUrl`.
- Failover to another API base is allowed for network/timeout/5xx errors, not for non-retriable auth/code/token errors on the sticky base.
- Timeweb Moscow and RUVDS Moscow now run bidirectional SQLite state sync every 30 seconds via `greenvpn-db-sync.timer`.
- The sync does not overwrite a live DB file. It streams a consistent peer snapshot and merges critical rows by natural keys.
- Critical auth/session/device/ad-grant/email state should be available on the other Russian control-plane within one timer interval.
- Conflicting rows are logged and left untouched; the sync is practical near-real-time failover, not a full distributed database.
- A future stronger active-active option is PostgreSQL, rqlite, LiteFS, or another DB layer with real consensus/replication semantics.
- Android Quick Tile must follow the same `Session.apiBaseUrl` rule.
- Preview build containing this behavior: `0.2.41-preview` / build `2026070501`.

Проверка fallback не должна ограничиваться `/healthz`. Нужно проверять именно рабочие операции:

- auth start/verify path;
- bootstrap;
- catalog;
- config/provisioning.

Проблема текущей схемы: `/healthz` может отвечать, а `bootstrap/config` может падать из-за SQLite/disk/schema/remote provisioning. Тогда клиент выбирает формально живой, но практически бесполезный API.

## Server pool

### Timeweb

- `Friendly Linnet` / `5.129.237.163`: личный/no-touch.
- `37.220.85.211`: NL1 VPN data plane; legacy backend полностью удалён.
- `Friendly Cetus` / `72.56.32.197`: primary Russian control plane,
  site/proxy/monitoring and only billing writer when sales are allowed.
- `GreenVPN NL1 VPN 20260511` / `5.129.216.42`: NL2 VPN data plane и
  единственный dnstt last-resort node.
- `tw-kz1-test-01` / `94.198.221.206`: тестовый KZ, держать вне stable до повторяемого smoke.

### RUVDS

- `ruvds-m9-control-01` / `176.113.81.35`: Russian fallback control-plane/API/download mirror, not a VPN node.
- `ruvds-2584554-ld8` / `88.218.250.86`: London VPN data plane;
  legacy backend удалён, direct `8000` закрыт.

### Serverspace

- API подготовлен, серверов нет.
- Используется как резервный провайдер после пополнения баланса.

### Retired

- Timeweb Frankfurt/Germany удален/не восстанавливать.

## Что считается рабочим smoke

Для backend/API:

- `/healthz` отвечает;
- `/api/v1/catalog/servers` отвечает для stable и preview;
- auth code start возвращает быстрый ответ;
- auth verify сохраняет сессию;
- bootstrap/config работают на primary и fallback.

Для VPN node:

- SSH reachable;
- WireGuard service/interface ready;
- temporary peer create/remove ok;
- client config shape valid;
- real Android full-tunnel test ok;
- real Android social-only test ok;
- Windows config/connect test ok.

Для release:

- Android update manifest отдает APK;
- Windows update manifest отдает EXE;
- legacy endpoint не путает платформы;
- stable и preview не смешаны.
