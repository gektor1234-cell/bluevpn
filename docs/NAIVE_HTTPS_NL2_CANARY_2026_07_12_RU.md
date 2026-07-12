# Green VPN Naive HTTPS NL2 Canary

Дата: 2026-07-12.

## Решение

Последняя HTTPS-подобная линия строится на NaiveProxy, а не на reference AnyTLS:

- NaiveProxy использует Chromium network stack, HTTP/2 CONNECT, padding и стандартный TLS fingerprint; клиент имеет лицензию BSD-3-Clause.
- Caddy имеет лицензию Apache-2.0; закреплённый `klzgrad/forwardproxy` также Apache-2.0.
- Reference `anytls-go` на момент аудита не содержит явного LICENSE и сам называет example client/server неполным reference implementation.
- Готовый AnyTLS через sing-box возможен, но sing-box распространяется под GPL-3.0-or-later. Он остаётся исследовательским вариантом, а не зависимостью коммерческого Green VPN клиента.

Первичные источники:

- `https://github.com/klzgrad/naiveproxy`
- `https://github.com/caddyserver/caddy`
- `https://github.com/klzgrad/forwardproxy/tree/d62c80d3dd2c706b6b87579844d2397bddd18317`
- `https://github.com/anytls/anytls-go`
- `https://github.com/SagerNet/sing-box`

## Изоляция

- Host: NL2 `5.129.216.42`.
- Domain: `nl2.vpn.greenvpn.pro`, trusted Let's Encrypt full chain.
- Service: `greenvpn-naive-https-canary.service`.
- Listener: только TCP/8443. UDP/8443 отсутствует.
- TCP/443 VLESS REALITY, UDP/443 WireGuard, UDP/1443 AWG2 и UDP/2443 Hysteria2 не менялись.
- Canary не добавлен в production или paid-beta catalog и не выдаётся ни одному клиенту.
- Незнакомый HTTPS-запрос получает обычный HTTP `404` с успешной TLS verification, а не признак proxy endpoint.

## Закреплённые компоненты

- Go `1.26.5`, archive SHA-256 `5C2C3B16CAEFA1D968A94C1DACA04A7CA301A496D9B086E17AD77BB81393F053`.
- Caddy `v2.11.4`.
- xcaddy `v0.4.5`.
- forwardproxy exact commit `d62c80d3dd2c706b6b87579844d2397bddd18317`.
- NaiveProxy `v150.0.7871.63-1`.
- Naive Linux archive SHA-256 `0C4F506CE66A7881892FD6932B542C53FC06AC2351987756096C61E753C687BF`.
- Built Caddy SHA-256 `FE70C730D8BED0A9570CE9ADF62B94958E676E196B40EA7108C5E93EC7003498`.
- Installed Naive binary SHA-256 `BAEA1E9B9F8DD879A6374110BD7BDCA80C2ECBDCA8DEBC4F84F784A8739EAEA7`.
- Windows archive SHA-256 `D09E35F9FDE6206A775A1B930D7D8252053BEE1408EE1C910B5681346C68D1A1`.
- Android arm64 plugin APK SHA-256 `733FBBBEBB383A91F42036992C21CFD19B99E089AC3D15D7C077DF79FC471A89`.
- Извлечённый Android `libnaive.so` SHA-256 `55B64ADBDA9FC09F4137800D74AC6772B797F96E224C12F69A8E001886BB82EB`.

## Защита

- Учётные данные создаются отдельно, хранятся root/group-only и никогда не печатаются readiness/bootstrap.
- Client profile root-owned mode `0600`; Caddy config mode `0640` доступен только dedicated user `greenvpn-naive`.
- Caddy работает не от root с systemd hardening, отдельным state directory, отключённым admin endpoint и без HTTP/3.
- Сертификат копируется из существующего ACME fullchain в отдельный canary material directory; права Hysteria не ослабляются.
- Bootstrap разрешён только при exact public IP и двойном NL2 approval argument.

## Проверка

`scripts/server/check_naive_https_canary_readiness.sh` подтвердил:

- service active и TCP/8443 listener;
- отсутствие UDP/8443;
- Caddy/forwardproxy/Naive build metadata;
- корректные owner/mode и отсутствие symlink config;
- внешний TLS status `404`, verify result `0`;
- реальный SOCKS data-plane egress `5.129.216.42`;
- активность WireGuard, AWG2, Hysteria2 и VLESS.

## Android preview

- Отдельный package `pro.greenvpn.app.transportpreview`; `GREENVPN_NAIVE_HTTPS_PREVIEW_ENABLED` по умолчанию выключен.
- Строгий validator принимает только loopback SOCKS `127.0.0.1:1982`, HTTPS, точный `nl2.vpn.greenvpn.pro:8443` и обязательные credentials; logging/netlog поля запрещены.
- HEV `mapdns` на `198.18.2.2` передаёт доменные имена через SOCKS CONNECT без UDP DNS. Обычный stable-клиент модуль и бинарник не включает.
- Full physical report: `C:\Users\gekto\GreenVPN_Checkpoints\android_naive_https_preview_physical_20260712.json`, SHA-256 `E2217CE98D011CEBC0729E45B578DACEC88B66D8EA4213613D9E02931BDB5521`.
- NL2 egress, production и оба paid-beta API вернули `200`; YouTube вернул `204`; один точный Naive process имел ненулевые RX/TX.
- Engine-kill дал fail-closed `error` без процесса/VPN service; reconnect вернулся в `up`; финальная очистка удалила runtime и plaintext profile.
- Background/Home/YouTube/relaunch report: `C:\Users\gekto\GreenVPN_Checkpoints\android_naive_https_background_youtube_20260712.json`, SHA-256 `AD3C408D595A2F04EADBCF8905A116364A30D3E0C3EA87432836F2F3AA253666`.
- Preview APK: `C:\BlueVPN_Builds\android_transport_preview_20260712_naive\GreenVPN_Android_Naive_HTTPS_Transport_Preview_0.2.45_debug.apk`, size `147,688,691`, SHA-256 `DB2439502B81A471C4D53E53C36689DD6726D5599207912EBCD8B1BA870A630E`.
- После тестов официальный `bluevpn-phone-3` восстановлен: owner `com.wireguard.android`, session `VALIDATED`.

## Windows preview

- Official NaiveProxy `v150.0.7871.63-1` is packaged only in the isolated transport-preview build.
- The client listens only on `127.0.0.1:1982`; the guarded endpoint is exactly `nl2.vpn.greenvpn.pro:8443`.
- HEV uses the dedicated `GreenVPNNaivePreview` adapter, `mapdns`, and route metric `42734`.
- Runtime profiles and PID files use restricted ACLs and are removed by disconnect and watchdog cleanup.
- Windows ZIP `0.3.0-preview3` compiled successfully and passed the release gate with packaged SHA-256 validation: `C:\BlueVPN_Builds\windows_transport_preview_20260712_naive\GreenVPN_Windows_Transport_Preview_0.3.0-preview3.zip`, SHA-256 `960D90856B7438A024B8C48378D2EB21D206B4A1AC7771215F8F319EFDF55E3D`.
- Non-disruptive SOCKS smoke passed with egress `5.129.216.42` and YouTube status `204`; route signature and WARP service state remained unchanged. Report: `C:\Users\gekto\GreenVPN_Checkpoints\windows_naive_https_client_smoke_20260712.json`, SHA-256 `98589B9DCE970BE9C1C40B43F231FC4EDD5B0431D969DE72954ACE796309FAAE`.
- Full Windows TUN smoke is deliberately deferred while changing WARP is forbidden by the owner.

## Rollback

Dry-run:

```bash
/tmp/remove_naive_https_canary.sh
```

Apply допускается только на точном NL2:

```bash
/tmp/remove_naive_https_canary.sh \
  --expected-public-ip 5.129.216.42 \
  --approved-existing-host 5.129.216.42 \
  --apply
```

Rollback сохраняет root-only backup, удаляет только service/config/client profile/install root Naive и проверяет активность четырёх прежних транспортов.

## Осталось до клиентского rollout

- Собрать и проверить отдельный Windows preview engine поверх существующего HEV bridge; Windows WARP нельзя переключать без отдельного разрешения владельца.
- Для реальной последней линии перевести Naive с 8443 на общий TCP/443 через проверенный SNI router; VLESS нельзя переносить до отдельного rollback/proof.
- Только после этого добавлять `naive_https` capability и endpoint в изолированный control plane.
