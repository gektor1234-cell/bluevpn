# Green VPN: план выполнения paid beta

Дата фиксации: 2026-07-10.

Этот файл является текущим рабочим порядком. Этапы выполняются строго сверху вниз. Новый этап не начинается, пока предыдущий не проверен. Остановиться можно только если требуется действие или решение владельца, которое нельзя безопасно получить из проекта или инфраструктуры.

## Жесткие ограничения

- Не удалять и не откатывать существующие изменения вслепую.
- Не использовать `git reset --hard` и `git checkout --`.
- Не печатать и не коммитить секреты, токены, пароли и private keys.
- Не блокировать существующий stable Trial при разработке paid beta.
- Все новые тарифы, ограничения, инвайты и платежная логика создаются только в отдельном тестовом beta-контуре. Production stable, основной сайт и действующие production-флаги не менять без отдельного разрешения владельца.
- Не включать рекламу и таймер принудительного отключения VPN.
- Не продавать выделенный IP, гарантированную скорость или сетевой приоритет, пока они реально не применяются на VPN-узлах.
- Не покупать новые VPS до подтвержденного спроса.
- Не запускать публичную рекламу VPN в России без письменного заключения профильного юриста.

## Зафиксированная коммерческая модель beta

- Закрытая когорта: 20 участников.
- Trial: 3 дня.
- Основной период: 30 дней.
- Базовая цена: 299 RUB.
- Первый период по персональному beta-инвайту: 149 RUB.
- Устройства: до 2.
- Реклама: выключена.
- Автопродление: выключено на первом этапе.

## Этапы

1. **Stable freeze** - выполнен 2026-07-10.
   - Локальный checkpoint: `C:\Users\gekto\GreenVPN_Checkpoints\pre_paid_beta_20260710_103722`.
   - Серверные root-only snapshots: `/root/greenvpn-pre-paid-beta-20260710T103821`.
   - Dirty tree разложен на тематические коммиты; рабочее дерево очищено.
   - Android stable воспроизведен байт-в-байт, Windows payload совпал во всех программных файлах.
   - Public manifests и downloads проверены, release gate проходит с 0 ошибками.
   - Восстановительный манифест: `docs/STABLE_FREEZE_2026_07_10_RU.md`.
   - Локальный release tag: `greenvpn-stable-pre-paid-beta-20260710`.
2. **Один beta-тариф** - выполнен 2026-07-10 в изолированном кодовом контуре.
   - Backend fixed-policy: 299 RUB, 30 дней, 2 устройства, без рекламы и автопродления.
   - Beta-клиент не показывает конструктор трафика, скоростей, приложений, устройств и выделенного IP.
   - Цена первого периода по инвайту 149 RUB зафиксирована в policy; персональные инвайты создаются на этапе 5.
   - Policy требует отдельные server flag, release channel и client marker; production default выключен.
   - Backend-тесты покрывают нормализацию, изоляцию stable, заказ, активацию, смену server flag и продление.
3. **Marker/cohort enforcement** - выполнен 2026-07-10 в коде тестового контура.
   - Beta требует точные server flag, release channel, client marker и cohort пользователя.
   - Non-cohort beta-клиент не получает конфиг и не может создать платежный заказ.
   - Beta-cohort не может обойти окончание Trial установкой stable-клиента.
   - Пользователи вне beta-cohort сохраняют stable-доступ и не попадают под beta enforcement.
   - Enrolment идемпотентно выдаёт 3-дневный Trial на 2 устройства и не перезаписывает активную платную подписку.
   - Реклама и session timer принудительно выключены для всего beta-scope на клиенте и backend.
   - Cohort/email/phone mutations получили `users.updated_at`; DB-sync переносит только более новую запись.
   - Cohort и DB-sync покрыты отдельными backend-тестами.
4. **Paid-beta clients** - выполнен и опубликован только в изолированном beta-контуре.
   - Отдельный channel `paid-beta`, финальный Android `0.3.0-paid-beta.5`, build `2026071005`, package `pro.greenvpn.app.beta`.
   - Оба beta-сервера отдают Windows `0.3.0-paid-beta.10`; этот же side-by-side артефакт прошёл полный физический install/reboot/VPN/DNS/uninstall/network-recovery/reinstall gate.
   - Primary/fallback указывают только на изолированный path `/paid-beta-api`.
   - YooKassa UI включён; rewarded ads и session timer выключены compile-time.
   - Android APK подписан и проверен; Windows `.10` изолирован по install/data/service/tunnel/port/process/window, но остаётся без Authenticode-подписи.
   - Stable APK/EXE после сборки сохранили исходные SHA-256.
   - Локальный release manifest: `docs/PAID_BETA_RELEASE_2026_07_10_RU.md`.
5. **Инвайты и воронка** - выполнен локально 2026-07-10, без развёртывания.
   - Код показывается администратору один раз; в БД хранится только HMAC-SHA256 и безопасная подсказка.
   - Claim идемпотентен, учитывает срок/лимит и включает cohort с 3-дневным Trial.
   - Первый заказ по инвайту стоит 149 RUB; повторный запрос возвращает тот же pending order; продление стоит 299 RUB.
   - Активация заказа защищена атомарным статусом `activating` от двойного продления при гонке webhook/polling.
   - Funnel считает app open, claim, bootstrap, order, activation и подтверждённое VPN-подключение по источникам.
   - Инвайты, погашения и funnel events добавлены в межсерверный SQLite state sync.
   - Двадцать backend/DB-sync тестов, Flutter smoke и локальный HTTP-contract проходят.
   - Контракт и ограничения: `docs/PAID_BETA_INVITES_AND_FUNNEL_2026_07_10_RU.md`.
6. **Закрытая beta-страница** - выполнена и опубликована только в тестовом контуре 2026-07-10.
   - Отдельный пакет `paid_beta_site` не пересекается с `public_demo_site` и production `/downloads/`.
   - Главная, условия и дополнение о данных имеют `noindex`; `robots.txt` закрывает весь путь.
   - Указаны только фактические условия beta, персональный инвайт и отдельные beta download links.
   - Desktop/mobile visual QA, локальные ссылки, якоря и ресурсы проверены; release-файлы добавляются только на этапе 7.
   - Манифест страницы: `docs/PAID_BETA_SITE_2026_07_10_RU.md`.
7. **Тесты и smoke** - выполнено в изолированном тестовом контуре 2026-07-10.
   - Backend `0.9.106-paid-beta.4` работает отдельно на `127.0.0.1:8010` у Timeweb и RUVDS; current release `paid-beta-0.3.0-paid-beta.5-2026071005-r6`.
   - Auth, marker/cohort denial, invite claim, quote 149, no-ads, expiry policy, primary/fallback bootstrap/config, update manifests, DB sync и funnel прошли.
   - Реальный beta peer получил `10.10.0.180`, одинаковый config на primary/fallback и был штатно удалён после smoke.
   - Остановка только Timeweb beta дала `502` на primary, selector выбрал RUVDS, production `0.9.105` не прервался; primary затем восстановлен.
   - Четыре beta download по двум HTTPS-маршрутам скачаны полностью и совпали по SHA; production SHA не изменились.
   - Двадцать восемь backend/DB-sync/package тестов и release gate 0/0 проходят.
   - Физический Samsung Android 13 прошёл login, YouTube, реальный Timeweb→RUVDS failover, recents/reopen и disconnect.
   - В social-only добавлены поиск и выбор любого установленного приложения; add/remove Chrome при активном VPN проверен по `tun0` и Android UID allowlist.
   - Серверный манифест: `docs/PAID_BETA_TEST_CONTOUR_2026_07_10_RU.md`.
8. **Ops cleanup** - выполнен в разрешённой test-only границе 2026-07-10.
   - Удалены временные beta seed/staging, 18 env-дублей устранены без изменения effective config.
   - На обоих beta control-plane установлен отдельный probe; primary/fallback API и три VPN endpoint получают свежие observations.
   - NL2 `dnsmasq`, NL1 certbot, London disk, KZ cost/reachability и support backlog диагностированы read-only; production-изменения вынесены владельцу.
   - Аудит: `docs/PAID_BETA_OPS_AUDIT_2026_07_10_RU.md`.
9. **Пакет для первых 20 участников** - технически подготовлен, ждёт owner gate.
   - Добавлен защищённый генератор одноразовых кодов и tracker; коды до real-device/payment/legal smoke намеренно не создавались.
   - Runbook аудитории, приглашений, касаний, метрик и stop-условий: `docs/PAID_BETA_FIRST20_RUNBOOK_2026_07_10_RU.md`.

## Текущая точка остановки

Техническая часть доступная без владельца завершена. Android real-device gate и полный Windows `.10` physical/recovery gate закрыты; `.10` опубликована только в beta-контуре. До генерации 20 кодов владелец должен провести один реальный платёж 149 RUB и подтвердить terms/privacy. Production до этих действий остаётся замороженным.

## Критерии beta

- 20 персональных приглашений.
- 12 установок.
- 8 успешных подключений.
- 5 открытий оплаты.
- 3-5 подтвержденных платежей.
- Не менее 2 платящих пользователей активны через 7 дней.
- Нет массовых HTTP 500, потери сессий и неопознанных платежей.
- Старый stable Trial продолжает работать.

## Правило изменения плана

Менять порядок, цену, модель доступа или публичный контур можно только после явного решения владельца. Технические уточнения внутри этапа допустимы, если они не меняют продуктовую модель и не расширяют риск.
