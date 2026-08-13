# Green VPN Fusion Paid-Beta, 2026-08-11

## Итог

Изолированный контур Fusion paid-beta обновлен на обоих control-plane и прошел
физическую приемку на Android и Windows. Stable production не изменялся.
Реклама, продажи, возвраты, автосписания и принудительный таймер отключения
остались выключены.

| Слой | Состояние |
|---|---|
| Production backend | `0.9.153-update-channel-alias.4`, без изменений |
| Paid-beta backend | `0.9.154-fusion-actions.1` на Timeweb и RUVDS |
| Production Android | `0.3.19+2026072914`, без изменений |
| Production Windows | `0.3.26+3105`, без изменений |
| Paid-beta Android | `0.4.6-paid-beta.1+2026081106` |
| Paid-beta Windows | `0.4.6-paid-beta.2+4602`, `NotSigned` |

## Что вошло

- Fusion-интерфейс с guest-first запуском, автоматическими значениями по
  умолчанию и скрытием второстепенных действий до момента, когда они нужны.
- Быстрые действия подключения: пауза, смена маршрута, диагностика и детали.
- Поиск, избранное и недавние локации.
- Единый режим выбора приложений и сайтов без лишнего деления на типы.
- Управляемые paid-beta feature flags и сетевой информационный контракт.
- Android runtime failover и восстановление фактически активного маршрута после
  пересоздания Activity или процесса.
- Windows single-instance/tray/close-to-tray поведение и Fusion UI-контракт.

Критическая Android-регрессия исправлена: после смены маршрута с Netherlands на
London и последующего пересоздания Activity интерфейс больше не возвращается к
`Автовыбору`. Источник истины берется из Android runtime, затем из текущего
состояния и только после этого из свежего кэша успешного маршрута.

Физический smoke `0.4.5` дополнительно выявил разрыв слова `Диагностика` в
компактной Android-кнопке. Кнопки быстрых действий переведены на ограниченную
однострочную компоновку с безопасным уменьшением текста. Исправление закреплено
в source anchor `26a8cf20e0abb9265171ac800f56e751428ed5b7` и выпущено только
как новая неизменяемая версия `0.4.6`; байты `0.4.5` повторно не публиковались.

## Точные артефакты

Android:

- файл: `GreenVPN_Android_0.4.6-paid-beta.1_2026081106.apk`;
- размер: `56340949` байт;
- SHA-256: `F2FF98B569C574910CEB4ED7BA18EBC33FD54013A1DD15DE808DEC69986F883D`;
- package: `pro.greenvpn.app.beta`, label: `Green VPN Beta`;
- подпись и совместимость с 16 KB pages подтверждены.

Windows:

- файл: `GreenVPN_Beta_Setup_0.4.6-paid-beta.2.exe`;
- размер: `55497728` байт;
- SHA-256: `B882DB6EEF672C21786608888431126FAFC997EC6D7C5CEADB6CA16DD0AEC4B3`;
- установленный payload: `0.4.6+4602`, SHA-256
  `200838477BCBA22C7AB2CC29A716B56D927249197754C0DC3035E61CC2549F80`;
- package audit: `success=true`;
- Authenticode: `NotSigned`, это известное ограничение paid-beta.

Локальный корень доказательств:
`C:\BlueVPN_Builds\paid_beta_20260813_fusion_acl_fix_v1_0.4.6`.

## Развертывание и rollback

Paid-beta backend установлен атомарно с резервными копиями:

- Timeweb:
  `/root/greenvpn-paid-beta-backend-backups/20260811T045217Z-paid-beta-backend-fusion-actions-20260811-r1`;
- RUVDS:
  `/root/greenvpn-paid-beta-backend-backups/20260811T045123Z-paid-beta-backend-fusion-actions-20260811-r1`.

Paid-beta клиенты опубликованы fallback-first с резервными копиями:

- Timeweb:
  `/root/greenvpn-paid-beta-client-release-backups/20260813T060548Z-timeweb-0.4.6-paid-beta.1-0.4.6-paid-beta.2`;
- RUVDS:
  `/root/greenvpn-paid-beta-client-release-backups/20260813T060415Z-ruvds-0.4.6-paid-beta.1-0.4.6-paid-beta.2`.

Обе публикации подтвердили `production_changed=false`.

## Автоматические проверки

- `flutter analyze`: без замечаний.
- Полный Flutter build-набор: `94 passed`, `11 skipped` по условным контурам.
- Отдельный Fusion build-набор: `9/9`.
- Android app-scoped JVM unit-тесты: `17/17` без failures и errors.
- Backend: `181 passed`; дополнительные parametrized subtests также прошли.
- Release gate: `0` предупреждений, `0` ошибок.
- Условный Android transport-probe собран отдельно; probe привязан к
  фактически активной Android-сети, а не к неявному системному default.
- Строгая публичная проверка: `12/12`, включая `8/8` manifests/тел и `4/4`
  backend health/версий на primary и fallback.
- Public-surface probe: `31/31`.
- Fail-closed audit production и paid-beta на обоих узлах: все коммерческие,
  рекламные, timer, quota и rate-limit gates выключены; значения секретов в
  отчет не попали.
- Paid-beta service и DB sync timer активны на обоих узлах, обе БД прошли
  `PRAGMA quick_check`, failed systemd units отсутствуют.
- Production Android и Windows на обоих узлах остались побайтно прежними.

## Физический Android smoke

На общем Android-телефоне установлен APK из раздела выше. Извлеченный после
установки `base.apk` совпал с кандидатом по размеру и SHA-256.

Последовательность проверки:

1. Публичный APK скачан с primary и установлен поверх предыдущей beta; его
   `base.apk` совпал с опубликованным кандидатом по размеру и SHA-256.
2. Подключение через Netherlands заняло `5.951` секунды; VPN transport активен.
3. Фоновая подготовка recovery стала доступна через `2.865` секунды.
4. Смена маршрута Netherlands -> London заняла не более `8.090` секунды.
5. Принудительное пересоздание Activity сохранило защиту и London без ложного
   возврата к `Автовыбору`.
6. Пауза на пять минут отключила transport за `4.094` секунды; ручное
   возобновление вернуло защиту за `8.979` секунды и отменило отложенный запуск.
7. Реальный YouTube data-plane продвинул позицию с `10` до `52` секунд при
   активном Green VPN.
8. Возврат из YouTube показал защищенное состояние. Финальное отключение заняло
   `4.297` секунды; VPN service, runtime failover и scheduled resume отсутствуют.
9. Исправленная кнопка `Диагностика` визуально подтверждена одной строкой;
   единый список приложений/сайтов, диагностика, тарифы 1/3/6 месяцев и экран
   версии также проверены. Телефон оставлен на главном экране без VPN.

Машинный итог:
`C:\BlueVPN_Builds\paid_beta_20260811_fusion_actions_v7_0.4.6\android-physical\android-physical-smoke-summary.json`.

## Физический Windows smoke

Точный `0.4.6-paid-beta.2+4602` проверен единственным delayed detached runner с
начальной задержкой, независимым deadman и без сетевых переключений внутри
активного Codex-запроса.

Последовательность проверки:

1. До установки подтверждены работа внешнего Amnezia-туннеля, production и
   paid-beta API, YouTube и отсутствие активных компонентов Green VPN.
2. SHA-256 и размер установщика повторно сверены до задержки и установки.
3. Fusion-окно прошло визуальный контракт: `980x720`, `405` различимых цветов,
   непустой интерфейс и видимая отдельная кнопка `Диагностика`.
4. Fresh connect использовал единственный кандидат `current_wg0`; клиентский
   лог зафиксировал `22.323` секунды, реальный wall-time тестовой обвязки был
   `30.535` секунды. Probe и privileged takeover подтверждены.
5. Cached connect снова использовал единственный кандидат; клиентский лог
   зафиксировал `16.257` секунды, wall-time `26.802` секунды. Свежая
   config-bound cached-route proof подтверждена.
6. Оба запуска завершились полным cleanup. Green VPN остановлен, внешний
   Amnezia-туннель восстановлен, production API ответил `200`, YouTube `204`,
   failsafe и deadman удалены.

Машинный итог и скриншот:
`C:\BlueVPN_Builds\fusion_windows_acceptance_20260813_physical_v5_b4602_afeccc7`.

После smoke точный Windows installer опубликован только в paid-beta на Timeweb
и RUVDS. Строгая проверка двух stable и двух paid-beta manifests/тел плюс
четырех backend health/version ответов прошла `12/12`; production остался
побайтно прежним.

## Границы готовности

- Это готовый Android и Windows paid-beta, а не разрешение на production.
- Production-кандидат получает новый Windows build `4603`, потому что его
  stable-runtime байты отличаются от уже проверенного beta `4602`.
- До stable-публикации точный production installer должен пройти отдельный
  автономный smoke с recovery.
- Для переноса Fusion в stable production требуются приемка интерфейса, решение
  по Authenticode/SmartScreen и отдельное явное разрешение владельца.
- Коммерческие и рекламные функции остаются fail-closed.
