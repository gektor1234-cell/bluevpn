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
- Commit `72443f9` делает кодировку installer UI детерминированной между
  Windows PowerShell 5.1 и PowerShell 7.
- Clean-source candidate `0.4.6+4632` прошел package audit (`66` entries), но
  отклонен physical smoke: клик подключения попал в момент незавершенного
  startup catalog refresh, а параллельный refresh возвращал управление вместо
  ожидания текущего запроса. Final recovery вернул исходный безопасный baseline.
- Commit `752968a` вводит single-flight catalog refresh и дожидается фактической
  остановки deadman перед записью cleanup evidence.
- Clean-source candidate `0.4.6+4633` прошел exact package audit и дошел до
  applications runtime. Exact install, paid owner, foreground, direct
  fingerprint, SOCKS5 preflight и selected attribution прошли; selected egress
  отклонен, потому что TCP redirect не был принят loopback relay. Cleanup и
  исходный Amnezia/API/YouTube baseline полностью восстановлены.
- Durable router evidence локализовал дефект после attribution: пакет успешно
  планировался и передавался `WinDivertSend`, но сохранял внешний source при
  loopback destination. Windows отбрасывал такой tuple до TCP listener.
- Текущий successor переписывает обе стороны selected tuple в IPv4/IPv6
  loopback, сохраняет точный исходный tuple для обратного восстановления и
  оставляет relay доступным только на loopback. Две независимые MSVC-сборки
  совпали: core SHA-256 `B4759403D1550594A6032DA4869C6666B234B88868ED19D8A1FD38372B7349CE`,
  размер `231424`; policy, analyze, `130` tests (`14` skipped) и release gate
  прошли, warnings/errors `0/0`.
- Fix зафиксирован и pushed exact commit
  `58c3ac8c54395980b7addb5ad094a58786c8b30e`.
- Exact clean-source candidate `0.4.6+4634`: installer SHA-256
  `79CE8577E1ADBCD08977B471FF797C0A8527253ABC056D1F5301E4988B6C1D7F`,
  размер `54026752`, `NotSigned`; package audit `66` entries, ошибок нет,
  `productionPublished=false`.
- Единственный delayed detached physical smoke успешно прошел
  `full -> applications -> full`: selected egress совпал с `5.129.216.42`,
  selected YouTube вернул `204`, returned-full egress восстановлен. Cleanup
  вернул Amnezia/API `200`/YouTube `204`; metric `42739` и failsafes отсутствуют.
- Все четыре screenshot-файла визуально проверены; privacy-safe router evidence
  подтверждает redirect injection, loopback relay acceptance и SOCKS5 upstream.
- После owner review найден отдельный Diagnostics false negative: установленный
  `+4634` показывал `не активно`, потому что обычный UI-процесс не имел доступа
  к прямому `wg.exe show`, хотя authenticated GreenVPNService подтверждал
  running full tunnel.
- Commit `fcd0c6e8a83742aa71e4aabf480cfa9df19321d3` (pushed) переводит Diagnostics,
  support summary и support report на authoritative local-service status;
  direct WireGuard query остается fallback только при недоступном service.
- Exact clean-source successor `0.4.6+4635`: installer SHA-256
  `0FBB24B4E79081A393D162130D593327B956D92453361A5944E89E661811ECB7`,
  размер `54026240`, `NotSigned`; package audit `66` entries, ошибок нет,
  `productionPublished=false`. Analyze, `135` tests (`14` skipped), focused
  Fusion tests и release gate `0/0` прошли.
- Работающий `+4634` не останавливался и сетевые переходы не выполнялись.
  `+4635` не установлен; целевая visual confirmation Diagnostics остается
  последней технической проверкой этого UI-only successor.

## Исполняемый чек-лист

- [x] Восстановить контекст репозитория, кандидата и последнего physical smoke.
- [x] Завершить loopback relay и убрать небезопасные port-only решения.
- [x] Убрать дублирующий переключатель режима со второй вкладки UI.
- [x] Добавить/обновить policy и UI regressions.
- [x] Прогнать deterministic double build, policy tests, Flutter analyze/tests и
  Windows release gate без warnings/errors.
- [x] Зафиксировать source commit и push.
- [x] Из clean source собрать `0.4.6+4632`, проверить точную версию, размеры,
  SHA-256, package audit и `productionPublished=false`; candidate отклонен по
  physical acceptance и не подлежит публикации.
- [x] Из clean source собрать successor `0.4.6+4633` после catalog-race fix и
  повторить точную проверку пакета; candidate отклонен по physical acceptance.
- [x] Локализовать post-attribution relay failure и подготовить детерминированный
  loopback-tuple successor без небезопасного attribution fallback.
- [x] Зафиксировать новый source commit/push и собрать exact clean-source
  successor `0.4.6+4634`.
- [x] Запустить один delayed detached physical smoke из уникального каталога.
- [x] Проверить логи, privacy-safe markers и screenshots.
- [x] Зафиксировать evidence/docs commit `0528f8e` и push.
- [x] Исправить Diagnostics source-of-truth, добавить policy regressions и
  зафиксировать/push source commit `fcd0c6e`.
- [x] Собрать и проверить exact clean-source successor `0.4.6+4635` без
  Android/backend изменений и без production publication.
- [ ] После завершения пользовательской VPN-сессии безопасно установить
  `+4635` и визуально подтвердить `Подключение: активно` в Diagnostics.

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

- Fusion UI/email владелец принял без отдельного live email-прогона; automated
  auth/recovery tests прошли. Acceptance окончательно привязывается к `+4635`
  после целевой проверки Diagnostics.
- Authenticode/unsigned SmartScreen gate владелец пока пропустил; он остается
  непройденным.
- Stable publication не разрешена и остается заблокированной предыдущим gate.
