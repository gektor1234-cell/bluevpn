# Green VPN: главный операционный регламент

## 1. Назначение

Регламент нужен для повторяемого обслуживания Green VPN без восстановления
контекста из старых чатов. Он покрывает checkpoint, deploy, rollback, новый
сервер, обновление каталога, платежи и транспортный контур.

Текущая public-product политика: клиент знает строгий каскад
`WireGuard UDP -> AmneziaWG -> Hysteria2 -> VLESS REALITY/XHTTP -> Naive HTTPS
-> dnstt`. Первые пять групп опубликованы на NL1, London и NL2; dnstt остаётся
последним резервом только на NL2. Новые узлы и изменение порядка требуют
guarded rollout, но уже опубликованная server-side конфигурация не требует
новой сборки клиента.

## 2. Неподвижные правила

1. Перед изменением выполнить `git status --short` и прочитать handoff.
2. Перед production/server изменением создать полный проверенный checkpoint.
3. Не печатать секреты и не передавать их через Git или обычные архивы.
4. Stable и preview имеют разные package IDs, services, ports, directories и API paths.
5. RUVDS не создаёт production-платежи и не запускает renewal executor.
6. Каталог не публикуется, пока data-plane probe не доказал реальный трафик.
7. Control-plane health не считается доказательством работы VPN-транспорта.
8. Любой deploy обязан содержать preflight, apply, verify и rollback.
9. Friendly Linnet `5.129.237.163` не изменяется без отдельной команды.
10. Сейчас запрещено переносить AWG2/H2/VLESS/Naive/dnstt на другие серверы.
11. Перед database/auth/payment операцией проверяется UTC/NTP на всех участвующих
    узлах. Clock skew больше 5 секунд блокирует изменение состояния.

Перед commit и в CI запускается безопасный сканер Git-дерева:

```powershell
python scripts/security/scan_tracked_secrets.py --include-untracked --history
```

Он запрещает приватные ключи, credential-файлы и известные форматы токенов в
текущем дереве и истории, но выводит только правило и координату, без найденного
значения.

### 2.1 Публичная модель локаций

1. Пользователь выбирает логическую локацию, а не физический сервер и не способ
   обхода: `Авто`, `Нидерланды`, `Англия` и последующие страны.
2. Все активные catalog rows одной страны имеют одинаковый публичный
   `locationId` вида `country:NL`. Клиент показывает только первую лучшую строку,
   но при подключении перебирает все готовые внутренние маршруты этой страны.
3. Ручной выбор страны никогда не имеет права незаметно перейти в другую
   страну. `Авто` может выбирать между всеми опубликованными локациями.
4. Новый физический сервер уже поддерживаемого клиентом транспорта добавляется
   без обновления приложения: hidden catalog row -> выдача конфига на обоих RU
   control planes -> data-plane proof -> публикация row.
5. Новый транспорт требует обновления приложения только тогда, когда его
   движка и parser/config contract ещё нет в установленном клиенте.
6. Под каждой реальной локацией всегда отображается числовая задержка `N мс`.
   Пока замера нет, контракт интерфейса требует `0 мс`, а не пустую строку.
7. Provider, hostname, server ID, endpoint, transport, health score и rollout
   marker не выводятся в customer UI, toast, update notes и support report.
8. Недоступная страна полностью скрывается из обычного picker. Например,
   `Англия` не публикуется, пока London имеет provider state `notpaid`.

## 3. Полный checkpoint

### 3.1 Создание

```powershell
$stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$root = "C:\Users\gekto\GreenVPN_Checkpoints\full_$stamp"
New-Item -ItemType Directory -Path $root
git bundle create "$root\bluevpn_all_refs.bundle" --all
powershell -ExecutionPolicy Bypass -File `
  scripts/windows/create_full_project_checkpoint.ps1 `
  -Label "full_$stamp" `
  -CheckpointRoot $root
```

Серверный script делает online-backup активных SQLite DB, `PRAGMA quick_check`,
сохраняет app/config/systemd/nginx/firewall/website и исключает venv, логи и
исторические backups. Windows-оркестратор скачивает root-only архивы, создаёт
AES-256 7z с encrypted headers, проверяет его и удаляет plaintext.

После серверной части `create_local_restore_snapshot.ps1` создаёт отдельный
`local_state.7z`: binary patch dirty tracked-файлов, untracked исходники,
Android release signing, SSH-доступ и локальный secret store. Сырые многогигабайтные
результаты старого поиска секретов исключаются как опасные производные дубли;
их redacted-инвентари сохраняются.

### 3.2 Критерий готовности

- Git bundle проходит `git bundle verify`.
- `server_state.7z` проходит `7z t`.
- `local_state.7z` проходит `7z t`, а manifest содержит dirty/untracked counts.
- `encrypted_manifest.json` содержит размер и SHA-256.
- Пароль находится только в защищённом secret store; DPAPI recovery приложен.
- На серверах не осталось временных `greenvpn-full-restore-*` файлов.
- ACL checkpoint: owner, SYSTEM, Administrators.
- Только после обеих проверок разрешён dry-run/apply
  `scripts/windows/prune_local_secret_scan_duplicates.ps1`.

### 3.3 Восстановление

1. Остановить только восстанавливаемый service.
2. Распаковать archive в отдельный staging directory.
3. Проверить hostname/role из metadata.
4. Восстановить app/config, сохраняя numeric ownership и modes.
5. Восстановить SQLite в новый файл, выполнить `quick_check`, затем atomic rename.
6. `systemctl daemon-reload`, config tests (`nginx -t`, transport-specific check).
7. Запустить service, проверить local health, затем public health/data plane.
8. Не удалять staging до завершения проверки с клиента.
9. Для local state применить `working_tree.patch`, затем вернуть каталог
   `untracked`; signing/SSH/secrets восстанавливать только в защищённые пути с
   прежними ACL.

## 4. Обычный новый VPN-сервер без обновления приложения

### 4.1 Provider preflight

- Зафиксировать provider, region, server ID, public IPv4, monthly price.
- Проверить API token read-only inventory и наличие SSH key.
- Не создавать сервер, если роль/IP/стоимость не записаны в deployment plan.
- Секрет provider API остаётся в локальном secret store.

### 4.2 Базовая система

1. Ubuntu 24.04 или Debian 12, отдельный hostname.
2. SSH key only; запрет password login и root password auth.
3. Обновить packages, включить automatic security updates.
4. Настроить firewall deny-by-default, открыть SSH и только transport ports.
5. Применить `scripts/server/harden_ssh_server.sh`: сначала dry-run, затем
   `--apply`, не закрывая исходную сессию до успешного второго SSH-подключения.
6. Установить time sync, fail2ban, journald limits и disk alerts.
   Штатный idempotent installer: `scripts/server/apply_server_os_baseline.sh`.
   Он не перезагружает сервер; `--upgrade-packages` применяется по одному узлу
   с проверкой резервного data/control plane между узлами.
   Если обнаружен большой clock skew, использовать
   `scripts/server/ensure_server_time_sync.sh`. `slew` не двигает время назад;
   `step` разрешён только после online-backup DB, остановки stateful/VPN-служб и
   явных `--allow-clock-step --stateful-services-stopped`. После шага все службы,
   tunnel egress и DB `quick_check` проверяются заново.
7. Создать `/opt/greenvpn-server`, root ownership, mode `0755`.
8. Снять post-hardening checkpoint.

### 4.3 Stable transport

1. Развернуть уже поддерживаемый stable engine из pinned package/source.
2. Создать уникальные server keys и subnet; не копировать peer identity NL1/NL2.
3. Config root-only, service hardening, forwarding и NAT rules.
4. Проверить UDP listener, handshake, bidirectional counters и exit IP.
5. Проверить production API, fallback API и целевые сервисы через tunnel.
6. Проверить cleanup после stop/restart и восстановление firewall после reboot.

### 4.4 Control-plane integration

1. Создать catalog row сначала как hidden/inactive.
2. Добавить endpoint/config generator server-side.
3. Проверить выдачу config на Timeweb и RUVDS для disposable test device.
4. Проверить отсутствие private key/config в logs и admin response.
5. Запустить data-plane probe минимум с двух control planes.
6. Только после green proof включить `is_active` и rollout percentage.
7. Stable client увидит узел после catalog refresh; APK/installer не меняются.

### 4.5 Rollback

- Немедленно скрыть catalog row.
- Отозвать тестовые peers/configs.
- Остановить service и восстановить firewall snapshot.
- Не удалять VPS до анализа и final snapshot.

## 5. Будущий перенос полного защитного контура

Этот раздел является инструкцией, а не разрешением на текущий rollout.

### 5.1 Изоляция

Для каждого транспорта обязательны отдельные:

- systemd unit и Unix user, если engine это поддерживает;
- root-only config directory;
- port/listener без конфликта со stable;
- client capability и config schema version;
- hidden catalog row;
- watchdog, cleanup и rollback script;
- server/data-plane readiness evidence.

### 5.2 Порядок внедрения

1. AWG2.
2. Hysteria2.
3. VLESS REALITY/XHTTP.
4. Naive HTTPS.
5. dnstt с отдельной authoritative DNS delegation.

Каждый следующий этап начинается только после green proof и rollback предыдущего.
Клиентский порядок: `WireGuard UDP -> AWG2 -> H2 -> VLESS -> Naive -> dnstt`.
Перед переходом к следующему маршруту клиент обязан остановить предыдущий и
подтвердить отсутствие его процесса, интерфейса и управляемых маршрутов.
Cooldown для неудачного маршрута: `1/3/10/30` минут.

### 5.3 Proof contract для каждого этапа

- endpoint доступен из обычной ISP-сети;
- exit IP совпадает с целевым сервером;
- production, Timeweb paid и RUVDS paid API отвечают через transport;
- YouTube/целевой ресурс отвечает ожидаемым status;
- ровно один engine process и есть двусторонние counters;
- kill engine приводит к fail-closed cleanup;
- reconnect проходит;
- background/relaunch не роняет Android tunnel;
- final down не оставляет process, route, service или plaintext config;
- stable tunnel и все ранее активные transports не изменены.

### 5.4 dnstt отдельно

- Делегация NS должна иметь минимум два реально независимых frontend IP.
- Authoritative frontend отвечает только за transport zone и REFUSED для чужих.
- Backend daemon loopback-only; public 53 слушает только hardened frontend.
- Перенос dnstt запрещён, пока владелец отдельно не разрешит расширение обходов.

## 6. Backend deploy

1. Запустить backend tests и `py_compile`.
2. Выполнить `pip-audit -r backend_live/requirements.txt`; уязвимости direct и
   transitive dependencies блокируют deploy.
3. Сравнить schema/env requirements с обеими control planes.
4. Создать immutable release directory, не перезаписывать current release.
5. На Timeweb deploy и local health; затем public health.
6. На RUVDS deploy той же SHA-256 сборки; billing writer остаётся false.
7. Проверить DB parity, bootstrap, login code, catalog и update manifests.
8. При ошибке atomic switch `current` на предыдущий release и restart.

Для server-only изменения paid-beta без APK, EXE и сайта использовать:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File `
  scripts/windows/prepare_paid_beta_backend_bundle.ps1
```

Затем одну и ту же SHA-256 сборку загрузить на оба control-plane, выполнить
`install.sh` сначала без `--apply`, остановить sync timer на обоих узлах и
применить с `--leave-sync-stopped --apply`. После green health/schema на обоих
узлах включить timers, вручную запустить по одному sync cycle в каждую сторону и
сравнить summaries. Installer не содержит и не меняет client artifacts или site.

## 7. SQLite state sync

- Billing имеет один writer: Timeweb.
- Sync должен переносить keyed inserts/updates и явные tombstones.
- Конфликт не разрешается молча; cycle возвращает nonzero и alert.
- Перед изменением схемы оба узла получают одинаковую migration version.
- После deploy сравниваются critical counts и deterministic row digests.
- Monitoring observations могут различаться и не являются parity failure.
- Timeweb использует `GREENVPN_SQLITE_NODE_ID_BASE=0`, RUVDS использует
  `1000000000`; новые auto-increment ID поэтому не пересекаются.
- Удаления реплицируются через `replication_tombstones`; повторно созданная после
  удаления запись с более новым timestamp не удаляется старым tombstone.
- Если natural key tombstone содержит `user_id`, sync сначала преобразует его через
  email-based `user_id_map`; иначе удаление может попасть в ID-пространство другого узла.
- Необязательная таблица, отсутствующая на обоих узлах, считается согласованно
  отсутствующей. Наличие таблицы только на одном узле является schema mismatch и
  блокирует транзакцию.
- Snapshot передаётся как gzip level 1, проверяется `gzip -t`, атомарно
  распаковывается и только затем передаётся merge-скрипту. Полный DB-файл никогда
  не заменяет live DB.
- Перед и после коррекции часов запускать
  `audit_sqlite_future_timestamps.py --fail-on-event-future`. Для узла с
  неверными часами передавать доверенное `--reference-now` от синхронизированного
  control host. `repair_sqlite_future_event_timestamps.py` меняет только event
  columns, требует точный offset, bounded future window и отдельный backup;
  deadline fields не корректируются автоматически.

## 8. Платежи и рекурренты

Production readiness зелёная только если:

1. YooKassa production keys и HTTPS webhook/return настроены.
2. Рекурренты по банковским картам одобрены магазином.
3. Реальный заказ `green_30d` на 249 RUB активирован provider confirmation.
4. `payment_method.saved=true`, `auto_renew=1`, method ID сохранён server-side.
5. Самостоятельное выключение ставит `auto_renew=0` и удаляет method ID на обоих узлах.
6. Уже оплаченный период остаётся активным.
7. RUVDS не создаёт первый платёж и не выполняет автоматическое списание.

Admin mark-paid никогда не считается provider smoke.

## 9. Клиентские релизы

### Android

- Release build запрещён без `android/key.properties`.
- `apksigner verify` обязателен.
- SHA-256 signer должен совпасть с `android/release_signer_sha256.txt`.
- Stable package ID не заменяется preview package ID.
- Перед публикацией: install-over-existing, login, connect, background, relaunch,
  social-only, update and rollback checks.

### Windows

- Stable и beta имеют отдельные service names, ports и ProgramData roots.
- Installer проверяется на чистой VM и при upgrade существующей версии.
- Публичный installer требует Authenticode code-signing certificate.
- Update manifest не становится mandatory до проверки signature и rollback.
- `finalize_windows_trusted_release.ps1` в режиме `-Apply` автоматически
  выбирает валидный Code Signing EKU certificate с private key, подписывает
  собственные app/service EXE до архивации, bootstrap и финальный installer
  после resource updates, затем сохраняет JSON signature reports.
- `install_windows_public_product_release.sh` получает оба signature report,
  сверяет их с точными SHA-256 и одной publisher/thumbprint identity. Без
  доказательства он не публикует trusted metadata.

### Воспроизводимый локальный финальный кандидат

Для обычного чистого release candidate после всех проверок сначала зафиксировать
исходники коммитом и убедиться, что `git status --porcelain` пуст. Затем одной
командой собрать отдельные Android и Windows артефакты без публикации:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File `
  scripts/windows/build_final_release_candidate.ps1
```

Скрипт отказывается работать с грязным Git-деревом и существующим выходным
каталогом, включает полный внутренний каскад, но собирает публичную оболочку без
beta/preview-маркеров. Android использует side-by-side package
`pro.greenvpn.app.finalcandidate` и debug-подпись только для физической проверки;
Windows остаётся неподписанным локальным кандидатом. Корневой
`final-candidate-manifest.json` фиксирует исходный коммит, версии, режимы и
SHA-256 обоих артефактов. Эти файлы нельзя публиковать как обязательное
обновление до production-подписи и ручных launch gates.

## 10. Публичный сайт

- Бесплатный доступ и его лимиты задаются сервером. Сайт не обещает
  фиксированные `3 дня`, если этот срок не включён в текущем tariff catalog.
- Цены, сроки подписки и платёжные обещания публикуются только при включённых
  production-продажах и после сверки с актуальным production API. Если продажи
  отключены, публичная страница не должна показывать исторические цены.
- Конструктор, 149/299 и «два устройства» не публикуются.
- Сайт содержит оферту, политику, реквизиты, возвраты и поддержку.
- Auto-renew выключен по умолчанию и описывается только после явного opt-in и
  отдельного production-разрешения.
- Main-domain routes не должны fallback-ить на landing вместо legal page.
- Маршрутизация main-domain legal устанавливается idempotent-скриптом
  `scripts/server/install_main_site_legal_proxy.sh`; dry-run обязателен перед
  `--apply`, а проверка ищет заголовок реального документа через loopback TLS.
- Семь файлов основной страницы, включая три точных продуктовых скриншота,
  устанавливаются guarded-скриптом `scripts/server/install_main_site_release.sh`.
  Архив не может содержать другие пути, symlink или downloads; при ошибке
  nginx/HTTPS восстанавливается root-only rollback-копия. Guard дополнительно
  отклоняет исторические цены и устаревшие формулировки.
- Сначала staging/preview, затем atomic switch production root.

## 11. Очистка серверов

Перед удалением собрать read-only inventory командой
`scripts/server/audit_server_runtime.py`. Скрипт выводит JSON без значений env,
ключей и пользовательских данных: unit/timer, listeners, ACL env/DB, SQLite
`quick_check`, размеры backup-каталогов, SSH hardening и pending updates.
ACL root-only runtime-файлов исправляются точечным скриптом
`scripts/server/repair_runtime_file_permissions.sh`; удаление старых одноразовых
credential-файлов требует отдельного флага `--remove-stale-onetime`.

Удаление разрешено только после verified checkpoint и проверки, что путь входит
в заранее указанный backup root. Сохраняются последний pre-change и последний
known-good archive. Исторические дубли удаляются oldest-first. VPS удаляется у
provider только после остановки billing и проверки отсутствия DNS/catalog/SSH
references.

Для исторического London recovery-каталога используется только
`scripts/server/prune_london_recovery_backups.sh`: сначала dry-run, затем
`--apply` после полного checkpoint. Скрипт сохраняет одну проверенную сжатую БД
и не принимает произвольный путь.

Для Timeweb/RUVDS control-серверов используется общий guarded-скрипт
`scripts/server/prune_control_server_artifacts.sh`. Он работает только на двух
точно заданных hostname, сохраняет текущие Android/Windows installers, один
rollback-комплект и два последних paid-site release. Все остальные типы файлов
или symlink приводят к отказу до удаления.

Подтверждённые failed units исправляются отдельно от общей очистки:

- `scripts/server/retire_nl1_legacy_api_tls.sh` выключает только устаревший Certbot/TLS vhost
  на NL1 после проверки, что `api.greenvpn.pro` уже указывает на control plane;
- `scripts/server/disable_unused_nl2_dnsmasq.sh` маскирует конфликтующий `dnsmasq`, только если
  WireGuard и все изолированные dnstt-службы активны.

Оба скрипта по умолчанию выполняют dry-run. Применение разрешено только после
полного checkpoint и заканчивается повторной проверкой зависимых служб.

Вывод VPS из эксплуатации разрешён только после доказательства нулевых
назначений, отсутствия DNS/catalog references и создания provider recovery
image. После удаления повторно проверяются provider inventory, billing и все
публичные поверхности. Исторический KZ-узел прошёл именно этот процесс; его
image указан в `CURRENT_HANDOFF.md`.

## 12. Мониторинг

### Независимая публичная проверка без секретов

- Скрипт: `scripts/monitoring/public_surface_probe.py`.
- GitHub Actions: `.github/workflows/public-surface-monitor.yml`, каждые 15 минут и вручную.
- Проверяются основной API, оба paid-beta API, основной и резервный paid-beta сайты, юридические страницы, APK/EXE и manifest загрузок.
- Probe не читает admin token и не отправляет данные в backend. HTTPS-проверка одновременно выявляет проблемы DNS, TLS, reverse proxy и публичной выдачи.
- При ошибке job завершается ненулевым кодом, а полный JSON-отчёт сохраняется на 14 дней как Actions artifact.
- Это внешний аварийный сигнал. Управляемый `service_probe.py` остаётся отдельным внутренним мониторингом сервисов и VPN endpoint-ов.

## 13. Финальная проверка

- Git clean, tests green, release gate green.
- Production и fallback health/API/catalog parity.
- Login email с обоих control planes.
- Stable Android и Windows physical connection.
- Site/legal/download SHA-256 live.
- YooKassa readiness соответствует фактам, а не историческим платежам.
- Monitoring идёт не только с проверяемого control-plane.
- Final checkpoint создан и его restore inventory проверен.
- На каждом сервере `system_time_offset <= 5s`; после clock repair нет будущих
  event timestamp.
