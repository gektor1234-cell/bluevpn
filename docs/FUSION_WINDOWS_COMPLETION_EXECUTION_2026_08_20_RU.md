# Green VPN Fusion Windows: план завершения

Этот файл является единым исполняемым чек-листом завершения Windows Fusion.
Он не заменяет release contract и не разрешает публикацию в production.

## Неподвижные границы

- Работа только с Windows-клиентом, process-router, Windows harness и документацией.
- Не менять Android, backend и Friendly Linnet `5.129.237.163`.
- Не выполнять ручные переключения VPN, маршрутов или служб в активной сессии.
- Физический прогон запускается один раз из уникального каталога отложенным
  detached runner с `try/finally`, независимым deadman и проверкой восстановления.
- Не создавать повторяющуюся heartbeat-автоматизацию и не запускать дубликаты.
- Не публиковать production до трех последовательных owner gates:
  UI/email acceptance, SmartScreen/Authenticode decision, stable approval.

## Текущая точка

- Базовый pushed commit: `cc6c8e712e18e9643e15f79a11c84a3468317163`.
- Candidate `0.4.6+4630` отклонен: exact install, paid owner, full UI/runtime,
  foreground, direct fingerprint и SOCKS5 preflight прошли, selected executable
  не дал подтвержденный egress fingerprint.
- Clean-source candidate `0.4.6+4631` отклонен до установки: package audit
  обнаружил зависимую от версии PowerShell запись `install_ui.ps1` без UTF-8 BOM.
- Commit `7eca502` исправляет loopback relay, точную tuple-привязку,
  ambiguity fail-closed, UI-дублирование и ложное определение исходного VPN.
- Следующий source commit делает кодировку installer UI детерминированной между
  Windows PowerShell 5.1 и PowerShell 7.

## Исполняемый чек-лист

- [x] Восстановить контекст репозитория, кандидата и последнего physical smoke.
- [x] Завершить loopback relay и убрать небезопасные port-only решения.
- [x] Убрать дублирующий переключатель режима со второй вкладки UI.
- [x] Добавить/обновить policy и UI regressions.
- [x] Прогнать deterministic double build, policy tests, Flutter analyze/tests и
  Windows release gate без warnings/errors.
- [x] Зафиксировать source commit и push.
- [ ] Из clean source собрать следующий Windows-only candidate, проверить точную
  версию, размеры, SHA-256, package audit и `productionPublished=false`.
- [ ] Запустить один delayed detached physical smoke из уникального каталога.
- [ ] Проверить логи, privacy-safe markers и screenshots.
- [ ] Зафиксировать evidence/docs commit и push.

## Обязательный physical acceptance

- exact hashes/version и paid owner session;
- authoritative UI/runtime `full -> applications -> full`;
- full screenshot содержит Pause, Change connection, Diagnostics и Details,
  но не показывает public IP, protocol или route;
- один foreground candidate не дольше 30 секунд;
- direct unselected fingerprint подтвержден;
- explicit SOCKS5 preflight подтвержден;
- selected executable egress равен `5.129.216.42`;
- selected YouTube возвращает HTTP 204;
- нет selected IPv6 escape, если direct IPv6 доступен;
- после возврата в full восстановлен full egress;
- authenticated disconnect и полный cleanup;
- отсутствуют metric `42739` и failsafes;
- финальный baseline: Amnezia, API 200 и YouTube 204.

## Что останется после технического завершения

Только внешние owner decisions, строго по очереди:

1. Принять Fusion UI и email-коммуникацию.
2. Выбрать: принять unsigned/SmartScreen риск либо предоставить Authenticode.
3. Отдельно разрешить stable production publication.
