# Green VPN: ops-аудит перед закрытой paid beta

Дата: 2026-07-10.

## Граница изменений

- Изменения применялись только к изолированному paid beta-контуру.
- Production API `:8000`, production DB, основной сайт, stable downloads, VPN peers и production-флаги не менялись.
- Production-серверы и VPN-ноды проверялись read-only. Любое удаление или перезапуск в production вынесены в отдельное решение владельца.

## Что исправлено в test-only контуре

- На Timeweb Moscow и RUVDS Moscow удалены временные копии `paid-beta.seed.env`. Перед удалением шесть секретных параметров сверены с действующим root-only env без вывода значений.
- `/etc/bluevpn/paid-beta.env` на обоих узлах приведён с 126 назначений и 18 дублей к 108 уникальным ключам. Effective fingerprint до и после совпал.
- Backups до нормализации env:
  - Timeweb: `/root/greenvpn-paid-beta-backups/20260710T103801Z-env-dedupe`;
  - RUVDS: `/root/greenvpn-paid-beta-backups/20260710T103751Z-env-dedupe`.
- После проверки current/site symlink и SHA-256 r2 удалён только временный `/root/greenvpn-paid-beta-stage`: освобождено по 237 МБ на каждом control-plane. Установленные releases, static site, DB и backups сохранены.
- В beta-инсталлятор добавлены атомарная env-дедупликация и опциональный `--remove-seed-env`. Удаление разрешено только для root-owned файла в beta staging или `/run`, live env удалить невозможно.
- На обоих узлах установлен отдельный `greenvpn-paid-beta-service-probe.timer` с интервалом 300 секунд. Он читает существующий root-only beta admin token, пишет только в beta API и не заменяет production probe.
- Probe backups:
  - Timeweb: `/root/greenvpn-paid-beta-backups/20260710T104147Z-timeweb-paid-beta-probe`;
  - RUVDS: `/root/greenvpn-paid-beta-backups/20260710T104206Z-ruvds-paid-beta-probe`.
- В обе beta-БД добавлена отдельная цель `green_api_fallback_1_healthz` для RUVDS fallback API. Она синхронизировалась штатным beta DB sync.
- После двух probe-циклов на каждом узле есть по 21 service observations, 6 server-health observations и 21 route observations. Все три выдаваемых VPN endpoint имеют статус `healthy` с обоих российских probe.
- Timeweb видит 11/11 service targets зелёными. RUVDS видит оба beta API зелёными, а недоступность части YouTube/Instagram из российской сети фиксирует отдельно и не смешивает с состоянием VPN endpoint.
- После каждой финальной операции local health подтвердил beta `0.9.106-paid-beta.4` на `:8010` и production `0.9.105` на `:8000`.
- На обоих control-plane создан root-only technical-ready snapshot `/root/greenvpn-paid-beta-technical-ready-20260710T110614Z`: env, admin token, sync/probe units, Nginx snippets, probe, manifests и согласованная SQLite backup. Обе backup DB проходят quick check и содержат 0 users/0 invites.

## Control-plane production: read-only результат

### Timeweb Moscow `72.56.32.197`

- Диск: 38% занят; failed systemd units нет.
- Production и beta backend активны; production sync каждые 30 секунд, beta sync каждые 10 секунд.
- Обе БД проходят `PRAGMA quick_check`.
- Production monitoring свежий; service/server observations обновляются каждые пять минут.
- Production DB больше fallback DB из-за локальной monitoring telemetry. Эти шумные таблицы специально не синхронизируются.

### RUVDS Moscow `176.113.81.35`

- Диск: 29% занят; failed systemd units нет.
- Production и beta backend, SMTP relay и оба sync timer активны.
- Обе БД проходят `PRAGMA quick_check`; последние sync summary имеют 0 conflicts и 0 errors.
- Старая дата production telemetry на fallback не означает падение API: telemetry намеренно не копируется из primary. Теперь beta имеет собственный локальный probe на каждом control-plane.

## VPN-ноды: read-only результат

### Netherlands #1 `37.220.85.211`

- `wg0` активен, диск занят на 47%, `dnsmasq` работает.
- `certbot.service` падает: сертификат `api.greenvpn.pro` действителен до 2026-07-29, но HTTP-01 уходит на текущий DNS `72.56.32.197`, а не на эту VPN-ноду, и получает 404.
- Это не ломает VPN UDP endpoint, но оставлять бесконечные renew failures нельзя. Рекомендация: после подтверждения, что legacy API на VPN-ноде не нужен, убрать legacy nginx/certbot; иначе выделить отдельный hostname или DNS-01.

### Netherlands #2 `5.129.216.42`

- `wg0` активен, диск занят на 7%, capacity reporter работает.
- `dnsmasq` не поднимается после reboot, потому что systemd запускает его до появления адреса `10.10.0.1` на `wg0`.
- Клиентские config сейчас используют `1.1.1.1, 8.8.8.8`, поэтому отказ этого лишнего local DNS не ломает текущий VPN.
- Рекомендация: либо удалить/disable неиспользуемый сервис, либо добавить корректный `After/Requires=wg-quick@wg0.service` и повторный старт. Production не менялся.

### London `88.218.250.86`

- `wg0` активен, failed units нет, но диск занят на 86%; свободно около 2.7 ГБ.
- Причина: около 7.4 ГБ старых аварийных DB backups и ещё около 4.3 ГБ промежуточных repair/schema-rebuild каталогов от 2-5 июля.
- Текущая DB мала, проходит quick check; большая часть ошибок журнала за сутки является внешним SSH scan noise.
- Рекомендация: оставить pre-paid-beta snapshot, текущую проверенную DB и один диагностический pre-repair набор, остальные подтверждённые дубли удалить. Это production-очистка и требует отдельного разрешения.

### Kazakhstan test `94.198.221.206`

- Timeweb server `8360589`, preset `2937`, 2 CPU / 2 ГБ / 40 ГБ, стоимость 611 RUB/месяц.
- Сервер включён у провайдера, но пять SSH-попыток с каждого российского control-plane завершаются timeout.
- Узел скрыт, не входит в stable/preview, клиентам не выдаётся и в beta не нужен.
- Рекомендация: удалить VPS у провайдера и затем убрать только его скрытые env/key/catalog записи. Удаление VPS необратимо и оставлено владельцу.

## Production backlog

- Support reports: 9 записей, 2 пользователя, 3 уникальных summary, все `new`, без комментариев. Восемь относятся к старым сборкам владельца/тестов; одна запись пользователя `34` требует ручной проверки перед закрытием. Автоматически статусы не менялись.
- Email outbox: 111 `sent`, 34 исторических `failed`; последние failures были 2026-07-05, последнее успешное письмо 2026-07-09. Текущая доставка работает, старые записи не удалялись.
- Production DB sync сейчас успешен на обоих control-plane: текущие result/exit status равны success/0, conflicts/errors равны 0.

## Решения владельца

1. Разрешить удаление недоступного KZ test VPS за 611 RUB/месяц.
2. Разрешить адресную очистку старых London recovery artifacts, не трогая stable snapshots.
3. Выбрать судьбу legacy nginx/certbot на NL1 и неиспользуемого `dnsmasq` на NL2.
4. После real-device beta smoke решить, закрывать ли восемь старых support reports как исправленные; запись пользователя `34` проверить отдельно.

До этих решений production остаётся без изменений.

## Финальная owner-gate ревизия

- На Timeweb и RUVDS current переключён на `paid-beta-0.3.0-paid-beta.5-2026071005-r5`.
- Installer теперь обновляет release metadata в root-only env при каждом deploy. Timeweb update API выдаёт primary download URL, RUVDS - независимый fallback URL.
- Android `.5` имеет отдельный package `pro.greenvpn.app.beta`, custom app picker и исправленный active reconfigure.
- Физический Samsung подтвердил, что Chrome входит в VPN UID allowlist только при выборе; MAX и другие невыбранные приложения остаются на прямом маршруте.
- Stateful smoke полностью прошёл. Старые smoke users/devices/invites удалены на обоих узлах при остановленных sync timers; после очистки timers снова `active`.
- Финальное состояние каждой beta DB: 1 owner user/token/subscription/device/invite/redemption, 0 billing orders, 0 smoke users/devices/invites; `PRAGMA quick_check=ok`.
- Final deploy backups:
  - Timeweb: `/root/greenvpn-paid-beta-backups/20260710T125718Z-timeweb-paid-beta-0.3.0-paid-beta.5-2026071005-r5`;
  - RUVDS: `/root/greenvpn-paid-beta-backups/20260710T125730Z-ruvds-paid-beta-0.3.0-paid-beta.5-2026071005-r5`.
- SQLite sync не распространяет delete tombstones. Для operational cleanup тестовых/удалённых сущностей оба узла очищаются одновременно при paused sync; для first20 сохраняется primary-normal/fallback-only.
