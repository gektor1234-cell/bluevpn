# Green VPN Android VLESS REALITY/XHTTP Preview

Дата: 2026-07-12.

## Область и изоляция

- Это внутренний transport preview, а не публичный релиз.
- Production, paid beta, основной сайт, загрузки, авторизация, биллинг и базы данных не менялись.
- Стабильный Android-клиент по умолчанию продолжает объявлять только `wireguard_udp`.
- Canary работает только на NL2 `5.129.216.42`: VLESS REALITY/XHTTP на TCP/443. Основной WireGuard остаётся на UDP/443.
- Preview имеет отдельный package id `pro.greenvpn.app.transportpreview`; флаг `GREENVPN_VLESS_REALITY_PREVIEW_ENABLED` по умолчанию выключен.

## Движок и лицензия

- Xray-core `v26.7.11`, commit `50231ea`, лицензия MPL-2.0.
- Android arm64-v8a binary SHA-256: `EA227CFB125FA093257F1A8227B5C6E30D93301D05F2E6AB8B79152F7AFF8CDB`.
- HEV SOCKS5 tunnel `2.14.4` используется только как TUN-to-SOCKS bridge.
- APK содержит MPL-2.0 notice и ссылку на соответствующий исходный код Xray-core.

## Android-контур

- `VpnService` создаёт full-tunnel TUN с MTU 1400; HEV передаёт трафик в loopback SOCKS Xray на `127.0.0.1:1981`.
- Runtime-конфигурация генерируется внутри private app storage, имеет owner-only permissions и удаляется при штатном отключении и аварийной очистке.
- Входной серверный профиль валидируется fail-closed: разрешены только точный NL2 IPv4, TCP/443, REALITY, allowlisted SNI и XHTTP; server private material запрещён.
- Android использует XHTTP `stream-up` и один переиспользуемый native HTTP/2 XMUX carrier. `mux.cool` не используется.
- DNS A/AAAA перехватывается Xray и отправляется в DoH `https://1.1.1.1/dns-query` через тот же VLESS outbound. Обычный DNS наружу не выпускается.
- UDP/443 блокируется внутри preview, чтобы QUIC-клиенты переходили на TCP. Private, link-local, multicast и зарезервированные сети блокируются.
- Foreground service следит за дочерним Xray-процессом. При его падении TUN, HEV, процесс и plaintext runtime-файлы удаляются fail-closed.
- Последний state хранится без секретов в `noBackupFilesDir`. Перед новым подключением старый аварийный status атомарно очищается, поэтому восстановление после watchdog корректно возвращается в `up`.

## Физическая проверка

Устройство: Samsung SM-A226B, Android 13; идентификатор устройства не сохраняется.

Основной отчёт:

- Путь: `C:\Users\gekto\GreenVPN_Checkpoints\android_vless_reality_preview_physical_20260712.json`.
- SHA-256: `C3A9C3B236D4FDF96143D9F707518DB13B06C1917A89E4A106F7FF5AEDB9836D`.
- NL2 egress: `5.129.216.42`, HTTP `200`.
- Production API, Timeweb paid-beta API и RUVDS paid-beta API: HTTP `200`.
- YouTube probe: HTTP `204`.
- Одновременно работал ровно один Xray-процесс; RX/TX были ненулевыми.
- Принудительное завершение Xray перевело state в `error`, удалило процесс и VPN service.
- Повторное подключение после fail-closed очистки вернулось в `up` и снова дало egress `5.129.216.42`.
- Финальное отключение вернуло `down`, удалило runtime и исходный plaintext profile.

Фоновый YouTube-отчёт:

- Путь: `C:\Users\gekto\GreenVPN_Checkpoints\android_vless_reality_background_youtube_20260712.json`.
- SHA-256: `D6BAC37B29626DDC204F26898F12879FC3044F3FEB0AA276E494190952AB34E5`.
- До и после Home/relaunch state оставался `up`, PID YouTube сохранился, egress остался `5.129.216.42`, оба YouTube probe вернули `204`.

После теста preview отключён. Официальный WireGuard `bluevpn-phone-3` восстановлен: owner `com.wireguard.android`, session `VALIDATED`, стабильный egress `5.129.237.163`; процессов Xray нет.

## Артефакт

- APK: `C:\BlueVPN_Builds\android_transport_preview_20260712_vless\GreenVPN_Android_VLESS_REALITY_Transport_Preview_0.2.45-preview2_debug.apk`.
- Размер: `147,691,009` bytes.
- SHA-256: `7C10F16B590A9DC9003E3050E5DD1C09BEB7EC39DD81DBF93EE4B0ED36D46DB4`.
- APK подписан debug-ключом и предназначен только для внутреннего физического preview.

## Rollback

1. На телефоне отключить preview и удалить только `pro.greenvpn.app.transportpreview`.
2. В официальном WireGuard снова включить `bluevpn-phone-3` и проверить `VALIDATED`.
3. Server canary удаляется guard-скриптом из Windows-документа; `wg0`, AWG2 и Hysteria2 не трогать.
4. Публичный каталог не содержит VLESS, поэтому отдельный клиентский rollback для stable не требуется.

## Осталось до публичного rollout

- Health-aware selector и ограниченный cooldown уже реализованы только для явно включённого preview. Перед public rollout нужны длительная telemetry-проверка и staged cohort; stable-флаги остаются выключенными.
- Naive HTTPS server canary уже доказан на NL2 TCP/8443. Клиентский engine, общий TCP/443 через безопасный SNI router и physical client smoke ещё не готовы.
- Release-сборка Android с production signing и staged cohort; до этого VLESS остаётся скрытым preview.
