# Green VPN: строгий жизненный цикл подписки

Дата: 2026-08-28 MSK.

Статус: реализовано, проверено и собрано в точные локальные candidate artifacts;
в production не опубликовано.

## Контракт продукта

1. Backend является единственным источником истины по платному доступу.
2. Каждый платный период имеет точные `accessStartsAt` и `expiresAt` в UTC.
3. Действующий период не заменяется повторной покупкой. Новая покупка продлевает
   доступ от текущего `expiresAt` и заранее показывает точные даты следующего
   периода.
4. Продление действующей подписки требует отдельного подтверждения пользователя.
   Клиент передаёт ожидаемые `revision` и `expiresAt`; сервер отклоняет устаревший
   расчёт.
5. Для одного аккаунта нельзя незаметно создать несколько несовместимых pending
   заказов. Совпадающий заказ переиспользуется, конфликтующий требует завершить
   или отменить предыдущий.
6. Оплаченный старый заказ не перезаписывает права, изменённые после checkout.
   Он остаётся в статусе `paid` для ручной сверки.
7. По достижении `expiresAt` платные права считаются истёкшими немедленно, даже
   если планировщик ещё не успел записать `is_active=0`.
8. Планировщик фиксирует истечение в базе, выключает автопродление и сохранённый
   способ оплаты, удаляет peer устройства со всех известных VPN-узлов и повторяет
   сетевую очистку после временной ошибки.
9. После окончания платного периода публичный пользователь может использовать
   только предусмотренный бесплатный режим. Премиальные режимы и лимиты больше
   не наследуются от истёкшей подписки.
10. Выдача или отзыв подписки администратором требует причины, записывает actor,
    before/after snapshot и не включает автоматические списания.

## Клиент Android и Windows

- Экран тарифа отдельно показывает текущий платный статус, начало и окончание
  периода.
- Активная подписка использует CTA продления, а не повторной покупки текущего
  месяца.
- Перед продлением показываются текущая дата окончания, начало нового периода,
  окончание нового периода и сумма.
- Истёкшая платная подписка показывается как истёкшая, а не как новый trial.
- Смена выбранного тарифа инвалидирует старую quote; кнопка недоступна до получения
  расчёта именно для текущего выбранного плана.
- Автопродление остаётся явным opt-in. Текущий manual NPD production-контур его
  не предлагает и автоматических списаний не выполняет.

## Backend и данные

- `subscriptions`: `access_started_at`, `revision`,
  `peer_revocation_pending`.
- `billing_orders`: неизменяемый `purchase_preview_json` с точным периодом,
  суммой, ожидаемыми revision/expiry и видом операции.
- `subscription_events`: append-only история activation, extension, expiry,
  admin grant/revoke и отмены автопродления.
- Исторические активированные billing orders безопасно восстанавливают события
  и начало платного доступа.
- Межузловое событие expiry получает одинаковый one-way SHA-256 tag по
  нормализованной учётной записи и моменту окончания; email и дата не попадают в
  открытый `event_id`.

## Администрирование

Предпочтительные endpoints:

- `GET /api/v1/admin/users/{user_id}/subscription-history`;
- `POST /api/v1/admin/users/{user_id}/subscription/grant`;
- `POST /api/v1/admin/users/{user_id}/subscription/revoke`;
- `GET /api/v1/admin/subscriptions/expiry-readiness`;
- `POST /api/v1/admin/subscriptions/expiry/run`.

Admin web показывает status/start/end/revision, историю и отдельные действия
выдачи/отзыва. PowerShell helper поддерживает `SubscriptionHistory`,
`GrantSubscription` и `RevokeSubscription`. Legacy `ApplyTariff` требует причину
и принудительно оставляет `autoRenew=false`.

## Планировщик

- `scripts/ops/run_subscription_expiry.py` вызывает защищённый admin endpoint.
- `scripts/ops/install_subscription_expiry_timer.sh` устанавливает отдельный
  systemd timer после `network-online.target` и для переданного имени backend
  service.
- Public и paid-beta backend installers устанавливают timer в своём изолированном
  контуре.
- Один и тот же expiry можно безопасно обработать повторно или на втором узле:
  права не продлеваются, событие не дублируется, незавершённая peer-очистка
  повторяется.

## Проверки до сборки кандидата

- Python compile: passed.
- PowerShell parser: `8/8` изменённых файлов.
- Bash parser: `3/3` изменённых файлов.
- Node syntax: passed.
- Backend lifecycle suite: `160/160` после финальной race-регрессии.
- All backend tests: `234/234`.
- Flutter analyze: no issues.
- Flutter default: `140` passed, `14` intentional skips.
- Flutter public product: `142` passed, `12` intentional skips.
- Release gate после candidate version bump: warnings `0`, errors `0`.
- Repository secret scan с untracked candidate-файлами: passed.

## Точные локальные артефакты

Исходный commit кандидата: `270a7fa8f6989ebe90be32fa1ddde78f51de2843`.
Основная реализация находится в commit
`e7580d33ec080882a9e53fb0c9960735a6be5020`; следующий commit исправляет только
состав Windows-пакета и release gate для обязательного standby probe.

- Android `0.4.11+2026082805`, production-signed:
  `C:\BlueVPN_Builds\public_product_final_candidate_20260828_android_2026082805_windows_4637_v2\GreenVPN_Android_0.4.11_final_candidate_2026082805.apk`;
  size `56274061`; SHA-256
  `26F8D1D38085FFDC2F47777A0EE369938E5EEBB0C9EE8C9C3AF516D4769B6451`.
- Windows `0.4.6+4637`, unsigned ZIP:
  `C:\BlueVPN_Builds\public_product_final_candidate_20260828_android_2026082805_windows_4637_v2\windows\GreenVPN_Windows_0.4.6_final_candidate.zip`;
  size `54278122`; SHA-256
  `E51330F9A3DA8FE882782EC71FFCCA0142AB69ED558EDE6789A14877A32F65AE`.
- Backend `0.9.165-subscription-lifecycle.1`:
  `C:\BlueVPN_Builds\subscription_lifecycle_20260828_backend_v3\public-product-backend-subscription-lifecycle-20260828-r3.tar.gz`;
  size `315136`; SHA-256
  `145FFEA587ADB39CD291EA71A86D96B3A142253D0B77A76B86CAF236524084FC`.

Итоговый client manifest находится рядом с APK. Независимая проверка повторно
сверила размеры и SHA-256 обоих клиентских артефактов. Android проходит APK v2
signature verification и 16 KB native alignment. Windows ZIP содержит
`app/tools/greenvpn_standby_probe.ps1`; release gate завершился с warnings `0`
и errors `0`.

Первый root без суффикса `_v2` отклонён fail-closed: в ZIP отсутствовал standby
probe. Он сохранён как evidence неуспешной упаковки и не является кандидатом.
Повторная сборка выполнялась из чистого commit и завершилась успешно.

## Граница готовности

Этот документ подтверждает source implementation, локальные проверки и точные
Android/Windows/backend candidate artifacts, но не production rollout. До
публикации остаются физическая проверка аккаунта с активной подпиской и аккаунта
без неё, а затем отдельно разрешённый fallback-first/primary-second deploy с
backup и rollback. Реальный платёж, автоматическое списание, установка на
пользовательское устройство и изменение production в этой работе не
выполнялись.
