# Green VPN: Android Hysteria2 preview

Дата фиксации: 2026-07-12.

## Статус

Android Hysteria2 доведён до изолированного физически проверенного preview.
Stable-приложение, production API/site, платежи, базы, public catalog и
действующие WireGuard-серверы не изменялись. Публичный rollout не разрешён.

## Изоляция

- Preview package: `pro.greenvpn.app.transportpreview`.
- Gradle подключает модуль только при
  `GREENVPN_ANDROID_HYSTERIA2_PREVIEW_ENABLED=true`.
- Dart/Kotlin capability включается отдельно через
  `GREENVPN_HYSTERIA2_PREVIEW_ENABLED=true`.
- Stable package остаётся `pro.greenvpn.app`; его проверочная сборка содержит
  флаг `false`, не содержит `pro.greenvpn.hysteria`, Hysteria/HEV/bridge `.so`,
  VPN-service или debug receiver.
- Debug receiver существует только в `src/debug`, экспортирован с системным
  permission `android.permission.DUMP` и не попадает в release manifest.

## Движок и лицензии

Hysteria `app/v2.9.3` работает только как loopback SOCKS5-клиент. Встроенный
Hysteria TUN не используется и не пакуется. Full-device TUN реализован HEV
Socks5 Tunnel `2.14.4` через внешний `tun_fd`.

Официальные Android SHA-256 внутри итогового APK:

| ABI | SHA-256 |
|---|---|
| `arm64-v8a` | `623B12826D13F8BB67F581396CF22C6639ABCBB6B1F22A42BF80350FFDAF50A3` |
| `armeabi-v7a` | `CD226A6EEBA011E809295082CA11C0B57560F070192372994E8DD968205595CC` |
| `x86_64` | `89D6C7CD9AAD1356196F8E7240A01368536091F1B1FA1E3EA5DE691F81B908D1` |

APK содержит по три ABI для HEV и JNI bridge, MIT/BSD notices и
`assets/transport_preview/SOURCE-MANIFEST.txt`. Источники HEV и все submodules
закреплены точными commit hash в `prepare_android_hysteria2_preview.ps1`.

## Безопасный runtime

1. YAML читается `SafeConstructor`; aliases запрещены, nesting ограничен.
2. Разрешён только IPv4-literal endpoint, обязательны auth, проверяемый TLS SNI,
   `insecure=false` и Salamander с паролем.
3. Base config не может задавать SOCKS/HTTP/TUN/forwarding listeners.
4. Клиент создаёт только `127.0.0.1:1980` и private Unix FD-control socket.
5. Unix socket имеет mode `0600`; QUIC descriptors передаются через
   `SCM_RIGHTS`, получают `FD_CLOEXEC` и вызывают `VpnService.protect()`.
6. TUN получает полные IPv4/IPv6 routes. Watchdog закрывает TUN, HEV, Hysteria,
   FD-control и runtime-файлы при падении любого engine.
7. Base profile удаляется сразу после render; runtime YAML удаляется при любом
   disconnect/error. Секреты не пишутся в отчёт.

## Физический тест

Устройство: Samsung SM-A226B, serial `R9WT10CDC2J`.

Отчёт:
`C:\Users\gekto\GreenVPN_Checkpoints\android_hysteria2_preview_physical_20260712.json`.

Результат:

- `versionCode=2026070515`;
- внешний IP `5.129.216.42`;
- ipify, production API, Timeweb paid-beta API, RUVDS paid-beta API и YouTube:
  HTTP `200`;
- `rxBytes=10829`, `txBytes=4191`, один exact Hysteria child;
- после forced kill: `state=error`, process count `0`, service count `0`;
- после явного disconnect: `state=down`, process count `0`, service count `0`;
- plaintext debug/base/runtime config удалён;
- итог `success=true`.

SHA-256 отчёта:
`D19CCA1CEEC45FF7D68F417FA05718DAFB9E0732FA1580DC85CD0ADA879F2800`.

## Артефакт

`C:\BlueVPN_Builds\GreenVPN_Android_0.2.44_awg2_hysteria2_transport_preview5_build2026070515_debug.apk`

- size: `117,990,976` bytes;
- SHA-256: `6D84E4F89296DE095133025BE3E4333F232DDC53A022FABD625F5A7E8F98D84E`;
- package: `pro.greenvpn.app.transportpreview`;
- signature scheme v2: verified;
- zip alignment: verified.

Проверка артефакта:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File `
  .\scripts\windows\verify_android_hysteria2_preview_apk.ps1 `
  -ApkPath 'C:\BlueVPN_Builds\GreenVPN_Android_0.2.44_awg2_hysteria2_transport_preview5_build2026070515_debug.apk' `
  -ExpectedVersionCode 2026070515
```

## Stable isolation

Отдельная сборка без preview-флагов прошла
`verify_android_stable_transport_isolation.ps1`:

- package `pro.greenvpn.app`;
- `GREENVPN_HYSTERIA2_PREVIEW_ENABLED=false`;
- Hysteria engine class/service/native entries: `0`;
- проверочная SHA-256: `DBC492C88F6318E938A3F12C889B76BAE4F96811B8132AC1CA250547B4F7698B`.

Эта проверочная debug-сборка не является новым stable release artifact; она
служит только доказательством compile-time изоляции.

## Rollback

Клиентский rollback не затрагивает stable:

1. Выполнить preview disconnect или удалить отдельный package
   `pro.greenvpn.app.transportpreview`.
2. Убедиться, что Hysteria process, `Hysteria2VpnService`, local SOCKS listener
   и runtime YAML отсутствуют.
3. Не менять production package `pro.greenvpn.app`.
4. Не публиковать capability `hysteria2` stable-клиентам и оставить stage
   `canary`.

Серверный rollback выполняется отдельным Hysteria2 canary runbook и не трогает
`wg0`, `awgcanary0`, control-plane или public catalog.
