# Green VPN paid-beta: контракт бесплатного тарифа

Дата: 27.07.2026
Область: только изолированный paid-beta
Production: без изменений

## Product Contract

Бесплатный тариф становится доступен участнику paid-beta после завершения
Trial или платного периода.

- 1 активное устройство;
- только бесплатные VPN-локации;
- полный VPN-туннель;
- режим выбранных приложений и сайтов остаётся платной возможностью;
- базовый профиль скорости: 10 Мбит/с, burst до 20 Мбит/с;
- месячный период считается по UTC в формате `YYYY-MM`;
- реклама не требуется и остаётся выключенной;
- платный или активный Trial имеет приоритет над бесплатным тарифом.

При включённой месячной квоте и её исчерпании:

- backend возвращает `free_quota_exhausted`;
- новый bootstrap получает `canConnect=false`;
- новая VPN-конфигурация не выдаётся;
- уже активное соединение принудительно не разрывается;
- следующий месячный период открывается автоматически по серверному UTC;
- переход на оплаченный тариф сразу снимает ограничение.

## Быстрые настройки

Все настройки server-side. Пересборка клиента не требуется.

| Переменная | Значение | Смысл |
|---|---:|---|
| `GREENVPN_FREE_TIER_ENABLED` | `0`/`1` | Полностью выключить или включить бесплатный тариф |
| `GREENVPN_FREE_TIER_QUOTA_ENFORCED` | `0`/`1` | Оставить бесплатный тариф, но снять или включить месячный лимит |
| `GREENVPN_FREE_TIER_MONTHLY_LIMIT_GB` | целое `1..10000` | Быстро изменить месячный лимит, стартовое значение `3` |
| `GREENVPN_FREE_TIER_MAX_DEVICES` | целое `1..5` | Лимит устройств, стартовое значение `1` |
| `GREENVPN_FREE_TIER_SPEED_MBPS` | целое `1..1000` | Базовая скорость; текущее временное значение paid-beta `10` |
| `GREENVPN_FREE_TIER_BURST_MBPS` | целое `1..2000` | Burst, стартовое значение `20` |

Примеры намерений:

```text
Бесплатный тариф 3 ГБ:
GREENVPN_FREE_TIER_ENABLED=1
GREENVPN_FREE_TIER_QUOTA_ENFORCED=1
GREENVPN_FREE_TIER_MONTHLY_LIMIT_GB=3

Временно убрать лимит трафика:
GREENVPN_FREE_TIER_ENABLED=1
GREENVPN_FREE_TIER_QUOTA_ENFORCED=0
GREENVPN_FREE_TIER_SPEED_MBPS=10

Полностью вернуть прежний paid-beta paywall:
GREENVPN_FREE_TIER_ENABLED=0
```

Безопасная команда владельца:

```bash
# Предпросмотр: 3 ГБ в месяц.
bash scripts/server/configure_paid_beta_free_tier.sh \
  --enabled 1 --quota-enforced 1 --monthly-limit-gb 3

# Применить безлимитный бесплатный режим с сохранением учёта трафика.
sudo bash scripts/server/configure_paid_beta_free_tier.sh \
  --enabled 1 --quota-enforced 0 --speed-mbps 10 --apply

# Полностью вернуть прежний paid-beta paywall.
sudo bash scripts/server/configure_paid_beta_free_tier.sh \
  --enabled 0 --apply
```

Команду запускают отдельно на каждом paid-beta control plane. Она не умеет
выбирать production-контур, сохраняет root-only backup и печатает готовую
rollback-команду. Последующие paid-beta deploy сохраняют выбранный владельцем
лимит и не сбрасывают его автоматически к `3`.

## Учёт реального трафика

Квоту нельзя включать в smoke, пока каждый VPN-узел, который обслуживает
paid-beta peer, не отправляет per-peer WireGuard counters в paid-beta API.
Reporter только читает публичные ключи, handshake и byte counters; интерфейс,
маршруты и peer-конфигурацию он не меняет.

Предпросмотр отдельного paid-beta timer:

```bash
bash scripts/server/install_vpn_capacity_reporter_systemd.sh \
  --unit-name greenvpn-paid-beta-vpn-usage-report \
  --script-path /opt/greenvpn-paid-beta-node/report_vpn_capacity.sh \
  --token-file /etc/greenvpn-monitoring/paid-beta-admin-token \
  --api-base https://api.greenvpn.pro/paid-beta-api \
  --server-id current_wg0 \
  --report-peer-traffic \
  --interval-seconds 60
```

Первый отчёт создаёт baseline и не начисляет старые байты. Только следующий
отчёт добавляет delta. Перед включением квоты обязательны два успешных отчёта,
ненулевая контролируемая delta и появление этой delta в
`/api/v1/subscription/me`.

## Текущее проверенное состояние, 2026-07-27

- На Timeweb Moscow и RUVDS Moscow paid-beta backend работает как
  `0.9.141-autorenew-optin.1`.
- В env-файле и реальном процессе обоих сервисов подтверждены:
  `FREE_TIER_ENABLED=1`, `QUOTA_ENFORCED=0`,
  `MONTHLY_LIMIT_GB=3`, `MAX_DEVICES=1`, `SPEED_MBPS=10`.
- Лимит `3` ГБ сохранён как быстрый переключатель, но сейчас не применяется.
  Его можно включить server-side без пересборки клиента. Burst остаётся
  `20` Мбит/с по серверному default.
- Отдельный usage reporter установлен на London `88.218.250.86`, NL1
  `37.220.85.211` и NL2 `5.129.216.42`. На всех трёх узлах timer активен,
  последний service result `success`; reporter не меняет интерфейсы, маршруты
  или peer-конфигурацию.
- В обоих синхронизированных paid-beta DB одинаково `21` запись usage и
  одинаковые суммы `rx=17136`, `tx=38932`. Ручной контрольный sync RUVDS
  завершился с `Result=success`.
- Физический Android tunnel smoke прошёл реальный трафик и показал
  `30.176` Мбит/с download, то есть доступность не ниже требуемых
  `10` Мбит/с подтверждена. Это не доказывает точность Linux shaping:
  backend хранит профиль тарифа, но сам не применяет `tc`.
- Рекламный master gate, Android Rewarded, web Rewarded, `test_web` и таймер
  принудительного отключения остаются выключены.
- На обоих control plane backend, sync, probes и retention завершаются без
  ошибок; failed units нет. Корневые диски заняты на `54%` и `71%`.
- Production free-tier env остаётся выключенным. Production backend и Android
  обновлялись отдельно для guest-first/auto-renew opt-in и не получают
  paid-beta free entitlement.
- Фактическое исчерпание квоты и fail-closed повторный bootstrap намеренно не
  запускались, потому что владелец попросил оставить лимит снятым. До
  `QUOTA_ENFORCED=1` это не release-блокер.

## Paid-beta smoke

1. Готово: одинаковый backend bundle и одинаковые free-tier env применены на
   обоих paid-beta control plane.
2. Готово: отдельные reporters установлены на всех трёх обслуживающих
   VPN-узлах; baseline и ненулевая delta дошли в обе DB.
3. Готово: free tier включён, лимит `3` сохранён, enforcement снят,
   rollback-команды создаются конфигуратором.
4. Готово на уровне backend/client tests: free plan, одно устройство,
   free-локации, full tunnel и отсутствие рекламы. Полный физический
   quota-exhaustion сценарий не запускался.
5. Готово: реальный трафик синхронно учтён обоими control plane.
6. Отложено осознанно: исчерпание и `free_quota_exhausted` проверять только
   перед решением владельца включить месячную квоту.
7. Текущий режим: `--quota-enforced 0`; reconnect и учёт usage работают.
   Не возвращать enforcement к `1` без отдельной команды владельца.
8. Rollback-механизм и root-only backup подготовлены. Разрушительный
   физический rollback действующего контура без причины не выполнять.

## Границы безопасности

- Функция применяется только к пользователям когорты paid-beta.
- Production-клиент и production backend не получают free entitlement.
- Рекламные флаги не изменяются.
- Нет таймера отключения и фонового принудительного disconnect.
- Traffic usage продолжает считаться и при снятом лимите.
- Изменение env требует рестарта только paid-beta backend.
- Перед изменением env создаётся root-only backup.

## Acceptance Criteria

1. Активный Trial и оплаченный тариф работают как раньше.
2. Истёкший paid-beta получает free entitlement при включённом флаге.
3. Free entitlement ограничен одним устройством и бесплатными локациями.
4. При лимите `3` API и клиенты показывают использовано и осталось.
5. При `QUOTA_ENFORCED=0` usage показывается, но подключение не блокируется.
6. При исчерпанной квоте bootstrap и config fail closed.
7. Обычный reconnect не выдаёт новую конфигурацию сверх квоты.
8. При `FREE_TIER_ENABLED=0` возвращается прежний `subscription_inactive`.
9. Android и Windows используют один серверный контракт.
10. Production и рекламные настройки остаются без изменений.
