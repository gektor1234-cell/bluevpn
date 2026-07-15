# Полная диагностика Android transport cascade, 15.07.2026

## Область проверки

Проверка выполнена только в тестовом контуре Green VPN:

- ветка `green-vpn-transport-canary-20260711`;
- Android-пакет `pro.greenvpn.app.transportpreview`;
- физический Samsung SM-A530F, Android 9, arm64;
- multiprotocol canary NL2 `5.129.216.42`;
- стабильное приложение, публичный каталог, production-флаги и основной сайт не изменялись.

Цель проверки: подтвердить работу каждого из шести реализованных транспортов отдельно, их последовательный запуск в одном процессе использования, автоматическое восстановление после потери движка или маршрута и независимость восстановления от открытого окна приложения.

## Реализованный порядок

Кандидаты берутся из актуального серверного каталога. Недоступные, отключённые, неподготовленные для выдачи конфигурации и неподдерживаемые клиентом варианты отбрасываются. Оставшиеся кандидаты сортируются в следующем порядке:

1. AmneziaWG;
2. Hysteria2;
3. VLESS REALITY/XHTTP;
4. Naive HTTPS;
5. dnstt;
6. WireGuard UDP.

Внутри одного типа учитываются server health, latency и стабильный server ID. Маршрут после ошибки получает cooldown: 60 секунд, 3 минуты, 10 минут, затем 30 минут при следующих ошибках. Маршруты в cooldown уходят в конец списка. После успешной проверки cooldown маршрута очищается.

После запуска транспорта выполняется независимая проверка реального маршрута. Для короткой гонки старта предусмотрено до трёх попыток через 750, 900 и 1400 мс. Непрошедший проверку транспорт полностью отключается до запуска следующего кандидата. Одновременно активным допускается только один транспорт.

Foreground supervisor проверяет наличие движка каждые 3 секунды и реальный маршрут каждые 20 секунд. Пропажа движка вызывает немедленное восстановление. Две последовательные ошибки route probe переводят состояние `monitoring -> degraded -> recovering`. Если восстановить связь не удалось, повторные попытки выполняются через 3, 10, 30 и 60 секунд.

## Изоляция процессов

Hysteria2, VLESS, Naive HTTPS и dnstt работают в отдельных Android-процессах. Это устранило обнаруженное при последовательном тесте загрязнение process-global состояния HEV/tun2socks между разными транспортами.

Для каждого процесса добавлены собственное сохранённое состояние, startup grace и явная межпроцессная команда `DISCONNECT`. Обычный `stopService()` на Android 9 не гарантировал корректную остановку удалённого VpnService; теперь остановка проходит через сам сервис и подтверждается отсутствием активного туннеля.

## Физическая матрица подключения

Каждый транспорт выбран через реальный Flutter UI. Проверка выполнялась отдельным probe-приложением, то есть результат не основывался на внутреннем статусе Green VPN.

| Транспорт | Активный протокол | Внешний IP | Production API | Paid-beta primary/fallback | YouTube | Результат |
|---|---|---:|---:|---:|---:|---|
| AmneziaWG | `amneziawg` | `5.129.216.42` | 200 | 200 / 200 | 204 | PASS |
| Hysteria2 | `hysteria2` | `5.129.216.42` | 200 | 200 / 200 | 204 | PASS |
| VLESS REALITY/XHTTP | `vless_reality` | `5.129.216.42` | 200 | 200 / 200 | 204 | PASS |
| Naive HTTPS | `naive_https` | `5.129.216.42` | 200 | 200 / 200 | 204 | PASS |
| dnstt | `dnstt` | `5.129.216.42` | 200 | 200 / 200 | 204 | PASS |
| WireGuard UDP | `wireguard_udp` | `37.220.85.211` | 200 | 200 / 200 | 204 | PASS |

После каждого этапа подтверждены отключение транспорта и пустой список активных протоколов. После всей матрицы восстановлен режим `Auto`.

Основной отчёт: `C:\Users\gekto\GreenVPN_Checkpoints\android_flutter_all_six_transports_sm_a530f_r48_20260715.json`.

## Автоматическое переключение

Во всех шести тестах окно Green VPN было удалено из списка последних приложений до отказа. Supervisor продолжил работать как foreground service и автоматически выбрал следующий пригодный маршрут.

| Исходный транспорт | Замена | Время восстановления | API | YouTube | Результат |
|---|---|---:|---:|---:|---|
| AmneziaWG | Hysteria2 | 9,946 с | 200 | 204 | PASS |
| Hysteria2 | AmneziaWG | 10,568 с | 200 | 204 | PASS |
| VLESS REALITY/XHTTP | AmneziaWG | 8,862 с | 200 | 204 | PASS |
| Naive HTTPS | AmneziaWG | 14,139 с | 200 | 204 | PASS |
| dnstt | AmneziaWG | 10,410 с | 200 | 204 | PASS |
| WireGuard UDP | AmneziaWG | 9,054 с | 200 | 204 | PASS |

Дополнительно проверен сложный отказ `живой VLESS engine + мёртвый TUN`. Route probe дважды обнаружил отсутствие рабочего маршрута, supervisor прошёл состояния `monitoring -> degraded -> recovering` и переключился на AmneziaWG за 82,458 с. Внешний IP, production API, оба fallback API и YouTube после восстановления прошли проверку.

Отчёт: `C:\Users\gekto\GreenVPN_Checkpoints\android_flutter_vless_black_route_failover_task_removed_sm_a530f_r48_20260715.json`.

## Нативные watchdog и Quick Tile

Отдельно физически завершались дочерние процессы `hysteria`, `xray`, `naive` и `dnstt-client`. Для каждого транспорта подтверждены fail-closed очистка, watchdog, повторное подключение и отсутствие plaintext runtime profile после остановки. Все четыре теста прошли.

Quick Tile прошёл строгую цепочку с принудительным cooldown предыдущего маршрута:

`AmneziaWG -> Hysteria2 -> VLESS REALITY/XHTTP -> Naive HTTPS -> dnstt -> WireGuard UDP`.

На каждом шаге подтверждены ожидаемый протокол, внешний IP, production API, оба fallback API и YouTube. После проверки первый маршрут восстановлен, затем все туннели отключены.

Отчёт: `C:\Users\gekto\GreenVPN_Checkpoints\android_quick_tile_cascade_physical_sm_a530f_r48_20260715.json`.

## Состояние NL2

После клиентских тестов выполнена read-only проверка NL2. Активны `wg-quick@wg0` и все canary units: AmneziaWG, Hysteria2, VLESS, Naive HTTPS, dnstt server, dnstt SOCKS и DNS frontend. У всех `NRestarts=0`, `ExecMainStatus=0`; failed units отсутствуют. Корневой диск занят на 11%, load average около нуля, ожидаемые TCP/UDP listener'ы присутствуют. Серверных изменений не потребовалось.

## Сборка и проверки

- APK: `C:\BlueVPN_Builds\android_transport_preview_20260715_api24_r48\GreenVPN_Android_six_stage_api24_preview_0.2.46_2026071428_debug.apk`;
- versionCode `2026071428`, versionName `0.2.46`, minSdk 24;
- SHA-256 `BD4F696139A37C44489297565B84857F9B8F011C7D1E62CE05607420A5CF5137`;
- Flutter analyze: PASS;
- Flutter tests: 12/12 PASS;
- `:app:testDebugUnitTest`: PASS, 98 Gradle tasks;
- APK structure, preview markers, ABI and v2 signature: PASS;
- transport contract probe: 10/10 PASS.
- BlueVPN release gate: PASS, 0 warnings, 0 errors.

Полный root Gradle test дополнительно запускает upstream-тесты `shared_preferences_android`; 12 DataStore-тестов этого плагина падают на Windows test host в `FileStorage.kt:121`. Собственные app-тесты проходят, APK этим не затронут.

## Итог и границы результата

Технический gate тестового Android preview на этом устройстве и текущей сети: **PASS**. Проверены все шесть реально реализованных транспортов по отдельности, их последовательная работа, автоматический failover, потеря движка, потеря TUN при живом движке, работа без открытого окна приложения, Quick Tile и чистая остановка.

Это не является доказательством обхода абсолютно любого будущего DPI или блокировки: такой конечной матрицы не существует. Физически проверены один Samsung с Android 9, текущая сеть пользователя и один multiprotocol canary NL2. Перед переносом в stable нужны release-сборка без debug-команд, тест минимум на современных Android 12-15 и управляемый canary rollout. До этого публичный stable должен оставаться без изменений.

Финальное состояние телефона после диагностики: `activeProtocols=[]`, активных сервисов и дочерних transport engine нет.

## Дополнение: финальная продуктовая оболочка

После transport-диагностики собран отдельный публично выглядящий кандидат без
beta/preview-интерфейса. Финальная пересборка от 16.07.2026:

- APK:
  `C:\BlueVPN_Builds\public_product_final_candidate_20260716\GreenVPN_Android_0.3.0_final_candidate_2026071601_debug.apk`;
- package `pro.greenvpn.app.finalcandidate`, versionName `0.3.0`, versionCode
  `2026071601`;
- SHA-256
  `59123FF5205BADD125C514302F07949952527ECEE507392543F90E264B5C3B21`;
- Hysteria2 и dnstt APK verifiers: PASS;
- `flutter analyze`: PASS; Flutter tests: 27/27 PASS;
- физический Samsung Android 9: login/session/main/picker PASS;
- Android 16/API 36 emulator: чистый login, main и picker PASS.

В picker подтверждены только `Авто` и одна строка `Нидерланды`. Обе строки
однотипны и всегда показывают число: при первой проверке `16 мс`, при повторном
обновлении `143 мс`; если измерения нет, политика отображения выдаёт `0 мс`.
Выбор `Нидерланды` сохранился на главной странице, затем состояние было
возвращено на `Авто`. Физические NL1/NL2 routes и пять способов обхода не
размножают пользовательский список. `Англия` отсутствует закономерно: London
не оплачен у провайдера и не опубликован. В проверенных UI-деревьях нет
`Beta`, `WireGuard`, `RUVDS`, `TimeWeb` и других внутренних marker'ов.

Визуальное доказательство финального picker:
`C:\BlueVPN_Builds\public_product_final_candidate_20260716\evidence\android9-server-picker.png`.

Проверка API 36 закрывает современную совместимость интерфейса и запуска, но не
заменяет физический data-plane proof: полный транспортный каскад по-прежнему
доказан на Samsung Android 9. После последней проверки приложение остановлено,
активного VPN agent на телефоне нет.
