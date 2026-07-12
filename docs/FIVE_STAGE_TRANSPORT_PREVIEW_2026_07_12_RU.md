# Пятиступенчатый transport preview Green VPN

Дата фиксации: 2026-07-12.

## Граница изменений

- Контур работает только в `paid-beta-api` и отдельном package `pro.greenvpn.app.transportpreview`.
- Production API, основной сайт, публичные загрузки и stable WireGuard не изменены.
- Production backend остаётся `0.9.105`.
- Все preview-флаги в stable выключены; stable APK не содержит движки, сервисы или native payload preview-транспортов.

## Цепочка выбора

1. AmneziaWG2.
2. Hysteria2.
3. VLESS REALITY/XHTTP через TCP/443.
4. Naive HTTPS.
5. dnstt через публичный DoH.

Клиент сравнивает только доступные и готовые preview-кандидаты. После ошибки маршрут получает локальный cooldown `1/3/10/30` минут и временно опускается ниже следующего готового кандидата. Порядок внутри одинакового состояния остаётся строгим. Proxy-транспорты разрешены только в full-tunnel режиме.

Server-side автоматизация работает fail-closed: обычный control-plane health не может повысить или опубликовать транспорт. Для автоматического route observation нужны `automationEligible=true`, подтверждённый egress и сигнал реального tunnel/proxy data plane.

## Серверы

Canary data plane: NL2 `5.129.216.42`.

- AWG2: `awgcanary0`, UDP/1443.
- Hysteria2: `greenvpn-hysteria2-canary`, UDP/2443.
- VLESS REALITY/XHTTP: Xray canary, TCP/443.
- Naive HTTPS: isolated Caddy/forwardproxy canary, TCP/8443.
- dnstt: `greenvpn-dnstt-canary.service`, UDP/53; authenticated local SOCKS `127.0.0.1:1083`.

Paid-beta control plane на Timeweb и RUVDS:

```text
release=paid-beta-0.3.0-paid-beta.6-2026071201-r19-preview-probe-contract
backend=0.9.113-transport-preview.7
production=0.9.105
```

Обе базы проходят SQLite `quick_check`, содержат одинаковые пять preview-строк, а профили Naive и dnstt находятся в root-only файлах `0600`. Временные staging-каталоги после деплоя удалены; rollback backups сохранены:

```text
Timeweb: /root/greenvpn-preview-probe-contract-prechange/20260712T145339Z-timeweb
RUVDS:  /root/greenvpn-preview-probe-contract-prechange/20260712T145423Z-ruvds
```

## Android

```text
apk=C:\BlueVPN_Builds\android_transport_preview_20260712_cascade_r19\GreenVPN_Android_five_stage_preview_0.2.45_2026071204.apk
package=pro.greenvpn.app.transportpreview
versionCode=2026071204
size=140139681
sha256=984CBEF0EB4C0A88A4D982AC63C1A1DFB3F597CF785F51D639E6DEE05C1FEFD1
```

APK прошёл pinned dnstt binary/license, manifest, DEX, BuildConfig, zipalign и APK signature checks. На Samsung SM-A226B сохранена существующая сессия.

Debug-only `TransportContractDebugService` защищён `android.permission.DUMP` и отсутствует в main manifest. Он расшифровывает сессию только внутри Android Keystore-процесса приложения, запрашивает пять конфигов через primary и fallback и сохраняет только безопасные метаданные. Результат:

```text
checks=10/10
http=200
primary=5/5
fallback=5/5
report=C:\Users\gekto\GreenVPN_Checkpoints\android_transport_contract_probe_20260712.json
report_sha256=7540393123545F4CF0F09F567BD7EAF4EB13ADEA3C6031A96B020EE47FA80316
```

Токены, device ID и конфиги в отчёт не выводятся. Временный `dnstt-client-android-arm64` из `/data/local/tmp` удалён.

Отдельный readiness smoke на NL2 прошёл реальный dnstt data plane напрямую к UDP/53, подтвердил egress `5.129.216.42`, YouTube и активность stable-транспортов. Итог: `server_data_plane_ready=true`, `doh_delegation_ready=false`, `secrets_printed=false`. Второй флаг станет положительным только после публичной DNS-делегации.

## Quick Settings cascade

Native Quick Settings использует тот же `paid-beta` marker/channel и динамический серверный каталог, что основной Flutter-экран. Stable при выключенных preview-флагах сохраняет прежний одноконфиговый путь.

Физический reversible-тест временно добавил tile через ADB, сохранил исходный список панели и затем восстановил его. Доказано:

- без cooldown первым принят `amneziawg`;
- после cooldown AWG2 принят `hysteria2`;
- success marker пишется только после YouTube data-plane probe;
- после теста все пять preview engines находятся в `down`, cooldown очищен.

```text
report=C:\Users\gekto\GreenVPN_Checkpoints\android_quick_tile_cascade_physical_20260712.json
report_sha256=CBED2FD33B0F20C37FBD67C8BB6546BD2F5B5494953D8878E537C134A1030B8A
```

## Проверки

- Flutter tests: `11/11`.
- Transport backend tests: `28/28`.
- Paid-beta backend tests: `33/33`.
- Native Quick Settings cascade tests: `3/3`.
- Android config contract: `10/10` на физическом телефоне.
- Release gate: `0 warnings`, `0 errors`.
- Stable APK isolation: исходный production SHA-256 `308320429991A3278E3BA903155482D6613425D46681F180338ECB8C0929248F`, preview payload отсутствует.
- Analyzer: прежний baseline `184` lint/info, новых blocking errors нет.

## Незавершённый физический gate dnstt

В REG.RU ещё не сохранены две записи:

```text
A   tns.greenvpn.pro -> 5.129.216.42
NS  t.greenvpn.pro   -> tns.greenvpn.pro
```

После сохранения и propagation нужно:

1. Запустить server readiness с `--require-delegation`.
2. Разблокировать телефон.
3. Запустить `test_android_dnstt_preview_physical.ps1`.
4. Подтвердить NL2 egress, production и оба paid-beta API, YouTube, watchdog fail-closed cleanup, reconnect и удаление plaintext profile.

До этого dnstt остаётся последним preview-only кандидатом и не считается полностью физически доказанным. Публикация в stable запрещена.
