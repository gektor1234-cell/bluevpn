# Green VPN Fusion: production-кандидат Windows, 2026-08-13

## Статус

Windows-кандидат `0.4.6+4608` технически принят как точный кандидат для
будущего production-продвижения. Он не опубликован, production backend и
публичные manifests не менялись. Android также не менялся.

Публикация остаётся закрыта тремя отдельными решениями владельца:

1. принять интерфейс Fusion;
2. принять риск `NotSigned`/SmartScreen либо предоставить Authenticode;
3. отдельно разрешить stable production promotion.

До получения всех трёх решений `productionPublished=false` и
`deploymentAttempted=false`.

## Точный Windows-артефакт

- версия: `0.4.6+4608`;
- файл:
  `C:\BlueVPN_Builds\fusion_production_promotion_20260813_b4608_windows_v3\clients\GreenVPN_Setup_0.4.6.exe`;
- размер: `55508992` байт;
- SHA-256:
  `DFB7C644F9F500D7680D956F189564C0D4B052605E5159566CABD6D624C89B9B`;
- Authenticode: `NotSigned`;
- package audit: `success=true`, `payloadEntryCount=66`;
- source commit:
  `d318cfed7cf289eabebea0e1ff451be6ee5f4cad`.

Установленный payload:

| Файл | Размер | SHA-256 |
|---|---:|---|
| `greenvpn.exe` | `149504` | `C61D7F340FC1EA93C59179C4B22976583BC2FF349CB3BA1EBB343A8C0A290AB6` |
| `data/app.so` | `7013296` | `11D73B327D2862FABEF78719B3CFD436C6BB4463FE58608CE1A2E1404CEB3F6B` |
| `greenvpn_service.exe` | `110592` | `71497BC559F49CB18A9920CC7D8CDA948AD854DF6E2DFA838D6B30227C2CDADF` |

Машинный package audit:
`C:\BlueVPN_Builds\fusion_production_promotion_20260813_b4608_windows_v3\clients\windows-package-audit.json`.

## Физическая приёмка

Точный установщик проверен одним delayed detached elevated runner с задержкой,
`try/finally` и независимым deadman. Переключения VPN не выполнялись внутри
активного Codex-запроса.

Итоговый отчёт:
`C:\BlueVPN_Builds\fusion_production_windows_smoke_20260813_b4608_v1\windows-standby-tray-autonomous-summary.json`.

Результат `success=true`:

- foreground использовал ровно один кандидат `current_wg0/wireguard_udp`;
- время по клиентскому журналу `18.766` секунды, меньше лимита `30` секунд;
- `probeConfirmed=true`, `privilegedTakeoverConfirmed=true`;
- пять tray lifecycle-циклов сохранили один экземпляр приложения при восьми
  повторных запусках в каждом цикле;
- в каждом цикле подтверждены один успешный `NIM_ADD`, один `NIM_SETVERSION`,
  одна stale-cleanup попытка и один graceful `NIM_DELETE`;
- forced predecessor recovery, финальное отсутствие иконки и нулевое число
  процессов подтверждены;
- все `15` eligible standby-маршрутов получили конечный результат;
- свежий config-bound native-handshake proof подтверждён для
  `gb1-awg2-canary/amneziawg`;
- после искусственного отказа WireGuard приложение использовало заранее
  проверенный AmneziaWG за `16.344` секунды;
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
- standby runtime и standby bypass routes отсутствуют.

Постоянные `GreenVPNService` и `GreenVPNBetaService` являются установленными
локальными контроллерами. Их наличие не означает активный Green-туннель;
фактические управляемые transport services после cleanup отсутствуют.

## Исправленные отказы кандидатов

- `4603`: прямой YouTube `204` ошибочно считался здоровьем VPN после остановки
  managed WireGuard;
- `4604`: поздно завершившийся standby proof мог попасть в recovery order;
- `4605`: localhost HTTP обрабатывался последовательно и блокировал runtime;
- `4606`: foreground занял `30.184` секунды;
- `4607`: продуктовые проверки прошли, но harness сохранял устаревший
  отрицательный cleanup result и затем встретил временную гонку очистки AWG.

Кандидаты `4603`-`4607` отклонены и не должны публиковаться. В `4608` cleanup
имеет ограниченные повторные попытки и после них проверяет отсутствие native
services, процессов, routes и runtime. Fail-closed поведение при постоянной
ошибке закреплено контрактным тестом.

## Границы пакета

Полная promotion-сборка сначала попыталась пересобрать Android, но Gradle JVM
завершилась из-за нехватки памяти на рабочем компьютере. Android-исходники,
артефакты и production при этом не изменились. Текущий каталог `b4608_windows_v3`
является намеренно Windows-only пакетом приёмки.

После получения owner gates финальный promotion-пакет должен быть собран без
изменения принятого Windows-артефакта либо с обязательным повторным exact smoke,
если байты Windows изменятся. Публикация выполняется fallback-first, затем
primary, только с атомарными backup/rollback и последующей проверкой четырёх
публичных тел, обоих backend и полного public-surface probe. Friendly Linnet
`5.129.237.163` исключён из rollout.
