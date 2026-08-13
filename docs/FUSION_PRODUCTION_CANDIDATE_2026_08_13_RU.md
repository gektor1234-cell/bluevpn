# Green VPN Fusion: production-кандидат Windows, 2026-08-13

## Статус

Windows-кандидат `0.4.6+4610` технически принят как точный кандидат для
будущего production-продвижения. Он не опубликован, production backend и
публичные manifests не менялись. Android также не менялся.

Публикация остаётся закрыта тремя отдельными решениями владельца:

1. принять исправленный интерфейс Fusion и вход по email;
2. принять риск `NotSigned`/SmartScreen либо предоставить Authenticode;
3. отдельно разрешить stable production promotion.

До получения всех трёх решений `productionPublished=false` и
`deploymentAttempted=false`.

## Точный Windows-артефакт

- версия: `0.4.6+4610`;
- файл:
  `C:\BlueVPN_Builds\fusion_production_promotion_20260813_b4610_privacy_auth_failover_v1\clients\GreenVPN_Setup_0.4.6.exe`;
- размер: `55506944` байт;
- SHA-256:
  `FCBA053F674FDFEAA1BA48604BDA455DB39C372490F2E9A6EBD20699E1EEB8CF`;
- Authenticode: `NotSigned`;
- package audit: `success=true`, `payloadEntryCount=66`;
- source commit:
  `333a876f59fd1804c2793369578cfb347bf8aec4`.

Установленный payload:

| Файл | Размер | SHA-256 |
|---|---:|---|
| `greenvpn.exe` | `149504` | `FA76BF89A39476FF0DFAB9FC3B5D8E598D4D852B4D8CF2ECC0FC97D0CB528979` |
| `data/app.so` | `7013296` | `0050E2FA26D6D4D65824FA584FF14B1DB6D8BADB01F3F40A353CC0E2210D382D` |
| `greenvpn_service.exe` | `110592` | `05BDC48E7F86D9D9F517910EC43E58DA0CDE34DF5C024843F8D9458C63BB9658` |

Машинный package audit:
`C:\BlueVPN_Builds\fusion_production_promotion_20260813_b4610_privacy_auth_failover_v1\clients\windows-package-audit.json`.

## Privacy, UI и вход

В exact payload входят исправления commit
`37a823f14e53db8ec3336e7aabe468909a2fde9f`:

- публичный IP больше не запрашивается и не показывается в деталях;
- пользователю не раскрываются маршрут, транспорт и название протокола;
- активное VPN-соединение обозначено отдельной зелёной галочкой;
- окно входа по email открывается сразу, а восстановление истёкшей гостевой
  сессии выполняется внутри уже видимого окна без исчезновения действия;
- widget-тесты закрепляют отсутствие сетевых деталей, connected-индикатор и
  сценарии входа/восстановления.

Реальный ввод email и одноразового кода остаётся частью владельческой
приёмки интерфейса; технические тесты не отправляли OTP и не создавали покупку.

## Физическая приёмка

Точный установщик проверен одним delayed detached elevated runner с задержкой,
`try/finally` и независимым deadman. Переключения VPN не выполнялись внутри
активного Codex-запроса.

Итоговый отчёт:
`C:\BlueVPN_Builds\fusion_production_windows_smoke_20260813_b4610_privacy_auth_failover_v1\windows-standby-tray-autonomous-summary.json`.

Результат `success=true`:

- foreground использовал ровно один кандидат;
- время подключения по клиентскому журналу `18.284` секунды, меньше лимита
  `30` секунд; полное wall-clock время runner `36.904` секунды включает запуск
  приложения и UI automation;
- `probeConfirmed=true`, `privilegedTakeoverConfirmed=true`;
- UI automation использовала единственный допустимый coordinate-click fallback;
- пять tray lifecycle-циклов сохранили один экземпляр приложения при восьми
  повторных запусках в каждом цикле;
- в каждом цикле подтверждены один успешный `NIM_ADD`, один `NIM_SETVERSION`,
  одна stale-cleanup попытка и один graceful `NIM_DELETE`;
- forced predecessor recovery, финальное отсутствие иконки и нулевое число
  процессов подтверждены;
- все `15` eligible standby-маршрутов получили конечный результат;
- свежий config-bound native-handshake proof подтверждён для заранее
  подготовленного резервного маршрута;
- после искусственного отказа активного маршрута приложение использовало
  заранее проверенный резерв за `17.17` секунды;
- транспортные группы не пересекались: `overlapObserved=false`;
- recovered route подтвердил egress, DNS resolution, отсутствие прямой DNS
  утечки и защищённые IPv4/IPv6 routes;
- standby cleanup завершился с `cleanupOk=true`, временных процессов,
  сервисов, listener и bypass routes не осталось.

## Финальное восстановление

После smoke подтверждено:

- Green VPN UI и управляемые Green-транспорты остановлены;
- внешний `AmneziaWGTunnel$device20_full` работает;
- production API возвращает `200`, YouTube probe возвращает `204`;
- routes с metric `42739` отсутствуют;
- failsafe/deadman задачи отсутствуют;
- standby runtime и standby bypass routes отсутствуют;
- установленный `greenvpn.exe`, `app.so` и `greenvpn_service.exe` побайтно
  соответствуют exact promotion-пакету.

Постоянные `GreenVPNService` и `GreenVPNBetaService` являются установленными
локальными контроллерами. Их наличие не означает активный Green-туннель;
фактические управляемые transport services после cleanup отсутствуют.

## История отклонённых и заменённых кандидатов

- `4603`: прямой YouTube `204` ошибочно считался здоровьем VPN после остановки
  managed WireGuard;
- `4604`: поздно завершившийся standby proof мог попасть в recovery order;
- `4605`: localhost HTTP обрабатывался последовательно и блокировал runtime;
- `4606`: foreground занял `30.184` секунды;
- `4607`: продуктовые проверки прошли, но harness сохранял устаревший
  отрицательный cleanup result и затем встретил временную гонку очистки;
- `4608`: прошёл прежнюю техническую приёмку, но заменён после privacy,
  connected-state и email UX исправлений;
- `4609`: первый исправленный UX-кандидат отклонён, потому что расхождение NTFS
  timestamps на `362.1291` мс аннулировало заранее проверенный резерв, а поздний
  proof другого маршрута мог попасть в recovery после первого сбоя.

В `4610` config timestamp получает ограниченный допуск `1000` мс, recovery
фиксирует cutoff на последнем здоровом sample и рассматривает только маршруты,
проверенные до сбоя. Если такого резерва нет, восстановление закрывается
fail-closed. `flutter analyze`, `103` Flutter-теста, `21` targeted-тест и
release gate прошли; warnings/errors release gate равны `0/0`.

Кандидаты `4603`-`4609` не должны публиковаться.

## Границы пакета

Каталог `b4610_privacy_auth_failover_v1` является намеренно Windows-only
пакетом приёмки. Android-исходники, Android-артефакты, backend production,
stable manifests и публичные файлы не изменялись.

После получения owner gates production promotion должен использовать точный
принятый Windows-артефакт. Любое изменение его байтов требует нового exact
physical smoke. Публикация выполняется fallback-first, затем primary, только с
атомарными backup/rollback и последующей проверкой четырёх публичных тел, обоих
backend и полного public-surface probe. Friendly Linnet `5.129.237.163`
исключён из rollout.
