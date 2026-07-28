# Green VPN: продажный контур и реклама

Статус: по прямому решению владельца от 2026-07-22 реклама временно отключена
в production и paid-beta. Реализация сохранена в коде, но серверный gate,
Android Rewarded и закрытый Windows `test_web` выключены на обоих control-plane.

Обновление 2026-07-27:

- production backend `0.9.141-autorenew-optin.1`, Android
  `0.3.14+2026072702` и Windows `0.3.13+2604` не содержат активного
  production placement/block id;
- production и paid-beta на обоих control plane подтверждены с
  `GREENVPN_FREE_AD_GATE_ENABLED=0`; Android/web Rewarded, `test_web` и
  forced-disconnect timer выключены;
- paid-beta вместо рекламы использует бесплатный тариф с выключенным
  enforcement квоты, сохранённым переключателем `3` ГБ и профилем
  `10` Мбит/с; usage продолжает считаться;
- реальный Rewarded-провайдер по критериям Windows WebView2, VPN-разрешения,
  подтверждаемого completion и доступного вывода в РФ не выбран;
- РСЯ 23.07 прислала только промежуточный статус: вопрос о засчитывании
  Windows WebView2-трафика всё ещё разбирают. Это не разрешение интеграции.
  Повторно подавать отклонённую площадку до `18.08.2026 12:55` нельзя;
- при контрольной проверке 27.07 MediaToday и ayeT не дали содержательного
  ответа; в Spam находилось только старое закрытое письмо Monetag;
- повторное включение рекламы возможно только после письменного разрешения
  конкретного провайдера, настоящего placement id, изолированного paid-beta
  smoke и отдельной команды владельца;
- guarded renewal worker существует, но automatic charge execution выключен.
  Missing `autoRenew` теперь fail-safe `false`.

Обновление 2026-07-22:

- production и paid-beta на Timeweb Moscow и RUVDS Moscow работают с
  `GREENVPN_FREE_AD_GATE_ENABLED=0` и пустым списком рекламных платформ;
- Android Rewarded выключен во всех контурах, Windows `test_web` выключен в
  paid-beta, а production Windows по-прежнему не имеет рекламного flow;
- опубликованные APK/EXE не менялись: клиент получает актуальную политику от
  backend перед подключением;
- таймер принудительного отключения остаётся выключенным;
- повторное включение допускается только по новой прямой команде владельца и
  после отдельной beta-проверки.

Обновление 2026-07-19:

- paid-beta backend `0.9.131-freemium.2` работает на Timeweb и RUVDS Moscow;
- paid-beta Android `0.3.9+2026071902` и Windows
  `0.3.9-paid-beta.1902` опубликованы на обоих зеркалах;
- режим «Только для соцсетей» доступен только при активной платной подписке;
  это проверяют и клиент, и endpoint `/api/v1/client/config`;
- существующие Нидерланды и Лондон остаются бесплатными; новые записи каталога
  по умолчанию создаются как premium, а tier можно менять из админки;
- free Android использует реальный Yandex Mobile Ads rewarded unit;
- free Windows в закрытом paid-beta использует только явно включённый
  `test_web`; production не содержит тестовой кнопки и отклоняет такой режим;
- deploy и backend используют одно каноническое имя флага
  `GREENVPN_FREE_AD_TEST_WEB_ENABLED`; прежнее имя принимается только как
  совместимый fallback;
- один зачтённый просмотр даёт одно подключение, таймер принудительного
  отключения выключен;
- Yandex site `api.greenvpn.pro` (id `19615469`) находится на модерации;
  запрос на доступ к desktop Web Rewarded отправлен в поддержку;
- пока Яндекс не выдаст настоящий block id формата `R-A-N-N`, production
  Windows остаётся без рекламного gate и версия `0.3.9` не продвигается в main.

Обновление 2026-05-17:

- backend `0.9.94` добавляет feature flag `GREENVPN_FREE_AD_GATE_ENABLED`;
- добавлены таблицы `ad_challenges` и `free_access_grants`;
- `client/bootstrap` возвращает `adGate`;
- `client/config` блокирует бесплатный connect с `ad_reward_required`, если gate включён и нет свежего grant;
- добавлены endpoint-ы `POST /api/v1/ads/challenges/start`, `GET /api/v1/ads/challenges/{id}`, `POST /api/v1/ads/challenges/{id}/complete`, `GET /api/v1/ads/free-access/me`;
- добавлена тестовая web-страница `/ads/reward/{id}` для закрытой проверки Windows/Android flow без реальной рекламной сети;
- Flutter-клиент для Windows и Android перед connect проходит общий ad-gate и не использует старый локальный config как обход рекламы;
- Android native layer получил `openUrl`, чтобы рекламный web-gate открывался на телефоне.
- live backend обновлён до `0.9.94`; `GREENVPN_FREE_AD_GATE_ENABLED=1` включён только для клиентов с маркером `adgate`, поэтому стабильные `0.2.4-mvp` Windows/Android остаются без рекламного gate.

Обновление 2026-05-22:

- добавлен Flutter plugin `yandex_mobileads: ^8.0.0`;
- Android Manifest получил безопасный meta-data `yandex_mobileads_age_restricted_user=true`;
- Android-клиент умеет показывать Yandex rewarded ad через SDK, но только если сборка сделана с `GREENVPN_YANDEX_REWARDED_ADS_ENABLED=true` и есть `adUnitId`;
- после SDK-события `reward` клиент вызывает backend complete для текущего рекламного challenge, backend выдаёт `free_access_grant`, затем VPN продолжает подключение;
- без включённого SDK-флага или без `adUnitId` остаётся текущий web-gate fallback;
- backend live обновлён до `0.9.95` и отдаёт поле `adGate.androidRewarded` для будущего server-side `adUnitId`;
- Windows-клиент не использует mobile SDK и остаётся на web-gate схеме.

Обновление 2026-05-24:

- Android preview `0.2.7` добавляет системную плитку Green VPN для шторки быстрых настроек Android;
- плитка появляется в списке доступных плиток после установки приложения;
- отключение VPN через плитку разрешено всегда, чтобы пользователь не застрял с включённым туннелем;
- подключение VPN через плитку разрешено только при активной платной подписке;
- бесплатный/Trial-пользователь остаётся в основном сценарии: открыть приложение, посмотреть rewarded-рекламу и включить VPN из приложения;
- это платная convenience-функция бизнес-модели: платный тариф убирает рекламу и даёт быстрый запуск из шторки Android.

## Цель

Сохранить текущую рабочую версию как тестовую для друзей и переноса пользователей с личных WARP-конфигов. Параллельно поднять отдельный продажный сценарий, где:

- пользователь может скачать приложение;
- бесплатный вход работает через зачтённый просмотр рекламы;
- платный тариф убирает рекламу;
- платный тариф открывает плитку быстрых настроек Android для включения VPN из шторки;
- покупка тарифа идёт через YooKassa;
- после успешной оплаты backend активирует подписку;
- автопродление использует сохранённый у YooKassa способ оплаты;
- личный WARP-сервер владельца и существующие WARP-конфиги не трогаются.

## Разделение контуров

Текущий сайт:

- `https://greenvpn.pro/`;
- оставить как есть;
- использовать для мягкого теста и ручной раздачи приложения.

Release-preview сайт:

- локальная папка: `C:\Users\gekto\projects\bluevpn\public_release_preview_site`;
- текущий закрытый online path без покупки домена: `https://greenvpn.pro/release-preview-20260517-private/`;
- короткий красивый path на потом, если понадобится: `https://greenvpn.pro/release-preview/`;
- `robots=noindex,nofollow`;
- можно закрыть basic auth или оставить скрытой ссылкой на первом этапе;
- не должен менять файлы текущего `public_demo_site`.

## Реклама

Android:

- текущий закрытый test-flow использует общий web-gate, чтобы сразу проверить Android вместе с Windows;
- production-этап: заменить test-web кнопку на rewarded ad SDK;
- после callback `reward earned` клиент/страница сообщает backend о зачёте;
- backend выдаёт короткий `free_ad_grant`;
- connect разрешается только при активном платном тарифе или свежем grant.

Windows:

- не закладываться на мобильный рекламный SDK внутри Windows exe;
- использовать web reward gate: приложение открывает защищённую страницу backend в браузере или embedded webview;
- backend создаёт одноразовый challenge для пользователя/устройства;
- рекламная страница показывает rewarded/web ad;
- после зачёта backend помечает challenge как completed;
- клиент polling-ом проверяет grant и запускает VPN.

Общее правило:

- нельзя просто показывать локальный баннер и считать его просмотром;
- засчитывать можно только событие от рекламной платформы/страницы, которое backend может связать с user/device/challenge;
- платные тарифы не проходят ad gate.

## Текущий backend по оплате

Уже есть:

- создание billing order;
- YooKassa redirect payment;
- `save_payment_method` при `autoRenew`;
- webhook/provider sync;
- активация подписки только после подтверждённого платежа;
- хранение признака сохранённого payment method без вывода provider id в публичные ответы;
- readiness для автопродления.

Не хватает до полной продажной версии:

- фактический renewal-worker для автоматических списаний;
- production smoke следующего реального платежа;
- включение strict subscription/ad-gate enforcement только для release-preview канала;
- UI ad-gate перед connect;
- provider-specific rewarded ads.

## MVP ad-gate контракт

Новые backend сущности:

- `ad_challenges`: user, device, platform, status, expires_at, completed_at;
- `free_access_grants`: user, device, source, starts_at, expires_at, max_connects или traffic_limit;
- audit events для start/complete/consume.

Новые endpoint-и:

- `POST /api/v1/ads/challenges/start`;
- `GET /api/v1/ads/challenges/{id}`;
- `POST /api/v1/ads/challenges/{id}/complete`;
- `GET /api/v1/ads/free-access/me`.

Клиентский connect flow:

1. Пользователь нажимает connect.
2. Клиент вызывает bootstrap/config preflight.
3. Если платный тариф активен, connect сразу.
4. Если бесплатный режим и grant отсутствует, открыть рекламу.
5. После зачёта рекламы повторить preflight.
6. Получить config и подключиться.

Feature flags/env:

- `GREENVPN_FREE_AD_GATE_ENABLED=1` — включает gate;
- `GREENVPN_FREE_AD_GATE_PLATFORMS=windows,android` — платформы, на которых gate действует;
- `GREENVPN_FREE_AD_GATE_PROVIDER=test_web` — текущий тестовый provider;
- `GREENVPN_FREE_AD_CHALLENGE_TTL_MINUTES=10` — срок жизни рекламного challenge;
- `GREENVPN_FREE_AD_GRANT_TTL_MINUTES=360` — срок жизни grant;
- `GREENVPN_FREE_AD_GRANT_CONNECTS=1` — сколько connect-разрешений даёт один просмотр.

Yandex rewarded Android:

- build-time `--dart-define=GREENVPN_YANDEX_REWARDED_ADS_ENABLED=true` — включает native rewarded path в Android-сборке;
- build-time `--dart-define=GREENVPN_YANDEX_REWARDED_ADS_DEMO=true` — использует тестовый Yandex block `demo-rewarded-yandex`, только для локальной проверки;
- build-time `--dart-define=GREENVPN_YANDEX_REWARDED_AD_UNIT_ID=<id>` — вшивает production `adUnitId`;
- server env `GREENVPN_YANDEX_REWARDED_ANDROID_ENABLED=1` — разрешает backend отдавать Android rewarded config;
- server env `GREENVPN_YANDEX_REWARDED_ANDROID_AD_UNIT_ID=<id>` — production `adUnitId` для bootstrap/adGate.

Команда для локальной demo-сборки:

```powershell
flutter build apk --release --no-pub `
  --dart-define=GREENVPN_YANDEX_REWARDED_ADS_ENABLED=true `
  --dart-define=GREENVPN_YANDEX_REWARDED_ADS_DEMO=true
```

Команда для production-сборки после получения `adUnitId`:

```powershell
flutter build apk --release --no-pub `
  --dart-define=GREENVPN_YANDEX_REWARDED_ADS_ENABLED=true `
  --dart-define=GREENVPN_YANDEX_REWARDED_AD_UNIT_ID=<YANDEX_AD_UNIT_ID>
```

Важно: на live gate включён только для preview-сборок `0.2.5-adgate`. Стабильные `0.2.4-mvp` Windows/Android не содержат маркер `adgate` и не попадают под это правило.

## Идеи для закрытого теста

- Первым 5-10 людям выдать обычную ссылку и просить писать баги по установке/подключению.
- Вторым кругом дать `release-preview` ссылку и тестировать оплату/рекламу.
- Сделать промокод `FRIENDS` или `START20`, но держать его неактивным до финального решения.
- В админке помечать таких пользователей cohort/source: `warp_friends`, `release_preview`, `paid_test`.
- Не включать автоматическое отключение VPN по таймеру до отдельного теста; сначала только правило “перед подключением нужен просмотр рекламы”.

## Риски

- Для массового Windows-релиза всё ещё нужен code signing, иначе холодная аудитория будет хуже доверять установщику.
- Реклама VPN в публичных каналах РФ требует аккуратной юридической формулировки; не использовать обещания обхода блокировок.
- Rewarded ads на desktop сложнее, чем на Android; web-gate безопаснее и гибче.
- Автоматические списания включать только после чистого payment smoke и ручного просмотра renewal readiness.

## Источники для технических решений

- Yandex Mobile Ads Flutter rewarded ads: `https://ads.yandex.com/helpcenter/ru/dev/flutter/rewarded`
- Google Ad Manager rewarded ads for web: `https://support.google.com/admanager/answer/9116812`
- YooKassa автоплатежи: `https://yookassa.ru/docs/support/payments/extra/autopayment`
- YooKassa платеж сохраненным способом: `https://yookassa.ru/developers/payment-acceptance/scenario-extensions/recurring-payments/pay-with-saved`
