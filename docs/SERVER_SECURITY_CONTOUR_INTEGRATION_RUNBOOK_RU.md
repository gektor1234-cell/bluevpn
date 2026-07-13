# Регламент интеграции нового VPN-сервера в защищённый контур Green VPN

Дата первой версии: 2026-07-13.

## Назначение

Этот документ задаёт единый воспроизводимый процесс добавления нового VPN-узла или нового провайдера. Текущий NL2 `5.129.216.42` является проверенным эталоном процесса, но его IP, имена, ключи и порты нельзя копировать на другой узел.

Регламент не является разрешением на развёртывание. Для каждого нового узла сначала создаётся отдельный паспорт и preview-canary. Stable WireGuard, production-каталог, WARP на рабочем Windows-ПК и существующие узлы остаются без изменений до прохождения всех ворот.

## Что можно добавить без обновления приложения

Новый сервер можно включить серверной публикацией без обновления клиента, если приложение уже содержит соответствующий engine и понимает выдаваемый `protocol/configFormat`. Меняются только серверный daemon, root-only профиль на control plane и preview-каталог.

Обновление приложения обязательно, если добавляется новый протокол, новый формат конфига, новая схема аутентификации или иное клиентское поведение. Неизвестный клиенту transport нельзя маскировать под известный.

## Неподвижные инварианты

1. Сначала preview, затем решение о production. Прямое включение нового узла в stable запрещено.
2. Bootstrap и rollback по умолчанию выполняют только dry-run. Изменение требует отдельного точного `--apply` и совпадения host guard.
3. Каждый изменяющий скрипт привязан к одному паспорту: публичный IP, provider, server ID, transport, unit и config path.
4. До и после операции сравниваются SHA-256 существующих конфигов и состояния всех stable unit.
5. Ключи, пароли, токены и полные клиентские конфиги не попадают в Git, stdout, отчёты или аргументы командной строки.
6. Секреты создаются на целевом сервере, лежат в root-only файлах и передаются control plane по защищённому каналу только в root-only файл.
7. Бинарники имеют закреплённую версию, SHA-256, источник и лицензию. `latest` и непроверенные install-pipe запрещены.
8. Один transport использует отдельные unit, config root, runtime user, listener и rollback. Общий процесс с другим transport не допускается.
9. Успех control plane не заменяет data-plane proof. Нужны egress, production API, оба control plane и YouTube/целевой сервис.
10. При любой ошибке срабатывает fail-closed cleanup; исходный VPN и сеть восстанавливаются и отдельно проверяются.
11. Каталог публикует только `clientConfigReady=true`, `serverDaemonReady=true` и `routeProbeReady=true`.
12. Stable APK после работ обязан иметь тот же ожидаемый SHA-256 и не содержать preview payload, components или DEX packages.

## Паспорт нового узла

До первой команды создать локальный файл отчёта без секретов со следующими полями:

```yaml
change_id: YYYYMMDD-provider-region-sequence
provider: <timeweb|ruvds|other>
provider_server_id: <id>
region_code: <ru-msk|nl-ams|gb-lon|...>
role: <vpn-data-plane|ru-control-plane>
public_ipv4: <exact-ip>
public_ipv6: <none-or-exact-prefix>
os_image: ubuntu-24.04
ssh_host_key_sha256: <fingerprint>
expected_egress_ipv4: <exact-ip>
preview_server_id: <unique-catalog-id>
preview_display_name: <public-name-without-provider-details>
protocols: [<existing-supported-protocols>]
listeners: [<proto/port>]
dns_names: [<names>]
stable_units_to_preserve: [wg-quick@wg0]
owner_approval_scope: preview-only
rollback_checkpoint: <filled-after-preflight>
```

Если одно из полей неизвестно, apply не начинается. Для нового провайдера дополнительно фиксируются биллинг, лимит трафика, правила firewall/security group, rescue-доступ и способ удаления сервера.

## Фаза 0. Состояние проекта и границы изменения

1. Прочитать `docs/CURRENT_HANDOFF.md`, этот регламент и документ соответствующего transport.
2. Выполнить `git status --short`, сохранить branch и HEAD. Не откатывать чужие изменения.
3. Создать change directory `C:\Users\gekto\GreenVPN_Checkpoints\<change_id>`.
4. Сохранить только безопасные preflight-отчёты. Не копировать туда private key или полный профиль.
5. Зафиксировать текущие stable APK size/SHA-256, production backend release, public catalog и stable egress.
6. Составить явный список разрешённых файлов, unit, портов, DNS-записей и control-plane rows. Всё остальное считается запрещённым.

## Фаза 1. Preflight сервера

Проверить до установки:

- IP и SSH host key совпадают с паспортом;
- Ubuntu release, архитектура, время/NTP, диск, RAM, CPU и kernel пригодны;
- egress равен ожидаемому IP;
- firewall провайдера и ОС известны, разрешаются только заявленные порты;
- нет конфликтующих listeners, failed units и незадокументированных NAT rules;
- `wg0` и другие существующие transport активны;
- конфиги и unit существующих transport сохранены в timestamped root-only backup;
- SHA-256 охраняемых файлов записаны в `stable.before.sha256`;
- публичные API и YouTube доступны с узла до изменения.

Apply запрещён при неверном IP, неизвестном host key, расхождении stable fingerprint, нездоровом узле или отсутствии rollback-доступа.

## Фаза 2. Стандарт canary-скриптов

Для каждого transport должны существовать три отдельных скрипта:

```text
bootstrap_<transport>_canary.sh
check_<transport>_canary_readiness.sh
remove_<transport>_canary.sh
```

Bootstrap обязан:

- проверять `EUID=0`, exact public IP и точный approval tuple;
- печатать полный план в dry-run без секретов;
- создавать timestamped backup до первой записи;
- проверять подпись/хеш upstream до установки;
- создавать отдельного system user без shell, если daemon это поддерживает;
- устанавливать конфиги с минимальными ACL;
- запускать daemon через hardened systemd unit;
- проверять точный listener, daemon config и реальный egress;
- повторно сравнивать `stable.before.sha256` и `stable.after.sha256`;
- автоматически восстанавливать backup при ошибке;
- завершаться ненулевым кодом, если доказательство неполно.

Rollback обязан иметь тот же exact-host guard, dry-run по умолчанию, удалять только принадлежащие canary объекты и после удаления доказывать active stable units и исходные fingerprints.

## Фаза 3. Безопасный удалённый запуск

PowerShell не должен передавать многострочный Bash напрямую через native pipe: CRLF или завершающий CR может исказить код возврата. Использовать точные LF-байты и Base64:

```powershell
$path = Resolve-Path '.\scripts\server\bootstrap_<transport>_canary.sh'
$text = [IO.File]::ReadAllText($path).Replace("`r", '')
$b64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($text))
ssh -o BatchMode=yes root@<exact-ip> `
  "printf '%s' '$b64' | base64 -d | bash -s -- --expected-public-ip <exact-ip> --approved-existing-host <exact-ip> --apply"
if ($LASTEXITCODE -ne 0) { throw 'Remote apply failed' }
```

Секреты нельзя добавлять в `$b64`, параметры SSH или transcript. Если секрет нельзя создать на сервере, он передаётся отдельным защищённым stdin/file workflow без вывода значения.

## Фаза 4. Порядок транспортов

Текущий порядок готовности и клиентского failover:

1. AmneziaWG2.
2. Hysteria2.
3. VLESS REALITY/XHTTP.
4. Naive HTTPS.
5. dnstt.
6. Stable WireGuard остаётся самостоятельным проверенным путём и не модифицируется canary-работами.

Новый узел не обязан сразу поддерживать все пять preview-транспортов. Каждый добавляется и принимается независимо. Следующий transport не скрывает провал предыдущего.

Для каждого transport проверить:

| Слой | Обязательное доказательство |
|---|---|
| Supply chain | version, source URL, signature/hash, license |
| Process | один точный daemon/child, отдельный unit и runtime directory |
| Network | только заявленный listener, нет случайного UDP/TCP exposure |
| Config | schema validation, root-only secrets, no symlink |
| Data plane | ожидаемый egress и полезный HTTPS-трафик |
| Failure | engine kill приводит к fail-closed cleanup |
| Recovery | reconnect возвращает `up` и ожидаемый egress |
| Cleanup | `down`, 0 процессов, 0 service records, plaintext удалён |
| Isolation | fingerprints и stable services не изменились |

## Фаза 5. Особый порядок для dnstt

dnstt принимается только после всех пунктов:

1. Отдельная подзона, два NS-имени и A/AAAA glue опубликованы у регистратора.
2. Авторитетный frontend отвечает NS/SOA с `AA=true`, не обслуживает открытую рекурсию и отказывает внешним зонам.
3. dnstt backend слушает только loopback; frontend слушает публичные UDP/53 и TCP/53.
4. dnsdist закреплён по версии, работает с `healthCheckMode="up"`, `TasksMax=8192`, `LimitNOFILE=16384` и не создаёт health-check spam.
5. Cloudflare и Google видят делегацию и SOA.
6. Readiness с `--require-delegation` возвращает `server_data_plane_ready=true` и `doh_delegation_ready=true`.
7. Физический Android-тест проходит egress/API/YouTube, watchdog, reconnect и cleanup.

Эталон NL2 использует `scripts/server/bootstrap_dnstt_dns_frontend.sh`, `check_dnstt_canary_readiness.sh` и `remove_dnstt_dns_frontend.sh`.

## Фаза 6. Control plane и каталог

1. Создать root-only базовый клиентский профиль отдельно на Timeweb и RUVDS.
2. Проверить schema и отсутствие server-private material.
3. Сначала добавить managed preview row с уникальным server ID; stable row не менять.
4. Развернуть атомарно с backup SQLite/config и rollback-on-error.
5. Выполнить SQLite `quick_check`, сравнить количество и hash критических строк на обоих control plane.
6. Проверить primary и fallback contract probe. Оба должны выдать одинаковый безопасный формат.
7. Legacy/stable client не должен видеть preview row.
8. Новый server/provider не требует app update только при уже поддерживаемом `protocol/configFormat`.

## Фаза 7. Клиентские физические ворота

Проверки проводятся отдельной preview-сборкой/package. Для каждого transport обязательны:

- VPN permission подготовлен;
- egress совпадает с паспортом;
- production API, primary control plane, fallback control plane возвращают ожидаемый HTTP;
- YouTube/целевой blocked service отвечает;
- RX/TX больше нуля и child process ровно один;
- Home, Recents и relaunch не разрывают активную сессию, если transport это поддерживает;
- принудительное убийство engine очищает VPN fail-closed;
- reconnect возвращает рабочий data plane;
- финальный disconnect оставляет ноль процессов/service records;
- runtime и plaintext profile удалены.

Cooldown принимается только после физического теста: `1/3/10/30` минут, success marker пишется после data-plane probe, а не после одного запуска процесса.

## Фаза 8. Release gate и публикация

До любой публикации выполнить:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\windows\bluevpn_release_gate.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\windows\verify_android_stable_transport_isolation.ps1 -ApkPath <stable-apk>
```

Критерии: release gate `0 warnings`, `0 errors`; stable APK size/SHA-256 совпадают с ожидаемыми; preview payload отсутствует. Затем выполняются backend/unit/native tests, APK verifier и отдельный physical report.

Публикация проходит ступенями: `server daemon -> root-only config -> managed preview row -> один тестовый аккаунт/device -> ограниченный preview cohort -> решение о production`. Любой провал останавливает продвижение и запускает rollback текущей ступени.

## Фаза 9. Контрольный слепок

Checkpoint должен содержать:

- паспорт и разрешённый scope;
- branch, HEAD, `git status --short` и Git bundle;
- версии и SHA-256 артефактов без секретов;
- pre/post stable fingerprints;
- readiness и physical JSON reports;
- server backup/rollback paths;
- service/listener/DNS status;
- release gate summary;
- SHA-256 manifest самого checkpoint;
- итог `ready`, `preview-only` или `rolled-back` с причиной.

Private keys, access tokens, payment data, email/SMS codes и полные клиентские профили в checkpoint запрещены.

## Быстрый маршрут следующей интеграции

1. Скопировать этот checklist в новый change directory и заполнить паспорт.
2. Выбрать уже поддерживаемые transport и назначить уникальные server ID/listeners.
3. Снять stable fingerprints и server backup.
4. Адаптировать exact-host guarded bootstrap/readiness/rollback, не копируя секреты NL2.
5. Dry-run, review diff, apply одного transport, readiness, rollback rehearsal.
6. Добавить только preview contracts в оба control plane и выполнить `10/10`-подобный contract proof.
7. Пройти физический data-plane/fail-closed/reconnect тест.
8. Пройти release gate и stable isolation.
9. Создать checkpoint и только затем решать вопрос о cohort/production.

Никакая часть этого быстрого маршрута не позволяет пропустить физический data-plane proof или изменить stable “на время теста”.
